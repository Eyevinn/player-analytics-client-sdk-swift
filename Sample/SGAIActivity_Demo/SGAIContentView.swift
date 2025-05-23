import SwiftUI
import AVKit
import Combine
import SGAI

struct SGAIContentView: View {

    @StateObject public var viewModel = SGAIPlayerViewModel(player: AVPlayer(playerItem: AVPlayerItem(url: URL(string: "https://eyevinnlab-adtracking.eyevinn-sgai-ad-proxy.auto.prod.osaas.io/loop/master.m3u8")!)))

    init() {
    }

    var body: some View {
        VStack {
            if viewModel.isAdPlaying {
                Text("Ad is playing")
                Text("Duration: \(viewModel.adDuration, specifier: "%.2f") seconds")
            } else {
                Text("No ad playing")
            }

            if let progressEvent = viewModel.adProgressEvent {
                Text("Ad Progress: \(progressEvent.rawValue)")
            }
            VideoPlayer(player: viewModel.player)
                .frame(height: 300)

            Button("Play") {
                viewModel.player.play()
            }

            Button("Pause") {
                viewModel.player.pause()
            }
        }
        .padding()
        .onAppear {
            viewModel.player.play()
        }
    }
}
