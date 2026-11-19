//
//  StateMachineTests.swift
//  VideoStreamTrackerTests
//
//  The EPAS event flow the state machine lets through (issue #56).
//

import XCTest
@testable import VideoStreamTracker

final class StateMachineTests: XCTestCase {

    /// Feeds events in and returns what is sent, by EPAS name.
    private func sent(_ events: [SinkerEvent], machine: StateMachine = StateMachine()) -> [String] {
        events.flatMap { machine.events(for: $0) }.map(\.description)
    }

    func testIssueSequenceDropsDuplicatesAndOutOfOrderEvents() {
        // The sequence from #56 (all 12 were sent before).
        let out = sent([.initEvent, .loading, .buffering, .buffering, .bitrateChanged, .loaded,
                        .playing, .playing, .seeked, .buffered, .paused, .paused])
        XCTAssertEqual(out, ["init", "loading", "bitrate_changed", "loaded", "playing", "paused"])
    }

    func testRealAVPlayerStartIgnoresBufferingWhileLoading() {
        // As recorded from AVPlayer on the simulator, 2026-11-18.
        let out = sent([.initEvent, .loading, .buffering, .buffering, .bitrateChanged, .loaded,
                        .metadata, .buffered, .playing])
        XCTAssertEqual(out, ["init", "loading", "bitrate_changed", "loaded", "metadata", "playing"])
    }

    func testPauseAndResumeClosesTheResumeWaitWithBuffered() {
        // AVPlayer on resume: waiting (buffering) then playing, without buffered.
        let out = sent([.initEvent, .loading, .loaded, .playing, .paused, .buffering, .playing])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "paused", "buffering", "buffered", "playing"])
    }

    func testRebufferIsOnePair() {
        let out = sent([.initEvent, .loading, .loaded, .playing, .buffering, .buffering, .buffered, .buffered, .playing])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "buffering", "buffered", "playing"])
    }

    func testSeekThroughTheLogger() {
        let out = sent([.initEvent, .loading, .loaded, .playing, .seeking, .seeked, .buffering, .buffered, .playing])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "seeking", "seeked", "buffering", "buffered", "playing"])
    }

    func testPlayingWaitsForSeekedAndSeekWhilePausedIsAllowed() {
        let out = sent([.initEvent, .loading, .loaded, .playing, .paused, .seeking, .playing, .seeked, .playing])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "paused", "seeking", "seeked", "playing"])
    }

    func testSeekedWithoutSeekingIsDropped() {
        XCTAssertEqual(sent([.initEvent, .loading, .loaded, .playing, .seeked]), ["init", "loading", "loaded", "playing"])
    }

    func testNothingFollowsStoppedExceptReport() {
        let out = sent([.initEvent, .loading, .loaded, .playing, .stopped, .paused, .heartbeat, .playing, .stopped, .report])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "stopped", "report"])
    }

    func testErrorIsFatal() {
        let out = sent([.initEvent, .loading, .loaded, .playing, .error, .heartbeat, .playing, .buffering, .stopped])
        XCTAssertEqual(out, ["init", "loading", "loaded", "playing", "error", "stopped"])
    }

    func testInitIsSentOnce() {
        XCTAssertEqual(sent([.initEvent, .initEvent, .loading]), ["init", "loading"])
    }

    func testStoppedBeforeLoadingIsSent() {
        XCTAssertEqual(sent([.initEvent, .stopped]), ["init", "stopped"])
    }

    func testNonStateEventsAreSentInEveryStateAndDoNotChangeIt() {
        let paths: [[SinkerEvent]] = [
            [.initEvent],
            [.initEvent, .loading],
            [.initEvent, .loading, .loaded],
            [.initEvent, .loading, .loaded, .playing],
            [.initEvent, .loading, .loaded, .playing, .paused],
            [.initEvent, .loading, .loaded, .playing, .buffering],
            [.initEvent, .loading, .loaded, .playing, .buffering, .buffered],
            [.initEvent, .loading, .loaded, .playing, .seeking],
            [.initEvent, .loading, .loaded, .playing, .seeking, .seeked],
        ]
        for path in paths {
            let machine = StateMachine()
            _ = sent(path, machine: machine)
            let state = machine.currentState
            for event: SinkerEvent in [.heartbeat, .metadata, .bitrateChanged, .warning, .report] {
                XCTAssertEqual(machine.events(for: event), [event], "\(event) in \(state)")
                XCTAssertEqual(machine.currentState, state, "\(event) changed \(state)")
            }
        }
    }

    func testNoPathReachesErrorWithoutAnErrorEvent() {
        let all: [SinkerEvent] = [.initEvent, .loading, .loaded, .playing, .paused, .buffering, .buffered,
                                  .seeking, .seeked, .heartbeat, .metadata, .bitrateChanged, .warning, .report]
        // Every pair of events from every reachable state.
        var frontier: [[SinkerEvent]] = [[]]
        for _ in 0..<4 {
            var next: [[SinkerEvent]] = []
            for path in frontier {
                for event in all {
                    let machine = StateMachine()
                    _ = sent(path + [event], machine: machine)
                    XCTAssertNotEqual(machine.currentState, .error, "\(path + [event])")
                    next.append(path + [event])
                }
            }
            frontier = Array(next.prefix(400))
        }
    }
}
