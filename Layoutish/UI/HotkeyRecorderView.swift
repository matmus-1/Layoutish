//
//  HotkeyRecorderView.swift
//  Layoutish
//
//  Created by Ross Mckinlay on 30/01/2026.
//

import SwiftUI
import AppKit

/// A view that records keyboard shortcuts
struct HotkeyRecorderView: NSViewRepresentable {
    let currentHotkey: String?
    let onHotkeyRecorded: (UInt, UInt16) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.currentHotkey = currentHotkey
        view.onHotkeyRecorded = onHotkeyRecorded
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.currentHotkey = currentHotkey
    }
}

/// NSView that captures keyboard events for hotkey recording
class HotkeyRecorderNSView: NSView {
    var currentHotkey: String? {
        didSet {
            updateDisplay()
        }
    }
    var onHotkeyRecorded: ((UInt, UInt16) -> Void)?

    private var isRecording = false
    private var textField: NSTextField!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Create text field for display
        textField = NSTextField()
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .center
        textField.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateDisplay()
    }

    private func updateDisplay() {
        if isRecording {
            textField.stringValue = "Press keys..."
            textField.textColor = NSColor.placeholderTextColor
        } else if let hotkey = currentHotkey {
            textField.stringValue = hotkey
            textField.textColor = NSColor.labelColor
        } else {
            textField.stringValue = "Click to record"
            textField.textColor = NSColor.placeholderTextColor
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        updateDisplay()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Ignore modifier-only keys
        let keyCode = event.keyCode

        // Check if any non-modifier key was pressed
        let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Modifier key codes
        if modifierOnlyKeyCodes.contains(keyCode) {
            return
        }

        // Require at least one modifier (Cmd, Option, Control, or Shift)
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            // Show feedback that modifiers are required
            NSSound.beep()
            return
        }

        // Record the hotkey
        isRecording = false
        onHotkeyRecorded?(modifiers.rawValue, keyCode)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateDisplay()
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        // Update display while recording to show current modifiers
        if isRecording {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !modifiers.isEmpty {
                var parts: [String] = []
                if modifiers.contains(.control) { parts.append("⌃") }
                if modifiers.contains(.option) { parts.append("⌥") }
                if modifiers.contains(.shift) { parts.append("⇧") }
                if modifiers.contains(.command) { parts.append("⌘") }
                textField.stringValue = parts.joined() + "..."
                textField.textColor = NSColor.labelColor
            } else {
                textField.stringValue = "Press keys..."
                textField.textColor = NSColor.placeholderTextColor
            }
        }
    }
}
