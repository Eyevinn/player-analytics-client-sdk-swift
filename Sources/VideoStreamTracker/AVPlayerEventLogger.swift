//
//  AvPlayerEventLogger.swift
//  VideoStreamTracker
//
//  Created by Kasper Blom on 2025-03-19.
//

import Foundation
import AVFoundation

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
        case bitrateChanged(Double)
        case errorOccurred(String)
        case warning(String)

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
            case .bitrateChanged(let bitrate):
                return "Bitrate Changed: \(bitrate) bps"
            case .errorOccurred(let errorMsg):
                return "Error: \(errorMsg)"
            case .warning(let warningMsg):
                return "Warning: \(warningMsg)"
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
        guard let duration = player.currentItem?.duration.seconds, duration > 0 else { return 0 }
        return Int64(duration * 1000)
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
        sendAnalytics(for:.initEvent)
        sendAnalytics(for:.loading)
        setupObservers()
        setupNotifications()
        setupMetadataTracking()
    }

    deinit {
        removeObservers()
    }

    // MARK: - Setup Observers

    private func setupObservers() {
        // Observe the currentItem's status to determine when it is ready.
        playerStatusObservation = player.observe(\.currentItem?.status, options: [.new, .old]) { [weak self] player, _ in
            guard let self = self else { return }
            switch player.currentItem?.status {
            case .unknown:
                sendAnalytics(for:.loading)
            case .readyToPlay:
                sendAnalytics(for:.loaded)
            case .failed:
                let errorMsg = player.currentItem?.error?.localizedDescription ?? "Unknown error"
                sendAnalytics(for:.errorOccurred(errorMsg))
            default:
                break
            }
        }

        // Observe timeControlStatus (playing, paused, buffering).
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new, .old]) { [weak self] player, _ in
            guard let self = self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.startHeartbeatTimer()
                sendAnalytics(for:.playing)
            case .paused:
                sendAnalytics(for:.paused)
            case .waitingToPlayAtSpecifiedRate:
                sendAnalytics(for:.buffering)
            @unknown default:
                break
            }
        }

        // Observe buffering status.
        if let item = player.currentItem {
            bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, change in
                if let isEmpty = change.newValue, isEmpty {
                    self?.sendAnalytics(for:.buffering)
                }
            }

            keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, change in
                if let likelyToKeepUp = change.newValue, likelyToKeepUp {
                    self?.sendAnalytics(for:.buffered)
                }
            }
        }
    }

    // MARK: - Setup Notifications

    private func setupNotifications() {
        // Playback ended.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(playbackDidEnd(notification:)),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: player.currentItem)

        // Logs from the player item access log.
        accessLogObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewAccessLogEntry,
                                                                   object: player.currentItem,
                                                                   queue: .main) { [weak self] _ in
            self?.processAccessLog()
        }

        // Logs from the player item error log.
        errorLogObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry,
                                                                  object: player.currentItem,
                                                                  queue: .main) { [weak self] _ in
            self?.processErrorLog()
        }

        // Observe time jumps.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(timeJumped(_:)),
                                               name: .AVPlayerItemTimeJumped,
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
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendAnalytics(for:.heartbeat)
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
            analytics.sendLoadedEvent(playhead: currentPlayhead,
                                duration: totalDuration)

        case .playing:
            analytics.sendPlayingEvent(playhead: currentPlayhead,
                                       duration: totalDuration)

        case .paused:
            analytics.sendPausedEvent(playhead: currentPlayhead,
                                      duration: totalDuration)

        case .stopped:
            analytics.sendStoppedEvent(playhead: currentPlayhead,
                                       duration: totalDuration,
                                       reason: nil)

        case .buffering:
            analytics.sendBufferingEvent(playhead: currentPlayhead,
                                         duration: totalDuration)

        case .buffered:
            analytics.sendBufferedEvent(playhead: currentPlayhead,
                                duration: totalDuration)

        case .metadata(let info):
            analytics.sendMetadataEvent(isLive: false,
                                        contentTitle: info)

        case .heartbeat:
            analytics.sendHeartbeatEvent(playhead: currentPlayhead,
                                         duration: totalDuration)

        case .seeking(let time):
            let seekPlayhead = Int64(time.seconds * 1000)
            analytics.sendSeekingEvent(playhead: seekPlayhead,
                                       duration: totalDuration)

        case .seeked(let time):
            let payload: [String: Any] = ["seekedTime": time.seconds]
            analytics.sendSeekedEvent(playhead: currentPlayhead,
                                duration: totalDuration,
                                payload: payload)

        case .bitrateChanged(let bitrate):
            let payload: [String: Any] = ["bitrate": bitrate]
            analytics.sendBitrateChangedEvent(playhead: currentPlayhead,
                                duration: totalDuration,
                                payload: payload)

        case .errorOccurred(let errorMsg):
            analytics.sendErrorEvent(playhead: currentPlayhead,
                                     duration: totalDuration,
                                     category: "AVPlayerError",
                                     code: nil,
                                     message: errorMsg)

        case .warning(let warningMsg):
            let payload: [String: Any] = ["warning": warningMsg]
            analytics.sendWarningEvent(playhead: currentPlayhead,
                                duration: totalDuration,
                                payload: payload)
        }
    }

    // MARK: - Notification Handlers

    @objc private func playbackDidEnd(notification: Notification) {
        stopHeartbeatTimer()
        sendAnalytics(for:.stopped)
    }

    @objc private func timeJumped(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        let currentTime = item.currentTime()
        sendAnalytics(for:.seeked(currentTime))
    }

    private func processAccessLog() {
        guard let accessLog = player.currentItem?.accessLog(),
              let lastEvent = accessLog.events.last else { return }

        let avgAudioBitrate = lastEvent.averageAudioBitrate
        #if os(watchOS)
        let avgVideoBitrate = 0
        #else
        let avgVideoBitrate = lastEvent.averageVideoBitrate
        #endif
        let evt = lastEvent
        sendAnalytics(for:.bitrateChanged(lastEvent.indicatedBitrate))
    }

    private func processErrorLog() {
        guard let errorLog = player.currentItem?.errorLog(),
              let lastError = errorLog.events.last else { return }
        let errorMsg = lastError.errorComment ?? "Unknown error"
        sendAnalytics(for:.errorOccurred(errorMsg))
    }

    /// Seek operation that logs before and after the seek.
    public func seek(to time: CMTime, completion: ((Bool) -> Void)? = nil) {
        sendAnalytics(for:.seeking(time))
        player.seek(to: time) { [weak self] finished in
            self?.sendAnalytics(for:.seeked(time))
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
    public func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                               didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                               from track: AVPlayerItemTrack?) {
        // Example: Log metadata events.
        for group in groups {
            for metadataItem in group.items {
                if let value = metadataItem.value(forKey: "value") {
                    sendAnalytics(for:.warning("Metadata: \(value)"))
                }
            }
        }
    }
}

extension AVPlayerEventLogger: @unchecked Sendable {}

