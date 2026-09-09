//
//  AvPlayerEventLogger.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//

import AVFoundation
import Foundation

public final class AVPlayerEventLogger: NSObject {

    // Internal enum to list events.
    enum PlayerEvent: CustomStringConvertible {
        case initEvent
        case loading
        case loaded
        case playing
        case paused
        case stopped
        case buffering
        case buffered
        case metadata(String)
        case heartbeat
        case seeking(CMTime)
        case seeked(CMTime)
        case bitrateChanged(bitrate: Double, videoBitrate: Double, audioBitrate: Double)
        case errorOccurred(String)
        case warning(String)
        case report([String: Any]?)

        var description: String {
            switch self {
            case .initEvent:
                return "Init: Player ready for load."
            case .loading:
                return "Loading"
            case .loaded:
                return "Loaded"
            case .playing:
                return "Playing"
            case .paused:
                return "Paused"
            case .stopped:
                return "Stopped"
            case .buffering:
                return "Buffering"
            case .buffered:
                return "Buffered"
            case .metadata(let info):
                return "Metadata received: \(info)"
            case .heartbeat:
                return "Heartbeat"
            case .seeking(let time):
                return "Seeking initiated to: \(time.seconds) sec"
            case .seeked(let time):
                return "Seek completed at: \(time.seconds) sec"
            case .bitrateChanged(let bitrate, let videoBitrate, let audioBitrate):
                return "Bitrate Changed: \(bitrate) bps, video: \(videoBitrate) bps, audio: \(audioBitrate) bps"
            case .errorOccurred(let errorMsg):
                return "Error: \(errorMsg)"
            case .warning(let warningMsg):
                return "Warning: \(warningMsg)"
            case .report(let payload):
                return "Report: \(payload)"
            }
        }
    }

    // MARK: - Properties

    private let player: AVPlayer
    private let analytics: AnalyticsEventSender

    // Observers & Notifications
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var accessLogObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?

    // AVPlayerItemMetadataOutput to capture metadata events.
    private let metadataOutput = AVPlayerItemMetadataOutput()

    // Heartbeat Timer (fires, for example, every 5 seconds)
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30.0

    // Helper computed properties for analytics.
    private var currentPlayhead: Int64 {
        Int64(player.currentTime().seconds * 1000)
    }

    private var totalDuration: Int64 {
        guard let duration = player.currentItem?.duration else { return -1 }
        // Spec `duration` for Live content is the live edge expressed as UTC wall-clock time in
        // milliseconds (VOD stays the finite stream length). For live, derive the live edge from
        // the item's `currentDate()`; when it is indeterminable, fall back to -1 (unknown).
        if isLiveContent {
            return AVPlayerEventLogger.liveEdgeUTCMilliseconds(from: player.currentItem?.currentDate())
        }
        return AVPlayerEventLogger.normalizeDuration(duration)
    }

    /// Whether the item duration indicates Live / indefinite content.
    ///
    /// Live streams surface an indefinite (or otherwise non-numeric) `CMTime` duration, which is
    /// exactly the set of values `normalizeDuration` maps to the `-1` unknown sentinel. A finite,
    /// numeric duration is VOD.
    private var isLiveContent: Bool {
        guard let duration = player.currentItem?.duration else { return false }
        return AVPlayerEventLogger.isLiveStream(duration)
    }

    /// Detects Live content from an item duration `CMTime`.
    ///
    /// - Parameter cmTime: The item's duration `CMTime`.
    /// - Returns: `true` when the duration is indefinite / non-numeric / non-finite (Live),
    ///   `false` for a finite, numeric duration (VOD).
    static func isLiveStream(_ cmTime: CMTime) -> Bool {
        guard CMTIME_IS_NUMERIC(cmTime) else { return true }
        return !cmTime.seconds.isFinite
    }

