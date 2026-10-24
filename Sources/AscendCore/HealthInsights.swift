import Foundation

/// Heart rate and blood oxygen recorded inside one sleep session. Worked out from imported samples, not sent by Mi Fitness.
public struct NightVitals: Equatable, Sendable {
    /// Lowest heart-rate sample while asleep, used as resting heart rate.
    public var restingHeartRate: Double?
    public var averageHeartRate: Double?
    public var averageOxygen: Double?
    public var lowestOxygen: Double?
    public var heartSamples = 0
    public var oxygenSamples = 0
}
/// How far a night drifted from the planned routine, in minutes. Positive means later than planned.
public struct RoutineDrift: Equatable, Sendable {
    public var bedtime: Int
    public var wake: Int
    public init(bedtime: Int, wake: Int) { self.bedtime = bedtime; self.wake = wake }
    /// Signed difference from `planned` to `actual` on a 24-hour clock, kept within ±12 hours.
    public static func offset(_ actual: Int, from planned: Int) -> Int {
        let raw = ((actual - planned) % 1440 + 1440) % 1440
        return raw > 720 ? raw - 1440 : raw
    }
}
public extension HealthArchive {
    /// Average adult walking stride, used only to estimate distance from steps.
    static let strideMeters = 0.75

    func nightVitals(_ night: HealthRecord) -> NightVitals {
        // A 5-minute summary can start just before sleep began, so summaries count when they overlap the night.
        let inside = { (r: HealthRecord) in r.samples == nil ? r.start >= night.start && r.start <= night.end : r.end >= night.start && r.start <= night.end }
        // Older nights are stored as 5-minute summaries; lowest, weighted average and counts match the raw readings.
        let heart = records.filter { $0.metric == .heartRate && inside($0) }
        let oxygen = records.filter { $0.metric == .oxygen && inside($0) }
        return NightVitals(restingHeartRate: heart.map(\.lowest).min(), averageHeartRate: HealthArchive.mean(heart), averageOxygen: HealthArchive.mean(oxygen),
                           lowestOxygen: oxygen.map(\.lowest).min(), heartSamples: heart.map(\.weight).reduce(0, +), oxygenSamples: oxygen.map(\.weight).reduce(0, +))
    }
    /// Average of readings, weighting each summary by how many readings it stands for.
    static func mean(_ records: [HealthRecord]) -> Double? {
        let count = records.map(\.weight).reduce(0, +)
        return count == 0 ? nil : records.map { $0.value * Double($0.weight) }.reduce(0, +) / Double(count)
    }
    public static func average(_ records: [HealthRecord]) -> Double? { mean(records) }
    /// The newest record of a type, so the app can show how fresh a reading is.
    func latest(_ metric: HealthMetric) -> HealthRecord? {
        records.filter { $0.metric == metric }.max { $0.end < $1.end }
    }
    /// Distance from the day's step total at an average stride. Nil when that day has no steps.
    func estimatedDistance(on day: String, engine: TrackerEngine) -> Double? {
        let steps = records(.steps, on: day, engine: engine)
        return steps.isEmpty ? nil : steps.map(\.value).reduce(0, +) * Self.strideMeters
    }
    var hasWorkouts: Bool { records.contains { $0.metric == .workout } }
    /// Hours slept on the main night ending on `day`: staged sleep time when Mi Fitness sent stages, else the session window.
    func sleepHours(on day: String, engine: TrackerEngine) -> Double? {
        sleepSessions(on: day, engine: engine).first.map { ($0.value * 10).rounded() / 10 }
    }
    func steps(on day: String, engine: TrackerEngine) -> Double? {
        let steps = records(.steps, on: day, engine: engine)
        return steps.isEmpty ? nil : steps.map(\.value).reduce(0, +)
    }
}
public extension TrackerEngine {
    /// Bedtime and wake of a sleep session against the routine. Nil until a routine is configured.
    func drift(_ night: HealthRecord) -> RoutineDrift? {
        let routine = document.routine
        guard routine.configured else { return nil }
        return RoutineDrift(bedtime: RoutineDrift.offset(minute(Date(timeIntervalSince1970: night.start)), from: routine.bedMinute),
                            wake: RoutineDrift.offset(minute(Date(timeIntervalSince1970: night.end)), from: routine.wakeMinute))
    }
}
extension TrackerDocument {
    /// The active Number habits that watch data fills: a sleep habit measured in hours and a habit measured in steps.
    public var healthHabits: (sleep: Habit?, steps: Habit?) {
        let metrics = habits.filter { $0.archivedDay == nil && $0.kind == .metric }
        return (metrics.first { $0.latest.target?.unit.lowercased() == "hours" && $0.latest.title.localizedCaseInsensitiveContains("sleep") },
                metrics.first { $0.latest.target?.unit.lowercased() == "steps" })
    }
    /// Fills the Sleep and Steps check-ins from imported watch data for every cycle day up to today.
    /// Ascend remembers each value it wrote; a check-in that is missing from that list or was changed by hand is never touched.
    public mutating func applyHealthReadings(today: String) {
        let engine = TrackerEngine(document: self)
        let targets = healthHabits
        var filled = health.filled ?? [:]
        let first = max(cycle.start, health.records.map { engine.key(Date(timeIntervalSince1970: $0.start)) }.min() ?? today)
        for day in engine.days(from: first, through: min(today, cycle.end)) where !restDays.contains(day) {
            for (habit, value) in [(targets.sleep, health.sleepHours(on: day, engine: engine)), (targets.steps, health.steps(on: day, engine: engine))] {
                guard let habit, engine.isDue(habit, on: day) else { continue }
                let key = "\(habit.id.uuidString)|\(day)"
                let current = engine.entry(for: habit, day: day)
                if let current, current.value != filled[key] { filled[key] = nil; continue }
                if let value { setEntry(CheckIn(habitID: habit.id, day: day, value: value)); filled[key] = value }
                else if current != nil { checkIns.removeAll { $0.habitID == habit.id && $0.day == day }; filled[key] = nil }
            }
        }
        health.filled = filled.isEmpty ? nil : filled
    }
}

