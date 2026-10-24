import Foundation
import AscendCore

private struct MedFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw MedFailure(message: message) } }
private func refuses(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw MedFailure(message: "Expected rejection")
}

func runMedChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let day = "2026-10-20" // a Tuesday
    let original = TrackerDocument.seeded(today: "2026-10-18")
    let engine = TrackerEngine(document: original)

    check("medicine schedules: daily, weekdays, every N days, course dates and as needed") {
        var s = MedSchedule(start: "2026-10-18")
        try expect(s.isDue(on: day, engine: engine) && !s.isDue(on: "2026-10-17", engine: engine))
        s.end = "2026-10-19"; try expect(!s.isDue(on: day, engine: engine), "Course has ended")
        s.end = nil; s.frequency = .weekdays; s.weekdays = [3, 5]
        try expect(s.isDue(on: day, engine: engine) && !s.isDue(on: "2026-10-21", engine: engine), "Tuesday is weekday 3")
        s.frequency = .everyNDays; s.interval = 2
        try expect(s.isDue(on: day, engine: engine) && !s.isDue(on: "2026-10-19", engine: engine) && s.isDue(on: "2026-10-18", engine: engine))
        s.frequency = .asNeeded; try expect(!s.isDue(on: day, engine: engine))
        var good = MedSchedule(start: day); good.times = [540, 1260]; good.amount = "1 tablet"; good.food = .after
        try good.validate(engine: engine)
        try expect(good.summary == "Daily · 09:00, 21:00 · 1 tablet · after food", good.summary)
        for broken in [{ var b = good; b.times = [] ; return b }(), { var b = good; b.times = [1, 2, 3, 4, 5]; return b }(), { var b = good; b.times = [540, 540]; return b }(),
                       { var b = good; b.frequency = .weekdays; return b }(), { var b = good; b.frequency = .everyNDays; b.interval = 1; return b }(),
                       { var b = good; b.end = "2026-10-01"; return b }(), { var b = good; b.times = [1440]; return b }()] as [MedSchedule] {
            try refuses { try broken.validate(engine: engine) }
        }
    }
    check("Claude's sorting keeps each photo on one medicine and puts the rest in unsure") {
        let raw = MedSorting(medicines: [
            MedReading(name: " Finpecia ", ingredients: ["Finasteride 1 mg"], strength: "1 mg", category: "Hair loss · DHT blocker", confidence: "HIGH", photos: [1, 3, 9]),
            MedReading(name: "Mintop", photos: [3, 4]),
            MedReading(name: "Ghost", photos: [42])], unsure: [])
        let sorted = raw.validated(photoCount: 5)
        try expect(sorted.medicines.count == 2 && sorted.medicines[0].name == "Finpecia" && sorted.medicines[0].photos == [1, 3] && sorted.medicines[0].confidence == "high")
        try expect(sorted.medicines[1].photos == [4] && sorted.unsure == [2, 5], "Duplicates, out-of-range and unplaced photos are handled")
        var medicine = Medicine(photos: ["a.jpg"]); medicine.schedule = MedSchedule(start: day); medicine.apply(sorted.medicines[0])
        try expect(medicine.name == "Finpecia" && medicine.category == "Hair loss · DHT blocker" && medicine.schedule != nil && medicine.photos == ["a.jpg"])
    }
    check("taking every scheduled dose ticks the medication habit; untaking clears only that tick") {
        var doc = original
        let habit = doc.medHabit
        try expect(habit?.latest.title == "Take medication")
        var fin = Medicine(name: "Finasteride"); fin.confirmed = true; fin.schedule = MedSchedule(start: "2026-10-18")
        var minox = Medicine(name: "Minoxidil"); minox.confirmed = true; var s = MedSchedule(start: "2026-10-18"); s.times = [540, 1260]; minox.schedule = s
        var review = Medicine(name: "Unreviewed"); review.schedule = MedSchedule(start: "2026-10-18")
        doc.meds.medicines = [fin, minox, review]
        let slots = doc.meds.slots(on: day, engine: TrackerEngine(document: doc))
        try expect(slots.count == 3 && slots.map(\.minute) == [540, 540, 1260], "Unreviewed medicines aren't scheduled")
        try doc.setDose(fin.id, day: day, minute: 540, taken: true, at: Date(), source: "phone", today: day)
        try doc.setDose(minox.id, day: day, minute: 540, taken: true, at: Date(), source: "mac", today: day)
        try expect(TrackerEngine(document: doc).entry(for: habit!, day: day) == nil, "Not all doses taken yet")
        try doc.setDose(minox.id, day: day, minute: 1260, taken: true, at: Date(), source: "phone", today: day)
        try expect(TrackerEngine(document: doc).entry(for: habit!, day: day)?.completed == true && doc.meds.filledDays.contains(day))
        try doc.setDose(minox.id, day: day, minute: 1260, taken: true, at: Date(), source: "phone", today: day)
        try expect(doc.meds.doses.count == 3, "Resending a dose doesn't duplicate it")
        try doc.setDose(minox.id, day: day, minute: 1260, taken: false, at: Date(), source: "phone", today: day)
        try expect(TrackerEngine(document: doc).entry(for: habit!, day: day) == nil && !doc.meds.filledDays.contains(day))
        try refuses { try doc.setDose(fin.id, day: day, minute: 600, taken: true, at: Date(), source: "phone", today: day) }
        try refuses { try doc.setDose(fin.id, day: "2026-10-25", minute: 540, taken: true, at: Date(), source: "phone", today: day) }
        try refuses { try doc.setDose(review.id, day: day, minute: 540, taken: true, at: Date(), source: "phone", today: day) }
        var manual = doc; manual.setEntry(CheckIn(habitID: habit!.id, day: day, completed: true))
        try manual.setDose(minox.id, day: day, minute: 1260, taken: true, at: Date(), source: "mac", today: day)
        try manual.setDose(minox.id, day: day, minute: 1260, taken: false, at: Date(), source: "mac", today: day)
        try expect(TrackerEngine(document: manual).entry(for: habit!, day: day)?.completed == true, "A tick made by hand stays")
        try doc.validate()
        try expect(try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc)).meds == doc.meds)
        let phone = doc.phoneMedDoses(today: day)
        try expect(phone.count == 14 * 3 && phone.first?.name == "Finasteride" && phone.first?.taken == true && phone.first?.day == day)
        try expect(phone.first?.at == TrackerEngine(document: doc).time(on: day, minute: 540)?.timeIntervalSince1970)
        let week = doc.meds.adherence(today: "2026-10-21", days: 7, engine: TrackerEngine(document: doc))
        try expect(week.taken == 2 && week.missed == 7, "18th–20th: 9 slots, 2 taken")
    }
    check("a forgotten dose can be logged for an earlier day at its scheduled time, completing that day's habit only") {
        var doc = original
        let habit = doc.medHabit!
        var fin = Medicine(name: "Finasteride"); fin.confirmed = true; fin.schedule = MedSchedule(start: "2026-10-18")
        doc.meds.medicines = [fin]
        let engine = TrackerEngine(document: doc), past = "2026-10-18", today = "2026-10-21"
        let scheduled = engine.time(on: past, minute: 540)!
        try doc.setDose(fin.id, day: past, minute: 540, taken: true, at: scheduled, source: "mac", today: today)
        let dose = doc.meds.dose(fin.id, day: past, minute: 540)
        try expect(dose?.takenAt == scheduled.timeIntervalSince1970 && dose?.source == "mac")
        try expect(TrackerEngine(document: doc).entry(for: habit, day: past)?.completed == true && TrackerEngine(document: doc).entry(for: habit, day: today) == nil)
        try expect(doc.meds.adherence(today: today, days: 3, engine: TrackerEngine(document: doc)) == (1, 2), "18th taken; 19th and 20th still missed")
        try doc.setDose(fin.id, day: past, minute: 540, taken: false, at: scheduled, source: "mac", today: today)
        try expect(TrackerEngine(document: doc).entry(for: habit, day: past) == nil, "Unticking an earlier day clears that day's tick")
    }
    check("medicine list validation and older tracker files without medicines") {
        var doc = original
        var m = Medicine(name: "x", photos: ["../escape.jpg"]); doc.meds.medicines = [m]
        try refuses { try doc.validate() }
        m.photos = ["a.jpg"]; doc.meds.medicines = [m, m]; try refuses { try doc.validate() }
        var bad = Medicine(name: "y"); var s = MedSchedule(start: day); s.times = []; bad.schedule = s; doc.meds.medicines = [bad]
        try refuses { try doc.validate() }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["meds"] = nil
        let legacy = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: json))
        try expect(legacy.meds.medicines.isEmpty)
    }
    check("Ask Ascend can add, schedule and stop medicines through the preview") {
        var doc = original
        var add = AssistantCommand(type: .setMedicine)
        add.title = "Finasteride"; add.strength = "1 mg"; add.frequency = "daily"; add.times = [540]; add.food = "after"; add.amount = "1 tablet"; add.category = "Hair loss"
        let proposal = try AssistantPlanner.prepare(AssistantReply(message: "Ready to review.", actions: [add]), document: doc, today: day)
        doc = try proposal.resolve(current: doc, today: day)
        let fin = doc.meds.medicines.first
        try expect(fin?.name == "Finasteride" && fin?.confirmed == true && fin?.schedule?.summary == "Daily · 09:00 · 1 tablet · after food" && fin?.schedule?.start == day)
        try expect(proposal.changes.first?.title == "Add medicine: Finasteride 1 mg")
        var update = AssistantCommand(type: .setMedicine); update.id = fin!.id.uuidString; update.frequency = "weekdays"; update.weekdays = [2, 4, 6]; update.times = [1260, 540]
        doc = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [update]), document: doc, today: day).resolve(current: doc, today: day)
        try expect(doc.meds.medicines.count == 1 && doc.meds.medicines[0].schedule?.times == [540, 1260] && doc.meds.medicines[0].schedule?.food == .after)
        var byName = AssistantCommand(type: .setMedicine); byName.title = "finasteride"; byName.end = "2027-01-09"
        doc = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [byName]), document: doc, today: day).resolve(current: doc, today: day)
        try expect(doc.meds.medicines.count == 1 && doc.meds.medicines[0].schedule?.end == "2027-01-09", "Matched by name, case-insensitive")
        for broken in [{ var c = update; c.frequency = "hourly"; return c }(), { var c = update; c.times = []; return c }(), { var c = update; c.id = UUID().uuidString; return c }(),
                       { var c = AssistantCommand(type: .setMedicine); c.frequency = "daily"; return c }()] as [AssistantCommand] {
            try refuses { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [broken]), document: doc, today: day) }
        }
        let context = String(decoding: try ClaudeAssistant.contextData(document: doc, today: day), as: UTF8.self)
        try expect(context.contains("Finasteride") && context.contains(doc.meds.medicines[0].id.uuidString), "Chat sees the medicine list: \(context.suffix(400))")
        var stop = AssistantCommand(type: .archiveMedicine); stop.id = doc.meds.medicines[0].id.uuidString
        let stopping = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [stop]), document: doc, today: day)
        try expect(stopping.isDestructive && (try stopping.resolve(current: doc, today: day)).meds.medicines[0].archived)
        let schema = try JSONSerialization.jsonObject(with: Data(ClaudeAssistant.responseSchemaJSON.utf8)) as! [String: Any]
        try expect(String(describing: schema).contains("set_medicine") && String(describing: schema).contains("everyNDays"))
    }
    check("medicine sorting runs unsaved without tools and decodes Claude's groups") {
        let args = ClaudeAssistant.medArguments(model: .sonnet, effort: .medium)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        try expect(args.contains("--no-session-persistence") && value("--tools") == "" && value("--model") == "claude-sonnet-5-5")
        let structured: [String: Any] = ["medicines": [["name": "Finpecia", "ingredients": ["Finasteride 1 mg"], "strength": "1 mg", "form": "tablet", "category": "Hair loss · DHT blocker",
                                                         "purpose": "Treats male pattern hair loss.", "confidence": "high", "notes": "", "photos": [2, 1]]], "unsure": [3]]
        let line = String(data: try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": structured]), encoding: .utf8)!
        let sorting = try ClaudeAssistant.decodeMeds(ClaudeProcessOutput(status: 0, stdout: Data(line.utf8)), photoCount: 3)
        try expect(sorting.medicines.first?.photos == [2, 1] && sorting.unsure == [3])
        let tooMany = (0...ClaudeAssistant.maxMedPhotos).map { URL(fileURLWithPath: "/tmp/\($0).jpg") }
        try refuses { _ = try ClaudeAssistant.medInput(photos: tooMany, single: false) }
        try refuses { _ = try ClaudeAssistant.medInput(photos: [], single: false) }
    }
    check("the phone's Today summary carries steps, sleep, vitals, food, habits and dose adherence") {
        var doc = original
        let engine = TrackerEngine(document: doc)
        let bed = engine.time(on: day, minute: 60)!.timeIntervalSince1970
        doc.health.records = [
            HealthRecord(id: "s", metric: .sleep, start: bed, end: bed + 7 * 3600, value: 6.6, detail: "Asleep stages"),
            HealthRecord(id: "h", metric: .heartRate, start: bed + 3600, end: bed + 3600, value: 57),
            HealthRecord(id: "o", metric: .oxygen, start: bed + 3600, end: bed + 3600, value: 96.25),
            HealthRecord(id: "st", metric: .steps, start: bed, end: bed + 3600, value: 8651)]
        var meal = MealEntry(takenAt: bed + 12 * 3600, day: day, photo: "a.jpg", source: "phone")
        meal.estimate = MealEstimate(name: "Dal", kcal: 488, kcalLow: 400, kcalHigh: 550, protein: 21, carbs: 60, fat: 12); meal.confirmed = true
        doc.meals.entries = [meal, MealEntry(takenAt: bed + 13 * 3600, day: day, photo: "b.jpg", source: "phone")]
        let t = doc.phoneToday(today: day)
        try expect(t.steps == 8651 && t.stepGoal == 10000 && t.sleepHours == 6.6 && t.sleepMin == 7 && t.sleepMax == 8)
        try expect(t.restingHeartRate == 57 && t.oxygen == 96.3 && t.kcal == 488 && t.protein == 21 && t.kcalLimit == 1700 && t.proteinGoal == 100 && t.mealsToReview == 1)
        try expect(t.cycle == doc.cycle.title && t.dayNumber == 3 && t.dayCount == 84 && t.habitsDue > 0, "Day \(t.dayNumber) of \(t.dayCount), \(t.habitsDue) due")
        try expect(t.medsWeekTaken == 0 && t.medsWeekMissed == 0)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(t)) as! [String: Any]
        try expect(json["restingHeartRate"] as? Double == 57 && json["habitsDone"] != nil, "Keys match what the phone reads")
    }
    check("the phone gets today's habits, goals and avatar, and its check-ins update the plan") {
        var doc = original
        let t0 = doc.phoneToday(today: day)
        try expect(t0.avatar == "Obsidian" && t0.evolution == 0 && t0.progress == 0 && t0.target == 0.75 && t0.toTarget == Int(ceil(Double(t0.habitsDue) * 0.75)))
        let habits = t0.habits
        try expect(habits.count == t0.habitsDue && habits.first?.period == "Morning" && habits.last?.period == "Evening", "Ordered morning to evening")
        let sleep = habits.first { $0.title == "Sleep" }, meds = habits.first { $0.title == "Take medication" }
        try expect(sleep?.kind == "metric" && sleep?.auto == true && sleep?.target == "7–8 hours" && meds?.kind == "check" && meds?.auto == false && meds?.goal == "Self-care")
        try expect(t0.goals.map(\.title).contains("Self-care") && t0.goals.allSatisfy { $0.done == 0 })
        try doc.applyPhoneCheckIn(PhoneCheckIn(id: "a", habitID: meds!.id, day: day, completed: true), today: day)
        try doc.applyPhoneCheckIn(PhoneCheckIn(id: "b", habitID: sleep!.id, day: day, value: 7.5), today: day)
        let t1 = doc.phoneToday(today: day)
        try expect(t1.habits.first { $0.id == meds!.id }?.done == true && t1.habits.first { $0.id == sleep!.id }?.value == 7.5 && t1.habitsDone == 2)
        try expect(t1.goals.first { $0.title == "Self-care" }?.done == 1 && t1.toTarget == t0.toTarget - 2)
        try doc.applyPhoneCheckIn(PhoneCheckIn(id: "c", habitID: meds!.id, day: day, clear: true), today: day)
        try expect(doc.phoneToday(today: day).habitsDone == 1)
        try refuses { try doc.applyPhoneCheckIn(PhoneCheckIn(id: "d", habitID: meds!.id, day: "2026-10-25", completed: true), today: day) }
        try refuses { try doc.applyPhoneCheckIn(PhoneCheckIn(id: "e", habitID: UUID().uuidString, day: day, completed: true), today: day) }
        try refuses { try doc.applyPhoneCheckIn(PhoneCheckIn(id: "f", habitID: sleep!.id, day: day, value: -1), today: day) }
        var rest = doc; rest.restDays.insert(day)
        try refuses { try rest.applyPhoneCheckIn(PhoneCheckIn(id: "g", habitID: meds!.id, day: day, completed: true), today: day) }
        try doc.validate()
    }
    check("phone medicine photos and doses are validated") {
        let now = Date()
        let photo = PhoneMedPhoto(id: UUID().uuidString, batch: UUID().uuidString, batchSize: 5, takenAt: now.timeIntervalSince1970 - 10, image: Data([1, 2, 3]).base64EncodedString())
        try expect((try photo.validated(now: now)).data == Data([1, 2, 3]))
        for broken in [{ var p = photo; p.batch = "x"; return p }(), { var p = photo; p.batchSize = 0; return p }(), { var p = photo; p.batchSize = 41; return p }(),
                       { var p = photo; p.mediaType = "image/gif"; return p }(), { var p = photo; p.takenAt = now.timeIntervalSince1970 + 3600; return p }(), { var p = photo; p.image = ""; return p }()] as [PhoneMedPhoto] {
            try refuses { _ = try broken.validated(now: now) }
        }
    }
    if ProcessInfo.processInfo.environment["ASCEND_LIVE_CLAUDE"] == "1", let folder = ProcessInfo.processInfo.environment["ASCEND_MED_PHOTOS"] {
        // Opt-in: real sorting of a mixed batch (two sides of one medicine, another medicine, an unnamed strip). Nothing is saved.
        count += 1
        do {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw MedFailure(message: "Claude Code not found") }
            let photos = try FileManager.default.contentsOfDirectory(atPath: folder).filter { $0.hasSuffix(".jpg") }.sorted().map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
            let output = try await ProcessClaudeLauncher(timeout: 240).run(ClaudeInvocation(executable: executable,
                arguments: ClaudeAssistant.medArguments(model: .sonnet, effort: .medium),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory),
                directory: FileManager.default.temporaryDirectory, input: try ClaudeAssistant.medInput(photos: photos, single: false)))
            let sorting = try ClaudeAssistant.decodeMeds(output, photoCount: photos.count)
            for m in sorting.medicines { print("  live med: \(m.name) \(m.strength) · \(m.category) · photos \(m.photos) · \(m.confidence)") }
            print("  live unsure: \(sorting.unsure)")
            let fin = sorting.medicines.first { $0.name.localizedCaseInsensitiveContains("finpecia") || $0.ingredients.joined().localizedCaseInsensitiveContains("finasteride") }
            try expect(sorting.medicines.count == 2 && Set(fin?.photos ?? []) == [1, 3], "Front and back of Finpecia should be grouped")
            print("PASS: live Claude sorts a mixed medicine batch")
        } catch { failures += 1; print("FAIL: live Claude sorts a mixed medicine batch: \(error)") }
    }
    return (count, failures)
}
