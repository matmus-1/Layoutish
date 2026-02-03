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

    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var isApplying = false
    @State private var editingName = false
    @State private var editedName: String = ""
    @State private var editingHotkey = false
    @State private var isRecordingHotkey = false

    /// Check if this layout was the last one applied
    private var isLastApplied: Bool {
        appState.lastAppliedLayoutId == layout.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row - clickable to expand/collapse
            HStack(spacing: 12) {
                // Layout icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isLastApplied ? Color.successGreenBackground : Color.brandPurpleBackground)
                        .frame(width: 35, height: 35)

                    Image(systemName: layout.icon)
                        .font(.system(size: 16))
                        .foregroundColor(isLastApplied ? Color.successGreen : Color.brandPurple)
                }

                // Layout name and info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(layout.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)

                        // Hotkey badge if set
                        if let hotkey = layout.hotkey {
                            Text(hotkey)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                )
                        }
                    }

                    // Window count and monitor info
                    Text("\(layout.windowCount) windows • \(layout.uniqueApps.count) apps")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Apply button
                Button(action: applyLayout) {
                    if isApplying {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 50, height: 24)
                    } else {
                        Text(isLastApplied ? "Active" : "Apply")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isLastApplied ? Color.successGreen : Color.brandPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isLastApplied ? Color.successGreenBackground : Color.brandPurpleBackground)
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!permissionsManager.canProceed || isApplying)

                // Expand/collapse chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 6)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(layout.uniqueApps.joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            // Monitor configuration
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved for")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: layout.matchesCurrentMonitors ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(layout.matchesCurrentMonitors ? .green : .orange)

                    Text(layout.monitorConfig.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)

            // Action buttons row
            HStack(spacing: 12) {
                // Update positions button
                Button(action: updateLayout) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Update")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color.brandPurple)
                }
                .buttonStyle(.plain)
                .help("Update this layout with current window positions")

                // Rename button
                Button(action: {
                    editedName = layout.name
                    editingName = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                        Text("Rename")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editingName) {
                    renamePopover
                }

                // Hotkey button
                Button(action: {
                    editingHotkey = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 9))
                        Text(layout.hotkey ?? "Hotkey")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(layout.hotkey != nil ? Color.brandPurple : .secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editingHotkey) {
                    hotkeyPopover
                }

                Spacer()

                // Remove button
                Button(action: {
                    appState.removeLayout(layout)
                    HotkeyManager.shared.unregisterHotkey(for: layout.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Remove")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Rename Popover

    private var renamePopover: some View {
        VStack(spacing: 12) {
            Text("Rename Layout")
                .font(.headline)

            TextField("Layout name", text: $editedName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    editingName = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    appState.renameLayout(id: layout.id, newName: editedName)
                    editingName = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedName.isEmpty)
            }
        }
        .padding()
        .frame(width: 220)
    }

    // MARK: - Hotkey Popover

    private var hotkeyPopover: some View {
        VStack(spacing: 12) {
            Text("Set Hotkey")
                .font(.headline)

            Text("Press a key combination")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Hotkey recorder
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
                .buttonStyle(.bordered)
                .disabled(layout.hotkey == nil)

                Spacer()

                Button("Cancel") {
                    editingHotkey = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 220)
    }

    // MARK: - Actions

    private func applyLayout() {
        guard !isApplying else { return }

        isApplying = true

        Task {
            await layoutEngine.applyLayout(layout)
            await MainActor.run {
                isApplying = false
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
            hotkey: "⌘⇧1",
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
