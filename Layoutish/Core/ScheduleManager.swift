//
//  ScheduleManager.swift
//  Layoutish
//
//  Manages time-based layout auto-switching
//

import Foundation
import Combine

@MainActor
final class ScheduleManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ScheduleManager()

    // MARK: - Published Properties

    @Published var schedules: [LayoutSchedule] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if isEnabled {
                startScheduleChecking()
            } else {
                stopScheduleChecking()
            }
        }
    }

    /// The schedule currently active (if any)
    @Published var activeSchedule: LayoutSchedule?

    // MARK: - Private

    private let storageKey = "com.appish.layoutish.schedules"
    private let enabledKey = "com.appish.layoutish.schedulesEnabled"
    private var checkTimer: Timer?
    private var lastAppliedScheduleId: UUID?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    deinit {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        loadSchedules()

        // Auto-save when schedules change
        $schedules
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveSchedules()
            }
            .store(in: &cancellables)

        if isEnabled {
            startScheduleChecking()
        }
    }

    // MARK: - Schedule Checking

    private func startScheduleChecking() {
        stopScheduleChecking()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSchedules()
            }
        }

        // Check immediately on start
        checkSchedules()
        NSLog("ScheduleManager: Started schedule checking (\(schedules.count) schedules)")
    }

    private func stopScheduleChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
        activeSchedule = nil
        lastAppliedScheduleId = nil
    }

    private func checkSchedules() {
        guard isEnabled else { return }

        // Find the first active schedule
        var foundActive: LayoutSchedule? = nil

        for schedule in schedules {
            if schedule.isActiveNow() {
                foundActive = schedule

                // Only apply if we haven't already applied this schedule
                if lastAppliedScheduleId != schedule.id {
                    applyScheduledLayout(schedule)
                }
                break
            }
        }

        // If no schedule is active, reset so we can re-trigger when one becomes active
        if foundActive == nil && lastAppliedScheduleId != nil {
            lastAppliedScheduleId = nil
        }

        activeSchedule = foundActive
    }

    private func applyScheduledLayout(_ schedule: LayoutSchedule) {
        guard let layout = AppState.shared.getLayout(by: schedule.layoutId) else {
            NSLog("ScheduleManager: Layout not found for schedule '\(schedule.name)'")
            return
        }

        lastAppliedScheduleId = schedule.id

        Task {
            await LayoutEngine.shared.applyLayout(layout)
            NSLog("ScheduleManager: Applied layout '\(layout.name)' from schedule '\(schedule.name)'")
        }
    }

    // MARK: - CRUD

    func addSchedule(_ schedule: LayoutSchedule) {
        schedules.append(schedule)
        NSLog("ScheduleManager: Added schedule '\(schedule.name)'")
        if isEnabled { checkSchedules() }
    }

    func removeSchedule(_ schedule: LayoutSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        if lastAppliedScheduleId == schedule.id {
            lastAppliedScheduleId = nil
        }
        NSLog("ScheduleManager: Removed schedule '\(schedule.name)'")
    }

    func updateSchedule(_ schedule: LayoutSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
            NSLog("ScheduleManager: Updated schedule '\(schedule.name)'")
        }
    }

    func toggleSchedule(_ schedule: LayoutSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index].enabled.toggle()
            if !schedules[index].enabled && lastAppliedScheduleId == schedule.id {
                lastAppliedScheduleId = nil
            }
        }
    }

    // MARK: - Persistence

    private func saveSchedules() {
        do {
            let data = try JSONEncoder().encode(schedules)
            UserDefaults.standard.set(data, forKey: storageKey)
            NSLog("ScheduleManager: Saved \(schedules.count) schedules")
        } catch {
            NSLog("ScheduleManager: Failed to save - \(error.localizedDescription)")
        }
    }

    private func loadSchedules() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            schedules = try JSONDecoder().decode([LayoutSchedule].self, from: data)
            NSLog("ScheduleManager: Loaded \(schedules.count) schedules")
        } catch {
            NSLog("ScheduleManager: Failed to load - \(error.localizedDescription)")
        }
    }
}
