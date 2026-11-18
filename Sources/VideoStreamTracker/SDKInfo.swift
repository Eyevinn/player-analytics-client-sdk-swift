//
//  SDKInfo.swift
//  VideoStreamTracker
//
//  The SDK's identity for the EPAS `sdk` field (#57).
//

import Foundation

internal enum SDKInfo {
    /// The name EPAS uses for this SDK (`web`, `swift`, `android`).
    static let name = "swift"
    /// This SDK's version. Keep it equal to the release tag when cutting a release.
    static let version = "0.2.0"
    /// The first EPAS version whose eventsink accepts the `sdk` field. Older eventsinks
    /// reject an event carrying `sdk` with HTTP 400 (EPAS "Units and normalisation").
    static let minimumEpasVersionForSdk = "0.7.0"

    /// True when `version` is a valid "x.y.z" (any suffix ignored) that is at least
    /// `minimum`, compared numerically ("0.10.0" > "0.7.0"). Anything else (missing,
    /// "n/a", garbage) is false, so the SDK keeps today's behaviour. Same rule as the
    /// Web SDK's `isEpasVersionAtLeast`.
    static func isVersion(_ version: Any?, atLeast minimum: String) -> Bool {
        guard let version = version as? String,
              let actual = parse(version), let required = parse(minimum) else { return false }
        for i in 0..<3 where actual[i] != required[i] {
            return actual[i] > required[i]
        }
        return true
    }

    private static func parse(_ version: String) -> [Int]? {
        let core = version.trimmingCharacters(in: .whitespaces)
            .prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).prefix(3).map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }
}
