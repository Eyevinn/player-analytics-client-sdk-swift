//
//  EventSinkPlayerLogger.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//

import Foundation

/// Receives each analytics event as it is sent. `EventSinkPlayerLogger` posts it to the
/// event sink; tests substitute a capturing implementation.
internal protocol EventLogging: AnyObject {
    func log(_ payload: [String: Any])
}

public final class EventSinkPlayerLogger: EventLogging {
    
    private let endpointURL: URL
    private let session: URLSession

    // Events are posted one at a time, in the order they were logged, so the eventsink sees
    // `init` first and a session's events in sequence (#41). Concurrent data tasks could
    // arrive in any order.
    private let sendQueue = DispatchQueue(label: "VideoStreamTracker.EventSinkPlayerLogger")
    private let requestTimeout: TimeInterval = 10

    /// Whether events carry the EPAS `sdk` field. Set from the `init` response's
    /// `epasVersion` (#57). Because events are posted one at a time, the `init` response is
    /// in before the next event is built, so every event after `init` gets the right answer.
    private let sdkGate = SDKGate()

    struct AnalyticsResponse: Codable {
        let sessionId: String
        let heartbeatInterval: Int
    }

    public convenience init(endpoint: URL) {
        self.init(endpoint: endpoint, session: .shared)
    }

    init(endpoint: URL, session: URLSession) {
        self.endpointURL = endpoint
        self.session = session
    }

    // MARK: - Logger
    // Tries to send the payload to the endpoint.
    // Only reports to the debug-log if something goes wrong.
    public func log(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload) else {
            print("Error serializing JSON: invalid payload \(payload)")
            return
        }
        let session = self.session
        let timeout = requestTimeout
        let endpointURL = self.endpointURL
        let gate = sdkGate
        let isInit = payload["event"] as? String == "init"
        // `[String: Any]` is not Sendable; the payload is only read on the send queue.
        nonisolated(unsafe) let payload = payload
        sendQueue.async {
            var body = payload
            if gate.sendsSdk {
                body["sdk"] = ["name": SDKInfo.name, "version": SDKInfo.version]
            }
            var request = URLRequest(url: endpointURL, timeoutInterval: timeout)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            } catch {
                print("Error serializing JSON: \(error)")
                return
            }

            let done = DispatchSemaphore(value: 0)
            let task = session.dataTask(with: request) { data, response, error in
                defer { done.signal() }
                if isInit { gate.update(fromInitResponse: data, response: response) }
                EventSinkPlayerLogger.report(data: data, response: response, error: error)
            }
            task.resume()
            // Wait for this request before sending the next one; never block longer than the timeout.
            _ = done.wait(timeout: .now() + timeout + 1)
        }
    }

    private static func report(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            print("Error making POST request: \(error)")
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response received")
            return
        }
        if (200...299).contains(httpResponse.statusCode)  {

            // everything is fine. So jump out.
            return
        }

        guard let data = data else {
            print("No data in response")
            return
        }

        // Print raw response if needed.
        if let jsonResponse = String(data: data, encoding: .utf8) {
            print("Raw response: \(jsonResponse)")
        }

        // If you expect a JSON response, decode it.
        do {
            let analyticResponse = try JSONDecoder().decode(AnalyticsResponse.self, from: data)
            print("Response: \(analyticResponse)")
        } catch {
            print ("Error decoding response JSON: \(error) from data: \(data)")
        }
    }
}

/// Holds the `sdk` decision; written from the `init` response, read on the send queue.
final class SDKGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _sendsSdk = false

    var sendsSdk: Bool {
        lock.lock(); defer { lock.unlock() }
        return _sendsSdk
    }

    /// Turns `sdk` on only when the eventsink answered `init` with HTTP 2xx and an
    /// `epasVersion` of at least `SDKInfo.minimumEpasVersionForSdk`; otherwise leaves it off.
    func update(fromInitResponse data: Data?, response: URLResponse?) {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let on = SDKInfo.isVersion(json["epasVersion"], atLeast: SDKInfo.minimumEpasVersionForSdk)
        lock.lock(); _sendsSdk = on; lock.unlock()
    }
}
