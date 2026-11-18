//
//  SDKFieldTests.swift
//  VideoStreamTrackerTests
//
//  The EPAS `sdk` field after the `epasVersion` handshake (issue #57).
//

import XCTest
@testable import VideoStreamTracker

/// A stub eventsink: answers `init` with the configured status and body, everything else
/// with 200, and records each request body.
final class HandshakeStubProtocol: URLProtocol {
    nonisolated(unsafe) static var initStatus = 200
    nonisolated(unsafe) static var initBody: [String: Any] = [:]
    nonisolated(unsafe) static var bodies: [[String: Any]] = []
    static let lock = NSLock()

    static func reset(initStatus: Int = 200, initBody: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        self.initStatus = initStatus
        self.initBody = initBody
        bodies = []
    }

    static var recorded: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return bodies
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        } ?? Data()
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        Self.lock.lock()
        Self.bodies.append(json)
        let isInit = json["event"] as? String == "init"
        let status = isInit ? Self.initStatus : 200
        let body = isInit ? Self.initBody : [:]
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SDKFieldTests: XCTestCase {

    /// Logs init, loading, playing and returns the request bodies the stub received.
    private func session(initStatus: Int = 200, initBody: [String: Any]) -> [[String: Any]] {
        HandshakeStubProtocol.reset(initStatus: initStatus, initBody: initBody)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HandshakeStubProtocol.self]
        let logger = EventSinkPlayerLogger(endpoint: URL(string: "https://sink.test/")!, session: URLSession(configuration: config))
        for event in ["init", "loading", "playing"] {
            logger.log(["event": event, "sessionId": "s1", "playhead": 1500, "duration": 30000])
        }
        let deadline = Date().addingTimeInterval(5)
        while HandshakeStubProtocol.recorded.count < 3 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return HandshakeStubProtocol.recorded
    }

    private let sdk: [String: String] = ["name": "swift", "version": SDKInfo.version]

    func testNoSdkWhenTheEventsinkIsOlderOrDoesNotSay() {
        let answers: [[String: Any]] = [
            ["sessionId": "s1", "heartbeatInterval": 5000, "epasVersion": "0.6.0"],
            ["sessionId": "s1", "heartbeatInterval": 5000],
            ["sessionId": "s1", "heartbeatInterval": 5000, "epasVersion": "n/a"],
            ["sessionId": "s1", "heartbeatInterval": 5000, "epasVersion": "garbage"],
            ["sessionId": "s1", "heartbeatInterval": 5000, "epasVersion": 7],
        ]
        for answer in answers {
            let bodies = session(initBody: answer)
            XCTAssertEqual(bodies.count, 3, "\(answer)")
            XCTAssertTrue(bodies.allSatisfy { $0["sdk"] == nil }, "\(answer): \(bodies)")
        }
    }

    func testSdkOnEveryEventAfterInitWhenTheEventsinkSupportsIt() {
        for version in ["0.7.0", "0.10.0", "1.0.0", "0.7.0-beta.1"] {
            let bodies = session(initBody: ["sessionId": "s1", "heartbeatInterval": 5000, "epasVersion": version])
            XCTAssertEqual(bodies.count, 3, version)
            XCTAssertNil(bodies.first?["sdk"], "init itself goes out before the handshake")
            for body in bodies.dropFirst() {
                XCTAssertEqual(body["sdk"] as? [String: String], sdk, version)
                // Nothing else changes.
                XCTAssertEqual(body["playhead"] as? Int, 1500, version)
                XCTAssertEqual(body["duration"] as? Int, 30000, version)
            }
        }
    }

    func testNoSdkWhenInitFails() {
        let bodies = session(initStatus: 400, initBody: ["epasVersion": "0.7.0"])
        XCTAssertTrue(bodies.allSatisfy { $0["sdk"] == nil }, "\(bodies)")
    }

    func testVersionComparisonIsNumeric() {
        XCTAssertTrue(SDKInfo.isVersion("0.10.0", atLeast: "0.7.0"))
        XCTAssertTrue(SDKInfo.isVersion("0.7.0", atLeast: "0.7.0"))
        XCTAssertTrue(SDKInfo.isVersion("1.0.0", atLeast: "0.7.0"))
        XCTAssertFalse(SDKInfo.isVersion("0.6.9", atLeast: "0.7.0"))
        XCTAssertFalse(SDKInfo.isVersion("0.7", atLeast: "0.7.0"))
        XCTAssertFalse(SDKInfo.isVersion(nil, atLeast: "0.7.0"))
        XCTAssertFalse(SDKInfo.isVersion("n/a", atLeast: "0.7.0"))
    }

    func testSdkVersionIsAValidVersion() {
        XCTAssertTrue(SDKInfo.isVersion(SDKInfo.version, atLeast: "0.0.0"))
    }
}
