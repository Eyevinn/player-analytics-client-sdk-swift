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
        if nextEvent == .warning || nextEvent == .heartbeat || nextEvent == .metadata || nextEvent == .bitrateChanged {
            return currentState
        }


        switch currentState {
        case .initEvent:
            if nextEvent == .loading || nextEvent == .loaded || nextEvent == .stopped {
                return nextEvent
            }
        case .loading:
            if nextEvent == .loaded || nextEvent == .buffering || nextEvent == .error {
                return nextEvent
            }
        case .loaded:
            if nextEvent == .playing || nextEvent == .paused || nextEvent == .buffering || nextEvent == .seeking  {
                return nextEvent
            }
        case .playing:
            if nextEvent == .paused || nextEvent == .buffering || nextEvent == .seeking || nextEvent == .stopped {
                return nextEvent
            }
        case .error:
            return currentState
        case .stopped:
            if nextEvent == .initEvent {
                return nextEvent
            } else {
                return currentState
            }
        case .seeking:
            if nextEvent == .seeked || nextEvent == .paused {
                return nextEvent
            }
        case .seeked:
            if nextEvent == .playing || nextEvent == .paused {
                return nextEvent
            }
        case .buffering:
            if nextEvent == .buffered {
                return nextEvent
            } else if nextEvent == .error {
                return nextEvent
            }
        case .buffered:
            if nextEvent == .playing || nextEvent == .seeking || nextEvent == .paused {
                return nextEvent
            }
        case .paused:
            if nextEvent == .playing || nextEvent == .buffering {
                return nextEvent
            }
        default:
            return .error
        }

        return .error   // Something is major-wrong so report error.
    }

    func currentStateAllows(_ nextEvent: SinkerEvent) -> Bool {
        if nextEvent == .error || nextEvent == .stopped || nextEvent == .warning ||  nextEvent == .heartbeat || nextEvent == .metadata {
            return true
        }

        switch currentState {
        case .initEvent:
            return nextEvent == .loading || nextEvent == .loaded || nextEvent == .initEvent
        case .loading:
            return nextEvent == .loaded || nextEvent == .buffering
        case .loaded:
            return nextEvent == .playing || nextEvent == .paused || nextEvent == .buffering || nextEvent == .seeking
        case .playing:
            return nextEvent == .paused || nextEvent == .buffering || nextEvent == .seeking || nextEvent == .stopped
        case .heartbeat:
            return true
        case .error:
            return true
        case .stopped:
            return nextEvent == .initEvent
        case .seeking:
            return nextEvent == .seeked || nextEvent == .paused
        case .seeked:
            return nextEvent == .playing || nextEvent == .paused
        case .buffering:
            return nextEvent == .buffered || nextEvent == .seeking || nextEvent == .stopped
        case .buffered:
            return nextEvent == .playing || nextEvent == .seeking || nextEvent == .paused
        case .bitrateChanged:
            return true
        case .warning:
            return true
        case .paused:
            return nextEvent == .playing || nextEvent == .buffering
        case .metadata:
            return true
        }
    }
}
