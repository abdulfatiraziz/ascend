import Foundation

/// One measurable target inside a mission. Auto targets read the app's own data; the rest are updated by hand.
public struct MissionTarget: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var unit: String
    public var start: Double?
    public var target: Double
    /// The value typed by hand (manual targets, and the fallback for auto ones).
    public var current: Double?
    /// weight, ffmi, sleep, stress, rhr, steps, protein, wardrobe, skills
    public var auto: String?
    public var due: String?
    /// For "on plan" checks: the day the plan started and how it grows (linear or geometric).
    public var planStart: String?
    public var geometric = false
    /// A yes/no target (target 1).
    public var checklist = false
    /// Smaller is better even without a start value (resting heart rate).
    public var lower = false

    public init(_ id: String, _ title: String, unit: String = "", start: Double? = nil, target: Double, current: Double? = nil,
                auto: String? = nil, due: String? = nil, planStart: String? = nil, geometric: Bool = false, checklist: Bool = false, lower: Bool = false, detail: String = "") {
        self.id = id; self.title = title; self.detail = detail; self.unit = unit; self.start = start; self.target = target
        self.current = current; self.auto = auto; self.due = due; self.planStart = planStart; self.geometric = geometric; self.checklist = checklist; self.lower = lower
    }

    public var lowerIsBetter: Bool { lower || (start ?? target) > target }

    /// 0...1 from start to target. Without a start, it's value ÷ target (or target ÷ value when lower is better).
    public func progress(_ value: Double?) -> Double? {
        guard let v = value else { return nil }
        if checklist { return v >= 1 ? 1 : 0 }
        if let s = start, s != target { return min(1, max(0, (v - s) / (target - s))) }
        guard target > 0, v > 0 else { return 0 }
        return min(1, lowerIsBetter ? target / v : v / target)
    }

    /// Where the plan says the value should be on `day` (yyyy-MM-dd); nil without a plan.
    public func planned(on day: String) -> Double? {
        guard let s = start, let from = planStart, let to = due, let a = Self.date(from), let b = Self.date(to), let d = Self.date(day), b > a else { return nil }
        let t = min(1, max(0, d.timeIntervalSince(a) / b.timeIntervalSince(a)))
        if geometric, s > 0, target > 0 { return s * pow(target / s, t) }
        return s + (target - s) * t
    }

    /// Value with its unit, e.g. "$3,000", "77.8 kg", "5/7", "21%".
    public func format(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        if checklist { return v >= 1 ? "Done" : "Not yet" }
        let n = v.rounded() == v || abs(v) >= 100 ? Int(v.rounded()).formatted() : String(format: abs(v) < 10 ? "%.2f" : "%.1f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        switch unit {
        case "$": return "$" + n
        case "%": return n + "%"
        case "/7", "/10": return n + unit
        case "": return n
        default: return n + " " + unit
        }
    }

    static func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}

/// One of the five missions (A–E): the top-level goals everything else serves.
public struct MissionFile: Codable, Identifiable, Equatable, Sendable {
    public var id: String          // "A"…"E"
    public var codename: String
    public var title: String
    public var due: String
    public var brief: String
    public var targets: [MissionTarget]
    public init(id: String, codename: String, title: String, due: String, brief: String, targets: [MissionTarget]) {
        self.id = id; self.codename = codename; self.title = title; self.due = due; self.brief = brief; self.targets = targets
    }
    /// Average progress of the targets that have a value.
    public func progress(_ value: (MissionTarget) -> Double?) -> Double? {
        let p = targets.compactMap { $0.progress(value($0)) }
        return p.isEmpty ? nil : p.reduce(0, +) / Double(p.count)
    }
}

public enum Missions {
    public static let heightM = 1.80
    public static let birthday = "2001-06-01"

    /// Fat-free mass index: lean mass ÷ height².
    public static func ffmi(kg: Double, bodyFatPercent: Double, heightM: Double = heightM) -> Double {
        kg * (1 - bodyFatPercent / 100) / (heightM * heightM)
    }
    /// Weight at a body fat % for the same lean mass.
    public static func weight(leanKg: Double, atBodyFat percent: Double) -> Double { leanKg / (1 - percent / 100) }
    /// Monthly growth rate to multiply `from` into `to` over `months`.
    public static func monthlyGrowth(from: Double, to: Double, months: Double) -> Double { pow(to / from, 1 / months) - 1 }

