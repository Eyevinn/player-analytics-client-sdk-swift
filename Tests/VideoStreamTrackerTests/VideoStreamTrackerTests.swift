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
}
