//
//  StateMachine.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//


import Foundation

/// The `StateMachine` class is responsible for managing the state of the player.
/// It keeps track of the current state and transitions to the next state based on the event.
///
/// The reason for the looooong implementation of the logic is to make each step as clear as possible.
/// Step 1. Based on the state the the StateMachine is in, is the state of the next step allowed? This you'll find in `currentStateAllows(_ nextEvent:)`.
/// Step 2. Since athe next step is valid, what state should the StateMachine transition to? This you'll find in `nextStateBasedOn(_ nextEvent:)`.
internal final class StateMachine {

    internal var currentState: SinkerEvent = .initEvent

    internal func handleEvent(nextEvent nextStep: SinkerEvent) -> Bool {

        if currentStateAllows(nextStep) {
            currentState = nextStateBasedOn(nextStep)
            return true
        } else {
            return false
        }
    }

    func nextStateBasedOn(_ nextEvent: SinkerEvent) -> SinkerEvent {
        switch currentState {
        case .initEvent:
            return nextEvent
        case .loading:
            return nextEvent
        case .loaded:
            if nextEvent == .playing {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            } else if nextEvent == .bitrateChanged {
                return currentState
            }
        case .playing:
            if nextEvent == .heartbeat {
                return currentState
            } else if nextEvent == .error {
                return nextEvent
            } else if nextEvent == .paused {
                return nextEvent
            } else if nextEvent == .buffering {
                return nextEvent
            } else if nextEvent == .seeking {
                return nextEvent
            } else if nextEvent == .stopped {
                return nextEvent
            } else if nextEvent == .bitrateChanged {
                return currentState
            } else if nextEvent == .warning {
                return currentState
            } else if nextEvent == .metadata {
                return currentState
            }
        case .heartbeat:
            // This should be impossible
            return .heartbeat
        case .error:
            return .stopped
        case .stopped:
            if nextEvent == .loading {
                return nextEvent
            } else if nextEvent == .error {
                return currentState
            } else if nextEvent == .initEvent {
                return nextEvent
            }
        case .seeking:
            if nextEvent == .seeked {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            }
        case .seeked:
            if nextEvent == .playing {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            } else if nextEvent == .paused {
                return nextEvent
            }
        case .buffering:
            if nextEvent == .buffered {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            }
        case .buffered:
            if nextEvent == .playing {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            } else if nextEvent == .paused {
                return nextEvent
            }
        case .bitrateChanged:
            return currentState
        case .warning:
            return currentState
        case .paused:
            if nextEvent == .playing {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            }
        case .metadata:
            return currentState
        }

        return currentState
    }

    func currentStateAllows(_ nextEvent: SinkerEvent) -> Bool {
        switch currentState {
        case .initEvent:
            return nextEvent == .loading || nextEvent == .initEvent
        case .loading:
            return nextEvent == .loaded || nextEvent == .error
        case .loaded:
            return nextEvent == .playing || nextEvent == .error || nextEvent == .bitrateChanged
        case .playing:
            return nextEvent == .heartbeat || nextEvent == .error || nextEvent == .paused || nextEvent == .buffering || nextEvent == .seeking || nextEvent == .stopped || nextEvent == .bitrateChanged || nextEvent == .warning || nextEvent == .metadata
        case .heartbeat:
            return true
        case .error:
            return nextEvent == .stopped
        case .stopped:
            return nextEvent == .loading || nextEvent == .error || nextEvent == .initEvent
        case .seeking:
            return nextEvent == .seeked || nextEvent == .error
        case .seeked:
            return nextEvent == .playing || nextEvent == .error || nextEvent == .paused
        case .buffering:
            return nextEvent == .buffered || nextEvent == .error
        case .buffered:
            return nextEvent == .playing || nextEvent == .error || nextEvent == .paused
        case .bitrateChanged:
            return true
        case .warning:
            return true
        case .paused:
            return nextEvent == .playing || nextEvent == .error
        case .metadata:
            return true
        }
    }
}
