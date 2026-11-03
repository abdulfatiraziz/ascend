import AscendCore
import Foundation

// Fictional generated fixture only. Never reads the live Ascend folder.
guard CommandLine.arguments.count == 2 else {
  fatalError("Usage: AscendBodySample <empty sample folder>")
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
if FileManager.default.fileExists(atPath: folder.path),
  !(try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty
{
  fatalError("Use an empty folder; existing data is never replaced.")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let now = Date()
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone.current
cal.firstWeekday = 2
let today = cal.startOfDay(for: now)
func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
func write<T: Encodable>(_ value: T, _ name: String) throws {
  try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
}
var a = TrainingArchive(now: now, calendar: cal)
a.age = 36
a.heightCM = 184
a.maintenanceSex = .male
a.weekOne = day(-56)
a.goal = BodyGoal(targetFat: 18, targetDate: day(100))
var checkpoint = BodyCheckpoint()
checkpoint.targetFat = 20
checkpoint.date = day(50)
a.goal.checkpoints = [checkpoint]
let definitions: [(String, [MuscleRegion], String, Double, Bool)] = [
  ("Goblet squat", [.quadriceps, .gluteal], "Dumbbell", 16, true),
  ("Chest-supported row", [.upperBack, .biceps, .backDeltoids], "Machine", 32, false),
  ("Floor press", [.chest, .triceps, .frontDeltoids], "Dumbbell", 14, false),
  ("Hip thrust", [.hamstring, .gluteal, .lowerBack], "Barbell", 42, true),
]
for (name, tags, equipment, weight, compound) in definitions {
  var e = TrainingExercise()
  e.name = name
  e.muscles = tags
  e.equipment = equipment
  e.startingWeight = weight
  let art = name.lowercased().replacingOccurrences(of: " ", with: "-")
  e.animationID = ["goblet-squat", "chest-supported-row", "hip-thrust"].contains(art) ? art : nil
  e.compound = compound
  e.priorityTags =
    tags.contains(.quadriceps)
    ? [.quads]
    : tags.contains(.hamstring)
      ? [.hamstrings] : tags.contains(.upperBack) ? [.upperBack, .rearDelts] : [.upperChest]
  a.exercises.append(e)
}
for d in 1...7 {
  var s = TrainingSession()
  s.weekday = d
  s.name =
    [
      "Sunday reset", "Full body A", "Incline walk", "Full body B", "Aerobic base", "Incline walk",
      "Full body C",
    ][d - 1]
  s.kind = [2, 4, 7].contains(d) ? .strength : d == 1 ? .rest : .cardio
  s.exercises = s.kind == .strength ? a.exercises.map(\.id) : []
  s.incline = 7
  s.speed = 4
  s.minutes = 50
  a.plan.append(s)
}
// Ensure a visible sample session regardless of the day this tool runs.
if let i = a.plan.firstIndex(where: { $0.weekday == cal.component(.weekday, from: now) }) {
  a.plan[i].kind = .strength
  a.plan[i].name = "Full body · sample session"
  a.plan[i].exercises = a.exercises.map(\.id)
}
for offset in [-35, -28, -21, -14, -7, -3, -2, -1] {
  for (index, e) in a.exercises.enumerated() {
    let weight = e.startingWeight + Double((35 + offset) / 14)
    let count = offset >= (-3) ? (index == 0 ? 4 : 3) : 3
    a.logs.append(
      .init(
        exerciseID: e.id, date: day(offset).addingTimeInterval(13 * 3600),
        sets: Array(repeating: .init(weight: weight, reps: 12, rpe: 8), count: count),
        muscles: e.muscles, priorityTags: e.priorityTags))
  }
}
try a.validate()
try write(a, "training.json")
var body = BodyArchive()
for i in 0..<29 {
  let offset = i - 28
  let w = 88.5 - Double(i) * 0.065 + sin(Double(i)) * 0.18
  let row = BodyMeasurement(fields: [
    "id": .text("sample-scale-\(i)"), "userId": .text("generated-sample"),
    "createdAt": .number(
      day(offset).addingTimeInterval(min(8 * 3600, max(0, now.timeIntervalSince(today) - 1800)))
        .timeIntervalSince1970 * 1000), "measuredWeight": .number(w),
    "bodyFatPercentage": .number(23.2 - Double(i) * 0.025), "isManual": .bool(false),
  ])
  body = try body.merging([row])
}
body = try body.savingManual(kilograms: 86.9, date: now.addingTimeInterval(-900))
try write(body, "body-measurements.json")
var doc = TrackerDocument.seeded(today: "2026-01-01", timeZoneID: cal.timeZone.identifier)
let engine = TrackerEngine(document: doc)
doc = TrackerDocument.seeded(today: engine.key(now), timeZoneID: cal.timeZone.identifier)
for offset in -28..<0 {
  for hour in [12, 19] {
    let when = day(offset).addingTimeInterval(Double(hour) * 3600)
    var meal = MealEntry(
      takenAt: when.timeIntervalSince1970, day: engine.key(when), note: "Generated sample meal",
      photo: "generated-placeholder.png", source: "mac")
    meal.confirmed = true
    meal.kcal = 1200
    meal.protein = 50
    meal.carbs = 130
    meal.fat = 40
    doc.meals.entries.append(meal)
  }
}
if let id = doc.mealHabits.calories?.id, let i = doc.habits.firstIndex(where: { $0.id == id }) {
  for j in doc.habits[i].revisions.indices { doc.habits[i].revisions[j].target?.maximum = 2500 }
}
try doc.validate()
try write(doc, "tracker.json")
var health = HealthArchive()
for i in -6...0 {
  let start = day(i)
  let limit = min(start.addingTimeInterval(22 * 3600), now)
  if limit > start {
    health.records.append(
      .init(
        id: "sample-steps-\(i)", metric: .steps, start: start.timeIntervalSince1970,
        end: limit.timeIntervalSince1970, value: i == 0 ? 6250 : Double(7400 + (i + 6) * 270)))
  }
  if i < 0 {
    let s = start.addingTimeInterval(13 * 3600)
    let end = s.addingTimeInterval(50 * 60)
    let code = i % 2 == 0 ? 45 : 34
    health.records.append(
      .init(
        id: "sample-workout-\(i)", metric: .workout, start: s.timeIntervalSince1970,
        end: end.timeIntervalSince1970, value: 50, detail: "Exercise type \(code)"))
    for j in 0..<10 {
      let t = s.addingTimeInterval(Double(j) * 300).timeIntervalSince1970
      health.records.append(
        .init(
          id: "sample-hr-\(i)-\(j)", metric: .heartRate, start: t, end: t,
          value: code == 45 ? 138 : 102))
    }
    health.records.append(
      .init(
        id: "sample-energy-\(i)", metric: .activeEnergy, start: s.timeIntervalSince1970,
        end: end.timeIntervalSince1970, value: 360))
    health.records.append(
      .init(
        id: "sample-distance-\(i)", metric: .distance, start: s.timeIntervalSince1970,
        end: end.timeIntervalSince1970, value: code == 45 ? 600 : 3100))
  }
}
try health.validate()
try write(health, "health.json")
print("Generated fictional Body preview in the requested empty folder.")
