//
//  SGAIInterstitialAdapter.swift
//  VideoStreamTracker
//
//  Watches AVPlayer's HLS interstitials (the SGAI ad breaks signalled with
//  `#EXT-X-DATERANGE` + `X-ASSET-LIST` / `X-ASSET-URI`) and tells
//  `SGAIAdEventTracker` what happens (issue #20).
//
//  What AVPlayer reports, measured on a local SGAI stream (2026-11-18):
//   - the break appears in `AVPlayerInterstitialEventMonitor.events` as soon as
//     the playlist loads, with the DATERANGE ID as `identifier`;
//   - AVPlayer loads the asset list and the first ad seconds BEFORE the break,
//     so the interstitial player's `currentItem` changing is not "ad started";
//   - the break starts when `currentEvent` becomes that event, and an ad starts
//     when the interstitial player plays an item while a break is current;
//   - each ad ends with `AVPlayerItemDidPlayToEndTime` on its item;
//   - a viewer pause shows as the interstitial player going to `.paused`;
//   - the break ends when `currentEvent` becomes nil.
//
//  Tracking URLs come from the asset list: `AVPlayerInterstitialEvent.assetListResponse`
//  on iOS / tvOS 18.4 and later (AVPlayer already fetched it), otherwise we fetch
//  the `X-ASSET-LIST` URL ourselves, found through the date-range metadata.
//

import AVFoundation
import Foundation

/// Lets the logger hold the adapter without an availability check.
internal protocol SGAIAdTracking: AnyObject {
    func invalidate()
}

/// All state is read and written on the main thread (observers are delivered on, or
/// dispatched to, the main queue), hence `@unchecked Sendable`.
@available(iOS 15.0, tvOS 15.0, *)
internal final class SGAIInterstitialAdapter: NSObject, SGAIAdTracking, AVPlayerItemMetadataCollectorPushDelegate, @unchecked Sendable {

    private let player: AVPlayer
    private let monitor: AVPlayerInterstitialEventMonitor
    private let store: SGAIAdTrackingUrlsExtractor
    private let tracker: SGAIAdEventTracker
    private let fetcher: SGAIAssetListFetching

    private let collector = AVPlayerItemMetadataCollector()
    private weak var collectedItem: AVPlayerItem?
    /// `X-ASSET-LIST` / `X-ASSET-URI` values by the date range's start date.
    private var assetListUrlByStartDate: [Date: String] = [:]
    private var loadedBreaks: Set<String> = []
    private var loadingBreaks: Set<String> = []

    private var activeBreakId: String?
    /// Last progress reported for the current ad, to catch an ad whose end
    /// notification arrives after the next ad has started.
    private var lastAdFraction = 0.0
    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var isInvalidated = false

    /// How close to its end a pause still counts as the ad finishing, not the viewer pausing.
    private static let endOfAdTolerance = 0.3

    internal init(player: AVPlayer,
                  store: SGAIAdTrackingUrlsExtractor,
                  tracker: SGAIAdEventTracker,
                  fetcher: SGAIAssetListFetching = SGAIURLSessionFetcher()) {
        self.player = player
        self.monitor = AVPlayerInterstitialEventMonitor(primaryPlayer: player)
        self.store = store
        self.tracker = tracker
        self.fetcher = fetcher
        super.init()
        collector.setDelegate(self, queue: .main)
        attachCollector(to: player.currentItem)
        startObserving()
        loadTrackingUrlsForKnownBreaks()
        handleCurrentEventChange()
    }

    deinit {
        invalidate()
    }

    internal func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
        if let timeObserver {
            monitor.interstitialPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        collectedItem?.remove(collector)
    }

    // MARK: - Observing

