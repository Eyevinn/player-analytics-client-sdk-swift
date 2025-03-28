//
//  EventSinkPlayerLogger.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//

import Foundation

public final class EventSinkPlayerLogger {
    
    private let endpointURL: URL

    struct AnalyticsResponse: Codable {
        let sessionId: String
        let heartbeatInterval: Int
    }

    public init(endpoint: URL) {
        self.endpointURL = endpoint
    }

    // MARK: - Logger
    // Tries to send the payload to the endpoint.
    // Only reports to the debug-log if something goes wrong.
    public func log(_ payload: [String: Any]) {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")


        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            print("Error serializeing JSONO: \(error)")
            return
        }

        // Create a datatask
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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

        // Start the task.
        task.resume()

    }
}
