//
//  QuickSwitcherManager.swift
//  Layoutish
//
//  Manages the floating Quick Switcher panel (⌘⇧L)
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class QuickSwitcherManager: ObservableObject {

    // MARK: - Singleton

    static let shared = QuickSwitcherManager()

    // MARK: - Properties

    @Published var isVisible: Bool = false
    private var panel: NSPanel?

    // MARK: - Toggle

    func toggle() {
        if let panel = panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    func open() {
        // Close existing panel first
        close()

        let contentView = QuickSwitcherView()
        let hostingController = NSHostingController(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.title = "Quick Switcher"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        // Center on screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 170
            let y = screen.frame.midY + 50
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        isVisible = true

        // Listen for panel close
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.isVisible = false
                self?.panel = nil
            }
        }
    }

    func close() {
        panel?.close()
        panel = nil
        isVisible = false
    }
}
