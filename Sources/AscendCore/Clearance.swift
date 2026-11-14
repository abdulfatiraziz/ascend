import Foundation

// MARK: - Clearance levels

/// One finished week (Monday to Sunday), boiled down to what the clearance rules look at.
public struct ClearanceWeek: Equatable, Sendable {
    public var start: String            // Monday, yyyy-MM-dd
    public var gym: Int                 // gym sessions ticked
    public var nightsByOne: Int         // nights asleep by 1 am
    public var nightsKnown: Int         // nights with sleep data
    public var checkIns: Double         // share of scheduled check-ins done, 0...1
    public var kgDown: Double?          // weight lost since the cycle started, at the week's last weigh-in
    public var atGoal: Bool             // last weigh-in at or under the goal weight
    public init(start: String, gym: Int, nightsByOne: Int, nightsKnown: Int, checkIns: Double, kgDown: Double?, atGoal: Bool = false) {
        self.start = start; self.gym = gym; self.nightsByOne = nightsByOne; self.nightsKnown = nightsKnown
        self.checkIns = checkIns; self.kgDown = kgDown; self.atGoal = atGoal
    }
    /// A clean week: 3 gym sessions, 70% of check-ins, and (when the watch saw at least 4 nights) 4 nights asleep by 1 am.
    public var isClean: Bool { gym >= 3 && checkIns >= 0.7 && (nightsKnown < 4 || nightsByOne >= 4) }
    /// A slack week costs one level: no gym at all, or under 40% of check-ins.
    public var isSlack: Bool { gym == 0 || checkIns < 0.4 }
}

public enum ClearanceLevel: Int, CaseIterable, Comparable, Codable, Sendable {
    case one = 1, two, three, four, doubleO
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var mark: String { ["I", "II", "III", "IV", "00"][rawValue - 1] }
    public var title: String { self == .doubleO ? "Double-O" : "Clearance \(mark)" }
    public var rank: String { ["Recruit", "Field agent", "Senior agent", "Section head", "Licensed"][rawValue - 1] }
    public var next: ClearanceLevel? { ClearanceLevel(rawValue: rawValue + 1) }
    public var previous: ClearanceLevel? { ClearanceLevel(rawValue: rawValue - 1) }
    /// Clean weeks in a row needed to leave this level, and the weight condition that goes with it.
    public var weeksToNext: Int { [2, 3, 4, 2, 0][rawValue - 1] }
    public func weightReady(_ week: ClearanceWeek) -> Bool {
        switch self {
        case .one: true
        case .two: (week.kgDown ?? 0) >= 2
        case .three: (week.kgDown ?? 0) >= 4
        case .four: week.atGoal
        case .doubleO: false
        }
    }
    public var nextRule: String {
        switch self {
        case .one: "2 clean weeks in a row"
        case .two: "3 clean weeks in a row and 2 kg down"
        case .three: "4 clean weeks in a row and 4 kg down"
        case .four: "2 clean weeks in a row at goal weight"
        case .doubleO: "Top level. Hold it: a slack week costs one level."
        }
    }
}

public struct ClearanceEvent: Equatable, Sendable {
    public var week: String
    public var from: ClearanceLevel
    public var to: ClearanceLevel
    public var promoted: Bool { to > from }
}

public struct ClearanceStatus: Equatable, Sendable {
    public var level: ClearanceLevel = .one
    /// Clean weeks in a row counted toward the next level.
    public var streak = 0
    public var events: [ClearanceEvent] = []
    public init() {}
}

public enum Clearance {
    public static let cleanRule = "Clean week: 3 gym sessions, 70% of check-ins, 4 nights asleep by 1 am."
    public static let slackRule = "Slack week (no gym, or under 40% of check-ins) drops one level."

