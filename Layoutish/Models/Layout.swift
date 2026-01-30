//
//  Layout.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import AppKit

// MARK: - Window Info

/// Represents a single window's position and metadata
struct WindowInfo: Codable, Identifiable, Equatable {
    let id: UUID
    let appBundleId: String
    let appName: String
    var windowTitle: String?
    var frame: CGRect
    var displayId: UInt32
    var windowIndex: Int  // For apps with multiple windows (index within that app)
    var zIndex: Int  // Global z-order: 0 = frontmost, higher = further back

    init(
        id: UUID = UUID(),
        appBundleId: String,
        appName: String,
        windowTitle: String? = nil,
        frame: CGRect,
        displayId: UInt32,
        windowIndex: Int = 0,
        zIndex: Int = 0
    ) {
        self.id = id
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.displayId = displayId
        self.windowIndex = windowIndex
        self.zIndex = zIndex
    }
}

// MARK: - Monitor Configuration

/// Represents the monitor setup when a layout was saved
struct MonitorConfiguration: Codable, Equatable {
    let displayCount: Int
    let displayIds: [UInt32]
    let description: String  // Human-readable, e.g., "MacBook Pro + Dell U2720Q"

    static func current() -> MonitorConfiguration {
        let screens = NSScreen.screens
        let displayIds = screens.compactMap { screen -> UInt32? in
            let deviceDescription = screen.deviceDescription
            if let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                return screenNumber.uint32Value
            }
            return nil
        }

        let description = screens.map { $0.localizedName }.joined(separator: " + ")

        return MonitorConfiguration(
            displayCount: screens.count,
            displayIds: displayIds,
            description: description
        )
    }
}

// MARK: - Layout

/// A saved window layout configuration
struct Layout: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name or emoji
    var hotkey: String?  // e.g., "⌘⇧1"
    var hotkeyModifiers: UInt?  // NSEvent.ModifierFlags raw value
    var hotkeyKeyCode: UInt16?
    let createdAt: Date
    var updatedAt: Date
    var monitorConfig: MonitorConfiguration
    var windows: [WindowInfo]

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "rectangle.3.group",
        hotkey: String? = nil,
        hotkeyModifiers: UInt? = nil,
        hotkeyKeyCode: UInt16? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        monitorConfig: MonitorConfiguration = .current(),
        windows: [WindowInfo] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.hotkey = hotkey
        self.hotkeyModifiers = hotkeyModifiers
        self.hotkeyKeyCode = hotkeyKeyCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.monitorConfig = monitorConfig
        self.windows = windows
    }

    /// Get unique apps in this layout
    var uniqueApps: [String] {
        Array(Set(windows.map { $0.appName })).sorted()
    }

    /// Get the count of windows
    var windowCount: Int {
        windows.count
    }

    /// Check if monitor configuration matches current setup
    var matchesCurrentMonitors: Bool {
        monitorConfig == MonitorConfiguration.current()
    }
}

// MARK: - Preset Icons

extension Layout {
    /// Suggested icons for different layout types
    static let suggestedIcons: [(name: String, symbol: String)] = [
        ("Coding", "chevron.left.forwardslash.chevron.right"),
        ("Design", "paintbrush"),
        ("Writing", "doc.text"),
        ("Meetings", "video"),
        ("Research", "magnifyingglass"),
        ("Communication", "bubble.left.and.bubble.right"),
        ("Media", "play.rectangle"),
        ("Finance", "chart.line.uptrend.xyaxis"),
        ("General", "rectangle.3.group"),
        ("Focus", "eye"),
    ]
}
