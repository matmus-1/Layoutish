//
//  MenuBarDropdownView.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import SwiftUI
import AppKit

// MARK: - Brand Colors (Matching Lockish)

extension Color {
    static let brandPurple = Color(red: 0.6, green: 0.55, blue: 0.9)
    static let brandPurpleBackground = Color(red: 0.25, green: 0.25, blue: 0.4)
    static let successGreen = Color(red: 0.3, green: 0.75, blue: 0.4)
    static let successGreenBackground = Color(red: 0.2, green: 0.35, blue: 0.25)
}

// MARK: - Main Menu Bar Dropdown View

struct MenuBarDropdownView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var layoutEngine = LayoutEngine.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @ObservedObject private var licenseManager = LicenseManager.shared

    @State private var showSettingsPopover = false
    @State private var showNewLayoutSheet = false
    @State private var newLayoutName = ""

    /// Check if app is fully active (licensed AND has permissions)
    private var isFullyActive: Bool {
        licenseManager.isLicensed && permissionsManager.canProceed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Show license warning banner first if not licensed
            if !licenseManager.isLicensed {
                licenseWarningBanner
            } else {
                // Show permission warning only if licensed
                if !permissionsManager.canProceed {
                    accessibilityWarningBanner
                }
            }

            Divider()
                .opacity(0.5)

            // Layouts list
            layoutsSection

            Divider()
                .opacity(0.5)

            // Footer with actions
            footerSection
        }
        .frame(width: 350)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showNewLayoutSheet) {
            NewLayoutSheet(isPresented: $showNewLayoutSheet)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Text("Layoutish")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            // Status indicator - shows actual state (licensed + permissions)
            if isFullyActive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("Setup Required")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - License Warning Banner

    private var licenseWarningBanner: some View {
        Button(action: {
            // Open settings popover to show license input
            showSettingsPopover = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("License Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Click to enter your license key")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accessibility Warning Banner

    private var accessibilityWarningBanner: some View {
        Button(action: {
            permissionsManager.openAccessibilitySettings()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Required to manage window positions")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.85))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Layouts Section

    private var layoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("Saved Layouts")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(appState.layouts.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            // Layouts list
            if appState.layouts.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.layouts.enumerated()), id: \.element.id) { index, layout in
                            LayoutCardView(layout: layout)

                            if index < appState.layouts.count - 1 {
                                Divider()
                                    .padding(.vertical, 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No saved layouts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Arrange your windows, then save")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 0) {
            // Action buttons row
            HStack(spacing: 12) {
                // Save Current Layout button - brand purple style
                Button(action: { showNewLayoutSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Save Current Layout")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color.brandPurple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.brandPurpleBackground)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isFullyActive)
                .opacity(isFullyActive ? 1.0 : 0.5)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            Divider()
                .opacity(0.5)

            // Bottom row - Settings button on left, Quit on right
            HStack {
                // Settings button
                Button {
                    showSettingsPopover.toggle()
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
                    SettingsPopupView()
                }

                Spacer()

                // Monitor info
                Text(MonitorConfiguration.current().description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer()

                // Quit button
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - New Layout Sheet

struct NewLayoutSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var layoutEngine = LayoutEngine.shared

    @State private var layoutName = ""
    @State private var selectedIcon = "rectangle.3.group"
    @State private var isCapturing = false
    @State private var error: String?

    private let iconOptions = [
        "rectangle.3.group",
        "chevron.left.forwardslash.chevron.right",
        "paintbrush",
        "doc.text",
        "video",
        "magnifyingglass",
        "bubble.left.and.bubble.right",
        "play.rectangle",
        "chart.line.uptrend.xyaxis",
        "eye",
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("Save Current Layout")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Layout name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Layout Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., Coding, Design, Meetings", text: $layoutName)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIcon == icon ? Color.brandPurpleBackground : Color.secondary.opacity(0.1))
                                )
                                .foregroundColor(selectedIcon == icon ? Color.brandPurple : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Error message
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Info about what will be captured
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("This will save positions of all open windows across \(NSScreen.screens.count) display(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: captureLayout) {
                    if isCapturing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Save Layout")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(layoutName.isEmpty || isCapturing)
            }
        }
        .padding(16)
        .frame(width: 300, height: 300)
    }

    private func captureLayout() {
        isCapturing = true
        error = nil

        // Close the sheet first so windows are visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let layout = layoutEngine.captureCurrentLayout(name: layoutName, icon: selectedIcon) {
                appState.addLayout(layout)
                isPresented = false
            } else {
                error = layoutEngine.lastError ?? "Failed to capture layout"
            }
            isCapturing = false
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarDropdownView()
        .frame(width: 350)
}
