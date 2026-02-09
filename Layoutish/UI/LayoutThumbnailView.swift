//
//  LayoutThumbnailView.swift
//  Layoutish
//
//  Mini preview of a layout's window arrangement
//

import SwiftUI

struct LayoutThumbnailView: View {
    let layout: Layout
    var size: CGFloat = 35

    /// Distinct colors for different apps, cycled
    private static let windowColors: [Color] = [
        Color(red: 0.6, green: 0.55, blue: 0.9),   // Purple (brand)
        Color(red: 0.35, green: 0.7, blue: 0.9),    // Blue
        Color(red: 0.3, green: 0.75, blue: 0.4),    // Green
        Color(red: 0.9, green: 0.6, blue: 0.3),     // Orange
        Color(red: 0.85, green: 0.4, blue: 0.5),    // Pink
        Color(red: 0.5, green: 0.8, blue: 0.7),     // Teal
        Color(red: 0.7, green: 0.65, blue: 0.4),    // Gold
        Color(red: 0.6, green: 0.4, blue: 0.8),     // Violet
    ]

    /// Map bundle IDs to consistent color indices
    private var appColorMap: [String: Int] {
        var map: [String: Int] = [:]
        var nextIndex = 0
        for window in layout.windows.sorted(by: { $0.zIndex < $1.zIndex }) {
            if map[window.appBundleId] == nil {
                map[window.appBundleId] = nextIndex % Self.windowColors.count
                nextIndex += 1
            }
        }
        return map
    }

    /// Calculate bounding box of all windows
    private var boundingBox: CGRect {
        let visibleWindows = layout.windows.filter { !$0.isMinimized && $0.frame.width > 0 && $0.frame.height > 0 }
        guard !visibleWindows.isEmpty else {
            // Use main screen size as fallback instead of hardcoded 1920x1080
            let mainFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            return mainFrame
        }

        let minX = visibleWindows.map { $0.frame.minX }.min() ?? 0
        let minY = visibleWindows.map { $0.frame.minY }.min() ?? 0
        let maxX = visibleWindows.map { $0.frame.maxX }.max() ?? 1920
        let maxY = visibleWindows.map { $0.frame.maxY }.max() ?? 1080

        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    var body: some View {
        let aspect = size * 0.7 // ~16:10 aspect ratio
        let colorMap = appColorMap
        let bounds = boundingBox
        let visibleWindows = layout.windows
            .filter { !$0.isMinimized && $0.frame.width > 0 && $0.frame.height > 0 }
            .sorted(by: { $0.zIndex > $1.zIndex }) // Draw back-to-front (higher zIndex = further back = draw first)

        ZStack {
            // Display background
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.08))

            if visibleWindows.isEmpty {
                // Empty layout indicator
                Image(systemName: layout.icon)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.tertiary)
            } else {
                // Draw windows proportionally
                ForEach(visibleWindows) { window in
                    let colorIndex = colorMap[window.appBundleId] ?? 0
                    let color = Self.windowColors[colorIndex]

                    // Scale window frame to thumbnail
                    let scaleX = (size - 4) / bounds.width
                    let scaleY = (aspect - 4) / bounds.height
                    let scale = min(scaleX, scaleY)

                    let x = (window.frame.minX - bounds.minX) * scale + 2
                    let y = (window.frame.minY - bounds.minY) * scale + 2
                    let w = max(window.frame.width * scale, 2)
                    let h = max(window.frame.height * scale, 2)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1)
                                .strokeBorder(color.opacity(0.9), lineWidth: 0.5)
                        )
                        .frame(width: w, height: h)
                        .position(x: x + w / 2, y: y + h / 2)
                }
            }
        }
        .frame(width: size, height: aspect)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
