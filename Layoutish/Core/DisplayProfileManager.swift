//
//  DisplayProfileManager.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 06/02/2026.
//

import Foundation
import AppKit
import Combine
import UserNotifications

// MARK: - Display Profile Manager

/// Manages display profile detection, matching, and auto-apply
@MainActor
final class DisplayProfileManager: ObservableObject {

    // MARK: - Singleton

    static let shared = DisplayProfileManager()

    // MARK: - Published State

    @Published var profiles: [DisplayProfile] = []
    @Published var currentProfile: DisplayProfile?
    @Published var isAutoApplyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoApplyEnabled, forKey: autoApplyKey)
        }
    }
    @Published var lastDisplayChange: Date?
    @Published var pendingNewFingerprint: DisplayFingerprint?  // Set when new config detected with no match

    // MARK: - Constants

    private let storageKey = "com.appish.layoutish.displayProfiles"
    private let autoApplyKey = "com.appish.layoutish.autoApplyEnabled"
    private let delayKey = "com.appish.layoutish.displayChangeDelay"

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()
    private var displayChangeWorkItem: DispatchWorkItem?

    /// Tracks which profile+layout was last auto-applied to prevent re-apply loops
    /// (moving windows triggers screen change notifications, which would re-trigger auto-apply)
    private var lastAutoAppliedKey: String?

    /// Configurable delay (in seconds) before fingerprinting after a display change
    var displayChangeDelay: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: delayKey)
            return stored > 0 ? stored : 2.0  // Default 2 seconds
        }
        set {
            UserDefaults.standard.set(newValue, forKey: delayKey)
        }
    }

    // MARK: - Initialization

    private init() {
        // Load settings
        isAutoApplyEnabled = UserDefaults.standard.bool(forKey: autoApplyKey)

        // Load saved profiles
        loadProfiles()

        // Auto-save when profiles change
        $profiles
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveProfiles()
            }
            .store(in: &cancellables)

        // Register for display reconfiguration events via CoreGraphics
        registerDisplayCallback()

        // Also listen to NSApplication screen change notification as backup
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                NSLog("DisplayProfileManager: NSApplication.didChangeScreenParametersNotification fired")
                self?.scheduleDisplayChangeHandling()
            }
            .store(in: &cancellables)

        NSLog("DisplayProfileManager: Initialized with \(profiles.count) saved profiles, autoApply=\(isAutoApplyEnabled)")
    }

    // MARK: - CoreGraphics Display Callback

    /// Register for CGDisplay reconfiguration events
    /// This is more reliable than NSScreen notifications for detecting physical display changes
    private func registerDisplayCallback() {
        // CGDisplayRegisterReconfigurationCallback requires a C function pointer
        // Must be a literal closure — cannot reference a named function
        let result = CGDisplayRegisterReconfigurationCallback({ display, flags, userInfo in
            Task { @MainActor in
                DisplayProfileManager.shared.handleDisplayReconfiguration(display: display, flags: flags)
            }
        }, nil)
        if result == .success {
            NSLog("DisplayProfileManager: Registered CGDisplay reconfiguration callback")
        } else {
            NSLog("DisplayProfileManager: Failed to register CGDisplay callback: \(result)")
        }
    }

    /// Handle display reconfiguration event (called from C callback on main thread)
    func handleDisplayReconfiguration(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        // The callback fires twice: once with beginConfigurationFlag, once without (completion)
        // We only act on the completion event
        if flags.contains(.beginConfigurationFlag) {
            NSLog("DisplayProfileManager: Display reconfiguration BEGINNING for display \(display)")
            return
        }

        NSLog("DisplayProfileManager: Display reconfiguration COMPLETED for display \(display), flags=\(flags.rawValue)")

        // Log what changed
        if flags.contains(.addFlag) {
            NSLog("DisplayProfileManager: Display ADDED: \(display)")
        }
        if flags.contains(.removeFlag) {
            NSLog("DisplayProfileManager: Display REMOVED: \(display)")
        }
        if flags.contains(.movedFlag) {
            NSLog("DisplayProfileManager: Display MOVED: \(display)")
        }

        scheduleDisplayChangeHandling()
    }

    // MARK: - Display Change Handling

    /// Schedule fingerprinting after a delay (debounced — multiple rapid events collapse into one)
    private func scheduleDisplayChangeHandling() {
        // Cancel any pending work
        displayChangeWorkItem?.cancel()

        let delay = displayChangeDelay
        NSLog("DisplayProfileManager: Scheduling fingerprint in \(delay)s...")

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange()
            }
        }
        displayChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Core logic: fingerprint current displays, match profile, auto-apply or prompt
    private func handleDisplayChange() {
        lastDisplayChange = Date()

        let fingerprint = DisplayFingerprint.current()
        NSLog("DisplayProfileManager: Current fingerprint: \(fingerprint.displayCount) displays — \(fingerprint.displays.map { $0.localizedName }.joined(separator: ", "))")

        // Find best matching profile
        let match = bestMatchingProfile(for: fingerprint)

        if let (profile, confidence) = match {
            NSLog("DisplayProfileManager: Matched profile '\(profile.name)' with confidence \(confidence.score)")

            // Update current profile
            currentProfile = profile
            pendingNewFingerprint = nil

            // Update lastSeenAt
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index].lastSeenAt = Date()
            }

            // Auto-apply if enabled and confidence is high enough
            if isAutoApplyEnabled && profile.isAutoApplyEnabled && confidence.meetsAutoApplyThreshold {
                if let layoutId = profile.defaultLayoutId,
                   let layout = AppState.shared.getLayout(by: layoutId) {
                    // Skip if we already auto-applied this exact profile+layout combo
                    // (moving windows triggers screen change notifications which would loop)
                    let applyKey = "\(profile.id)-\(layoutId)"
                    if lastAutoAppliedKey == applyKey {
                        NSLog("DisplayProfileManager: Skipping re-apply — already applied '\(layout.name)' for '\(profile.name)'")
                    } else {
                        lastAutoAppliedKey = applyKey
                        NSLog("DisplayProfileManager: Auto-applying layout '\(layout.name)' for profile '\(profile.name)'")

                        Task {
                            await LayoutEngine.shared.applyLayout(layout)
                            postAutoApplyNotification(layoutName: layout.name, profileName: profile.name)
                        }
                    }
                } else {
                    NSLog("DisplayProfileManager: Profile '\(profile.name)' has no default layout set")
                }
            }
        } else {
            NSLog("DisplayProfileManager: No matching profile found for current display configuration")

            currentProfile = nil
            pendingNewFingerprint = fingerprint
            lastAutoAppliedKey = nil  // Reset so auto-apply works when a profile matches again

            // Post notification about unrecognized configuration
            postNewConfigNotification(fingerprint: fingerprint)
        }
    }

    // MARK: - Profile Detection (called on app launch)

    /// Detect and match the current display configuration (called once on startup)
    func detectCurrentProfile() {
        let fingerprint = DisplayFingerprint.current()
        NSLog("DisplayProfileManager: Initial detection — \(fingerprint.displayCount) displays")

        let match = bestMatchingProfile(for: fingerprint)
        if let (profile, _) = match {
            currentProfile = profile

            // Update lastSeenAt
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index].lastSeenAt = Date()
            }

            NSLog("DisplayProfileManager: Startup matched profile '\(profile.name)'")
        } else {
            currentProfile = nil
            NSLog("DisplayProfileManager: No profile matches current display configuration on startup")
        }
    }

    // MARK: - Profile Matching

    /// Find the best matching profile for a given fingerprint
    /// Returns the profile and its match confidence, or nil if no match
    private func bestMatchingProfile(for fingerprint: DisplayFingerprint) -> (DisplayProfile, DisplayFingerprint.MatchConfidence)? {
        var bestMatch: (DisplayProfile, DisplayFingerprint.MatchConfidence)?

        // Minimum confidence threshold for considering a profile as matching.
        // Partial matches (different display count) cap at 0.6, so a threshold
        // of 0.5 effectively requires a strong match (same display count) to be
        // considered valid. This ensures that adding/removing a monitor is treated
        // as a new display configuration rather than a partial match of an existing one.
        let minimumConfidenceThreshold: Float = 0.5

        for profile in profiles {
            let confidence = fingerprint.matchConfidence(against: profile.fingerprint)

            if confidence.score >= minimumConfidenceThreshold {
                if bestMatch == nil || confidence > bestMatch!.1 {
                    bestMatch = (profile, confidence)
                }
            } else if confidence.score > 0 {
                NSLog("DisplayProfileManager: Profile '\(profile.name)' has low confidence \(confidence.score) — below threshold \(minimumConfidenceThreshold), treating as no match")
            }
        }

        return bestMatch
    }

    // MARK: - Profile Management (CRUD)

    /// Create a new profile from the current display configuration
    @discardableResult
    func createProfileFromCurrentDisplays(name: String? = nil, defaultLayoutId: UUID? = nil) -> DisplayProfile {
        let fingerprint = DisplayFingerprint.current()
        let profileName = name ?? DisplayProfile.autoName(from: fingerprint)

        let profile = DisplayProfile(
            name: profileName,
            fingerprint: fingerprint,
            defaultLayoutId: defaultLayoutId
        )

        profiles.append(profile)
        currentProfile = profile
        pendingNewFingerprint = nil

        NSLog("DisplayProfileManager: Created profile '\(profileName)' with \(fingerprint.displayCount) displays")
        return profile
    }

    /// Remove a profile
    func removeProfile(_ profile: DisplayProfile) {
        profiles.removeAll { $0.id == profile.id }
        if currentProfile?.id == profile.id {
            currentProfile = nil
        }
        NSLog("DisplayProfileManager: Removed profile '\(profile.name)'")
    }

    /// Update a profile's name
    func renameProfile(id: UUID, newName: String) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].name = newName
            NSLog("DisplayProfileManager: Renamed profile to '\(newName)'")
        }
    }

    /// Set the default layout for a profile
    func setDefaultLayout(profileId: UUID, layoutId: UUID?) {
        if let index = profiles.firstIndex(where: { $0.id == profileId }) {
            profiles[index].defaultLayoutId = layoutId
            let layoutName = layoutId.flatMap { AppState.shared.getLayout(by: $0)?.name } ?? "none"
            NSLog("DisplayProfileManager: Set default layout for '\(profiles[index].name)' to '\(layoutName)'")
        }
    }

    /// Toggle auto-apply for a specific profile
    func toggleProfileAutoApply(id: UUID) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].isAutoApplyEnabled.toggle()
            NSLog("DisplayProfileManager: Profile '\(profiles[index].name)' autoApply=\(profiles[index].isAutoApplyEnabled)")
        }
    }

    /// Dismiss the pending new fingerprint banner
    func dismissPendingFingerprint() {
        pendingNewFingerprint = nil
    }

    // MARK: - Persistence

    private func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: storageKey)
            NSLog("DisplayProfileManager: Saved \(profiles.count) profiles")
        } catch {
            NSLog("DisplayProfileManager: Failed to save profiles — \(error.localizedDescription)")
        }
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            NSLog("DisplayProfileManager: No saved profiles found")
            return
        }

        do {
            profiles = try JSONDecoder().decode([DisplayProfile].self, from: data)
            NSLog("DisplayProfileManager: Loaded \(profiles.count) profiles")
        } catch {
            NSLog("DisplayProfileManager: Failed to load profiles — \(error.localizedDescription)")
        }
    }

    // MARK: - Notifications

    /// Request notification permission (called when user enables auto-apply)
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                NSLog("DisplayProfileManager: Notification permission granted")
            } else if let error = error {
                NSLog("DisplayProfileManager: Notification permission error — \(error.localizedDescription)")
            }
        }
    }

    /// Post a system notification when a layout is auto-applied
    private func postAutoApplyNotification(layoutName: String, profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Layout Applied"
        content.body = "Applied '\(layoutName)' — \(profileName) detected"
        content.sound = nil  // Silent — don't disturb the user

        let request = UNNotificationRequest(
            identifier: "layoutish.autoApply.\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("DisplayProfileManager: Failed to post notification — \(error.localizedDescription)")
            }
        }
    }

    /// Post a notification when an unrecognized display config is detected
    private func postNewConfigNotification(fingerprint: DisplayFingerprint) {
        let displayNames = fingerprint.displays.map { $0.localizedName }.joined(separator: " + ")

        let content = UNMutableNotificationContent()
        content.title = "New Display Configuration"
        content.body = "\(fingerprint.displayCount) display(s): \(displayNames). Open Layoutish to save as a profile."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "layoutish.newConfig.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("DisplayProfileManager: Failed to post new config notification — \(error.localizedDescription)")
            }
        }
    }
}

