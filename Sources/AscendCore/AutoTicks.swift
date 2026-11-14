import Foundation

/// Medicines grouped by time of day, so one tap logs every dose due at that moment.
public enum MedMoment: String, CaseIterable, Sendable {
    case morning = "Morning", evening = "Evening", night = "Night"
    /// Before noon is morning, noon to 10 pm is evening, from 10 pm is night.
    public static func of(minute: Int) -> MedMoment { minute < 12 * 60 ? .morning : minute < 22 * 60 ? .evening : .night }
}

public struct MedMomentGroup: Equatable, Sendable, Identifiable {
    public var moment: MedMoment
    public var slots: [MedSlot]
    public var id: String { moment.rawValue }
    public var taken: Int { slots.filter { $0.taken != nil }.count }
    public var allTaken: Bool { !slots.isEmpty && taken == slots.count }
    /// The first dose time, when the reminder fires.
    public var minute: Int { slots.map(\.minute).min() ?? 0 }
    /// "Sola Top · Helio Tone · Calmora"
    public var names: String {
        var seen: [String] = []
        for s in slots where !seen.contains(s.medicine.title) { seen.append(s.medicine.title) }
        return seen.joined(separator: " · ")
    }
}

extension MedCabinet {
    /// Only moments with at least one dose that day, in time order.
    public func moments(on day: String, engine: TrackerEngine) -> [MedMomentGroup] {
        let all = slots(on: day, engine: engine)
        return MedMoment.allCases.compactMap { m in
            let s = all.filter { MedMoment.of(minute: $0.minute) == m }
            return s.isEmpty ? nil : MedMomentGroup(moment: m, slots: s)
        }
    }
}

extension TrackerDocument {
    /// Marks every dose in one moment taken (or clears them all) and updates the meds habit.
    public mutating func setMoment(_ moment: MedMoment, day: String, taken: Bool, at: Date, source: String, today: String) throws {
        let engine = TrackerEngine(document: self)
        guard day <= today, let group = meds.moments(on: day, engine: engine).first(where: { $0.moment == moment }) else {
            throw ValidationError(message: "No \(moment.rawValue.lowercased()) medicines on \(day).")
        }
        for slot in group.slots {
            if taken, slot.taken != nil { continue }   // keep the time it was really taken
            meds.doses.removeAll { $0.medID == slot.medicine.id && $0.day == day && $0.minute == slot.minute }
            if taken { meds.doses.append(MedDose(medID: slot.medicine.id, day: day, minute: slot.minute, takenAt: at.timeIntervalSince1970, source: source)) }
        }
        applyMedDoses(on: day, today: today)
    }
}

// MARK: - Habits that tick themselves

extension TrackerDocument {
    /// Watch workout types that count as a gym session. Mi Fitness's gym workout arrives as type 45.
    public static let gymWorkoutTypes: Set<String> = ["Exercise type 45", "Exercise type 70", "Exercise type 81"]
    public static let gymMinimumMinutes = 20.0

    private func activeCheck(_ match: (String) -> Bool) -> Habit? {
        habits.first { $0.archivedDay == nil && $0.kind == .check && match($0.latest.title.lowercased()) }
    }
    public var gymHabit: Habit? { activeCheck { $0.contains("gym") } }
    public var windDownHabit: Habit? { activeCheck { $0.contains("wind down") } }
    public var sweetsHabit: Habit? {
        guard let id = diet?.sweetsHabitID else { return nil }
        return habits.first { $0.id == id && $0.archivedDay == nil }
    }

    /// Minutes of gym-type watch workouts that started on `day`.
    public func gymMinutes(on day: String, engine: TrackerEngine) -> Double {
        health.records(.workout, on: day, engine: engine).filter { Self.gymWorkoutTypes.contains($0.detail) }.map(\.value).reduce(0, +)
    }

