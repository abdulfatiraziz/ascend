import Foundation

/// One day of watch data turned into a report: vitals, an hour-by-hour trace, last night against the plan,
/// eight-day trends, a recovery score and plain-language signals. Built in one pass over the archive.
public struct HealthReport: Sendable {
    public struct Span: Equatable, Sendable { public var start: Double; public var end: Double }
    /// A reading averaged over a 10-minute slot of the day.
    public struct Point: Equatable, Sendable { public var time: Double; public var value: Double }
    public struct TrendDay: Equatable, Sendable {
        public var day: String
        public var sleepHours: Double?
        public var steps: Double?
        public var restingHeartRate: Double?
        /// Hours after midnight the main night started (negative before midnight).
        public var bedtime: Double?
    }
    public struct Recovery: Equatable, Sendable {
        public var score: Int
        /// Each part 0–100; nil when that input is missing.
        public var resting: Double?, sleep: Double?, stress: Double?
        public var label: String { score >= 80 ? "Good" : score >= 60 ? "Fair" : "Low" }
    }
    public enum Tone: String, Sendable { case good, warn, info }
    public struct Signal: Equatable, Sendable { public var tone: Tone; public var title: String; public var detail: String }

    public var day: String
    public var dayStart: Double
    public var restingHeartRate: Double?
    /// "Mi Fitness" when the cloud sent its daily figure, else "asleep" (lowest reading during the night).
    public var restingSource: String?
    public var restingBaseline: Double?
    /// Resting heart rate for up to 15 days ending on `day`.
    public var restingSeries: [Double] = []
    public var heart: [Point] = []
    public var heartAverage: Double?, heartLow: Double?, heartHigh: Double?
    public var heartReadings = 0
    public var stress: [Point] = []
    public var stressAverage: Double?, stressHigh: Double?, stressLow: Double?
    /// Share of the day's stress readings under 30 (relaxed), 0–1.
    public var relaxedShare: Double?
    public var oxygen: [Point] = []
    public var oxygenAverage: Double?, oxygenLow: Double?
    public var steps: Double?, stepGoal: Double?, activeEnergy: Double?, distance: Double?
    public var workouts: [Span] = []
    public var night: HealthRecord?
    public var asleepMinutes: Double?
    public var stageMinutes: [SleepStageKind: Double] = [:]
    public var overnightStress: Double?
    /// Planned bedtime and wake as minutes after midnight, and the planned time asleep.
    public var planBed: Int?, planWake: Int?, planMinutes: Double = 480
    public var drift: RoutineDrift?
    public var recovery: Recovery?
    public var trend: [TrendDay] = []
    public var signals: [Signal] = []
    public var headline = ""
    public var summary = ""
    public var hasData: Bool { night != nil || !heart.isEmpty || steps != nil || restingHeartRate != nil }

    /// "1:54 am" for a minute of the day.
    public static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440, h = m / 60
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m % 60)) \(h < 12 ? "am" : "pm")"
    }
    /// "6 h 40 m", "45 m".
    public static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? (m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m") : "\(m) m"
    }
}

