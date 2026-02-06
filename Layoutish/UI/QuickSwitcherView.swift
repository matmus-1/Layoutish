//
//  QuickSwitcherView.swift
//  Layoutish
//
//  Floating overlay for quickly searching and applying layouts (⌘⇧L)
//

import SwiftUI

struct QuickSwitcherView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var layoutEngine = LayoutEngine.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared

    @State private var searchText = ""
    @State private var isApplying = false
    @State private var appliedLayoutId: UUID?

    private var filteredLayouts: [Layout] {
        if searchText.isEmpty {
            return appState.layouts
        }
        return appState.layouts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.uniqueApps.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                TextField("Search layouts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.5)

            // Layouts list
            if filteredLayouts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "rectangle.3.group" : "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "No saved layouts" : "No matching layouts")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(filteredLayouts) { layout in
                            quickSwitcherRow(layout: layout)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }

            Divider().opacity(0.5)

            // Footer
            HStack {
                Text("⌘⇧L to toggle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Esc to close")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 340, height: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand {
            QuickSwitcherManager.shared.close()
        }
    }

    @ViewBuilder
    private func quickSwitcherRow(layout: Layout) -> some View {
        let isLastApplied = appState.lastAppliedLayoutId == layout.id
        let justApplied = appliedLayoutId == layout.id

        Button(action: {
            applyAndClose(layout)
        }) {
            HStack(spacing: 10) {
                // Thumbnail
                LayoutThumbnailView(layout: layout, size: 30)

                // Layout info
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text("\(layout.windowCount) windows • \(layout.uniqueApps.count) apps")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Hotkey badge
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

                // Status
                if justApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.successGreen)
                } else if isLastApplied {
                    Text("Active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color.successGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLastApplied ? Color.successGreenBackground.opacity(0.5) : Color.primary.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!permissionsManager.canProceed || isApplying)
    }

    private func applyAndClose(_ layout: Layout) {
        guard !isApplying else { return }
        isApplying = true

        Task {
            await LayoutEngine.shared.applyLayout(layout)
            await MainActor.run {
                appliedLayoutId = layout.id
                isApplying = false

                // Brief delay to show checkmark, then close
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    QuickSwitcherManager.shared.close()
                }
            }
        }
    }
}
