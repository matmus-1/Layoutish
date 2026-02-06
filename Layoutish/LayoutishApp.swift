//
//  LayoutishApp.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import SwiftUI
import AppKit

@main
struct LayoutishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only - no window
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Layoutish: App launched")

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        setupMenuBar()

        // Check permissions on launch
        Task { @MainActor in
            PermissionsManager.shared.recheckPermissions()
        }

        // Register global hotkeys after a short delay (to let AppState load layouts)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { @MainActor in
                HotkeyManager.shared.registerAllHotkeys()
                HotkeyManager.shared.registerQuickSwitcherHotkey()
            }
        }

        // Initialize display profile monitoring after everything else is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Task { @MainActor in
                _ = DisplayProfileManager.shared  // Triggers init, registers CG callback
                DisplayProfileManager.shared.detectCurrentProfile()  // Match current displays on launch
                NSLog("Layoutish: Display profile monitoring initialized")
            }
        }

        // Initialize schedule manager
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            Task { @MainActor in
                _ = ScheduleManager.shared  // Triggers init, starts timer if enabled
                NSLog("Layoutish: Schedule manager initialized")
            }
        }
    }

    private func setupMenuBar() {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use SF Symbol for menu bar icon
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Layoutish")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(config)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 350, height: 340)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.delegate = self
        popover?.contentViewController = NSHostingController(rootView: MenuBarDropdownView())
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        // Add event monitor to close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        // Remove event monitor
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running even without windows (menu bar app)
        return false
    }
}
