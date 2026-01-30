//
//  LayoutEngine.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import AppKit
import ApplicationServices
import Combine

/// Handles capturing and restoring window layouts using Accessibility APIs
@MainActor
class LayoutEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = LayoutEngine()

    // MARK: - Published State

    @Published var isApplyingLayout: Bool = false
    @Published var applyingLayoutName: String?
    @Published var lastError: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Capture Current Layout

    /// Capture all current window positions and create a new layout
    func captureCurrentLayout(name: String, icon: String = "rectangle.3.group") -> Layout? {
        NSLog("LayoutEngine: Capturing layout '\(name)'")

        // Get all windows on screen
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            lastError = "Failed to get window list"
            NSLog("LayoutEngine: Failed to get window list")
            return nil
        }

        NSLog("LayoutEngine: Found \(windowList.count) total windows")

        var windowInfos: [WindowInfo] = []
        var globalZIndex = 0  // Track global z-order (0 = frontmost)

        for windowDict in windowList {
            // Skip windows without an owning application
            guard let ownerPID = windowDict[kCGWindowOwnerPID as String] as? pid_t,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowDict[kCGWindowBounds as String] as? [String: Any],
                  let windowLayer = windowDict[kCGWindowLayer as String] as? Int else {
                continue
            }

            // Skip system UI elements (menu bar, dock, etc.) - layer 0 is normal windows
            if windowLayer != 0 { continue }

            // Skip Layoutish itself
            if ownerName == "Layoutish" { continue }

            // Skip certain system apps without window names (background windows)
            let skipApps = ["Control Center", "Notification Center", "WindowServer", "Dock"]
            if skipApps.contains(ownerName) {
                continue
            }

            // Get window bounds - handle both Int and CGFloat values
            let x: CGFloat
            let y: CGFloat
            let width: CGFloat
            let height: CGFloat

            if let xVal = boundsDict["X"] as? CGFloat {
                x = xVal
            } else if let xVal = boundsDict["X"] as? Int {
                x = CGFloat(xVal)
            } else if let xVal = boundsDict["X"] as? Double {
                x = CGFloat(xVal)
            } else {
                continue
            }

            if let yVal = boundsDict["Y"] as? CGFloat {
                y = yVal
            } else if let yVal = boundsDict["Y"] as? Int {
                y = CGFloat(yVal)
            } else if let yVal = boundsDict["Y"] as? Double {
                y = CGFloat(yVal)
            } else {
                continue
            }

            if let wVal = boundsDict["Width"] as? CGFloat {
                width = wVal
            } else if let wVal = boundsDict["Width"] as? Int {
                width = CGFloat(wVal)
            } else if let wVal = boundsDict["Width"] as? Double {
                width = CGFloat(wVal)
            } else {
                continue
            }

            if let hVal = boundsDict["Height"] as? CGFloat {
                height = hVal
            } else if let hVal = boundsDict["Height"] as? Int {
                height = CGFloat(hVal)
            } else if let hVal = boundsDict["Height"] as? Double {
                height = CGFloat(hVal)
            } else {
                continue
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)

            // Skip tiny windows (likely invisible or decorative)
            if frame.width < 100 || frame.height < 100 { continue }

            // Get bundle identifier
            let app = NSRunningApplication(processIdentifier: ownerPID)
            let bundleId = app?.bundleIdentifier ?? "unknown.\(ownerName.lowercased().replacingOccurrences(of: " ", with: "."))"

            // Skip apps without valid bundle IDs (system processes)
            if bundleId.starts(with: "unknown.") && ownerName != "Finder" {
                NSLog("LayoutEngine: Skipping \(ownerName) - no bundle ID")
                continue
            }

            // Get window title if available
            let windowTitle = windowDict[kCGWindowName as String] as? String

            // Get display ID for the window
            let displayId = getDisplayIdForWindow(frame: frame)

            // Check if we already have a window from this app
            let existingCount = windowInfos.filter { $0.appBundleId == bundleId }.count

            let windowInfo = WindowInfo(
                appBundleId: bundleId,
                appName: ownerName,
                windowTitle: windowTitle,
                frame: frame,
                displayId: displayId,
                windowIndex: existingCount,
                zIndex: globalZIndex,  // Global z-order: 0 = frontmost
                isMinimized: false  // On-screen windows are not minimized
            )

            NSLog("LayoutEngine: Captured window - \(ownerName) '\(windowTitle ?? "untitled")' at (\(Int(x)), \(Int(y))) zIndex=\(globalZIndex)")
            windowInfos.append(windowInfo)
            globalZIndex += 1  // Next window is further back
        }

        // Also capture minimized windows using Accessibility API
        let minimizedWindows = captureMinimizedWindows(globalZIndexStart: globalZIndex)
        windowInfos.append(contentsOf: minimizedWindows)

        NSLog("LayoutEngine: Captured \(windowInfos.count) windows total (\(minimizedWindows.count) minimized)")

        if windowInfos.isEmpty {
            lastError = "No windows to capture"
            return nil
        }

        return Layout(
            name: name,
            icon: icon,
            monitorConfig: .current(),
            windows: windowInfos
        )
    }

    // MARK: - Apply Layout

    /// Restore a saved layout - launches apps if needed and positions windows
    func applyLayout(_ layout: Layout, launchApps: Bool = true) async {
        NSLog("LayoutEngine: ========== APPLYING LAYOUT '\(layout.name)' ==========")
        NSLog("LayoutEngine: Layout has \(layout.windowCount) windows across \(layout.uniqueApps.count) apps")

        isApplyingLayout = true
        applyingLayoutName = layout.name
        lastError = nil

        // Group windows by app
        let windowsByApp = Dictionary(grouping: layout.windows) { $0.appBundleId }

        // Track which apps we need to launch
        var appsToLaunch: [String] = []

        // First pass: identify apps that need launching
        for (bundleId, windows) in windowsByApp {
            let runningApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
            let appName = windows.first?.appName ?? bundleId

            if runningApps.isEmpty {
                NSLog("LayoutEngine: App '\(appName)' is NOT running - will launch")
                appsToLaunch.append(bundleId)
            } else {
                NSLog("LayoutEngine: App '\(appName)' is already running")
            }
        }

        // Launch apps that aren't running
        if launchApps && !appsToLaunch.isEmpty {
            NSLog("LayoutEngine: Launching \(appsToLaunch.count) apps...")

            // Launch all apps first
            for bundleId in appsToLaunch {
                await launchApp(bundleId: bundleId)
            }

            // Small initial delay to let apps start
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

            // Wait for each launched app to have windows (with 15 second timeout per app)
            for bundleId in appsToLaunch {
                let appName = windowsByApp[bundleId]?.first?.appName ?? bundleId
                _ = await waitForAppWindow(bundleId: bundleId, appName: appName, timeout: 15.0)
            }
        }

        // Activate all apps (but don't blindly unminimize - we'll handle that per-window)
        NSLog("LayoutEngine: Activating all apps...")
        for (bundleId, _) in windowsByApp {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // Small delay after activation
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

        // Second pass: Position all windows sorted by zIndex (highest first = backmost first)
        // This ensures frontmost windows (zIndex=0) are raised last and end up on top
        NSLog("LayoutEngine: Positioning windows by z-order (backmost first, frontmost last)...")

        var failedWindows: [WindowInfo] = []

        // Sort by zIndex descending (highest zIndex = backmost = positioned first)
        let windowsSorted = layout.windows.sorted { $0.zIndex > $1.zIndex }

        for window in windowsSorted {
            NSLog("LayoutEngine: Processing '\(window.appName)' '\(window.windowTitle ?? "untitled")' zIndex=\(window.zIndex)")
            let success = await positionWindow(window, retries: 5)
            if !success {
                failedWindows.append(window)
            }
        }

        // Third pass: Retry failed windows after additional delay (for slow apps like Ghostty)
        if !failedWindows.isEmpty {
            NSLog("LayoutEngine: \(failedWindows.count) window(s) failed, waiting 5s then retrying...")
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 more seconds

            for window in failedWindows {
                NSLog("LayoutEngine: Retrying \(window.appName)...")
                _ = await positionWindow(window, retries: 5)
            }
        }

        // Update last applied
        AppState.shared.lastAppliedLayoutId = layout.id

        isApplyingLayout = false
        applyingLayoutName = nil

        NSLog("LayoutEngine: ========== FINISHED APPLYING LAYOUT '\(layout.name)' ==========")
    }

    // MARK: - Launch App

    private func launchApp(bundleId: String) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            NSLog("LayoutEngine: Could not find app URL for \(bundleId)")
            return
        }

        do {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true  // Activate the app so windows appear
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            NSLog("LayoutEngine: Successfully launched \(bundleId)")
        } catch {
            NSLog("LayoutEngine: Failed to launch \(bundleId) - \(error.localizedDescription)")
        }
    }

    /// Activate an app and unminimize all its windows
    private func activateAndUnminimizeApp(bundleId: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return
        }

        // Activate the app
        app.activate(options: [.activateIgnoringOtherApps])

        // Unminimize all windows via Accessibility
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?

        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {
            for axWindow in axWindows {
                // Unminimize
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                // Raise
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            }
            NSLog("LayoutEngine: Activated and unminimized \(axWindows.count) window(s) for \(bundleId)")
        }
    }

    /// Wait for an app to have at least one window (up to timeout)
    private func waitForAppWindow(bundleId: String, appName: String, timeout: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()
        let checkInterval: UInt64 = 500_000_000  // 0.5 seconds

        NSLog("LayoutEngine: Waiting for \(appName) to create window (timeout: \(Int(timeout))s)...")

        while Date().timeIntervalSince(startTime) < timeout {
            // Find the running app
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                var windowsRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

                if result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    NSLog("LayoutEngine: \(appName) has \(axWindows.count) window(s) after \(String(format: "%.1f", elapsed))s")
                    return true
                }
            }

            try? await Task.sleep(nanoseconds: checkInterval)
        }

        NSLog("LayoutEngine: Timeout waiting for \(appName) to create window")
        return false
    }

    // MARK: - Position Window

    /// Position a single window using Accessibility APIs
    /// Returns true if successful, false if failed
    @discardableResult
    private func positionWindow(_ window: WindowInfo, retries: Int = 5) async -> Bool {
        NSLog("LayoutEngine: Positioning \(window.appName) '\(window.windowTitle ?? "untitled")' -> (\(Int(window.frame.origin.x)), \(Int(window.frame.origin.y))) \(Int(window.frame.width))x\(Int(window.frame.height))")

        for attempt in 1...retries {
            // Find the running app
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == window.appBundleId }) else {
                NSLog("LayoutEngine: [\(attempt)/\(retries)] App not running: \(window.appName)")
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                }
                continue
            }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)

            // Get all windows for this app
            var windowsRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

            guard result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
                NSLog("LayoutEngine: [\(attempt)/\(retries)] No windows yet for \(window.appName) (AX result: \(result.rawValue))")
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8 seconds
                }
                continue
            }

            NSLog("LayoutEngine: [\(attempt)/\(retries)] Found \(axWindows.count) window(s) for \(window.appName)")

            // Try to match window by TITLE first (most reliable)
            var axWindow: AXUIElement?
            var matchedBy = "unknown"

            if let savedTitle = window.windowTitle, !savedTitle.isEmpty {
                // Try to find a window with matching title
                for (idx, candidate) in axWindows.enumerated() {
                    var titleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(candidate, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let title = titleRef as? String, title == savedTitle {
                        axWindow = candidate
                        matchedBy = "title '\(title)' at index \(idx)"
                        break
                    }
                }
            }

            // Fall back to index matching if title match failed
            if axWindow == nil {
                let windowIndex = min(window.windowIndex, axWindows.count - 1)
                guard windowIndex >= 0 else {
                    NSLog("LayoutEngine: No valid window index for \(window.appName)")
                    return false
                }
                axWindow = axWindows[windowIndex]
                matchedBy = "index \(windowIndex)"
            }

            guard let targetWindow = axWindow else {
                NSLog("LayoutEngine: Could not find target window for \(window.appName)")
                return false
            }

            NSLog("LayoutEngine: Matched window by \(matchedBy)")

            // Check current minimized state
            var minimizedRef: CFTypeRef?
            var isCurrentlyMinimized = false
            if AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success {
                isCurrentlyMinimized = (minimizedRef as? Bool) ?? false
            }

            // OPTIMIZATION: If window should stay minimized and is already minimized, skip positioning
            if window.isMinimized && isCurrentlyMinimized {
                NSLog("LayoutEngine: Window already minimized and should stay minimized - skipping")
                return true
            }

            // STEP 1: Unminimize only if window is minimized BUT should NOT be minimized
            if isCurrentlyMinimized && !window.isMinimized {
                NSLog("LayoutEngine: Window is minimized but should be visible, unminimizing...")
                AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                // Wait a moment for the window to unminimize
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
            }

            // STEP 2: Set position
            var position = CGPoint(x: window.frame.origin.x, y: window.frame.origin.y)
            if let positionValue = AXValueCreate(.cgPoint, &position) {
                let posResult = AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, positionValue)
                if posResult != .success {
                    NSLog("LayoutEngine: Failed to set position - AX error: \(posResult.rawValue)")
                } else {
                    NSLog("LayoutEngine: Position set successfully")
                }
            }

            // STEP 3: Set size
            var size = CGSize(width: window.frame.width, height: window.frame.height)
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                let sizeResult = AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue)
                if sizeResult != .success {
                    NSLog("LayoutEngine: Failed to set size - AX error: \(sizeResult.rawValue)")
                } else {
                    NSLog("LayoutEngine: Size set successfully")
                }
            }

            // STEP 4: Handle final minimized state
            if window.isMinimized && !isCurrentlyMinimized {
                // Window should be minimized but isn't - minimize it
                NSLog("LayoutEngine: Minimizing window (was minimized in saved layout)")
                AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            } else if !window.isMinimized {
                // Window should be visible - raise it
                AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
            }

            NSLog("LayoutEngine: Successfully positioned \(window.appName) '\(window.windowTitle ?? "untitled")' (minimized: \(window.isMinimized))")
            return true  // Success
        }

        NSLog("LayoutEngine: FAILED to position \(window.appName) after \(retries) attempts")
        return false  // Failed
    }

    // MARK: - Capture Minimized Windows

    /// Capture minimized windows using Accessibility API
    private func captureMinimizedWindows(globalZIndexStart: Int) -> [WindowInfo] {
        var minimizedWindowInfos: [WindowInfo] = []
        var currentZIndex = globalZIndexStart

        let skipApps = ["Layoutish", "Control Center", "Notification Center", "WindowServer", "Dock", "Finder"]

        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier,
                  app.activationPolicy == .regular,  // Only regular apps (not background)
                  !skipApps.contains(app.localizedName ?? "") else {
                continue
            }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?

            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else {
                continue
            }

            var appWindowIndex = 0

            for axWindow in axWindows {
                // Check if window is minimized
                var minimizedRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                      let isMinimized = minimizedRef as? Bool,
                      isMinimized else {
                    appWindowIndex += 1
                    continue  // Skip non-minimized windows (already captured via CGWindowList)
                }

                // Get window title
                var titleRef: CFTypeRef?
                let windowTitle: String?
                if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success {
                    windowTitle = titleRef as? String
                } else {
                    windowTitle = nil
                }

                // Get window position and size (for when it's restored)
                var positionRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                var position = CGPoint.zero
                var size = CGSize.zero

                if AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef) == .success,
                   let posValue = positionRef {
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
                }

                if AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success,
                   let sizeValue = sizeRef {
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                }

                // Skip windows with no meaningful size
                if size.width < 100 || size.height < 100 {
                    appWindowIndex += 1
                    continue
                }

                let frame = CGRect(origin: position, size: size)
                let displayId = getDisplayIdForWindow(frame: frame)

                let windowInfo = WindowInfo(
                    appBundleId: bundleId,
                    appName: app.localizedName ?? "Unknown",
                    windowTitle: windowTitle,
                    frame: frame,
                    displayId: displayId,
                    windowIndex: appWindowIndex,
                    zIndex: currentZIndex,
                    isMinimized: true
                )

                NSLog("LayoutEngine: Captured MINIMIZED window - \(app.localizedName ?? "Unknown") '\(windowTitle ?? "untitled")'")
                minimizedWindowInfos.append(windowInfo)
                currentZIndex += 1
                appWindowIndex += 1
            }
        }

        return minimizedWindowInfos
    }

    // MARK: - Helpers

    /// Get the display ID for a given window frame
    private func getDisplayIdForWindow(frame: CGRect) -> UInt32 {
        let screens = NSScreen.screens

        for screen in screens {
            let screenFrame = screen.frame
            if screenFrame.intersects(frame) {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return screenNumber.uint32Value
                }
            }
        }

        // Default to main display
        if let mainScreen = NSScreen.main,
           let screenNumber = mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return screenNumber.uint32Value
        }

        return 0
    }

    /// Check if accessibility permissions are granted
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
