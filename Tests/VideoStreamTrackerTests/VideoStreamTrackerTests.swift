import XCTest
import AVKit
@testable import VideoStreamTracker

final class VideoStreamTrackerTests: XCTestCase {
    func testInitialization() throws {
        let player = AVPlayer()
        let tracker = AVPlayerEventLogger(player: player, eventSinkUrl: URL(string: "https://example.com/sink")!)
        XCTAssertNotNil(tracker)
    }

    // MARK: - isLiveStream

    func testIsLiveStreamIndefiniteReturnsTrue() {
        // Live streams surface an indefinite CMTime -> live.
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.indefinite))
    }

    func testIsLiveStreamInvalidReturnsTrue() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.invalid))
    }

    func testIsLiveStreamPositiveInfinityReturnsTrue() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.positiveInfinity))
    }

    func testIsLiveStreamNaNSecondsReturnsTrue() {
        // A CMTime whose .seconds evaluates to NaN must still map to live, not VOD.
        let nanTime = CMTime(value: 0, timescale: 0)
        XCTAssertTrue(nanTime.seconds.isNaN)
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(nanTime))
    }

    func testIsLiveStreamFiniteDurationReturnsFalse() {
        // VOD content exposes a finite, numeric duration -> not live.
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(tenSeconds))
    }

    func testIsLiveStreamZeroLengthReturnsFalse() {
        // A genuine 0-length (finite) item is still VOD, not live.
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(.zero))
    }

    // MARK: - normalizeDuration

    func testNormalizeDurationIndefiniteReturnsMinusOne() {
        // Live / indefinite streams surface an indefinite CMTime; spec requires -1 (unknown).
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.indefinite), -1)
    }

    func testNormalizeDurationInvalidReturnsMinusOne() {
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.invalid), -1)
    }

    func testNormalizeDurationPositiveInfinityReturnsMinusOne() {
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.positiveInfinity), -1)
    }

    func testNormalizeDurationNaNSecondsReturnsMinusOne() {
        // A CMTime whose .seconds evaluates to NaN must still map to unknown, not 0.
        let nanTime = CMTime(value: 0, timescale: 0)
        XCTAssertTrue(nanTime.seconds.isNaN)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(nanTime), -1)
    }

    func testNormalizeDurationZeroLengthReturnsZero() {
        // A genuine 0-length item stays 0 (must NOT be conflated with unknown).
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.zero), 0)
    }

    func testNormalizeDurationFiniteReturnsMilliseconds() {
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(tenSeconds), 10_000)
    }

    func testNormalizeDurationFractionalFiniteReturnsMilliseconds() {
        let time = CMTime(seconds: 1.5, preferredTimescale: 600)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(time), 1_500)
    }

    // MARK: - isLiveStream

    func testIsLiveStreamIndefiniteIsLive() {
        // Live streams surface an indefinite duration.
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.indefinite))
    }

    func testIsLiveStreamPositiveInfinityIsLive() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.positiveInfinity))
    }

    func testIsLiveStreamFiniteIsNotLive() {
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(tenSeconds))
    }

    func testIsLiveStreamZeroLengthIsNotLive() {
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(.zero))
    }

    // MARK: - liveEdgeUTCMilliseconds

    func testLiveEdgeUTCMillisecondsNilReturnsMinusOne() {
        // Live edge indeterminable -> unknown (-1), mirroring the normalizeDuration contract.
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: nil), -1)
    }

    func testLiveEdgeUTCMillisecondsReturnsUTCMilliseconds() {
        // Spec: Live `duration` is the live edge as UTC wall-clock time in milliseconds.
        let date = Date(timeIntervalSince1970: 1_634_911_668.339)
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: date), 1_634_911_668_339)
    }

    func testLiveEdgeUTCMillisecondsEpochReturnsZero() {
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: Date(timeIntervalSince1970: 0)), 0)
    }
}

// MARK: - Test helpers

final class CapturingLogger: EventLogging {
    var events: [[String: Any]] = []
    func log(_ payload: [String: Any]) { events.append(payload) }
    func events(named name: String) -> [[String: Any]] {
        events.filter { $0["event"] as? String == name }
    }
}

// MARK: - stopped reason (#40)

final class StoppedReasonTests: XCTestCase {
    func testStoppedCarriesStringReasonNeverNull() throws {
        let capture = CapturingLogger()
        let sender = AnalyticsEventSender(logger: capture)
        sender.sendInitEvent(expectedStartTime: 0)
        sender.sendLoadingEvent()
        sender.sendLoadedEvent(playhead: 0, duration: 10_000)
        sender.sendPlayingEvent(playhead: 0, duration: 10_000)
        sender.sendStoppedEvent(playhead: 10_000, duration: 10_000, reason: .ended)

        let stopped = try XCTUnwrap(capture.events(named: "stopped").last)
        let payload = try XCTUnwrap(stopped["payload"] as? [String: Any])
        XCTAssertEqual(payload["reason"] as? String, "ended")

        // Serialised JSON must not contain a null reason.
        let json = String(data: try JSONSerialization.data(withJSONObject: stopped), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("null"), json)
    }

    func testStopReasonValuesMatchEPAS() {
        XCTAssertEqual(StopReason.ended.rawValue, "ended")
        XCTAssertEqual(StopReason.error.rawValue, "error")
        XCTAssertEqual(StopReason.aborted.rawValue, "aborted")
        XCTAssertEqual(StopReason.unknown.rawValue, "unknown")
    }

    func testStopTrackingSendsOneAbortedStopped() throws {
        let capture = CapturingLogger()
        var tracker: AVPlayerEventLogger? = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        tracker?.stopTracking()
        tracker?.stopTracking()
        tracker = nil  // deinit must not send a second stopped

        let stopped = capture.events(named: "stopped")
        XCTAssertEqual(stopped.count, 1)
        let payload = try XCTUnwrap(stopped.first?["payload"] as? [String: Any])
        XCTAssertEqual(payload["reason"] as? String, "aborted")
    }

    func testReleasingTrackerSendsAbortedStopped() {
        let capture = CapturingLogger()
        var tracker: AVPlayerEventLogger? = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        XCTAssertNotNil(tracker)
        tracker = nil
        XCTAssertEqual(capture.events(named: "stopped").count, 1)
    }
}

final class PlayheadTests: XCTestCase {
    func testUnknownPlayheadIsMinusOneNotACrash() {
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(.invalid), -1)
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(.indefinite), -1)
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(CMTime(seconds: 1.5, preferredTimescale: 600)), 1500)
    }
}
