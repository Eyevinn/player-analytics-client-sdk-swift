//
//  MetadataFieldsTests.swift
//  VideoStreamTrackerTests
//
//  Content ID/title (#62), time zone (#64) and platform (#65) in the metadata event.
//

import AVFoundation
import XCTest
@testable import VideoStreamTracker

final class MetadataFieldsTests: XCTestCase {

    private func lastMetadataPayload(_ capture: CapturingLogger) throws -> [String: Any] {
        let event = try XCTUnwrap(capture.events(named: "metadata").last)
        return try XCTUnwrap(event["payload"] as? [String: Any])
    }

    func testContentIdAndTitleAreSentWhenGiven() throws {
        let capture = CapturingLogger()
        AnalyticsEventSender(logger: capture).sendMetadataEvent(isLive: false, contentTitle: "VINN", contentId: "vinn-1")
        let payload = try lastMetadataPayload(capture)
        XCTAssertEqual(payload["contentTitle"] as? String, "VINN")
        XCTAssertEqual(payload["contentId"] as? String, "vinn-1")
    }

    func testContentFieldsAreOmittedNotNull() throws {
        let capture = CapturingLogger()
        AnalyticsEventSender(logger: capture).sendMetadataEvent(isLive: nil, contentTitle: nil)
        let payload = try lastMetadataPayload(capture)
        XCTAssertNil(payload["contentTitle"])
        XCTAssertNil(payload["contentId"])
        let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("null"), json)
    }

    func testDeviceTimeZoneIsSentByDefault() throws {
        let capture = CapturingLogger()
        AnalyticsEventSender(logger: capture).sendMetadataEvent(isLive: false, contentTitle: nil)
        XCTAssertEqual(try lastMetadataPayload(capture)["timeZone"] as? String, TimeZone.current.identifier)
    }

    func testTimeZoneOverrideIsSentUnchanged() throws {
        let capture = CapturingLogger()
        AnalyticsEventSender(logger: capture).sendMetadataEvent(isLive: false, contentTitle: nil, timeZone: "Asia/Tokyo")
        XCTAssertEqual(try lastMetadataPayload(capture)["timeZone"] as? String, "Asia/Tokyo")
    }

    func testPlatformForModelIdentifiers() {
        XCTAssertEqual(AnalyticsEventSender.platform(forModelIdentifier: "iPhone18,1"), "iOS")
        XCTAssertEqual(AnalyticsEventSender.platform(forModelIdentifier: "iPod9,1"), "iOS")
        XCTAssertEqual(AnalyticsEventSender.platform(forModelIdentifier: "iPad13,4"), "iPadOS")
        XCTAssertEqual(AnalyticsEventSender.platform(forModelIdentifier: "AppleTV14,1"), "tvOS")
    }

    func testPlatformIsSentForThisDevice() throws {
        let capture = CapturingLogger()
        AnalyticsEventSender(logger: capture).sendMetadataEvent(isLive: false, contentTitle: nil)
        #if os(tvOS)
        XCTAssertEqual(try lastMetadataPayload(capture)["platform"] as? String, "tvOS")
        #else
        let model = AnalyticsEventSender.modelIdentifier
        XCTAssertEqual(try lastMetadataPayload(capture)["platform"] as? String, model.hasPrefix("iPad") ? "iPadOS" : "iOS")
        #endif
    }

    func testReportNoLongerSendsATitleOverwritingMetadata() {
        let capture = CapturingLogger()
        let logger = AVPlayerEventLogger(player: AVPlayer(), logger: capture, contentTitle: "VINN")
        logger.report(payload: ["k": "v"])
        XCTAssertTrue(capture.events(named: "metadata").isEmpty)
    }

    func testSetContentBeforeTheItemIsReadySendsNothingYet() {
        let capture = CapturingLogger()
        let logger = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        logger.setContent(id: "a", title: "A")
        XCTAssertTrue(capture.events(named: "metadata").isEmpty)
    }
}

/// The logger end to end on a local stream: runs only when `PLAYBACK_E2E_URL` is set.
final class MetadataEndToEndTests: XCTestCase {

    func testMetadataCarriesContentTimeZoneAndPlatformAndFollowsSetContent() throws {
        guard let s = ProcessInfo.processInfo.environment["PLAYBACK_E2E_URL"], let url = URL(string: s) else {
            throw XCTSkip("Set PLAYBACK_E2E_URL to a local stream to run this test")
        }
        let capture = CapturingLogger()
        let player = AVPlayer(url: url)
        player.isMuted = true
        let logger = AVPlayerEventLogger(player: player, logger: capture, contentId: "vinn-1", contentTitle: "VINN")
        player.play()
        let ready = expectation(description: "metadata sent")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if !capture.events(named: "metadata").isEmpty { ready.fulfill() }
        }
        wait(for: [ready], timeout: 15)
        timer.invalidate()

        let first = try XCTUnwrap(capture.events(named: "metadata").first?["payload"] as? [String: Any])
        print("Metadata payload: \(first)")
        XCTAssertEqual(first["contentId"] as? String, "vinn-1")
        XCTAssertEqual(first["contentTitle"] as? String, "VINN")
        XCTAssertEqual(first["timeZone"] as? String, TimeZone.current.identifier)
        XCTAssertNotNil(first["platform"])
        XCTAssertNotNil(first["deviceType"])

        logger.setTimeZone("Europe/Oslo")
        logger.setContent(id: "next-2", title: "Next")
        let second = try XCTUnwrap(capture.events(named: "metadata").last?["payload"] as? [String: Any])
        XCTAssertEqual(capture.events(named: "metadata").count, 2)
        XCTAssertEqual(second["contentId"] as? String, "next-2")
        XCTAssertEqual(second["contentTitle"] as? String, "Next")
        XCTAssertEqual(second["timeZone"] as? String, "Europe/Oslo")
        logger.stopTracking()
    }
}
