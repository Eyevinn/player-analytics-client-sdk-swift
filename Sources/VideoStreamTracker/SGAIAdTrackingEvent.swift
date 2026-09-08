//
//  SGAIAdTrackingEvent.swift
//  VideoStreamTracker
//
//  Ad tracking event names for HLS SGAI (Server-Guided Ad Insertion).
//
//  Mirrors the contract implemented in the Android SDK
//  (SGAIAdTrackingEvent.kt): the `eventName` raw values are the exact
//  `type` strings used in the asset-list JSON under
//  `X-AD-CREATIVE-SIGNALING.payload.tracking[].type`.
//

import Foundation

/// Types of ad tracking events for SGAI ad tracking.
///
/// These correspond to standard VAST/VPAID ad tracking events plus ad-pod
/// events. The raw value of each case is the `type` string as it appears in
/// the asset-list JSON, so it can be used directly as the key into a parsed
/// ``SGAIAdTrackingUrls`` model.
internal enum SGAIAdTrackingEvent: String, CaseIterable {
    // Core impression and playback events.
    case impression
    case start

    // Quartile events for video ads.
    case firstQuartile
    case midpoint
    case thirdQuartile
    case complete

    case pause
    case resume

    // Ad pod events.
    case podStart
    case podEnd

    /// The event name as used in the asset-list JSON and as the tracking-map key.
    var eventName: String { rawValue }
}
