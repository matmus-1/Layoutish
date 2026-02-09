//
//  SettingsPopupView.swift
//  Layoutish
//
//  Settings popup with General, Permissions and About sections
//  Matching Lockish design patterns
//

import SwiftUI
import ServiceManagement
import Sparkle

struct SettingsPopupView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("launchAppsOnRestore") private var launchAppsOnRestore = true
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @Environment(\.openURL) var openURL

    init() {
        _checkForUpdatesViewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(
            updater: UpdateManager.shared.updaterController.updater
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // GENERAL Section
            generalSection

            Divider()

            // BEHAVIOR Section
            behaviorSection

            Divider()

            // PERMISSIONS Section
            permissionsSection

            Divider()

            // LICENSE Section
            licenseSection

            Divider()

            // ABOUT Section
            aboutSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            // Sync the toggle with actual launch at login status
            launchAtLogin = getLaunchAtLoginStatus()
        }
    }

    // MARK: - License Section

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if licenseManager.isLicensed {
                LicenseStatusView()
            } else {
                UnlicensedView()
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("General")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $launchAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 13))
                    Text("Start Layoutish automatically when you log in")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { newValue in
                setLaunchAtLogin(enabled: newValue)
            }
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Behavior")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(isOn: $launchAppsOnRestore) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch Apps on Restore")
                        .font(.system(size: 13))
                    Text("Open apps that aren't running when applying a layout")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Accessibility status
            HStack(spacing: 8) {
                Image(systemName: permissionsManager.canProceed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(permissionsManager.canProceed ? .green : .red)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                        .font(.system(size: 13, weight: .medium))
                    Text(permissionsManager.canProceed ? "Granted" : "Required for window management")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                permissionsManager.openAccessibilitySettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 12))
                        .frame(width: 16)
                    Text("Open Accessibility Settings")
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color.brandPurple)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // App icon
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.brandPurple)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Layoutish")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Version \(getAppVersion())")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\u{00A9} \(String(Calendar.current.component(.year, from: Date()))) Appish")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            // Links
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let url = URL(string: "https://appish.app/layoutish") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text("Website")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.brandPurple)
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "mailto:layoutish@appish.app") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .font(.system(size: 12))
                        Text("Support")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.brandPurple)
                }
                .buttonStyle(.plain)

                Button {
                    checkForUpdatesViewModel.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Check for Updates")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(Color.brandPurple)
                }
                .buttonStyle(.plain)
                .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    NSLog("SettingsPopupView: Registered for launch at login")
                } else {
                    try SMAppService.mainApp.unregister()
                    NSLog("SettingsPopupView: Unregistered from launch at login")
                }
            } catch {
                NSLog("SettingsPopupView: Failed to set launch at login - %@", error.localizedDescription)
            }
        } else {
            NSLog("SettingsPopupView: Launch at login not supported on macOS < 13")
        }
    }

    private func getLaunchAtLoginStatus() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    // MARK: - App Version

    private func getAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsPopupView()
}
