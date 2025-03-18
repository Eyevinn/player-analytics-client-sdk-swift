import Foundation

public final class EventSinkPlayerLogger: Logger {
    public func log(_ message: String) {
        //nope
    }
    
    private let endpointURL: URL

    public init(endpoint: String) {
        self.endpointURL = URL(string: endpoint)!
    }


}
