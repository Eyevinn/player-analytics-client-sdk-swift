import XCTest
import AVKit
@testable import VideoStreamTracker

final class VideoStreamTrackerTests: XCTestCase {
    func testInitialization() throws {
        let player = AVPlayer()
        let tracker = AVPlayerEventLogger(player: player, eventSinkUrl: URL(string: "https://example.com/sink")!)
        XCTAssertNotNil(tracker)
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
