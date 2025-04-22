//
//  ContentView.swift
//
//  Created by Kasper Blom on 2025-04-22.
//

import SwiftUI
import AVKit
import VideoStreamTracker

private let videoURL = "https://url.to.video.m3u8"
private let eventsinkURL = "https://url.to.eventsink.com"

struct ContentView: View {
    private let player = AVPlayer(url: URL(string: videoURL)!)
    private var eventLogger: AVPlayerEventLogger

    init() {
        eventLogger = AVPlayerEventLogger(player: player, eventSinkUrl: URL(string: eventsinkURL)!)
    }
    var body: some View {
        VStack {
            VideoPlayer(player: player)
                .frame(height: 300)

            Button("Play") {
                player.play()
                eventLogger.report(payload: ["MyStartEvent": Date().timeIntervalSince1970])
            }

            Button("Pause") {
                player.pause()
                // Row below reports a custom event to the event sink.
                eventLogger.report(payload: ["MyPauseEvent": Date().timeIntervalSince1970])
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
