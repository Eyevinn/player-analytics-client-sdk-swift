import Foundation


// MARK: - Logger Protocol

/// A protocol that defines a logger to which AVPlayer events are sent.
public protocol Logger: Sendable {
    func log(_ message: String)
}

/// A simple console logger for debugging purposes.
public struct ConsoleLogger: Logger {
    public init() {}
    public func log(_ message: String) {
        print("[AVPlayerEventLogger] \(message)")
    }
}

public final class EventSinkPlayerLogger: Logger {
    public func log(_ message: String) {
        //nope
    }
    
    private let endpointURL: URL

    public init(endpoint: String) {
        self.endpointURL = URL(string: endpoint)!
    }


}
