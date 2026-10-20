import Foundation

public extension TrackerDocument {
    mutating func resetDay(_ day: String) {
        checkIns.removeAll { $0.day == day }
        restDays.remove(day)
    }
    mutating func resetProgress() {
        checkIns.removeAll()
        restDays.removeAll()
    }
    /// Starts a new scoring window. Earlier dated records and revisions remain available.
    mutating func restart(on today: String, length: Int) {
        let old = cycle
        let engine = TrackerEngine(document: self)
        previousCycles.append(Cycle(title: old.title, start: old.start,
            end: min(old.end, engine.adding(-1, to: today)), target: old.target))
        previousCycles.removeAll { $0.end < $0.start }
        cycle.start = today
        cycle.end = engine.adding(length - 1, to: today)
        // A restart clears records from the new start onward, including today's partial log.
        checkIns.removeAll { $0.day >= today }
        restDays = restDays.filter { $0 < today }
        for i in goals.indices {
            goals[i].revise(GoalWindow(effectiveDay: today, start: today, end: cycle.end))
        }
        for i in habits.indices where habits[i].archivedDay == nil && habits[i].kind == .milestone {
            var r = habits[i].latest
            if let due = r.schedule.once {
                let offset = max(0, engine.days(from: old.start, through: due).count - 1)
                r.effectiveDay = today
                r.schedule.once = engine.adding(min(offset, length - 1), to: today)
                habits[i].revise(r)
            }
        }
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public let id: String
    public let date: Date
    public let title: String
    public let body: String
}
public extension TrackerEngine {
    /// At most 60 requests. Refreshed on launch, activation, a new day, and every saved change.
    func plannedReminders(now: Date) -> [PlannedReminder] {
        guard document.reminders.enabled else { return [] }
        let today = key(now)
        var result: [PlannedReminder] = []
        for day in days(from: max(today, document.cycle.start), through: min(document.cycle.end, adding(29, to: today))) {
            guard !document.restDays.contains(day), let date = date(day) else { continue }
            let pending = due(on: day).filter { !completed($0, on: day) }
            for (slot, minute) in [("morning", document.reminders.morningMinute), ("evening", document.reminders.eveningMinute)] {
                let relevant = slot == "morning" ? pending.filter { $0.revision(on: day)?.period == .morning } : pending
                guard !relevant.isEmpty,
                      let fire = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date), fire > now else { continue }
                result.append(PlannedReminder(id: "ascend.\(day).\(slot)", date: fire,
                    title: slot == "morning" ? "Your morning protocol" : "A moment for yourself",
                    body: slot == "morning" ? "Open Ascend for your morning check-in." : "Review today’s protocol and log what you’ve done."))
            }
        }
        return result
    }
}
