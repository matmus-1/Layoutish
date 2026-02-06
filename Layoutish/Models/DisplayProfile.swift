//
//  DisplayProfile.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 06/02/2026.
//

import Foundation
import AppKit

// MARK: - Display Info

/// Represents a single physical display's properties
struct DisplayInfo: Codable, Equatable, Identifiable {
    var id: UInt32 { displayId }

    let displayId: UInt32               // CGDirectDisplayID
    let width: Int                      // Resolution width in points
    let height: Int                     // Resolution height in points
    let localizedName: String           // e.g. "Dell U2720Q", "Built-in Retina Display"
    let originX: Int                    // Position in global coordinate space
    let originY: Int
    let isBuiltIn: Bool                 // CGDisplayIsBuiltin() — identifies laptop screen

    /// Create from an NSScreen
    static func from(screen: NSScreen) -> DisplayInfo? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let displayId = screenNumber.uint32Value
        let frame = screen.frame

        return DisplayInfo(
            displayId: displayId,
            width: Int(frame.width),
            height: Int(frame.height),
            localizedName: screen.localizedName,
            originX: Int(frame.origin.x),
            originY: Int(frame.origin.y),
            isBuiltIn: CGDisplayIsBuiltin(displayId) != 0
        )
    }
}

// MARK: - Display Fingerprint

/// A hardware signature for a specific monitor configuration
struct DisplayFingerprint: Codable, Equatable {
    let displayCount: Int
    let displays: [DisplayInfo]         // Ordered by x-position (left to right)

    /// Build a fingerprint from the current live display state
    static func current() -> DisplayFingerprint {
        let screens = NSScreen.screens
        let displays = screens
            .compactMap { DisplayInfo.from(screen: $0) }
            .sorted { $0.originX < $1.originX }  // Left-to-right ordering

        return DisplayFingerprint(
            displayCount: displays.count,
            displays: displays
        )
    }

    // MARK: - Matching

    /// Match confidence level
    enum MatchConfidence: Comparable {
        case none
        case partial(Float)     // 0.0–0.6: same displays but different count (e.g. lid closed)
        case strong(Float)      // 0.7–0.9: same names+resolutions, different IDs (reboot)
        case exact              // 1.0: everything matches

        var score: Float {
            switch self {
            case .none: return 0.0
            case .partial(let s): return s
            case .strong(let s): return s
            case .exact: return 1.0
            }
        }

        var meetsAutoApplyThreshold: Bool {
            score >= 0.8
        }

        static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
            lhs.score < rhs.score
        }
    }

    /// Compare this fingerprint against another and return match confidence
    func matchConfidence(against other: DisplayFingerprint) -> MatchConfidence {
        // EXACT MATCH: same count, same display IDs, same resolutions
        if self == other {
            return .exact
        }

        // Build sets for comparison
        let selfDisplaySet = Set(displays.map { DisplaySignature(name: $0.localizedName, width: $0.width, height: $0.height) })
        let otherDisplaySet = Set(other.displays.map { DisplaySignature(name: $0.localizedName, width: $0.width, height: $0.height) })

        // STRONG MATCH: same count, same names+resolutions, different IDs
        // This handles the common case where display IDs change after reboot
        if displayCount == other.displayCount && selfDisplaySet == otherDisplaySet {
            return .strong(0.9)
        }

        // STRONG MATCH: same count, same resolutions (names might differ slightly)
        let selfResolutions = Set(displays.map { ResolutionSignature(width: $0.width, height: $0.height) })
        let otherResolutions = Set(other.displays.map { ResolutionSignature(width: $0.width, height: $0.height) })

        if displayCount == other.displayCount && selfResolutions == otherResolutions {
            return .strong(0.8)
        }

        // PARTIAL MATCH: different count but overlapping displays
        // e.g. saved with 2 monitors, now on 1 (laptop lid closed, or monitor disconnected)
        let overlap = selfDisplaySet.intersection(otherDisplaySet)
        if !overlap.isEmpty {
            let overlapRatio = Float(overlap.count) / Float(max(selfDisplaySet.count, otherDisplaySet.count))
            return .partial(overlapRatio * 0.6)
        }

        // NO MATCH
        return .none
    }
}

// MARK: - Signature Helpers (for set-based comparison)

/// Display signature for matching (ignores display ID and position)
private struct DisplaySignature: Hashable {
    let name: String
    let width: Int
    let height: Int
}

/// Resolution-only signature for looser matching
private struct ResolutionSignature: Hashable {
    let width: Int
    let height: Int
}

// MARK: - Display Profile

/// A saved display configuration with an associated default layout
struct DisplayProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String                        // e.g. "Desk Setup", "Laptop Only"
    var fingerprint: DisplayFingerprint     // The hardware signature
    var defaultLayoutId: UUID?              // Layout to auto-apply when detected
    var isAutoApplyEnabled: Bool            // Per-profile toggle
    let createdAt: Date
    var lastSeenAt: Date                    // Updated each time this profile is detected

    init(
        id: UUID = UUID(),
        name: String,
        fingerprint: DisplayFingerprint,
        defaultLayoutId: UUID? = nil,
        isAutoApplyEnabled: Bool = true,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.defaultLayoutId = defaultLayoutId
        self.isAutoApplyEnabled = isAutoApplyEnabled
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }

    /// Human-readable display description, e.g. "Built-in Retina + Dell U2720Q"
    var displayDescription: String {
        fingerprint.displays.map { $0.localizedName }.joined(separator: " + ")
    }

    /// Auto-generate a name from the display configuration
    static func autoName(from fingerprint: DisplayFingerprint) -> String {
        if fingerprint.displayCount == 1 {
            if fingerprint.displays.first?.isBuiltIn == true {
                return "Laptop Only"
            } else {
                return fingerprint.displays.first?.localizedName ?? "Single Display"
            }
        }

        let hasBuiltIn = fingerprint.displays.contains { $0.isBuiltIn }
        let externalNames = fingerprint.displays
            .filter { !$0.isBuiltIn }
            .map { $0.localizedName }

        if hasBuiltIn && !externalNames.isEmpty {
            return "Desk Setup" // Laptop + external(s) — most common docking scenario
        }

        return "\(fingerprint.displayCount) Displays"
    }
}
