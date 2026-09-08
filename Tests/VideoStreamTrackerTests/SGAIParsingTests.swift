//
//  SGAIParsingTests.swift
//  VideoStreamTrackerTests
//
//  Unit tests for HLS SGAI asset-list signaling parsing (issue #19).
//  These cover pure-Foundation parsing types and require no AVFoundation, so
//  they are testable off-device.
//

import XCTest
@testable import VideoStreamTracker

final class SGAIParsingTests: XCTestCase {

    // MARK: - Manifest #EXT-X-DATERANGE parsing

    func testParsesDateRangeWithAssetList() throws {
        let manifest = """
        #EXTM3U
        #EXTINF:6.0,
        segment1.ts
        #EXT-X-DATERANGE:ID="ad-break-1",X-ASSET-LIST="https://your-server.com/ads.json"
        #EXTINF:6.0,
        segment2.ts
        """

        let ranges = SGAIManifestParser.parseDateRanges(from: manifest)

        XCTAssertEqual(ranges.count, 1)
        let range = try XCTUnwrap(ranges.first)
        XCTAssertEqual(range.id, "ad-break-1")
        XCTAssertEqual(range.assetListUri, "https://your-server.com/ads.json")
        XCTAssertNil(range.assetUri)
        XCTAssertEqual(range.resolvedAssetListUri, "https://your-server.com/ads.json")
    }

    func testParsesDateRangeWithAssetUri() throws {
        let manifest = """
        #EXTM3U
        #EXT-X-DATERANGE:ID="ad-break-1",X-ASSET-URI="https://your-server.com/ads.json"
        """

        let ranges = SGAIManifestParser.parseDateRanges(from: manifest)

        XCTAssertEqual(ranges.count, 1)
        let range = try XCTUnwrap(ranges.first)
        XCTAssertEqual(range.id, "ad-break-1")
        XCTAssertNil(range.assetListUri)
        XCTAssertEqual(range.assetUri, "https://your-server.com/ads.json")
        XCTAssertEqual(range.resolvedAssetListUri, "https://your-server.com/ads.json")
    }

    func testIgnoresDateRangeWithoutAssetSignaling() {
        let manifest = """
        #EXTM3U
        #EXT-X-DATERANGE:ID="scte-1",START-DATE="2026-01-01T00:00:00Z",DURATION=30
        #EXTINF:6.0,
        segment1.ts
        """

        let ranges = SGAIManifestParser.parseDateRanges(from: manifest)
        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Asset-list JSON parsing (Android README shape)

    /// The asset-list JSON documented in the Android SDK README, verbatim shape.
    private let sampleAssetListJSON = """
    {
      "ASSETS": [
        {
          "URI": "ad-creative.mp4",
          "DURATION": 15,
          "X-AD-CREATIVE-SIGNALING": {
            "payload": {
              "tracking": [
                { "type": "impression", "urls": ["https://tracking.example.com/impression"] },
                { "type": "start", "urls": ["https://tracking.example.com/start"] },
                { "type": "firstQuartile", "urls": ["https://tracking.example.com/firstQuartile"] },
                { "type": "midpoint", "urls": ["https://tracking.example.com/midpoint"] },
                { "type": "thirdQuartile", "urls": ["https://tracking.example.com/thirdQuartile"] },
                { "type": "complete", "urls": ["https://tracking.example.com/complete"] },
                { "type": "pause", "urls": ["https://tracking.example.com/pause"] },
                { "type": "resume", "urls": ["https://tracking.example.com/resume"] }
              ]
            }
          }
        }
      ],
      "X-AD-CREATIVE-SIGNALING": {
        "payload": {
          "tracking": [
            { "type": "podStart", "urls": ["https://tracking.example.com/podStart"] },
            { "type": "podEnd", "urls": ["https://tracking.example.com/podEnd"] }
          ]
        }
      }
    }
    """

    func testParsesAssetListIntoTrackingModel() throws {
        let extractor = SGAIAdTrackingUrlsExtractor()
        let map = try extractor.parse(assetListJSON: sampleAssetListJSON, adBreakId: "ad-break-1")

        // Pod-level tracking stored under "pod_<adBreakId>".
        let pod = try XCTUnwrap(map["pod_ad-break-1"])
        XCTAssertEqual(pod.urls(for: .podStart), ["https://tracking.example.com/podStart"])
        XCTAssertEqual(pod.urls(for: .podEnd), ["https://tracking.example.com/podEnd"])

        // Per-asset tracking stored under "<currentAdsId>_0_<index>".
        let ad = try XCTUnwrap(map["ad-session-1_0_0"])
        XCTAssertEqual(ad.urls(for: .impression), ["https://tracking.example.com/impression"])
        XCTAssertEqual(ad.urls(for: .start), ["https://tracking.example.com/start"])
        XCTAssertEqual(ad.urls(for: .firstQuartile), ["https://tracking.example.com/firstQuartile"])
        XCTAssertEqual(ad.urls(for: .midpoint), ["https://tracking.example.com/midpoint"])
        XCTAssertEqual(ad.urls(for: .thirdQuartile), ["https://tracking.example.com/thirdQuartile"])
        XCTAssertEqual(ad.urls(for: .complete), ["https://tracking.example.com/complete"])
        XCTAssertEqual(ad.urls(for: .pause), ["https://tracking.example.com/pause"])
        XCTAssertEqual(ad.urls(for: .resume), ["https://tracking.example.com/resume"])

        // Lookup helpers mirror the Android accessors.
        XCTAssertEqual(extractor.trackingUrls(forAdIndex: 0), ad)
        XCTAssertEqual(extractor.trackingUrls(forAd: "pod_ad-break-1"), pod)
    }

    func testMissingAndEmptyTrackingProducesNoEntries() throws {
        // An asset with no signaling, plus a pod signaling whose tracking list
        // is empty -> nothing should be stored.
        let json = """
        {
          "ASSETS": [
            { "URI": "ad-creative.mp4" }
          ],
          "X-AD-CREATIVE-SIGNALING": {
            "payload": { "tracking": [] }
          }
        }
        """

        let extractor = SGAIAdTrackingUrlsExtractor()
        let map = try extractor.parse(assetListJSON: json, adBreakId: "ad-break-1")

        XCTAssertTrue(map.isEmpty)
        XCTAssertNil(extractor.trackingUrls(forAdIndex: 0))
        XCTAssertNil(extractor.trackingUrls(forAd: "pod_ad-break-1"))
    }

    func testTrackingEventWithEmptyUrlsIsDropped() throws {
        // A tracking event present but with an empty urls array is filtered out,
        // mirroring Android's `filterValues { it.isNotEmpty() }`.
        let json = """
        {
          "ASSETS": [
            {
              "URI": "ad-creative.mp4",
              "X-AD-CREATIVE-SIGNALING": {
                "payload": {
                  "tracking": [
                    { "type": "impression", "urls": [] },
                    { "type": "start", "urls": ["https://tracking.example.com/start"] }
                  ]
                }
              }
            }
          ]
        }
        """

        let extractor = SGAIAdTrackingUrlsExtractor()
        let map = try extractor.parse(assetListJSON: json, adBreakId: "ad-break-1")

        let ad = try XCTUnwrap(map["ad-session-1_0_0"])
        XCTAssertNil(ad.urls(for: .impression))
        XCTAssertEqual(ad.urls(for: .start), ["https://tracking.example.com/start"])
    }
}
