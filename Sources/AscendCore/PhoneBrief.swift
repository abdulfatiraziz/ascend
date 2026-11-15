import Foundation

/// The Mac's Brief, Condition, Notes and Dossier screens in small form, so the phone's tabs can show the same things.
/// Read-only on the phone; built fresh by the Mac with every sync reply.
public struct PhoneBrief: Codable, Equatable, Sendable {
    // Brief › Goals
    public var missions: [PhoneMission] = []
    public var orders: [PhoneOrder] = []
    public var measured = 0
    public var targets = 0
    public var behind = 0
    public var milestones = 0
    // Brief › Today
    public var focus: String?
    public var focusDetail: String?
    public var daysLeft: Int?
    // Brief › Routine
    public var routineLine: String?
    public var routine: [PhoneRoutineItem] = []
    public var earlier: [String] = []
    // Condition › Screen time (phone, from what the phone already sent)
    public var screenLine: String?
    public var screenDays: [PhoneScreenDay] = []
    public var topApps: [PhoneScreenApp] = []
    // Field log › Notes
    public var notes: [PhoneNote] = []
    // Dossier
    public var clearance: PhoneClearance?
    public var memo: PhoneMemo?
    public var sections: [PhoneDossierSection] = []
    /// Brief › Today, as the Mac shows it: what Ascend tracks by itself, the day's score and what was eaten.
    public var tracking: [PhoneGlance]? = nil
    public var score: PhoneScore? = nil
    public var food: PhoneFood? = nil
    /// Field log › Urges: the Mac's urges from the last 8 days, newest first, so the phone shows what reached the Mac
    /// and which spot visits still wait for an answer. Spot names only, never coordinates.
    public var urges: [PhoneUrgeLine]? = nil
    public init() {}
}
public struct PhoneUrgeLine: Codable, Equatable, Sendable {
    public var id: String
    /// Seconds since 1970.
    public var at: Double
    /// An `UrgeOutcome` raw value; "Not recorded" with a spot is a visit waiting for an answer.
    public var outcome: String
    public var spot: String?
    public var trigger: String?
    public init(id: String, at: Double, outcome: String, spot: String? = nil, trigger: String? = nil) {
        self.id = id; self.at = at; self.outcome = outcome; self.spot = spot; self.trigger = trigger
    }
}
public struct PhoneMission: Codable, Equatable, Sendable {
    public var id: String, codename: String, title: String, due: String
    public var progress: Double, status: String
    public init(id: String, codename: String, title: String, due: String, progress: Double, status: String) {
        self.id = id; self.codename = codename; self.title = title; self.due = due; self.progress = progress; self.status = status
    }
}
public struct PhoneOrder: Codable, Equatable, Sendable {
    public var mission: String, title: String, line: String, logged: Bool
    public init(mission: String, title: String, line: String, logged: Bool) { self.mission = mission; self.title = title; self.line = line; self.logged = logged }
}
public struct PhoneRoutineItem: Codable, Equatable, Sendable {
    /// "4:00 pm"; status is "OPEN", "TAKEN", "LOGGED" or "in 1 h 53".
    public var time: String, title: String, detail: String, status: String
    public var kind: String, done: Bool, current: Bool
    public init(time: String, title: String, detail: String, status: String, kind: String, done: Bool, current: Bool) {
        self.time = time; self.title = title; self.detail = detail; self.status = status; self.kind = kind; self.done = done; self.current = current
    }
}
public struct PhoneScreenDay: Codable, Equatable, Sendable {
    public var label: String, minutes: Double?, shown: Bool
    public init(label: String, minutes: Double?, shown: Bool) { self.label = label; self.minutes = minutes; self.shown = shown }
}
public struct PhoneScreenApp: Codable, Equatable, Sendable {
    public var name: String, minutes: Double
    public init(name: String, minutes: Double) { self.name = name; self.minutes = minutes }
}
public struct PhoneNote: Codable, Equatable, Sendable {
    public var kind: String, title: String, body: String, date: String, pinned: Bool
    public init(kind: String, title: String, body: String, date: String, pinned: Bool) {
        self.kind = kind; self.title = title; self.body = body; self.date = date; self.pinned = pinned
    }
}
public struct PhoneClearance: Codable, Equatable, Sendable {
    /// level 1–5; marks/ranks/rewards hold all five levels in order.
    public var level: Int, next: String, week: String
    public var marks: [String], ranks: [String], rewards: [String]
    public init(level: Int, next: String, week: String, marks: [String], ranks: [String], rewards: [String]) {
        self.level = level; self.next = next; self.week = week; self.marks = marks; self.ranks = ranks; self.rewards = rewards
    }
}
public struct PhoneMemo: Codable, Equatable, Sendable {
    public var week: String, wins: [String], misses: [String], order: String
    public init(week: String, wins: [String], misses: [String], order: String) { self.week = week; self.wins = wins; self.misses = misses; self.order = order }
}
public struct PhoneDossierSection: Codable, Equatable, Sendable {
    public var title: String, blurb: String, items: [PhoneDossierItem]
    public init(title: String, blurb: String, items: [PhoneDossierItem]) { self.title = title; self.blurb = blurb; self.items = items }
}
public struct PhoneDossierItem: Codable, Equatable, Sendable {
    public var title: String, detail: String, tag: String, placeholder: Bool, progress: Double?
    public init(title: String, detail: String, tag: String, placeholder: Bool, progress: Double?) {
        self.title = title; self.detail = detail; self.tag = tag; self.placeholder = placeholder; self.progress = progress
    }
}
extension PhoneNote {
    /// Notes can be long; the phone shows the start. Cuts on a word.
    public static func clip(_ text: String, max: Int = 600) -> String {
        guard text.count > max else { return text }
        let cut = text.prefix(max)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}

/// One line of the Mac's "Ascend is tracking" card. state: done, going, waiting or missed.
public struct PhoneGlance: Codable, Equatable, Sendable {
    public var title: String, state: String, value: String, note: String?, ratio: Double?
    public init(title: String, state: String, value: String, note: String?, ratio: Double?) {
        self.title = title; self.state = state; self.value = value; self.note = note; self.ratio = ratio
    }
}
public struct PhoneScore: Codable, Equatable, Sendable {
    public var completed: Int, scheduled: Int, line: String
    public init(completed: Int, scheduled: Int, line: String) { self.completed = completed; self.scheduled = scheduled; self.line = line }
}
/// The day's eaten totals (confirmed meals only) and each meal logged.
public struct PhoneFood: Codable, Equatable, Sendable {
    public var kcal: Double, protein: Double, carbs: Double, fat: Double
    public var kcalLimit: Double?, proteinGoal: Double?
    public var pending: Int
    public var meals: [PhoneMealLine]
    public init(kcal: Double, protein: Double, carbs: Double, fat: Double, kcalLimit: Double?, proteinGoal: Double?, pending: Int, meals: [PhoneMealLine]) {
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.kcalLimit = kcalLimit; self.proteinGoal = proteinGoal; self.pending = pending; self.meals = meals
    }
}
public struct PhoneMealLine: Codable, Equatable, Sendable {
    public var time: String, title: String, kcal: Double, protein: Double, carbs: Double, fat: Double, confirmed: Bool
    public init(time: String, title: String, kcal: Double, protein: Double, carbs: Double, fat: Double, confirmed: Bool) {
        self.time = time; self.title = title; self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.confirmed = confirmed
    }
}
