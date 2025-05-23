import AVKit
import Combine
import Foundation
import AVFoundation

public final class SGAIPlayerViewModel: ObservableObject {
    @Published public var isAdPlaying: Bool = false
    @Published public var adDuration: Double = 0.0
    @Published public var adProgressEvent: AdActivityEvent?

    public let player: AVPlayer
    private var cancellables = Set<AnyCancellable>()
    private var timers: [Timer] = []

    public init(player: AVPlayer) {
        self.player = player

        let observer = AVPlayerInterstitialEventMonitor(primaryPlayer: player)

//        NotificationCenter.default.publisher(for: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification, object: observer)
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] _ in
//                self?.handleInterstitialEvent(observer.currentEvent)
//            }
//            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification, object: observer)
            .map { _ in observer.currentEvent }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleInterstitialEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleInterstitialEvent(_ event: AVPlayerInterstitialEvent?) {

        if let event = event {
            // Ad started
            var duration = 0.0
            if #available(iOS 18.0, *) {
                duration = event.plannedDuration.seconds
            }
            isAdPlaying = true
            adDuration = duration
            adProgressEvent = .started
            scheduleAdProgressTimers(duration: duration)
        } else {
            // Ad ended
            isAdPlaying = false
            adDuration = 0.0
            adProgressEvent = .complete
            invalidateAdProgressTimers()
        }
    }

    private func scheduleAdProgressTimers(duration: Double) {
        invalidateAdProgressTimers()

        let intervals: [(TimeInterval, AdActivityEvent)] = [
            (duration / 4, .firstQuartile),
            (duration / 2, .midPoint),
            (3 * duration / 4, .thirdQuartile)
        ]

        for (interval, event) in intervals {
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                guard let self = self, self.isAdPlaying else { return }
                self.adProgressEvent = event
            }
            timers.append(timer)
        }
    }

    private func invalidateAdProgressTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
