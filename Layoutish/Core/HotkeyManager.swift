//
//  HotkeyManager.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import Foundation
import AppKit
import Carbon

/// Manages global hotkey registration and handling
class HotkeyManager {

    // MARK: - Singleton

    static let shared = HotkeyManager()

    // MARK: - Properties

    private var registeredHotkeys: [UUID: EventHotKeyRef] = [:]
    private var hotkeyIDToLayoutID: [UInt32: UUID] = [:]
    private var nextHotkeyID: UInt32 = 1
    private var quickSwitcherHotkeyRef: EventHotKeyRef?
    private let quickSwitcherHotkeyID: UInt32 = 9999

    // MARK: - Initialization

    private init() {
        setupEventHandler()
    }

    // MARK: - Event Handler Setup

    private func setupEventHandler() {
        // Install Carbon event handler for hotkey events
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            if status == noErr {
                // Dispatch to main thread to handle the hotkey
                DispatchQueue.main.async {
                    HotkeyManager.shared.handleHotkey(id: hotkeyID.id)
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            nil,
            nil
        )

        NSLog("HotkeyManager: Event handler installed")
    }

    // MARK: - Hotkey Registration

    /// Register all hotkeys from saved layouts
    func registerAllHotkeys() {
        // Unregister existing hotkeys first
        unregisterAllHotkeys()

        // Register hotkeys for all layouts that have them
        for layout in AppState.shared.layouts {
            if layout.hotkeyKeyCode != nil && layout.hotkeyModifiers != nil {
                registerHotkey(for: layout)
            }
        }

        NSLog("HotkeyManager: Registered \(registeredHotkeys.count) hotkeys")
    }

    /// Register a hotkey for a specific layout
    func registerHotkey(for layout: Layout) {
        guard let keyCode = layout.hotkeyKeyCode,
              let modifiers = layout.hotkeyModifiers else {
            return
        }

        // Unregister existing hotkey for this layout if any
        unregisterHotkey(for: layout.id)

        // Convert NSEvent modifiers to Carbon modifiers
        let carbonModifiers = carbonModifierFlags(from: modifiers)

        // Create hotkey ID
        let hotkeyID = EventHotKeyID(signature: OSType(0x4C59_5448), id: nextHotkeyID) // "LYTH" signature
        hotkeyIDToLayoutID[nextHotkeyID] = layout.id
        nextHotkeyID += 1

        // Register the hotkey
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let ref = hotkeyRef {
            registeredHotkeys[layout.id] = ref
            NSLog("HotkeyManager: Registered hotkey '\(layout.hotkey ?? "?")' for layout '\(layout.name)'")
        } else {
            NSLog("HotkeyManager: Failed to register hotkey for '\(layout.name)' - status: \(status)")
        }
    }

    /// Unregister hotkey for a specific layout
    func unregisterHotkey(for layoutID: UUID) {
        if let ref = registeredHotkeys[layoutID] {
            UnregisterEventHotKey(ref)
            registeredHotkeys.removeValue(forKey: layoutID)

            // Remove from ID mapping
            hotkeyIDToLayoutID = hotkeyIDToLayoutID.filter { $0.value != layoutID }

            NSLog("HotkeyManager: Unregistered hotkey for layout \(layoutID)")
        }
    }

    /// Unregister all hotkeys
    func unregisterAllHotkeys() {
        for (_, ref) in registeredHotkeys {
            UnregisterEventHotKey(ref)
        }
        registeredHotkeys.removeAll()
        hotkeyIDToLayoutID.removeAll()
        NSLog("HotkeyManager: Unregistered all hotkeys")
    }

    // MARK: - Hotkey Handling

    private func handleHotkey(id: UInt32) {
        // Check if it's the Quick Switcher hotkey
        if id == quickSwitcherHotkeyID {
            NSLog("HotkeyManager: Quick Switcher hotkey triggered")
            Task { @MainActor in
                QuickSwitcherManager.shared.toggle()
            }
            return
        }

        guard let layoutID = hotkeyIDToLayoutID[id],
              let layout = AppState.shared.getLayout(by: layoutID) else {
            NSLog("HotkeyManager: Unknown hotkey ID: \(id)")
            return
        }

        NSLog("HotkeyManager: Hotkey triggered for layout '\(layout.name)'")

        // Apply the layout
        Task { @MainActor in
            await LayoutEngine.shared.applyLayout(layout)
            AppState.shared.markLayoutAsApplied(layout.id)
        }
    }

    // MARK: - Quick Switcher Hotkey

    /// Register the ⌘⇧L hotkey for the Quick Switcher
    func registerQuickSwitcherHotkey() {
        // Unregister if already registered
        if let ref = quickSwitcherHotkeyRef {
            UnregisterEventHotKey(ref)
            quickSwitcherHotkeyRef = nil
        }

        // ⌘⇧L: Command + Shift + L (keyCode 37)
        let carbonMods = UInt32(cmdKey) | UInt32(shiftKey)
        let hotkeyID = EventHotKeyID(signature: OSType(0x4C59_5448), id: quickSwitcherHotkeyID)

        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            37, // L key
            carbonMods,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let ref = hotkeyRef {
            quickSwitcherHotkeyRef = ref
            NSLog("HotkeyManager: Registered Quick Switcher hotkey ⌘⇧L")
        } else {
            NSLog("HotkeyManager: Failed to register Quick Switcher hotkey - status: \(status)")
        }
    }

    // MARK: - Modifier Conversion

    /// Convert NSEvent modifier flags to Carbon modifier flags
    private func carbonModifierFlags(from nsModifiers: UInt) -> UInt32 {
        var carbonMods: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: nsModifiers)

        if flags.contains(.command) {
            carbonMods |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            carbonMods |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonMods |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
        }

        return carbonMods
    }

    // MARK: - Hotkey String Helpers

    /// Convert modifier flags and key code to display string (e.g., "⌘⇧1")
    static func hotkeyString(modifiers: UInt, keyCode: UInt16) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        // Convert key code to character
        if let char = keyCodeToString(keyCode) {
            parts.append(char)
        }

        return parts.joined()
    }

    /// Static key code to string map — created once, reused on every lookup
    private static let keyCodeMap: [UInt16: String] = [
        // Numbers
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",

        // Letters
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E",
        3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",

        // Function keys
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",

        // Special keys
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
        53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Convert key code to string representation
    static func keyCodeToString(_ keyCode: UInt16) -> String? {
        return keyCodeMap[keyCode]
    }
}
