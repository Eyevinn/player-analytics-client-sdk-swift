import XCTest
import AVKit
@testable import VideoStreamTracker

final class VideoStreamTrackerTests: XCTestCase {
    func testInitialization() throws {
        let player = AVPlayer()
        let tracker = VideoStreamTracker(player: player)
        XCTAssertNotNil(tracker)
    }
}

