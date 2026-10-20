import Foundation

public struct Score: Equatable, Sendable {
    public var completed: Int = 0
    public var scheduled: Int = 0
    public init(completed: Int = 0, scheduled: Int = 0) { self.completed = completed; self.scheduled = scheduled }
    public var ratio: Double? { scheduled > 0 ? Double(completed) / Double(scheduled) : nil }
    public var percentLabel: String { ratio.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    public func remaining(target: Double) -> Int { max(0, Int(ceil(Double(scheduled) * target)) - completed) }
}
public struct TrackerEngine: Sendable {
    public let document: TrackerDocument
    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: document.timeZoneID) ?? .current
        c.firstWeekday = 2
        return c
    }
    public init(document: TrackerDocument) { self.document = document }
    public func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, parts.count == 3, (1900...2200).contains(parts[0]),
              let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), self.key(d) == key else { return nil }
        return d
    }
    public func adding(_ days: Int, to key: String) -> String {
        guard let d = date(key), let result = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return self.key(result)
    }
    public func days(from start: String, through end: String) -> [String] {
        guard start <= end, let a = date(start), let b = date(end),
              let count = calendar.dateComponents([.day], from: a, to: b).day, count >= 0 else { return [] }
        return (0...min(count, 3660)).map { adding($0, to: start) }
    }
    public func isDue(_ habit: Habit, on day: String) -> Bool {
        guard day >= habit.createdDay, habit.archivedDay.map({ day < $0 }) ?? true,
              let r = habit.revision(on: day), let g = document.goals.first(where: { $0.id == habit.goalID }),
              let w = g.window(on: day), day >= w.start, day <= w.end,
              let d = date(day) else { return false }
        if habit.kind == .milestone { return r.schedule.once == day }
        return r.schedule.weekdays.contains(calendar.component(.weekday, from: d))
    }
    public func due(on day: String, includeMilestones: Bool = false) -> [Habit] {
        document.habits.filter { (includeMilestones || $0.kind != .milestone) && isDue($0, on: day) }
    }
    public func reviewTasks(on day: String) -> [Habit] {
        document.habits.filter { isDue($0, on: day) || (entry(for: $0, day: day) != nil && $0.revision(on: day) != nil) }
    }
    public func entry(for habit: Habit, day: String) -> CheckIn? {
        document.checkIns.first { $0.habitID == habit.id && $0.day == day }
    }
    public func completed(_ habit: Habit, on day: String) -> Bool {
        guard let entry = entry(for: habit, day: day), let r = habit.revision(on: day) else { return false }
        if habit.kind == .metric { return entry.value.map { r.target?.accepts($0) ?? false } ?? false }
        return entry.completed
    }
    public func score(on day: String, goalID: UUID? = nil) -> Score {
        if document.restDays.contains(day) { return Score() }
        let habits = due(on: day).filter { goalID == nil || $0.goalID == goalID }
        return Score(completed: habits.filter { completed($0, on: day) }.count, scheduled: habits.count)
    }
    public func score(from start: String, through end: String, goalID: UUID? = nil) -> Score {
        days(from: start, through: end).reduce(into: Score()) { sum, day in
            let daily = score(on: day, goalID: goalID)
            sum.completed += daily.completed; sum.scheduled += daily.scheduled
        }
    }
    public func closedScore(today: String) -> Score {
        score(from: document.cycle.start, through: min(document.cycle.end, adding(-1, to: today)))
    }
    public func dayNumber(_ today: String) -> Int {
        guard today >= document.cycle.start else { return 0 }
        return min(days(from: document.cycle.start, through: document.cycle.end).count,
                   days(from: document.cycle.start, through: today).count)
    }
    public func evolution(today: String) -> Double {
        let plan = score(from: document.cycle.start, through: document.cycle.end)
        let earned = score(from: document.cycle.start, through: min(today, document.cycle.end)).completed
        return plan.scheduled > 0 ? min(1, Double(earned) / (Double(plan.scheduled) * document.cycle.target)) : 0
    }
    public func milestoneCompleted(_ habit: Habit) -> Bool {
        document.checkIns.contains { $0.habitID == habit.id && $0.completed && $0.day >= document.cycle.start && $0.day <= document.cycle.end }
    }
}

public extension TrackerDocument {
    static func seeded(today: String, timeZoneID: String = "Asia/Kolkata") -> TrackerDocument {
        // A neutral starter plan for new installs; every part of it can be edited or replaced.
        var doc = TrackerDocument(timeZoneID: timeZoneID, cycle: Cycle(title: "Foundation", start: today, end: today), goals: [], habits: [])
        let engine = TrackerEngine(document: doc)
        let end = engine.adding(83, to: today)
        doc.cycle.end = end
        doc.goals = [("Health & fitness", "figure.strengthtraining.traditional"), ("Self-care", "sparkles"),
                     ("Mind & focus", "brain.head.profile"), ("Teeth", "mouth")].map {
            Goal(title: $0.0, symbol: $0.1, windows: [GoalWindow(effectiveDay: today, start: today, end: end)])
        }
        func add(_ title: String, _ goal: Int, _ period: Period, _ note: String = "",
                 target: MetricTarget? = nil, days: [Int] = Array(1...7)) {
            doc.habits.append(Habit(goalID: doc.goals[goal].id, kind: target == nil ? .check : .metric,
                createdDay: today, revisions: [HabitRevision(effectiveDay: today, title: title, note: note,
                    period: period, schedule: Schedule(weekdays: days), target: target)]))
        }
        add("Sleep", 0, .morning, target: MetricTarget(minimum: 7, maximum: 8, unit: "hours"))
        add("Take medication", 1, .morning)
        add("Morning skincare", 1, .morning)
        add("Meditate 10 minutes", 2, .morning)
        add("Stretch 10 minutes", 0, .daytime)
        add("Walk 10,000 steps", 0, .daytime, target: MetricTarget(minimum: 10000, unit: "steps"))
        add("Calorie target", 0, .daytime, "Under 1,700 kcal", target: MetricTarget(maximum: 1699.9, unit: "kcal"))
        add("Protein target", 0, .daytime, target: MetricTarget(minimum: 100, unit: "g"))
        add("Gym session", 0, .daytime, "Four sessions a week", days: [2,4,6,7])
        add("Wind down before bed", 0, .evening, "Two hours before sleep")
        add("Evening skincare", 1, .evening)
        add("Brush & floss", 3, .evening)
        add("No sugar or junk food", 0, .evening, "Confirm at day’s end")
        add("Read 20 minutes", 2, .evening)
        add("Plan tomorrow", 2, .evening, "Confirm at day’s end")
        for (title, offset) in [("Dental check-up", 14), ("Book a cleaning", 42)] {
            doc.habits.append(Habit(goalID: doc.goals[3].id, kind: .milestone, createdDay: today,
                revisions: [HabitRevision(effectiveDay: today, title: title, period: .daytime,
                    schedule: Schedule(weekdays: [], once: engine.adding(offset, to: today)))]))
        }
        return doc
    }
}
