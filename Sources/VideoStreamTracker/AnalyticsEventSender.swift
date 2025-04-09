//
//  AnalyticsEventSender.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//

import Foundation
import AVFoundation
import UIKit

internal enum SinkerEvent: CustomStringConvertible {
    case initEvent
    case loading
    case loaded
    case playing
    case heartbeat
    case error
    case stopped
    case seeking
    case seeked
    case buffering
    case buffered
    case bitrateChanged
    case warning
    case paused
    case metadata
    case report

    var description: String {
        switch self {
        case .initEvent:
            return "init"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .playing:
            return "playing"
        case .heartbeat:
            return "heartbeat"
        case .error:
            return "error"
        case .stopped:
            return "stopped"
        case .seeking:
            return "seeking"
        case .seeked:
            return "seeked"
        case .buffering:
            return "buffering"
        case .buffered:
            return "buffered"
        case .bitrateChanged:
            return "bitrate_changed"
        case .warning:
            return "warning"
        case .paused:
            return "paused"
        case .metadata:
            return "metadata"
        case .report:
            return "report"
        }
    }
}

/// The `AnalyticsEventSender` class is responsible for sending analytics events to the event sink if they are allowed by the state machine.
/// It also keeps track of the current session ID.
internal final class AnalyticsEventSender {
    private let sessionId = UUID().uuidString
    private let eventSink: EventSinkPlayerLogger

    private let stateMachine = StateMachine()

    public var lastError: Error? = nil

    /// Obtain the machine hardware platform from the `uname()` unix command
    ///
    /// Example of return values
    ///  - `"iPhone8,1"` = iPhone 6s
    ///  - `"iPad6,7"` = iPad Pro (12.9-inch)
    static internal var unameMachine: String {
        var utsnameInstance = utsname()
        uname(&utsnameInstance)
        let optionalString: String? = withUnsafePointer(to: &utsnameInstance.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        return optionalString ?? "N/A"
    }

    /// A computed property to retrieve the current time in milliseconds.
    private var currentTimestamp: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public init(logger eventSink : EventSinkPlayerLogger) {
        self.eventSink = eventSink
    }

    private func sendEvent(eventType: SinkerEvent,
                   timestamp: Int64,
                   playhead: Int64,
                   duration: Int64,
                   payload: [String: Any]? = nil) {

        if stateMachine.handleEvent(nextEvent: eventType ) {


            var event: [String: Any] = [
                "event": eventType.description,
                "sessionId": sessionId,
                "timestamp": timestamp,
                "playhead": playhead,
                "duration": duration
            ]

            if let payload {
                event["payload"] = payload
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: event, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("******* Sending JSON-event: \(jsonString)")
            } else {
                print("******* Sending event: \(event)")
            }

            sendToEventSink(event: event)
        }
        else {
            print("============Event \(eventType) not allowed in state \(stateMachine.currentState)")
        }
    }

    func sendInitEvent(expectedStartTime: Int64) {
        sendEvent(eventType: .initEvent,
                  timestamp: currentTimestamp,
                  playhead: expectedStartTime,
                  duration: -1)
    }

    func sendMetadataEvent(isLive: Bool, contentTitle: String?) {
        
        let payload: [String: Any] = [
            "deviceType": AnalyticsEventSender.unameMachine,
            "live": isLive,
            "contentTitle": contentTitle as Any
        ]
        sendEvent(eventType: .metadata,
                  timestamp: currentTimestamp,
                  playhead: 0,
                  duration: 0,
                  payload: payload)
    }

    func sendHeartbeatEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .heartbeat,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendLoadingEvent() {
        sendEvent(eventType: .loading,
                  timestamp: currentTimestamp,
                  playhead: 0,
                  duration: 0)
    }

    func sendLoadedEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .loaded,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendPlayingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .playing,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendPausedEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .paused,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendBufferingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .buffering,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendBufferedEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .buffered,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendSeekingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: .seeking,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendSeekedEvent(playhead: Int64, duration: Int64, payload: [String: Any]? = nil) {
        sendEvent(eventType: .seeked,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }

    func sendBitrateChangedEvent(playhead: Int64, duration: Int64, payload: [String: Any]? = nil) {
        sendEvent(eventType: .bitrateChanged,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }


    func sendStoppedEvent(playhead: Int64, duration: Int64, reason: String?) {
        let payload: [String: Any] = ["reason": reason as Any]
        sendEvent(eventType: .stopped,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }

    func sendErrorEvent(playhead: Int64,
                        duration: Int64,
                        category: String?,
                        code: String?,
                        message: String?) {
        let payload: [String: Any] = [
            "category": category as Any,
            "code": code as Any,
            "message": message as Any
        ]
        sendEvent(eventType: .error,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }

    func sendWarningEvent(playhead: Int64,
                          duration: Int64,
                          payload: [String: Any]? = nil) {
        sendEvent(eventType: .warning,
                  timestamp: currentTimestamp,
                    playhead: playhead,
                    duration: duration,
                    payload: payload)
    }

    func sendReportEvent(playhead: Int64,
                         duration: Int64,
                         payload: [String: Any]?=nil) {
        sendEvent(eventType: .report,
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }

    private func sendToEventSink(event: [String: Any]) {

        eventSink.log(event)
    }
}