    private func startObserving() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVPlayerInterstitialEventMonitor.eventsDidChangeNotification,
            object: monitor, queue: .main) { [weak self] _ in
                self?.loadTrackingUrlsForKnownBreaks()
            })
        notificationTokens.append(center.addObserver(
            forName: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification,
            object: monitor, queue: .main) { [weak self] _ in
                self?.handleCurrentEventChange()
            })
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
                self?.handleItemDidPlayToEnd(notification.object as? AVPlayerItem)
            })

        let interstitialPlayer = monitor.interstitialPlayer
        observations.append(interstitialPlayer.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.startAdIfPlaying() }
        })
        observations.append(interstitialPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.handleInterstitialStatusChange() }
        })
        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            let item = player.currentItem
            DispatchQueue.main.async { self?.attachCollector(to: item) }
        })
        timeObserver = interstitialPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
                self?.reportProgress()
            }
    }

    private func attachCollector(to item: AVPlayerItem?) {
        guard collectedItem !== item else { return }
        collectedItem?.remove(collector)
        collectedItem = item
        item?.add(collector)
    }

    // MARK: - Break and ad transitions

    private func handleCurrentEventChange() {
        let id = monitor.currentEvent?.identifier
        guard id != activeBreakId else { return }
        if activeBreakId != nil {
            if lastAdFraction >= 0.9 { tracker.adCompleted() }
            tracker.breakEnded()
        }
        activeBreakId = id
        lastAdFraction = 0
        guard let event = monitor.currentEvent, let id else { return }
        loadTrackingUrls(for: event)
        tracker.breakStarted(id: id)
        startAdIfPlaying()
    }

    /// An ad starts when the interstitial player plays an item while a break is current.
    private func startAdIfPlaying() {
        guard activeBreakId != nil,
              let event = monitor.currentEvent,
              monitor.interstitialPlayer.timeControlStatus == .playing,
              let item = monitor.interstitialPlayer.currentItem else { return }
        let url = Self.url(of: item)
        let index = event.templateItems.firstIndex { url != nil && Self.url(of: $0) == url }
            ?? (tracker.adIndex.map { $0 + 1 } ?? 0)
        guard index != tracker.adIndex else { return }
        if tracker.adIndex != nil, lastAdFraction >= 0.9 { tracker.adCompleted() }
        lastAdFraction = 0
        tracker.adStarted(index: index)
    }

    private func handleInterstitialStatusChange() {
        guard activeBreakId != nil else { return }
        let interstitialPlayer = monitor.interstitialPlayer
        switch interstitialPlayer.timeControlStatus {
        case .playing:
            startAdIfPlaying()
            tracker.adResumed()
        case .paused:
            if let item = interstitialPlayer.currentItem, Self.isAtEnd(item) { return }
            tracker.adPaused()
        default:
            break
        }
    }

    private func handleItemDidPlayToEnd(_ item: AVPlayerItem?) {
        guard activeBreakId != nil, let item, let event = monitor.currentEvent else { return }
        let url = Self.url(of: item)
        let index = event.templateItems.firstIndex { $0 === item || (url != nil && Self.url(of: $0) == url) }
        guard index != nil || item === monitor.interstitialPlayer.currentItem else { return }
        tracker.adCompleted(index: index)
    }

    private func reportProgress() {
        guard activeBreakId != nil, let item = monitor.interstitialPlayer.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        lastAdFraction = item.currentTime().seconds / duration
        tracker.adProgress(fraction: lastAdFraction)
    }

    // MARK: - Tracking URLs

    private func loadTrackingUrlsForKnownBreaks() {
        for event in monitor.events { loadTrackingUrls(for: event) }
    }

    private func loadTrackingUrls(for event: AVPlayerInterstitialEvent) {
        let breakId = event.identifier
        guard !breakId.isEmpty, !loadedBreaks.contains(breakId), !loadingBreaks.contains(breakId) else { return }

        if #available(iOS 18.4, tvOS 18.4, *),
           let response = event.assetListResponse,
           JSONSerialization.isValidJSONObject(response),
           let data = try? JSONSerialization.data(withJSONObject: response) {
            store(assetListData: data, breakId: breakId)
            return
        }

        guard let date = event.date,
              let assetListUrl = assetListUrlByStartDate.first(where: { abs($0.key.timeIntervalSince(date)) < 0.001 })?.value,
              let url = URL(string: assetListUrl) else { return }
        loadingBreaks.insert(breakId)
        let fetcher = self.fetcher
        Task { [self] in
            let data = try? await fetcher.fetch(url: url)
            DispatchQueue.main.async { self.finishLoading(data, breakId: breakId) }
        }
    }

    private func finishLoading(_ data: Data?, breakId: String) {
        loadingBreaks.remove(breakId)
        guard !isInvalidated, let data else { return }
        store(assetListData: data, breakId: breakId)
    }

    private func store(assetListData data: Data, breakId: String) {
        guard (try? store.parse(assetListData: data, adBreakId: breakId, adsId: breakId)) != nil else { return }
        loadedBreaks.insert(breakId)
        tracker.trackingUrlsDidLoad(breakId: breakId)
    }

    // MARK: - AVPlayerItemMetadataCollectorPushDelegate

    func metadataCollector(_ metadataCollector: AVPlayerItemMetadataCollector,
                           didCollect metadataGroups: [AVDateRangeMetadataGroup],
                           indexesOfNewGroups: IndexSet,
                           indexesOfModifiedGroups: IndexSet) {
        for group in metadataGroups {
            for item in group.items {
                guard let key = item.key as? String,
                      key == "X-ASSET-LIST" || key == "X-ASSET-URI",
                      let value = item.stringValue else { continue }
                assetListUrlByStartDate[group.startDate] = value
            }
        }
        loadTrackingUrlsForKnownBreaks()
    }

    // MARK: - Helpers

    private static func url(of item: AVPlayerItem) -> URL? {
        (item.asset as? AVURLAsset)?.url
    }

    private static func isAtEnd(_ item: AVPlayerItem) -> Bool {
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return false }
        return item.currentTime().seconds >= duration - endOfAdTolerance
    }
}