/// Today at a glance for the phone's Today screen, sent with every reply.
public struct PhoneToday: Codable, Equatable, Sendable {
    public var day: String
    public var cycle: String
    public var dayNumber: Int
    public var dayCount: Int
    public var habitsDone: Int
    public var habitsDue: Int
    public var steps: Double?
    public var stepGoal: Double?
    public var sleepHours: Double?
    public var sleepMin: Double?
    public var sleepMax: Double?
    public var protein: Double
    public var proteinGoal: Double?
    public var kcal: Double
    public var kcalLimit: Double?
    public var mealsToReview: Int
    public var restingHeartRate: Double?
    public var oxygen: Double?
    public var medsWeekTaken: Int
    public var medsWeekMissed: Int
    /// The avatar's form ("Obsidian", "Titanium", "Ascendant") and how far the cycle has earned it, 0–1.
    public var avatar: String
    public var evolution: Double
    /// Today's share of due habits done, the cycle target, and how many more reach it.
    public var progress: Double
    public var target: Double
    public var toTarget: Int
    public var rest: Bool
    public var habits: [PhoneHabit]
    public var goals: [PhoneGoal]
}
extension TrackerDocument {
    public func phoneToday(today: String) -> PhoneToday {
        let engine = TrackerEngine(document: self)
        let score = engine.score(on: today)
        let watch = healthHabits, food = mealHabits, totals = meals.totals(today)
        let vitals = health.sleepSessions(on: today, engine: engine).first.map(health.nightVitals)
        let meds = self.meds.adherence(today: today, days: 7, engine: engine)
        return PhoneToday(day: today, cycle: cycle.title, dayNumber: engine.dayNumber(today), dayCount: engine.days(from: cycle.start, through: cycle.end).count,
                          habitsDone: score.completed, habitsDue: score.scheduled,
                          steps: health.steps(on: today, engine: engine), stepGoal: watch.steps?.latest.target?.minimum,
                          sleepHours: health.sleepHours(on: today, engine: engine), sleepMin: watch.sleep?.latest.target?.minimum, sleepMax: watch.sleep?.latest.target?.maximum,
                          protein: totals.protein.rounded(), proteinGoal: food.protein?.latest.target?.minimum,
                          kcal: totals.kcal.rounded(), kcalLimit: food.calories?.latest.target?.maximum.map { $0.rounded() }, mealsToReview: totals.pending,
                          restingHeartRate: vitals?.restingHeartRate, oxygen: vitals?.averageOxygen.map { ($0 * 10).rounded() / 10 },
                          medsWeekTaken: meds.taken, medsWeekMissed: meds.missed,
                          avatar: AvatarStage.resolve(evolution: engine.evolution(today: today), appearance: avatarFinish).rawValue,
                          evolution: engine.evolution(today: today), progress: score.ratio ?? 0, target: cycle.target,
                          toTarget: score.remaining(target: cycle.target), rest: restDays.contains(today),
                          habits: phoneHabits(today: today), goals: phoneGoals(today: today))
    }
}
