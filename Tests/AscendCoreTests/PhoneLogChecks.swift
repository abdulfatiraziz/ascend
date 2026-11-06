import AscendCore
import Foundation

func runPhoneLogChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    struct Failure: Error {}
    func expect(_ value: Bool) throws { if !value { throw Failure() } }
    func rejects(_ body: () throws -> Void) throws { do { try body() } catch { return }; throw Failure() }
    func check(_ name: String, _ body: () throws -> Void) { count += 1; do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") } }
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let id = UUID().uuidString

    check("phone urge keeps early catch, anchor, spot and rounded location") {
        let u = PhoneUrge(id: id, takenAt: now.timeIntervalSince1970 - 60, outcome: "Acted on it", trigger: "Need quiet",
                          caughtEarly: false, usedAnchor: true, latitude: 48.858370, longitude: 2.294481, spot: "Spot 1")
        let log = try u.validated(now: now)
        try expect(log.category == nil && log.outcome == .acted && log.trigger == .other && log.customTrigger == "Need quiet" && log.spot == "Spot 1")
        try expect(log.caughtEarly == false && log.usedAnchor == true && log.latitude == 48.8584 && log.longitude == 2.2945)
        try rejects { _ = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Not recorded", spot: "").validated(now: now) }
    }
    check("a spot visit answered later upgrades the unanswered log and keeps what was recorded") {
        var visit = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Not recorded", latitude: 1, longitude: 2, spot: "Spot 1").validated(now: now)
        visit.note = "kept"
        let answer = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Let it pass", intensity: 3, trigger: "Stress", note: "late", spot: "Spot 1").validated(now: now)
        visit.upgrade(from: answer)
        try expect(visit.outcome == .passed && visit.intensity == 3 && visit.trigger == .stress && visit.note == "kept" && visit.spot == "Spot 1" && visit.latitude == 1)
    }
    check("phone triggers map to built-in ones where they match") {
        try expect(try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Let it pass", trigger: "After a meal").validated(now: now).trigger == .meal)
        try expect(try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Let it pass", trigger: "With people").validated(now: now).trigger == .social)
        let plain = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Let it pass").validated(now: now)
        try expect(plain.trigger == nil && plain.customTrigger == nil && plain.latitude == nil && plain.category == nil)
    }
    check("urge rejects half a location, bad coordinates and long triggers") {
        try rejects { _ = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Acted on it", latitude: 12).validated(now: now) }
        try rejects { _ = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Acted on it", latitude: 95, longitude: 10).validated(now: now) }
        try rejects { _ = try PhoneUrge(id: id, takenAt: now.timeIntervalSince1970, outcome: "Acted on it", trigger: String(repeating: "x", count: 41)).validated(now: now) }
    }
    check("urge logs without the new fields still decode, and new fields round-trip") {
        let old = #"{"id":"\#(id)","timestamp":0,"outcome":"Let it pass","note":""}"#
        let decoded = try JSONDecoder().decode(UrgeLog.self, from: Data(old.utf8))
        try expect(decoded.latitude == nil && decoded.caughtEarly == nil)
        var log = decoded; log.latitude = 1; log.longitude = 2; log.usedAnchor = true
        try expect(try JSONDecoder().decode(UrgeLog.self, from: JSONEncoder().encode(log)) == log)
    }
    check("weight log validates range and gives a stable manual ID") {
        guard case .weight(let wid, let kg, _) = try PhoneLogEntry(id: id, takenAt: now.timeIntervalSince1970, type: "weight", kilograms: 77.876).validated(now: now) else { throw Failure() }
        try expect(wid == "manual-phone-" + id.lowercased() && kg == 77.88)
        try rejects { _ = try PhoneLogEntry(id: id, takenAt: now.timeIntervalSince1970, type: "weight", kilograms: 9).validated(now: now) }
        try rejects { _ = try PhoneLogEntry(id: id, takenAt: now.timeIntervalSince1970, type: "dance").validated(now: now) }
        try rejects { _ = try PhoneLogEntry(id: id, takenAt: now.timeIntervalSince1970 + 3600, type: "weight", kilograms: 70).validated(now: now) }
    }
    check("phone weight is saved once as a manual reading") {
        var a = BodyArchive()
        a.records = [BodyMeasurement(fields: ["id": .text("scale-1"), "userId": .text("fictional"), "createdAt": .number((now.timeIntervalSince1970 - 86400) * 1000), "measuredWeight": .number(75)])]
        let wid = "manual-phone-" + id.lowercased()
        guard let saved = try a.savingPhoneWeight(id: wid, kilograms: 77.5, date: now) else { throw Failure() }
        try expect(saved.records.count == 2 && saved.latest?.kilograms == 77.5 && saved.latest?.isManual == true && saved.latest?.userID == "fictional")
        try expect(try saved.savingPhoneWeight(id: wid, kilograms: 77.5, date: now) == nil)
    }
    check("sets: same index replaces, next index appends, unknown exercise is refused") {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var a = TrainingArchive()
        var e = TrainingExercise(); e.name = "Incline press"; e.muscles = [.chest]
        a.exercises = [e]
        var s = TrainingSession(); s.weekday = cal.component(.weekday, from: now); s.name = "Push"; s.exercises = [e.id]
        a.plan = [s]
        a.logs = [LiftLog(exerciseID: e.id, date: now.addingTimeInterval(-7 * 86400), sets: [TrainingSet(weight: 20, reps: 10)], muscles: [.chest])]
        try a.applyPhoneSet(exerciseID: e.id, index: 0, set: TrainingSet(weight: 22.5, reps: 10), date: now, calendar: cal)
        try a.applyPhoneSet(exerciseID: e.id, index: 1, set: TrainingSet(weight: 22.5, reps: 9), date: now, calendar: cal)
        try a.applyPhoneSet(exerciseID: e.id, index: 1, set: TrainingSet(weight: 22.5, reps: 8), date: now, calendar: cal)
        let today = a.logs.first { cal.isDate($0.date, inSameDayAs: now) }!
        try expect(a.logs.count == 2 && today.sets.map(\.reps) == [10, 8] && today.muscles == [.chest])
        let w = a.phoneWorkout(now: now, calendar: cal)
        try expect(w?.name == "Push" && w?.exercises.first?.last.first?.weight == 20 && w?.exercises.first?.today.count == 2)
        try rejects { try a.applyPhoneSet(exerciseID: UUID(), index: 0, set: TrainingSet(weight: 10, reps: 5), date: now, calendar: cal) }
        try rejects { _ = try PhoneLogEntry(id: id, takenAt: now.timeIntervalSince1970, type: "set", exerciseID: e.id.uuidString, setIndex: 0, weight: 20, reps: 0).validated(now: now) }
    }
    check("Now card: current slot, next slot, then nothing after the last") {
        var d = TrackerDocument.seeded(today: "2026-06-01", timeZoneID: "UTC")
        var p = DietPlan(effectiveDay: "2026-06-01")
        p.slots = [.init(name: "Lunch", portion: "Chicken 150 g · rice 100 g", startMinute: 960, endMinute: 1020, kcal: 560, protein: 54),
                   .init(name: "Sweet slot", startMinute: 1350, endMinute: 1380, kcal: 240, protein: 35, sweet: true)]
        d.diet = p
        d.routine = RoutinePreferences()
        let e = TrackerEngine(document: d)
        func at(_ minute: Int) -> Date { e.time(on: "2026-06-02", minute: minute)! }
        let lunch = d.phoneNow(at: at(970))
        try expect(lunch?.kicker == "Now · Lunch" && lunch?.title == "Chicken 150 g · rice 100 g" && lunch?.detail == "~560 kcal · 54 g protein" && lunch?.kind == "meal")
        try expect(d.phoneNow(at: at(1100))?.kicker == "Next · Sweet slot at 10:30 pm")
        try expect(d.phoneNow(at: at(1390)) == nil)
        // A routine item that comes before the next slot goes first; a current slot still wins.
        d.routine.configured = true; d.routine.bedMinute = 1380; d.routine.windDownMinutes = 120; d.routine.wakeMinute = 540
        let wind = d.phoneNow(at: at(1100))
        try expect(wind?.kicker == "Next · 9:00 pm" && wind?.title == "Wind down" && wind?.kind == "routine")
        try expect(d.phoneNow(at: at(970))?.kicker == "Now · Lunch")
        try expect(Clock12.label(0) == "12:00 am" && Clock12.label(750) == "12:30 pm" && Clock12.label(1380) == "11:00 pm")
    }
    check("urge counts: acted on today and the 7 days before, and unanswered spot visits") {
        var d = TrackerDocument.seeded(today: "2026-06-01", timeZoneID: "UTC")
        let e = TrackerEngine(document: d)
        let noon = e.time(on: "2026-06-10", minute: 720)!
        func log(_ daysAgo: Int, _ outcome: UrgeOutcome, spot: String? = nil) -> UrgeLog {
            var u = UrgeLog(timestamp: noon.addingTimeInterval(Double(-daysAgo) * 86400), outcome: outcome); u.spot = spot; return u
        }
        d.urgeLogs = [log(0, .acted), log(0, .acted), log(0, .passed), log(1, .acted), log(3, .acted), log(9, .acted),
                      log(0, .unrecorded, spot: "Spot 1"), log(2, .unrecorded, spot: "Spot 1"), log(9, .unrecorded, spot: "Spot 1"), log(1, .unrecorded)]
        let c = d.urgeCounts(at: noon)
        try expect(c.actedToday == 2 && c.actedWeekAverage == 2.0 / 7 && c.unansweredVisits == 2)
        var fresh = d; fresh.urgeLogs = [log(0, .acted)]
        try expect(fresh.urgeCounts(at: noon).actedWeekAverage == nil)
    }
    check("spots file: valid spots load; invalid, duplicate or missing files give none") {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-spots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("spots.json")
        try expect(SpotArchive.read(url).spots.isEmpty)
        let good = SpotArchive(spots: [UrgeSpot(id: "a", name: "Spot A", latitude: 48.8584, longitude: 2.2945), UrgeSpot(id: "b", name: "Spot B", latitude: 48.8606, longitude: 2.3376)])
        try JSONEncoder().encode(good).write(to: url)
        try expect(SpotArchive.read(url) == good)
        for bad in [SpotArchive(spots: [UrgeSpot(id: "a", name: "A", latitude: 91, longitude: 0)]),
                    SpotArchive(spots: [UrgeSpot(id: "a", name: "A", latitude: 1, longitude: 1), UrgeSpot(id: "a", name: "B", latitude: 2, longitude: 2)]),
                    SpotArchive(spots: [UrgeSpot(id: "a", name: " ", latitude: 1, longitude: 1)])] {
            try JSONEncoder().encode(bad).write(to: url)
            try expect(SpotArchive.read(url).spots.isEmpty)
        }
    }
    return (count, failures)
}
