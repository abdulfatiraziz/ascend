import Foundation

public enum AssistantCommandType: String, Codable, CaseIterable, Sendable {
    case createGoal = "create_goal", updateGoal = "update_goal"
    case createHabit = "create_habit", updateHabit = "update_habit", archiveHabit = "archive_habit"
    case logCheckIn = "log_checkin", clearCheckIn = "clear_checkin", setRestDay = "set_rest_day"
    case updateCycle = "update_cycle", restartCycle = "restart_cycle", updateRoutine = "update_routine"
    case setMedicine = "set_medicine", archiveMedicine = "archive_medicine"
    case saveNote = "save_note"
}
public struct AssistantCommand: Codable, Equatable, Sendable {
    public var type: AssistantCommandType
    public var id: String?
    public var goalID: String?
    public var reference: String?
    public var title: String?
    public var note: String?
    public var kind: String?
    public var period: String?
    public var day: String?
    public var start: String?
    public var end: String?
    public var weekdays: [Int]?
    public var minimum: Double?
    public var maximum: Double?
    public var unit: String?
    public var value: Double?
    public var completed: Bool?
    public var rest: Bool?
    public var days: Int?
    public var target: Double?
    public var minute: Int?
    public var clearTime: Bool?
    public var clearMinimum: Bool?
    public var clearMaximum: Bool?
    public var wakeMinute: Int?
    public var bedMinute: Int?
    public var morningMinutes: Int?
    public var windDownMinutes: Int?
    public var frequency: String?
    public var interval: Int?
    public var times: [Int]?
    public var amount: String?
    public var food: String?
    public var strength: String?
    public var category: String?
    public var purpose: String?
    public var clearEnd: Bool?
    public var noteKind: String?
    public var items: [String]?
    public init(type: AssistantCommandType) { self.type = type }
}
public struct AssistantReply: Codable, Equatable, Sendable {
    public var message: String
    public var actions: [AssistantCommand]
    public init(message: String, actions: [AssistantCommand]) { self.message = message; self.actions = actions }
}
public struct ProposedChange: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var title: String
    public var before: String
    public var after: String
    public var destructive: Bool = false
}
public struct PreparedProposal: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let baseline: TrackerDocument
    public let candidate: TrackerDocument
    public let day: String
    public let changes: [ProposedChange]
    public var isDestructive: Bool { changes.contains { $0.destructive } }
    public func resolve(current: TrackerDocument, today: String) throws -> TrackerDocument {
        guard current == baseline, today == day else {
            throw ValidationError(message: "Your plan or date changed since this preview. Ask Ascend again to create a fresh proposal.")
        }
        try candidate.validate()
        return candidate
    }
}
public enum AssistantPlanner {
    public static let maxActions = 20, maxMessageLength = 20_000
    /// `chat` links notes saved by `save_note` back to the conversation.
    public static func prepare(_ reply: AssistantReply, document: TrackerDocument, today: String, chat: UUID? = nil) throws -> PreparedProposal {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ValidationError(message: message) }
        }
        try document.validate()
        try require(TrackerEngine(document: document).date(today) != nil, "Invalid current date.")
        try require(reply.actions.count <= maxActions && reply.message.count <= maxMessageLength, "That proposal is too large. Ask for fewer changes at once.")
        var doc = document
        var references: [String: UUID] = [:]
        var changes: [ProposedChange] = []
        func name(_ value: String?) throws -> String {
            let result = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            try require(!result.isEmpty && result.count <= 120, "Names must contain 1–120 characters.")
            return result
        }
        func goalID(_ value: String?) throws -> UUID {
            guard let value, let id = references[value] ?? UUID(uuidString: value), doc.goals.contains(where: { $0.id == id }) else {
                throw ValidationError(message: "The proposed goal does not exist. Nothing has been changed.")
            }
            return id
        }
        func habitIndex(_ value: String?) throws -> Int {
            guard let value, let id = UUID(uuidString: value), let i = doc.habits.firstIndex(where: { $0.id == id }), doc.habits[i].archivedDay == nil else {
                throw ValidationError(message: "The proposed habit is missing or archived. Nothing has been changed.")
            }
            return i
        }
        func date(_ value: String?) throws -> String {
            guard let value, TrackerEngine(document: doc).date(value) != nil else { throw ValidationError(message: "A proposed date is missing or invalid.") }
            return value
        }
        func target(_ r: HabitRevision) -> String { r.target?.label ?? r.schedule.label }
        func detail(_ r: HabitRevision) -> String {
            let time = r.scheduledMinute.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "Anytime"
            return "\(target(r)) · \(r.period.rawValue) · \(time)"
        }
        for action in reply.actions {
            let beforeAction = doc, previewStart = changes.count
            switch action.type {
            case .createGoal:
                let title = try name(action.title), start = try date(action.start ?? doc.cycle.start), end = try date(action.end ?? doc.cycle.end)
                let goal = Goal(title: title, windows: [GoalWindow(effectiveDay: today, start: start, end: end)])
                if let ref = action.reference {
                    try require(!ref.isEmpty && references[ref] == nil && UUID(uuidString: ref) == nil, "A new goal reference must be unique and distinct from existing IDs.")
                    references[ref] = goal.id
                }
                doc.goals.append(goal)
                changes.append(ProposedChange(title: "Create goal: \(title)", before: "No goal", after: "\(start) → \(end)"))
            case .updateGoal:
                let id = try goalID(action.id), i = doc.goals.firstIndex { $0.id == id }!, old = doc.goals[i]
                let title = try name(action.title ?? old.title), start = try date(action.start ?? old.latest.start), end = try date(action.end ?? old.latest.end)
                doc.goals[i].title = title
                if start != old.latest.start || end != old.latest.end { doc.goals[i].revise(GoalWindow(effectiveDay: today, start: start, end: end)) }
                changes.append(ProposedChange(title: "Update goal: \(title)", before: "\(old.title) · \(old.latest.start) → \(old.latest.end)", after: "\(title) · \(start) → \(end); applies from \(today)"))
            case .createHabit, .updateHabit:
                let existing = action.type == .updateHabit ? try habitIndex(action.id) : nil
                let old = existing.map { doc.habits[$0] }
                let goal = try goalID(action.goalID ?? old?.goalID.uuidString)
                let kind: HabitKind
                switch action.kind ?? old.map({ $0.kind == .metric ? "metric" : $0.kind == .milestone ? "milestone" : "check" }) ?? "check" {
                case "check": kind = .check
                case "metric": kind = .metric
                case "milestone": kind = .milestone
                default: throw ValidationError(message: "Unknown habit type.")
                }
                if let old { try require(old.goalID == goal && old.kind == kind, "A habit’s goal and type are fixed to preserve history. Create a new habit for that change.") }
                var r = old?.latest ?? HabitRevision(effectiveDay: today, title: "", period: .daytime)
                r.effectiveDay = today; r.title = try name(action.title ?? old?.latest.title)
                if let note = action.note { try require(note.count <= 1000, "Habit notes must be 1,000 characters or fewer."); r.note = note }
                if let period = action.period {
                    guard let p = Period(rawValue: period) else { throw ValidationError(message: "Unknown time of day.") }; r.period = p
                }
                if kind == .milestone {
                    let due = try date(action.day ?? old?.latest.schedule.once)
                    try require(due >= today, "New milestone due dates must be today or later.")
                    r.schedule = Schedule(weekdays: [], once: due)
                } else if let weekdays = action.weekdays { r.schedule = Schedule(weekdays: Array(Set(weekdays)).sorted()) }
                if kind == .metric {
                    r.target = MetricTarget(minimum: action.clearMinimum == true ? nil : action.minimum ?? r.target?.minimum, maximum: action.clearMaximum == true ? nil : action.maximum ?? r.target?.maximum, unit: action.unit ?? r.target?.unit ?? "")
                }
                if action.clearTime == true { r.scheduledMinute = nil }
                else if let minute = action.minute { r.scheduledMinute = minute }
                if let i = existing {
                    var comparison = r; comparison.effectiveDay = doc.habits[i].latest.effectiveDay
                    if comparison != doc.habits[i].latest { doc.habits[i].revise(r) }
                }
                else { doc.habits.append(Habit(goalID: goal, kind: kind, createdDay: today, revisions: [r])) }
                changes.append(ProposedChange(title: "\(old == nil ? "Create" : "Update") habit: \(r.title)", before: old.map { detail($0.latest) } ?? "No habit", after: "\(detail(r)); applies from \(today)"))
            case .archiveHabit:
                let i = try habitIndex(action.id)
                let title = doc.habits[i].latest.title
                doc.habits[i].archivedDay = today
                changes.append(ProposedChange(title: "Archive: \(title)", before: "Active habit", after: "Archived from \(today). Earlier records remain.", destructive: true))
            case .logCheckIn, .clearCheckIn:
                let i = try habitIndex(action.id), habit = doc.habits[i], day = try date(action.day)
                let e = TrackerEngine(document: doc)
                try require(day <= today && (e.isDue(habit, on: day) || e.entry(for: habit, day: day) != nil), "Check-ins must be for a scheduled past or current date.")
                try require(!doc.restDays.contains(day) || habit.kind == .milestone, "Resume this rest day before logging recurring habits.")
                let previous = e.entry(for: habit, day: day)
                let before = previous?.value.map { $0.pretty } ?? (previous?.completed == true ? "Complete" : "Not logged")
                let after: String
                if action.type == .clearCheckIn {
                    doc.checkIns.removeAll { $0.habitID == habit.id && $0.day == day }; after = "Entry cleared"
                } else if habit.kind == .metric {
                    guard let value = action.value, value.isFinite, value >= 0 else { throw ValidationError(message: "A numeric check-in needs a finite value of zero or more.") }
                    doc.setEntry(CheckIn(habitID: habit.id, day: day, value: value))
                    after = "\(value.pretty) \(habit.revision(on: day)?.target?.unit ?? "")"
                } else {
                    let done = action.completed ?? true
                    doc.setEntry(CheckIn(habitID: habit.id, day: day, completed: done)); after = done ? "Complete" : "Unchecked"
                }
                changes.append(ProposedChange(title: "\(habit.revision(on: day)!.title) · \(day)", before: before, after: after, destructive: action.type == .clearCheckIn))
            case .setRestDay:
                let day = try date(action.day)
                try require(day <= today && action.rest != nil, "Rest-day changes need a past/current date and a rest value.")
                let wasRest = doc.restDays.contains(day)
                if action.rest == true { doc.restDays.insert(day) } else { doc.restDays.remove(day) }
                changes.append(ProposedChange(title: "\(day)", before: wasRest ? "Rest day" : "Active day", after: action.rest == true ? "Rest day; existing values preserved" : "Active day; recurring tasks count again"))
            case .updateCycle:
                let old = doc.cycle
                doc.cycle = Cycle(title: try name(action.title ?? old.title), start: try date(action.start ?? old.start), end: try date(action.end ?? old.end), target: action.target ?? old.target)
                for i in doc.goals.indices where doc.goals[i].latest.start == old.start && doc.goals[i].latest.end == old.end {
                    if doc.cycle.start != old.start || doc.cycle.end != old.end { doc.goals[i].revise(GoalWindow(effectiveDay: today, start: doc.cycle.start, end: doc.cycle.end)) }
                }
                changes.append(ProposedChange(title: "Update cycle", before: "\(old.title) · \(old.start) → \(old.end) · \(Int(old.target * 100))%", after: "\(doc.cycle.title) · \(doc.cycle.start) → \(doc.cycle.end) · \((doc.cycle.target * 100).pretty)%"))
            case .restartCycle:
                guard let days = action.days, [84,90].contains(days) else { throw ValidationError(message: "Restart length must be 84 or 90 days.") }
                let old = doc.cycle
                doc.restart(on: today, length: days)
                changes.append(ProposedChange(title: "Start a fresh \(days)-day cycle", before: "\(old.start) → \(old.end)", after: "\(today) → \(doc.cycle.end). Today’s check-ins clear; all goal windows restart and milestone due dates move. Earlier records stay in Calendar.", destructive: true))
            case .updateRoutine:
                let old = doc.routine
                var r = old; r.configured = true
                r.wakeMinute = action.wakeMinute ?? r.wakeMinute; r.bedMinute = action.bedMinute ?? r.bedMinute
                r.morningMinutes = action.morningMinutes ?? r.morningMinutes; r.windDownMinutes = action.windDownMinutes ?? r.windDownMinutes
                try r.validate(); doc.routine = r
                changes.append(ProposedChange(title: "Update routine clock", before: old.configured ? "Wake \(clockTime(old.wakeMinute)), bed \(clockTime(old.bedMinute))" : "Not configured", after: "Wake \(clockTime(r.wakeMinute)), bed \(clockTime(r.bedMinute)), wind-down \(r.windDownMinutes) min"))
            case .setMedicine:
                // Records the schedule the user states. Matches an existing medicine by ID, then by name; otherwise adds one.
                let named = action.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let index = action.id.flatMap(UUID.init(uuidString:)).flatMap { id in doc.meds.medicines.firstIndex { $0.id == id && !$0.archived } }
                    ?? named.flatMap { n in doc.meds.medicines.firstIndex { !$0.archived && $0.name.caseInsensitiveCompare(n) == .orderedSame } }
                if action.id != nil && index == nil { throw ValidationError(message: "The proposed medicine is missing or archived. Nothing has been changed.") }
                let old = index.map { doc.meds.medicines[$0] }
                var m: Medicine
                // A title renames only a medicine picked by ID; when it matched by name, the stored spelling stays.
                if let old { m = old; if let named, action.id != nil { m.name = try name(named) } } else { m = Medicine(name: try name(named)) }
                for (value, keyPath, limit) in [(action.strength, \Medicine.strength, 120), (action.category, \.category, 120), (action.purpose, \.purpose, 300), (action.note, \.notes, 1000)] {
                    guard let value else { continue }
                    try require(value.count <= limit, "A medicine field is too long."); m[keyPath: keyPath] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let scheduling = action.frequency != nil || action.times != nil || action.weekdays != nil || action.interval != nil || action.amount != nil
                    || action.food != nil || action.start != nil || action.end != nil || action.clearEnd == true
                if scheduling {
                    var s = m.schedule ?? MedSchedule(start: today)
                    if let value = action.frequency { guard let f = MedFrequency(rawValue: value) else { throw ValidationError(message: "Unknown medicine frequency.") }; s.frequency = f }
                    if let value = action.food { guard let f = MedFood(rawValue: value) else { throw ValidationError(message: "Unknown food timing.") }; s.food = f }
                    if let times = action.times { s.times = Array(Set(times)).sorted() }
                    if let weekdays = action.weekdays { s.weekdays = Array(Set(weekdays)).sorted() }
                    if let interval = action.interval { s.interval = interval }
                    if let amount = action.amount { s.amount = amount.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let start = action.start { s.start = try date(start) }
                    if action.clearEnd == true { s.end = nil } else if let end = action.end { s.end = try date(end) }
                    try s.validate(engine: TrackerEngine(document: doc)); m.schedule = s
                }
                m.confirmed = true
                if let index { doc.meds.medicines[index] = m } else { doc.meds.medicines.append(m) }
                changes.append(ProposedChange(title: "\(old == nil ? "Add" : "Update") medicine: \(m.title)",
                    before: old.map { $0.schedule?.summary ?? "No schedule" } ?? "Not in your list",
                    after: [m.schedule?.summary ?? "No schedule", m.category].filter { !$0.isEmpty }.joined(separator: " · ")))
            case .saveNote:
                guard let kind = NoteKind(rawValue: action.noteKind ?? "") else { throw ValidationError(message: "A note needs a type: journal, plan, decision or insight.") }
                let draft = NoteDraft(kind: kind.rawValue, title: try name(action.title), body: action.note ?? "", actions: action.items ?? [])
                try require((action.note ?? "").count <= JournalNote.maxBody && (action.items ?? []).count <= JournalNote.maxActions, "That note is too long to save.")
                let note = draft.note(day: today, chatID: chat)
                doc.notes.notes.append(note)
                changes.append(ProposedChange(title: "Save \(kind.label.lowercased()) note: \(note.title)", before: "Not saved",
                    after: "\(note.body.split(whereSeparator: \.isNewline).count) lines\(note.actions.isEmpty ? "" : ", \(note.actions.count) action items")\(note.shareWithClaude ? "; Ascend can refer to it in later chats" : "; private to you")"))
            case .archiveMedicine:
                guard let id = action.id.flatMap(UUID.init(uuidString:)), let i = doc.meds.medicines.firstIndex(where: { $0.id == id && !$0.archived }) else {
                    throw ValidationError(message: "The proposed medicine is missing or archived. Nothing has been changed.")
                }
                doc.meds.medicines[i].archived = true
                changes.append(ProposedChange(title: "Stop: \(doc.meds.medicines[i].title)", before: doc.meds.medicines[i].schedule?.summary ?? "No schedule", after: "Archived; no more reminders. Past doses remain.", destructive: true))
            }
            if doc == beforeAction { changes.removeSubrange(previewStart..<changes.count) }
        }
        try doc.validate()
        return PreparedProposal(baseline: document, candidate: doc, day: today, changes: changes)
    }
}
public func clockTime(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
