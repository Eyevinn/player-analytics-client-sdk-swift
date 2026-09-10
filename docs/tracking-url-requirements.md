# Tracking-URL enhancement — requirements & scope confirmation

Requirements-clarification note for issue #23, split from #16 during backlog triage. Issue #16
had an empty body and a likely scope mismatch; this note grounds the work in the code that
actually exists in this repo (`player-analytics-client-sdk-swift`, a.k.a. `VideoStreamTracker`)
before any implementation issue is picked up.

This is a documentation-only note. It defines *what* a client-side tracking-URL API in this repo
would mean and points at the existing open feat issues (#20, #21) that already carry the
implementable slices — it deliberately does not duplicate them.

## 1. Scope / repo fit

The #16 title — "Enhance the Ad Normalizer service to in addition to ad creatives also provide
tracking url:s" — describes a **server-side normalizer service**. There is no normalizer service
in this repository. This repo is a Swift/AVFoundation *client SDK*: it consumes an HLS stream via
`AVPlayer` and emits playback-analytics events to the EPAS Eventsink
(`Sources/VideoStreamTracker/AVPlayerEventLogger.swift`, README §Usage). A component that
*produces / rewrites* asset-list JSON with tracking URLs belongs outside this product family (or
to a server-side component), **not** here.

What *does* exist here is the client-side counterpart: code that **consumes** SGAI
(server-guided ad insertion) tracking URLs already present in the HLS manifest / asset-list JSON.
It was landed under the #19 slice and is currently all `internal` (no public surface yet):

- `Sources/VideoStreamTracker/SGAIManifestParser.swift` — parses `#EXT-X-DATERANGE` cues with
  `X-ASSET-LIST` (live) / `X-ASSET-URI` (VoD) into `SGAIDateRange`.
- `Sources/VideoStreamTracker/SGAIAdTrackingUrlsExtractor.swift` — fetches + parses the
  referenced asset-list JSON and stores per-ad tracking URLs in `adTrackingUrlsMap`, keyed
  `pod_<adBreakId>` (pod-level) and `<currentAdsId>_0_<index>` (per-asset).
- `Sources/VideoStreamTracker/SGAIAdTrackingUrls.swift` — the tracking-URL model
  (`urlsByEvent: [String: [String]]`) plus the `Codable` asset-list JSON shape.
- `Sources/VideoStreamTracker/SGAIAdTrackingEvent.swift` — the canonical ad-event names that key
  the model.

**Conclusion:** the only grounded interpretation of a "tracking-URL enhancement" *in this repo*
is a **client-side SGAI tracking-URL API on `AVPlayerEventLogger`** — surfacing and firing the
tracking URLs this SDK already parses. Producing/normalizing tracking URLs server-side is out of
scope for this repo and, if still wanted, should be raised against the correct component (spec,
eventsink, worker, or a separate server-side service outside this SDK family). Issue #16 is
already CLOSED; #23 supersedes it with this scoping.

## 2. Functional requirements (client-side tracking-URL API)

Grounded in the types already present, "tracking URLs" here means: for each SGAI ad event, the
list of URLs the client must fire when that event occurs. The shape is **fixed by the existing
code** — no new model needs inventing:

- **Keyed by ad event name.** `SGAIAdTrackingUrls.urlsByEvent` is `[String: [String]]`; the keys
  are the raw `type` strings from `X-AD-CREATIVE-SIGNALING.payload.tracking[].type`. The
  canonical set is `SGAIAdTrackingEvent` (`impression`, `start`, `firstQuartile`, `midpoint`,
  `thirdQuartile`, `complete`, `pause`, `resume`, `podStart`, `podEnd`).
- **List per event.** Each event maps to one-or-more URLs (`[String]`), matching the Android
  `Map<String, List<String>>` shape.
- **Keyed by ad within a break.** `SGAIAdTrackingUrlsExtractor.adTrackingUrlsMap` is
  `[String: SGAIAdTrackingUrls]`, keyed `pod_<adBreakId>` for pod-level signaling and
  `<currentAdsId>_0_<index>` per asset. Lookups already exist:
  `trackingUrls(forAd:)` and `trackingUrls(forAdIndex:)`.
- **Relation to existing ad-creative data.** Tracking URLs live *alongside* the ad creative in
  the same asset-list JSON (each `ASSETS[]` entry carries `URI`/`DURATION` plus an optional
  `X-AD-CREATIVE-SIGNALING`; the break carries an optional pod-level `X-AD-CREATIVE-SIGNALING`).
  So this is not new data to fetch — it is the same asset list the SDK already parses.

The remaining functional work is therefore **exposure + firing**, which is exactly what the two
open feat issues already cover (see §5), not a new data model:

- Fire the URLs for the standard events off AVPlayer time/boundary observers → **#20**.
- Expose a public opt-in toggle + get/set-per-ad API on `AVPlayerEventLogger` → **#21**.

## 3. Data contract / spec impact

No `player-analytics-specification` schema change is implied by the client-side interpretation.
Tracking URLs are **read from the HLS asset-list JSON and fired as HTTP GETs to the ad server**;
they are not part of the EPAS event envelope the SDK POSTs to the Eventsink. The SDK's analytics
events (`AVPlayerEventLogger` → `AnalyticsEventSender`) are unchanged — firing a tracking URL is a
side-effect ping to a third party, not a new EPAS event field.

Caveat for the follow-up issues: *if* #20/#21 decide the SDK should ALSO emit an EPAS analytics
event when an ad event fires (e.g. an ad-impression analytics event, distinct from the tracking
ping), that WOULD require a spec addition in `player-analytics-specification` and downstream
propagation to eventsink/worker and the other SDKs. That is a separate decision to be made in #20
and is explicitly NOT assumed here. The tracking-URL firing itself needs no spec change.

## 4. Acceptance criteria

For the requirements-clarification chore (#23) — this note:

- [x] Scope question answered and grounded in real files: no normalizer service in this repo;
      the grounded deliverable is a client-side SGAI tracking-URL API on `AVPlayerEventLogger`.
- [x] Functional requirements defined against the existing `SGAI*` types (shape, keying,
      relation to ad-creative data).
- [x] Spec impact stated: none for client-side firing; the one case that WOULD need a spec change
      is called out as a #20 decision.
- [x] Concrete acceptance criteria + follow-up issues cross-referenced (#20, #21) without
      duplicating them.

Concrete input/output example the follow-up implementation should satisfy (drawn from the
`SGAIAdTrackingUrls` header contract):

Input asset-list JSON (abridged):

```json
{
  "ASSETS": [
    {
      "URI": "ad-creative.mp4",
      "DURATION": 15,
      "X-AD-CREATIVE-SIGNALING": {
        "payload": {
          "tracking": [
            { "type": "impression", "urls": ["https://ads.example/imp"] },
            { "type": "complete",   "urls": ["https://ads.example/comp"] }
          ]
        }
      }
    }
  ],
  "X-AD-CREATIVE-SIGNALING": {
    "payload": { "tracking": [ { "type": "podStart", "urls": ["https://ads.example/pod"] } ] }
  }
}
```

Expected parsed model (already produced by `SGAIAdTrackingUrlsExtractor.parse(...)`):

- `adTrackingUrlsMap["pod_<adBreakId>"].urls(for: .podStart)` → `["https://ads.example/pod"]`
- `adTrackingUrlsMap["<currentAdsId>_0_0"].urls(for: .impression)` → `["https://ads.example/imp"]`
- `adTrackingUrlsMap["<currentAdsId>_0_0"].urls(for: .complete)` → `["https://ads.example/comp"]`

Expected client behaviour (to be delivered by #20/#21): with SGAI tracking enabled, when the ad
reaches each boundary the SDK fires an HTTP GET to the corresponding URL(s) exactly once; when
disabled (the default), nothing is fired.

## 5. Proposed follow-up sub-issues

The implementable work already exists as open issues in this repo — align to them rather than
opening duplicates:

- **#20 — feat: fire SGAI ad tracking events from AVPlayer in the Swift SDK.** Detect ad
  transitions / quartile progress / pod boundaries off AVPlayer observers and fire the tracking
  URLs from `adTrackingUrlsMap`. This is the "firing" half of the tracking-URL enhancement.
- **#21 — feat: expose SGAI ad-tracking toggle and tracking-URL API on the Swift analytics
  logger.** Public opt-in enable/disable plus get/set-per-ad tracking URLs on
  `AVPlayerEventLogger`, mirroring the Android `enableSGAIAdTracking(...)` /
  `setAdTrackingUrls(...)` / `getTrackingUrlsForAd(...)` surface. This is the "exposure" half.

No new sub-issue is required for #23 beyond these two. If a server-side normalizer capability is
still desired (the original #16 intent), raise it against the correct component **outside** this
SDK — it is out of scope here.
