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
    /// A repeating visit (dermatologist, dentist): how many months between visits.
    public var everyMonths: Int?
    /// The last visit you picked, and a booked next visit if you set one (yyyy-MM-dd).
    public var lastVisit: String?
    public var nextVisit: String?

    public init(_ id: String, _ title: String, unit: String = "", start: Double? = nil, target: Double, current: Double? = nil,
                auto: String? = nil, due: String? = nil, planStart: String? = nil, geometric: Bool = false, checklist: Bool = false, lower: Bool = false, everyMonths: Int? = nil, detail: String = "") {
        self.id = id; self.title = title; self.detail = detail; self.unit = unit; self.start = start; self.target = target
        self.current = current; self.auto = auto; self.due = due; self.planStart = planStart; self.geometric = geometric; self.checklist = checklist; self.lower = lower; self.everyMonths = everyMonths
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
        if everyMonths != nil { return v >= 1 ? "Up to date" : "Overdue" }
        if checklist { return v >= 1 ? "Done" : "Not yet" }
        let n = v.rounded() == v || abs(v) >= 100 ? Int(v.rounded()).formatted() : String(format: abs(v) < 10 ? "%.2f" : "%.1f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        switch unit {
        case "$": return "$" + n
        case "%": return n + "%"
        case "/3", "/7", "/10": return n + unit
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
                    MissionTarget("a.bodyfat", "Body fat", unit: "%", start: 22, target: 15, current: 22, due: "2026-12-31", planStart: "2026-11-03",
                                  detail: "Your own estimate; update it monthly. The scale reads lower. Then 12% by 31 Mar 2027."),
                    MissionTarget("a.ffmi", "Muscle score (FFMI)", start: 18.8, target: 21.5, auto: "ffmi", due: "2029-06-01", planStart: "2026-11-14",
                                  detail: "Lean mass ÷ height². 21.5 = 70 kg lean, about 78 kg at 11%: +9 kg of muscle over 2–3 years."),
                    MissionTarget("a.gym", "Gym sessions this week", unit: "/3", target: 3, auto: "gym", detail: "Mon · Wed · Sat. Three a week is a clean week for Clearance."),
                    MissionTarget("a.sleep", "Asleep by 1 am", unit: "/7", start: 1, target: 5, auto: "sleep", detail: "Nights in the last 7. Then move to 12:30 am."),
                    MissionTarget("a.stress", "Evening stress", start: 40, target: 32, auto: "stress", detail: "Watch stress after 6 pm, last 7 days."),
                    MissionTarget("a.rhr", "Resting heart rate", unit: "bpm", target: 59, auto: "rhr", lower: true, detail: "Under 60 means a strong engine."),
                    MissionTarget("a.steps", "Steps, 7-day average", target: 10000, auto: "steps", detail: "Floor 7,000; mission 10,000."),
                    MissionTarget("a.protein", "Protein, 7-day average", unit: "g", target: 150, auto: "protein", detail: "About 2.5 g per kg of lean mass protects muscle in the cut."),
                    MissionTarget("a.skin", "Dermatologist visit", target: 1, everyMonths: 1, detail: "Once a month. Pick the day you went; the next visit is set a month later, or pick a booked date."),
                    MissionTarget("a.teeth", "Dental cleaning", target: 1, everyMonths: 6, detail: "Every 6 months; whitening after the cut. Pick the day you went; the next visit is set 6 months later, or pick a booked date."),
                ]),
            MissionFile(id: "B", codename: "Treasury", title: "$12k a month", due: "2028-03-31",
                brief: "4× in 16½ months = +\(String(format: "%.1f", growth * 100))% a month. Checkpoints: $4,400 by Mar 2027 · $7,250 by Sep 2027 · $12,000 by Mar 2028. Save 30% of it.",
                targets: [
                    MissionTarget("b.income", "Monthly income", unit: "$", start: 3000, target: 12000, current: 3000, due: "2028-03-31", planStart: "2026-11-14", geometric: true,
                                  detail: "Update on payday. The plan line grows \(String(format: "%.1f", growth * 100))% a month."),
                    MissionTarget("b.streams", "Income streams", start: 1, target: 3, current: 1, due: "2028-03-31", planStart: "2026-11-14", detail: "Job + consulting retainers + products (Cueplane, YouTube)."),
                    MissionTarget("b.savings", "Savings rate", unit: "%", target: 30, detail: "Saved or invested ÷ income, monthly."),
                    MissionTarget("b.fund", "Emergency fund", unit: "months", target: 6, detail: "Months of expenses in cash."),
                ]),
            MissionFile(id: "C", codename: "The Voice", title: "American accent", due: "2027-12-31",
                brief: "Practise most days (one tap on Today: did you or not), record the same 60-second passage every Sunday, score it honestly.",
                targets: [
                    MissionTarget("c.score", "Accent score, weekly recording", unit: "/10", target: 9, detail: "Score the Sunday recording 1–10; keep every file."),
                    MissionTarget("c.shadow", "Practice days this week", unit: "/7", target: 6, auto: "accent", detail: "Counted from the daily Accent practice tap on Today."),
                    MissionTarget("c.vo", "YouTube voice-over with no retakes", target: 1, current: 0, checklist: true),
                    MissionTarget("c.call", "A stranger doesn't ask where you're from", target: 1, current: 0, checklist: true),
                ]),
            MissionFile(id: "D", codename: "Presence", title: "Style & people", due: "2027-12-31",
                brief: "How the room sees you: a capsule wardrobe, sharp grooming, a close circle, dating, family.",
                targets: [
                    MissionTarget("d.wardrobe", "Capsule pieces owned", target: 12, auto: "wardrobe", detail: "Counted from the Dossier's wardrobe."),
                    MissionTarget("d.grooming", "Grooming routine days this week", unit: "/7", target: 6),
                    MissionTarget("d.circle", "Close-circle meet-ups this month", target: 4),
                    MissionTarget("d.dates", "Dates this month", target: 2),
                    MissionTarget("d.family", "Family calls this week", target: 2),
                ]),
            MissionFile(id: "E", codename: "Field Craft", title: "Hard skills", due: "2027-12-31",
                brief: "Capable outdoors: water, trail, saddle, range, track. Log a session only on the day it happens.",
                targets: [
                    MissionTarget("e.swim", "Swimming: freestyle without stopping", unit: "m", start: 0, target: 1000, due: "2027-12-31", planStart: "2026-11-14",
                                  detail: "Type your best distance on the days you test."),
                    MissionTarget("e.hike", "Hiking: hikes done", start: 0, target: 6, auto: "hikes", due: "2027-12-31", planStart: "2026-11-14",
                                  detail: "Counted from hikes recorded on the watch."),
                    MissionTarget("e.ride", "Horse riding: lessons", start: 0, target: 12, due: "2027-12-31", planStart: "2026-11-14", detail: "Add one after each lesson."),
                    MissionTarget("e.range", "Firearm: range sessions", start: 0, target: 10, due: "2027-12-31", planStart: "2026-11-14", detail: "Safety course first, then add one per session."),
                    MissionTarget("e.track", "Race car: track or karting days", start: 0, target: 4, due: "2027-12-31", planStart: "2026-11-14", detail: "Add one per track day."),
                ]),
        ]
    }

    /// Current definitions (titles, targets, plans) from the code, with every value typed into the saved file kept.
    public static func merged(_ saved: [MissionFile]) -> [MissionFile] {
        let typed = Dictionary(saved.flatMap(\.targets).map { ($0.id, $0.current) }, uniquingKeysWith: { a, _ in a })
        let visits = Dictionary(saved.flatMap(\.targets).map { ($0.id, ($0.lastVisit, $0.nextVisit)) }, uniquingKeysWith: { a, _ in a })
        return Missions.defaults.map { def in
            var m = def
            for i in m.targets.indices {
                if let v = typed[m.targets[i].id] { m.targets[i].current = v }
                if m.targets[i].everyMonths != nil, let d = visits[m.targets[i].id] { m.targets[i].lastVisit = d.0; m.targets[i].nextVisit = d.1 }
            }
            return m
        }
    }

    /// The targets most behind, for the Orders list: behind plan first (biggest gap), then not logged yet.
    public static func orders(_ missions: [MissionFile], value: (MissionTarget) -> Double?, today: String, limit: Int = 3) -> [MissionOrder] {
        var behind: [MissionOrder] = [], missing: [MissionOrder] = []
        for m in missions {
            for t in m.targets where !t.checklist && t.everyMonths == nil {
                guard let v = value(t) else {
                    missing.append(MissionOrder(missionID: m.id, target: t, value: nil, need: nil, severity: 0))
                    continue
                }
                guard let p = t.progress(v), p < 1 else { continue }
                if let plan = t.planned(on: today) {
                    let span = abs(t.target - (t.start ?? plan))
                    let gap = (t.lowerIsBetter ? v - plan : plan - v) / max(span, 1e-9)
                    if gap > 0.01 { behind.append(MissionOrder(missionID: m.id, target: t, value: v, need: plan, severity: 1 + gap)) }
                } else if p < 0.6 {
                    behind.append(MissionOrder(missionID: m.id, target: t, value: v, need: t.target, severity: 1 - p))
                }
            }
        }
        return Array((behind.sorted { $0.severity > $1.severity } + missing).prefix(limit))
    }

    /// One word for a mission's state: BEHIND when any order is from it, ON PLAN when anything is measured, else NO DATA.
    public static func status(_ m: MissionFile, value: (MissionTarget) -> Double?, today: String) -> MissionStatus {
        let measured = m.targets.filter { !$0.checklist && $0.everyMonths == nil && value($0) != nil }
        if measured.isEmpty { return .noData }
        let behind = orders([m], value: value, today: today, limit: 99).contains { $0.value != nil }
        return behind ? .behind : .onPlan
    }

    public static func summary(_ missions: [MissionFile], value: (MissionTarget) -> Double?) -> String {
        var lines = ["MISSIONS (Abdul's five top-level goals, A–E; data only):"]
        for m in missions {
            lines.append("\(m.id) · \(m.codename) — \(m.title), due \(m.due). \(m.brief)")
            for t in m.targets {
                if t.everyMonths != nil {
                    lines.append("- \(t.title): last visit \(t.lastVisit ?? "not logged"), next \(t.nextVisitDay ?? "not set")")
                    continue
                }
                lines.append("- \(t.title): \(t.format(value(t))) → \(t.format(t.target))\(t.detail.isEmpty ? "" : " (\(t.detail))")")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public struct MissionOrder: Equatable, Sendable {
    public var missionID: String
    public var target: MissionTarget
    public var value: Double?
    /// Where the plan says it should be today, or the target when there's no plan; nil when not logged.
    public var need: Double?
    public var severity: Double
    public var line: String {
        guard let v = value else { return "Not logged yet. Enter it in mission \(missionID)." }
        let need = need.map { (($0 * 10).rounded() / 10) } ?? target.target
        return "\(target.format(v)) now · need \(target.format(need))\(target.planned(on: "9999-12-31") != nil ? " to be on plan" : "")"
    }
}

public enum MissionStatus: String, Sendable { case onPlan = "On plan", behind = "Behind", noData = "No data" }

/// How a target gets its number: synced from a device or log, worked out by the app, or typed by you.
public enum TargetKind: String, CaseIterable, Sendable {
    case synced = "Syncs automatically", calculated = "Calculated", manual = "You log"
}

/// One word for one target.
public enum TargetState: String, Sendable { case done = "Done", onPlan = "On plan", behind = "Behind", notLogged = "Not logged", notYet = "Not yet", scheduled = "Scheduled", overdue = "Overdue" }

extension MissionTarget {
    public var kind: TargetKind {
        switch auto { case nil: .manual; case "ffmi": .calculated; default: .synced }
    }
    /// Where a synced or calculated number comes from.
    public var source: String {
        switch auto {
        case "weight": "Scale"
        case "ffmi": "Weight + body fat"
        case "sleep", "stress", "rhr", "steps": "Watch"
        case "protein": "Food log"
        case "gym", "hikes": "Watch workouts"
        case "accent": "Daily tap on Today"
        case "wardrobe", "skills": "Dossier"
        default: ""
        }
    }
    /// How often to type a manual number.
    public var cadence: String {
        if let n = everyMonths { return n == 1 ? "Every month" : "Every \(n) months" }
        return Missions.cadence[id] ?? "When it changes"
    }

    /// The next visit: a booked date if it comes after the last visit, else the last visit plus the interval.
    public var nextVisitDay: String? {
        if let b = nextVisit, b > (lastVisit ?? "") { return b }
        guard let n = everyMonths, let l = lastVisit, let d = Self.date(l) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let next = cal.date(byAdding: .month, value: n, to: d) else { return nil }
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: next)
    }

    /// 1 when the next visit is today or later, 0 when it has passed, nil when nothing is logged.
    public func visitValue(today: String) -> Double? { nextVisitDay.map { $0 < today ? 0 : 1 } }

    public func state(_ value: Double?, today: String) -> TargetState {
        if everyMonths != nil {
            guard let next = nextVisitDay else { return .notLogged }
            return next < today ? .overdue : .scheduled
        }
        guard let v = value else { return .notLogged }
        if (progress(v) ?? 0) >= 1 { return .done }
        if checklist { return .notYet }
        if let plan = planned(on: today) {
            let span = abs(target - (start ?? plan))
            let gap = (lowerIsBetter ? v - plan : plan - v) / max(span, 1e-9)
            return gap > 0.01 ? .behind : .onPlan
        }
        return (progress(v) ?? 0) < 0.6 ? .behind : .onPlan
    }
}

extension Missions {
    public static let cadence: [String: String] = [
        "a.bodyfat": "Monthly",
        "b.income": "Monthly", "b.savings": "Monthly", "b.fund": "Monthly",
        "c.score": "Sundays", "c.shadow": "Weekly", "c.vo": "Once", "c.call": "Once",
        "d.grooming": "Weekly", "d.circle": "Monthly", "d.dates": "Monthly", "d.family": "Weekly",
        "e.swim": "When you test", "e.ride": "After each lesson", "e.range": "After each session", "e.track": "After each track day",
    ]
}
