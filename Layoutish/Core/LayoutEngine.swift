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

    // MARK: - Position Tolerance

    /// Tolerance in pixels for considering a position/size "close enough"
    private let positionTolerance: CGFloat = 5.0

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

            // Skip system/utility apps that shouldn't be part of saved layouts
            let skipApps = ["Control Center", "Notification Center", "WindowServer", "Dock",
                            "System Settings", "System Preferences"]
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

        // NOTE: We no longer "activate all apps" here - it causes visual flicker
        // Instead, we only raise the frontmost window at the end

        // Second pass: Position all windows IN PARALLEL for speed
        // Only the frontmost window is processed last (so it ends up on top)
        NSLog("LayoutEngine: Positioning windows in parallel...")

        // Find the frontmost window (lowest zIndex among non-minimized windows)
        let frontmostZIndex = layout.windows
            .filter { !$0.isMinimized }
            .map { $0.zIndex }
            .min() ?? 0

        // Separate frontmost window from the rest
        let frontmostWindow = layout.windows.first { $0.zIndex == frontmostZIndex && !$0.isMinimized }
        let otherWindows = layout.windows.filter { window in
            !(window.zIndex == frontmostZIndex && !window.isMinimized)
        }

        // Process all non-frontmost windows in parallel
        var failedWindows: [WindowInfo] = []

        await withTaskGroup(of: (WindowInfo, Bool).self) { group in
            for window in otherWindows {
                group.addTask {
                    let success = await self.positionWindow(window, retries: 5, isFrontmost: false)
                    return (window, success)
                }
            }

            // Collect results
            for await (window, success) in group {
                if !success {
                    failedWindows.append(window)
                }
            }
        }

        // Process frontmost window LAST so it ends up on top
        if let frontmost = frontmostWindow {
            let success = await positionWindow(frontmost, retries: 5, isFrontmost: true)
            if !success {
                failedWindows.append(frontmost)
            }
        }

        // Third pass: Retry failed windows in parallel after additional delay
        if !failedWindows.isEmpty {
            NSLog("LayoutEngine: \(failedWindows.count) window(s) failed, waiting 3s then retrying in parallel...")
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds

            await withTaskGroup(of: Void.self) { group in
                for window in failedWindows {
                    group.addTask {
                        NSLog("LayoutEngine: Retrying \(window.appName)...")
                        let isFrontmost = (window.zIndex == frontmostZIndex) && !window.isMinimized
                        _ = await self.positionWindow(window, retries: 5, isFrontmost: isFrontmost)
                    }
                }
            }
        }

        // Final step: Re-raise the frontmost window to guarantee it's on top.
        // Fallback activations during parallel positioning or retries may have
        // brought other apps to the front, so we do one final raise.
        if let frontmost = frontmostWindow, !frontmost.isMinimized,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == frontmost.appBundleId }) {
            app.activate(options: [.activateIgnoringOtherApps])
            NSLog("LayoutEngine: Final re-raise of frontmost app '\(frontmost.appName)'")
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
    /// - Parameters:
    ///   - window: The window info to position
    ///   - retries: Number of retry attempts
    ///   - isFrontmost: Whether this window should be the frontmost (zIndex == 0)
    @discardableResult
    private func positionWindow(_ window: WindowInfo, retries: Int = 5, isFrontmost: Bool = false) async -> Bool {
        for attempt in 1...retries {
            // Find the running app
            guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == window.appBundleId }) else {
                NSLog("LayoutEngine: [\(attempt)/\(retries)] App not running: \(window.appName)")
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 second
                }
                continue
            }

            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)

            // Unhide (but do NOT activate) so AX windows are accessible.
            // We avoid app.activate() here because when called for multiple apps
            // in parallel it brings each app to the front, creating z-order chaos.
            // If AX windows still aren't accessible, the fallback below (line ~414)
            // will activate the app as a last resort.
            if !window.isMinimized && attempt == 1 {
                app.unhide()
            }

            // Get all windows for this app
            var windowsRef: CFTypeRef?
            var result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

            // If we can't access windows, try activating the app first
            // macOS often hides AX window info for non-active/background apps (returns empty array or -25211)
            // Some apps (Ghostty, Chrome, etc.) need forceful activation AND longer delays to expose their windows
            // This is especially true for GPU-accelerated terminal apps and browsers when minimized
            if result != .success || windowsRef == nil || (windowsRef as? [AXUIElement])?.isEmpty == true {
                // Forcefully activate the app to make its windows accessible via Accessibility API
                app.unhide()  // Unhide first in case it's hidden
                app.activate(options: [.activateIgnoringOtherApps])

                // Longer delay for apps that need time to expose windows (especially when previously minimized)
                // Apps like Ghostty, Chrome need ~1 second after activation
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 second

                // Retry getting windows after activation
                windowsRef = nil
                result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

                // If still no windows, try clicking the dock icon via Accessibility API
                // This works for stubborn apps like Ghostty that don't expose minimized windows
                // Uses Accessibility permission (which we have) - no Automation permission needed
                if result != .success || windowsRef == nil || (windowsRef as? [AXUIElement])?.isEmpty == true {
                    NSLog("LayoutEngine: [\(window.appName)] Windows still empty, clicking dock icon via Accessibility...")
                    await forceUnminimizeViaActivation(bundleId: window.appBundleId, appName: window.appName)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0 second for window to appear

                    windowsRef = nil
                    result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
                }
            }

            guard result == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
                NSLog("LayoutEngine: [\(attempt)/\(retries)] No windows yet for \(window.appName) (AX result: \(result.rawValue))")
                if attempt < retries {
                    // Longer delay between retries - apps like Ghostty/Chrome need more time
                    try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds
                }
                continue
            }

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

            // Check current minimized state
            var minimizedRef: CFTypeRef?
            var isCurrentlyMinimized = false
            if AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success {
                isCurrentlyMinimized = (minimizedRef as? Bool) ?? false
            }

            // OPTIMIZATION: If window should stay minimized and is already minimized, skip entirely
            if window.isMinimized && isCurrentlyMinimized {
                NSLog("LayoutEngine: [\(window.appName)] Already minimized - skipping")
                return true
            }

            // Get current position and size
            let currentFrame = getCurrentWindowFrame(targetWindow)

            // Check if position and size are already correct (within tolerance)
            let positionCorrect = abs(currentFrame.origin.x - window.frame.origin.x) <= positionTolerance &&
                                  abs(currentFrame.origin.y - window.frame.origin.y) <= positionTolerance
            let sizeCorrect = abs(currentFrame.width - window.frame.width) <= positionTolerance &&
                              abs(currentFrame.height - window.frame.height) <= positionTolerance
            let minimizedCorrect = isCurrentlyMinimized == window.isMinimized

            // If everything is already correct, skip (unless we need to raise frontmost)
            if positionCorrect && sizeCorrect && minimizedCorrect && !isFrontmost {
                NSLog("LayoutEngine: [\(window.appName)] Already in correct position - skipping")
                return true
            }

            // Log what we're actually doing
            var actions: [String] = []
            if !positionCorrect { actions.append("position") }
            if !sizeCorrect { actions.append("size") }
            if !minimizedCorrect { actions.append(window.isMinimized ? "minimize" : "unminimize") }
            if isFrontmost { actions.append("raise") }

            NSLog("LayoutEngine: [\(window.appName)] Matched by \(matchedBy), will: \(actions.joined(separator: ", "))")

            // STEP 1: Unminimize only if window is minimized BUT should NOT be minimized
            if isCurrentlyMinimized && !window.isMinimized {
                AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
            }

            // STEP 2: Set position only if needed
            if !positionCorrect {
                var position = CGPoint(x: window.frame.origin.x, y: window.frame.origin.y)
                if let positionValue = AXValueCreate(.cgPoint, &position) {
                    AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, positionValue)
                }
            }

            // STEP 3: Set size only if needed
            if !sizeCorrect {
                var size = CGSize(width: window.frame.width, height: window.frame.height)
                if let sizeValue = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue)
                }
            }

            // STEP 4: Handle minimized state
            if window.isMinimized && !isCurrentlyMinimized {
                AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            } else if !window.isMinimized && isFrontmost {
                // For the frontmost window, we need to:
                // 1. Activate the app (so it gets focus)
                // 2. Raise the window
                // 3. Set it as main window
                app.activate(options: [.activateIgnoringOtherApps])
                AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                NSLog("LayoutEngine: [\(window.appName)] Activated app and raised window to front")
            }

            return true  // Success
        }

        NSLog("LayoutEngine: FAILED to position \(window.appName) after \(retries) attempts")
        return false  // Failed
    }

    /// Get current window frame from AXUIElement
    private func getCurrentWindowFrame(_ window: AXUIElement) -> CGRect {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var position = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
           let posValue = positionRef {
            AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        }

        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        return CGRect(origin: position, size: size)
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

    /// Click an app's dock icon using Accessibility API to unminimize its windows
    /// This uses Accessibility permission (which we have) rather than Automation permission
    private func clickDockIconViaAccessibility(appName: String) {
        // Find the Dock process
        guard let dockApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            NSLog("LayoutEngine: Could not find Dock process")
            return
        }

        let dockAx = AXUIElementCreateApplication(dockApp.processIdentifier)

        // Get the Dock's children (the dock items list)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockAx, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            NSLog("LayoutEngine: Could not get Dock children")
            return
        }

        // Find the list containing app icons (usually the first list)
        for child in children {
            var roleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef) == .success,
               let role = roleRef as? String, role == "AXList" {

                // Get items in the list
                var itemsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                      let items = itemsRef as? [AXUIElement] else {
                    continue
                }

                // Find the app icon by title
                for item in items {
                    var titleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let title = titleRef as? String, title == appName {
                        // Found it! Perform press action
                        let pressResult = AXUIElementPerformAction(item, kAXPressAction as CFString)
                        if pressResult == .success {
                            NSLog("LayoutEngine: Clicked dock icon for \(appName) via Accessibility API")
                        } else {
                            NSLog("LayoutEngine: Failed to click dock icon for \(appName): \(pressResult.rawValue)")
                        }
                        return
                    }
                }
            }
        }

        NSLog("LayoutEngine: Could not find \(appName) in Dock")
    }

    /// Force unminimize windows for an app by aggressively activating it
    /// Uses only APIs that work with Accessibility permission (no Automation needed)
    private func forceUnminimizeViaActivation(bundleId: String, appName: String) async {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            NSLog("LayoutEngine: App not found for force unminimize: \(appName)")
            return
        }

        NSLog("LayoutEngine: Force unminimizing \(appName) via repeated activation...")

        // Aggressive activation sequence
        app.unhide()
        app.activate(options: [.activateIgnoringOtherApps])

        // Try clicking the dock icon via Accessibility API
        clickDockIconViaAccessibility(appName: appName)

        // Give it time to respond
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Activate again after dock click
        app.activate(options: [.activateIgnoringOtherApps])
    }

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
