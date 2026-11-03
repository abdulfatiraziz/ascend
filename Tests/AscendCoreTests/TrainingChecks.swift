import AscendCore
import Foundation

func runTrainingChecks() -> (count: Int, failures: Int) {
  var count = 0
  var failures = 0
  struct Failed: Error {}
  func expect(_ condition: Bool) throws { if !condition { throw Failed() } }
  func rejects(_ action: () throws -> Void) throws {
    do { try action() } catch { return }
    throw Failed()
  }
  func check(_ name: String, _ test: () throws -> Void) {
    count += 1
    do {
      try test()
      print("PASS: \(name)")
    } catch {
      failures += 1
      print("FAIL: \(name): \(error)")
    }
  }
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(secondsFromGMT: 0)!
  cal.firstWeekday = 2
  let now = ISO8601DateFormatter().date(from: "2026-09-25T22:00:00Z")!
  func date(_ days: Int, _ hour: Int = 12) -> Date {
    cal.date(
      byAdding: .hour, value: hour,
      to: cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now))!)!
  }
  func scale(_ id: String, _ when: Date, _ weight: Double, _ fat: Double = 24) -> BodyMeasurement {
    .init(fields: [
      "id": .text(id), "userId": .text("fictional-profile"),
      "createdAt": .number(when.timeIntervalSince1970 * 1000), "measuredWeight": .number(weight),
      "bodyFatPercentage": .number(fat),
    ])
  }
  func workout(_ id: String, _ when: Date, _ minutes: Double, _ code: Int) -> HealthRecord {
    .init(
      id: id, metric: .workout, start: when.timeIntervalSince1970,
      end: when.timeIntervalSince1970 + minutes * 60, value: minutes,
      detail: "Exercise type \(code)")
  }
  check("goal uses scale lean mass and weekly averages for pace/projection") {
    let rows = (0..<4).map { scale("sample-\($0)", date(-21 + $0 * 7), 90 - Double($0)) }
    let r = BodyGoalReport.build(
      records: rows, goal: .init(targetFat: 20, targetDate: date(60)), now: now, calendar: cal)
    try expect(abs(r.leanMass! - 87 * 0.76) < 0.001 && abs(r.goalWeight! - 87 * 0.76 / 0.8) < 0.001)
    try expect(abs(r.actualLossPerWeek! - 1) < 0.001 && r.projectedDate != nil)
    let noisy = rows + [scale("noise-a", date(-13), 87), scale("noise-b", date(-12), 91)]
    let weekly = BodyGoalReport.build(records: noisy, goal: .init(), now: now, calendar: cal).weekly
    try expect(weekly.count == 4)
  }
  check("aggressive deadline and stale/flat data do not invent a projection") {
    let rows = [scale("a", date(-21), 92), scale("b", date(-14), 92), scale("c", date(-7), 92)]
    let r = BodyGoalReport.build(
      records: rows, goal: .init(targetDate: date(7), targetWeight: 80), now: now, calendar: cal)
    try expect(r.aggressive && r.projectedDate == nil && r.earliestDate! > date(7))
    let sparse = BodyGoalReport.build(
      records: [rows[0]], goal: .init(targetWeight: 85), now: now, calendar: cal)
    try expect(sparse.actualLossPerWeek == nil && sparse.stale)
    try expect(BodyGoalReport.weekNumber(date(-8), weekOne: date(-15), calendar: cal) == 2)
  }
  check("normal, small dumbbell, assisted and incomplete progression") {
    var e = TrainingExercise()
    e.equipment = "Dumbbell"
    e.sets = 2
    var l = LiftLog(
      exerciseID: e.id, date: now, sets: Array(repeating: .init(weight: 6, reps: 12), count: 2),
      muscles: [])
    try expect(TrainingProgression.hint(e, last: l).contains("+1 kg"))
    e.equipment = "Machine"
    try expect(TrainingProgression.hint(e, last: l).contains("+2.5"))
    e.assisted = true
    try expect(TrainingProgression.hint(e, last: l).contains("−2"))
    l.sets[0].reps = 9
    try expect(TrainingProgression.hint(e, last: l).contains("+1 rep"))
    l.sets = Array(l.sets.prefix(1))
    try expect(TrainingProgression.hint(e, last: l).contains("+1 rep"))
  }
  check("manual CRUD preserves legacy IDs and cloud merge; scale immutable") {
    var a = try BodyArchive().savingManual(kilograms: 94.12, date: date(-2))
    let id = a.records[0].id
    a = try a.savingManual(id: id, kilograms: 93.98, date: date(-1))
    a = try a.merging([scale("scale", date(0), 93)])
    try expect(a.records.first { $0.id == id }?.kilograms == 93.98 && a.records.count == 2)
    try rejects { _ = try a.savingManual(id: "scale", kilograms: 90, date: now) }
    try rejects { _ = try a.deletingManual("scale") }
    a = try a.deletingManual(id)
    try expect(a.records.count == 1)
    let legacy = BodyMeasurement(fields: [
      "id": .text("manual-whiteboard-2026-08-01"), "userId": .text("local-manual"),
      "createdAt": .number(date(-30).timeIntervalSince1970 * 1000), "measuredWeight": .number(95),
      "isManual": .bool(true),
    ])
    a = try a.merging([legacy])
    try expect(a.records.contains { $0.id == legacy.id })
    try rejects {
      _ = try a.merging([
        BodyMeasurement(fields: [
          "id": .text(legacy.id), "userId": .text("fictional-profile"),
          "createdAt": .number(date(-30).timeIntervalSince1970 * 1000),
          "measuredWeight": .number(90),
        ])
      ])
    }
  }
  check("manual atomic writes reject corrupt files and never edit scale bytes") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = folder.appendingPathComponent("body-measurements.json")
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try BodyArchive().savingManual(kilograms: 91, date: date(0))
    try BodyStorage.saveManual(a, to: url)
    try expect(try BodyStorage.read(url) == a)
    try Data("broken".utf8).write(to: url)
    try rejects { try BodyStorage.saveManual(a, to: url) }
    try expect(try Data(contentsOf: url) == Data("broken".utf8))
  }
  check("training round-trip, validation and corrupt preservation without backups") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = folder.appendingPathComponent("training.json")
    defer { try? FileManager.default.removeItem(at: folder) }
    var a = TrainingArchive(now: now, calendar: cal)
    var e = TrainingExercise()
    e.name = "Sample row"
    a.exercises = [e]
    try TrainingStorage.save(a, to: url)
    try expect(try TrainingStorage.read(url) == a)
    try TrainingStorage.save(a, to: url)
    try expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
    a.exercises[0].minReps = 99
    a.exercises[0].maxReps = 2
    try rejects { try a.validate() }
    try Data("broken".utf8).write(to: url)
    try rejects { try TrainingStorage.save(TrainingArchive(), to: url) }
    try expect(try Data(contentsOf: url) == Data("broken".utf8))
  }
  check("muscle volume counts hard sets once per region and excludes warmups/future") {
    var a = TrainingArchive()
    let e = TrainingExercise()
    a.exercises = [e]
    a.logs = [
      .init(
        exerciseID: e.id, date: date(-1),
        sets: [.init(weight: 20, reps: 9), .init(weight: 10, reps: 9, hard: false)],
        muscles: [.chest, .triceps]),
      .init(exerciseID: e.id, date: date(1), sets: [.init(weight: 25, reps: 9)], muscles: [.chest]),
    ]
    let v = a.muscleVolume(from: date(-4), to: now)
    try expect(v[.chest] == 1 && v[.triceps] == 1)
  }
  check("platform workout codes, session matching, HR and deduped adherence") {
    var a = TrainingArchive()
    a.age = 32
    var s = TrainingSession()
    s.weekday = cal.component(.weekday, from: date(-1))
    s.name = "Sample pull"
    a.plan = [s]
    var h = HealthArchive()
    let w = workout("gym", date(-1), 50, 45)
    h.records = [
      w, .init(id: "heart", metric: .heartRate, start: w.start + 60, end: w.start + 60, value: 150),
      .init(
        id: "steps", metric: .steps, start: date(-1).timeIntervalSince1970,
        end: date(-1).timeIntervalSince1970 + 60, value: 8200),
    ]
    a.completions = [.init(sessionID: s.id, date: date(-1), outcome: .done, kind: .strength)]
    let score = TrainingScorecard.build(training: a, health: h, now: now, calendar: cal)
    try expect(
      score.strength == 1 && score.walkingDays == 1 && score.workouts[0].session == s.name
        && score.workouts[0].averageHR == 150)
    try expect(TrainingScorecard.workoutType("Exercise type 53").0 == "Walking")
    try expect(TrainingScorecard.workoutType("Exercise type 4").0 == "Cycling")
    try expect(TrainingScorecard.workoutType("Exercise type 8").1 == nil)
    try expect(TrainingScorecard.workoutType("Exercise type 33").0 == "Running")
    try expect(TrainingScorecard.workoutType("Exercise type 999").1 == nil)
  }
  check("late hard workouts flagged; easy evening walks allowed; cardio HR evidence") {
    var a = TrainingArchive()
    a.age = 40
    var h = HealthArchive()
    let hard = workout("late", date(-1, 21), 30, 45)
    let easy = workout("walk", date(-2, 21), 55, 53)
    h.records = [
      hard, easy,
      .init(id: "h1", metric: .heartRate, start: hard.start + 10, end: hard.start + 10, value: 170),
      .init(id: "h2", metric: .heartRate, start: easy.start + 10, end: easy.start + 10, value: 95),
    ]
    let r = TrainingScorecard.build(training: a, health: h, now: now, calendar: cal)
    try expect(
      r.workouts.first { $0.id == "late" }!.late && !r.workouts.first { $0.id == "walk" }!.late
        && r.longCardio == 1)
    a.rules.lateEnabled = false
    try expect(
      !TrainingScorecard.build(training: a, health: h, now: now, calendar: cal).workouts.contains {
        $0.late
      })
  }
  check("flat low-HR walking pad does not earn cardio; incline does") {
    var a = TrainingArchive()
    a.age = 30
    var s = TrainingSession()
    s.kind = .cardio
    s.weekday = cal.component(.weekday, from: date(-1))
    s.cardioType = "Walking pad"
    s.incline = 0
    a.plan = [s]
    let w = workout("pad", date(-1), 55, 53)
    var h = HealthArchive()
    h.records = [
      w, .init(id: "hr", metric: .heartRate, start: w.start + 10, end: w.start + 10, value: 100),
    ]
    try expect(TrainingScorecard.build(training: a, health: h, now: now, calendar: cal).cardio == 0)
    a.plan[0].cardioType = "Incline treadmill"
    a.plan[0].incline = 8
    try expect(TrainingScorecard.build(training: a, health: h, now: now, calendar: cal).cardio == 1)
  }
  check("priority volume warnings never edit plan; overload stall detection") {
    var a = TrainingArchive()
    var e = TrainingExercise()
    e.name = "Sample leg exercise"
    a.exercises = [e]
    var s = TrainingSession()
    s.weekday = 7
    s.exercises = [e.id]
    a.plan = [s]
    e.priorityTags = [.quads]
    a.exercises = [e]
    let before = a.plan
    try expect(
      a.priorityVolume(now: now, calendar: cal).first { $0.muscle == .quads }?.planned == 3
        && a.plan == before)
    a.rules.volumeWarnings = false
    try expect(a.priorityVolume(now: now, calendar: cal).isEmpty)
    a.logs = [-42, -28, -14, -1].map {
      .init(exerciseID: e.id, date: date($0), sets: [.init(weight: 14, reps: 8)], muscles: [])
    }
    try expect(a.stalled(e, now: now))
    a.logs[a.logs.count - 1].sets[0].reps = 9
    try expect(!a.stalled(e, now: now))
  }
  check("walk nudge uses meal time, thresholds, opt-out and unknown steps") {
    var a = TrainingArchive()
    try expect(
      a.walkNudge(steps: 4000, now: now, mealTimes: [now.addingTimeInterval(-600)], calendar: cal)?
        .contains("now") == true)
    try expect(a.walkNudge(steps: nil, now: now, mealTimes: [], calendar: cal) == nil)
    try expect(a.walkNudge(steps: 7500, now: now, mealTimes: [], calendar: cal) == nil)
    a.rules.stepsEnabled = false
    try expect(a.walkNudge(steps: 4000, now: now, mealTimes: [], calendar: cal) == nil)
  }
  check("step plan separates floor and habit target; does not add estimates") {
    let doc = TrackerDocument.seeded(today: "2026-09-25", timeZoneID: "UTC")
    let a = TrainingArchive()
    var h = HealthArchive()
    h.records = [
      .init(
        id: "daily", metric: .steps, start: date(0, 0).timeIntervalSince1970,
        end: date(0, 21).timeIntervalSince1970, value: 7800)
    ]
    let r = TrainingStepsReport.build(training: a, health: h, document: doc, now: now)
    try expect(
      r.steps == 7800 && r.headline.contains("Floor met") && !r.blocks.contains { $0.checked })
    try expect(
      TrainingStepsReport.build(training: a, health: HealthArchive(), document: doc, now: now).steps
        == nil)
  }
  check("treadmill low step count triggers rails hint only with actual samples") {
    let doc = TrackerDocument.seeded(today: "2026-09-25", timeZoneID: "UTC")
    var a = TrainingArchive()
    var s = TrainingSession()
    s.weekday = 6
    s.kind = .cardio
    s.cardioType = "Incline treadmill"
    a.plan = [s]
    let w = workout("treadmill", date(0), 50, 34)
    var h = HealthArchive()
    h.records = [w, .init(id: "few", metric: .steps, start: w.start, end: w.end, value: 900)]
    let r = TrainingStepsReport.build(training: a, health: h, document: doc, now: now)
    try expect(r.railsHint && r.blocks.contains { $0.evidence == "Watch workout" })
    h.records = [w]
    try expect(
      !TrainingStepsReport.build(training: a, health: h, document: doc, now: now).railsHint)
  }
  check("assistant body summary is bounded, explicit and optional") {
    let doc = TrackerDocument.seeded(today: "2026-09-25")
    let p = try ClaudeAssistant.prompt(
      "Review training", document: doc, today: "2026-09-25", shareHistory: false,
      bodySummary: "Sample goal and lifts")
    try expect(p.contains("BODY TRAINING SUMMARY") && p.contains("Sample goal and lifts"))
    try expect(
      !(try ClaudeAssistant.prompt("Hi", document: doc, today: "2026-09-25", shareHistory: false))
        .contains("BODY TRAINING SUMMARY"))
  }
  check("walking sessions never receive a late flag, even at high recorded HR") {
    var a = TrainingArchive()
    a.age = 38
    let w = workout("late-walk", date(-1, 21), 40, 53)
    var h = HealthArchive()
    h.records = [
      w, .init(id: "peak", metric: .heartRate, start: w.start + 60, end: w.start + 60, value: 175),
    ]
    let r = TrainingScorecard.build(training: a, health: h, now: now, calendar: cal)
    try expect(!r.workouts[0].late)
  }
  check("supersets validate references and prevent pairing the same exercise twice") {
    var a=TrainingArchive();let first=TrainingExercise(),second=TrainingExercise(),third=TrainingExercise();a.exercises=[first,second,third]
    var session=TrainingSession();session.exercises=a.exercises.map(\.id);session.supersets=[[first.id,second.id]];a.plan=[session]
    try a.validate();a.plan[0].supersets.append([second.id,third.id]);try rejects{try a.validate()}
  }
  check("priority volumes distinguish explicit tags, planned sets and logged hard sets") {
    var a=TrainingArchive();var e=TrainingExercise();e.priorityTags=[.sideDelts];a.exercises=[e]
    var session=TrainingSession();session.exercises=[e.id];a.plan=[session]
    a.logs=[.init(exerciseID:e.id,date:date(-1),sets:[.init(weight:6,reps:14),.init(weight:3,reps:10,hard:false)],muscles:[.frontDeltoids],priorityTags:[.sideDelts])]
    let r=a.priorityVolume(now:now,calendar:cal).first{$0.muscle == .sideDelts}!
    try expect(r.planned==3 && r.logged==1 && r.minimum==6)
    try expect(a.priorityVolume(now:now,calendar:cal).first{$0.muscle == .upperChest}?.planned==0)
  }
  return (count, failures)
}
