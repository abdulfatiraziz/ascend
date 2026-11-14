import Foundation
import AscendCore

private struct ClearanceFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw ClearanceFailure(message: message) } }

func runClearanceChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    func week(_ n: Int, gym: Int = 3, nights: Int = 5, known: Int = 7, checkIns: Double = 0.8, kg: Double? = nil, atGoal: Bool = false) -> ClearanceWeek {
        let start = String(format: "2026-%02d-%02d", 9 + n / 4, 1 + (n % 4) * 7)
        return ClearanceWeek(start: start, gym: gym, nightsByOne: nights, nightsKnown: known, checkIns: checkIns, kgDown: kg, atGoal: atGoal)
    }

    check("No history starts at Clearance I") {
        let s = Clearance.evaluate([])
        try expect(s.level == .one && s.streak == 0 && s.events.isEmpty)
    }
    check("Two clean weeks in a row reach Clearance II; one clean week does not") {
        try expect(Clearance.evaluate([week(0)]).level == .one)
        let s = Clearance.evaluate([week(0), week(1)])
        try expect(s.level == .two && s.streak == 0 && s.events.count == 1 && s.events[0].promoted)
    }
    check("A neutral week breaks the streak without dropping a level") {
        let s = Clearance.evaluate([week(0), week(1, gym: 2), week(2)])
        try expect(s.level == .one && s.streak == 1, "level \(s.level) streak \(s.streak)")
    }
    check("Clearance III needs 3 clean weeks and 2 kg down together") {
        let noWeight = Clearance.evaluate([week(0), week(1), week(2, kg: 1), week(3, kg: 1.5), week(4, kg: 1.8)])
        try expect(noWeight.level == .two && noWeight.streak == 3)
        let s = Clearance.evaluate([week(0), week(1), week(2, kg: 1), week(3, kg: 1.5), week(4, kg: 2.1)])
        try expect(s.level == .three)
    }
    check("A slack week drops one level and never below I") {
        let s = Clearance.evaluate([week(0), week(1), week(2, gym: 0)])
        try expect(s.level == .one && s.events.last?.promoted == false)
        let low = Clearance.evaluate([week(0, checkIns: 0.2), week(1, checkIns: 0.1)])
        try expect(low.level == .one && low.events.isEmpty)
    }
    check("Late nights block a clean week only when the watch saw at least 4 nights") {
        try expect(!week(0, nights: 2, known: 6).isClean)
        try expect(week(0, nights: 0, known: 2).isClean)
    }
    check("Double-O needs goal weight; a full run reaches it") {
        var weeks: [ClearanceWeek] = []
        for i in 0..<2 { weeks.append(week(i)) }                       // → II
        for i in 2..<5 { weeks.append(week(i, kg: 2.5)) }              // → III
        for i in 5..<9 { weeks.append(week(i, kg: 4.2)) }              // → IV
        let atFour = Clearance.evaluate(weeks + [week(9, kg: 4.5), week(10, kg: 4.8)])
        try expect(atFour.level == .four, "got \(atFour.level)")
        let s = Clearance.evaluate(weeks + [week(9, kg: 5.5, atGoal: true), week(10, kg: 5.6, atGoal: true)])
        try expect(s.level == .doubleO && s.events.filter(\.promoted).count == 4)
    }
    check("Weeks are evaluated in date order whatever order they arrive in") {
        try expect(Clearance.evaluate([week(1), week(0)]).level == .two)
    }
    check("Dossier placeholders are valid, round-trip as JSON and are labelled for Ask Ascend") {
        let l = Lifestyle.placeholder
        try l.validate()
        let back = try JSONDecoder().decode(Lifestyle.self, from: JSONEncoder().encode(l))
        try expect(back == l)
        try expect(l.assistantSummary.contains("Wardrobe:") && l.assistantSummary.contains("placeholder, not real yet") && l.assistantSummary.contains("00:"))
        try expect(ClearanceLevel.allCases.allSatisfy { l.rewards[$0.mark] != nil })
    }
    check("Dossier rejects empty titles and out-of-range progress") {
        var l = Lifestyle.placeholder
        l.items.append(DossierItem(section: .skills, title: "  ", tag: "Training"))
        do { try l.validate(); throw ClearanceFailure(message: "accepted empty title") } catch is ValidationError {}
        var p = Lifestyle.placeholder
        p.items.append(DossierItem(section: .skills, title: "Chess", tag: "Training", progress: 1.4))
        do { try p.validate(); throw ClearanceFailure(message: "accepted progress > 1") } catch is ValidationError {}
    }
    check("Tonight's fit picks owned pieces only, no repeats, and changes by day") {
        let l = Lifestyle.placeholder
        let a = l.tonightsFit(dayOfYear: 10), b = l.tonightsFit(dayOfYear: 11)
        try expect(a.count == 3 && a.allSatisfy { $0.tag == "Owned" } && Set(a.map(\.id)).count == a.count && a != b)
    }
    check("Debrief uses the week's own numbers, stays under 150 words and gives one order") {
        let w = DebriefWeek(start: "2026-11-02", checkIns: Score(completed: 40, scheduled: 60), gym: 1, nightsByOne: 2, nightsKnown: 6,
                            averageOnsetMinute: 1590, kgStart: 78.3, kgEnd: 77.8, averageSteps: 6200, proteinDays: 3)
        let m = Debrief.compose(w)
        try expect(m.misses.contains("Gym 1 of 3.") && m.text.contains("67% (40 of 60)") && m.text.contains("2 of 6 nights, average 2:30 am"))
        try expect(m.text.contains("78.3 → 77.8 kg, down 0.5") && m.order.hasPrefix("Three gym sessions"))
        try expect(m.wordCount < 150, "words \(m.wordCount)")
        try expect(!m.text.localizedCaseInsensitiveContains("urge"))
    }
    check("A strong week gets wins and 'same again'") {
        let w = DebriefWeek(start: "2026-11-02", checkIns: Score(completed: 55, scheduled: 60), gym: 3, nightsByOne: 6, nightsKnown: 7,
                            averageOnsetMinute: 1470, kgStart: 78.3, kgEnd: 77.6, averageSteps: 10400, proteinDays: 6)
        let m = Debrief.compose(w)
        try expect(m.misses == ["None worth naming."] && m.order == "Same again. Hold the line." && m.text.contains("12:30 am"))
    }
    check("Missions: five files A–E with unique target ids, and they round-trip as JSON") {
        let m = Missions.defaults
        try expect(m.map(\.id) == ["A", "B", "C", "D", "E"])
        let ids = m.flatMap(\.targets).map(\.id)
        try expect(Set(ids).count == ids.count)
        try expect(try JSONDecoder().decode([MissionFile].self, from: JSONEncoder().encode(m)) == m)
    }
    check("Mission A math: 15% at the same lean mass is 71.6 kg, FFMI today 18.8") {
        let weight = Missions.defaults[0].targets.first { $0.id == "a.weight" }!
        try expect(weight.target == 71.6, "got \(weight.target)")
        try expect(abs(Missions.ffmi(kg: 78.0, bodyFatPercent: 22) - 18.8) < 0.05)
        try expect(abs(Missions.weight(leanKg: 70 * 1.0, atBodyFat: 11) - 78.7) < 0.1)
    }
    check("Mission B: $3,000 → $12,000 by 31 Mar 2028 is about 8.8% a month, ~$4,400 by end of Mar 2027") {
        let g = Missions.monthlyGrowth(from: 3000, to: 12000, months: 16.5)
        try expect(abs(g - 0.0876) < 0.001, "got \(g)")
        let income = Missions.defaults[1].targets[0]
        let mar = income.planned(on: "2027-03-31")!
        try expect(abs(mar - 4380) < 70, "got \(mar)")
        try expect(abs(income.planned(on: "2028-03-31")! - 12000) < 1 && income.planned(on: "2026-11-14")! == 3000)
    }
    check("Target progress handles lower-is-better, plain ratios, checklists and missing values") {
        let run = MissionTarget("r", "5 km", unit: "min", start: 35, target: 25)
        try expect(run.lowerIsBetter && run.progress(30) == 0.5 && run.progress(24) == 1)
        let rhr = MissionTarget("h", "RHR", unit: "bpm", target: 59, lower: true)
        try expect(rhr.progress(nil) == nil && abs(rhr.progress(65)! - 59.0 / 65) < 1e-9)
        let done = MissionTarget("d", "Licence", target: 1, checklist: true)
        try expect(done.progress(1) == 1 && done.progress(0) == 0 && done.format(1) == "Done")
        try expect(MissionTarget("i", "Income", unit: "$", target: 12000).format(3000) == "$3,000")
    }
    check("Orders: behind-plan targets come first by gap, then unlogged ones; done and checklist targets never") {
        let ms = Missions.defaults
        let values: [String: Double] = ["a.weight": 78.0, "a.sleep": 1, "a.steps": 10500, "b.income": 3000]
        let o = Missions.orders(ms, value: { values[$0.id] }, today: "2026-12-01", limit: 4)
        try expect(o.count == 4)
        try expect(o[0].target.id == "a.sleep" || o[0].target.id == "a.weight", "first \(o[0].target.id)")
        try expect(Set(o.prefix(3).map(\.target.id)) == ["a.weight", "a.sleep", "b.income"], "\(o.map(\.target.id))")
        try expect(o[3].value == nil && o[3].line.hasPrefix("Not logged"))
        try expect(!o.contains { $0.target.id == "a.steps" || $0.target.checklist })
    }
    check("Mission status: no data, on plan, behind") {
        let b = Missions.defaults[1]
        try expect(Missions.status(b, value: { _ in nil }, today: "2026-11-20") == .noData)
        try expect(Missions.status(b, value: { $0.id == "b.income" ? 3100 : nil }, today: "2026-11-20") == .onPlan)
        try expect(Missions.status(b, value: { $0.id == "b.income" ? 3000 : nil }, today: "2027-06-01") == .behind)
    }
    check("A saved missions file gains new targets and keeps typed values") {
        var old = Missions.defaults
        old[0].targets.removeAll { $0.id == "a.gym" }
        old[1].targets[0].current = 3100
        let m = Missions.merged(old)
        old[0].targets[0].title = "Old name"
        let m2 = Missions.merged(old)
        try expect(m2[0].targets.contains { $0.id == "a.gym" } && m2[1].targets[0].current == 3100 && m2[0].targets[0].title == "Weight")
        try expect(m[1].targets[0].current == 3100)
        try expect(Missions.merged(m) == m)
    }
    check("Mission A splits into synced, calculated and you-log targets, each with a source or rhythm") {
        let a = Missions.defaults[0].targets
        try expect(a.filter { $0.kind == .calculated }.map(\.id) == ["a.ffmi"])
        try expect(a.filter { $0.kind == .synced }.allSatisfy { !$0.source.isEmpty })
        try expect(a.first { $0.id == "a.bodyfat" }?.kind == .manual && a.first { $0.id == "a.bodyfat" }?.cadence == "Monthly")
        try expect(!a.contains { ["a.bench", "a.squat", "a.deadlift", "a.pullups", "a.run", "a.mind", "a.hair"].contains($0.id) })
    }
    check("Mission E is the five hard skills; hikes come from the watch, the rest are logged per session") {
        let e = Missions.defaults[4].targets
        try expect(e.map(\.id) == ["e.swim", "e.hike", "e.ride", "e.range", "e.track"], "\(e.map(\.id))")
        try expect(e[1].kind == .synced && e[1].source == "Watch workouts")
        try expect(e.filter { $0.id != "e.hike" }.allSatisfy { $0.kind == .manual && !$0.cadence.isEmpty })
        let shadow = Missions.defaults[2].targets.first { $0.id == "c.shadow" }!
        try expect(shadow.kind == .synced && shadow.source == "Daily tap on Today")
    }
    check("Accent practice: added once as a daily tap, never again after it is archived") {
        var doc = TrackerDocument.seeded(today: "2026-11-01")
        doc.ensureAccentHabit(today: "2026-11-14")
        try expect(doc.accentHabit?.latest.title == "Accent practice" && doc.accentHabit?.kind == .check)
        try expect(doc.goals.filter { $0.title == "American accent" }.count == 1 && doc.accentHabit?.latest.schedule.weekdays.count == 7)
        let count = doc.habits.count
        doc.ensureAccentHabit(today: "2026-11-14"); try expect(doc.habits.count == count)
        let i = doc.habits.firstIndex { $0.id == doc.accentHabit!.id }!
        doc.habits[i].archivedDay = "2026-11-20"
        doc.ensureAccentHabit(today: "2026-11-21"); try expect(doc.habits.count == count && doc.accentHabit == nil)
        try doc.validate()
    }
    check("Visits: next visit is last + interval unless a later date is booked; overdue once it passes") {
        var skin = Missions.defaults[0].targets.first { $0.id == "a.skin" }!
        try expect(skin.cadence == "Every month" && skin.state(nil, today: "2026-11-14") == .notLogged)
        skin.lastVisit = "2026-10-31"
        try expect(skin.nextVisitDay == "2026-11-30" && skin.state(nil, today: "2026-11-14") == .scheduled)
        try expect(skin.state(nil, today: "2026-12-01") == .overdue && skin.visitValue(today: "2026-12-01") == 0)
        skin.nextVisit = "2026-12-10"
        try expect(skin.nextVisitDay == "2026-12-10")
        skin.lastVisit = "2026-12-10"
        try expect(skin.nextVisitDay == "2027-01-10", "a new visit moves past the old booking")
        var teeth = Missions.defaults[0].targets.first { $0.id == "a.teeth" }!
        teeth.lastVisit = "2026-11-14"
        try expect(teeth.nextVisitDay == "2027-05-14" && teeth.cadence == "Every 6 months")
        var saved = Missions.defaults; saved[0].targets[saved[0].targets.firstIndex { $0.id == "a.teeth" }!].lastVisit = "2026-11-14"
        try expect(Missions.merged(saved)[0].targets.first { $0.id == "a.teeth" }?.lastVisit == "2026-11-14")
        try expect(!Missions.orders(Missions.defaults, value: { _ in nil }, today: "2026-11-14", limit: 99).contains { $0.target.everyMonths != nil })
    }
    check("Target state: not logged, behind, on plan, done, and 'not yet' for an unticked box") {
        let w = Missions.defaults[0].targets.first { $0.id == "a.weight" }!
        try expect(w.state(nil, today: "2026-11-14") == .notLogged)
        try expect(w.state(77.1, today: "2026-11-14") == .behind && w.state(76.6, today: "2026-11-14") == .onPlan && w.state(71, today: "2026-11-14") == .done)
        let box = MissionTarget("x", "Licence", target: 1, checklist: true)
        try expect(box.state(0, today: "2026-11-14") == .notYet && box.state(1, today: "2026-11-14") == .done)
    }
    // Fixture: a seeded plan plus gym, wind-down and meds habits, and three medicines across the day.
    let today = "2026-11-14"
    func fixture() -> TrackerDocument {
        var doc = TrackerDocument.seeded(today: "2026-11-01")
        let g = doc.goals[0].id
        func habit(_ title: String, _ days: [Int] = Array(1...7)) -> Habit {
            Habit(goalID: g, kind: .check, createdDay: "2026-11-01", revisions: [HabitRevision(effectiveDay: "2026-11-01", title: title, note: "", period: .evening, schedule: Schedule(weekdays: days), target: nil)])
        }
        doc.habits = [habit("Gym session", [2, 4, 7]), habit("Wind down before bed"), habit("Hair care meds")]
        func med(_ name: String, _ times: [Int]) -> Medicine {
            var m = Medicine(name: name); m.confirmed = true; var s = MedSchedule(start: "2026-11-01"); s.times = times; m.schedule = s; return m
        }
        doc.meds.medicines = [med("Sola Top", [540]), med("Helio Tone", [540, 1260]), med("Calmora", [600, 1080]), med("Strovin", [1380])]
        return doc
    }
    check("Medicine moments: morning, evening, night; one tap logs the whole moment and ticks the meds habit") {
        var doc = fixture()
        let engine = TrackerEngine(document: doc)
        let m = doc.meds.moments(on: today, engine: engine)
        try expect(m.map(\.moment) == [.morning, .evening, .night] && m.map(\.slots.count) == [3, 2, 1], "\(m.map(\.slots.count))")
        try expect(m[0].names == "Helio Tone · Sola Top · Calmora" && m[0].minute == 540)
        let at = Date(timeIntervalSince1970: 1794110000)
        for moment in MedMoment.allCases { try doc.setMoment(moment, day: today, taken: true, at: at, source: "mac", today: today) }
        let e = TrackerEngine(document: doc)
        try expect(doc.meds.moments(on: today, engine: e).allSatisfy(\.allTaken), "not all taken"); try expect(doc.medHabit != nil, "no med habit"); try expect(e.completed(doc.medHabit!, on: today), "habit not ticked")
        try doc.setMoment(.evening, day: today, taken: false, at: at, source: "mac", today: today)
        let e2 = TrackerEngine(document: doc)
        try expect(doc.meds.moments(on: today, engine: e2)[1].taken == 0 && !e2.completed(doc.medHabit!, on: today))
        do { try doc.setMoment(.night, day: "2026-11-20", taken: true, at: at, source: "mac", today: today); throw ClearanceFailure(message: "future day accepted") } catch is ValidationError {}
    }
    check("Medicine reminders: one per untaken moment, with a Taken-ready id") {
        var doc = fixture(); doc.reminders.enabled = true
        let engine = TrackerEngine(document: doc)
        let now = engine.date(today)!.addingTimeInterval(-12 * 3600 + 8 * 3600)   // 8 am today
        let r = engine.medMomentReminders(now: now).filter { $0.id.contains(today) }
        try expect(r.map(\.id) == ["ascend.meds.\(today).Morning", "ascend.meds.\(today).Evening", "ascend.meds.\(today).Night"], "\(r.map(\.id))")
        try expect(r[0].title == "Morning medicines · 3 doses")
    }
    check("Gym ticks itself from a 20+ minute gym workout on the watch, on any day; a hand tick is never touched") {
        var doc = fixture()
        let engine = TrackerEngine(document: doc)
        let fri = engine.date("2026-11-13")!.timeIntervalSince1970   // noon, a Friday (not a gym day)
        doc.health.records = [HealthRecord(id: "w1", metric: .workout, start: fri + 2 * 3600, end: fri + 3 * 3600, value: 49, detail: "Exercise type 45"),
                              HealthRecord(id: "w2", metric: .workout, start: fri - 86400, end: fri - 86400 + 600, value: 10, detail: "Exercise type 45"),
                              HealthRecord(id: "w3", metric: .workout, start: fri - 2 * 86400, end: fri - 2 * 86400 + 3600, value: 60, detail: "Exercise type 33")]
        doc.applyAutoTicks(today: today, windDown: [:])
        let e = TrackerEngine(document: doc), gym = doc.gymHabit!
        try expect(e.completed(gym, on: "2026-11-13") && !e.completed(gym, on: "2026-11-12") && !e.completed(gym, on: "2026-11-11"))
        try expect(doc.autoTickSource(gym, day: "2026-11-13") == "Watch workout")
        var manual = fixture(); manual.health.records = doc.health.records
        manual.setEntry(CheckIn(habitID: gym.id, day: "2026-11-13", completed: false))
        manual.applyAutoTicks(today: today, windDown: [:])
        try expect(!TrackerEngine(document: manual).completed(gym, on: "2026-11-13"))
        doc.health.records.removeAll { $0.id == "w1" }; doc.applyAutoTicks(today: today, windDown: [:])
        try expect(TrackerEngine(document: doc).entry(for: gym, day: "2026-11-13") == nil, "a tick it wrote goes when the workout goes")
        try doc.validate()
    }
    check("Wind down: 2 hours before the watch's sleep start, 15 minutes of screens or less; no phone data = no decision") {
        let engine = TrackerEngine(document: fixture())
        let mid = engine.date("2026-11-13")!.timeIntervalSince1970 - 12 * 3600   // midnight starting 13 Nov
        let asleep = mid + 25 * 3600                                              // 1 am on 14 Nov
        var health = HealthArchive()
        health.records = [HealthRecord(id: "s", metric: .sleep, start: asleep, end: asleep + 7 * 3600, value: 7, detail: "Asleep stages")]
        func archive(_ hours: [(Double, Double)]) throws -> ScreenTimeArchive {
            let h = hours.map { ["start": $0.0, "seconds": $0.1] }
            let json: [String: Any] = ["version": 1, "devices": [["id": UUID().uuidString, "name": "Pixel", "status": "allowed", "timeZoneID": "Asia/Kolkata", "lastSync": asleep + 9 * 3600,
                "days": [["start": mid + 86400, "end": mid + 2 * 86400, "complete": true, "apps": [], "hours": []],
                         ["start": mid, "end": mid + 86400, "complete": true, "apps": [], "hours": h]]]]]
            return try JSONDecoder().decode(ScreenTimeArchive.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let quiet = try archive([(mid + 23 * 3600, 300)])                         // 11 pm–midnight: 5 min
        try expect(WindDown.nights(health: health, screen: quiet, engine: engine, today: today)["2026-11-13"] == true)
        let busy = try archive([(mid + 23 * 3600, 1800)])                         // 30 min
        try expect(WindDown.nights(health: health, screen: busy, engine: engine, today: today)["2026-11-13"] == false)
        try expect(WindDown.nights(health: health, screen: ScreenTimeArchive(), engine: engine, today: today)["2026-11-13"] == nil)
        var doc = fixture(); doc.applyAutoTicks(today: today, windDown: ["2026-11-13": true, "2026-11-12": false])
        let e = TrackerEngine(document: doc)
        try expect(e.completed(doc.windDownHabit!, on: "2026-11-13") && e.entry(for: doc.windDownHabit!, day: "2026-11-12") == nil)
    }
    return (count, failures)
}
