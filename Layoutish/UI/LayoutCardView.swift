//
//  LayoutCardView.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import SwiftUI

// MARK: - Layout Card View

struct LayoutCardView: View {
    let layout: Layout

    @ObservedObject var appState = AppState.shared
    @ObservedObject var layoutEngine = LayoutEngine.shared
    @ObservedObject var permissionsManager = PermissionsManager.shared
    @ObservedObject var displayProfileManager = DisplayProfileManager.shared

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var isApplying = false
    @State private var appliedSuccessfully = false
    @State private var editingName = false
    @State private var editedName: String = ""
    @State private var editingHotkey = false
    @State private var showProfilePicker = false
    @State private var showDeleteConfirmation = false

    /// Display profiles that use this layout as their default
    private var associatedProfiles: [DisplayProfile] {
        displayProfileManager.profiles.filter { $0.defaultLayoutId == layout.id }
    }

    /// Check if this layout was the last one applied
    private var isLastApplied: Bool {
        appState.lastAppliedLayoutId == layout.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - clickable to expand/collapse
            HStack(spacing: 12) {
                // Layout thumbnail (or icon fallback for empty layouts)
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isLastApplied ? Color.successGreenBackground : Color.brandPurpleBackground)
                        .frame(width: 38, height: 38)

                    if layout.windows.isEmpty {
                        Image(systemName: layout.icon)
                            .font(.system(size: 17))
                            .foregroundColor(isLastApplied ? Color.successGreen : Color.brandPurple)
                    } else {
                        LayoutThumbnailView(layout: layout, size: 38)
                    }
                }

