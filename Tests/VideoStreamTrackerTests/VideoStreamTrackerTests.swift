import XCTest
import AVKit
@testable import VideoStreamTracker

final class VideoStreamTrackerTests: XCTestCase {
    func testInitialization() throws {
        let player = AVPlayer()
        let tracker = AVPlayerEventLogger(player: player, eventSinkUrl: URL(string: "https://example.com/sink")!)
        XCTAssertNotNil(tracker)
    }

    // MARK: - isLiveStream

    func testIsLiveStreamIndefiniteReturnsTrue() {
        // Live streams surface an indefinite CMTime -> live.
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.indefinite))
    }

    func testIsLiveStreamInvalidReturnsTrue() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.invalid))
    }

    func testIsLiveStreamPositiveInfinityReturnsTrue() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.positiveInfinity))
    }

    func testIsLiveStreamNaNSecondsReturnsTrue() {
        // A CMTime whose .seconds evaluates to NaN must still map to live, not VOD.
        let nanTime = CMTime(value: 0, timescale: 0)
        XCTAssertTrue(nanTime.seconds.isNaN)
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(nanTime))
    }

    func testIsLiveStreamFiniteDurationReturnsFalse() {
        // VOD content exposes a finite, numeric duration -> not live.
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(tenSeconds))
    }

    func testIsLiveStreamZeroLengthReturnsFalse() {
        // A genuine 0-length (finite) item is still VOD, not live.
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(.zero))
    }

    // MARK: - normalizeDuration

    func testNormalizeDurationIndefiniteReturnsMinusOne() {
        // Live / indefinite streams surface an indefinite CMTime; spec requires -1 (unknown).
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.indefinite), -1)
    }

    func testNormalizeDurationInvalidReturnsMinusOne() {
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.invalid), -1)
    }

    func testNormalizeDurationPositiveInfinityReturnsMinusOne() {
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.positiveInfinity), -1)
    }

    func testNormalizeDurationNaNSecondsReturnsMinusOne() {
        // A CMTime whose .seconds evaluates to NaN must still map to unknown, not 0.
        let nanTime = CMTime(value: 0, timescale: 0)
        XCTAssertTrue(nanTime.seconds.isNaN)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(nanTime), -1)
    }

    func testNormalizeDurationZeroLengthReturnsZero() {
        // A genuine 0-length item stays 0 (must NOT be conflated with unknown).
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(.zero), 0)
    }

    func testNormalizeDurationFiniteReturnsMilliseconds() {
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(tenSeconds), 10_000)
    }

    func testNormalizeDurationFractionalFiniteReturnsMilliseconds() {
        let time = CMTime(seconds: 1.5, preferredTimescale: 600)
        XCTAssertEqual(AVPlayerEventLogger.normalizeDuration(time), 1_500)
    }

    // MARK: - isLiveStream

    func testIsLiveStreamIndefiniteIsLive() {
        // Live streams surface an indefinite duration.
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.indefinite))
    }

    func testIsLiveStreamPositiveInfinityIsLive() {
        XCTAssertTrue(AVPlayerEventLogger.isLiveStream(.positiveInfinity))
    }

    func testIsLiveStreamFiniteIsNotLive() {
        let tenSeconds = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(tenSeconds))
    }

    func testIsLiveStreamZeroLengthIsNotLive() {
        XCTAssertFalse(AVPlayerEventLogger.isLiveStream(.zero))
    }

    // MARK: - liveEdgeUTCMilliseconds

    func testLiveEdgeUTCMillisecondsNilReturnsMinusOne() {
        // Live edge indeterminable -> unknown (-1), mirroring the normalizeDuration contract.
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: nil), -1)
    }

    func testLiveEdgeUTCMillisecondsReturnsUTCMilliseconds() {
        // Spec: Live `duration` is the live edge as UTC wall-clock time in milliseconds.
        let date = Date(timeIntervalSince1970: 1_634_911_668.339)
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: date), 1_634_911_668_339)
    }

    func testLiveEdgeUTCMillisecondsEpochReturnsZero() {
        XCTAssertEqual(AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: Date(timeIntervalSince1970: 0)), 0)
    }
}

