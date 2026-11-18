//
//  PlaybackEndToEndTests.swift
//  VideoStreamTrackerTests
//
//  Real playback in the simulator against local streams (issue #59). Skipped unless
//  the URLs are set, e.g.
//  `TEST_RUNNER_PLAYBACK_E2E_URL=http://127.0.0.1:8099/content.m3u8`
//  `TEST_RUNNER_STALL_E2E_URL=http://127.0.0.1:8098/content.m3u8` (a server that serves
//  segments slower than they play) `xcodebuild test ...`.
//

import AVFoundation
import XCTest
@testable import VideoStreamTracker

final class PlaybackEndToEndTests: XCTestCase {

    private func url(_ name: String) throws -> URL {
        guard let s = ProcessInfo.processInfo.environment[name], let url = URL(string: s) else {
            throw XCTSkip("Set \(name) to a local stream to run this test")
        }
        return url
    }

    private func names(_ capture: CapturingLogger) -> [String] {
        capture.events.compactMap { $0["event"] as? String }
    }

    private func wait(seconds: TimeInterval) {
        let done = expectation(description: "wait \(seconds)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    func testResumeWithAFullBufferIsNotARebuffer() throws {
        let url = try url("PLAYBACK_E2E_URL")
        let capture = CapturingLogger()
        let player = AVPlayer(url: url)
        player.isMuted = true
        let logger = AVPlayerEventLogger(player: player, logger: capture)
        player.play()
        wait(seconds: 4); player.pause()
        wait(seconds: 2); player.play()
        wait(seconds: 3); player.pause()
        wait(seconds: 2); player.play()
        wait(seconds: 3)
        _ = logger

        let events = names(capture)
        print("Resume events: \(events)")
        let afterFirstPlay = events.drop { $0 != "playing" }
        XCTAssertFalse(afterFirstPlay.contains("buffering"), "\(events)")
        XCTAssertEqual(afterFirstPlay.filter { $0 == "paused" }.count, 2, "\(events)")
        XCTAssertEqual(afterFirstPlay.filter { $0 == "playing" }.count, 3, "\(events)")
    }

    func testARealStallIsStillReported() throws {
        let url = try url("STALL_E2E_URL")
        let capture = CapturingLogger()
        let player = AVPlayer(url: url)
        player.isMuted = true
        let logger = AVPlayerEventLogger(player: player, logger: capture)
        player.play()
        wait(seconds: 20)
        _ = logger

        let events = names(capture)
        print("Stall events: \(events)")
        let afterFirstPlay = Array(events.drop { $0 != "playing" })
        let buffering = try XCTUnwrap(afterFirstPlay.firstIndex(of: "buffering"), "\(events)")
        XCTAssertTrue(afterFirstPlay[buffering...].contains("buffered"), "\(events)")
    }
}
