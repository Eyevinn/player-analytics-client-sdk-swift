//
//  SGAIManifestParser.swift
//  VideoStreamTracker
//
//  Parses `#EXT-X-DATERANGE` cues from an HLS manifest to extract SGAI ad
//  signaling: the ad-break `ID` and the referenced asset list via either
//  `X-ASSET-LIST` (live) or `X-ASSET-URI` (VoD).
//
//  Mirrors the Android contract: the manifest carries standard HLS SGAI cues,
//  e.g.
//
//    #EXT-X-DATERANGE:ID="ad-break-1",X-ASSET-LIST="https://.../ads.json"
//    #EXT-X-DATERANGE:ID="ad-break-1",X-ASSET-URI="https://.../ads.json"
//
//  SCOPE (issue #19): pure parsing into a value type. No AVPlayer wiring
//  (issue #20) and no public API (issue #21) — everything here is `internal`
//  and depends only on Foundation, so it is testable off-device.
//

import Foundation

/// A single `#EXT-X-DATERANGE` cue that carries SGAI ad signaling.
internal struct SGAIDateRange: Equatable {
    /// The `ID` attribute of the date range (the ad-break identifier).
    internal let id: String
    /// The `X-ASSET-LIST` URI (live SGAI), if present.
    internal let assetListUri: String?
    /// The `X-ASSET-URI` (VoD SGAI), if present.
    internal let assetUri: String?

    /// The effective asset-list URI to fetch, preferring `X-ASSET-LIST` and
    /// falling back to `X-ASSET-URI` — matching the Android behaviour of
    /// handling either type.
    internal var resolvedAssetListUri: String? {
        assetListUri ?? assetUri
    }
}

/// Extracts SGAI `#EXT-X-DATERANGE` cues from a raw HLS manifest string.
internal enum SGAIManifestParser {
    private static let dateRangeTag = "#EXT-X-DATERANGE:"

    /// Parse every `#EXT-X-DATERANGE` line that carries `X-ASSET-LIST` or
    /// `X-ASSET-URI`. Date ranges without either attribute are ignored, since
    /// only SGAI ad-signaling cues are of interest here.
    internal static func parseDateRanges(from manifest: String) -> [SGAIDateRange] {
        var results: [SGAIDateRange] = []

        for rawLine in manifest.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(dateRangeTag) else { continue }

            let attributeList = String(line.dropFirst(dateRangeTag.count))
            let attributes = parseAttributes(attributeList)

            let assetListUri = attributes["X-ASSET-LIST"]
            let assetUri = attributes["X-ASSET-URI"]

            // Only keep cues that actually reference an asset list.
            guard assetListUri != nil || assetUri != nil else { continue }

            results.append(
                SGAIDateRange(
                    id: attributes["ID"] ?? "",
                    assetListUri: assetListUri,
                    assetUri: assetUri
                )
            )
        }

        return results
    }

    /// Parse a comma-separated HLS attribute list into a `[key: value]` map,
    /// stripping surrounding double quotes from quoted values and respecting
    /// commas that appear inside quoted values.
    private static func parseAttributes(_ attributeList: String) -> [String: String] {
        var attributes: [String: String] = [:]

        for pair in splitTopLevel(attributeList) {
            guard let equalsIndex = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(pair[pair.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }

            guard !key.isEmpty else { continue }
            attributes[key] = value
        }

        return attributes
    }

    /// Split on top-level commas only — commas inside double-quoted values are
    /// preserved so that a URL containing a comma is not truncated.
    private static func splitTopLevel(_ input: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var insideQuotes = false

        for character in input {
            switch character {
            case "\"":
                insideQuotes.toggle()
                current.append(character)
            case "," where !insideQuotes:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        parts.append(current)

        return parts
    }
}
