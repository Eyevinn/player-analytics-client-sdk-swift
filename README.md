# player-analytics-client-sdk-swift
### a.k.a. VideoStreamTracker

This is a Swift SDK package for the Eyevinn Player Analytics Service.

The Swift SDK uses the [Eyevinn Player Analytics Eventsink](https://app.osaas.io/dashboard/service/eyevinn-player-analytics-eventsink) to send events and it is easily added to your project through the [Swift Package Manager](https://swift.org/package-manager/).

You can read more about Eyevinn Open Source Cloud [here](https://docs.osaas.io/osaas.wiki/Home.html).

----

The easiest way to get started is to add the SDK to your project using the Swift Package Manager.

### Adding the SDK to you project.
Click on `File` -> `Swift Packages` -> `Add Package Dependency...` and add the following URL: https://github.com/Eyevinn/player-analytics-client-sdk-swift

### Usage
```swift
import VideoStreamTracker
..
    private let player = AVPlayer(url: URL(string: "https://path/to/video.m3u8")!)
    private  var logger: AVPlayerEventLogger 

let logger = AVPlayerEventLogger(
    player: player,
    eventSinkUrl: URL(string: "https://eventsink.osaas.io")!)

...
    var body: some View {
        VStack {
            VideoPlayer(player: player)                VideoPlayer(player:player) 

            Button("Play") {
                player.play()
            }
            Button("Pause") {
                player.pause()
            }
        }
        .padding()
    }
}