// MARK: - Test helpers

final class CapturingLogger: EventLogging {
    var events: [[String: Any]] = []
    func log(_ payload: [String: Any]) { events.append(payload) }
    func events(named name: String) -> [[String: Any]] {
        events.filter { $0["event"] as? String == name }
    }
}

// MARK: - stopped reason (#40)

final class StoppedReasonTests: XCTestCase {
    func testStoppedCarriesStringReasonNeverNull() throws {
        let capture = CapturingLogger()
        let sender = AnalyticsEventSender(logger: capture)
        sender.sendInitEvent(expectedStartTime: 0)
        sender.sendLoadingEvent()
        sender.sendLoadedEvent(playhead: 0, duration: 10_000)
        sender.sendPlayingEvent(playhead: 0, duration: 10_000)
        sender.sendStoppedEvent(playhead: 10_000, duration: 10_000, reason: .ended)

        let stopped = try XCTUnwrap(capture.events(named: "stopped").last)
        let payload = try XCTUnwrap(stopped["payload"] as? [String: Any])
        XCTAssertEqual(payload["reason"] as? String, "ended")

        // Serialised JSON must not contain a null reason.
        let json = String(data: try JSONSerialization.data(withJSONObject: stopped), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("null"), json)
    }

    func testStopReasonValuesMatchEPAS() {
        XCTAssertEqual(StopReason.ended.rawValue, "ended")
        XCTAssertEqual(StopReason.error.rawValue, "error")
        XCTAssertEqual(StopReason.aborted.rawValue, "aborted")
        XCTAssertEqual(StopReason.unknown.rawValue, "unknown")
    }

    func testStopTrackingSendsOneAbortedStopped() throws {
        let capture = CapturingLogger()
        var tracker: AVPlayerEventLogger? = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        tracker?.stopTracking()
        tracker?.stopTracking()
        tracker = nil  // deinit must not send a second stopped

        let stopped = capture.events(named: "stopped")
        XCTAssertEqual(stopped.count, 1)
        let payload = try XCTUnwrap(stopped.first?["payload"] as? [String: Any])
        XCTAssertEqual(payload["reason"] as? String, "aborted")
    }

    func testReleasingTrackerSendsAbortedStopped() {
        let capture = CapturingLogger()
        var tracker: AVPlayerEventLogger? = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        XCTAssertNotNil(tracker)
        tracker = nil
        XCTAssertEqual(capture.events(named: "stopped").count, 1)
    }
}

final class PlayheadTests: XCTestCase {
    func testUnknownPlayheadIsMinusOneNotACrash() {
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(.invalid), -1)
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(.indefinite), -1)
        XCTAssertEqual(AVPlayerEventLogger.playheadMilliseconds(CMTime(seconds: 1.5, preferredTimescale: 600)), 1500)
    }
}

// MARK: - kbps (#43)

final class BitrateConversionTests: XCTestCase {
    func testKbpsConvertsAndRounds() {
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: 649_048), 649)
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: 3_306_586), 3307)
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: 136_413.56), 136)
    }

    func testKbpsUnknownValuesMapToZero() {
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: -1), 0)
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: .nan), 0)
        XCTAssertEqual(AVPlayerEventLogger.kbps(fromBps: .infinity), 0)
    }
}

// MARK: - deviceType / deviceModel (#42)

