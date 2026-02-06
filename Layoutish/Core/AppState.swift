//
//  AppState.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import SwiftUI
import Combine

/// Central state management for the Layoutish app
@MainActor
class AppState: ObservableObject {

    // MARK: - Singleton

    static let shared = AppState()

    // MARK: - Published Properties

    @Published var layouts: [Layout] = []
    @Published var isCapturingLayout: Bool = false
    @Published var lastAppliedLayoutId: UUID?
    @Published var recentlyAppliedIds: [UUID] = []

    // MARK: - Private Properties

    private let storageKey = "com.appish.layoutish.layouts"
    private let recentKey = "com.appish.layoutish.recentlyApplied"
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadLayouts()
        loadRecentlyApplied()

        // Auto-save when layouts change
        $layouts
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveLayouts()
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout Management

    /// Add a new layout
    func addLayout(_ layout: Layout) {
        layouts.append(layout)
        NSLog("AppState: Added layout '\(layout.name)' with \(layout.windowCount) windows")
    }

    /// Remove a layout
    func removeLayout(_ layout: Layout) {
        layouts.removeAll { $0.id == layout.id }
        NSLog("AppState: Removed layout '\(layout.name)'")
    }

    /// Update an existing layout
    func updateLayout(_ layout: Layout) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            var updated = layout
            updated.updatedAt = Date()
            layouts[index] = updated
            NSLog("AppState: Updated layout '\(layout.name)'")
        }
    }

    /// Rename a layout
    func renameLayout(id: UUID, newName: String) {
        if let index = layouts.firstIndex(where: { $0.id == id }) {
            layouts[index].name = newName
            layouts[index].updatedAt = Date()
            NSLog("AppState: Renamed layout to '\(newName)'")
        }
    }

    /// Update layout icon
    func updateLayoutIcon(id: UUID, icon: String) {
        if let index = layouts.firstIndex(where: { $0.id == id }) {
            layouts[index].icon = icon
            layouts[index].updatedAt = Date()
        }
    }

    /// Update layout hotkey
    func updateLayoutHotkey(id: UUID, hotkey: String?, modifiers: UInt?, keyCode: UInt16?) {
        if let index = layouts.firstIndex(where: { $0.id == id }) {
            layouts[index].hotkey = hotkey
            layouts[index].hotkeyModifiers = modifiers
            layouts[index].hotkeyKeyCode = keyCode
            layouts[index].updatedAt = Date()
        }
    }

    /// Duplicate a layout with a new UUID and "(Copy)" suffix
    func duplicateLayout(_ layout: Layout) {
        let copy = Layout(
            name: layout.name + " (Copy)",
            icon: layout.icon,
            hotkey: nil,
            hotkeyModifiers: nil,
            hotkeyKeyCode: nil,
            monitorConfig: layout.monitorConfig,
            windows: layout.windows
        )
        addLayout(copy)
        NSLog("AppState: Duplicated layout '\(layout.name)' -> '\(copy.name)'")
    }

    /// Get layout by ID
    func getLayout(by id: UUID) -> Layout? {
        layouts.first { $0.id == id }
    }

    /// Track a layout as recently applied (max 5, most recent first)
    func markLayoutAsApplied(_ layoutId: UUID) {
        lastAppliedLayoutId = layoutId
        recentlyAppliedIds.removeAll { $0 == layoutId }
        recentlyAppliedIds.insert(layoutId, at: 0)
        if recentlyAppliedIds.count > 5 {
            recentlyAppliedIds = Array(recentlyAppliedIds.prefix(5))
        }
        saveRecentlyApplied()
    }

    /// Reorder layouts
    func moveLayout(from source: IndexSet, to destination: Int) {
        layouts.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private func saveLayouts() {
        do {
            let data = try JSONEncoder().encode(layouts)
            UserDefaults.standard.set(data, forKey: storageKey)
            NSLog("AppState: Saved \(layouts.count) layouts")
        } catch {
            NSLog("AppState: Failed to save layouts - \(error.localizedDescription)")
        }
    }

    private func loadLayouts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            NSLog("AppState: No saved layouts found")
            return
        }

        do {
            layouts = try JSONDecoder().decode([Layout].self, from: data)
            NSLog("AppState: Loaded \(layouts.count) layouts")
        } catch {
            NSLog("AppState: Failed to load layouts - \(error.localizedDescription)")
        }
    }

    // MARK: - Recent Persistence

    private func saveRecentlyApplied() {
        let strings = recentlyAppliedIds.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: recentKey)
    }

    private func loadRecentlyApplied() {
        guard let strings = UserDefaults.standard.stringArray(forKey: recentKey) else { return }
        recentlyAppliedIds = strings.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Export/Import

    func exportLayoutsToJSON() -> Data? {
        try? JSONEncoder().encode(layouts)
    }

    func importLayoutsFromJSON(_ data: Data) throws {
        let imported = try JSONDecoder().decode([Layout].self, from: data)
        layouts.append(contentsOf: imported)
        NSLog("AppState: Imported \(imported.count) layouts")
    }
}
