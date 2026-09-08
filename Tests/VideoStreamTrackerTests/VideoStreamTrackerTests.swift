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
}
