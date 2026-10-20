import Foundation

/// One of today's habits for the phone's checklist.
public struct PhoneHabit: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var goal: String
    public var period: String
    /// "check", "metric" or "milestone".
    public var kind: String
    public var done: Bool
    public var value: Double?
    public var unit: String?
    /// The metric target, such as "7–8 hours".
    public var target: String?
    public var minimum: Double?
    public var maximum: Double?
    /// Filled from the watch or confirmed meals rather than typed.
    public var auto: Bool
    public var minute: Int?
}
public struct PhoneGoal: Codable, Equatable, Sendable {
    public var title: String
    public var done: Int
    public var due: Int
}
/// A tick, number or clear from the phone's checklist. The ID is stable across retries.
public struct PhoneCheckIn: Codable, Equatable, Sendable {
    public var id: String
    public var habitID: String
    public var day: String
    public var completed: Bool?
    public var value: Double?
    public var clear: Bool?
    public init(id: String, habitID: String, day: String, completed: Bool? = nil, value: Double? = nil, clear: Bool? = nil) {
        self.id = id; self.habitID = habitID; self.day = day; self.completed = completed; self.value = value; self.clear = clear
    }
}

extension TrackerDocument {
    /// Today's habits in the Mac's order (period, then time), with goal names and whether each is done.
    public func phoneHabits(today: String) -> [PhoneHabit] {
        let engine = TrackerEngine(document: self)
        let autoIDs = Set([healthHabits.sleep, healthHabits.steps, mealHabits.calories, mealHabits.protein].compactMap { $0?.id })
        let goalNames = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.title) })
        let periods = Period.allCases
        return engine.due(on: today, includeMilestones: true).compactMap { habit -> PhoneHabit? in
            guard let r = habit.revision(on: today) else { return nil }
            let entry = engine.entry(for: habit, day: today)
            return PhoneHabit(id: habit.id.uuidString, title: r.title, goal: goalNames[habit.goalID] ?? "", period: r.period.rawValue,
                              kind: habit.kind == .metric ? "metric" : habit.kind == .milestone ? "milestone" : "check",
                              done: engine.completed(habit, on: today), value: habit.kind == .metric ? entry?.value : nil,
                              unit: r.target?.unit, target: r.target?.label, minimum: r.target?.minimum, maximum: r.target?.maximum,
                              auto: autoIDs.contains(habit.id), minute: r.scheduledMinute)
        }.sorted {
            let a = periods.firstIndex(of: Period(rawValue: $0.period) ?? .daytime)!, b = periods.firstIndex(of: Period(rawValue: $1.period) ?? .daytime)!
            return a != b ? a < b : ($0.minute ?? 1440, $0.title) < ($1.minute ?? 1440, $1.title)
        }
    }
    public func phoneGoals(today: String) -> [PhoneGoal] {
        let engine = TrackerEngine(document: self)
        return goals.compactMap { goal in
            let score = engine.score(on: today, goalID: goal.id)
            return score.scheduled > 0 ? PhoneGoal(title: goal.title, done: score.completed, due: score.scheduled) : nil
        }
    }
    /// Applies a check-in from the phone to a habit due on a past or current day.
    public mutating func applyPhoneCheckIn(_ c: PhoneCheckIn, today: String) throws {
        let engine = TrackerEngine(document: self)
        guard let id = UUID(uuidString: c.habitID), let habit = habits.first(where: { $0.id == id }), engine.date(c.day) != nil, c.day <= today,
              engine.isDue(habit, on: c.day) || engine.entry(for: habit, day: c.day) != nil else {
            throw ValidationError(message: "That habit isn’t scheduled for \(c.day).")
        }
        guard !restDays.contains(c.day) || habit.kind == .milestone else { throw ValidationError(message: "\(c.day) is a rest day. Resume it on the Mac first.") }
        if c.clear == true { checkIns.removeAll { $0.habitID == id && $0.day == c.day }; return }
        if habit.kind == .metric {
            guard let value = c.value, value.isFinite, value >= 0, value <= 1_000_000 else { throw ValidationError(message: "Enter a number of zero or more.") }
            setEntry(CheckIn(habitID: id, day: c.day, value: value))
        } else {
            setEntry(CheckIn(habitID: id, day: c.day, completed: c.completed ?? true))
        }
    }
}