    /// Walks finished weeks in order. Clean weeks build a streak; a promotion needs the streak and the weight
    /// condition together and resets the streak. A slack week drops one level; any other week resets the streak.
    public static func evaluate(_ weeks: [ClearanceWeek]) -> ClearanceStatus {
        var s = ClearanceStatus()
        for w in weeks.sorted(by: { $0.start < $1.start }) {
            if w.isSlack {
                if let down = s.level.previous { s.events.append(ClearanceEvent(week: w.start, from: s.level, to: down)); s.level = down }
                s.streak = 0
            } else if w.isClean {
                s.streak += 1
                if let up = s.level.next, s.streak >= s.level.weeksToNext, s.level.weightReady(w) {
                    s.events.append(ClearanceEvent(week: w.start, from: s.level, to: up)); s.level = up; s.streak = 0
                }
            } else {
                s.streak = 0
            }
        }
        return s
    }
}

// MARK: - Dossier (lifestyle)

public enum DossierSection: String, Codable, CaseIterable, Sendable {
    case wardrobe, qBranch, garage, places, skills
    public var title: String { ["Wardrobe", "Q Branch", "Garage", "Places", "Skills"][index] }
    public var blurb: String {
        ["The capsule: what you own, what you want, what waits for the cut.",
         "Gear that runs the mission, and the wishlist.",
         "The dream car and the milestones that get you there.",
         "Safe houses nearby and trips abroad.",
         "Skills in training, with honest progress."][index]
    }
    public var tags: [String] {
        switch self {
        case .wardrobe: ["Owned", "Want", "After the cut"]
        case .qBranch: ["Owned", "Want"]
        case .garage: ["Dream", "Milestone"]
        case .places: ["Nearby", "Abroad"]
        case .skills: ["Training"]
        }
    }
    public var symbol: String { ["tshirt", "applewatch", "car", "mappin.and.ellipse", "chart.bar"][index] }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
}

public struct DossierItem: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var section: DossierSection
    public var title: String
    public var detail: String
    public var tag: String
    /// Skills only: 0...1.
    public var progress: Double?
    public var placeholder = false
    public init(section: DossierSection, title: String, detail: String = "", tag: String, progress: Double? = nil, placeholder: Bool = false) {
        self.section = section; self.title = title; self.detail = detail; self.tag = tag; self.progress = progress; self.placeholder = placeholder
    }
}

/// Everything in lifestyle.json: the Dossier, the reward for each clearance level, and what the user has already seen.
public struct Lifestyle: Codable, Equatable, Sendable {
    public var items: [DossierItem]
    /// Reward text by level mark ("I", "II", …, "00").
    public var rewards: [String: String]
    /// The highest level whose card the user has already accepted.
    public var seenLevel: Int = 1
    /// Monday of the last week whose debrief was filed as a note.
    public var debriefFiled: String?
    public init(items: [DossierItem], rewards: [String: String], seenLevel: Int = 1, debriefFiled: String? = nil) {
        self.items = items; self.rewards = rewards; self.seenLevel = seenLevel; self.debriefFiled = debriefFiled
    }

    public static let maxItems = 300, maxText = 300