    /// Converts a live-edge wall-clock `Date` into the UTC milliseconds value the spec expects for
    /// the `duration` field of Live content.
    ///
    /// Spec `duration` contract (Live): "live edge in UTC. -1 if unknown". This pure helper is
    /// kept free of any `AVPlayer` dependency so it can be unit-tested directly; the AVPlayer glue
    /// (`player.currentItem?.currentDate()`) stays thin in `totalDuration`.
    ///
    /// - Parameter date: The live-edge wall-clock date, or `nil` when it is indeterminable.
    /// - Returns: `Int64(date.timeIntervalSince1970 * 1000)` (UTC ms) for a determinable, finite
    ///   live edge; `-1` when `nil` or non-finite.
    static func liveEdgeUTCMilliseconds(from date: Date?) -> Int64 {
        guard let interval = date?.timeIntervalSince1970, interval.isFinite else { return -1 }
        return Int64(interval * 1000)
    }

    /// Normalizes an `AVPlayerItem` duration into the milliseconds value expected by the
    /// analytics spec.
    ///
    /// Spec `duration` contract: a finite length is reported in milliseconds, while an
    /// unknown/unavailable duration must be `-1` (never `0`, which is reserved for a genuine
    /// zero-length item). Live / indefinite items report `duration.seconds` as `NaN`, so the
    /// previous `duration > 0` guard incorrectly collapsed both "unknown" and "zero-length"
    /// into `0`.
    ///
    /// - Parameter cmTime: The item's duration `CMTime`.
    /// - Returns: `Int64(seconds * 1000)` for a finite, non-negative duration (0-length stays
    ///   `0`); `-1` for an indefinite, non-numeric, or `NaN` duration.
    static func normalizeDuration(_ cmTime: CMTime) -> Int64 {
        // Indefinite (live edge) or otherwise non-numeric (invalid / infinite) -> unknown.
        guard CMTIME_IS_NUMERIC(cmTime) else { return -1 }
        let seconds = cmTime.seconds
        // Guard against NaN / negative sentinels that survive the numeric check.
        guard seconds.isFinite, seconds >= 0 else { return -1 }
        return Int64(seconds * 1000)
    }

    /// Whether the current item should be reported as live in the metadata event.
    ///
    /// Derived from the current item's duration: a live stream reports an indefinite /
    /// non-numeric duration, whereas VOD reports a finite length. Falls back to `false`
    /// (VOD) when there is no current item.
    private var isLiveContent: Bool {
        guard let duration = player.currentItem?.duration else { return false }
        return AVPlayerEventLogger.isLiveStream(duration)
    }

    /// Determines whether a stream is live from its `AVPlayerItem` duration.
    ///
    /// Spec `metadata.payload.live` contract: `true` for live/dynamic content, `false` for
    /// VOD/static content. AVFoundation surfaces live/indefinite items with a duration that
    /// is either explicitly indefinite or otherwise non-numeric (invalid/infinite), and their
    /// `duration.seconds` evaluates to `NaN`. A VOD item exposes a finite, numeric duration.
    ///
    /// Kept pure and `CMTime`-based (no `AVPlayer` dependency) so it is unit-testable off-device,
    /// mirroring how #26 structured `normalizeDuration`.
    ///
    /// - Parameter cmDuration: The item's duration `CMTime`.
    /// - Returns: `true` when the duration is indefinite / non-numeric / `NaN` (live);
    ///   `false` for a finite, numeric duration (VOD).
    static func isLiveStream(_ cmDuration: CMTime) -> Bool {
        // Indefinite (live edge) or otherwise non-numeric (invalid / infinite) -> live.
        guard CMTIME_IS_NUMERIC(cmDuration) else { return true }
        // A numeric CMTime can still surface NaN/infinite seconds; treat those as live too.
        return !cmDuration.seconds.isFinite
    }

    private var currentTimestamp: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Initialization

