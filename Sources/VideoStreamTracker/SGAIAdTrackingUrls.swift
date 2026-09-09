//
//  SGAIAdTrackingUrls.swift
//  VideoStreamTracker
//
//  Tracking-URL model for HLS SGAI (Server-Guided Ad Insertion) ad signaling,
//  and the Codable representation of the asset-list JSON it is parsed from.
//
//  This mirrors the contract implemented in the Android SDK
//  (SGAIAdTrackingUrlsExtractor.kt). The asset-list JSON shape is:
//
//    {
//      "ASSETS": [
//        {
//          "URI": "ad-creative.mp4",
//          "DURATION": 15,
//          "X-AD-CREATIVE-SIGNALING": {
//            "payload": {
//              "tracking": [ { "type": "impression", "urls": [ ... ] }, ... ]
//            }
//          }
//        }
//      ],
//      "X-AD-CREATIVE-SIGNALING": {          // pod-level signaling (optional)
//        "payload": {
//          "tracking": [ { "type": "podStart", "urls": [ ... ] }, ... ]
//        }
//      }
//    }
//
//  SCOPE (issue #19): parsing + model only. This type carries no logic for
//  detecting ad transitions or firing tracking URLs (issue #20), and exposes
//  no public API surface (issue #21) — everything here is `internal`.
//

import Foundation

// MARK: - Tracking-URL model

/// Per-event tracking URLs keyed by SGAI ad event name.
///
/// The keys match the `type` strings from the asset-list JSON (see
/// ``SGAIAdTrackingEvent`` for the canonical set, e.g. `impression`, `start`,
/// `firstQuartile`, `midpoint`, `thirdQuartile`, `complete`, `pause`,
/// `resume`, `podStart`, `podEnd`). Each event may map to one or more URLs,
/// mirroring the Android `Map<String, List<String>>` shape produced by
/// `groupTrackingByType`.
internal struct SGAIAdTrackingUrls: Equatable {
    /// Tracking URLs grouped by event type, e.g. `["impression": ["https://..."]]`.
    internal let urlsByEvent: [String: [String]]

    internal init(urlsByEvent: [String: [String]] = [:]) {
        self.urlsByEvent = urlsByEvent
    }

    /// `true` when no tracking URLs were present for any event.
    internal var isEmpty: Bool { urlsByEvent.isEmpty }

    /// The tracking URLs for a given event, or `nil` if none are present.
    internal func urls(for event: SGAIAdTrackingEvent) -> [String]? {
        urlsByEvent[event.eventName]
    }

    /// The tracking URLs for a raw event name, or `nil` if none are present.
    internal func urls(for eventName: String) -> [String]? {
        urlsByEvent[eventName]
    }

    /// Build the model from a decoded list of tracking events, grouping URLs by
    /// `type` and dropping any event whose URL list is empty.
    ///
    /// Mirrors Android's `groupTrackingByType`:
    /// group by `type`, flat-map the `urls`, filter out empty values.
    internal static func from(tracking: [SGAIAssetList.TrackingEvent]?) -> SGAIAdTrackingUrls {
        guard let tracking else { return SGAIAdTrackingUrls() }

        var grouped: [String: [String]] = [:]
        for event in tracking {
            guard !event.urls.isEmpty else { continue }
            grouped[event.type, default: []].append(contentsOf: event.urls)
        }
        return SGAIAdTrackingUrls(urlsByEvent: grouped)
    }
}

// MARK: - Asset-list JSON (Codable)

/// Decoded representation of the asset-list JSON referenced by an
/// `#EXT-X-DATERANGE` `X-ASSET-LIST` / `X-ASSET-URI` attribute.
///
/// Field names mirror the Android `AdResponse` / `AdAsset` model exactly
/// (`ASSETS`, `URI`, `DURATION`, `X-AD-CREATIVE-SIGNALING`, `payload`,
/// `tracking`, `type`, `urls`).
internal struct SGAIAssetList: Decodable, Equatable {
    /// The individual ad assets in the break.
    internal let assets: [Asset]
    /// Optional pod-level (ad-break) signaling.
    internal let podSignaling: CreativeSignaling?

    internal enum CodingKeys: String, CodingKey {
        case assets = "ASSETS"
        case podSignaling = "X-AD-CREATIVE-SIGNALING"
    }

    internal init(assets: [Asset], podSignaling: CreativeSignaling?) {
        self.assets = assets
        self.podSignaling = podSignaling
    }

    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `ASSETS` may be absent in a pod-only asset list; default to empty.
        self.assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        self.podSignaling = try container.decodeIfPresent(CreativeSignaling.self, forKey: .podSignaling)
    }

    /// A single ad creative within the asset list.
    internal struct Asset: Decodable, Equatable {
        internal let uri: String
        internal let duration: Int?
        internal let signaling: CreativeSignaling?

        internal enum CodingKeys: String, CodingKey {
            case uri = "URI"
            case duration = "DURATION"
            case signaling = "X-AD-CREATIVE-SIGNALING"
        }
    }

    /// The `X-AD-CREATIVE-SIGNALING` object (both pod- and asset-level).
    internal struct CreativeSignaling: Decodable, Equatable {
        internal let payload: Payload
    }

    /// The `payload` object carrying the tracking events.
    internal struct Payload: Decodable, Equatable {
        internal let tracking: [TrackingEvent]?
    }

    /// A single `{ "type": ..., "urls": [...] }` tracking entry.
    internal struct TrackingEvent: Decodable, Equatable {
        internal let type: String
        internal let urls: [String]

        internal enum CodingKeys: String, CodingKey {
            case type
            case urls
        }

        internal init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(String.self, forKey: .type)
            // Tolerate a missing `urls` array (treat as empty).
            self.urls = try container.decodeIfPresent([String].self, forKey: .urls) ?? []
        }

        internal init(type: String, urls: [String]) {
            self.type = type
            self.urls = urls
        }
    }
}