final class DeviceTypeTests: XCTestCase {
    func testModelIdentifierMapsToDeviceClass() {
        XCTAssertEqual(AnalyticsEventSender.deviceType(forModelIdentifier: "iPhone18,1"), "mobile")
        XCTAssertEqual(AnalyticsEventSender.deviceType(forModelIdentifier: "iPod9,1"), "mobile")
        XCTAssertEqual(AnalyticsEventSender.deviceType(forModelIdentifier: "iPad16,3"), "tablet")
        XCTAssertEqual(AnalyticsEventSender.deviceType(forModelIdentifier: "AppleTV14,1"), "tv")
        XCTAssertEqual(AnalyticsEventSender.deviceType(forModelIdentifier: "Mac14,2"), "desktop")
        XCTAssertNil(AnalyticsEventSender.deviceType(forModelIdentifier: "arm64"))
    }

    func testDeviceFieldsNeverReportCPUArchitecture() {
        let fields = AnalyticsEventSender.deviceFields
        XCTAssertNotEqual(fields["deviceType"] as? String, "arm64")
        XCTAssertNotEqual(fields["deviceModel"] as? String, "arm64")
        XCTAssertNotNil(fields["deviceType"])
    }
}

// MARK: - init first, metadata after the item is ready (#41)

/// Answers each request after a delay taken from the request body's event name, and records
/// the order in which responses complete.
final class DelayedStubProtocol: URLProtocol {
    nonisolated(unsafe) static var completed: [String] = []
    nonisolated(unsafe) static var delays: [String: TimeInterval] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        } ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let event = json?["event"] as? String ?? "?"
        let delay = DelayedStubProtocol.delays[event] ?? 0
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            DelayedStubProtocol.lock.lock(); DelayedStubProtocol.completed.append(event); DelayedStubProtocol.lock.unlock()
            let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data("{}".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class EventOrderTests: XCTestCase {
    func testEventsReachTheSinkInTheOrderTheyWereLogged() {
        DelayedStubProtocol.completed = []
        DelayedStubProtocol.delays = ["init": 0.3]  // a slow init must still arrive first
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedStubProtocol.self]
        let logger = EventSinkPlayerLogger(endpoint: URL(string: "https://sink.test/")!, session: URLSession(configuration: config))

        logger.log(["event": "init"])
        logger.log(["event": "loading"])
        logger.log(["event": "metadata"])

        let deadline = Date().addingTimeInterval(5)
        while DelayedStubProtocol.completed.count < 3 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(DelayedStubProtocol.completed, ["init", "loading", "metadata"])
    }

    func testInitIsFirstAndNoMetadataBeforeTheItemIsReady() {
        let capture = CapturingLogger()
        let tracker = AVPlayerEventLogger(player: AVPlayer(), logger: capture)
        XCTAssertEqual(capture.events.first?["event"] as? String, "init")
        XCTAssertTrue(capture.events(named: "metadata").isEmpty)
        _ = tracker
    }

    func testMetadataOmitsUnknownValuesInsteadOfNull() throws {
        let capture = CapturingLogger()
        let sender = AnalyticsEventSender(logger: capture)
        sender.sendMetadataEvent(isLive: nil, contentTitle: nil)
        let event = try XCTUnwrap(capture.events(named: "metadata").first)
        let payload = try XCTUnwrap(event["payload"] as? [String: Any])
        XCTAssertNil(payload["live"])
        XCTAssertNil(payload["contentTitle"])
        let json = String(data: try JSONSerialization.data(withJSONObject: event), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("null"), json)
    }

    func testMetadataReportsVODAndLive() throws {
        let capture = CapturingLogger()
        let sender = AnalyticsEventSender(logger: capture)
        sender.sendMetadataEvent(isLive: AVPlayerEventLogger.isLiveStream(CMTime(seconds: 63, preferredTimescale: 600)), contentTitle: nil)
        sender.sendMetadataEvent(isLive: AVPlayerEventLogger.isLiveStream(.indefinite), contentTitle: nil)
        let lives = capture.events(named: "metadata").compactMap { ($0["payload"] as? [String: Any])?["live"] as? Bool }
        XCTAssertEqual(lives, [false, true])
    }
}
