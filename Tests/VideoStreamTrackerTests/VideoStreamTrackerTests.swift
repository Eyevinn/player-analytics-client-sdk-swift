import XCTest
import AVKit
@testable import VideoStreamTracker

final class VideoStreamTrackerTests: XCTestCase {
    func testInitialization() throws {
        let player = AVPlayer()
        let url = URL(string: "https://example.com/events")!
        let tracker = AVPlayerEventLogger(player: player, eventSinkUrl: url)
        XCTAssertNotNil(tracker)
    }
}