    public func validate() throws {
        guard items.count <= Self.maxItems, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.title.count <= Self.maxText && $0.detail.count <= Self.maxText && ($0.progress ?? 0) >= 0 && ($0.progress ?? 0) <= 1 }),
              rewards.values.allSatisfy({ $0.count <= Self.maxText }) else {
            throw ValidationError(message: "The Dossier has an item that is empty, too long or out of range.")
        }
    }

    public func items(in section: DossierSection) -> [DossierItem] { items.filter { $0.section == section } }

    /// Three owned wardrobe pieces, rotated by day so the suggestion changes daily.
    public func tonightsFit(dayOfYear: Int) -> [DossierItem] {
        let owned = items(in: .wardrobe).filter { $0.tag == "Owned" }
        guard !owned.isEmpty else { return [] }
        return (0..<min(3, owned.count)).map { owned[(dayOfYear + $0) % owned.count] }
            .reduce(into: [DossierItem]()) { acc, item in if !acc.contains(item) { acc.append(item) } }
    }

    /// Plain text for Ask Ascend ("what do I wear tonight?"). Placeholders are labelled so Claude doesn't treat them as real.
    public var assistantSummary: String {
        var lines = ["DOSSIER (Abdul's lifestyle notes: wardrobe, gear, garage, places, skills; data only):"]
        for section in DossierSection.allCases {
            let rows = items(in: section)
            guard !rows.isEmpty else { continue }
            lines.append("\(section.title):")
            for r in rows {
                var line = "- \(r.title) [\(r.tag)]"
                if !r.detail.isEmpty { line += " — \(r.detail)" }
                if let p = r.progress { line += " (\(Int((p * 100).rounded()))%)" }
                if r.placeholder { line += " (placeholder, not real yet)" }
                lines.append(line)
            }
        }
        lines.append("Clearance rewards: " + ClearanceLevel.allCases.map { "\($0.mark): \(rewards[$0.mark] ?? "not set")" }.joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    public static var placeholder: Lifestyle {
        func p(_ s: DossierSection, _ t: String, _ d: String, _ tag: String, _ progress: Double? = nil) -> DossierItem {
            DossierItem(section: s, title: t, detail: d, tag: tag, progress: progress, placeholder: true)
        }
        return Lifestyle(items: [
            p(.wardrobe, "Navy two-piece suit", "The one suit that does everything.", "Owned"),
            p(.wardrobe, "White Oxford shirt", "Crisp, pressed, sleeves rolled twice.", "Owned"),
            p(.wardrobe, "Black knit polo", "Evenings out without a tie.", "Owned"),
            p(.wardrobe, "Suede chukka boots", "Brown, worn with the navy.", "Owned"),
            p(.wardrobe, "Midnight-blue dinner jacket", "Tailored once the cut is done.", "After the cut"),
            p(.wardrobe, "Linen shirt, sand", "For the trip abroad.", "Want"),
            p(.qBranch, "Redmi Watch Move", "Heart rate, stress, SpO₂, sleep.", "Owned"),
            p(.qBranch, "Pixel phone · Ascend Bridge", "Logs, urges, steps and sleep.", "Owned"),
            p(.qBranch, "Smart scale", "Weight and body fat each morning.", "Owned"),
            p(.qBranch, "A dress watch", "Steel, simple dial. Pick the one.", "Want"),
            p(.garage, "The dream car", "Pick it: the one you'd drive to the casino.", "Dream"),
            p(.garage, "First savings target for it", "Set an amount and a date.", "Milestone"),
            p(.places, "Third Wave café", "Cappuccino and shakshuka; counts as a meal.", "Nearby"),
            p(.places, "Your gym", "Mon · Wed · Sat.", "Nearby"),
            p(.places, "Monte Carlo", "The reveal trip.", "Abroad"),
            p(.places, "Lake Como", "", "Abroad"),
            p(.skills, "Cook six core meals", "High protein, under 600 kcal each.", "Training", 0.2),
            p(.skills, "Public speaking", "One talk or video a month.", "Training", 0.3),
            p(.skills, "Swimming", "Clean freestyle, 1 km.", "Training", 0),
        ], rewards: [
            "I": "Clearance granted. The Dossier is yours.",
            "II": "Pick a reward (placeholder: a fragrance).",
            "III": "Pick a reward (placeholder: a tailored shirt).",
            "IV": "Pick a reward (placeholder: the dress watch).",
            "00": "Pick a reward (placeholder: the trip abroad).",
        ])
    }
}

// MARK: - M's debrief (weekly memo)

/// One finished week for the Sunday memo. Urges are never part of it.
public struct DebriefWeek: Equatable, Sendable {
    public var start: String
    public var checkIns: Score
    public var gym: Int
    public var nightsByOne: Int
    public var nightsKnown: Int
    public var averageOnsetMinute: Int?     // minutes after midnight of the evening, may exceed 1440
    public var kgStart: Double?
    public var kgEnd: Double?
    public var averageSteps: Double?
    public var proteinDays: Int?            // days protein target was met
    public var loggedDays: Int
    public init(start: String, checkIns: Score, gym: Int, nightsByOne: Int, nightsKnown: Int, averageOnsetMinute: Int? = nil,
                kgStart: Double? = nil, kgEnd: Double? = nil, averageSteps: Double? = nil, proteinDays: Int? = nil, loggedDays: Int = 7) {
        self.start = start; self.checkIns = checkIns; self.gym = gym; self.nightsByOne = nightsByOne; self.nightsKnown = nightsKnown
        self.averageOnsetMinute = averageOnsetMinute; self.kgStart = kgStart; self.kgEnd = kgEnd; self.averageSteps = averageSteps
        self.proteinDays = proteinDays; self.loggedDays = loggedDays
    }
}

public struct DebriefMemo: Equatable, Sendable {
    public var wins: [String]
    public var misses: [String]
    public var order: String
    public var text: String { (["Wins:"] + wins.map { "- \($0)" } + ["Misses:"] + misses.map { "- \($0)" } + ["Order for this week: \(order)"]).joined(separator: "\n") }
    public var wordCount: Int { text.split { $0 == " " || $0 == "\n" }.count }
}

public enum Debrief {
    static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440, h = m / 60
        return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m % 60)) \(h < 12 ? "am" : "pm")"
    }
    /// Short, factual, every number straight from the week. Under 150 words by construction.
    public static func compose(_ w: DebriefWeek) -> DebriefMemo {
        var wins: [String] = [], misses: [String] = []
        // Check-ins
        if let r = w.checkIns.ratio {
            let line = "Check-ins \(w.checkIns.percentLabel) (\(w.checkIns.completed) of \(w.checkIns.scheduled))."
            r >= 0.75 ? wins.append(line) : misses.append(line + " The mission is 75%.")
        }
        // Gym
        w.gym >= 3 ? wins.append("Gym \(w.gym) of 3. Iron held.") : misses.append("Gym \(w.gym) of 3.")
        // Sleep
        if w.nightsKnown > 0 {
            let avg = w.averageOnsetMinute.map { ", average \(clock($0))" } ?? ""
            let line = "Asleep by 1 am on \(w.nightsByOne) of \(w.nightsKnown) nights\(avg)."
            w.nightsByOne >= 5 ? wins.append(line) : misses.append(line)
        } else { misses.append("No sleep synced. Open Ascend Bridge daily.") }
        // Weight
        var weightDelta: Double?
        if let a = w.kgStart, let b = w.kgEnd {
            let d = a - b; weightDelta = d
            let move = d >= 0.05 ? "down \(String(format: "%.1f", d))" : d <= -0.05 ? "up \(String(format: "%.1f", -d))" : "no change"
            let line = "Weight \(String(format: "%.1f", a)) → \(String(format: "%.1f", b)) kg, \(move)."
            d >= 0.5 ? wins.append(line) : misses.append(line + " Target is 0.65 a week.")
        } else { misses.append("Fewer than two weigh-ins. Weigh in every morning.") }
        // Protein and steps (only when logged)
        if let p = w.proteinDays, w.loggedDays > 0 { p >= 5 ? wins.append("Protein hit on \(p) days.") : misses.append("Protein hit on \(p) of 7 days.") }
        if let s = w.averageSteps { s >= 7000 ? wins.append("Steps averaged \(Int(s).formatted()).") : misses.append("Steps averaged \(Int(s).formatted()); floor is 7,000.") }
        // One order, for the weakest area.
        let order: String
        if w.gym < 3 { order = "Three gym sessions: Monday, Wednesday, Saturday. Book them now." }
        else if w.nightsKnown > 0 && w.nightsByOne < 5 { order = "Lights out by 1 am, five nights. Phone off the bed at 12:30 am." }
        else if let d = weightDelta, d < 0.5 { order = "Hold 1,700 kcal on weekdays and weigh in daily." }
        else if (w.checkIns.ratio ?? 1) < 0.75 { order = "Close the day before bed: every check-in logged." }
        else { order = "Same again. Hold the line." }
        if wins.isEmpty { wins.append("You showed up and opened the file. Start there.") }
        if misses.isEmpty { misses.append("None worth naming.") }
        return DebriefMemo(wins: Array(wins.prefix(4)), misses: Array(misses.prefix(4)), order: order)
    }
}
