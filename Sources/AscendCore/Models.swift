import Foundation

public enum Period: String, Codable, CaseIterable, Sendable {
    case morning = "Morning", daytime = "Daytime", evening = "Evening"
}
public enum HabitKind: String, Codable, CaseIterable, Sendable {
    case check = "Check-in", metric = "Number", milestone = "One-off"
}
public struct MetricTarget: Codable, Equatable, Sendable {
    public var minimum: Double?
    public var maximum: Double?
    public var unit: String
    public init(minimum: Double? = nil, maximum: Double? = nil, unit: String) {
        self.minimum = minimum; self.maximum = maximum; self.unit = unit
    }
    public func accepts(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value >= (minimum ?? 0) && value <= (maximum ?? .infinity)
    }
    public var label: String {
        if let a = minimum, let b = maximum { return "\(a.pretty)–\(b.pretty) \(unit)" }
        if let a = minimum { return "\(a.pretty)+ \(unit)" }
        if let b = maximum { return "≤ \(b.pretty) \(unit)" }
        return unit
    }
}
public struct Schedule: Codable, Equatable, Sendable {
    public var weekdays: [Int]
    public var once: String?
    public init(weekdays: [Int] = Array(1...7), once: String? = nil) {
        self.weekdays = weekdays; self.once = once
    }
    public var label: String {
        if let once { return once }
        if Set(weekdays) == Set(1...7) { return "Daily" }
        let labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return weekdays.sorted().filter { (1...7).contains($0) }.map { labels[$0 - 1] }.joined(separator: " · ")
    }
}
public struct HabitRevision: Codable, Equatable, Sendable {
    public var effectiveDay: String
    public var title: String
    public var note: String
    public var period: Period
    public var schedule: Schedule
    public var target: MetricTarget?
    public var scheduledMinute: Int?
    public init(effectiveDay: String, title: String, note: String = "", period: Period,
                schedule: Schedule = Schedule(), target: MetricTarget? = nil, scheduledMinute: Int? = nil) {
        self.effectiveDay = effectiveDay; self.title = title; self.note = note
        self.period = period; self.schedule = schedule; self.target = target; self.scheduledMinute = scheduledMinute
    }
}
public struct Habit: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var goalID: UUID
    public var kind: HabitKind
    public var createdDay: String
    public var archivedDay: String?
    public var revisions: [HabitRevision]
    public init(id: UUID = UUID(), goalID: UUID, kind: HabitKind, createdDay: String,
                archivedDay: String? = nil, revisions: [HabitRevision]) {
        self.id = id; self.goalID = goalID; self.kind = kind; self.createdDay = createdDay
        self.archivedDay = archivedDay; self.revisions = revisions
    }
    public func revision(on day: String) -> HabitRevision? {
        revisions.filter { $0.effectiveDay <= day }.max { $0.effectiveDay < $1.effectiveDay }
    }
    public var latest: HabitRevision { revisions.max { $0.effectiveDay < $1.effectiveDay }! }
    public mutating func revise(_ revision: HabitRevision) {
        revisions.removeAll { $0.effectiveDay == revision.effectiveDay }
        revisions.append(revision)
        revisions.sort { $0.effectiveDay < $1.effectiveDay }
    }
}
public struct GoalWindow: Codable, Equatable, Sendable {
    public var effectiveDay: String
    public var start: String
    public var end: String
    public init(effectiveDay: String, start: String, end: String) {
        self.effectiveDay = effectiveDay; self.start = start; self.end = end
    }
}
public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var symbol: String
    public var windows: [GoalWindow]
    public init(id: UUID = UUID(), title: String, symbol: String = "flag", windows: [GoalWindow]) {
        self.id = id; self.title = title; self.symbol = symbol; self.windows = windows
    }
    public var latest: GoalWindow { windows.max { $0.effectiveDay < $1.effectiveDay }! }
    public func window(on day: String) -> GoalWindow? {
        windows.filter { $0.effectiveDay <= day }.max { $0.effectiveDay < $1.effectiveDay }
    }
    public mutating func revise(_ window: GoalWindow) {
        windows.removeAll { $0.effectiveDay == window.effectiveDay }
        windows.append(window)
        windows.sort { $0.effectiveDay < $1.effectiveDay }
    }
}
public struct CheckIn: Codable, Equatable, Sendable {
    public var habitID: UUID
    public var day: String
    public var completed: Bool
    public var value: Double?
    public init(habitID: UUID, day: String, completed: Bool = false, value: Double? = nil) {
        self.habitID = habitID; self.day = day; self.completed = completed; self.value = value
    }
}
public struct Cycle: Codable, Equatable, Sendable {
    public var title: String
    public var start: String
    public var end: String
    public var target: Double
    public init(title: String, start: String, end: String, target: Double = 0.75) {
        self.title = title; self.start = start; self.end = end; self.target = target
    }
}
public struct ReminderPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var morningMinute = 9 * 60
    public var eveningMinute = 21 * 60
    public var sound = false
    public init() {}
}
public struct TrackerDocument: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var timeZoneID: String
    public var cycle: Cycle
    public var goals: [Goal]
    public var habits: [Habit]
    public var checkIns: [CheckIn]
    public var avatarFinish: String
    public var restDays: Set<String> = []
    public var previousCycles: [Cycle] = []
    public var reminders = ReminderPreferences()
    public var routine = RoutinePreferences()
    public var urgeLogs: [UrgeLog] = []
    public var health = HealthArchive()
    public var wellbeing = WellbeingJournal()
    public var meals = MealLog()
    public var meds = MedCabinet()
    public var notes = NoteBook()
    public var photos = PhotoAlbum()
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, timeZoneID, cycle, goals, habits, checkIns, avatarFinish, restDays, previousCycles, reminders, routine, urgeLogs, health, wellbeing, meals, meds, notes, photos
        case legacyUrges = "smokeUrges"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try c.decode(Int.self, forKey: .schemaVersion)
        schemaVersion = [1, 2].contains(storedVersion) ? 3 : storedVersion
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        cycle = try c.decode(Cycle.self, forKey: .cycle)
        goals = try c.decode([Goal].self, forKey: .goals)
        habits = try c.decode([Habit].self, forKey: .habits)
        checkIns = try c.decode([CheckIn].self, forKey: .checkIns)
        avatarFinish = try c.decode(String.self, forKey: .avatarFinish)
        restDays = try c.decodeIfPresent(Set<String>.self, forKey: .restDays) ?? []
        previousCycles = try c.decodeIfPresent([Cycle].self, forKey: .previousCycles) ?? []
        reminders = try c.decodeIfPresent(ReminderPreferences.self, forKey: .reminders) ?? ReminderPreferences()
        routine = try c.decodeIfPresent(RoutinePreferences.self, forKey: .routine) ?? RoutinePreferences()
        urgeLogs = try c.decodeIfPresent([UrgeLog].self, forKey: .urgeLogs) ?? c.decodeIfPresent([UrgeLog].self, forKey: .legacyUrges) ?? []
        health = try c.decodeIfPresent(HealthArchive.self, forKey: .health) ?? HealthArchive()
        wellbeing = try c.decodeIfPresent(WellbeingJournal.self, forKey: .wellbeing) ?? WellbeingJournal()
        meals = try c.decodeIfPresent(MealLog.self, forKey: .meals) ?? MealLog()
        meds = try c.decodeIfPresent(MedCabinet.self, forKey: .meds) ?? MedCabinet()
        notes = try c.decodeIfPresent(NoteBook.self, forKey: .notes) ?? NoteBook()
        photos = try c.decodeIfPresent(PhotoAlbum.self, forKey: .photos) ?? PhotoAlbum()
        for i in habits.indices {
            for j in habits[i].revisions.indices where habits[i].revisions[j].title == "No smoking" {
                habits[i].revisions[j].title = "Stay intentional"
            }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(timeZoneID, forKey: .timeZoneID)
        try c.encode(cycle, forKey: .cycle)
        try c.encode(goals, forKey: .goals)
        try c.encode(habits, forKey: .habits)
        try c.encode(checkIns, forKey: .checkIns)
        try c.encode(avatarFinish, forKey: .avatarFinish)
        try c.encode(restDays, forKey: .restDays)
        try c.encode(previousCycles, forKey: .previousCycles)
        try c.encode(reminders, forKey: .reminders)
        try c.encode(routine, forKey: .routine)
        try c.encode(urgeLogs, forKey: .urgeLogs)
        // The app keeps watch data in its own file; exported backups still include it.
        if encoder.userInfo[TrackerDocument.omitHealth] as? Bool != true { try c.encode(health, forKey: .health) }
        try c.encode(wellbeing, forKey: .wellbeing)
        try c.encode(meals, forKey: .meals)
        try c.encode(meds, forKey: .meds)
        try c.encode(notes, forKey: .notes)
        try c.encode(photos, forKey: .photos)
    }
    /// Encoder option: leave `health` out (it is saved separately as health.json).
    public static let omitHealth = CodingUserInfoKey(rawValue: "ascend.omitHealth")!
    public init(timeZoneID: String = "Asia/Kolkata", cycle: Cycle, goals: [Goal],
                habits: [Habit], checkIns: [CheckIn] = [], avatarFinish: String = "Progress") {
        self.timeZoneID = timeZoneID; self.cycle = cycle; self.goals = goals
        self.habits = habits; self.checkIns = checkIns; self.avatarFinish = avatarFinish
    }
    public mutating func setEntry(_ entry: CheckIn) {
        checkIns.removeAll { $0.habitID == entry.habitID && $0.day == entry.day }
        checkIns.append(entry)
    }
    public func validate() throws {
        func require(_ test: Bool, _ text: String) throws {
            if !test { throw ValidationError(message: text) }
        }
        try routine.validate()
        try health.validate()
        try wellbeing.validate(engine: TrackerEngine(document: self))
        try meals.validate()
        try meds.validate(engine: TrackerEngine(document: self))
        try notes.validate(engine: TrackerEngine(document: self))
        try photos.validate(engine: TrackerEngine(document: self))
        try require(Set(urgeLogs.map(\.id)).count == urgeLogs.count, "Duplicate urge logs.")
        for urge in urgeLogs {
            try require(urge.timestamp.timeIntervalSince1970.isFinite && (-2208988800...7289654399).contains(urge.timestamp.timeIntervalSince1970) && TrackerEngine(document: self).date(TrackerEngine(document: self).key(urge.timestamp)) != nil, "Invalid urge timestamp.")
            try require(urge.intensity.map { (1...5).contains($0) } ?? true, "Urge intensity must be 1–5.")
            try require(urge.category.map { $0.count <= 60 } ?? true, "Urge labels must be 60 characters or fewer.")
            try require(urge.customTrigger.map { urge.trigger == .other && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 40 && $0.rangeOfCharacter(from: .newlines) == nil } ?? true, "Custom triggers must be a short single line of 40 characters or fewer, with Other selected.")
            try require(urge.note.count <= 500, "Urge notes must be 500 characters or fewer.")
        }
        try require(restDays.allSatisfy { TrackerEngine(document: self).date($0) != nil }, "Invalid rest day.")
        try require((0..<1440).contains(reminders.morningMinute) && (0..<1440).contains(reminders.eveningMinute), "Invalid reminder time.")
        try require(reminders.morningMinute < reminders.eveningMinute, "The evening reminder must follow the morning reminder.")
        for old in previousCycles {
            let e = TrackerEngine(document: self)
            try require(e.date(old.start) != nil && e.date(old.end) != nil && old.start <= old.end && old.target.isFinite && old.target > 0 && old.target <= 1, "Invalid previous cycle.")
        }
        try require(schemaVersion == 3, "This backup uses an unsupported format.")
        try require(TimeZone(identifier: timeZoneID) != nil, "Invalid time zone.")
        let engine = TrackerEngine(document: self)
        let validDay: (String) -> Bool = { engine.date($0) != nil }
        try require(validDay(cycle.start) && validDay(cycle.end) && cycle.start <= cycle.end, "Invalid cycle dates.")
        try require(engine.days(from: cycle.start, through: cycle.end).count <= 3660, "A cycle must be shorter than ten years.")
        try require(cycle.target.isFinite && cycle.target > 0 && cycle.target <= 1, "Invalid consistency target.")
        try require(Set(goals.map(\.id)).count == goals.count && Set(habits.map(\.id)).count == habits.count, "Duplicate goals or habits.")
        for goal in goals {
            try require(!goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !goal.windows.isEmpty, "A goal is missing its name or dates.")
            try require(Set(goal.windows.map(\.effectiveDay)).count == goal.windows.count, "Duplicate goal date revisions.")
            for w in goal.windows { try require(validDay(w.effectiveDay) && validDay(w.start) && validDay(w.end) && w.start <= w.end, "Invalid goal dates.") }
        }
        for habit in habits {
            try require(goals.contains { $0.id == habit.goalID }, "A habit refers to a missing goal.")
            try require(validDay(habit.createdDay) && !habit.revisions.isEmpty, "A habit has no valid schedule.")
            if let end = habit.archivedDay { try require(validDay(end) && end >= habit.createdDay, "Invalid archive date.") }
            try require(Set(habit.revisions.map(\.effectiveDay)).count == habit.revisions.count, "Duplicate habit revisions.")
            for r in habit.revisions {
                try require(r.scheduledMinute.map { (0..<1440).contains($0) } ?? true, "Invalid habit time.")
                try require(validDay(r.effectiveDay) && r.effectiveDay >= habit.createdDay && !r.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Invalid habit revision.")
                if habit.kind == .milestone { try require(r.schedule.once.map(validDay) == true, "A milestone needs a valid due date.") }
                else { try require(r.schedule.once == nil && !r.schedule.weekdays.isEmpty && r.schedule.weekdays.allSatisfy { (1...7).contains($0) }, "Invalid repeat days.") }
                if habit.kind == .metric {
                    try require(r.target != nil, "A numeric habit needs a target.")
                    if let t = r.target {
                        try require(!t.unit.isEmpty && (t.minimum != nil || t.maximum != nil), "A numeric habit needs units and a bound.")
                        try require(t.minimum.map { $0.isFinite && $0 >= 0 } ?? true, "Invalid numeric minimum.")
                        try require(t.maximum.map { $0.isFinite && $0 >= 0 } ?? true, "Invalid numeric maximum.")
                        try require((t.minimum ?? 0) <= (t.maximum ?? .infinity), "The minimum exceeds the maximum.")
                    }
                }
            }
        }
        var keys = Set<String>()
        for entry in checkIns {
            try require(habits.contains { $0.id == entry.habitID } && validDay(entry.day), "A check-in has an invalid habit or date.")
            try require(entry.value.map { $0.isFinite && $0 >= 0 } ?? true, "Invalid logged value.")
            try require(keys.insert("\(entry.habitID):\(entry.day)").inserted, "Duplicate check-ins.")
        }
        try require(["Progress", "Obsidian", "Titanium", "Ascendant"].contains(avatarFinish), "Invalid avatar appearance.")
    }
}
public struct ValidationError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public extension Double {
    var pretty: String { formatted(.number.precision(.fractionLength(0...1))) }
}
