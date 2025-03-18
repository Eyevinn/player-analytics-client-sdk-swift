import Foundation
import AVFoundation

// MARK: - AnalyticsEventSender

internal final class AnalyticsEventSender {
    private let sessionId = UUID().uuidString
    private let eventSink: EventSinkPlayerLogger

    public var lastError: Error? = nil

    /// A computed property to retrieve the current time in milliseconds.
    private var currentTimestamp: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public init(logger eventSink : EventSinkPlayerLogger) {
        self.eventSink = eventSink
    }

    func sendEvent(eventType: String,
                   timestamp: Int64,
                   playhead: Int64,
                   duration: Int64,
                   payload: [String: Any]? = nil) {
        var event: [String: Any] = [
            "event": eventType,
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

    func sendInitEvent(expectedStartTime: Int64) {
        sendEvent(eventType: "init",
                  timestamp: currentTimestamp,
                  playhead: expectedStartTime,
                  duration: -1)
    }

    func sendMetadataEvent(isLive: Bool, contentTitle: String?) {
        let payload: [String: Any] = [
            "live": isLive,
            "contentTitle": contentTitle as Any
        ]
        sendEvent(eventType: "metadata",
                  timestamp: currentTimestamp,
                  playhead: 0,
                  duration: 0,
                  payload: payload)
    }

    func sendHeartbeatEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: "heartbeat",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendLoadingEvent() {
        sendEvent(eventType: "loading",
                  timestamp: currentTimestamp,
                  playhead: 0,
                  duration: 0)
    }

    func sendPlayingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: "playing",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendPausedEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: "paused",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendBufferingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: "buffering",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendSeekingEvent(playhead: Int64, duration: Int64) {
        sendEvent(eventType: "seeking",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration)
    }

    func sendStoppedEvent(playhead: Int64, duration: Int64, reason: String?) {
        let payload: [String: Any] = ["reason": reason as Any]
        sendEvent(eventType: "stopped",
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
        sendEvent(eventType: "error",
                  timestamp: currentTimestamp,
                  playhead: playhead,
                  duration: duration,
                  payload: payload)
    }

    private func sendToEventSink(event: [String: Any]) {

        eventSink.log(event)
    }
}
