import Foundation
import ImageIO
import UniformTypeIdentifiers
import AscendCore

private struct FeatureFailure: Error { let message: String }
private func verify(_ test: @autoclosure () -> Bool, _ message: String = "Assertion failed") throws {
    if !test() { throw FeatureFailure(message: message) }
}
private func rejects(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw FeatureFailure(message: "Expected rejection")
}
private actor FixtureLauncher: ClaudeLauncher {
    let output: ClaudeProcessOutput
    var calls = 0
    var last: ClaudeInvocation?
    init(_ output: ClaudeProcessOutput) { self.output = output }
    func run(_ invocation: ClaudeInvocation) async throws -> ClaudeProcessOutput { calls += 1; last = invocation; return output }
}
private func line(_ object: [String: Any]) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }
private func streamOutput(_ reply: AssistantReply, session: UUID = UUID(), status: Int32 = 0) throws -> ClaudeProcessOutput {
    let structured = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))
    let lines = [line(["type": "system", "subtype": "init", "session_id": session.uuidString.lowercased(), "tools": ["StructuredOutput"]]),
                 line(["type": "assistant", "message": ["content": []]]),
                 line(["type": "result", "subtype": "success", "is_error": false, "structured_output": structured])]
    return ClaudeProcessOutput(status: status, stdout: Data(lines.joined(separator: "\n").utf8))
}
private func script(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-fake-claude-\(UUID().uuidString).sh")
    try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
/// Writes a PNG filled red; with `alpha`, only the left half is painted and the rest is transparent.
private func makePNG(width: Int, height: Int, alpha: Bool = false) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-photo-\(UUID().uuidString).png")
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    context.setFillColor(CGColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: alpha ? width / 2 : width, height: height))
    let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(writer) else { throw FeatureFailure(message: "Could not write test image") }
    return url
}
private func pixelSize(_ url: URL) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
}
func runFeatureChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") }
        catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    func checkAsync(_ name: String, _ body: () async throws -> Void) async {
        count += 1
        do { try await body(); print("PASS: \(name)") }
        catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let day = "2026-10-19"
    let original = TrackerDocument.seeded(today: day)
    check("portrait progression starts at Obsidian, reaches Titanium halfway and Ascendant at the goal") {
        try verify(AvatarStage.allCases == [.obsidian, .titanium, .ascendant])
        try verify(AvatarStage.earned(0) == .obsidian && AvatarStage.earned(0.4999) == .obsidian)
        try verify(AvatarStage.earned(0.5) == .titanium && AvatarStage.earned(0.9999) == .titanium)
        try verify(AvatarStage.earned(1) == .ascendant && AvatarStage.earned(2) == .ascendant)
        try verify(AvatarStage.earned(-1) == .obsidian && AvatarStage.earned(.nan) == .obsidian && AvatarStage.earned(.infinity) == .obsidian)
    }
    check("appearance previews override display without changing earned progression or the plan") {
        try verify(AvatarStage.resolve(evolution: 0, appearance: "Progress", preview: .ascendant) == .ascendant)
        try verify(AvatarStage.resolve(evolution: 0, appearance: "Progress") == .obsidian)
        try verify(AvatarStage.resolve(evolution: 0.75, appearance: "Progress") == .titanium)
        try verify(AvatarStage.resolve(evolution: 1, appearance: "Obsidian") == .obsidian)
        try verify(TrackerEngine(document: original).evolution(today: "2026-11-01") == 0)
    }
    check("automatic and legacy fixed appearances survive backup round trips") {
        for appearance in ["Progress", "Obsidian", "Titanium", "Ascendant"] {
            var doc = original; doc.avatarFinish = appearance
            let loaded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
            try loaded.validate(); try verify(loaded == doc)
        }
        try verify(original.avatarFinish == "Progress")
    }
    check("legacy urge logs and neutral habit labels migrate without losing IDs or history") {
        var old = original
        let id = old.habits[0].id
        old.habits[0].revisions[0].title = "No smoking"
        old.setEntry(CheckIn(habitID: id, day: day, completed: true))
        old.urgeLogs = [UrgeLog(timestamp: Date(), outcome: .acted)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        var logs = json.removeValue(forKey: "urgeLogs") as! [[String: Any]]
        logs[0]["outcome"] = "Smoked"; logs[0].removeValue(forKey: "category")
        json["smokeUrges"] = logs; json["schemaVersion"] = 1; json.removeValue(forKey: "health")
        let migrated = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: json))
        try migrated.validate(); try verify(migrated.schemaVersion == 3)
        try verify(migrated.habits[0].latest.title == "Stay intentional" && migrated.habits[0].id == id)
        try verify(migrated.checkIns == old.checkIns && migrated.urgeLogs[0].outcome == .acted && migrated.urgeLogs[0].category == nil)
        let encoded = String(data: try JSONEncoder().encode(migrated), encoding: .utf8)!
        try verify(!encoded.lowercased().contains("smok"))
        let passed = try JSONDecoder().decode(UrgeOutcome.self, from: Data("\"Passed without smoking\"".utf8))
        try verify(passed == .passed && passed.rawValue == "Let it pass")
    }
    check("future backup schemas are rejected instead of silently dropping new data") {
        var future = original; future.schemaVersion = 4
        let loaded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(future))
        try rejects { try loaded.validate() }
    }
    check("generic urge labels round trip and have a bounded length") {
        var doc = original
        doc.urgeLogs = [UrgeLog(category: "Distraction")]
        let loaded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try verify(loaded.urgeLogs[0].category == "Distraction")
        doc.urgeLogs[0].category = String(repeating: "a", count: 61)
        try rejects { try doc.validate() }
    }
    check("custom urge triggers round trip while legacy Other remains readable") {
        var doc = original
        let custom = UrgeLog(trigger: .other, category: "Distraction", customTrigger: "  Work break  ")
        doc.urgeLogs = [custom, UrgeLog(trigger: .other)]
        let loaded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try loaded.validate()
        try verify(loaded.urgeLogs[0].triggerLabel == "Work break")
        try verify(loaded.urgeLogs[1].triggerLabel == "Other" && loaded.urgeLogs[1].customTrigger == nil)
        try verify(UrgeLog(trigger: .stress, customTrigger: "Work break").customTrigger == nil)
        try verify(UrgeLog(trigger: .other, customTrigger: "  ").triggerLabel == "Other")
    }
    check("custom triggers reject oversized multiline and mismatched imported values") {
        var doc = original
        doc.urgeLogs = [UrgeLog(trigger: .other, customTrigger: String(repeating: "x", count: 40))]
        try doc.validate()
        doc.urgeLogs[0].customTrigger = String(repeating: "x", count: 41); try rejects { try doc.validate() }
        doc.urgeLogs[0].customTrigger = "Work\nbreak"; try rejects { try doc.validate() }
        doc.urgeLogs[0].customTrigger = " "; try rejects { try doc.validate() }
        doc.urgeLogs[0].customTrigger = "Work break"; doc.urgeLogs[0].trigger = .coffee; try rejects { try doc.validate() }
    }
    check("custom trigger appears in the local timeline and remains outside automatic AI context") {
        var doc = original
        doc.urgeLogs = [UrgeLog(timestamp: TrackerEngine(document: doc).date(day)!, trigger: .other, customTrigger: "TRIGGER_PRIVATE_SENTINEL")]
        let events = PatternsEngine(document: doc, today: day).timeline(on: day)
        try verify(events.contains { $0.detail.contains("TRIGGER_PRIVATE_SENTINEL") })
        for share in [false, true] {
            let context = String(data: try ClaudeAssistant.contextData(document: doc, today: day, shareHistory: share), encoding: .utf8)!
            try verify(!context.contains("TRIGGER_PRIVATE_SENTINEL"))
        }
    }
    let now = Date(), epoch = now.timeIntervalSince1970
    let request = UUID().uuidString
    let grants = Dictionary(uniqueKeysWithValues: HealthMetric.allCases.map { ($0.rawValue, true) })
    let reading = HealthRecord(id: "hr-1", metric: .heartRate, start: epoch - 60, end: epoch - 60, value: 72)
    let snapshot = HealthSnapshot(requestID: request, generatedAt: epoch, rangeStart: epoch - 86400, rangeEnd: epoch, permissions: grants, records: [reading])
    check("watch snapshot validates exact source, nonce and fresh bounded time range") {
        try snapshot.validate(expectedRequestID: request, now: now)
        var bad = snapshot; bad.sourcePackage = "another.app"; try rejects { try bad.validate(now: now) }
        try rejects { try snapshot.validate(expectedRequestID: UUID().uuidString, now: now) }
        try rejects { try snapshot.validate(now: now.addingTimeInterval(301)) }
        bad = snapshot; bad.rangeStart = epoch - 16 * 86400; try rejects { try bad.validate(now: now) }
    }
    check("watch snapshots reject invalid metrics, duplicates and unpermitted readings") {
        var bad = snapshot; bad.records[0].value = .nan; try rejects { try bad.validate(now: now) }
        bad = snapshot; bad.records[0].value = 500; try rejects { try bad.validate(now: now) }
        bad = snapshot; bad.records.append(reading); try rejects { try bad.validate(now: now) }
        bad = snapshot; bad.permissions["heartRate"] = false; try rejects { try bad.validate(now: now) }
        bad = snapshot; bad.permissions.removeValue(forKey: "sleep"); try rejects { try bad.validate(now: now) }
        bad = snapshot; bad.records[0].end = epoch + 300; try rejects { try bad.validate(now: now) }
    }
    check("an unfinished source type retains earlier data while valid daily steps import") {
        var archive = HealthArchive()
        let energy = HealthRecord(id: "earlier-energy", metric: .activeEnergy, start: epoch - 1000, end: epoch - 600, value: 2)
        archive.records = [energy]
        let steps = HealthRecord(id: "steps-day", metric: .steps, start: epoch - 3600, end: epoch, value: 50)
        var fresh = snapshot
        fresh.records = [reading, steps]
        fresh.errors = ["activeEnergy": "Source interval is not finished yet."]
        let merged = try archive.merging(fresh, expectedRequestID: request, now: now)
        try verify(merged.records.contains(energy) && merged.records.contains(steps) && merged.records.contains(reading))
        let repeated = try merged.merging(fresh, expectedRequestID: request, now: now)
        try verify(repeated.records == merged.records && repeated.errors["activeEnergy"] != nil)
        fresh.records.append(HealthRecord(id: "unfinished", metric: .activeEnergy, start: epoch - 60, end: epoch + 600, value: 1))
        try rejects { try fresh.validate(now: now) }
    }
    check("watch import is idempotent and refreshes source corrections and deletions") {
        let first = try HealthArchive().merging(snapshot, expectedRequestID: request, now: now)
        let twice = try first.merging(snapshot, expectedRequestID: request, now: now)
        try verify(first == twice && twice.records.count == 1)
        var corrected = snapshot; corrected.records[0].value = 80
        let updated = try twice.merging(corrected, expectedRequestID: request, now: now)
        try verify(updated.records[0].value == 80)
        corrected.records = []
        let cleared = try updated.merging(corrected, expectedRequestID: request, now: now)
        try verify(cleared.records.isEmpty)
    }
    check("watch refresh preserves older records and denied or failed types") {
        var base = try HealthArchive().merging(snapshot, expectedRequestID: request, now: now)
        var older = reading; older.id = "older"; older.start = epoch - 2 * 86400; older.end = older.start
        base.records.append(older)
        var denied = snapshot; denied.records = []; denied.permissions["heartRate"] = false
        let retained = try base.merging(denied, expectedRequestID: request, now: now)
        try verify(retained.records.count == 2)
        var failed = snapshot; failed.records = []; failed.errors["heartRate"] = "Unavailable"
        let kept = try base.merging(failed, expectedRequestID: request, now: now)
        let refreshed = try base.merging(snapshot, expectedRequestID: request, now: now)
        try verify(kept.records.count == 2 && refreshed.records.count == 2)
    }
    check("denied watch access never masquerades as a successful empty import") {
        var denied = snapshot; denied.records = []; denied.permissions = grants.mapValues { _ in false }
        try rejects { _ = try HealthArchive().merging(denied, expectedRequestID: request, now: now) }
    }
    check("watch data never changes habits or enters AI context") {
        var doc = original
        doc.health = try HealthArchive().merging(snapshot, expectedRequestID: request, now: now)
        try doc.validate(); try verify(doc.checkIns == original.checkIns)
        let before = TrackerEngine(document: original).score(on: day)
        try verify(TrackerEngine(document: doc).score(on: day) == before)
        let body = try ClaudeAssistant.prompt("Review my plan", document: doc, today: day, shareHistory: true)
        try verify(!body.contains("hr-1") && !body.contains("lastSync"))
        let restored = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try verify(restored.health == doc.health)
        var reset = doc; reset.resetProgress(); try verify(reset.health == doc.health)
        reset.restart(on: day, length: 90); try verify(reset.health == doc.health)
    }
    check("watch sleep groups by wake date and step aggregates by local start date") {
        let e = TrackerEngine(document: original)
        let start = e.date(day)!.timeIntervalSince1970
        var archive = HealthArchive()
        archive.records = [HealthRecord(id: "sleep", metric: .sleep, start: start - 3600, end: start + 7 * 3600, value: 8), HealthRecord(id: "steps", metric: .steps, start: start, end: start + 86399, value: 5000)]
        try verify(archive.records(.sleep, on: day, engine: e).count == 1 && archive.records(.steps, on: day, engine: e).first?.value == 5000)
    }
    check("legacy JSON defaults routine and urges without changing the plan") {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        for key in ["routine", "urgeLogs", "restDays", "previousCycles", "reminders"] { json.removeValue(forKey: key) }
        let result = try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: json))
        try result.validate(); try verify(result == original)
    }
    check("24-hour phase boundaries and two-hour wind-down") {
        var r = RoutinePreferences(); r.configured = true
        try r.validate()
        try verify(r.phase(at: 419) == .sleep && r.phase(at: 420) == .morning)
        try verify(r.phase(at: 599) == .morning && r.phase(at: 600) == .daytime)
        try verify(r.phase(at: 1259) == .daytime && r.phase(at: 1260) == .windDown)
        try verify(r.phase(at: 1380) == .sleep && r.phase(at: 0) == .sleep)
        try verify(r.windDownMinute == 1260)
    }
    check("routine supports an awake window crossing midnight") {
        var r = RoutinePreferences(); r.wakeMinute = 15 * 60; r.bedMinute = 7 * 60
        try r.validate(); try verify(r.awakeMinutes == 16 * 60)
        try verify(r.phase(at: 16 * 60) == .morning && r.phase(at: 2 * 60) == .daytime)
        try verify(r.phase(at: 6 * 60) == .windDown && r.phase(at: 8 * 60) == .sleep)
        r.wakeMinute = 8 * 60; r.bedMinute = 60
        try r.validate(); try verify(r.windDownMinute == 23 * 60 && r.phase(at: 0) == .windDown)
    }
    check("invalid routine windows are rejected") {
        var r = RoutinePreferences(); r.bedMinute = r.wakeMinute
        try rejects { try r.validate() }
        r = RoutinePreferences(); r.morningMinutes = 1200
        try rejects { try r.validate() }
        r = RoutinePreferences(); r.wakeMinute = Int.max
        try rejects { try r.validate() }
    }
    check("clock stays unconfigured until the user saves it") {
        let e = TrackerEngine(document: original)
        try verify(e.routineEvents(on: day).isEmpty)
        try verify(e.nextRoutineEvent(after: e.date(day)!) == nil)
    }
    check("clock next event skips completed tasks and rolls into tomorrow") {
        var doc = original; doc.routine.configured = true
        doc.habits[1].revisions[0].scheduledMinute = 8 * 60
        let e = TrackerEngine(document: doc), now = e.time(on: day, minute: 7 * 60 + 30)!
        try verify(e.nextRoutineEvent(after: now)?.habitID == doc.habits[1].id)
        doc.setEntry(CheckIn(habitID: doc.habits[1].id, day: day, completed: true))
        let next = TrackerEngine(document: doc).nextRoutineEvent(after: now)
        try verify(next?.title == "Wind down")
        let late = e.time(on: day, minute: 23 * 60 + 59)!
        try verify(e.nextRoutineEvent(after: late)?.title == "Wake up")
        try verify(e.key(e.nextRoutineEvent(after: late)!.date) == "2026-10-20")
    }
    check("rest day removes timed habits and retains clock anchors") {
        var doc = original; doc.routine.configured = true; doc.restDays.insert(day)
        doc.habits[1].revisions[0].scheduledMinute = 480
        let events = TrackerEngine(document: doc).routineEvents(on: day)
        try verify(events.count == 3 && events.allSatisfy(\.isAnchor))
    }
    check("scheduled habit times are versioned and range-validated") {
        var doc = original
        var revision = doc.habits[1].latest; revision.effectiveDay = "2026-10-20"; revision.scheduledMinute = 480
        doc.habits[1].revise(revision); try doc.validate()
        try verify(doc.habits[1].revision(on: day)?.scheduledMinute == nil)
        try verify(doc.habits[1].revision(on: "2026-10-20")?.scheduledMinute == 480)
        doc.habits[1].revisions[0].scheduledMinute = 1440
        try rejects { try doc.validate() }
    }
    check("DST clock timestamps remain on the selected local day") {
        var doc = original; doc.timeZoneID = "America/New_York"; doc.routine.configured = true
        let e = TrackerEngine(document: doc)
        try verify(e.key(e.time(on: "2026-03-08", minute: 150)!) == "2026-03-08")
        try verify(e.key(e.time(on: "2026-11-01", minute: 90)!) == "2026-11-01")
    }
    check("urge logs persist independently of habits and scoring") {
        var doc = original
        let before = TrackerEngine(document: doc).score(on: day)
        doc.urgeLogs.append(UrgeLog(timestamp: TrackerEngine(document: doc).date(day)!, intensity: 4, trigger: .coffee, outcome: .acted, note: "An observation"))
        try doc.validate()
        let decoded = try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc))
        try verify(decoded == doc && doc.checkIns.isEmpty && TrackerEngine(document: doc).score(on: day) == before)
        doc.resetDay(day); doc.resetProgress(); doc.restart(on: day, length: 90)
        try verify(doc.urgeLogs.count == 1)
    }
    check("invalid, duplicate and oversized urge records are rejected") {
        let time = TrackerEngine(document: original).date(day)!
        var doc = original; doc.urgeLogs = [UrgeLog(timestamp: time, intensity: 6)]
        try rejects { try doc.validate() }
        doc.urgeLogs = [UrgeLog(timestamp: time, note: String(repeating: "x", count: 501))]
        try rejects { try doc.validate() }
        let urge = UrgeLog(timestamp: time); doc.urgeLogs = [urge, urge]
        try rejects { try doc.validate() }
        doc.urgeLogs = [UrgeLog(timestamp: Date(timeIntervalSince1970: 1e100))]
        try rejects { try doc.validate() }
    }
    check("AI proposals are previews without mutations") {
        var command = AssistantCommand(type: .updateHabit); command.id = original.habits[1].id.uuidString; command.minute = 480
        let prepared = try AssistantPlanner.prepare(AssistantReply(message: "Review", actions: [command]), document: original, today: day)
        try verify(original.habits[1].latest.scheduledMinute == nil)
        try verify(prepared.candidate.habits[1].latest.scheduledMinute == 480)
        let resolved = try prepared.resolve(current: original, today: day)
        try verify(resolved == prepared.candidate)
        try verify(!prepared.isDestructive)
    }
    check("AI invalid second action rejects the whole transaction") {
        var good = AssistantCommand(type: .updateHabit); good.id = original.habits[1].id.uuidString; good.title = "Renamed"
        var bad = AssistantCommand(type: .updateHabit); bad.id = "not-a-real-id"; bad.title = "Bad"
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [good, bad]), document: original, today: day) }
        try verify(original.habits[1].latest.title == "Take medication")
    }
    check("AI stale document or date cannot overwrite newer edits") {
        var action = AssistantCommand(type: .setRestDay); action.day = day; action.rest = true
        let prepared = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day)
        var changed = original; changed.avatarFinish = "Titanium"
        try rejects { _ = try prepared.resolve(current: changed, today: day) }
        try rejects { _ = try prepared.resolve(current: original, today: "2026-10-20") }
    }
    check("AI creates a goal and linked habit in one preview") {
        var goal = AssistantCommand(type: .createGoal); goal.title = "Read more"; goal.reference = "reading"
        var habit = AssistantCommand(type: .createHabit); habit.title = "Read 20 minutes"; habit.goalID = "reading"; habit.period = "Evening"; habit.minute = 1200
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [goal, habit]), document: original, today: day)
        try verify(p.candidate.goals.count == 5 && p.candidate.habits.count == 18)
        try verify(p.candidate.habits.last?.goalID == p.candidate.goals.last?.id)
    }
    check("AI preserves old recurrence and goal windows") {
        var habit = AssistantCommand(type: .updateHabit); habit.id = original.habits.first { $0.latest.title == "Gym session" }!.id.uuidString; habit.weekdays = [3,4,6,7]
        var goal = AssistantCommand(type: .updateGoal); goal.id = original.goals[0].id.uuidString; goal.end = "2026-11-30"
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [habit, goal]), document: original, today: "2026-10-20")
        let e = TrackerEngine(document: p.candidate)
        try verify(e.score(on: day) == TrackerEngine(document: original).score(on: day))
        try verify(p.candidate.goals[0].window(on: day)?.end == original.goals[0].latest.end)
    }
    check("AI logs values and rejects future or unscheduled entries") {
        var action = AssistantCommand(type: .logCheckIn); action.id = original.habits[0].id.uuidString; action.day = day; action.value = 7.5
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day)
        try verify(TrackerEngine(document: p.candidate).completed(original.habits[0], on: day))
        action.day = "2026-10-20"
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day) }
        action.day = "2026-10-18"
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day) }
    }
    check("AI rest-day and metric target validation cannot be bypassed") {
        var doc = original; doc.restDays.insert(day)
        var action = AssistantCommand(type: .logCheckIn); action.id = doc.habits[0].id.uuidString; action.day = day; action.value = 7.5
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: doc, today: day) }
        action = AssistantCommand(type: .updateHabit); action.id = doc.habits[0].id.uuidString; action.minimum = 9
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day) }
        action.clearMaximum = true
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day)
        try verify(p.candidate.habits[0].latest.target?.minimum == 9 && p.candidate.habits[0].latest.target?.maximum == nil)
    }
    check("AI cannot change identity or submit unknown operations") {
        var action = AssistantCommand(type: .updateHabit); action.id = original.habits[1].id.uuidString; action.goalID = original.goals[0].id.uuidString
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [action]), document: original, today: day) }
        try rejects { _ = try JSONDecoder().decode(AssistantReply.self, from: Data(#"{"message":"x","actions":[{"type":"delete_all_data"}]}"#.utf8)) }
    }
    check("AI restart is explicit, destructive and preserves old records and urges") {
        var doc = original
        doc.setEntry(CheckIn(habitID: doc.habits[1].id, day: day, completed: true))
        doc.urgeLogs = [UrgeLog(timestamp: TrackerEngine(document: doc).date(day)!)]
        var a = AssistantCommand(type: .restartCycle); a.days = 90
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: doc, today: "2026-10-20")
        try verify(p.isDestructive && p.candidate.checkIns.count == 1 && p.candidate.urgeLogs.count == 1)
        try verify(p.candidate.previousCycles.count == 1)
        a.days = 100
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: doc, today: day) }
    }
    check("AI routine change validates sleep and window geometry") {
        var a = AssistantCommand(type: .updateRoutine); a.wakeMinute = 9 * 60; a.bedMinute = 60
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: original, today: day)
        try verify(p.candidate.routine.configured && p.candidate.routine.windDownMinute == 23 * 60)
        a.bedMinute = 9 * 60
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: original, today: day) }
    }
    check("AI context excludes notes and check-ins unless sharing, and never sends urges") {
        var doc = original; doc.habits[0].revisions[0].note = "NOTE_PRIVATE_SENTINEL"
        doc.urgeLogs = [UrgeLog(timestamp: TrackerEngine(document: doc).date(day)!, note: "URGE_PRIVATE_SENTINEL")]
        doc.setEntry(CheckIn(habitID: doc.habits[0].id, day: day, value: 123456789))
        let closed = try ClaudeAssistant.prompt("Move gym", document: doc, today: day, shareHistory: false)
        try verify(!closed.contains("NOTE_PRIVATE_SENTINEL") && !closed.contains("URGE_PRIVATE_SENTINEL") && !closed.contains("123456789"))
        try verify(!closed.contains("recentDays") && !closed.contains("progress") && closed.hasSuffix("USER MESSAGE:\nMove gym"))
        let shared = try ClaudeAssistant.prompt("How am I doing?", document: doc, today: day, shareHistory: true)
        try verify(shared.contains("NOTE_PRIVATE_SENTINEL") && shared.contains("123456789") && shared.contains("closedDaysScore"))
        try verify(!shared.contains("URGE_PRIVATE_SENTINEL") && !shared.contains("urgeLogs"))
    }
    check("shared history covers at most 14 days within the cycle and lists unlogged habits") {
        let e = TrackerEngine(document: original), later = e.adding(20, to: original.cycle.start)
        let data = try ClaudeAssistant.contextData(document: original, today: later, shareHistory: true)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let days = json["recentDays"] as! [[String: Any]]
        try verify(days.count == 14 && days.first?["day"] as? String == later && !(days.first?["notLogged"] as! [String]).isEmpty)
        let early = try JSONSerialization.jsonObject(with: ClaudeAssistant.contextData(document: original, today: original.cycle.start, shareHistory: true)) as! [String: Any]
        try verify((early["recentDays"] as! [[String: Any]]).count == 1)
    }
    check("AI prompts reject empty and oversized messages") {
        try rejects { _ = try ClaudeAssistant.prompt("   ", document: original, today: day, shareHistory: false) }
        try rejects { _ = try ClaudeAssistant.prompt(String(repeating: "x", count: ClaudeAssistant.maxPromptLength + 1), document: original, today: day, shareHistory: false) }
        _ = try ClaudeAssistant.prompt(String(repeating: "x", count: ClaudeAssistant.maxPromptLength), document: original, today: day, shareHistory: false)
    }
    check("Claude CLI arguments pick the model, session and no tools") {
        let id = UUID()
        let first = ClaudeAssistant.arguments(model: .opus, session: id, resume: false)
        let next = ClaudeAssistant.arguments(model: .haiku, session: id, resume: true)
        let test = ClaudeAssistant.arguments(model: .sonnet, session: nil, resume: false)
        func value(_ args: [String], _ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        try verify(first.prefix(1) == ["-p"] && value(first, "--model") == "claude-opus-5-5" && value(first, "--session-id") == id.uuidString.lowercased())
        try verify(value(next, "--resume") == id.uuidString.lowercased() && value(next, "--model") == "claude-haiku-5-5" && !next.contains("--session-id"))
        try verify(test.contains("--no-session-persistence") && !test.contains("--resume") && !test.contains("--session-id"))
        try verify(value(first, "--tools") == "" && first.contains("--strict-mcp-config") && value(first, "--setting-sources") == "")
        let schema = try JSONSerialization.jsonObject(with: Data(value(first, "--json-schema")!.utf8)) as! [String: Any]
        try verify((schema["required"] as! [String]) == ["message", "actions"])
        try verify(ClaudeModel.allCases.count == 4 && ClaudeAssistant.defaultModel == .sonnet)
        try verify(ClaudeAssistant.defaultEffort == .medium && [first, next, test].allSatisfy { value($0, "--effort") == "medium" })
        let high = ClaudeAssistant.arguments(model: .opus, effort: .xhigh, session: id, resume: true)
        try verify(value(high, "--effort") == "xhigh" && ClaudeEffort.allCases.map(\.rawValue) == ["low", "medium", "high", "xhigh", "max"])
        try verify([first, next, test].allSatisfy { value($0, "--input-format") == "stream-json" && value($0, "--output-format") == "stream-json" })
    }
    check("chat photos are downscaled, keep transparency as PNG and reject non-images") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-photos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let large = try makePNG(width: 3000, height: 1000), clear = try makePNG(width: 200, height: 100, alpha: true)
        defer { try? FileManager.default.removeItem(at: large); try? FileManager.default.removeItem(at: clear) }
        let big = try ChatPhotos.store(large, in: folder), small = try ChatPhotos.store(clear, in: folder)
        try verify(big.hasSuffix(".jpg") && small.hasSuffix(".png"))
        let bigSize = pixelSize(folder.appendingPathComponent(big)), smallSize = pixelSize(folder.appendingPathComponent(small))
        try verify(bigSize?.0 == ChatPhotos.maxPixelSize && bigSize?.1 == 523, "Unexpected size \(String(describing: bigSize))")
        try verify(smallSize?.0 == 200 && smallSize?.1 == 100, "Small images must not be upscaled")
        try verify(ChatPhotos.mediaType(folder.appendingPathComponent(big)) == "image/jpeg" && ChatPhotos.mediaType(folder.appendingPathComponent(small)) == "image/png")
        let text = folder.appendingPathComponent("notes.txt"); try Data("hello".utf8).write(to: text)
        try rejects { _ = try ChatPhotos.store(text, in: folder) }
        try verify(ChatPhotos.isImage(large) && !ChatPhotos.isImage(text) && ChatPhotos.isImage(URL(fileURLWithPath: "/x/IMG_1.HEIC")))
        try verify(ChatPhotos.folder(chat: UUID(uuidString: "0DBB8BC7-5C82-4668-810E-B002729DFEE3")!, workspace: URL(fileURLWithPath: "/w")).path == "/w/attachments/0dbb8bc7-5c82-4668-810e-b002729dfee3")
    }
    check("stream-json input carries photos as image blocks before the text") {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-input-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try makePNG(width: 40, height: 40); defer { try? FileManager.default.removeItem(at: source) }
        let photo = folder.appendingPathComponent(try ChatPhotos.store(source, in: folder))
        let line = try ClaudeAssistant.inputLine("What is this?", photos: [photo])
        try verify(line.hasSuffix("\n") && !line.dropLast().contains("\n"))
        let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        let message = json["message"] as! [String: Any], content = message["content"] as! [[String: Any]]
        try verify(json["type"] as? String == "user" && message["role"] as? String == "user" && content.count == 2)
        let source0 = content[0]["source"] as! [String: Any]
        try verify(content[0]["type"] as? String == "image" && source0["media_type"] as? String == "image/jpeg" && source0["type"] as? String == "base64")
        let bytes = try Data(contentsOf: photo)
        try verify(Data(base64Encoded: source0["data"] as! String) == bytes)
        try verify(content[1]["type"] as? String == "text" && content[1]["text"] as? String == "What is this?")
        try rejects { _ = try ClaudeAssistant.inputLine("x", photos: Array(repeating: photo, count: ChatPhotos.maxPerMessage + 1)) }
        try rejects { _ = try ClaudeAssistant.inputLine("x", photos: [folder.appendingPathComponent("missing.jpg")]) }
        let photoOnly = try ClaudeAssistant.prompt("  ", document: original, today: day, shareHistory: false, photos: 2)
        try verify(photoOnly.hasSuffix("(Sent 2 photos without a message.)"))
        try rejects { _ = try ClaudeAssistant.prompt("  ", document: original, today: day, shareHistory: false) }
    }
    check("chat messages keep their photos; older messages load without any") {
        var archive = ChatArchive(), thread = ChatThread(model: .sonnet)
        archive.insert(thread)
        archive.append(ChatMessage(fromUser: true, text: "", attachments: ["a.jpg", "b.png"]), to: thread.id)
        thread = archive.thread(thread.id)!
        try verify(thread.title == "Photo" && thread.messages[0].photos == ["a.jpg", "b.png"])
        try verify(ChatMessage(fromUser: true, text: "hi").attachments == nil)
        let restored = try JSONDecoder().decode(ChatArchive.self, from: JSONEncoder().encode(archive))
        try verify(restored == archive)
        let legacy = #"{"id":"0DBB8BC7-5C82-4668-810E-B002729DFEE3","fromUser":true,"text":"old","date":0}"#
        let old = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))
        try verify(old.photos.isEmpty && old.text == "old")
    }
    check("chat effort is saved per chat and older chats load as medium") {
        var thread = ChatThread(model: .haiku, effort: .high)
        try verify(thread.claudeEffort == .high && ChatThread(model: .opus).claudeEffort == .medium)
        thread.effort = nil; try verify(thread.claudeEffort == .medium)
        thread.effort = "turbo"; try verify(thread.claudeEffort == .medium)
        let legacy = #"{"version":1,"threads":[{"id":"0DBB8BC7-5C82-4668-810E-B002729DFEE3","title":"Old","model":"claude-opus-5-5","created":0,"updated":0,"sessionStarted":true,"messages":[]}]}"#
        let archive = try JSONDecoder().decode(ChatArchive.self, from: Data(legacy.utf8))
        try verify(archive.threads.first?.claudeEffort == .medium && archive.threads.first?.claudeModel == .opus)
    }
    check("Claude environment uses the personal profile and drops API keys and nested sessions") {
        let env = ClaudeAssistant.environment(base: ["PATH": "/usr/bin", "ANTHROPIC_API_KEY": "SECRET_SENTINEL", "ANTHROPIC_BASE_URL": "https://example.invalid",
            "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CONFIG_DIR": "/work", "LANG": "en_US.UTF-8"], configDirectory: "~/.claude-personal", home: "/Users/test")
        try verify(env["CLAUDE_CONFIG_DIR"] == "/Users/test/.claude-personal" && env["LANG"] == "en_US.UTF-8")
        try verify(env["ANTHROPIC_API_KEY"] == nil && env["ANTHROPIC_BASE_URL"] == nil && env["CLAUDECODE"] == nil && env["CLAUDE_CODE_ENTRYPOINT"] == nil)
        try verify(env["PATH"]!.hasPrefix("/Users/test/.local/bin:") && env["PATH"]!.hasSuffix(":/usr/bin"))
        try verify(!env.values.contains("SECRET_SENTINEL"))
    }
    check("chat sessions map to Claude Code transcripts and Terminal resume commands") {
        let id = UUID(uuidString: "0DBB8BC7-5C82-4668-810E-B002729DFEE3")!
        let workspace = URL(fileURLWithPath: "/Users/test/Library/Application Support/Ascend/Claude")
        let url = ClaudeAssistant.transcriptURL(session: id, workspace: workspace, configDirectory: "~/.claude-personal", home: "/Users/test")
        try verify(url.path == "/Users/test/.claude-personal/projects/-Users-test-Library-Application-Support-Ascend-Claude/0dbb8bc7-5c82-4668-810e-b002729dfee3.jsonl")
        try verify(ClaudeAssistant.terminalCommand(session: id, workspace: workspace) == "cd '/Users/test/Library/Application Support/Ascend/Claude' && claude --personal --resume 0dbb8bc7-5c82-4668-810e-b002729dfee3")
    }
    check("Claude stream decode returns structured replies and reports failures without edits") {
        let reply = AssistantReply(message: "Hi", actions: []), id = UUID()
        let output = try streamOutput(reply, session: id)
        let decoded = try ClaudeAssistant.decode(output)
        try verify(decoded == reply)
        try verify(ClaudeAssistant.sessionStarted(output.stdout, session: id) && !ClaudeAssistant.sessionStarted(output.stdout, session: UUID()))
        let failure = ClaudeProcessOutput(status: 1, stdout: Data(line(["type": "result", "subtype": "success", "is_error": true, "result": "Not logged in · Please run /login"]).utf8))
        do { _ = try ClaudeAssistant.decode(failure); throw FeatureFailure(message: "Expected rejection") }
        catch let error as ValidationError { try verify(error.message.contains("Not logged in") && error.message.contains("claude --personal")) }
        try rejects { _ = try ClaudeAssistant.decode(ClaudeProcessOutput(status: 1, stdout: Data("garbage".utf8), stderr: Data("boom".utf8))) }
        try rejects { _ = try ClaudeAssistant.decode(ClaudeProcessOutput(status: 0, stdout: output.stdout, timedOut: true)) }
        let unknown = Data(line(["type": "result", "is_error": false, "structured_output": ["message": "x", "actions": [["type": "delete_all_data"]]]]).utf8)
        try rejects { _ = try ClaudeAssistant.decode(ClaudeProcessOutput(status: 0, stdout: unknown)) }
        let long = AssistantReply(message: String(repeating: "x", count: AssistantPlanner.maxMessageLength + 1), actions: [])
        try rejects { _ = try ClaudeAssistant.decode(try streamOutput(long)) }
    }
    check("chat archive titles, trims and survives a round trip; unreadable files are kept") {
        var archive = ChatArchive(), thread = ChatThread(model: .opus)
        archive.insert(thread)
        archive.append(ChatMessage(fromUser: true, text: "  Plan my week\nwith detail"), to: thread.id)
        archive.append(ChatMessage(fromUser: true, text: "Second message"), to: thread.id)
        try verify(archive.thread(thread.id)?.title == "Plan my week" && archive.thread(thread.id)?.claudeModel == .opus)
        try verify(ChatArchive.title(for: String(repeating: "a", count: 90)).count == ChatArchive.maxTitleLength)
        for i in 0..<ChatArchive.maxMessages { archive.append(ChatMessage(fromUser: false, text: "\(i)"), to: thread.id) }
        try verify(archive.thread(thread.id)?.messages.count == ChatArchive.maxMessages)
        thread.model = "claude-future-9"; try verify(thread.claudeModel == ClaudeAssistant.defaultModel)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-chats-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("chats.json")
        try archive.save(to: url)
        let loaded = ChatArchive.load(from: url)
        try verify(loaded.notice == nil && loaded.archive == archive)
        try Data("not json".utf8).write(to: url)
        let broken = ChatArchive.load(from: url)
        try verify(broken.archive.threads.isEmpty && broken.notice != nil && !FileManager.default.fileExists(atPath: url.path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        try verify(kept.contains { $0.hasPrefix("chats-unreadable-") })
        try? FileManager.default.removeItem(at: folder)
    }
    check("AI cycle edits move linked goals but preserve custom windows and records") {
        var doc = original
        doc.goals[1].revise(GoalWindow(effectiveDay: day, start: day, end: "2026-11-01"))
        doc.setEntry(CheckIn(habitID: doc.habits[1].id, day: day, completed: true))
        var a = AssistantCommand(type: .updateCycle); a.end = "2027-01-31"; a.target = 0.8
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: doc, today: "2026-10-20")
        try verify(p.candidate.goals[0].latest.end == "2027-01-31")
        try verify(p.candidate.goals[1].latest.end == "2026-11-01" && p.candidate.checkIns == doc.checkIns)
        try verify(p.candidate.goals[0].window(on: day) == doc.goals[0].window(on: day))
    }
    check("AI clearing one check-in preserves other dates and requires destructive review") {
        var doc = original
        let h = doc.habits[1]
        doc.setEntry(CheckIn(habitID: h.id, day: day, completed: true))
        doc.setEntry(CheckIn(habitID: h.id, day: "2026-10-20", completed: true))
        var a = AssistantCommand(type: .clearCheckIn); a.id = h.id.uuidString; a.day = day
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: doc, today: "2026-10-20")
        try verify(p.isDestructive && p.candidate.checkIns.count == 1 && p.candidate.checkIns[0].day == "2026-10-20")
    }
    check("AI archiving preserves historical scheduled scores") {
        var a = AssistantCommand(type: .archiveHabit); a.id = original.habits[1].id.uuidString
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: original, today: "2026-10-20")
        try verify(p.isDestructive)
        try verify(TrackerEngine(document: p.candidate).score(on: day) == TrackerEngine(document: original).score(on: day))
        try verify(!TrackerEngine(document: p.candidate).isDue(p.candidate.habits[1], on: "2026-10-20"))
    }
    check("AI cannot overwrite private urge logs added while waiting for a reply") {
        var a = AssistantCommand(type: .updateHabit); a.id = original.habits[1].id.uuidString; a.minute = 500
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: original, today: day)
        var newer = original; newer.urgeLogs.append(UrgeLog(timestamp: TrackerEngine(document: newer).date(day)!))
        try rejects { _ = try p.resolve(current: newer, today: day) }
        try verify(newer.urgeLogs.count == 1)
    }
    check("AI clearing an exact time keeps its historical revision") {
        var doc = original; doc.habits[1].revisions[0].scheduledMinute = 480
        var a = AssistantCommand(type: .updateHabit); a.id = doc.habits[1].id.uuidString; a.clearTime = true
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [a]), document: doc, today: "2026-10-20")
        try verify(p.candidate.habits[1].latest.scheduledMinute == nil)
        try verify(p.candidate.habits[1].revision(on: day)?.scheduledMinute == 480)
    }
    check("AI operation limits and clarification replies never mutate the plan") {
        var a = AssistantCommand(type: .setRestDay); a.day = day; a.rest = true
        try rejects { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: Array(repeating: a, count: 21)), document: original, today: day) }
        let p = try AssistantPlanner.prepare(AssistantReply(message: "Which day?", actions: []), document: original, today: day)
        try verify(p.candidate == original && p.changes.isEmpty)
    }
    check("unchanged AI edits do not rewrite revisions or create a fake preview") {
        var habit = AssistantCommand(type: .updateHabit); habit.id = original.habits[1].id.uuidString; habit.title = original.habits[1].latest.title
        var goal = AssistantCommand(type: .updateGoal); goal.id = original.goals[0].id.uuidString; goal.end = original.goals[0].latest.end
        var cycle = AssistantCommand(type: .updateCycle); cycle.end = original.cycle.end; cycle.target = original.cycle.target
        let p = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [habit, goal, cycle]), document: original, today: "2026-10-20")
        try verify(p.candidate == original && p.changes.isEmpty)
    }
    await checkAsync("mocked Claude launcher completes prompt → decode → validated preview") {
        var a = AssistantCommand(type: .updateHabit); a.id = original.habits[1].id.uuidString; a.minute = 480
        let fixture = FixtureLauncher(try streamOutput(AssistantReply(message: "Review this time", actions: [a])))
        let invocation = ClaudeInvocation(executable: URL(fileURLWithPath: "/bin/false"), arguments: ClaudeAssistant.arguments(model: .haiku, session: UUID(), resume: false),
            environment: [:], directory: FileManager.default.temporaryDirectory, input: try ClaudeAssistant.prompt("Move meds to 08:00", document: original, today: day, shareHistory: false))
        let p = try AssistantPlanner.prepare(ClaudeAssistant.decode(try await fixture.run(invocation)), document: original, today: day)
        let calls = await fixture.calls
        try verify(calls == 1 && p.candidate.habits[1].latest.scheduledMinute == 480 && original.checkIns.isEmpty)
    }
    await checkAsync("process launcher passes the prompt on stdin with the profile environment") {
        let reply = line(["type": "result", "is_error": false, "structured_output": ["message": "ok", "actions": []]])
        let fake = try script("input=$(cat)\nprintf '%s' \"$CLAUDE_CONFIG_DIR|$1|$input\" >&2\necho '\(reply)'\n")
        defer { try? FileManager.default.removeItem(at: fake) }
        let output = try await ProcessClaudeLauncher(timeout: 20).run(ClaudeInvocation(executable: fake, arguments: ["-p"],
            environment: ["CLAUDE_CONFIG_DIR": "/tmp/profile", "PATH": "/usr/bin:/bin"], directory: FileManager.default.temporaryDirectory, input: "PROMPT_SENTINEL"))
        try verify(output.status == 0 && String(decoding: output.stderr, as: UTF8.self) == "/tmp/profile|-p|PROMPT_SENTINEL")
        let message = try ClaudeAssistant.decode(output).message
        try verify(message == "ok")
    }
    await checkAsync("cancelling or timing out the Claude process stops it without a reply") {
        let slow = try script("sleep 10\n")
        defer { try? FileManager.default.removeItem(at: slow) }
        let invocation = ClaudeInvocation(executable: slow, arguments: [], environment: ["PATH": "/usr/bin:/bin"], directory: FileManager.default.temporaryDirectory, input: "")
        let started = Date()
        let task = Task { try await ProcessClaudeLauncher(timeout: 20).run(invocation) }
        try await Task.sleep(for: .milliseconds(200)); task.cancel()
        do { _ = try await task.value; throw FeatureFailure(message: "Expected cancellation") }
        catch is CancellationError { }
        let timed = try await ProcessClaudeLauncher(timeout: 0.3).run(invocation)
        try verify(timed.timedOut && Date().timeIntervalSince(started) < 5)
        try rejects { _ = try ClaudeAssistant.decode(timed) }
    }
    if ProcessInfo.processInfo.environment["ASCEND_LIVE_CLAUDE"] == "1" {
        // Opt-in: uses the real Claude Code CLI and the personal profile, then removes its test session.
        await checkAsync("live Claude chat proposes a reviewed edit and resumes the session") {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw FeatureFailure(message: "Claude Code not found") }
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-live-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let id = UUID(), env = ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory)
            defer {
                try? FileManager.default.removeItem(at: ClaudeAssistant.transcriptURL(session: id, workspace: workspace, configDirectory: ClaudeAssistant.defaultConfigDirectory).deletingLastPathComponent())
                try? FileManager.default.removeItem(at: workspace)
            }
            let gym = original.habits.first { $0.latest.title == "Gym session" }!
            func ask(_ text: String, resume: Bool, photos: [URL] = []) async throws -> (AssistantReply, ClaudeProcessOutput) {
                let output = try await ProcessClaudeLauncher(timeout: 180).run(ClaudeInvocation(executable: executable,
                    arguments: ClaudeAssistant.arguments(model: .haiku, session: id, resume: resume), environment: env, directory: workspace,
                    input: try ClaudeAssistant.inputLine(ClaudeAssistant.prompt(text, document: original, today: day, shareHistory: true, photos: photos.count), photos: photos)))
                return (try ClaudeAssistant.decode(output), output)
            }
            let (first, output) = try await ask("Change my gym days to Tuesday, Thursday, Saturday and Sunday.", resume: false)
            try verify(ClaudeAssistant.sessionStarted(output.stdout, session: id), "Session not started")
            let transcript = ClaudeAssistant.transcriptURL(session: id, workspace: workspace, configDirectory: ClaudeAssistant.defaultConfigDirectory)
            try verify(FileManager.default.fileExists(atPath: transcript.path), "Transcript not at \(transcript.path)")
            let p = try AssistantPlanner.prepare(first, document: original, today: day)
            try verify(p.candidate.habits.first { $0.id == gym.id }?.latest.schedule.weekdays == [1, 3, 5, 7], "Unexpected proposal: \(first)")
            let (second, _) = try await ask("Which days did I just ask for? Answer in one short sentence with no actions.", resume: true)
            try verify(second.actions.isEmpty && second.message.contains("Tuesday"), "Resume lost context: \(second.message)")
            print("  live reply: \(second.message)")
            let source = try makePNG(width: 300, height: 300); defer { try? FileManager.default.removeItem(at: source) }
            let photos = ChatPhotos.folder(chat: id, workspace: workspace)
            let (third, _) = try await ask("What colour is this square? Answer with the colour name only and no actions.", resume: true,
                                           photos: [photos.appendingPathComponent(try ChatPhotos.store(source, in: photos))])
            try verify(third.actions.isEmpty && third.message.lowercased().contains("red"), "Photo not understood: \(third.message)")
            print("  live photo reply: \(third.message)")
        }
        await checkAsync("live Claude accepts medium effort on Opus, Sonnet and Haiku") {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw FeatureFailure(message: "Claude Code not found") }
            let env = ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory)
            for model in [ClaudeModel.opus, .sonnet, .haiku] {
                let output = try await ProcessClaudeLauncher(timeout: 180).run(ClaudeInvocation(executable: executable,
                    arguments: ClaudeAssistant.arguments(model: model, effort: .medium, session: nil, resume: false), environment: env,
                    directory: FileManager.default.temporaryDirectory, input: try ClaudeAssistant.inputLine("Connection test. Reply OK with no actions.")))
                let reply = try ClaudeAssistant.decode(output)
                try verify(reply.actions.isEmpty, "\(model.label) proposed actions")
                print("  \(model.label) · medium: \(reply.message)")
            }
        }
    }
    return (count, failures)
}
