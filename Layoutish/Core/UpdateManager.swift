//
//  UpdateManager.swift
//  Layoutish
//
//  Handles automatic updates using Sparkle framework
//

import Foundation
import Sparkle
import SwiftUI
import Combine

// MARK: - Update Manager (Singleton)

/// Manages app updates using Sparkle
final class UpdateManager: ObservableObject {

    // MARK: - Singleton

    static let shared = UpdateManager()

    // MARK: - Sparkle Controller

    /// The Sparkle updater controller - handles UI and update logic
    let updaterController: SPUStandardUpdaterController

    // MARK: - Initialization

    private init() {
        // Initialize Sparkle updater controller
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Disable automatic scheduled update checks - only manual or on startup
        updaterController.updater.automaticallyChecksForUpdates = false

        // Start the updater
        do {
            try updaterController.updater.start()
        } catch {
            print("[Sparkle] Failed to start updater: \(error)")
        }
    }

    // MARK: - Background Check

    /// Check for updates silently - only shows UI if update is available
    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }

    // MARK: - Convenience

    /// Get the current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Get the current build number
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - CheckForUpdatesViewModel

/// Observable view model for the "Check for Updates" button
final class CheckForUpdatesViewModel: ObservableObject {

    @Published var canCheckForUpdates = false

    private let updater: SPUUpdater
    private var cancellable: Any?

    init(updater: SPUUpdater) {
        self.updater = updater

        // Observe canCheckForUpdates using Combine
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

// MARK: - CheckForUpdatesView

/// SwiftUI view that displays a "Check for Updates" button
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            viewModel.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
