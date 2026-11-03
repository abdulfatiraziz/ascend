import AscendCore
import Foundation

func runMaintenanceChecks() -> (count: Int, failures: Int) {
  var count = 0
  var failures = 0
  struct Failure: Error {}
  func expect(_ value: Bool) throws { if !value { throw Failure() } }
  func check(_ name: String, _ body: () throws -> Void) {
    count += 1
    do {
      try body()
      print("PASS: \(name)")
    } catch {
      failures += 1
      print("FAIL: \(name): \(error)")
    }
  }
  let now = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(secondsFromGMT: 0)!
  func date(_ index: Int, _ days: Int = 14) -> Date {
    cal.date(byAdding: .day, value: index - days, to: cal.startOfDay(for: now))!
  }
  func fixture(_ days: Int = 14, loss: Double = 0.08) -> (
    TrainingArchive, TrackerDocument, [BodyMeasurement]
  ) {
    var a = TrainingArchive(now: now, calendar: cal)
    a.age = 34
    a.heightCM = 184
    a.maintenanceSex = .male
    a.goal = BodyGoal(targetDate: now.addingTimeInterval(100 * 86400), targetWeight: 92)
    var doc = TrackerDocument.seeded(today: "2026-09-29", timeZoneID: "UTC")
    let engine = TrackerEngine(document: doc)
    for i in 0..<days {
      for j in 0..<2 {
        let when = date(i, days).addingTimeInterval(Double(12 + j * 6) * 3600)
        var meal = MealEntry(
          takenAt: when.timeIntervalSince1970, day: engine.key(when), photo: "fictional-meal.png",
          source: "mac")
        meal.confirmed = true
        meal.kcal = 1200
        doc.meals.entries.append(meal)
      }
      let start = date(i, days).timeIntervalSince1970
      doc.health.records.append(
        .init(
          id: "fictional-steps-\(i)", metric: .steps, start: start, end: start + 23 * 3600,
          value: 8200))
      doc.health.records.append(
        .init(
          id: "fictional-energy-\(i)", metric: .activeEnergy, start: start, end: start + 23 * 3600,
          value: 650))
    }
    let rows = [0, 6, days - 7, days - 1].map { i in
      BodyMeasurement(fields: [
        "id": .text("fictional-weight-\(i)"), "userId": .text("sample-maintenance"),
        "createdAt": .number(
          date(i, days).addingTimeInterval(8 * 3600).timeIntervalSince1970 * 1000),
        "measuredWeight": .number(98 - Double(i) * loss),
      ])
    }
    return (a, doc, rows)
  }
  check("Mifflin equation uses kg/cm/years and correct sex coefficient") {
    try expect(
      abs(
        BodyMaintenanceReport.restingEnergy(weight: 94, height: 186, age: 38, sex: .male)! - 1917.5)
        < 0.001)
    try expect(
      abs(
        BodyMaintenanceReport.restingEnergy(weight: 94, height: 186, age: 38, sex: .female)!
          - 1751.5) < 0.001)
    try expect(
      BodyMaintenanceReport.restingEnergy(weight: 94, height: 186, age: 16, sex: .male) == nil)
  }
  check("weight loss raises inferred maintenance above intake; gain lowers it") {
    let (a, d, w) = fixture()
    let r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(r.fullDays == 14 && r.weighIns == 4 && r.weightSpanDays == 7)
    try expect(abs(r.measured! - 3016) < 0.001 && r.averageIntake == 2400)
    let (ag, dg, wg) = fixture(loss: -0.08)
    try expect(
      abs(
        BodyMaintenanceReport.build(training: ag, records: wg, document: dg, now: now).measured!
          - 1784) < 0.001)
  }
  check("gaps never become zero intake; 12/14 gate blocks 11 days") {
    var (a, d, w) = fixture()
    let e = TrackerEngine(document: d)
    let removed = Set([e.key(date(4)), e.key(date(9))])
    d.meals.entries.removeAll { removed.contains($0.day) }
    var r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(r.fullDays == 12 && r.averageIntake == 2400 && r.measured != nil)
    d.meals.entries.removeAll { $0.day == e.key(date(10)) }
    r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(r.measured == nil && r.missing.contains { $0.contains("Log 1 more") })
    a.completedNutritionDays = [e.key(date(10))]
    r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(r.fullDays == 12 && r.days.first { $0.key == e.key(date(10)) }?.marked == true)
  }
  check("28-day gate and weight-average centroid spacing") {
    let (a, d, w) = fixture(28)
    let r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now, window: 28)
    try expect(
      r.requiredFullDays == 24 && r.weightSpanDays == 21 && abs(r.measured! - 3016) < 0.001)
  }
  check("weigh-ins must span both ends; duplicate same-day weights do not fake coverage") {
    let (a, d, w) = fixture()
    let clustered = Array(repeating: w[0], count: 4)
    let r = BodyMaintenanceReport.build(training: a, records: clustered, document: d, now: now)
    try expect(
      r.measured == nil && r.weightDays == 1 && r.missing.contains { $0.contains("seven-day") })
  }
  check("today, future and unconfirmed meals do not enter measured intake") {
    var (a, d, w) = fixture()
    var unconfirmed = d.meals.entries[0]
    unconfirmed.id = UUID()
    unconfirmed.confirmed = false
    unconfirmed.kcal = 9000
    d.meals.entries.append(unconfirmed)
    var today = d.meals.entries[0]
    today.id = UUID()
    today.takenAt = now.timeIntervalSince1970
    today.day = "2026-09-29"
    today.kcal = 9000
    d.meals.entries.append(today)
    a.completedNutritionDays = ["2026-09-29"]
    try expect(
      BodyMaintenanceReport.build(training: a, records: w, document: d, now: now).averageIntake
        == 2400)
  }
  check("confirmed kcal falls back to estimate; unreviewed estimates remain excluded") {
    var (a, d, w) = fixture()
    d.meals.entries[0].kcal = nil
    d.meals.entries[0].estimate = .init(
      name: "Fictional meal", kcal: 1200, kcalLow: 1000, kcalHigh: 1400, protein: 50, carbs: 120,
      fat: 40)
    try expect(
      BodyMaintenanceReport.build(training: a, records: w, document: d, now: now).averageIntake
        == 2400)
    a.heightCM = nil
    try expect(
      BodyMaintenanceReport.build(training: a, records: w, document: d, now: now).formula == nil)
  }
  check("formula activity is explicit; missing steps never imply sedentary") {
    let (a, d, w) = fixture()
    let r = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(r.factor == 1.55 && r.bmr != nil && r.formula != nil)
    var missing = d
    missing.health.records.removeAll { $0.metric == .steps }
    let noSteps = BodyMaintenanceReport.build(training: a, records: w, document: missing, now: now)
    try expect(
      noSteps.formula == nil && noSteps.formulaMissing.contains { $0.contains("watch steps") })
    try expect(BodyMaintenanceReport.activityFactor(steps: 3000, strengthPerWeek: 0) == 1.2)
    try expect(BodyMaintenanceReport.activityFactor(steps: 5500, strengthPerWeek: 1) == 1.375)
    try expect(BodyMaintenanceReport.activityFactor(steps: 12000, strengthPerWeek: 3) == 1.725)
  }
  check("watch calories never alter planning target; active-only is kept distinct") {
    var (a, d, w) = fixture()
    let before = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    for i in d.health.records.indices where d.health.records[i].metric == .activeEnergy {
      d.health.records[i].value = 99999
    }
    let after = BodyMaintenanceReport.build(training: a, records: w, document: d, now: now)
    try expect(
      before.deviceActive == 650 && after.deviceActive == 99999
        && before.suggestedTarget == after.suggestedTarget)
    try expect(before.currentTarget == after.currentTarget && before.suggestedTarget != nil)
    a.goal.targetDate = now.addingTimeInterval(5 * 86400)
    try expect(
      BodyMaintenanceReport.build(training: a, records: w, document: d, now: now).suggestedTarget
        == nil)
  }
  check("rounding and optional maintenance settings preserve older training archives") {
    try expect(
      BodyMaintenanceReport.round(1524) == 1500 && BodyMaintenanceReport.round(1525) == 1550)
    let a = TrainingArchive(now: now, calendar: cal)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
    json.removeValue(forKey: "heightCM")
    json.removeValue(forKey: "maintenanceSex")
    json.removeValue(forKey: "completedNutritionDays")
    let old = try JSONDecoder().decode(
      TrainingArchive.self, from: JSONSerialization.data(withJSONObject: json))
    try old.validate()
    try expect(old.heightCM == nil && old.completedNutritionDays == nil)
    try expect(
      !BodyMaintenanceReport.validDay("2026-02-30") && BodyMaintenanceReport.validDay("2026-09-29"))
  }
  return (count, failures)
}
