import Foundation

/// Read-only summaries for the Health tab's "Last night" and "Fuel" cards. Nothing here logs or sets targets.
extension Condition {
    /// One sleep stage block, simplified to four lanes.
    public enum Lane: String, CaseIterable, Sendable { case awake, rem, light, deep }

    public struct Night: Equatable, Sendable {
        public var start: Double, end: Double
        public var blocks: [(lane: Lane, start: Double, end: Double)]
        public var minutes: [Lane: Double]
        public var wakeTimes: [Double]
        public var heartLow: Double?, heartAverage: Double?
        public var oxygenLow: Double?, oxygenAverage: Double?
        public var hasStages: Bool { !blocks.isEmpty }
        public var asleepMinutes: Double { (minutes[.rem] ?? 0) + (minutes[.light] ?? 0) + (minutes[.deep] ?? 0) }
        /// Share of asleep time, 0–100.
        public func percent(_ lane: Lane) -> Double { asleepMinutes > 0 ? (minutes[lane] ?? 0) / asleepMinutes * 100 : 0 }
        public static func == (a: Night, b: Night) -> Bool {
            a.start == b.start && a.end == b.end && a.minutes == b.minutes && a.wakeTimes == b.wakeTimes && a.blocks.count == b.blocks.count
        }
    }

    static func lane(_ kind: SleepStageKind) -> Lane? {
        switch kind {
        case .awake, .awakeInBed, .outOfBed: return .awake
        case .rem: return .rem
        case .deep: return .deep
        case .light, .asleep: return .light
        case .unknown: return nil
        }
    }

    /// The main night that ended on `day`, with stages, wake-ups and overnight heart rate and oxygen.
    public static func night(_ health: HealthArchive, on day: String, engine: TrackerEngine) -> Night? {
        guard let s = health.sleepSessions(on: day, engine: engine).first else { return nil }
        let blocks = (s.stages ?? []).sorted { $0.start < $1.start }.compactMap { st in lane(st.kind).map { (lane: $0, start: st.start, end: st.end) } }
        var minutes: [Lane: Double] = [:]
        for b in blocks { minutes[b.lane, default: 0] += (b.end - b.start) / 60 }
        func within(_ m: HealthMetric) -> [Double] {
            health.records.filter { $0.metric == m && $0.start >= s.start && $0.start <= s.end && $0.value > 0 }.map(\.value)
        }
        let heart = within(.heartRate), oxygen = within(.oxygen)
        func avg(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        return Night(start: s.start, end: s.end, blocks: blocks, minutes: minutes,
                     wakeTimes: blocks.filter { $0.lane == .awake }.map(\.start),
                     heartLow: heart.min(), heartAverage: avg(heart), oxygenLow: oxygen.min(), oxygenAverage: avg(oxygen))
    }

    /// A plain note on a stage's share of sleep, e.g. "Good · aim 15–25%".
    public static func stageNote(_ lane: Lane, percent p: Double) -> String {
        switch lane {
        case .deep: return p < 15 ? "Low side · aim 15–25%" : p <= 25 ? "Good · aim 15–25%" : "Plenty · aim 15–25%"
        case .rem: return p < 20 ? "Low side · aim 20–25%" : p <= 25 ? "Good · aim 20–25%" : "High · aim 20–25%"
        case .light: return (40...60).contains(p) ? "Normal" : p < 40 ? "Below usual" : "Above usual"
        case .awake: return ""
        }
    }

    /// "4 h 05" for minutes; "45 m" under an hour.
    static func hm(_ minutes: Double) -> String { let m = Int(minutes.rounded()); return m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) m" }

    /// The pattern line under the night: only when there is something true to say.
    public static func nightPattern(asleepAt: Int, phoneMinutes: Double?, deepPercent: Double?) -> String? {
        let late = lateMinutes(asleepAt: asleepAt)
        let at = HealthReport.clock((asleepAt + 1440) % 1440)
        let phone = phoneMinutes.flatMap { $0 >= 30 ? "\(hm($0)) on the phone from 11 pm, " : nil } ?? ""
        guard late > 15 else { return phone.isEmpty ? nil : "\(phone.prefix(1).uppercased() + phone.dropFirst())and still asleep by \(at), inside your 1 am line." }
        var text = "\(phone)asleep at \(at), \(hm(Double(late))) past your 1 am line."
        if let deepPercent, deepPercent >= 15 { text += " Deep sleep was fine once you were down; the late start is what cost the night." }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    public struct Fuel: Equatable, Sendable {
        public var kcal = 0.0, protein = 0.0
        public var meals = 0, unconfirmed = 0
        public var kcalTarget: Double?, proteinTarget: Double?
        public var activeKcal: Double?
        /// The latest day on or before this one with any meal logged.
        public var lastMealDay: String?
    }

    /// What was eaten (confirmed meals, plus estimates not yet confirmed), the day's targets, and the watch's active burn.
    public static func fuel(_ document: TrackerDocument, on day: String, engine: TrackerEngine) -> Fuel {
        var f = Fuel()
        for e in document.meals.on(day) {
            let v = e.values
            f.kcal += v.kcal; f.protein += v.protein; f.meals += 1
            if !e.confirmed { f.unconfirmed += 1 }
        }
        let habits = document.mealHabits
        if let h = habits.calories, let t = engine.target(for: h, on: day) { f.kcalTarget = t.maximum ?? t.minimum }
        if let h = habits.protein, let t = engine.target(for: h, on: day) { f.proteinTarget = t.minimum ?? t.maximum }
        let burn = document.health.records(.activeEnergy, on: day, engine: engine)
        f.activeKcal = burn.isEmpty ? nil : burn.map(\.value).reduce(0, +)
        f.lastMealDay = document.meals.entries.map(\.day).filter { $0 <= day }.max()
        return f
    }
}
