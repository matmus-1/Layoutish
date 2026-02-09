//
//  LayoutSchedule.swift
//  Layoutish
//
//  Time-based layout scheduling model
//

import Foundation

/// A time-based rule for auto-applying a layout
struct LayoutSchedule: Codable, Identifiable, Equatable {
    let id: UUID
    var layoutId: UUID
    var enabled: Bool
    var name: String

    // Time range (24-hour format)
    var startHour: Int      // 0-23
    var startMinute: Int    // 0-59
    var endHour: Int        // 0-23
    var endMinute: Int      // 0-59

    // Days of week: index 0 = Monday, 6 = Sunday
    var daysOfWeek: [Bool]

    init(
        id: UUID = UUID(),
        layoutId: UUID,
        enabled: Bool = true,
        name: String,
        startHour: Int = 9,
        startMinute: Int = 0,
        endHour: Int = 17,
        endMinute: Int = 0,
        daysOfWeek: [Bool] = [true, true, true, true, true, false, false]
    ) {
        self.id = id
        self.layoutId = layoutId
        self.enabled = enabled
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.daysOfWeek = daysOfWeek
    }

    /// Formatted time string, e.g. "09:00 - 17:00"
    var timeRangeDescription: String {
        String(format: "%02d:%02d – %02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    /// Short days string, e.g. "Mon-Fri" or "Mon, Wed, Fri"
    /// Uses locale-aware short weekday names (Mon=index 0 through Sun=index 6)
    var daysDescription: String {
        // Calendar.shortWeekdaySymbols is Sun-indexed (0=Sun), remap to Mon-indexed
        let symbols = Calendar.current.shortWeekdaySymbols  // ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        let dayNames = Array(symbols[1...]) + [symbols[0]]  // ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        let activeDays = daysOfWeek.enumerated().compactMap { $0.element ? dayNames[$0.offset] : nil }

        if activeDays.isEmpty { return "No days" }
        if activeDays.count == 7 { return "Every day" }

        // Check weekday/weekend patterns using indices rather than localized strings
        let weekdayPattern: [Bool] = [true, true, true, true, true, false, false]
        let weekendPattern: [Bool] = [false, false, false, false, false, true, true]
        if daysOfWeek == weekdayPattern { return "Weekdays" }
        if daysOfWeek == weekendPattern { return "Weekends" }

        return activeDays.joined(separator: ", ")
    }

    /// Check if the schedule is active right now
    func isActiveNow() -> Bool {
        guard enabled else { return false }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)

        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else {
            return false
        }

        // Convert Calendar weekday (1=Sun, 2=Mon..7=Sat) to our index (0=Mon..6=Sun)
        let dayIndex = (weekday - 2 + 7) % 7

        guard daysOfWeek.indices.contains(dayIndex), daysOfWeek[dayIndex] else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes <= endMinutes {
            // Normal range: e.g., 09:00 - 17:00
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight range: e.g., 22:00 - 06:00
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }
}
