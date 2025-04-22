# player-analytics-client-sdk-swift
### a.k.a. VideoStreamTracker

This is a Swift SDK package for the Eyevinn Player Analytics Specification (EPAS).

The Swift SDK uses the [Eyevinn Player Analytics Eventsink](https://app.osaas.io/dashboard/service/eyevinn-player-analytics-eventsink) to send events and it is easily added to your project through the [Swift Package Manager](https://swift.org/package-manager/).

You can read more about Eyevinn Open Source Cloud [here](https://docs.osaas.io/osaas.wiki/Home.html).

----

The easiest way to get started is to add the SDK to your project using the Swift Package Manager.

### Adding the SDK to you project.
Click on `File` -> `Swift Packages` -> `Add Package Dependency...` and add the following URL: https://github.com/Eyevinn/player-analytics-client-sdk-swift

### Usage
```swift
...

import VideoStreamTracker

...

    private let player = AVPlayer(url: URL(string: "https://path/to/video.m3u8")!)
    private var logger: AVPlayerEventLogger

...

let logger = AVPlayerEventLogger(
    player: player,
    eventSinkUrl: URL(string: "https://eventsink.osaas.io")!)

...

    var body: some View {
        VStack {
            VideoPlayer(player: player)

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
```
### Demo project
There is a demo-project included in the repository. You can run it by opening the `SEPA_Demo.xcodeproj` file in Xcode. The demo project is a simple SwiftUI app that uses the SDK to send events to the Eyevinn Player Analytics Eventsink.

# About Eyevinn
We are [Eyevinn Technology](https://www.eyevinntechnology.se/), and we help companies in the TV, media, and entertainment sectors optimize costs and boost profitability through enhanced media solutions. We are independent in a way that we are not commercially tied to any platform or technology vendor. As our way to innovate and push the industry forward, we develop proof-of-concepts and tools. We share things we have learn and code as open-source.

With Eyevinn Open Source Cloud we enable to build solutions and applications based on Open Web Services and avoid being locked in with a single web service vendor. Our open-source solutions offer full flexibility with a revenue share model that supports the creators.

Read our blogs and articles here:

- [Developer blogs](https://dev.to/video)
- [Medium](https://eyevinntechnology.medium.com/)
- [OSC](https://osaas.io/)
- [LinkedIn](https://www.linkedin.com/company/eyevinn/)

Want to know more about Eyevinn, contact us at [info@eyevinn.se](mailto:info@eyevinn.se)!
