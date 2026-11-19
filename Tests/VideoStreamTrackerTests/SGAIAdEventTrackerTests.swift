//
//  SGAIAdEventTrackerTests.swift
//  VideoStreamTrackerTests
//
//  The SGAI ad event rules (issue #20), without AVPlayer.
//

import AVFoundation
import XCTest
@testable import VideoStreamTracker

/// Records pings instead of sending them. Thread-safe so the end-to-end test can read it.
final class RecordingPinger: SGAITrackingPinging, @unchecked Sendable {
    private let lock = NSLock()
    private var _pings: [(event: String, adKey: String, url: String)] = []
    private let forward: SGAITrackingPinging?

    init(forwardTo forward: SGAITrackingPinging? = nil) { self.forward = forward }

    var pings: [(event: String, adKey: String, url: String)] {
        lock.lock(); defer { lock.unlock() }
        return _pings
    }

    /// "adKey:event" in firing order.
    var trace: [String] { pings.map { "\($0.adKey):\($0.event)" } }

    func ping(_ url: URL, event: SGAIAdTrackingEvent, adKey: String) {
        lock.lock()
        _pings.append((event.eventName, adKey, url.absoluteString))
        lock.unlock()
        forward?.ping(url, event: event, adKey: adKey)
    }
}

final class SGAIAdEventTrackerTests: XCTestCase {

    private let allAdEvents = ["impression", "start", "firstQuartile", "midpoint", "thirdQuartile", "complete", "pause", "resume"]
    private var urls: [String: [String: [String]]] = [:]
    private var pinger = RecordingPinger()
    private var tracker: SGAIAdEventTracker!

    override func setUp() {
        super.setUp()
        urls = [:]
        addUrls(breakId: "b1", ads: 2)
        pinger = RecordingPinger()
        tracker = SGAIAdEventTracker(lookup: { [unowned self] key in self.urls[key] }, pinger: pinger)
    }

    private func addUrls(breakId: String, ads: Int) {
        urls["pod_\(breakId)"] = ["podStart": ["https://t.example/\(breakId)/podStart"],
                                 "podEnd": ["https://t.example/\(breakId)/podEnd"]]
        for i in 0..<ads {
            var map: [String: [String]] = [:]
            for e in allAdEvents { map[e] = ["https://t.example/\(breakId)/\(i)/\(e)"] }
            urls["\(breakId)_0_\(i)"] = map
        }
    }

    func testKeysMatchTheAndroidShapeWithTheBreakIdAsAdsId() {
        XCTAssertEqual(SGAIAdEventTracker.podKey(breakId: "b1"), "pod_b1")
        XCTAssertEqual(SGAIAdEventTracker.adKey(breakId: "b1", index: 2), "b1_0_2")
    }

    func testFullBreakFiresEveryEventInOrder() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        for f in stride(from: 0.0, through: 1.0, by: 0.1) { tracker.adProgress(fraction: f) }
        tracker.adCompleted(index: 0)
        tracker.adStarted(index: 1)
        tracker.adProgress(fraction: 0.3)
        tracker.adPaused()
        tracker.adResumed()
        tracker.adProgress(fraction: 0.8)
        tracker.adCompleted(index: 1)
        tracker.breakEnded()

