import Foundation
import AscendCore

private struct PatternFailure: Error { let message: String }
private func requirePattern(_ value: @autoclosure () -> Bool, _ message: String = "Unexpected pattern result") throws { if !value() { throw PatternFailure(message: message) } }
private func rejectPattern(_ body: () throws -> Void) throws { do { try body() } catch { return }; throw PatternFailure(message: "Expected validation failure") }

func runPatternChecks() -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ title: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(title)") } catch { failures += 1; print("FAIL: \(title): \(error)") }
    }
    let today = "2026-10-16", wakeDay = "2026-10-15"
    let base = TrackerDocument.seeded(today: "2026-10-01"), e = TrackerEngine(document: TrackerDocument.seeded(today: "2026-10-01"))
    func at(_ day: String, _ minute: Int) -> Date { e.time(on: day, minute: minute)! }
    func window(_ day: String, hours: Double) -> SleepWindow {
        let wake = at(day, 7 * 60); return SleepWindow(bedtime: wake.addingTimeInterval(-hours * 3600), wakeTime: wake)
    }
    func paired(_ n: Int) -> TrackerDocument {
        var doc = base
        for index in 1...n {
            let day = e.adding(-index, to: today)
            doc.wellbeing.set(DailyObservation(day: day, energy: index % 2 == 0 ? 4 : 2, sleep: window(day, hours: index % 2 == 0 ? 8 : 6), caffeineComplete: true, urgesComplete: true))
        }
        return doc
    }
    check("schema 1 and 2 backups migrate to an empty journal without losing existing records") {
        var doc = base; doc.health.records = [HealthRecord(id: "kept", metric: .heartRate, start: at(wakeDay, 600).timeIntervalSince1970, end: at(wakeDay, 600).timeIntervalSince1970, value: 70)]
        doc.urgeLogs = [UrgeLog(timestamp: at(wakeDay, 500))]
        for version in [1,2] {
            var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
            raw["schemaVersion"] = version; raw.removeValue(forKey: "wellbeing")
            let read = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: raw))
            try read.validate(); try requirePattern(read.schemaVersion == 3 && read.wellbeing == WellbeingJournal() && read.health == doc.health && read.urgeLogs == doc.urgeLogs)
        }
    }
    check("daily ratings are optional, bounded and unique per local date") {
        var doc = base
        doc.wellbeing.daily = [DailyObservation(day: wakeDay, energy: 0)]; try rejectPattern { try doc.validate() }
        doc.wellbeing.daily = [DailyObservation(day: wakeDay, stress: 6)]; try rejectPattern { try doc.validate() }
        doc.wellbeing.daily = [DailyObservation(day: "2026-02-30", energy: 3)]; try rejectPattern { try doc.validate() }
        let valid = DailyObservation(day: wakeDay, mood: 3)
        doc.wellbeing.daily = [valid, valid]; try rejectPattern { try doc.validate() }
        doc.wellbeing.daily = [valid]; try doc.validate()
    }
    check("saving an empty reflection removes that observation without clearing caffeine") {
        var journal = WellbeingJournal(); journal.set(DailyObservation(day: wakeDay, energy: 3)); journal.set(CaffeineEntry(timestamp: at(wakeDay, 500)))
        journal.set(DailyObservation(day: wakeDay)); try requirePattern(journal.daily.isEmpty && journal.caffeine.count == 1)
    }
    check("manual sleep rejects reversed, wrong-date and impossible asleep durations") {
        try window(wakeDay, hours: 8).validate(day: wakeDay, engine: e)
        var sleep = window(wakeDay, hours: 8); sleep.wakeTime = sleep.bedtime; try rejectPattern { try sleep.validate(day: wakeDay, engine: e) }
        sleep = window(wakeDay, hours: 8); sleep.asleepHours = 9; try rejectPattern { try sleep.validate(day: wakeDay, engine: e) }
        sleep.asleepHours = .nan; try rejectPattern { try sleep.validate(day: wakeDay, engine: e) }
        try rejectPattern { try window(wakeDay, hours: 8).validate(day: today, engine: e) }
        try rejectPattern { try window(wakeDay, hours: 37).validate(day: wakeDay, engine: e) }
    }
    check("caffeine amounts keep unknown and zero distinct and reject invalid entries") {
        var doc = base
        let entry = CaffeineEntry(timestamp: at(wakeDay, 500), milligrams: nil)
        doc.wellbeing.caffeine = [entry]; try doc.validate()
        for amount in [-1.0, 2001, .infinity, .nan] {
            doc.wellbeing.caffeine[0].milligrams = amount; try rejectPattern { try doc.validate() }
        }
        doc.wellbeing.caffeine[0].milligrams = 0; try doc.validate()
        doc.wellbeing.caffeine[0].name = "  "; try rejectPattern { try doc.validate() }
        doc.wellbeing.caffeine = [entry, entry]; try rejectPattern { try doc.validate() }
    }
    check("daily caffeine totals require completeness and known amounts") {
        var doc = base
        try requirePattern(PatternsEngine(document: doc, today: today).day(wakeDay).caffeineMg == nil)
        doc.wellbeing.set(DailyObservation(day: wakeDay, caffeineComplete: true))
        try requirePattern(PatternsEngine(document: doc, today: today).day(wakeDay).caffeineMg == 0)
        let id = UUID(); doc.wellbeing.set(CaffeineEntry(id: id, timestamp: at(wakeDay, 500)))
        try requirePattern(PatternsEngine(document: doc, today: today).day(wakeDay).caffeineMg == nil)
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: at(wakeDay, 500), milligrams: 80))
        try requirePattern(PatternsEngine(document: doc, today: today).day(wakeDay).caffeineMg == 80)
        doc.wellbeing.set(DailyObservation(day: wakeDay))
        try requirePattern(PatternsEngine(document: doc, today: today).day(wakeDay).caffeineMg == nil)
    }
    check("manual sleep takes priority over watch data and removing it restores the main session") {
        var doc = base
        let sleep = window(wakeDay, hours: 8)
        doc.health.records = [HealthRecord(id: "night", metric: .sleep, start: sleep.bedtime.timeIntervalSince1970, end: sleep.wakeTime.timeIntervalSince1970, value: 7, detail: "Asleep stages"), HealthRecord(id: "nap", metric: .sleep, start: at(wakeDay, 12 * 60).timeIntervalSince1970, end: at(wakeDay, 13 * 60).timeIntervalSince1970, value: 1)]
        doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: window(wakeDay, hours: 6)))
        let manual = PatternsEngine(document: doc, today: today).night(on: wakeDay)!
        try requirePattern(manual.manuallyCorrected && manual.window.hours == 6 && doc.health.records.count == 2)
        doc.wellbeing.set(DailyObservation(day: wakeDay))
        let watched = PatternsEngine(document: doc, today: today).night(on: wakeDay)!
        try requirePattern(!watched.manuallyCorrected && watched.window.hours == 8 && watched.window.asleepHours == 7)
        doc.health.records[0].detail = "Session window"
        try requirePattern(PatternsEngine(document: doc, today: today).night(on: wakeDay)?.window.asleepHours == nil)
    }
    check("closed-day ranges exclude today and future ratings without shortening the window") {
        var doc = paired(14); doc.wellbeing.set(DailyObservation(day: today, energy: 5, sleep: window(today, hours: 8)))
        let a = PatternsEngine(document: doc, today: today), rows = a.closedDays(14)
        try requirePattern(rows.count == 14 && rows.first?.day == "2026-10-02" && rows.last?.day == wakeDay && !rows.contains { $0.day == today })
        try requirePattern(a.closedDays(0).isEmpty && a.closedDays(367).isEmpty)
        try requirePattern(a.comparisons(days: 14)[0].pairedDays == 14)
    }
    check("comparison averages unlock only with 14 paired dates and five per group") {
        try requirePattern(!PatternsEngine(document: paired(13), today: today).comparisons(days: 28)[0].ready)
        let enough = PatternsEngine(document: paired(14), today: today).comparisons(days: 28)[0]
        try requirePattern(enough.ready && enough.first.count == 7 && enough.second.count == 7 && enough.first.average == 4 && enough.second.average == 2)
        var skewed = paired(14)
        for i in skewed.wellbeing.daily.indices { skewed.wellbeing.daily[i].sleep = window(skewed.wellbeing.daily[i].day, hours: i == 0 ? 6 : 8) }
        try requirePattern(!PatternsEngine(document: skewed, today: today).comparisons(days: 28)[0].ready)
    }
    check("missing energy and incomplete urge logs never become zero-valued comparison days") {
        var doc = base; doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: window(wakeDay, hours: 8)))
        var c = PatternsEngine(document: doc, today: today).comparisons(days: 14)
        try requirePattern(c[0].pairedDays == 0 && c[1].pairedDays == 0)
        doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: window(wakeDay, hours: 8), urgesComplete: true))
        c = PatternsEngine(document: doc, today: today).comparisons(days: 14)
        try requirePattern(c[1].pairedDays == 1 && c[1].first.average == 0)
        doc.urgeLogs = [UrgeLog(timestamp: at(wakeDay, 600))]
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 14)[1].first.average == 1)
    }
    check("rest days and dates outside the current cycle stay out of habit comparisons") {
        var doc = paired(14)
        doc.restDays.insert(wakeDay)
        let all = PatternsEngine(document: doc, today: today).comparisons(days: 28)[3]
        try requirePattern(all.pairedDays == 13)
        let old = e.adding(-30, to: today)
        doc.wellbeing.set(DailyObservation(day: old, sleep: window(old, hours: 8)))
        try requirePattern(PatternsEngine(document: doc, today: today).day(old).habitRatio == nil)
    }
    check("after-midnight caffeine comparisons require both local dates to be complete") {
        var doc = base
        let sleep = SleepWindow(bedtime: at(wakeDay, 60), wakeTime: at(wakeDay, 8 * 60))
        doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: sleep, caffeineComplete: true))
        doc.wellbeing.set(CaffeineEntry(timestamp: at("2026-10-14", 20 * 60)))
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 1)[2].pairedDays == 0)
        doc.wellbeing.set(DailyObservation(day: "2026-10-14", caffeineComplete: true))
        let c = PatternsEngine(document: doc, today: today).comparisons(days: 1)[2]
        try requirePattern(c.first.count == 1 && c.first.average == 7 && c.second.count == 0)
    }
    check("six-hour timing boundaries include unknown doses and exclude zero-dose events") {
        var doc = base
        doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: window(wakeDay, hours: 8)))
        doc.wellbeing.set(DailyObservation(day: "2026-10-14", caffeineComplete: true))
        let id = UUID(), boundary = at("2026-10-14", 17 * 60)
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: boundary))
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 1)[2].first.count == 1)
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: boundary, milligrams: 0))
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 1)[2].second.count == 1)
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: boundary.addingTimeInterval(-1), milligrams: 80))
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 1)[2].second.count == 1)
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: at("2026-10-14", 23 * 60).addingTimeInterval(1), milligrams: 80))
        try requirePattern(PatternsEngine(document: doc, today: today).comparisons(days: 1)[2].second.count == 1)
    }
    check("bedtime variation handles midnight and undefined circular averages") {
        let a = PatternsEngine(document: base, today: today)
        let variation = a.clockRegularity([at("2026-10-14", 23 * 60 + 50), at(wakeDay, 10)])!
        try requirePattern(abs(variation - 10) < 0.001)
        try requirePattern(a.clockRegularity([at(wakeDay, 10)]) == nil)
        try requirePattern(a.clockRegularity([at(wakeDay, 0), at(wakeDay, 12 * 60)]) == nil)
        try requirePattern(a.clockRegularity([at(wakeDay, 10), at(wakeDay, 10)]) == 0)
    }
    check("sleep duration uses elapsed time across DST rather than subtracting clock labels") {
        var doc = base; doc.timeZoneID = "America/New_York"
        let local = TrackerEngine(document: doc)
        let sleep = SleepWindow(bedtime: local.time(on: "2026-03-07", minute: 23 * 60)!, wakeTime: local.time(on: "2026-03-08", minute: 7 * 60)!)
        try sleep.validate(day: "2026-03-08", engine: local)
        try requirePattern(sleep.hours == 7)
    }
    check("timeline preserves local ordering, overnight sleep and distinct event IDs") {
        var doc = base; let id = UUID()
        doc.wellbeing.set(DailyObservation(day: wakeDay, sleep: window(wakeDay, hours: 8)))
        doc.wellbeing.set(CaffeineEntry(id: id, timestamp: at(wakeDay, 600), name: "Tea", milligrams: 30))
        doc.urgeLogs = [UrgeLog(id: id, timestamp: at(wakeDay, 601))]
        let events = PatternsEngine(document: doc, today: today).timeline(on: wakeDay)
        try requirePattern(events.count == 3 && Set(events.map(\.id)).count == 3 && events[0].title == "Sleep window" && events[1].caffeineID == id && events[2].urgeID == id)
    }
    check("journal notes and caffeine names never enter automatic AI context") {
        var doc = base
        doc.wellbeing.set(DailyObservation(day: wakeDay, energy: 3, note: "JOURNAL_PRIVATE_SENTINEL"))
        doc.wellbeing.set(CaffeineEntry(timestamp: at(wakeDay, 600), name: "CAFFEINE_PRIVATE_SENTINEL", milligrams: 81))
        let data = try ClaudeAssistant.contextData(document: doc, today: today, shareHistory: true)
        let context = String(decoding: data, as: UTF8.self)
        try requirePattern(!context.contains("JOURNAL_PRIVATE_SENTINEL") && !context.contains("CAFFEINE_PRIVATE_SENTINEL") && !context.contains("wellbeing"))
        let restored = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try requirePattern(restored.wellbeing == doc.wellbeing)
    }
    check("habit resets and cycle restart preserve the wellbeing journal") {
        var doc = paired(14); doc.wellbeing.set(CaffeineEntry(timestamp: at(wakeDay, 600), milligrams: 81))
        let journal = doc.wellbeing
        doc.resetDay(wakeDay); try requirePattern(doc.wellbeing == journal)
        doc.resetProgress(); try requirePattern(doc.wellbeing == journal)
        doc.restart(on: today, length: 90); try requirePattern(doc.wellbeing == journal)
    }
    check("AI proposals cannot overwrite a reflection added while awaiting a reply") {
        var action = AssistantCommand(type: .updateRoutine); action.wakeMinute = 480
        let reply = AssistantReply(message: "Change routine", actions: [action])
        let proposal = try AssistantPlanner.prepare(reply, document: base, today: today)
        var changed = base; changed.wellbeing.set(DailyObservation(day: wakeDay, energy: 4))
        try rejectPattern { _ = try proposal.resolve(current: changed, today: today) }
    }
    return (count, failures)
}
