# Requirements: setup documentation for `player-analytics-client-sdk-swift`

Status: requirements clarification for issue #24 (split from #15, which had an empty body).
This document does **not** write the setup docs themselves — it captures, grounded in the
current code, exactly what the eventual setup documentation must cover so the doc-writing issue
(#15) can be re-triaged for readiness.

All statements below are grounded in the repository as it stands on this branch:
`Package.swift`, `README.md`, `Sources/VideoStreamTracker/`, and `Sample/EPAS_Demo/`.

---

## 1. Terminology: what "SGAI" means here, and what it does *not* yet mean for setup

"SGAI" throughout this repo is a generic term for **server-guided ad insertion** — the pattern
where the HLS manifest itself carries ad-signaling cues (`#EXT-X-DATERANGE` with `X-ASSET-LIST`
for live or `X-ASSET-URI` for VoD) that reference an asset-list JSON of ad creatives and their
per-event tracking URLs. See `Sources/VideoStreamTracker/SGAIManifestParser.swift` and the
asset-list JSON shape documented at the top of
`Sources/VideoStreamTracker/SGAIAdTrackingUrls.swift`.

Important grounding for the setup docs: **the SGAI capability is currently `internal`, not part
of the public API.** Every SGAI type is declared `internal`:

- `SGAIManifestParser` / `SGAIDateRange` — `internal enum` / `internal struct`
- `SGAIAdTrackingUrlsExtractor`, `SGAIAssetListFetching`, `SGAIURLSessionFetcher` — `internal`
- `SGAIAdTrackingUrls`, `SGAIAssetList` — `internal struct`
- `SGAIAdTrackingEvent` — `internal enum`

The SGAI source headers state the scope explicitly, e.g. in `SGAIManifestParser.swift`:
"No AVPlayer wiring (issue #20) and no public API (issue #21) — everything here is `internal`."
The same "no public API (issue #21)" note appears in `SGAIAdTrackingUrlsExtractor.swift` and
`SGAIAdTrackingUrls.swift`.

**Requirement R1 — scope SGAI correctly in the docs.** The setup documentation must NOT present
SGAI ad-tracking as a consumer-facing setup step, because no public API exposes it yet. It should
either (a) omit SGAI from integrator setup entirely, or (b) mention it only as an in-progress
internal capability (manifest parsing + asset-list tracking-URL extraction, mirroring the Android
SDK) that is not yet callable by integrators, deferring integrator-facing SGAI setup to whichever
issue makes that surface `public` (referenced in-code as #20/#21). Do not document a setup flow
for an API that does not exist.

---

## 2. What the setup docs must actually cover (the public capability today)

The public, integrator-callable surface is small and centres on one class,
`AVPlayerEventLogger` (`Sources/VideoStreamTracker/AVPlayerEventLogger.swift`):

- `public init(player: AVPlayer, eventSinkUrl url: URL)` — attaching the logger to an existing
  `AVPlayer` starts tracking automatically (the initializer sends `init` / `loading` / `metadata`
  and installs the observers). Documented in the initializer's own doc comment: "By instantiating
  this class, you will start tracking events from the AVPlayer".
- `public func report(payload: [String: Any]?)` — sends a custom `report` (plus `metadata`) event.
- `public func seek(to time: CMTime, completion: ((Bool) -> Void)? = nil)` — a seek wrapper that
  emits `seeking` / `seeked` events around the underlying `player.seek`.

Supporting public type: `EventSinkPlayerLogger(endpoint: URL)`
(`Sources/VideoStreamTracker/EventSinkPlayerLogger.swift`) — the HTTP transport that POSTs each
event as JSON to the event sink. Integrators do not normally instantiate it directly; the
`AVPlayerEventLogger` initializer builds it internally from `eventSinkUrl`.

Events emitted automatically (from `AVPlayerEventLogger` observers, mapped through
`AnalyticsEventSender`): `init`, `loading`, `loaded`, `playing`, `paused`, `buffering`,
`buffered`, `stopped`, `heartbeat` (30s interval — `heartbeatInterval = 30.0`), `seeking`,
`seeked`, `bitrate_changed`, `metadata`, `error`, `warning`, `report`.

**Requirement R2 — the setup docs must, at minimum, cover this integrator flow:**
1. Add the package (Swift Package Manager URL — see R4).
2. `import VideoStreamTracker`.
3. Construct an `AVPlayer` for an HLS (`.m3u8`) source.
4. Create and **retain** an `AVPlayerEventLogger(player:eventSinkUrl:)` — retention matters
   because the logger deregisters its observers in `deinit`; if it is not held, tracking stops.
5. Point `eventSinkUrl` at a Player Analytics Event Sink endpoint.
6. (Optional) call `report(payload:)` for custom events and `seek(to:completion:)` for tracked
   seeks.

---

## 3. Target audience and the distinction the docs must keep

There are two distinct audiences, and existing docs already serve one of them:

- **Integrators** (apps consuming the SDK): need the "add package → import → init logger →
  point at event sink" flow. The README already has a minimal "Adding the SDK to you project"
  + "Usage" block (`README.md`, around the `AVPlayerEventLogger(player:eventSinkUrl:)` snippet)
  and a "Demo project" pointer.
- **Contributors** (working on the SDK itself): the README already carries a full
  "Development setup" section (prerequisites, `swift build`, `swift test`, running the sample,
  project layout) added in PR #33.

**Requirement R3 — do not duplicate or contradict the existing "Development setup" section.**
The new setup documentation is **integrator-facing** and must be reconciled against what the
README already says. It should expand the existing "Usage" material into a complete, correct
integrator setup guide (see R2), not re-document the contributor `swift build`/`swift test`
workflow that PR #33 already covers.

---

## 4. Where the docs should live and how they should be structured

Current state: there is **no `docs/` folder** other than this requirements file, and integrator
setup currently lives as short sections inside `README.md`. The README's integrator snippets are
also slightly out of date with the code style (the README init omits the `eventSinkUrl` argument
label wrapping used in the Sample; the Sample uses `AVPlayerEventLogger(player:eventSinkUrl:)`
with `report(payload:)` examples — see `Sample/EPAS_Demo/ContentView.swift`).

**Requirement R4 — placement.** Prefer expanding the integrator setup **in `README.md`** (this is
where discovery happens and where the existing Usage/Dev-setup sections already are), OR add a
dedicated `docs/setup.md` linked from the README. Do not scatter setup across both without a link
between them. Whichever is chosen, keep the SPM install instructions authoritative: package URL
`https://github.com/Eyevinn/player-analytics-client-sdk-swift`, `swift-tools-version: 6.0`,
platforms iOS 13+/tvOS 13+, no external dependencies (`dependencies: []` in `Package.swift`).

**Requirement R5 — section structure.** The integrator setup doc should contain, in order:
1. Overview (what the SDK does: emits EPAS events from an `AVPlayer` to an event sink).
2. Requirements (see R6).
3. Installation (Swift Package Manager, package URL above).
4. Quick start (the minimal code sample — see R7).
5. Configuration (event sink URL; heartbeat interval is fixed at 30s and not currently
   configurable — state that rather than implying it is tunable).
6. Custom events / advanced usage (`report(payload:)`, `seek(to:completion:)`).
7. Sample app pointer (`Sample/EPAS_Demo.xcodeproj`).
8. (Optional/deferred) note on SGAI status per R1.

---

## 5. Prerequisites, configuration, and code samples the docs must include

**Requirement R6 — prerequisites (all grounded in `Package.swift`):**
- Swift tools 6.0 (`swift-tools-version: 6.0`).
- Deployment targets iOS 13+ / tvOS 13+ (`platforms: [.iOS(.v13), .tvOS(.v13)]`).
- A reachable Player Analytics Event Sink HTTP endpoint that accepts `POST` of JSON events
  (`EventSinkPlayerLogger.log(_:)` POSTs `Content-Type: application/json`).
- An HLS source URL (the Sample and README both use `.m3u8`).
- No third-party dependencies to install (`dependencies: []`).

**Requirement R7 — the canonical code sample must match the real signatures.** Use the same
shape as `Sample/EPAS_Demo/ContentView.swift`, i.e.:

```swift
import SwiftUI
import AVKit
import VideoStreamTracker

struct ContentView: View {
    private let player = AVPlayer(url: URL(string: "https://.../video.m3u8")!)
    private var eventLogger: AVPlayerEventLogger

    init() {
        eventLogger = AVPlayerEventLogger(
            player: player,
            eventSinkUrl: URL(string: "https://.../eventsink")!)
    }

    var body: some View {
        VStack {
            VideoPlayer(player: player)
            Button("Play")  { player.play() }
            Button("Pause") { player.pause() }
        }
    }
}
```

The sample must (a) retain the logger for the view's lifetime (see R2 step 4), (b) use real
argument labels `player:` and `eventSinkUrl:`, and (c) if it shows custom events, use
`eventLogger.report(payload: ["MyEvent": ...])` exactly as `ContentView.swift` does. Do not
invent configuration parameters (e.g. session ID, batching, or heartbeat overrides) — none exist
in the public API; `sessionId` is generated internally in `AnalyticsEventSender`.

---

## 6. Sibling-repo question (web / android / specification)

Per the team `CLAUDE.md`, **this issue is scoped to the Swift SDK only.** No documentation work
in `player-analytics-client-sdk-web`, `player-analytics-client-sdk-android`, or
`player-analytics-specification` is in scope here, and this document asserts none.

For context (not a work item): the SGAI parsing/extraction types in this repo state in their own
headers that they "mirror the Android contract" / "mirror the Android SDK
(`SGAIAdTrackingUrlsExtractor.kt`)" — see `SGAIAdTrackingUrls.swift`,
`SGAIAdTrackingUrlsExtractor.swift`, `SGAIAdTrackingEvent.swift`. So **if** integrator-facing SGAI
setup docs are ever written (after the public-API issue lands), cross-SDK consistency between the
Swift and Android setup docs would matter. That is a note for future triage, not an action this
issue authorizes in any sibling repo.

---

## 7. Readiness checklist for the doc-writing issue (#15)

The follow-up doc issue is ready to implement once it commits to:
- [ ] Integrator-facing scope (R3), not a rewrite of the existing "Development setup" section.
- [ ] SGAI treated per R1 (internal / deferred, not a public setup step).
- [ ] A placement decision per R4 (README expansion or `docs/setup.md` with a link).
- [ ] The section structure in R5.
- [ ] Prerequisites from R6 and a code sample matching the real signatures in R7.
- [ ] Swift-only scope confirmed (Section 6).
