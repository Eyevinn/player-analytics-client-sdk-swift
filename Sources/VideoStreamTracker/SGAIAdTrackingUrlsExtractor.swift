//
//  SGAIAdTrackingUrlsExtractor.swift
//  VideoStreamTracker
//
//  Fetches and parses the SGAI asset-list JSON referenced by an
//  `#EXT-X-DATERANGE` cue and extracts per-event tracking URLs into the
//  ``SGAIAdTrackingUrls`` model.
//
//  Mirrors the Android `SGAIAdTrackingUrlsExtractor`:
//   - the pod-level (`X-AD-CREATIVE-SIGNALING`) tracking is stored under the
//     key `pod_<adBreakId>`;
//   - each asset's tracking is stored under `<adsId>_0_<index>`.
//
//  SCOPE (issue #19): fetch + parse into the model only. This type does NOT
//  detect ad transitions or fire any tracking URL (issue #20) and exposes no
//  public API (issue #21) — everything is `internal`. Networking is injected
//  so parsing can be unit-tested from provided `Data` without a live fetch.
//

import Foundation

/// Abstraction over the network fetch of an asset-list URL, injected so tests
/// can supply canned `Data` instead of performing a live request.
internal protocol SGAIAssetListFetching {
    /// Fetch the raw bytes of the asset-list JSON at `url`.
    func fetch(url: URL) async throws -> Data
}

/// Default `URLSession`-backed fetcher.
internal struct SGAIURLSessionFetcher: SGAIAssetListFetching {
    private let session: URLSession

    internal init(session: URLSession = .shared) {
        self.session = session
    }

    internal func fetch(url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}

/// Extracts SGAI tracking URLs from an asset list, keyed per ad event.
internal final class SGAIAdTrackingUrlsExtractor {

    /// Errors surfaced while extracting tracking URLs.
    internal enum ExtractionError: Error, Equatable {
        case invalidAssetListUrl(String)
    }

    /// Prefix for the pod (ad-break) tracking key, mirroring Android's
    /// `"pod_${adBreakId}"`.
    internal static let podKeyPrefix = "pod_"

    /// The current ad session identifier, matching Android's `currentAdsId`.
    /// Used to build per-asset keys `"<currentAdsId>_0_<index>"`.
    internal var currentAdsId: String = "ad-session-1"

    private let fetcher: SGAIAssetListFetching

    /// Per-key tracking URLs. Keys are `pod_<adBreakId>` for the ad break and
    /// `<currentAdsId>_0_<index>` for each individual asset — mirroring the
    /// Android `adTrackingUrlsMap` shape (`Map<String, Map<String, List<String>>>`).
    private(set) internal var adTrackingUrlsMap: [String: SGAIAdTrackingUrls] = [:]

    internal init(fetcher: SGAIAssetListFetching = SGAIURLSessionFetcher()) {
        self.fetcher = fetcher
    }

    // MARK: - Fetch + parse

    /// Fetch the asset list at `assetListUrl`, parse it, and store the extracted
    /// tracking URLs keyed by ad-break / asset. Returns the parsed model map.
    @discardableResult
    internal func extractTrackingUrls(assetListUrl: String, adBreakId: String) async throws -> [String: SGAIAdTrackingUrls] {
        guard let url = URL(string: assetListUrl) else {
            throw ExtractionError.invalidAssetListUrl(assetListUrl)
        }
        let data = try await fetcher.fetch(url: url)
        return try parse(assetListData: data, adBreakId: adBreakId)
    }

    // MARK: - Parse-only (testable without networking)

    /// Parse a raw asset-list JSON `Data` and store the extracted tracking URLs.
    /// This is the networking-free entry point used by unit tests.
    @discardableResult
    internal func parse(assetListData data: Data, adBreakId: String) throws -> [String: SGAIAdTrackingUrls] {
        let assetList = try JSONDecoder().decode(SGAIAssetList.self, from: data)
        return process(assetList: assetList, adBreakId: adBreakId)
    }

    /// Convenience overload that accepts a JSON string.
    @discardableResult
    internal func parse(assetListJSON json: String, adBreakId: String) throws -> [String: SGAIAdTrackingUrls] {
        try parse(assetListData: Data(json.utf8), adBreakId: adBreakId)
    }

    /// Populate `adTrackingUrlsMap` from a decoded asset list.
    /// Mirrors Android's `processAdResponse`: pod signaling first, then each
    /// asset by index. Empty tracking maps are skipped.
    @discardableResult
    private func process(assetList: SGAIAssetList, adBreakId: String) -> [String: SGAIAdTrackingUrls] {
        // Pod-level tracking -> "pod_<adBreakId>".
        let podTracking = SGAIAdTrackingUrls.from(tracking: assetList.podSignaling?.payload.tracking)
        if !podTracking.isEmpty {
            adTrackingUrlsMap["\(Self.podKeyPrefix)\(adBreakId)"] = podTracking
        }

        // Per-asset tracking -> "<currentAdsId>_0_<index>".
        for (index, asset) in assetList.assets.enumerated() {
            let assetTracking = SGAIAdTrackingUrls.from(tracking: asset.signaling?.payload.tracking)
            if !assetTracking.isEmpty {
                adTrackingUrlsMap["\(currentAdsId)_0_\(index)"] = assetTracking
            }
        }

        return adTrackingUrlsMap
    }

    // MARK: - Lookup

    /// Tracking URLs for a specific stored ad key, or `nil` if absent.
    internal func trackingUrls(forAd adId: String) -> SGAIAdTrackingUrls? {
        adTrackingUrlsMap[adId]
    }

    /// Tracking URLs for an asset by its index in the current session.
    internal func trackingUrls(forAdIndex adIndex: Int) -> SGAIAdTrackingUrls? {
        adTrackingUrlsMap["\(currentAdsId)_0_\(adIndex)"]
    }
}