    /// Example missions for a fresh install (age 30; 180 cm, 78.0 kg at ~22%; $3,000 a month).
    public static var defaults: [MissionFile] {
        let lean = 78.0 * (1 - 0.22)                               // 60.8 kg
        let at15 = weight(leanKg: lean, atBodyFat: 15)             // 71.6 kg
        let growth = monthlyGrowth(from: 3000, to: 12000, months: 16.5)
        return [
            MissionFile(id: "A", codename: "The Instrument", title: "Mind & body", due: "2026-12-31",
                brief: "Phase 1: 15% body fat by 31 Dec. Phase 2: 12% by 31 Mar 2027. The long mission: a muscle score of 21.5, the lean Bond build.",
                targets: [
                    MissionTarget("a.weight", "Weight", unit: "kg", start: 78.0, target: (at15 * 10).rounded() / 10, auto: "weight", due: "2026-12-31", planStart: "2026-11-03",
                                  detail: "Lean mass \(String(format: "%.1f", lean)) kg ÷ 0.85 = \(String(format: "%.1f", at15)) kg at 15%. About −0.77 kg a week."),
                    MissionTarget("a.bodyfat", "Body fat", unit: "%", start: 22, target: 15, current: 22, due: "2026-12-31",
                                  detail: "Your own estimate; update it monthly. The scale reads lower. Then 12% by 31 Mar 2027."),
                    MissionTarget("a.ffmi", "Muscle score (FFMI)", start: 18.8, target: 21.5, auto: "ffmi", due: "2029-06-01",
                                  detail: "Lean mass ÷ height². 21.5 = 70 kg lean, about 78 kg at 11%: +9 kg of muscle over 2–3 years."),
                    MissionTarget("a.sleep", "Asleep by 1 am", unit: "/7", start: 1, target: 5, auto: "sleep", detail: "Nights in the last 7. Then move to 12:30 am."),
                    MissionTarget("a.stress", "Evening stress", start: 40, target: 32, auto: "stress", detail: "Watch stress after 6 pm, last 7 days."),
                    MissionTarget("a.rhr", "Resting heart rate", unit: "bpm", target: 59, auto: "rhr", lower: true, detail: "Under 60 means a strong engine."),
                    MissionTarget("a.steps", "Steps, 7-day average", target: 10000, auto: "steps", detail: "Floor 7,000; mission 10,000."),
                    MissionTarget("a.protein", "Protein, 7-day average", unit: "g", target: 150, auto: "protein", detail: "About 2.5 g per kg of lean mass protects muscle in the cut."),
                    MissionTarget("a.bench", "Bench press", unit: "× bodyweight", target: 1.0, detail: "One clean rep at your bodyweight."),
                    MissionTarget("a.squat", "Squat", unit: "× bodyweight", target: 1.5),
                    MissionTarget("a.deadlift", "Deadlift", unit: "× bodyweight", target: 2.0),
                    MissionTarget("a.pullups", "Strict pull-ups", unit: "reps", target: 10),
                    MissionTarget("a.run", "5 km run", unit: "min", start: 35, target: 25, detail: "Under 25 minutes."),
                    MissionTarget("a.mind", "Breathing or NSDR days this week", unit: "/7", target: 6, current: 0, detail: "10 minutes a day."),
                    MissionTarget("a.skin", "Dermatologist visit", target: 1, current: 0, checklist: true, detail: "Then SPF every morning, a night routine."),
                    MissionTarget("a.teeth", "Dental cleaning", target: 1, current: 0, due: "2027-05-14", checklist: true, detail: "Every 6 months; whitening after the cut."),
                    MissionTarget("a.hair", "Hair photo this month", target: 1, current: 0, checklist: true, detail: "Same angle every 4 weeks; keep the current treatment."),
                ]),
            MissionFile(id: "B", codename: "Treasury", title: "$12k a month", due: "2028-03-31",
                brief: "4× in 16½ months = +\(String(format: "%.1f", growth * 100))% a month. Checkpoints: $4,400 by Mar 2027 · $7,250 by Sep 2027 · $12,000 by Mar 2028. Save 30% of it.",
                targets: [
                    MissionTarget("b.income", "Monthly income", unit: "$", start: 3000, target: 12000, current: 3000, due: "2028-03-31", planStart: "2026-11-14", geometric: true,
                                  detail: "Update on payday. The plan line grows \(String(format: "%.1f", growth * 100))% a month."),
                    MissionTarget("b.streams", "Income streams", start: 1, target: 3, current: 1, detail: "Job + consulting retainers + products (Cueplane, YouTube)."),
                    MissionTarget("b.savings", "Savings rate", unit: "%", target: 30, detail: "Saved or invested ÷ income, monthly."),
                    MissionTarget("b.fund", "Emergency fund", unit: "months", target: 6, detail: "Months of expenses in cash."),
                ]),
            MissionFile(id: "C", codename: "The Voice", title: "American accent", due: "2027-12-31",
                brief: "Shadow 20 minutes a day, record the same 60-second passage every Sunday, score it honestly.",
                targets: [
                    MissionTarget("c.score", "Accent score, weekly recording", unit: "/10", target: 9, detail: "Score the Sunday recording 1–10; keep every file."),
                    MissionTarget("c.shadow", "Shadowing days this week", unit: "/7", target: 6, current: 0, detail: "20 minutes a day."),
                    MissionTarget("c.vo", "YouTube voice-over with no retakes", target: 1, current: 0, checklist: true),
                    MissionTarget("c.call", "A stranger doesn't ask where you're from", target: 1, current: 0, checklist: true),
                ]),
            MissionFile(id: "D", codename: "Presence", title: "Style & people", due: "2027-12-31",
                brief: "How the room sees you: a capsule wardrobe, sharp grooming, a close circle, dating, family.",
                targets: [
                    MissionTarget("d.wardrobe", "Capsule pieces owned", target: 12, auto: "wardrobe", detail: "Counted from the Dossier's wardrobe."),
                    MissionTarget("d.grooming", "Grooming routine days this week", unit: "/7", target: 6, current: 0),
                    MissionTarget("d.circle", "Close-circle meet-ups this month", target: 4, current: 0),
                    MissionTarget("d.dates", "Dates this month", target: 2, current: 0),
                    MissionTarget("d.family", "Family calls this week", target: 2, current: 0),
                ]),
            MissionFile(id: "E", codename: "Field Craft", title: "Hard skills", due: "2027-12-31",
                brief: "Capable, not just good-looking: water, road, ring, kitchen, a second language.",
                targets: [
                    MissionTarget("e.skills", "Dossier skills, average", unit: "%", target: 100, auto: "skills", detail: "From the Dossier's skill bars."),
                    MissionTarget("e.swim", "Freestyle without stopping", unit: "m", start: 0, target: 1000, current: 0),
                    MissionTarget("e.combat", "Boxing or Muay Thai sessions a week", target: 2, current: 0),
                    MissionTarget("e.cook", "Core meals you can cook", start: 0, target: 6, current: 0, detail: "High protein, under 600 kcal each."),
                    MissionTarget("e.drive", "Driving licence", target: 1, current: 0, checklist: true),
                    MissionTarget("e.language", "Second language at A2", target: 1, current: 0, checklist: true),
                ]),
        ]
    }

    public static func summary(_ missions: [MissionFile], value: (MissionTarget) -> Double?) -> String {
        var lines = ["MISSIONS (Abdul's five top-level goals, A–E; data only):"]
        for m in missions {
            lines.append("\(m.id) · \(m.codename) — \(m.title), due \(m.due). \(m.brief)")
            for t in m.targets {
                lines.append("- \(t.title): \(t.format(value(t))) → \(t.format(t.target))\(t.detail.isEmpty ? "" : " (\(t.detail))")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