    /// Where an auto tick came from, for the habit row.
    public func autoTickSource(_ habit: Habit, day: String) -> String? {
        guard health.filled?["\(habit.id.uuidString)|\(day)"] != nil, engine.entry(for: habit, day: day) != nil else { return nil }
        if habit.id == gymHabit?.id { return "Watch workout" }
        if habit.id == windDownHabit?.id { return "Screen time + sleep" }
        if habit.id == sweetsHabit?.id { return "Food log" }
        return nil
    }
    private var engine: TrackerEngine { TrackerEngine(document: self) }

    /// Ticks Gym (from watch workouts), No sweets (a logged day with no unplanned sweet) and Wind down
    /// (`windDown`: day → screens stayed off before sleep) for the last two weeks.
    /// Like the steps fill, it remembers each tick it wrote; a check-in made or changed by hand is never touched.
    public mutating func applyAutoTicks(today: String, windDown: [String: Bool]) {
        let engine = TrackerEngine(document: self)
        var filled = health.filled ?? [:]
        func set(_ habit: Habit, _ day: String, _ on: Bool?) {
            let key = "\(habit.id.uuidString)|\(day)"
            let current = engine.entry(for: habit, day: day)
            if current != nil && filled[key] == nil { return }          // yours
            if on == true {
                if current?.completed != true { setEntry(CheckIn(habitID: habit.id, day: day, completed: true)) }
                filled[key] = 1
            } else if current != nil || filled[key] != nil {
                checkIns.removeAll { $0.habitID == habit.id && $0.day == day }
                filled[key] = nil
            }
        }
        let gym = gymHabit, wind = windDownHabit, sweets = sweetsHabit
        let first = max(cycle.start, engine.adding(-13, to: today))
        for day in engine.days(from: first, through: min(today, cycle.end)) where !restDays.contains(day) {
            if let gym { set(gym, day, gymMinutes(on: day, engine: engine) >= Self.gymMinimumMinutes) }
            if let sweets, engine.isDue(sweets, on: day), let diet {
                let logged = meals.on(day).contains { $0.confirmed }
                set(sweets, day, logged && diet.unplannedSweets(meals, day: day, calendar: engine.calendar).isEmpty)
            }
            if let wind, engine.isDue(wind, on: day) { set(wind, day, windDown[day]) }
        }
        health.filled = filled.isEmpty ? nil : filled
    }
}

// MARK: - Wind down from screen time

extension ScreenTimeArchive {
    /// Screen seconds between two instants across all devices, prorating hourly buckets.
    /// Nil when no phone has a synced day covering the start (so a missing sync never counts as "screens off").
    public func seconds(from a: Double, to b: Double) -> Double? {
        let phone = devices.filter { $0.source != "macKnowledge" }
        let phoneCovers = phone.contains { d in d.days.contains { $0.start <= a && $0.end > a } && d.days.contains { $0.start < b && $0.end >= b } }
        guard phoneCovers, b > a else { return nil }
        var total = 0.0
        for d in devices {
            for day in d.days where day.end > a && day.start < b {
                for h in day.hours {
                    let overlap = min(b, h.start + 3600) - max(a, h.start)
                    if overlap > 0 { total += h.seconds * overlap / 3600 }
                }
            }
        }
        return total
    }
}

public enum WindDown {
    public static let window = 2.0 * 3600
    public static let allowedSeconds = 15.0 * 60
    /// For each evening before `today`: true when screens stayed under 15 minutes in the 2 hours before the watch saw you fall asleep.
    /// Days without a synced night or phone screen time are left out.
    public static func nights(health: HealthArchive, screen: ScreenTimeArchive, engine: TrackerEngine, today: String, days: Int = 14) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for day in engine.days(from: engine.adding(-days, to: today), through: engine.adding(-1, to: today)) {
            guard let night = health.sleepSessions(on: engine.adding(1, to: day), engine: engine).first,
                  let used = screen.seconds(from: night.start - window, to: night.start) else { continue }
            out[day] = used <= allowedSeconds
        }
        return out
    }
}
