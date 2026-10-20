import Foundation

public struct SleepWindow: Codable, Equatable, Sendable {
    public var bedtime: Date
    public var wakeTime: Date
    public var asleepHours: Double?
    public init(bedtime: Date, wakeTime: Date, asleepHours: Double? = nil) {
        self.bedtime = bedtime; self.wakeTime = wakeTime; self.asleepHours = asleepHours
    }
    public var hours: Double { wakeTime.timeIntervalSince(bedtime) / 3600 }
    public func validate(day: String, engine: TrackerEngine) throws {
        guard bedtime.timeIntervalSince1970.isFinite, wakeTime.timeIntervalSince1970.isFinite,
              (946684800...7289654399).contains(bedtime.timeIntervalSince1970),
              (946684800...7289654399).contains(wakeTime.timeIntervalSince1970),
              hours > 0, hours <= 36, engine.key(wakeTime) == day,
              asleepHours.map({ $0.isFinite && $0 >= 0 && $0 <= hours }) ?? true else {
            throw ValidationError(message: "Sleep must end on the selected date, after bedtime, within 36 hours. Asleep hours cannot exceed the window.")
        }
    }
}
public struct DailyObservation: Codable, Equatable, Identifiable, Sendable {
    public var day: String
    public var energy: Int?
    public var mood: Int?
    public var stress: Int?
    public var sleep: SleepWindow?
    public var caffeineComplete: Bool
    public var urgesComplete: Bool
    public var note: String
    public var id: String { day }
    public init(day: String, energy: Int? = nil, mood: Int? = nil, stress: Int? = nil, sleep: SleepWindow? = nil,
                caffeineComplete: Bool = false, urgesComplete: Bool = false, note: String = "") {
        self.day = day; self.energy = energy; self.mood = mood; self.stress = stress; self.sleep = sleep
        self.caffeineComplete = caffeineComplete; self.urgesComplete = urgesComplete; self.note = note
    }
    public var isEmpty: Bool { energy == nil && mood == nil && stress == nil && sleep == nil && !caffeineComplete && !urgesComplete && note.isEmpty }
}
public struct CaffeineEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var name: String
    public var milligrams: Double?
    public init(id: UUID = UUID(), timestamp: Date = Date(), name: String = "Caffeine", milligrams: Double? = nil) {
        self.id = id; self.timestamp = timestamp; self.name = name; self.milligrams = milligrams
    }
}
public struct WellbeingJournal: Codable, Equatable, Sendable {
    public var daily: [DailyObservation] = []
    public var caffeine: [CaffeineEntry] = []
    public init() {}
    public func observation(on day: String) -> DailyObservation? { daily.first { $0.day == day } }
    public mutating func set(_ observation: DailyObservation) {
        daily.removeAll { $0.day == observation.day }
        if !observation.isEmpty { daily.append(observation) }
    }
    public mutating func set(_ entry: CaffeineEntry) {
        caffeine.removeAll { $0.id == entry.id }; caffeine.append(entry)
    }
    public func validate(engine: TrackerEngine) throws {
        guard daily.count <= 50_000, caffeine.count <= 200_000, Set(daily.map(\.day)).count == daily.count,
              Set(caffeine.map(\.id)).count == caffeine.count else { throw ValidationError(message: "Duplicate or oversized wellbeing journal.") }
        for d in daily {
            guard engine.date(d.day) != nil, d.note.count <= 500,
                  [d.energy, d.mood, d.stress].allSatisfy({ $0.map { (1...5).contains($0) } ?? true }) else {
                throw ValidationError(message: "Daily ratings must be 1–5, with a valid date and at most 500 note characters.")
            }
            try d.sleep?.validate(day: d.day, engine: engine)
        }
        for c in caffeine {
            guard c.timestamp.timeIntervalSince1970.isFinite, (946684800...7289654399).contains(c.timestamp.timeIntervalSince1970),
                  !c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, c.name.count <= 60,
                  c.milligrams.map({ $0.isFinite && (0...2000).contains($0) }) ?? true else {
                throw ValidationError(message: "Caffeine needs a valid time and name (up to 60 characters). Optional amounts must be 0–2,000 mg.")
            }
        }
    }
}
public struct NightSummary: Equatable, Sendable {
    public var window: SleepWindow
    public var source: String
    public var manuallyCorrected: Bool
}
public struct PatternDay: Identifiable, Sendable {
    public var day: String
    public var night: NightSummary?
    public var energy: Int?
    public var mood: Int?
    public var stress: Int?
    public var caffeine: [CaffeineEntry]
    public var caffeineComplete: Bool
    public var urgeCount: Int
    public var urgesComplete: Bool
    public var habitRatio: Double?
    public var id: String { day }
    /// A known zero requires an explicitly completed log. An unknown dose never becomes zero.
    public var caffeineMg: Double? {
        guard caffeineComplete, caffeine.allSatisfy({ $0.milligrams != nil }) else { return nil }
        return caffeine.compactMap(\.milligrams).reduce(0, +)
    }
}
public struct PatternGroup: Sendable {
    public var label: String
    public var values: [Double]
    public var count: Int { values.count }
    public var average: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
}
public struct PatternComparison: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var metric: String
    public var unit: String
    public var explanation: String
    public var first: PatternGroup
    public var second: PatternGroup
    public var pairedDays: Int { first.count + second.count }
    public var ready: Bool { pairedDays >= 14 && first.count >= 5 && second.count >= 5 }
}
public struct PatternTimelineEvent: Identifiable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date?
    public var title: String
    public var detail: String
    public var symbol: String
    public var caffeineID: UUID?
    public var urgeID: UUID?
}
public struct PatternsEngine {
    public let document: TrackerDocument
    public let today: String
    public let tracker: TrackerEngine
    private let observations: [String: DailyObservation]
    private let caffeineDays: [String: [CaffeineEntry]]
    private let urgeDays: [String: [UrgeLog]]
    private let sleepDays: [String: [HealthRecord]]
    private let workoutDays: [String: [HealthRecord]]
    public init(document: TrackerDocument, today: String) {
        self.document = document; self.today = today
        let e = TrackerEngine(document: document); tracker = e
        observations = Dictionary(document.wellbeing.daily.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        caffeineDays = Dictionary(grouping: document.wellbeing.caffeine) { e.key($0.timestamp) }
        urgeDays = Dictionary(grouping: document.urgeLogs) { e.key($0.timestamp) }
        sleepDays = Dictionary(grouping: document.health.records.filter { $0.metric == .sleep }) { e.key(Date(timeIntervalSince1970: $0.end)) }
        workoutDays = Dictionary(grouping: document.health.records.filter { $0.metric == .workout }) { e.key(Date(timeIntervalSince1970: $0.start)) }
    }
    public func night(on day: String) -> NightSummary? {
        if let manual = observations[day]?.sleep {
            return NightSummary(window: manual, source: "Your sleep window", manuallyCorrected: true)
        }
        let records = (sleepDays[day] ?? []).filter { $0.end > $0.start && $0.end - $0.start <= 36 * 3600 }
        // One main session per wake date; naps are not added to the overnight window.
        guard let main = records.sorted(by: {
            let a = $0.end - $0.start, b = $1.end - $1.start
            return a == b ? $0.id < $1.id : a > b
        }).first else { return nil }
        let hours = main.detail == "Asleep stages" && main.value <= (main.end - main.start) / 3600 ? main.value : nil
        return NightSummary(window: SleepWindow(bedtime: Date(timeIntervalSince1970: main.start), wakeTime: Date(timeIntervalSince1970: main.end), asleepHours: hours), source: "Mi Fitness · main session", manuallyCorrected: false)
    }
    public func day(_ key: String) -> PatternDay {
        let observation = observations[key]
        let caffeine = (caffeineDays[key] ?? []).sorted { $0.timestamp < $1.timestamp }
        let score = tracker.score(on: key)
        let ratio = key >= document.cycle.start && key <= document.cycle.end ? score.ratio : nil
        return PatternDay(day: key, night: night(on: key), energy: observation?.energy, mood: observation?.mood, stress: observation?.stress,
                          caffeine: caffeine, caffeineComplete: observation?.caffeineComplete ?? false,
                          urgeCount: (urgeDays[key] ?? []).count,
                          urgesComplete: observation?.urgesComplete ?? false, habitRatio: ratio)
    }
    public func closedDays(_ count: Int) -> [PatternDay] {
        guard (1...366).contains(count), tracker.date(today) != nil else { return [] }
        return (1...count).reversed().map { day(tracker.adding(-$0, to: today)) }
    }
    /// Circular mean handles bedtimes near midnight. Deviations are local clock minutes.
    public func clockRegularity(_ dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }
        let minutes = dates.map { Double(tracker.calendar.component(.hour, from: $0) * 60 + tracker.calendar.component(.minute, from: $0)) }
        let x = minutes.map { cos($0 * 2 * .pi / 1440) }.reduce(0, +)
        let y = minutes.map { sin($0 * 2 * .pi / 1440) }.reduce(0, +)
        guard hypot(x, y) > 0.00001 else { return nil }
        let mean = atan2(y, x) * 1440 / (2 * .pi)
        return minutes.map { m in let d = abs(m - mean).truncatingRemainder(dividingBy: 1440); return min(d, 1440 - d) }.reduce(0, +) / Double(minutes.count)
    }
    public func comparisons(days count: Int) -> [PatternComparison] {
        let days = closedDays(count)
        func sleepGroups(_ value: (PatternDay) -> Double?) -> (PatternGroup, PatternGroup) {
            var longer: [Double] = [], shorter: [Double] = []
            for d in days {
                guard let n = d.night, let v = value(d) else { continue }
                if n.window.hours >= 7 { longer.append(v) } else { shorter.append(v) }
            }
            return (PatternGroup(label: "7h+ window", values: longer), PatternGroup(label: "Under 7h", values: shorter))
        }
        let energy = sleepGroups { $0.energy.map(Double.init) }
        let urges = sleepGroups { $0.urgesComplete ? Double($0.urgeCount) : nil }
        let habits = sleepGroups { $0.habitRatio.map { $0 * 100 } }
        var late: [Double] = [], none: [Double] = []
        for d in days {
            guard let night = d.night else { continue }
            let start = night.window.bedtime.addingTimeInterval(-6 * 3600), end = night.window.bedtime
            let covered = tracker.days(from: tracker.key(start), through: tracker.key(end))
            guard covered.allSatisfy({ observations[$0]?.caffeineComplete == true }) else { continue }
            let entries = covered.flatMap { caffeineDays[$0] ?? [] }.filter { $0.timestamp >= start && $0.timestamp <= end && $0.milligrams != 0 }
            if entries.isEmpty { none.append(night.window.hours) } else { late.append(night.window.hours) }
        }
        return [
            PatternComparison(id: "sleep-energy", title: "Sleep window & energy", metric: "Next-day energy", unit: "/5", explanation: "Overall energy on the wake date, grouped by the main sleep window.", first: energy.0, second: energy.1),
            PatternComparison(id: "sleep-urges", title: "Sleep window & urges", metric: "Urges per day", unit: "", explanation: "Uses only wake dates explicitly marked as finished urge logs, including confirmed zero days.", first: urges.0, second: urges.1),
            PatternComparison(id: "caffeine-sleep", title: "Caffeine timing & sleep", metric: "Sleep window", unit: "h", explanation: "Groups nights by logged caffeine in the six hours before bedtime. Every local date touched by that interval needs a complete caffeine log. Unknown amounts count for timing; 0 mg entries do not.", first: PatternGroup(label: "Within 6h of bed", values: late), second: PatternGroup(label: "None in window", values: none)),
            PatternComparison(id: "sleep-habits", title: "Sleep window & consistency", metric: "Habit completion", unit: "%", explanation: "Closed dates in the current cycle. Rest days and dates without scheduled habits are excluded.", first: habits.0, second: habits.1)
        ]
    }
    public func timeline(on key: String) -> [PatternTimelineEvent] {
        var events: [PatternTimelineEvent] = []
        if let night = night(on: key) {
            events.append(PatternTimelineEvent(id: "sleep-\(key)", start: night.window.bedtime, end: night.window.wakeTime, title: "Sleep window", detail: night.source, symbol: "moon"))
        }
        for c in day(key).caffeine {
            events.append(PatternTimelineEvent(id: "caffeine-\(c.id)", start: c.timestamp, title: c.name, detail: c.milligrams.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mg caffeine" } ?? "Caffeine · amount unknown", symbol: "cup.and.saucer", caffeineID: c.id))
        }
        for u in urgeDays[key] ?? [] {
            events.append(PatternTimelineEvent(id: "urge-\(u.id)", start: u.timestamp, title: u.category ?? "Urge logged", detail: [u.triggerLabel, u.intensity.map { "\($0)/5 intensity" }].compactMap { $0 }.joined(separator: " · "), symbol: "circle.dotted", urgeID: u.id))
        }
        for w in workoutDays[key] ?? [] {
            events.append(PatternTimelineEvent(id: "workout-\(w.id)", start: Date(timeIntervalSince1970: w.start), end: Date(timeIntervalSince1970: w.end), title: "Workout", detail: "Mi Fitness · \(Int(w.value.rounded())) min", symbol: "figure.strengthtraining.traditional"))
        }
        return events.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}
