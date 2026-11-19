//
//  StateMachine.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//


import Foundation

/// Decides which events are sent, so the eventsink gets the EPAS event flow
/// (player-analytics-specification `specification/README.md` and its flowchart).
///
/// Two kinds of events:
/// - **State events** (`init`, `loading`, `loaded`, `playing`, `paused`, `buffering`,
///   `buffered`, `seeking`, `seeked`) are sent only when they are a valid next step from the
///   current state, and then move the machine to that state. Anything else (a duplicate, or
///   an event out of order) is dropped and the state stays as it is.
/// - **Other events** (`heartbeat`, `metadata`, `bitrate_changed`, `warning`, `report`) are
///   sent in every state, except after `stopped`, and never change the state.
///
/// `error` and `stopped` are always sent (until the session has stopped). `error` is fatal:
/// after it only `stopped` and `report` are sent.
///
/// Before #56 the first event (`init`) moved the machine to `.error`, which allowed every
/// event from then on, so nothing was ever filtered.
internal final class StateMachine {

    internal private(set) var currentState: SinkerEvent = .initEvent
    private var hasStarted = false

    /// The events to send for `nextEvent`, in order, and updates the state. Usually
    /// `[nextEvent]` or `[]`; `[.buffered, .playing]` when playback starts while buffering
    /// without a `buffered` (AVPlayer goes from waiting straight to playing when a viewer
    /// resumes), because EPAS closes a buffering period with `buffered` before `playing`.
    internal func events(for nextEvent: SinkerEvent) -> [SinkerEvent] {
        if nextEvent == .playing, currentState == .buffering {
            currentState = .playing
            return [.buffered, .playing]
        }
        return handleEvent(nextEvent: nextEvent) ? [nextEvent] : []
    }

    /// Returns true when `nextEvent` should be sent, and updates the state.
    internal func handleEvent(nextEvent: SinkerEvent) -> Bool {
        if currentState == .stopped {
            // Nothing follows `stopped` except an app's own report.
            return nextEvent == .report
        }

        switch nextEvent {
        case .heartbeat, .metadata, .bitrateChanged, .warning, .report:
            return currentState != .error || nextEvent == .report
        case .stopped:
            currentState = .stopped
            return true
        case .error:
            currentState = .error
            return true
        default:
            break
        }

        guard let next = Self.transitions[currentState]?[nextEvent] else { return false }
        if nextEvent == .initEvent {
            // `init` MUST be sent once per session.
            guard !hasStarted else { return false }
            hasStarted = true
        }
        currentState = next
        return true
    }

    /// Valid state events per state, and the state each one moves to.
    private static let transitions: [SinkerEvent: [SinkerEvent: SinkerEvent]] = [
        // `init` first; then the content is attached (`loading`) or already loaded.
        .initEvent: [.initEvent: .initEvent, .loading: .loading, .loaded: .loaded],
        // EPAS: buffering while loading is ignored.
        .loading: [.loaded: .loaded],
        // Before the first `playing`, buffering is still part of loading.
        .loaded: [.playing: .playing, .paused: .paused, .seeking: .seeking],
        .playing: [.paused: .paused, .buffering: .buffering, .seeking: .seeking],
        .paused: [.playing: .playing, .buffering: .buffering, .seeking: .seeking],
        // EPAS: `playing` only after `buffered`; a seek can interrupt buffering.
        .buffering: [.buffered: .buffered, .seeking: .seeking, .paused: .paused],
        .buffered: [.playing: .playing, .paused: .paused, .seeking: .seeking, .buffering: .buffering],
        // EPAS: `playing` only after `seeked`.
        .seeking: [.seeked: .seeked],
        .seeked: [.playing: .playing, .paused: .paused, .buffering: .buffering, .seeking: .seeking],
    ]
}