                // Layout name and info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if editingName {
                            // Inline rename field
                            TextField("Name", text: $editedName, onCommit: {
                                if !editedName.isEmpty {
                                    appState.renameLayout(id: layout.id, newName: editedName)
                                }
                                editingName = false
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(maxWidth: 120)

                            Button(action: {
                                if !editedName.isEmpty {
                                    appState.renameLayout(id: layout.id, newName: editedName)
                                }
                                editingName = false
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)

                            Button(action: { editingName = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(layout.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            // Hotkey badge if set
                            if let hotkey = layout.hotkey {
                                Text(hotkey)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.secondary.opacity(0.1))
                                    )
                            }
                        }
                    }

                    // Window count, monitor info, and profile badge
                    HStack(spacing: 4) {
                        Text("\(layout.windowCount) windows \u{2022} \(layout.uniqueApps.count) apps")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        // Show display profile badge if this layout is a default
                        if let firstProfile = associatedProfiles.first {
                            HStack(spacing: 2) {
                                Image(systemName: firstProfile.fingerprint.displayCount == 1 ? "laptopcomputer" : "display.2")
                                    .font(.system(size: 9))
                                Text(firstProfile.name)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(Color.brandPurple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.brandPurpleBackground)
                            )
                        }
                    }
                }

                Spacer()

                // Apply button
                Button(action: applyLayout) {
                    if isApplying {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 55, height: 26)
                    } else if appliedSuccessfully {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Applied!")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color.successGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.successGreenBackground)
                        )
                    } else {
                        Text(isLastApplied ? "Active" : "Apply")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isLastApplied ? Color.successGreen : Color.brandPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isLastApplied ? Color.successGreenBackground : Color.brandPurpleBackground)
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!permissionsManager.canProceed || isApplying)
                .animation(.easeInOut(duration: 0.2), value: appliedSuccessfully)

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Expanded settings section
            if isExpanded {
                expandedContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.025))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: isExpanded) { expanded in
            if !expanded {
                showDeleteConfirmation = false
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 10) {
            Divider()
                .opacity(0.3)
                .padding(.horizontal, 8)

            // Apps in this layout
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps in this layout")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(layout.uniqueApps.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            // Monitor configuration
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved for")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: layout.matchesCurrentMonitors ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(layout.matchesCurrentMonitors ? .green : .orange)

                    Text(layout.monitorConfig.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            // Action buttons — two rows
            VStack(spacing: 6) {
                // Row 1: Update, Rename, Duplicate
                HStack(spacing: 12) {
                    Button(action: updateLayout) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text("Update")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Color.brandPurple)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        editedName = layout.name
                        editingName = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                            Text("Rename")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        appState.duplicateLayout(layout)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 10))
                            Text("Duplicate")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Row 2: Hotkey, Desk Setup, Remove
                HStack(spacing: 12) {
                    Button(action: {
                        editingHotkey = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 10))
                            Text(layout.hotkey ?? "Hotkey")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(layout.hotkey != nil ? Color.brandPurple : .secondary)
                    }
                    .buttonStyle(.plain)

                    if !displayProfileManager.profiles.isEmpty {
                        Button(action: {
                            showProfilePicker.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "display")
                                    .font(.system(size: 10))
                                Text(associatedProfiles.isEmpty ? "Desk Setup" : associatedProfiles.first!.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(!associatedProfiles.isEmpty ? Color.brandPurple : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Delete with confirmation
                    if showDeleteConfirmation {
                        HStack(spacing: 6) {
                            Text("Delete?")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)

                            Button(action: {
                                appState.removeLayout(layout)
                                HotkeyManager.shared.unregisterHotkey(for: layout.id)
                            }) {
                                Text("Yes")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.red))
                            }
                            .buttonStyle(.plain)

                            Button(action: { showDeleteConfirmation = false }) {
                                Text("No")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button(action: { showDeleteConfirmation = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Remove")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)

            // Inline profile picker section
            if showProfilePicker {
                VStack(spacing: 8) {
                    Divider().opacity(0.3)

                    Text("Set as Profile Default")
                        .font(.system(size: 12, weight: .medium))

                    Text("Auto-apply this layout when a display profile is detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    ForEach(displayProfileManager.profiles) { profile in
                        Button {
                            let isAlreadySet = profile.defaultLayoutId == layout.id
                            displayProfileManager.setDefaultLayout(
                                profileId: profile.id,
                                layoutId: isAlreadySet ? nil : layout.id
                            )
                            showProfilePicker = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: profile.fingerprint.displayCount == 1 ? "laptopcomputer" : "display.2")
                                    .font(.system(size: 14))
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(profile.displayDescription)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if profile.defaultLayoutId == layout.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.brandPurple)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Done") {
                        showProfilePicker = false
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            // Inline hotkey recording section
            if editingHotkey {
                VStack(spacing: 8) {
                    Divider().opacity(0.3)

                    Text("Press a key combination")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HotkeyRecorderView(
                        currentHotkey: layout.hotkey,
                        onHotkeyRecorded: { modifiers, keyCode in
                            let hotkeyString = HotkeyManager.hotkeyString(modifiers: modifiers, keyCode: keyCode)
                            appState.updateLayoutHotkey(
                                id: layout.id,
                                hotkey: hotkeyString,
                                modifiers: modifiers,
                                keyCode: keyCode
                            )
                            HotkeyManager.shared.registerHotkey(for: appState.getLayout(by: layout.id)!)
                            editingHotkey = false
                        }
                    )
                    .frame(height: 36)

                    HStack {
                        Button("Clear") {
                            appState.updateLayoutHotkey(id: layout.id, hotkey: nil, modifiers: nil, keyCode: nil)
                            HotkeyManager.shared.unregisterHotkey(for: layout.id)
                            editingHotkey = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(layout.hotkey == nil)

                        Spacer()

                        Button("Cancel") {
                            editingHotkey = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            Spacer().frame(height: 8)
        }
    }

    // MARK: - Actions

    private func applyLayout() {
        guard !isApplying else { return }

        isApplying = true

        Task {
            await layoutEngine.applyLayout(layout)
            await MainActor.run {
                isApplying = false
                appliedSuccessfully = true
                appState.markLayoutAsApplied(layout.id)

                // Revert success feedback after 1.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        appliedSuccessfully = false
                    }
                }
            }
        }
    }

    private func updateLayout() {
        if let updatedLayout = layoutEngine.captureCurrentLayout(name: layout.name, icon: layout.icon) {
            var newLayout = updatedLayout
            newLayout.hotkey = layout.hotkey
            newLayout.hotkeyModifiers = layout.hotkeyModifiers
            newLayout.hotkeyKeyCode = layout.hotkeyKeyCode

            // Create a new layout with the same ID
            let finalLayout = Layout(
                id: layout.id,
                name: layout.name,
                icon: layout.icon,
                hotkey: layout.hotkey,
                hotkeyModifiers: layout.hotkeyModifiers,
                hotkeyKeyCode: layout.hotkeyKeyCode,
                createdAt: layout.createdAt,
                updatedAt: Date(),
                monitorConfig: newLayout.monitorConfig,
                windows: newLayout.windows
            )

            appState.updateLayout(finalLayout)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        LayoutCardView(layout: Layout(
            name: "Coding",
            icon: "chevron.left.forwardslash.chevron.right",
            hotkey: "\u{2318}\u{21E7}1",
            windows: [
                WindowInfo(appBundleId: "com.apple.Safari", appName: "Safari", frame: .zero, displayId: 1),
                WindowInfo(appBundleId: "com.apple.Terminal", appName: "Terminal", frame: .zero, displayId: 1),
            ]
        ))

        LayoutCardView(layout: Layout(
            name: "Design",
            icon: "paintbrush",
            windows: [
                WindowInfo(appBundleId: "com.figma.Desktop", appName: "Figma", frame: .zero, displayId: 1),
            ]
        ))
    }
    .padding()
    .frame(width: 350)
}
