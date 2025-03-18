import Foundation

public final class EventSinkPlayerLogger {//: Logger {
    
    private let endpointURL: URL

    struct AnalyticsResponse: Codable {
        let sessionId: String
        let heartbeatInterval: Int
    }

    public init(endpoint: URL) {
        self.endpointURL = endpoint
    }


    public func log(_ payload: [String: Any]) {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        // wet the content-Type header
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Seialize the payload ilnto JSON data.
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            print("Error serializeing JSONO: \(error)")
            return
        }

        // Create a datatask
        let task = URLSession.shared.dataTask(with: request) { data, repsonse, error in
            if let error = error {
                print("Error making POST request: \(error)")
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
                print("Decoded response: sessionId = \(analyticResponse.sessionId),heartbeatInterval = \(analyticResponse.heartbeatInterval)")
            } catch {
                print ("Error decoding response JSON: \(error)")
            }
        }

        // Start the task.
        task.resume()

    }
}
