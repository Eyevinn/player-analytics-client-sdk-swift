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
There is a demo-project included in the repository. You can run it by opening the `EPAS_Demo.xcodeproj` file in Xcode. The demo project is a simple SwiftUI app that uses the SDK to send events to the Eyevinn Player Analytics Eventsink.

## Development setup

This section is for contributors working on the SDK itself (not integrators consuming it).

### Prerequisites
- macOS with Xcode 16 or later (the package declares `swift-tools-version: 6.0`).
- A Swift 6 toolchain. Verify with `swift --version`.
- Supported deployment targets are iOS 13+ and tvOS 13+ (see `Package.swift`). The library
  depends on `AVFoundation`/`AVKit`, so building and running the tests requires an Apple
  platform toolchain.

### Getting the source
```sh
git clone https://github.com/Eyevinn/player-analytics-client-sdk-swift.git
cd player-analytics-client-sdk-swift
```

### Building
The package has no external dependencies (`dependencies: []` in `Package.swift`), so a checkout
is ready to build immediately:
```sh
swift build
```

The single library product is `VideoStreamTracker`, built from `Sources/VideoStreamTracker`.

### Running the tests
Unit tests live in `Tests/VideoStreamTrackerTests` and use `XCTest`:
```sh
swift test
```

Because the test target imports `AVKit`, run the tests on macOS (via SwiftPM as above) or from
Xcode with an iOS/tvOS simulator selected (`File` -> `Open...` the package folder, then
`Product` -> `Test`, or `⌘U`).

### Running the sample app
A SwiftUI sample that exercises the SDK against a live Eventsink is included under `Sample/`.
Open `Sample/EPAS_Demo.xcodeproj` in Xcode and run the `EPAS_Demo` scheme on a simulator or
device.

### Project layout
| Path | Contents |
|------|----------|
| `Sources/VideoStreamTracker/` | The library: `AVPlayerEventLogger`, `AnalyticsEventSender`, `EventSinkPlayerLogger`, `StateMachine`. |
| `Tests/VideoStreamTrackerTests/` | `XCTest` unit tests. |
| `Sample/EPAS_Demo.xcodeproj` | SwiftUI demo app. |
| `Package.swift` | Swift Package Manager manifest. |

# About Eyevinn
We are [Eyevinn Technology](https://www.eyevinntechnology.se/), and we help companies in the TV, media, and entertainment sectors optimize costs and boost profitability through enhanced media solutions. We are independent in a way that we are not commercially tied to any platform or technology vendor. As our way to innovate and push the industry forward, we develop proof-of-concepts and tools. We share things we have learn and code as open-source.

With Eyevinn Open Source Cloud we enable to build solutions and applications based on Open Web Services and avoid being locked in with a single web service vendor. Our open-source solutions offer full flexibility with a revenue share model that supports the creators.

Read our blogs and articles here:

- [Developer blogs](https://dev.to/video)
- [Medium](https://eyevinntechnology.medium.com/)
- [OSC](https://blog.osaas.io/)
- [LinkedIn](https://www.linkedin.com/company/eyevinn/)

Want to know more about Eyevinn, contact us at [info@eyevinn.se](mailto:info@eyevinn.se)!