    /// Initialize the event logger with an AVPlayer and a logger.
    /// By instantiating this class, you will start tracking events from the AVPlayer
    /// - Parameters:
    ///   - player: The AVPlayer whose events will be tracked.
    ///   - eventSinkUrl: A URL to your Player Analytics Event sink
    public init(player: AVPlayer, eventSinkUrl url: URL) {
        self.player = player
        self.analytics = AnalyticsEventSender(logger: EventSinkPlayerLogger(endpoint: url))
        super.init()
        // Log init event as soon as logger is created and also loading since we usually don't get that.
        sendAnalytics(for: .initEvent)
        sendAnalytics(for: .loading)
        sendAnalytics(for: .metadata(""))
        setupObservers()
        setupNotifications()
        setupMetadataTracking()
    }

    deinit {
        removeObservers()
    }

    // MARK: - Public API
    public func report(payload: [String: Any]?) {
        sendAnalytics(for: .metadata("Report: \(payload ?? [:])"))
        sendAnalytics(for: .report(payload))
    }
    // MARK: - Setup Observers

    private func setupObservers() {
        // Observe the currentItem's status to determine when it is ready.
        playerStatusObservation = player.observe(\.currentItem?.status, options: [.new, .old]) {
            [weak self] player, _ in
            guard let self = self else { return }
            switch player.currentItem?.status {
            case .unknown:
                sendAnalytics(for: .loading)
            case .readyToPlay:
                sendAnalytics(for: .loaded)
            case .failed:
                let errorMsg = player.currentItem?.error?.localizedDescription ?? "Unknown error"
                sendAnalytics(for: .errorOccurred(errorMsg))
            default:
                break
            }
        }

        // Observe timeControlStatus (playing, paused, buffering).
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new, .old]) {
            [weak self] player, _ in
            guard let self = self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.startHeartbeatTimer()
                sendAnalytics(for: .playing)
            case .paused:
                sendAnalytics(for: .paused)
            case .waitingToPlayAtSpecifiedRate:
                sendAnalytics(for: .buffering)
            @unknown default:
                break
            }
        }

        // Observe buffering status.
        if let item = player.currentItem {
            bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) {
                [weak self] item, change in
                if let isEmpty = change.newValue, isEmpty {
                    self?.sendAnalytics(for: .buffering)
                }
            }

            keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
                [weak self] item, change in
                if let likelyToKeepUp = change.newValue, likelyToKeepUp {
                    self?.sendAnalytics(for: .buffered)
                }
            }
        }
    }

    // MARK: - Setup Notifications

    private func setupNotifications() {
        // Playback ended.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackDidEnd(notification:)),
            name: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem)

        // Logs from the player item access log.
        accessLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newAccessLogEntryNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.processAccessLog()
        }

        // Logs from the player item error log.
        errorLogObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.processErrorLog()
        }

        // Observe time jumps.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeJumped(_:)),
            name: AVPlayerItem.timeJumpedNotification,
            object: player.currentItem)
    }

    // MARK: - Metadata Tracking

    private func setupMetadataTracking() {
        guard let item = player.currentItem else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.metadataOutput.setDelegate(self, queue: .main)
            if !item.outputs.contains(self.metadataOutput) {
                item.add(self.metadataOutput)
            }
        }
    }

    // MARK: - Heartbeat Implementation

    private func startHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) {
            [weak self] _ in
            self?.sendAnalytics(for: .heartbeat)
        }
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Logging Helpers

    /// Maps PlayerEvent values to AnalyticsEventSender calls for conformity with other platforms.
    private func sendAnalytics(for event: PlayerEvent) {
        switch event {
        case .initEvent:
            // For init events, we use expected start time = 0.
            analytics.sendInitEvent(expectedStartTime: 0)

        case .loading:
            analytics.sendLoadingEvent()

        case .loaded:
            analytics.sendLoadedEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .playing:
            analytics.sendPlayingEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .paused:
            analytics.sendPausedEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .stopped:
            analytics.sendStoppedEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                reason: nil)

        case .buffering:
            analytics.sendBufferingEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .buffered:
            analytics.sendBufferedEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .metadata(let info):
            // Derive live/VOD from the current item rather than hardcoding false. Note: the
            // metadata event is also sent from init before the item's duration is known; in
            // that window `isLiveContent` falls back to false (VOD). The spec allows the
            // server to handle `live` toggling from true to false, so a later, better-informed
            // metadata event can correct an early conservative value.
            analytics.sendMetadataEvent(
                isLive: isLiveContent,
                contentTitle: info)

        case .heartbeat:
            analytics.sendHeartbeatEvent(
                playhead: currentPlayhead,
                duration: totalDuration)

        case .seeking(let time):
            let seekPlayhead = Int64(time.seconds * 1000)
            analytics.sendSeekingEvent(
                playhead: seekPlayhead,
                duration: totalDuration)

        case .seeked(let time):
            let payload: [String: Any] = ["seekedTime": time.seconds]
            analytics.sendSeekedEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                payload: payload)

        case .bitrateChanged(let bitrate, let videoBitrate, let audioBitrate):
            let payload: [String: Any] = ["bitrate": bitrate, "videoBitrate": videoBitrate, "audioBitrate": audioBitrate]
            analytics.sendBitrateChangedEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                payload: payload)

        case .errorOccurred(let errorMsg):
            analytics.sendErrorEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                category: "AVPlayerError",
                code: nil,
                message: errorMsg)

        case .warning(let warningMsg):
            let payload: [String: Any] = ["warning": warningMsg]
            analytics.sendWarningEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                payload: payload)
        case .report(let payload):
            let sendPayload = payload
            analytics.sendReportEvent(
                playhead: currentPlayhead,
                duration: totalDuration,
                payload: sendPayload)

        }
    }

    // MARK: - Notification Handlers

    @objc private func playbackDidEnd(notification: Notification) {
        stopHeartbeatTimer()
        sendAnalytics(for: .stopped)
    }

    @objc private func timeJumped(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        let currentTime = item.currentTime()
        sendAnalytics(for: .seeked(currentTime))
    }

    private func processAccessLog() {
        guard let accessLog = player.currentItem?.accessLog(),
            let lastEvent = accessLog.events.last
        else { return }

        print("###########################")
        print ("Access log: \(accessLog)")
        print("###########################")
        let avgAudioBitrate = lastEvent.averageAudioBitrate

        #if os(watchOS)
            let avgVideoBitrate = 0
        #else
            let avgVideoBitrate = lastEvent.averageVideoBitrate
        #endif
        let evt = lastEvent
        sendAnalytics(for: .bitrateChanged(bitrate: lastEvent.indicatedBitrate, videoBitrate: avgVideoBitrate, audioBitrate: avgAudioBitrate))
    }

    private func processErrorLog() {
        guard let errorLog = player.currentItem?.errorLog(),
            let lastError = errorLog.events.last
        else { return }
        let errorMsg = lastError.errorComment ?? "Unknown error"
        sendAnalytics(for: .errorOccurred(errorMsg))
    }

    /// Seek operation that logs before and after the seek.
    public func seek(to time: CMTime, completion: ((Bool) -> Void)? = nil) {
        sendAnalytics(for: .seeking(time))
        player.seek(to: time) { [weak self] finished in
            self?.sendAnalytics(for: .seeked(time))
            completion?(finished)
        }
    }

    // MARK: - Remove Observers

    private func removeObservers() {
        timeControlStatusObservation?.invalidate()
        playerStatusObservation?.invalidate()
        bufferEmptyObservation?.invalidate()
        keepUpObservation?.invalidate()
        heartbeatTimer?.invalidate()

        if let obs = accessLogObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = errorLogObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - AVPlayerItemMetadataOutputPushDelegate

extension AVPlayerEventLogger: @preconcurrency AVPlayerItemMetadataOutputPushDelegate {

    @MainActor
    public func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        // Example: Log metadata events.
        for group in groups {
            for metadataItem in group.items {
                if let value = metadataItem.value(forKey: "value") {
                    sendAnalytics(for: .metadata("\(value)"))
                }
            }
        }
    }
}

extension AVPlayerEventLogger: @unchecked Sendable {}
