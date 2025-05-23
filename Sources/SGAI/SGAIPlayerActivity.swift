import AVKit
import AVFoundation
import Foundation

protocol SGAIActivityDelegate: AnyObject {
    func adStarted(_ duration: Double)
    func adEnded()
    func adProgress(_ progress: AdActivityEvent)
}

public final class PlayerActivityHandler {
    weak var delegate: SGAIActivityDelegate?

    private var startTime: Date?
    private var adPlaying = false

    let player:  AVPlayer

    public init(player: AVPlayer) {
        self.player = player

        let observer = AVPlayerInterstitialEventMonitor(primaryPlayer: player)
        NotificationCenter.default.addObserver(
            forName: AVPlayerInterstitialEventMonitor.currentEventDidChangeNotification,
            object: observer,
            queue: OperationQueue.main) {
                notification_ in
                self.updateUI(observer.currentEvent)
            }
    }

    private func updateUI(_ event: AVPlayerInterstitialEvent?) {
        var adStatus = ""
        var adDuration = 0.0
        if let eventId = event?.identifier {
            adStatus = "🔴 Ad Playing: \(event?.identifier ?? "Unknown")"
            print("-> Ad started: \(eventId) - \(Date().description)")
            self.adPlaying = true

            if #available(iOS 18.0, *) {
                if let duration = event?.plannedDuration {
                    adDuration = duration.seconds
                }
            }

            delegate?.adStarted(adDuration)

            _ = Timer.scheduledTimer(withTimeInterval: adDuration / 4, repeats: false) { [self] _ in
                if self.adPlaying {
                    print("+---Ad Q1")
                    delegate?.adProgress(.firstQuartile)
                }
            }
            _ = Timer.scheduledTimer(withTimeInterval: adDuration / 2, repeats: false) { [self] _ in
                if self.adPlaying {
                    print("++--Ad Q2")
                    self.delegate?.adProgress(.midPoint)
                }
            }
            _ = Timer.scheduledTimer(withTimeInterval: (adDuration / 4) * 3, repeats: false) { [self] _ in
                if self.adPlaying {
                    print("+++-Ad Q3")
                    delegate?.adProgress(.thirdQuartile)
                }
            }
        } else {
            if self.adPlaying {
                print("<- Ad ended: - \(Date().description)")
                self.adPlaying = false
            }
            adStatus = "🟢 Ad ended"
            delegate?.adEnded()
            delegate?.adProgress(.complete)
        }
    }
}
