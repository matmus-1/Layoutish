//
//  PermissionsManager.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import AppKit
import Combine

// MARK: - Permission Status

enum PermissionStatus {
    case granted
    case denied
    case unknown
}

// MARK: - Permissions Manager

@MainActor
class PermissionsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = PermissionsManager()

    // MARK: - Published State

    @Published var accessibilityStatus: PermissionStatus = .unknown

    // MARK: - Computed Properties

    var canProceed: Bool {
        accessibilityStatus == .granted
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var previousStatus: PermissionStatus = .unknown

    // MARK: - Initialization

    private init() {
        // Check permissions on init
        recheckPermissions()

        // Recheck when app becomes active (user may have granted permission)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.recheckPermissions()
            }
            .store(in: &cancellables)

        // Only start polling if not already granted
        if accessibilityStatus != .granted {
            startPermissionPolling()
        }
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Permission Checking

    func recheckPermissions() {
        let isAccessibilityGranted = AXIsProcessTrusted()
        let newStatus: PermissionStatus = isAccessibilityGranted ? .granted : .denied

        // Only log and update if status changed
        if newStatus != previousStatus {
            NSLog("PermissionsManager: Accessibility changed to \(isAccessibilityGranted ? "GRANTED" : "denied")")
            previousStatus = newStatus
            accessibilityStatus = newStatus

            // Stop polling once granted
            if isAccessibilityGranted {
                stopPolling()
            }
        }
    }

    // MARK: - Request Permissions

    func requestAccessibilityPermission() {
        NSLog("PermissionsManager: Requesting accessibility permission")

        // This will show the system prompt if not already trusted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Start polling if not already
        if pollTimer == nil && accessibilityStatus != .granted {
            startPermissionPolling()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Start polling if not already
        if pollTimer == nil && accessibilityStatus != .granted {
            startPermissionPolling()
        }
    }

    // MARK: - Polling

    private func startPermissionPolling() {
        NSLog("PermissionsManager: Starting permission polling")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.recheckPermissions()
            }
        }
    }

    private func stopPolling() {
        if pollTimer != nil {
            NSLog("PermissionsManager: Stopping permission polling")
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Diagnostics

    struct Diagnostics {
        let bundleIdentifier: String
        let bundlePath: String
        let executablePath: String
        let accessibilityAuthorized: Bool
    }

    func getDiagnostics() -> Diagnostics {
        Diagnostics(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            bundlePath: Bundle.main.bundlePath,
            executablePath: Bundle.main.executablePath ?? "unknown",
            accessibilityAuthorized: AXIsProcessTrusted()
        )
    }

    func copyDiagnosticsToClipboard() {
        let diag = getDiagnostics()
        let text = """
        Layoutish Diagnostics
        =====================
        Bundle ID: \(diag.bundleIdentifier)
        Bundle Path: \(diag.bundlePath)
        Executable: \(diag.executablePath)
        Accessibility: \(diag.accessibilityAuthorized ? "AUTHORIZED" : "NOT AUTHORIZED")
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
