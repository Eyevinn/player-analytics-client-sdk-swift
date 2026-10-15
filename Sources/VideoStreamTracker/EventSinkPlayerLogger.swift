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
        var request = URLRequest(url: endpointURL, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")


        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            print("Error serializeing JSONO: \(error)")
            return
        }

        let session = self.session
        let timeout = requestTimeout
        sendQueue.async {
            let done = DispatchSemaphore(value: 0)
            let task = session.dataTask(with: request) { data, response, error in
                defer { done.signal() }
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
