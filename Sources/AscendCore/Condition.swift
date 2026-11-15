import Foundation

/// Read-only figures behind the Condition tab (Health, Body, Screen time). Nothing here logs or sets targets.
public enum Condition {
    /// The steps floor the mission uses (Mission A: "Floor 7,000; mission 10,000").
    public static let stepsFloor = 7_000.0
    /// The steps goal above the floor (the "Walk 10,000 steps" habit and the diet plan).
    public static let stepsGoal = 10_000.0
    /// "Asleep by 1 am", in minutes after midnight.
    public static let asleepBy = 60
    /// The "Evening stress under 28" goal; the line on the stress row.
    public static let stressLine = 28.0
    /// Phone hours a day before the dot turns red. A starting line, not a goal he set.
    public static let phoneHoursLine = 6.0

    /// Resting heart rate from one night's readings: the lowest 30-minute average while asleep.
    /// Needs at least 3 readings in that window; nil when the night is too thin.
    public static func restingFromSleep(_ points: [(time: Double, value: Double)], from start: Double, to end: Double) -> Double? {
        let night = points.filter { $0.time >= start && $0.time <= end && $0.value > 25 && $0.value < 200 }.sorted { $0.time < $1.time }
        var best: Double?
        for (i, p) in night.enumerated() {
            let window = night[i...].prefix { $0.time < p.time + 1800 }
            guard window.count >= 3 else { continue }
            let avg = window.map(\.value).reduce(0, +) / Double(window.count)
            if best.map({ avg < $0 }) ?? true { best = avg }
        }
        return best.map { ($0 * 10).rounded() / 10 }
    }

    /// Resting heart rate worked out from the night that ended on `day` (the main sleep session).
    public static func restingFromSleep(_ health: HealthArchive, on day: String, engine: TrackerEngine) -> Double? {
        guard let night = health.sleepSessions(on: day, engine: engine).first else { return nil }
        let points = health.records.filter { $0.metric == .heartRate && $0.start >= night.start && $0.start <= night.end }.map { (time: $0.start, value: $0.value) }
        return restingFromSleep(points, from: night.start, to: night.end)
    }

    /// The day the Health report opens on: today when it already has readings, otherwise the latest of the
    /// three days before it that does (after midnight that is yesterday, the last full day).
    public static func reportDay(today: String, engine: TrackerEngine, hasData: (String) -> Bool) -> String {
        if hasData(today) { return today }
        for back in 1...3 { let key = engine.adding(-back, to: today); if hasData(key) { return key } }
        return today
    }

