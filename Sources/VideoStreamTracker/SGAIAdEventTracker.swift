//
//  SGAIAdEventTracker.swift
//  VideoStreamTracker
//
//  Decides which SGAI ad tracking events to fire, and fires their tracking URLs
//  (issue #20). It knows nothing about AVPlayer: `SGAIInterstitialAdapter` feeds
//  it what happens (break started, ad started, progress, pause, resume, ad
//  completed, break ended), so the rules can be unit tested without playback.
//
//  Mirrors the Android SDK (VideoAnalyticsTracker / SGAIAdImpressionSender):
//   - podStart when an ad break starts, podEnd when it ends;
//   - impression and start when an ad starts;
//   - firstQuartile, midpoint, thirdQuartile at 25 %, 50 % and 75 % of the ad;
//   - complete when the ad plays to its end;
//   - pause and resume while an ad plays (these may fire more than once).
//  Every other event fires at most once per ad each time its break plays.
//
//  Keys: `pod_<breakId>` for the break and `<breakId>_0_<index>` for its ads,
//  the same shape as the Android SDK's `<adsId>_0_<index>` with the break's
//  `EXT-X-DATERANGE` ID as the ads ID.
//

import Foundation

/// Sends one tracking request. Injected so tests can record instead of calling out.
internal protocol SGAITrackingPinging {
    func ping(_ url: URL, event: SGAIAdTrackingEvent, adKey: String)
}

/// Default sender: a GET per URL, fire and forget, like the Android SDK.
internal struct SGAIURLSessionPinger: SGAITrackingPinging {
    private let session: URLSession

    internal init(session: URLSession = .shared) {
        self.session = session
    }

    internal func ping(_ url: URL, event: SGAIAdTrackingEvent, adKey: String) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue(adKey, forHTTPHeaderField: "X-Ad-Key")
        session.dataTask(with: request).resume()
    }
}

/// The SGAI ad event rules. Not thread-safe: call it from the main thread.
internal final class SGAIAdEventTracker {

    /// Looks up the tracking URLs for an ad key, keyed by event name.
    internal typealias URLLookup = (String) -> [String: [String]]?

    private let lookup: URLLookup
    private let pinger: SGAITrackingPinging

    /// The ID of the ad break that is playing, if any.
    private(set) internal var breakId: String?
    /// The index of the ad that is playing within the break, if any.
    private(set) internal var adIndex: Int?

    private var adHasCompleted = false
    private var isPaused = false
    private var lastQuartile = 0

    /// Events already fired per key (fire-once events only).
    private var fired: [String: Set<String>] = [:]
    /// Fire-once events that had no URLs yet, retried when URLs load.
    private var pending: [(key: String, event: SGAIAdTrackingEvent)] = []

    internal init(lookup: @escaping URLLookup, pinger: SGAITrackingPinging) {
        self.lookup = lookup
        self.pinger = pinger
    }

    internal static func podKey(breakId: String) -> String { "pod_\(breakId)" }
    internal static func adKey(breakId: String, index: Int) -> String { "\(breakId)_0_\(index)" }

    private var currentAdKey: String? {
        guard let breakId, let adIndex else { return nil }
        return Self.adKey(breakId: breakId, index: adIndex)
    }

    // MARK: - What happened

    internal func breakStarted(id: String) {
        guard breakId != id else { return }
        if breakId != nil { breakEnded() }
        breakId = id
        resetAdState()
        adIndex = nil
        // A break that plays again (e.g. seeking back in VOD) is tracked again.
        let prefix = "\(id)_0_"
        let podKey = Self.podKey(breakId: id)
        fired = fired.filter { key, _ in key != podKey && !key.hasPrefix(prefix) }
        fire(.podStart, key: podKey)
    }

    internal func adStarted(index: Int) {
        guard let breakId, adIndex != index else { return }
        adIndex = index
        resetAdState()
        let key = Self.adKey(breakId: breakId, index: index)
        fire(.impression, key: key)
        fire(.start, key: key)
    }

    /// Progress through the current ad, 0...1.
    internal func adProgress(fraction: Double) {
        guard let key = currentAdKey, !adHasCompleted, fraction.isFinite else { return }
        let quartile = fraction >= 0.75 ? 3 : fraction >= 0.5 ? 2 : fraction >= 0.25 ? 1 : 0
        while lastQuartile < quartile {
            lastQuartile += 1
            let event: SGAIAdTrackingEvent = lastQuartile == 1 ? .firstQuartile : lastQuartile == 2 ? .midpoint : .thirdQuartile
            fire(event, key: key)
        }
    }

    internal func adPaused() {
        guard let key = currentAdKey, !adHasCompleted, !isPaused else { return }
        isPaused = true
        fire(.pause, key: key, once: false)
    }

    internal func adResumed() {
        guard let key = currentAdKey, isPaused else { return }
        isPaused = false
        fire(.resume, key: key, once: false)
    }

    /// The ad played to its end. Quartiles not yet reached (e.g. a short ad between
    /// progress ticks) are fired first, so a completed ad always reports all four.
    /// - Parameter index: The ad that ended, if known; an end reported for another ad
    ///   (e.g. arriving after the next ad already started) is ignored.
    internal func adCompleted(index: Int? = nil) {
        guard let key = currentAdKey, !adHasCompleted else { return }
        if let index, index != adIndex { return }
        adProgress(fraction: 1)
        adHasCompleted = true
        isPaused = false
        fire(.complete, key: key)
    }

    internal func breakEnded() {
        guard let id = breakId else { return }
        fire(.podEnd, key: Self.podKey(breakId: id))
        let prefix = "\(id)_0_"
        let podKey = Self.podKey(breakId: id)
        pending.removeAll { $0.key == podKey || $0.key.hasPrefix(prefix) }
        breakId = nil
        adIndex = nil
        resetAdState()
    }

    /// Tracking URLs for a break arrived (e.g. its asset list loaded after the break
    /// started): fire the events that were waiting for them.
    internal func trackingUrlsDidLoad(breakId id: String) {
        guard breakId == id, !pending.isEmpty else { return }
        let waiting = pending
        pending.removeAll()
        for item in waiting { fire(item.event, key: item.key) }
    }

    // MARK: - Firing

    private func resetAdState() {
        adHasCompleted = false
        isPaused = false
        lastQuartile = 0
    }

    private func fire(_ event: SGAIAdTrackingEvent, key: String, once: Bool = true) {
        if once, fired[key]?.contains(event.eventName) == true { return }
        let urls = (lookup(key)?[event.eventName] ?? []).compactMap(URL.init(string:))
        guard !urls.isEmpty else {
            if once, !pending.contains(where: { $0.key == key && $0.event == event }) {
                pending.append((key, event))
            }
            return
        }
        if once { fired[key, default: []].insert(event.eventName) }
        for url in urls { pinger.ping(url, event: event, adKey: key) }
    }
}
