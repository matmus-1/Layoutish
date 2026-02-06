//
//  ScheduleSettingsView.swift
//  Layoutish
//
//  Settings UI for time-based layout auto-switching
//  NOTE: Uses inline form instead of popover to avoid NSPopover nesting crash
//

import SwiftUI

// MARK: - Schedule Popover View (standalone popover from footer)

struct SchedulePopoverView: View {
    @ObservedObject private var scheduleManager = ScheduleManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Scheduling")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                ScheduleSettingsSection()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(maxHeight: scheduleManager.isEnabled ? 400 : nil)
        }
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.2), value: scheduleManager.isEnabled)
    }
}

// MARK: - Schedule Settings Section

struct ScheduleSettingsSection: View {
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @ObservedObject private var appState = AppState.shared
    @State private var showAddForm = false

    // Inline add form state
    @State private var newName = ""
    @State private var newLayoutId: UUID?
    @State private var newStartHour = 9
    @State private var newStartMinute = 0
    @State private var newEndHour = 17
    @State private var newEndMinute = 0
    @State private var newDays: [Bool] = [true, true, true, true, true, false, false]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Global enable toggle
            Toggle(isOn: $scheduleManager.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Switch Layouts")
                        .font(.system(size: 13))
                    Text("Automatically apply layouts at scheduled times")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if scheduleManager.isEnabled {
                // Schedule list
                if scheduleManager.schedules.isEmpty && !showAddForm {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("No schedules yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else if !scheduleManager.schedules.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(scheduleManager.schedules) { schedule in
                            ScheduleRow(schedule: schedule)
                        }
                    }
                }

                // Inline add form
                if showAddForm {
                    inlineAddForm
                } else {
                    // Add button
                    Button(action: {
                        resetForm()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAddForm = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text("Add Schedule")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.layouts.isEmpty)
                }
            }
        }
    }

    // MARK: - Inline Add Form

    private var inlineAddForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text("New Schedule")
                .font(.system(size: 13, weight: .semibold))

            // Name
            TextField("Name (e.g. Work Hours)", text: $newName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            // Layout picker
            HStack(spacing: 6) {
                Text("Layout:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $newLayoutId) {
                    Text("Select...")
                        .tag(nil as UUID?)
                    ForEach(appState.layouts) { layout in
                        Text(layout.name)
                            .tag(layout.id as UUID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }

            // Time range
            HStack(spacing: 6) {
                Text("Time:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                InlineTimePicker(hour: $newStartHour, minute: $newStartMinute)
                Text("–")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                InlineTimePicker(hour: $newEndHour, minute: $newEndMinute)
            }

            // Days of week
            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Button(action: {
                        newDays[index].toggle()
                    }) {
                        Text(dayLabels[index])
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(newDays[index] ? Color.blue : Color.secondary.opacity(0.15))
                            )
                            .foregroundColor(newDays[index] ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // Quick day presets
            HStack(spacing: 10) {
                Button("Weekdays") {
                    newDays = [true, true, true, true, true, false, false]
                }
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)

                Button("Weekends") {
                    newDays = [false, false, false, false, false, true, true]
                }
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)

                Button("Every day") {
                    newDays = Array(repeating: true, count: 7)
                }
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }

            // Action buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAddForm = false
                    }
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Add") {
                    addSchedule()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .disabled(newName.isEmpty || newLayoutId == nil || !newDays.contains(true))
            }

            Divider()
        }
    }

    // MARK: - Helpers

    private func resetForm() {
        newName = ""
        newLayoutId = appState.layouts.first?.id
        newStartHour = 9
        newStartMinute = 0
        newEndHour = 17
        newEndMinute = 0
        newDays = [true, true, true, true, true, false, false]
    }

    private func addSchedule() {
        guard let layoutId = newLayoutId else { return }

        let schedule = LayoutSchedule(
            layoutId: layoutId,
            name: newName.isEmpty ? "Schedule" : newName,
            startHour: newStartHour,
            startMinute: newStartMinute,
            endHour: newEndHour,
            endMinute: newEndMinute,
            daysOfWeek: newDays
        )

        scheduleManager.addSchedule(schedule)
        withAnimation(.easeInOut(duration: 0.2)) {
            showAddForm = false
        }
    }
}

// MARK: - Schedule Row

private struct ScheduleRow: View {
    let schedule: LayoutSchedule
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @ObservedObject private var appState = AppState.shared

    private var layoutName: String {
        appState.getLayout(by: schedule.layoutId)?.name ?? "Unknown Layout"
    }

    private var isActive: Bool {
        scheduleManager.activeSchedule?.id == schedule.id
    }

    var body: some View {
        HStack(spacing: 8) {
            // Enable toggle
            Button(action: {
                scheduleManager.toggleSchedule(schedule)
            }) {
                Image(systemName: schedule.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(schedule.enabled ? (isActive ? Color.successGreen : .blue) : .secondary)
            }
            .buttonStyle(.plain)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(schedule.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.successGreen)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.successGreenBackground.opacity(0.5))
                            )
                    }
                }

                Text("\(layoutName) • \(schedule.timeRangeDescription) • \(schedule.daysDescription)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Delete
            Button(action: {
                scheduleManager.removeSchedule(schedule)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.successGreenBackground.opacity(0.3) : Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Inline Time Picker Component

private struct InlineTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack(spacing: 1) {
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 50)

            Text(":")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("", selection: $minute) {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 50)
        }
    }
}
