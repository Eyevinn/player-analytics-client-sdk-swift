//
//  SGAITrackingAPITests.swift
//  VideoStreamTrackerTests
//
//  Public SGAI ad-tracking API on AVPlayerEventLogger (issue #21): the opt-in
//  toggle and get/set of tracking URLs per ad.
//

import AVFoundation
import XCTest
@testable import VideoStreamTracker

final class SGAITrackingAPITests: XCTestCase {

    private let adKey = "ad-session-1_0_0"

    func testSGAIAdTrackingIsOffByDefault() {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), eventSinkUrl: URL(string: "https://example.com/sink")!)
        XCTAssertFalse(tracker.isSGAIAdTrackingEnabled)
    }

    func testSGAIAdTrackingCanBeEnabledAtInit() {
        let tracker = AVPlayerEventLogger(
            player: AVPlayer(),
            eventSinkUrl: URL(string: "https://example.com/sink")!,
            enableSGAIAdTracking: true)
        XCTAssertTrue(tracker.isSGAIAdTrackingEnabled)
    }

    func testEnablingSGAIDoesNotChangeTheEventsSent() {
        let off = CapturingLogger()
        let on = CapturingLogger()
        _ = AVPlayerEventLogger(player: AVPlayer(), logger: off)
        _ = AVPlayerEventLogger(player: AVPlayer(), logger: on, enableSGAIAdTracking: true)
        XCTAssertEqual(on.events(named: "init").count, off.events(named: "init").count)
        XCTAssertEqual(on.events(named: "loading").count, off.events(named: "loading").count)
    }

    func testSetThenGetTrackingUrls() {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        let urls = [
            "impression": ["https://tracking.example.com/impression"],
            "firstQuartile": ["https://tracking.example.com/q1", "https://other.example.com/q1"],
        ]
        tracker.setAdTrackingUrls(urls, forAd: adKey)
        XCTAssertEqual(tracker.trackingUrls(forAd: adKey), urls)
    }

    func testUnknownAdReturnsNil() {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        XCTAssertNil(tracker.trackingUrls(forAd: "no-such-ad"))
    }

    func testSetReplacesAndDropsEventsWithoutUrls() {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        tracker.setAdTrackingUrls(["impression": ["https://a.example.com/i"]], forAd: adKey)
        tracker.setAdTrackingUrls(["complete": ["https://a.example.com/c"], "midpoint": []], forAd: adKey)
        XCTAssertEqual(tracker.trackingUrls(forAd: adKey), ["complete": ["https://a.example.com/c"]])
    }

    func testEmptyMapRemovesTheAd() {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        tracker.setAdTrackingUrls(["impression": ["https://a.example.com/i"]], forAd: adKey)
        tracker.setAdTrackingUrls([:], forAd: adKey)
        XCTAssertNil(tracker.trackingUrls(forAd: adKey))
    }

    func testUrlsParsedFromAssetListAreReadableAndOverridable() throws {
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: CapturingLogger())
        let assetList = """
        {
          "ASSETS": [
            { "URI": "ad.mp4", "DURATION": 15,
              "X-AD-CREATIVE-SIGNALING": { "payload": { "tracking": [
                { "type": "impression", "urls": ["https://parsed.example.com/i"] }
              ] } } }
          ],
          "X-AD-CREATIVE-SIGNALING": { "payload": { "tracking": [
            { "type": "podStart", "urls": ["https://parsed.example.com/pod-start"] }
          ] } }
        }
        """
        try tracker.sgaiTrackingUrls.parse(assetListJSON: assetList, adBreakId: "break-1")

        XCTAssertEqual(tracker.trackingUrls(forAd: adKey), ["impression": ["https://parsed.example.com/i"]])
        XCTAssertEqual(tracker.trackingUrls(forAd: "pod_break-1"), ["podStart": ["https://parsed.example.com/pod-start"]])

        tracker.setAdTrackingUrls(["impression": ["https://custom.example.com/i"]], forAd: adKey)
        XCTAssertEqual(tracker.trackingUrls(forAd: adKey), ["impression": ["https://custom.example.com/i"]])
        XCTAssertEqual(tracker.trackingUrls(forAd: "pod_break-1"), ["podStart": ["https://parsed.example.com/pod-start"]])
    }
}
