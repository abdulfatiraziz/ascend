import Foundation

public enum MuscleRegion: String, Codable, CaseIterable, Sendable {
  case chest = "CHEST"
  case frontDeltoids = "FRONT_DELTOIDS"
  case backDeltoids = "BACK_DELTOIDS"
  case triceps = "TRICEPS"
  case biceps = "BICEPS"
  case forearm = "FOREARM"
  case upperBack = "UPPER_BACK"
  case lowerBack = "LOWER_BACK"
  case trapezius = "TRAPEZIUS"
  case abs = "ABS"
  case obliques = "OBLIQUES"
  case quadriceps = "QUADRICEPS"
  case hamstring = "HAMSTRING"
  case gluteal = "GLUTEAL"
  case calves = "CALVES"
  case adductor = "ADDUCTOR"
  case abductors = "ABDUCTORS"
  public var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}
public enum PriorityMuscle: String, Codable, CaseIterable, Sendable {
  case upperChest = "Upper chest"
  case sideDelts = "Side delts"
  case upperBack = "Upper back"
  case rearDelts = "Rear delts"
  case quads = "Quads"
  case hamstrings = "Hamstrings"
}
public struct PriorityVolume: Identifiable, Sendable {
  public var muscle: PriorityMuscle
  public var planned: Int
  public var logged: Int
  public var minimum: Int
  public var id: String { muscle.rawValue }
}
public struct CoachRules: Codable, Equatable, Sendable {
  public var stepsEnabled = true
  public var stepsFloor = 7000
  public var nudgeMinute = 1080
  public var volumeWarnings = true
  public var priorityMinimum = 6
  public var priorities = PriorityMuscle.allCases
  public var progressionEnabled = true
  public var stallWeeks = 4
  public var lateEnabled = true
  public var lateMinute = 1230
  public var calorieCaution = true
  public var walkingPadRule = true
  public var walkingHR = 110.0
  public init() {}
}
public struct TrainingExercise: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var name = "New exercise"
  public var muscles: [MuscleRegion] = []
  public var equipment = "Machine"
  public var sets = 3
  public var minReps = 8
  public var maxReps = 12
  public var startingWeight = 0.0
  public var assisted = false
  public var compound = false
  public var priorityTags: [PriorityMuscle] = []
  public var timed = false
  public var animationID: String?
  public init() {}
}
public enum TrainingKind: String, Codable, CaseIterable, Sendable { case strength, cardio, rest }
public struct TrainingSession: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var weekday = 2
  public var name = "Strength"
  public var kind = TrainingKind.strength
  public var exercises: [UUID] = []
  public var supersets: [[UUID]] = []
  public var restSeconds = 90
  public var cardioType = "Incline treadmill"
  public var minutes = 30.0
  public var incline = 0.0
  public var speed = 0.0
  public init() {}
}
public struct TrainingSet: Codable, Equatable, Sendable {
  public var weight: Double
  public var reps: Int
  public var rpe: Double?
  public var hard: Bool
  public init(weight: Double, reps: Int, rpe: Double? = nil, hard: Bool = true) {
    self.weight = weight
    self.reps = reps
    self.rpe = rpe
    self.hard = hard
  }
  public var volume: Double { weight * Double(reps) }
  public var epley: Double { weight * (1 + Double(reps) / 30) }
}
public struct LiftLog: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var exerciseID: UUID
  public var date: Date
  public var sets: [TrainingSet]
  public var muscles: [MuscleRegion]
  public var priorityTags: [PriorityMuscle]
  public init(
    exerciseID: UUID, date: Date, sets: [TrainingSet], muscles: [MuscleRegion],
    priorityTags: [PriorityMuscle] = []
  ) {
    self.exerciseID = exerciseID
    self.date = date
    self.sets = sets
    self.muscles = muscles
    self.priorityTags = priorityTags
  }
}
public enum SessionOutcome: String, Codable, CaseIterable, Sendable { case done, rest, skipped }
public struct TrainingCompletion: Codable, Equatable, Identifiable, Sendable {
  public var id = UUID()
  public var sessionID: UUID?
  public var date: Date
  public var outcome: SessionOutcome
  public var kind: TrainingKind
  public var minutes: Double
  public init(
    sessionID: UUID?, date: Date, outcome: SessionOutcome, kind: TrainingKind, minutes: Double = 0
  ) {
    self.sessionID = sessionID
    self.date = date
    self.outcome = outcome
    self.kind = kind
    self.minutes = minutes
  }
}
public struct TrainingArchive: Codable, Equatable, Sendable {
  public var version = 1
  public var exercises: [TrainingExercise] = []
  public var plan: [TrainingSession] = []
  public var logs: [LiftLog] = []
  public var completions: [TrainingCompletion] = []
  public var stepBlocks = StepBlock.defaults
  public var stepChecks: [String: [UUID]] = [:]
  public var railsHintEnabled = true
  public var railsStepsPerMinute = 60.0
  public var goal = BodyGoal()
  public var weekOne: Date
  public var age: Int?
  public var heightCM: Double?
  public var maintenanceSex: MaintenanceSex?
  public var completedNutritionDays: [String]?
  public var rules = CoachRules()
  public init(now: Date = Date(), calendar: Calendar = Calendar.current) {
    var c = calendar
    c.firstWeekday = 2
    weekOne = c.dateInterval(of: .weekOfYear, for: now)!.start
  }
  public func validate() throws {
    func dateOK(_ d: Date) -> Bool {
      d.timeIntervalSince1970.isFinite
        && (946_684_800...7_289_654_399).contains(d.timeIntervalSince1970)
    }
    func fatOK(_ x: Double) -> Bool { x.isFinite && (3...60).contains(x) }
    func weightOK(_ x: Double) -> Bool { x.isFinite && (20...500).contains(x) }
    guard version == 1, exercises.count <= 1000, plan.count <= 7, logs.count <= 100_000,
      completions.count <= 30_000,
      Set(exercises.map(\.id)).count == exercises.count, Set(plan.map(\.id)).count == plan.count,
      Set(plan.map(\.weekday)).count == plan.count,
      Set(logs.map(\.id)).count == logs.count,
      Set(completions.map(\.id)).count == completions.count, dateOK(weekOne),
      age.map({ (16...110).contains($0) }) ?? true,
      goal.targetFat.map(fatOK) ?? true, goal.targetWeight.map(weightOK) ?? true,
      goal.targetDate.map(dateOK) ?? true,
      goal.checkpoints.count <= 20, Set(goal.checkpoints.map(\.id)).count == goal.checkpoints.count,
      goal.checkpoints.allSatisfy({
        fatOK($0.targetFat) && ($0.targetWeight.map(weightOK) ?? true) && dateOK($0.date)
      }),
      (1000...50000).contains(rules.stepsFloor), (0...1439).contains(rules.nudgeMinute),
      (0...1439).contains(rules.lateMinute), (2...26).contains(rules.stallWeeks),
      rules.walkingHR.isFinite, (60...180).contains(rules.walkingHR)
    else { throw ValidationError(message: "Invalid training settings. The file was preserved.") }
    guard stepBlocks.count <= 50, Set(stepBlocks.map(\.id)).count == stepBlocks.count,
      stepBlocks.allSatisfy({
        !$0.title.isEmpty && $0.title.count <= 120 && (0...30000).contains($0.steps)
          && (0...180).contains($0.minutes)
      }), stepChecks.count <= 5000,
      stepChecks.allSatisfy({ $0.key.count == 10 && $0.value.count <= 50 }),
      railsStepsPerMinute.isFinite, (10...150).contains(railsStepsPerMinute)
    else { throw ValidationError(message: "Invalid step plan.") }
    guard (1...30).contains(rules.priorityMinimum),
      Set(rules.priorities).count == rules.priorities.count
    else { throw ValidationError(message: "Invalid priority-muscle settings.") }
    guard heightCM.map({ $0.isFinite && (100...250).contains($0) }) ?? true,
      (completedNutritionDays?.count ?? 0) <= 5000,
      completedNutritionDays?.allSatisfy(BodyMaintenanceReport.validDay) ?? true,
      Set(completedNutritionDays ?? []).count == (completedNutritionDays?.count ?? 0)
    else { throw ValidationError(message: "Invalid maintenance settings.") }
    let ids = Set(exercises.map(\.id))
    for e in exercises {
      guard !e.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, e.name.count <= 120,
        e.equipment.count <= 80, (1...20).contains(e.sets), (1...100).contains(e.minReps),
        e.maxReps >= e.minReps, e.maxReps <= 100, e.startingWeight.isFinite,
        (0...1000).contains(e.startingWeight), Set(e.muscles).count == e.muscles.count,
        Set(e.priorityTags).count == e.priorityTags.count, (e.animationID?.count ?? 0) <= 120
      else { throw ValidationError(message: "Check exercise name, sets, reps and weight.") }
    }
    for s in plan {
      guard (1...7).contains(s.weekday), !s.name.isEmpty, s.name.count <= 120,
        s.cardioType.count <= 120, s.exercises.count <= 50,
        Set(s.exercises).count == s.exercises.count, Set(s.exercises).isSubset(of: ids),
        s.supersets.count <= 25,
        s.supersets.allSatisfy({
          $0.count == 2 && Set($0).count == 2 && Set($0).isSubset(of: Set(s.exercises))
        }), Set(s.supersets.flatMap { $0 }).count == s.supersets.flatMap { $0 }.count,
        (0...600).contains(s.restSeconds),
        s.minutes.isFinite, (0...600).contains(s.minutes), s.incline.isFinite,
        (0...40).contains(s.incline), s.speed.isFinite, (0...50).contains(s.speed)
      else { throw ValidationError(message: "Invalid weekly session.") }
    }
    for l in logs {
      guard ids.contains(l.exerciseID), dateOK(l.date), !l.sets.isEmpty, l.sets.count <= 30,
        Set(l.muscles).count == l.muscles.count, Set(l.priorityTags).count == l.priorityTags.count,
        l.sets.allSatisfy({
          $0.weight.isFinite && (0...1000).contains($0.weight) && (1...100).contains($0.reps)
            && ($0.rpe.map { $0.isFinite && (1...10).contains($0) } ?? true)
        })
      else { throw ValidationError(message: "Check set weight, reps, RPE and exercise.") }
    }
    for c in completions {
      guard dateOK(c.date), c.minutes.isFinite, (0...600).contains(c.minutes) else {
        throw ValidationError(message: "Invalid session completion.")
      }
    }
  }
  public func lastLog(_ exercise: UUID, before date: Date) -> LiftLog? {
    logs.filter { $0.exerciseID == exercise && $0.date < date }.max { $0.date < $1.date }
  }
  public func today(_ date: Date, calendar: Calendar) -> TrainingSession? {
    plan.first { $0.weekday == calendar.component(.weekday, from: date) }
  }
  public func muscleVolume(from start: Date, to end: Date) -> [MuscleRegion: Int] {
    var result: [MuscleRegion: Int] = [:]
    for l in logs where l.date >= start && l.date < end {
      for m in Set(l.muscles) { result[m, default: 0] += l.sets.filter(\.hard).count }
    }
    return result
  }
  public func stalled(_ e: TrainingExercise, now: Date) -> Bool {
    let recent = logs.filter { $0.exerciseID == e.id && $0.date <= now }.sorted {
      $0.date < $1.date
    }
    guard let last = recent.last, let first = recent.first,
      now.timeIntervalSince(last.date) < 14 * 86400,
      last.date.timeIntervalSince(first.date) >= Double(rules.stallWeeks) * 604800
    else { return false }
    let cutoff = last.date.addingTimeInterval(-Double(rules.stallWeeks) * 604800)
    func score(_ l: LiftLog) -> Double {
      l.sets.map {
        e.timed ? Double($0.reps) : (e.assisted ? -$0.weight + Double($0.reps) * 0.01 : $0.epley)
      }.max() ?? 0
    }
    guard let baseline = recent.last(where: { $0.date <= cutoff }) else { return false }
    return !recent.filter { $0.date > baseline.date }.contains {
      score($0) > score(baseline) + 0.001
    }
  }
  public func priorityVolume(now: Date, calendar: Calendar) -> [PriorityVolume] {
    guard rules.volumeWarnings, !plan.isEmpty else { return [] }
    var c = calendar
    c.firstWeekday = 2
    let week = c.dateInterval(of: .weekOfYear, for: now)!
    var planned: [PriorityMuscle: Int] = [:]
    var logged: [PriorityMuscle: Int] = [:]
    for session in plan where session.kind == .strength {
      for id in session.exercises {
        if let e = exercises.first(where: { $0.id == id }) {
          for m in Set(e.priorityTags) { planned[m, default: 0] += e.sets }
        }
      }
    }
    for log in logs where log.date >= week.start && log.date <= now {
      for m in Set(log.priorityTags) { logged[m, default: 0] += log.sets.filter(\.hard).count }
    }
    return rules.priorities.map {
      .init(
        muscle: $0, planned: planned[$0] ?? 0, logged: logged[$0] ?? 0,
        minimum: rules.priorityMinimum)
    }
  }
  public func walkNudge(steps: Double?, now: Date, mealTimes: [Date], calendar: Calendar) -> String?
  {
    guard rules.stepsEnabled, let steps, steps < Double(rules.stepsFloor),
      calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        >= rules.nudgeMinute
    else { return nil }
    let justAte = mealTimes.contains { $0 <= now && now.timeIntervalSince($0) <= 1800 }
    return justAte
      ? "10–20 min walk now, within 30 min of your meal" : "10–20 min walk after your next meal"
  }
}
public enum TrainingStorage {
  public static func read(_ url: URL) throws -> TrainingArchive {
    guard FileManager.default.fileExists(atPath: url.path) else { return TrainingArchive() }
    let data = try Data(contentsOf: url)
    guard data.count <= 30_000_000 else {
      throw ValidationError(message: "Training file is too large.")
    }
    let a = try JSONDecoder().decode(TrainingArchive.self, from: data)
    try a.validate()
    return a
  }
  public static func save(_ a: TrainingArchive, to url: URL) throws {
    _ = try read(url)
    try a.validate()
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    let bytes = try e.encode(a)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
public enum TrainingProgression {
  public static func hint(_ e: TrainingExercise, last: LiftLog?) -> String {
    if e.timed {
      return last == nil ? "Start with \(e.minReps)–\(e.maxReps) s holds" : "+5 s when comfortable"
    }
    guard let last, !last.sets.isEmpty else {
      guard e.startingWeight > 0 else {
        return "First time: pick a weight you can do for \(e.minReps) clean reps"
      }
      let kg = e.startingWeight == e.startingWeight.rounded()
        ? String(Int(e.startingWeight)) : String(format: "%g", e.startingWeight)
      return "Start at \(kg) kg\(e.assisted ? " assist" : "") · \(e.minReps)–\(e.maxReps) reps"
    }
    guard last.sets.count >= e.sets, last.sets.allSatisfy({ $0.reps >= e.maxReps }) else {
      return "+1 rep next time, within your range"
    }
    if e.assisted { return "−2 kg assistance next time (minimum 0 kg)" }
    return e.equipment.lowercased().contains("dumbbell")
      && (last.sets.map(\.weight).max() ?? 0) <= 10 ? "+1 kg next time" : "+2.5 kg next time"
  }
}
public struct TrainingWorkout: Identifiable, Sendable {
  public var id: String
  public var start: Date
  public var end: Date
  public var title: String
  public var kind: TrainingKind?
  public var session: String?
  public var averageHR: Double?
  public var maxHR: Double?
  public var distance: Double?
  public var calories: Double?
  public var intensity: String
  public var late: Bool
  public var minutes: Double { end.timeIntervalSince(start) / 60 }
}
public struct TrainingScorecard: Sendable {
  public var strength = 0
  public var cardio = 0
  public var walkingDays = 0
  public var longCardio = 0
  public var workouts: [TrainingWorkout] = []
  /// Android platform ExerciseSessionType codes used by Bridge (not AndroidX constants).
  public static func workoutType(_ detail: String) -> (String, TrainingKind?) {
    let code = Int(detail.replacingOccurrences(of: "Exercise type ", with: ""))
    switch code {
    case 45, 55: return ("Strength training", .strength)
    case 33: return ("Running", .cardio)
    case 34: return ("Treadmill", .cardio)
    case 53: return ("Walking", .cardio)
    case 4, 5: return ("Cycling", .cardio)
    case 48, 49: return ("Swimming", .cardio)
    case 60: return ("Elliptical", .cardio)
    case 57: return ("Yoga", nil)
    default:
      return (code.map { "Exercise type \($0)" } ?? (detail.isEmpty ? "Workout" : detail), nil)
    }
  }

  public static func build(
    training a: TrainingArchive, health: HealthArchive, now: Date, calendar: Calendar
  ) -> Self {
    var c = calendar
    c.firstWeekday = 2
    let week = c.dateInterval(of: .weekOfYear, for: now)!
    let end = min(week.end, now.addingTimeInterval(1))
    var r = Self()
    var strength = Set<Date>()
    var cardio = Set<Date>()
    var long = Set<Date>()
    for w in health.records.filter({
      $0.metric == .workout && $0.start >= week.start.timeIntervalSince1970
        && $0.start < end.timeIntervalSince1970 && $0.end <= now.timeIntervalSince1970
    }).sorted(by: { $0.start < $1.start }) {
      let start = Date(timeIntervalSince1970: w.start)
      let finish = Date(timeIntervalSince1970: w.end)
      let day = c.startOfDay(for: start)
      let (title, rawKind) = workoutType(w.detail)
      let planned = a.today(start, calendar: c)
      let heart = health.records.filter {
        $0.metric == .heartRate && $0.start >= w.start && $0.end <= w.end
      }
      let n = heart.map(\.weight).reduce(0, +)
      let avg = n > 0 ? heart.map { $0.value * Double($0.weight) }.reduce(0, +) / Double(n) : nil
      let ratio = a.age.flatMap { age in avg.map { $0 / (208 - 0.7 * Double(age)) } }
      let intensity =
        ratio.map { $0 >= 0.77 ? "Hard" : $0 >= 0.64 ? "Moderate" : "Low" } ?? "Intensity unknown"
      // Health Connect type 33 does not encode incline. Use an explicit planned walking-pad label,
      // and retain unknown HR as unknown rather than assuming it meets a cardio target.
      let pad =
        planned?.cardioType.lowercased().contains("walking pad") == true && planned?.incline == 0
      let walkingType = ["Exercise type 53", "Exercise type 34"].contains(w.detail)
      let walkingOnly =
        a.rules.walkingPadRule && walkingType && pad && (avg.map { $0 < a.rules.walkingHR } ?? true)
      let kind = walkingOnly ? nil : rawKind
      let minute = c.component(.hour, from: finish) * 60 + c.component(.minute, from: finish)
      func sum(_ metric: HealthMetric) -> Double? {
        let rows = health.records.filter {
          $0.metric == metric && $0.start >= w.start && $0.end <= w.end
        }
        return rows.isEmpty ? nil : rows.map(\.value).reduce(0, +)
      }
      let item = TrainingWorkout(
        id: w.id, start: start, end: finish,
        title: walkingOnly ? "Walking pad · walking only" : title, kind: kind,
        session: planned.flatMap { $0.kind == rawKind ? $0.name : nil }, averageHR: avg,
        maxHR: heart.map(\.highest).max(), distance: sum(.distance), calories: sum(.activeEnergy),
        intensity: intensity,
        late: a.rules.lateEnabled && w.detail != "Exercise type 53" && !walkingOnly
          && intensity == "Hard" && minute > a.rules.lateMinute)
      r.workouts.append(item)
      if kind == .strength { strength.insert(day) }
      if kind == .cardio {
        cardio.insert(day)
        if item.minutes >= 45 && item.minutes <= 75 && intensity == "Low" { long.insert(day) }
      }
    }
    for item in a.completions
    where item.date >= week.start && item.date < end && item.outcome == .done {
      let day = c.startOfDay(for: item.date)
      if item.kind == .strength { strength.insert(day) }
      if item.kind == .cardio {
        let p = a.plan.first { $0.id == item.sessionID }
        if !(a.rules.walkingPadRule && p?.cardioType.lowercased().contains("walking pad") == true
          && p?.incline == 0)
        {
          cardio.insert(day)
        }
      }
    }
    r.strength = strength.count
    r.cardio = cardio.count
    r.longCardio = long.count
    var steps: [Date: Double] = [:]
    for item in health.records
    where item.metric == .steps && item.start >= week.start.timeIntervalSince1970
      && item.start < end.timeIntervalSince1970
    { steps[c.startOfDay(for: Date(timeIntervalSince1970: item.start)), default: 0] += item.value }
    r.walkingDays = steps.values.filter { $0 >= Double(a.rules.stepsFloor) }.count
    return r
  }
}