    /// Minutes after midnight, with evening times negative (11:30 pm = -30), so bedtimes average across midnight.
    public static func signedMinute(_ t: Double, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t))
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return m >= 720 ? m - 1440 : m
    }

    /// How late a bedtime is against "asleep by 1 am", in minutes (0 when on time).
    public static func lateMinutes(asleepAt minute: Int, plan: Int = asleepBy) -> Int { max(0, minute - plan) }

    /// Phone use between 11 pm on `evening` and 4 am the next morning, in minutes. Nil when the phone
    /// sent no hourly data covering that window.
    public static func afterHoursMinutes(_ device: ScreenTimeDevice, evening: String, engine: TrackerEngine) -> Double? {
        guard let noon = engine.date(evening), case let day = engine.calendar.startOfDay(for: noon), let from = engine.calendar.date(byAdding: .hour, value: 23, to: day),
              let to = engine.calendar.date(byAdding: .hour, value: 5, to: from) else { return nil }
        let a = from.timeIntervalSince1970, b = to.timeIntervalSince1970
        let covering = device.days.filter { $0.end > a && $0.start < b && !$0.hours.isEmpty }
        guard !covering.isEmpty else { return nil }
        let seconds = covering.flatMap(\.hours).filter { $0.start >= a && $0.start < b }.map(\.seconds).reduce(0, +)
        return (seconds / 60).rounded()
    }

    /// The device's day that starts on `key` in the device's own calendar.
    public static func day(_ device: ScreenTimeDevice, key: String, engine: TrackerEngine) -> ScreenTimeDay? {
        device.days.first { engine.key(Date(timeIntervalSince1970: $0.start + 60)) == key }
    }

    /// Kilograms a week still needed to reach `target` by `due`, and the weeks left.
    public static func neededPerWeek(current: Double, target: Double, today: Date, due: Date) -> (perWeek: Double, weeks: Double)? {
        let weeks = due.timeIntervalSince(today) / (7 * 86_400)
        guard weeks > 0 else { return nil }
        return ((current - target) / weeks, weeks)
    }

    /// Lean mass at a body-fat estimate.
    public static func leanMass(kg: Double, bodyFat: Double) -> Double { kg * (1 - bodyFat / 100) }

    /// Daily steps (Mi Fitness total, else counted records).
    public static func steps(_ health: HealthArchive, on day: String, engine: TrackerEngine) -> Double? { health.steps(on: day, engine: engine) }

    /// Average stress for a day, optionally only from 6 pm on.
    public static func stress(_ health: HealthArchive, on day: String, engine: TrackerEngine, eveningOnly: Bool = false) -> Double? {
        let list = health.records(.stress, on: day, engine: engine).filter { !eveningOnly || engine.calendar.component(.hour, from: Date(timeIntervalSince1970: $0.start)) >= 18 }
        return list.isEmpty ? nil : list.map(\.value).reduce(0, +) / Double(list.count)
    }

    /// The latest resting heart rate on or before `day`, and the day it was read.
    public static func lastResting(_ health: HealthArchive, onOrBefore day: String, engine: TrackerEngine) -> (value: Double, day: String)? {
        health.records.last { $0.metric == .restingHeartRate && engine.key(Date(timeIntervalSince1970: $0.start)) <= day }
            .map { ($0.value, engine.key(Date(timeIntervalSince1970: $0.start))) }
    }

    /// One plain sentence for the Health lede, e.g. "Slept 7 h 47, but late. A calm day on few steps."
    public static func healthLede(asleep: Double?, asleepAt: Int?, planMinutes: Double, stress: Double?, steps: Double?) -> String {
        var parts: [String] = []
        if let asleep {
            let late = asleepAt.map { lateMinutes(asleepAt: $0) > 15 } ?? false, short = asleep < planMinutes * 0.9
            parts.append("Slept \(HealthReport.duration(asleep))" + (late && short ? ", late and short." : late ? ", but late." : short ? ", short of plan." : ", on time."))
        }
        let mood = stress.map { $0 < 30 ? "A calm day" : $0 < 50 ? "A steady day" : "A stressful day" }
        let feet = steps.map { $0 < stepsFloor * 0.6 ? "on few steps" : $0 < stepsFloor ? "under the \(Int(stepsFloor).formatted()) floor" : "on your feet" }
        switch (mood, feet) {
        case let (m?, f?): parts.append("\(m) \(f).")
        case let (m?, nil): parts.append("\(m).")
        case let (nil, f?): parts.append("\(Int(steps!).formatted()) steps, \(f).")
        default: break
        }
        return parts.isEmpty ? "No watch data for this day yet." : parts.joined(separator: " ")
    }

    /// The pattern line under the 7-day trends.
    public static func stepsPattern(days: [(label: String, steps: Double?, workout: Bool)]) -> String? {
        let known = days.compactMap { d in d.steps.map { (d.label, $0, d.workout) } }
        guard known.count >= 4 else { return nil }
        var text: [String] = []
        let under = known.filter { $0.1 < stepsFloor }.count
        if under >= 3 { text.append("steps fell under \(Int(stepsFloor).formatted()) on \(under) of \(known.count) days.") }
        let best = known.sorted { $0.1 > $1.1 }.prefix(2)
        if best.count == 2, best.allSatisfy({ $0.2 }) {
            let names = best.sorted { a, b in (known.firstIndex { $0.0 == a.0 } ?? 0) < (known.firstIndex { $0.0 == b.0 } ?? 0) }.map(\.0)
            text.append("Your two best days, \(names[0]) and \(names[1]), both had a workout.")
        }
        guard !text.isEmpty else { return nil }
        return text.joined(separator: " ")
    }

    /// The pattern line under the after-11-pm nights. `nights` pairs phone minutes with the asleep minute (signed).
    public static func nightsPattern(_ nights: [(minutes: Double, asleepAt: Int?)]) -> String? {
        func list(_ m: [Int]) -> String {
            let t = m.map { HealthReport.clock(($0 + 1440) % 1440) }
            return t.count <= 1 ? (t.first ?? "") : t.dropLast().joined(separator: ", ") + " and " + t.last!
        }
        let quiet = nights.filter { $0.minutes < 15 }.compactMap(\.asleepAt), heavy = nights.filter { $0.minutes >= 120 }.compactMap(\.asleepAt)
        guard !quiet.isEmpty, !heavy.isEmpty else { return nil }
        return "on nights under 15 minutes of phone after 11 pm you were asleep by \(list(quiet)). On nights over 2 hours, \(list(heavy))."
    }
}