        XCTAssertEqual(pinger.trace, [
            "pod_b1:podStart",
            "b1_0_0:impression", "b1_0_0:start", "b1_0_0:firstQuartile", "b1_0_0:midpoint", "b1_0_0:thirdQuartile", "b1_0_0:complete",
            "b1_0_1:impression", "b1_0_1:start", "b1_0_1:firstQuartile", "b1_0_1:pause", "b1_0_1:resume",
            "b1_0_1:midpoint", "b1_0_1:thirdQuartile", "b1_0_1:complete",
            "pod_b1:podEnd",
        ])
        XCTAssertEqual(pinger.pings.first?.url, "https://t.example/b1/podStart")
    }

    func testFireOnceEventsAreNotRepeated() {
        tracker.breakStarted(id: "b1")
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.adStarted(index: 0)
        tracker.adProgress(fraction: 0.3)
        tracker.adProgress(fraction: 0.3)
        tracker.adCompleted()
        tracker.adCompleted()
        XCTAssertEqual(pinger.trace.filter { $0 == "b1_0_0:impression" }.count, 1)
        XCTAssertEqual(pinger.trace.filter { $0 == "b1_0_0:firstQuartile" }.count, 1)
        XCTAssertEqual(pinger.trace.filter { $0 == "b1_0_0:complete" }.count, 1)
        XCTAssertEqual(pinger.trace.filter { $0 == "pod_b1:podStart" }.count, 1)
    }

    func testPauseAndResumeCanRepeatButNeverDoublePause() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.adPaused(); tracker.adPaused()
        tracker.adResumed(); tracker.adResumed()
        tracker.adPaused()
        tracker.adResumed()
        XCTAssertEqual(pinger.trace.filter { $0.hasSuffix(":pause") }.count, 2)
        XCTAssertEqual(pinger.trace.filter { $0.hasSuffix(":resume") }.count, 2)
    }

    func testNoPauseAfterTheAdCompleted() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.adCompleted()
        tracker.adPaused()
        XCTAssertFalse(pinger.trace.contains("b1_0_0:pause"))
    }

    func testCompleteFillsInMissedQuartiles() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.adProgress(fraction: 0.1)
        tracker.adCompleted()
        XCTAssertEqual(pinger.trace.suffix(4), ["b1_0_0:firstQuartile", "b1_0_0:midpoint", "b1_0_0:thirdQuartile", "b1_0_0:complete"])
    }

    func testLateEndOfThePreviousAdIsIgnored() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.adStarted(index: 1)
        tracker.adCompleted(index: 0)
        XCTAssertFalse(pinger.trace.contains("b1_0_1:complete"))
    }

    func testNothingFiresOutsideABreak() {
        tracker.adStarted(index: 0)
        tracker.adProgress(fraction: 0.9)
        tracker.adPaused()
        tracker.adCompleted()
        tracker.breakEnded()
        XCTAssertTrue(pinger.pings.isEmpty)
    }

    func testEventsWaitForUrlsThatLoadAfterTheBreakStarted() {
        urls = [:]
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        XCTAssertTrue(pinger.pings.isEmpty)

        addUrls(breakId: "b1", ads: 1)
        tracker.trackingUrlsDidLoad(breakId: "b1")
        XCTAssertEqual(pinger.trace, ["pod_b1:podStart", "b1_0_0:impression", "b1_0_0:start"])

        tracker.trackingUrlsDidLoad(breakId: "b1")
        XCTAssertEqual(pinger.pings.count, 3)
    }

    func testABreakPlayedAgainIsTrackedAgain() {
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        tracker.breakEnded()
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        XCTAssertEqual(pinger.trace.filter { $0 == "b1_0_0:impression" }.count, 2)
        XCTAssertEqual(pinger.trace.filter { $0 == "pod_b1:podStart" }.count, 2)
    }

    func testANewBreakEndsTheOldOne() {
        addUrls(breakId: "b2", ads: 1)
        tracker.breakStarted(id: "b1")
        tracker.breakStarted(id: "b2")
        XCTAssertEqual(pinger.trace, ["pod_b1:podStart", "pod_b1:podEnd", "pod_b2:podStart"])
    }

    func testAllUrlsForAnEventAreCalled() {
        urls["b1_0_0"]?["impression"] = ["https://a.example/i", "https://b.example/i"]
        tracker.breakStarted(id: "b1")
        tracker.adStarted(index: 0)
        XCTAssertEqual(pinger.pings.filter { $0.event == "impression" }.map(\.url), ["https://a.example/i", "https://b.example/i"])
    }

    func testCustomUrlsSetOnTheLoggerAreUsed() {
        let pinger = RecordingPinger()
        let logger = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger(), enableSGAIAdTracking: true, sgaiPinger: pinger)
        logger.setAdTrackingUrls(["impression": ["https://custom.example/i"]], forAd: "b9_0_0")
        let tracker = SGAIAdEventTracker(lookup: { logger.trackingUrls(forAd: $0) }, pinger: pinger)
        tracker.breakStarted(id: "b9")
        tracker.adStarted(index: 0)
        XCTAssertEqual(pinger.pings.map(\.url), ["https://custom.example/i"])
    }

    func testAdTrackingIsOnlySetUpWhenEnabled() {
        let off = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        let on = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger(), enableSGAIAdTracking: true)
        XCTAssertNil(off.sgaiAdTracking)
        XCTAssertNotNil(on.sgaiAdTracking)
    }
}

/// Plays a real SGAI stream and checks the tracking calls. Needs a local server, so it
/// runs only when `SGAI_E2E_URL` is set, e.g.
/// `TEST_RUNNER_SGAI_E2E_URL=http://127.0.0.1:8099/sgai.m3u8 xcodebuild test ...`.
/// The stream must have one break of two ads, each with all ad events in its asset list.
final class SGAIEndToEndTests: XCTestCase {

    func testRealInterstitialBreakFiresAllEvents() throws {
        guard let urlString = ProcessInfo.processInfo.environment["SGAI_E2E_URL"],
              let url = URL(string: urlString) else {
            throw XCTSkip("Set SGAI_E2E_URL to a local SGAI stream to run this test")
        }
        let pinger = RecordingPinger(forwardTo: SGAIURLSessionPinger())
        let player = AVPlayer(url: url)
        player.isMuted = true
        let logger = AVPlayerEventLogger(player: player, logger: CapturingLogger(), enableSGAIAdTracking: true, sgaiPinger: pinger)
        player.play()

        // Pause 3 s into the first ad, then resume.
        let paused = expectation(description: "paused during ad")
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            player.pause()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                player.play()
                paused.fulfill()
            }
        }
        wait(for: [paused], timeout: 15)

        let done = expectation(description: "break ended")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            if pinger.trace.contains(where: { $0.hasSuffix(":podEnd") }) { done.fulfill() }
        }
        wait(for: [done], timeout: 40)
        timer.invalidate()
        _ = logger

        let trace = pinger.trace
        print("SGAI e2e trace: \(trace)")
        let breakId = try XCTUnwrap(trace.first?.split(separator: ":").first.map { String($0.dropFirst("pod_".count)) })
        let ad0 = "\(breakId)_0_0", ad1 = "\(breakId)_0_1"
        XCTAssertEqual(trace.first, "pod_\(breakId):podStart")
        XCTAssertEqual(trace.last, "pod_\(breakId):podEnd")
        for ad in [ad0, ad1] {
            for event in ["impression", "start", "firstQuartile", "midpoint", "thirdQuartile", "complete"] {
                XCTAssertEqual(trace.filter { $0 == "\(ad):\(event)" }.count, 1, "\(ad):\(event)")
            }
        }
        XCTAssertEqual(trace.filter { $0 == "\(ad0):pause" }.count, 1)
        XCTAssertEqual(trace.filter { $0 == "\(ad0):resume" }.count, 1)
        XCTAssertFalse(trace.contains("\(ad1):pause"))
        XCTAssertLessThan(trace.firstIndex(of: "\(ad0):complete")!, trace.firstIndex(of: "\(ad1):impression")!)
    }
}
