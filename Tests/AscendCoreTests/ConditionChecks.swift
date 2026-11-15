import Foundation
import AscendCore

private struct ConditionFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw ConditionFailure(message: message) } }

func runConditionChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let engine = TrackerEngine(document: TrackerDocument.seeded(today: "2026-11-15"))

    check("Last night: stage notes and the pattern only say what the data shows") {
        try expect(Condition.stageNote(.deep, percent: 25) == "Good · aim 15–25%" && Condition.stageNote(.rem, percent: 18).hasPrefix("Low side"))
        let late = Condition.nightPattern(asleepAt: 197, phoneMinutes: 245, deepPercent: 25) ?? ""
        try expect(late.hasPrefix("4 h 05 on the phone from 11 pm, asleep at 3:17 am, 2 h 17 past"), late)
        try expect(late.contains("past your 1 am line") && late.contains("Deep sleep was fine"), late)
        try expect(Condition.nightPattern(asleepAt: 40, phoneMinutes: 5, deepPercent: 20) == nil, "on time and no phone: nothing to say")
        try expect(Condition.nightPattern(asleepAt: 200, phoneMinutes: nil, deepPercent: 10).map { !$0.contains("Deep sleep was fine") } ?? false)
    }

    check("Resting HR from sleep: lowest 30-minute average while asleep, needs 3 readings") {
        let t0 = 1_000_000.0
        // 5-minute readings: 60 bpm, then a calm 50 stretch, one 40 spike-down alone is not enough.
        var pts: [(time: Double, value: Double)] = (0..<12).map { (t0 + Double($0) * 300, 60) }
        pts += (12..<18).map { (t0 + Double($0) * 300, 50) }
        pts += [(t0 + 30 * 300, 40)]
        try expect(Condition.restingFromSleep(pts, from: t0, to: t0 + 18 * 300) == 50, "calm stretch wins; outside the night ignored")
        try expect(Condition.restingFromSleep(Array(pts.prefix(2)), from: t0, to: t0 + 600) == nil, "too thin")
    }

    check("Style & people: no family calls, grooming repeats every 3 weeks, meet-ups and dates fill from planned days") {
        let d = Missions.defaults.first { $0.id == "D" }!
        try expect(d.title == "Style & people" && !d.targets.contains { $0.id == "d.family" }, "family calls removed, name kept")
        var groom = d.targets.first { $0.id == "d.grooming" }!
        try expect(groom.isVisit && groom.cadence == "Every 3 weeks")
        groom.lastVisit = "2026-11-01"
        try expect(groom.nextVisitDay == "2026-11-22", "3 weeks after the last one")
        var dates = d.targets.first { $0.id == "d.dates" }!
        try expect(dates.isDated && dates.kind == .dated && dates.datedValue(today: "2026-11-15") == 0)
        dates.plannedDays = ["2026-10-30", "2026-11-08", "2026-11-15", "2026-11-28"]
        try expect(dates.datedValue(today: "2026-11-15") == 2, "this month, up to today")
        try expect(dates.nextPlanned(today: "2026-11-16") == "2026-11-28")
        try expect(dates.state(2, today: "2026-11-15") == .done)
        dates.plannedDays = ["2026-11-28"]
        try expect(dates.state(0, today: "2026-11-15") == .scheduled)
        try expect(!Missions.orders(Missions.defaults, value: { _ in nil }, today: "2026-11-15", limit: 99).contains { $0.missionID == "D" && $0.target.id != "d.wardrobe" },
                   "only the wardrobe can be an order; nothing in D asks to be logged")
        var saved = Missions.defaults
        saved[3].targets[2].plannedDays = ["2026-11-20"]
        try expect(Missions.merged(saved)[3].targets[2].plannedDays == ["2026-11-20"], "planned days survive a reload")
    }
    check("Health opens on today with data, else the last full day within three days") {
        try expect(Condition.reportDay(today: "2026-11-15", engine: engine) { $0 == "2026-11-15" } == "2026-11-15")
        try expect(Condition.reportDay(today: "2026-11-15", engine: engine) { $0 == "2026-11-14" } == "2026-11-14")
        try expect(Condition.reportDay(today: "2026-11-15", engine: engine) { $0 == "2026-11-12" } == "2026-11-12")
        try expect(Condition.reportDay(today: "2026-11-15", engine: engine) { _ in false } == "2026-11-15")
    }
    check("phone minutes count 11 pm to 4 am across two phone days only") {
        let d14 = engine.calendar.startOfDay(for: engine.date("2026-11-14")!).timeIntervalSince1970, d15 = engine.calendar.startOfDay(for: engine.date("2026-11-15")!).timeIntervalSince1970
        let json = """
        {"id":"p","name":"Pixel","status":"allowed","timeZoneID":"UTC","lastSync":\(d15),"days":[
          {"start":\(d14),"end":\(d15),"screenSeconds":6000,"complete":true,"apps":[],"hours":[{"start":\(d14 + 22 * 3600),"seconds":2400},{"start":\(d14 + 23 * 3600),"seconds":3600}]},
          {"start":\(d15),"end":\(d15 + 86_400),"screenSeconds":4800,"complete":true,"apps":[],"hours":[{"start":\(d15 + 3600),"seconds":1800},{"start":\(d15 + 4 * 3600),"seconds":3000}]}]}
        """
        let device = try JSONDecoder().decode(ScreenTimeDevice.self, from: Data(json.utf8))
        try expect(Condition.afterHoursMinutes(device, evening: "2026-11-14", engine: engine) == 90, "only 11 pm and 1 am count")
        try expect(Condition.afterHoursMinutes(device, evening: "2026-11-01", engine: engine) == nil, "no data is unknown, not zero")
        try expect(Condition.day(device, key: "2026-11-15", engine: engine)?.start == d15)
    }
    check("needed per week and lean mass come from the 21% estimate and the plan") {
        let today = engine.date("2026-11-15")!, due = engine.date("2026-12-31")!
        let n = Condition.neededPerWeek(current: 77.85, target: 71.6, today: today, due: due)!
        try expect(abs(n.weeks - 46.0 / 7) < 0.01 && abs(n.perWeek - 0.9511) < 0.01, "\(n)")
        try expect(Condition.neededPerWeek(current: 74, target: 70, today: due, due: today) == nil)
        try expect(abs(Condition.leanMass(kg: 77.85, bodyFat: 21) - 61.50) < 0.01)
    }
    check("bedtime minutes are signed around midnight and lateness is against 1 am") {
        let d = engine.calendar.startOfDay(for: engine.date("2026-11-14")!).timeIntervalSince1970
        try expect(Condition.signedMinute(d + 23.5 * 3600, calendar: engine.calendar) == -30)
        try expect(Condition.signedMinute(d + 3 * 3600 + 17 * 60, calendar: engine.calendar) == 197)
        try expect(Condition.lateMinutes(asleepAt: 197) == 137 && Condition.lateMinutes(asleepAt: -30) == 0)
    }
    check("the Health lede is written from the numbers") {
        try expect(Condition.healthLede(asleep: 467, asleepAt: 197, planMinutes: 480, stress: 25, steps: 3285) == "Slept 7 h 47 m, but late. A calm day on few steps.")
        try expect(Condition.healthLede(asleep: 300, asleepAt: 30, planMinutes: 480, stress: 55, steps: 9000) == "Slept 5 h, short of plan. A stressful day on your feet.")
        try expect(Condition.healthLede(asleep: nil, asleepAt: nil, planMinutes: 480, stress: nil, steps: nil) == "No watch data for this day yet.")
    }
    check("pattern lines only speak when the data shows something") {
        let days: [(label: String, steps: Double?, workout: Bool)] = [("8 Nov", 6813, true), ("9 Nov", 8035, true), ("10 Nov", 3299, false), ("11 Nov", 4500, true), ("12 Nov", 2179, true), ("13 Nov", 1352, false), ("14 Nov", 3285, false)]
        try expect(Condition.stepsPattern(days: days) == "steps fell under 7,000 on 6 of 7 days. Your two best days, 8 Nov and 9 Nov, both had a workout.")
        try expect(Condition.stepsPattern(days: [("a", 9000, false), ("b", 9000, false), ("c", 9000, false), ("d", 9000, false)]) == nil)
        let nights: [(minutes: Double, asleepAt: Int?)] = [(11, 82), (82, 163), (1, -11), (86, 234), (248, 222), (110, 102), (245, 197)]
        try expect(Condition.nightsPattern(nights) == "on nights under 15 minutes of phone after 11 pm you were asleep by 1:22 am and 11:49 pm. On nights over 2 hours, 3:42 am and 3:17 am.")
        try expect(Condition.nightsPattern([(5, 60)]) == nil)
    }
    return (count, failures)
}