public extension HealthArchive {
    func report(on day: String, document: TrackerDocument) -> HealthReport {
        let engine = TrackerEngine(document: document)
        let calendar = engine.calendar
        // engine.date gives midday; the report runs midnight to midnight.
        func midnight(_ key: String) -> Double? { engine.date(key).map { calendar.startOfDay(for: $0).timeIntervalSince1970 } }
        var r = HealthReport(day: day, dayStart: midnight(day) ?? 0)
        guard let start = midnight(day) else { return r }
        let end = midnight(engine.adding(1, to: day)) ?? start + 86_400
        func minuteOfDay(_ t: Double) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: t)); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        // One pass: the day's readings, and resting heart rate for the 14 days before it.
        let windowStart = midnight(engine.adding(-14, to: day)) ?? start - 14 * 86_400
        var dayHeart: [HealthRecord] = [], dayStress: [HealthRecord] = [], dayOxygen: [HealthRecord] = [], cloudResting: [String: Double] = [:]
        for record in records where record.end >= windowStart && record.start < end {
            switch record.metric {
            case .heartRate where record.start >= start: dayHeart.append(record)
            case .stress where record.start >= start: dayStress.append(record)
            case .oxygen where record.start >= start: dayOxygen.append(record)
            case .restingHeartRate: cloudResting[engine.key(Date(timeIntervalSince1970: record.start))] = record.value
            case .workout where record.start >= start: r.workouts.append(.init(start: record.start, end: min(record.end, end)))
            default: break
            }
        }
        func slots(_ list: [HealthRecord]) -> [HealthReport.Point] {
            var sums: [Int: (Double, Int)] = [:]
            for x in list { let slot = Int((x.start - start) / 600); let s = sums[slot] ?? (0, 0); sums[slot] = (s.0 + x.value * Double(x.weight), s.1 + x.weight) }
            return sums.keys.sorted().map { .init(time: start + Double($0) * 600 + 300, value: sums[$0]!.0 / Double(sums[$0]!.1)) }
        }
        r.heart = slots(dayHeart); r.stress = slots(dayStress); r.oxygen = slots(dayOxygen)
        r.heartAverage = HealthArchive.mean(dayHeart); r.heartLow = dayHeart.map(\.lowest).min(); r.heartHigh = dayHeart.map(\.highest).max()
        r.heartReadings = dayHeart.map(\.weight).reduce(0, +)
        let stressValues = dayStress.map(\.value)
        if !stressValues.isEmpty {
            r.stressAverage = stressValues.reduce(0, +) / Double(stressValues.count); r.stressHigh = stressValues.max(); r.stressLow = stressValues.min()
            r.relaxedShare = Double(stressValues.filter { $0 < 30 }.count) / Double(stressValues.count)
        }
        r.oxygenAverage = HealthArchive.mean(dayOxygen); r.oxygenLow = dayOxygen.map(\.lowest).min()
        r.steps = steps(on: day, engine: engine)
        r.stepGoal = document.healthHabits.steps?.latest.target?.minimum
        let energy = records(.activeEnergy, on: day, engine: engine); r.activeEnergy = energy.isEmpty ? nil : energy.map(\.value).reduce(0, +)
        let distance = records(.distance, on: day, engine: engine)
        r.distance = distance.isEmpty ? estimatedDistance(on: day, engine: engine) : distance.map(\.value).reduce(0, +)

        // Last night against the routine.
        let routine = document.routine
        if routine.configured {
            r.planBed = routine.bedMinute; r.planWake = routine.wakeMinute
            r.planMinutes = Double(((routine.wakeMinute - routine.bedMinute) % 1440 + 1440) % 1440)
        } else if let target = document.healthHabits.sleep?.latest.target?.minimum { r.planMinutes = target * 60 }
        if let night = sleepSessions(on: day, engine: engine).first {
            r.night = night
            r.stageMinutes = night.stageMinutes
            let asleep = r.stageMinutes.filter { $0.key.isAsleep }.values.reduce(0, +)
            r.asleepMinutes = asleep > 0 ? asleep : night.value * 60
            r.drift = engine.drift(night)
            let overnight = records.filter { $0.metric == .stress && $0.start >= night.start && $0.start <= night.end }.map(\.value)
            r.overnightStress = overnight.isEmpty ? nil : overnight.reduce(0, +) / Double(overnight.count)
        }

        // Resting heart rate: Mi Fitness's daily figure, else the lowest reading while asleep.
        func resting(_ key: String) -> (Double, String)? {
            if let cloud = cloudResting[key] { return (cloud, "Mi Fitness") }
            return sleepSessions(on: key, engine: engine).first.flatMap { nightVitals($0).restingHeartRate }.map { ($0, "asleep") }
        }
        if let (value, source) = resting(day) { r.restingHeartRate = value; r.restingSource = source }
        let history = (1...14).reversed().compactMap { resting(engine.adding(-$0, to: day))?.0 }
        r.restingSeries = history + (r.restingHeartRate.map { [$0] } ?? [])
        if history.count >= 3 { r.restingBaseline = history.reduce(0, +) / Double(history.count) }

        // Eight days ending on `day`.
        r.trend = (0..<8).reversed().map { back in
            let key = engine.adding(-back, to: day)
            let night = sleepSessions(on: key, engine: engine).first
            let bed = night.map { n -> Double in let m = Double(minuteOfDay(n.start)); return m > 720 ? (m - 1440) / 60 : m / 60 }
            return .init(day: key, sleepHours: sleepHours(on: key, engine: engine), steps: steps(on: key, engine: engine),
                         restingHeartRate: back == 0 ? r.restingHeartRate : resting(key)?.0, bedtime: bed)
        }

        // Recovery: resting heart rate against baseline (40%), time asleep against plan (40%), overnight stress (20%).
        let restingPart = r.restingHeartRate.flatMap { rhr in r.restingBaseline.map { min(100, max(0, 100 - max(0, rhr - $0) * 12)) } }
        let sleepPart = r.asleepMinutes.map { min(100, $0 / max(60, r.planMinutes) * 100) }
        let stressPart = r.overnightStress.map { min(100, max(0, (70 - $0) / 50 * 100)) }
        let parts = [(restingPart, 0.4), (sleepPart, 0.4), (stressPart, 0.2)].compactMap { p in p.0.map { ($0, p.1) } }
        if parts.count >= 2 {
            let weight = parts.map(\.1).reduce(0, +)
            r.recovery = .init(score: Int((parts.map { $0.0 * $0.1 }.reduce(0, +) / weight).rounded()), resting: restingPart, sleep: sleepPart, stress: stressPart)
        }

        r.signals = signals(r)
        (r.headline, r.summary) = headline(r)
        return r
    }

    private func headline(_ r: HealthReport) -> (String, String) {
        guard r.hasData else { return ("No watch data for this day yet.", "Sync your watch in Mi Fitness, then open Cipher Bridge or wait for the hourly cloud sync.") }
        let short = r.asleepMinutes.map { $0 < r.planMinutes * 0.9 } ?? false
        let title: String
        switch r.recovery?.label {
        case "Good": title = short ? "Recovered, but short on sleep." : "Well recovered."
        case "Fair": title = short ? "Partly recovered after a short night." : "Partly recovered."
        case "Low": title = "Running on low recovery."
        default: title = short ? "A short night." : "Today so far."
        }
        var parts: [String] = []
        if let rhr = r.restingHeartRate, let base = r.restingBaseline {
            let delta = rhr - base
            parts.append(abs(delta) < 2 ? "Resting heart rate is at your baseline" : delta > 0 ? "Resting heart rate is \(Int(delta.rounded())) above your baseline" : "Resting heart rate is \(Int((-delta).rounded())) below your baseline")
        }
        if let s = r.overnightStress { parts.append(s < 30 ? "stress stayed low overnight" : "stress ran high overnight") }
        var text = parts.isEmpty ? "" : parts.joined(separator: " and ") + ". "
        if let asleep = r.asleepMinutes {
            text += "You slept \(HealthReport.duration(asleep)) against your \(HealthReport.duration(r.planMinutes)) plan"
            if let late = r.drift?.bedtime, late > 15 { text += " and got to bed \(HealthReport.duration(Double(late))) later than planned" }
            text += "."
        }
        return (title, text.prefix(1).uppercased() + text.dropFirst())
    }

    private func signals(_ r: HealthReport) -> [HealthReport.Signal] {
        var out: [HealthReport.Signal] = []
        if let rhr = r.restingHeartRate, let base = r.restingBaseline {
            if rhr - base >= 5 {
                out.append(.init(tone: .warn, title: "Resting heart rate is up", detail: "\(Int(rhr)) bpm against a 14-day baseline of \(Int(base.rounded())). That often follows short sleep, alcohol, a hard session or getting ill; go easier today."))
            } else {
                let asleep = r.heart.filter { p in r.night.map { p.time >= $0.start && p.time <= $0.end } ?? false }
                let low = asleep.min { $0.value < $1.value }
                out.append(.init(tone: .good, title: "Recovery is solid", detail: (low.map { "Heart rate settled to \(Int($0.value.rounded())) by \(HealthReport.clock(Int(($0.time - r.dayStart) / 60))) and resting" } ?? "Resting") + " heart rate is \(Int(rhr)), against your 14-day baseline of \(Int(base.rounded()))."))
            }
        }
        if let plan = r.planBed {
            let nights = r.trend.compactMap(\.bedtime)
            let late = nights.filter { ($0 * 60) - Double(plan > 720 ? plan - 1440 : plan) > 15 }.count
            if nights.count >= 4 && late * 2 > nights.count {
                let windDown = HealthReport.clock(plan - 120)
                out.append(.init(tone: .warn, title: "Bedtime keeps slipping", detail: "You got to bed more than 15 min after your \(HealthReport.clock(plan)) plan on \(late) of the last \(nights.count) nights. Starting wind-down at \(windDown) would put you on plan."))
            }
        }
        if let asleep = r.asleepMinutes {
            let deep = r.stageMinutes[.deep] ?? 0, rem = r.stageMinutes[.rem] ?? 0
            if asleep < r.planMinutes * 0.9 {
                out.append(.init(tone: .info, title: deep / max(asleep, 1) >= 0.2 ? "Deep sleep is strong, total sleep is short" : "Short night",
                                 detail: "\(HealthReport.duration(asleep)) asleep against \(HealthReport.duration(r.planMinutes)) planned" + (deep > 0 ? ": deep \(HealthReport.duration(deep)), REM \(HealthReport.duration(rem))." : ".") + " REM mostly comes late in the night, so it's the first thing a short night cuts."))
            } else {
                out.append(.init(tone: .good, title: "Full night", detail: "\(HealthReport.duration(asleep)) asleep" + (deep > 0 ? " with \(HealthReport.duration(deep)) deep and \(HealthReport.duration(rem)) REM." : ".")))
            }
        }
        if let goal = r.stepGoal {
            let days = r.trend.compactMap(\.steps)
            let hit = days.filter { $0 >= goal }.count, low = days.filter { $0 < 3000 }.count
            if hit >= 2 && low >= 2 {
                out.append(.init(tone: .info, title: "Movement is all-or-nothing", detail: "\(hit) days over \(Int(goal).formatted()) steps, \(low) days under 3,000 in the last \(days.count). A 30 min walk on quiet days would even it out."))
            } else if !days.isEmpty && hit * 2 < days.count {
                out.append(.init(tone: .info, title: "Steps are under goal", detail: "\(Int(goal).formatted()) steps on \(hit) of the last \(days.count) days."))
            }
        }
        if let s = r.stressAverage, s >= 50 {
            out.append(.init(tone: .warn, title: "High stress day", detail: "Average stress \(Int(s)) out of 100. A short walk or slow breathing for 5 min brings it down."))
        }
        return Array(out.prefix(4))
    }
}
