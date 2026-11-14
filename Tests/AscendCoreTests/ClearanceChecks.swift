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
    return (count, failures)
}
