import Foundation
import AscendCore

private struct NoteFailure: Error { let message: String }
private func expect(_ test: Bool, _ message: String = "Assertion failed") throws { if !test { throw NoteFailure(message: message) } }
private func refuses(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw NoteFailure(message: "Expected rejection")
}

func runNoteChecks() async -> (count: Int, failures: Int) {
    var count = 0, failures = 0
    func check(_ name: String, _ body: () throws -> Void) {
        count += 1
        do { try body(); print("PASS: \(name)") } catch { failures += 1; print("FAIL: \(name): \(error)") }
    }
    let day = "2026-10-20"
    let original = TrackerDocument.seeded(today: "2026-10-18")
    let chat = UUID()

    check("Claude's note draft is tidied into a note; plans and decisions are shared by default") {
        let draft = NoteDraft(kind: "PLAN", title: "  Morning gym switch  ", body: " - You move gym to 7am ", actions: [" Pack bag at night ", "  ", String(repeating: "x", count: 300)])
        let note = draft.note(day: day, chatID: chat)
        try expect(note.kind == .plan && note.title == "Morning gym switch" && note.body == "- You move gym to 7am" && note.chatID == chat)
        try expect(note.actions.count == 2 && note.actions[0] == "Pack bag at night" && note.actions[1].count == JournalNote.maxAction)
        try expect(note.shareWithClaude && !NoteDraft(kind: "journal", title: "", body: "").note(day: day, chatID: nil).shareWithClaude)
        try expect(NoteDraft(kind: "nonsense", title: "", body: "").note(day: day, chatID: nil).title == "Chat summary")
    }
    check("notes validate, sort pinned first and only shared ones reach Claude") {
        var doc = original
        var old = JournalNote(kind: .decision, title: "Old decision", body: "b", day: "2026-10-18", now: Date(timeIntervalSince1970: 1_792_300_000))
        old.pinned = true
        let privateEntry = JournalNote(kind: .journal, title: "PRIVATE_SENTINEL", body: "feelings", day: day, now: Date(timeIntervalSince1970: 1_792_500_000))
        let plan = JournalNote(kind: .plan, title: "Gym plan", body: "- 7am", actions: ["Pack bag"], day: day, now: Date(timeIntervalSince1970: 1_792_400_000), chatID: chat)
        doc.notes.notes = [privateEntry, plan, old]
        try doc.validate()
        try expect(doc.notes.sorted.map(\.title) == ["Old decision", "PRIVATE_SENTINEL", "Gym plan"])
        try expect(doc.notes.forClaude().map(\.title) == ["Old decision", "Gym plan"])
        let context = String(decoding: try ClaudeAssistant.contextData(document: doc, today: day), as: UTF8.self)
        try expect(context.contains("Gym plan") && context.contains("Pack bag") && !context.contains("PRIVATE_SENTINEL"), "Private notes stay out of chats")
        try expect(try JSONDecoder().decode(TrackerDocument.self, from: JSONEncoder().encode(doc)).notes == doc.notes)
        for broken in [{ var n = plan; n.title = " "; return n }(), { var n = plan; n.body = String(repeating: "x", count: 8001); return n }(),
                       { var n = plan; n.actions = Array(repeating: "a", count: 21); return n }(), { var n = plan; n.day = "nope"; return n }()] as [JournalNote] {
            var bad = original; bad.notes.notes = [broken]; try refuses { try bad.validate() }
        }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["notes"] = nil
        try expect(try JSONDecoder().decode(TrackerDocument.self, from: JSONSerialization.data(withJSONObject: json)).notes.notes.isEmpty)
    }
    check("save_note from a chat is a reviewed change linked to that chat") {
        var action = AssistantCommand(type: .saveNote)
        action.noteKind = "decision"; action.title = "Stop late coffee"; action.note = "- You stop coffee after 2pm"; action.items = ["Switch to green tea"]
        let proposal = try AssistantPlanner.prepare(AssistantReply(message: "Ready to save.", actions: [action]), document: original, today: day, chat: chat)
        try expect(proposal.changes.first?.title == "Save decision note: Stop late coffee" && proposal.changes.first?.after.contains("Ascend can refer") == true)
        let doc = try proposal.resolve(current: original, today: day)
        let note = doc.notes.notes.first
        try expect(note?.chatID == chat && note?.actions == ["Switch to green tea"] && note?.day == day && note?.shareWithClaude == true)
        for broken in [{ var a = action; a.noteKind = nil; return a }(), { var a = action; a.title = nil; return a }(), { var a = action; a.note = String(repeating: "x", count: 9000); return a }()] as [AssistantCommand] {
            try refuses { _ = try AssistantPlanner.prepare(AssistantReply(message: "", actions: [broken]), document: original, today: day) }
        }
        let schema = ClaudeAssistant.responseSchemaJSON
        try expect(schema.contains("save_note") && schema.contains("noteKind"))
    }
    check("note drafts run unsaved and send the chat, focused on one reply when asked") {
        let args = ClaudeAssistant.noteArguments(model: .haiku, effort: .medium)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        try expect(args.contains("--no-session-persistence") && value("--tools") == "" && value("--model") == "claude-haiku-5-5")
        let messages = [ChatMessage(fromUser: true, text: "Should I gym in the morning?"), ChatMessage(fromUser: false, text: "REPLY_SENTINEL: yes, 7am.")]
        let whole = try ClaudeAssistant.noteInput(messages: messages, today: day)
        try expect(whole.contains("USER: Should I gym") && whole.contains("ASCEND: REPLY_SENTINEL") && whole.contains("whole chat"))
        let focused = try ClaudeAssistant.noteInput(messages: messages, focus: messages[1], today: day)
        try expect(focused.contains("THIS reply"))
        let long = (0..<200).map { ChatMessage(fromUser: $0 % 2 == 0, text: "message \($0) " + String(repeating: "x", count: 600)) }
        let trimmed = try ClaudeAssistant.noteInput(messages: long, today: day)
        try expect(trimmed.contains("earlier messages omitted") && trimmed.contains("message 199") && !trimmed.contains("message 0 "), "Long chats keep the newest messages")
        try refuses { _ = try ClaudeAssistant.noteInput(messages: [], today: day) }
        let structured: [String: Any] = ["kind": "insight", "title": "Afternoon urges", "body": "- Most urges come after lunch", "actions": []]
        let line = String(data: try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "structured_output": structured]), encoding: .utf8)!
        let draft = try ClaudeAssistant.decodeNote(ClaudeProcessOutput(status: 0, stdout: Data(line.utf8)))
        try expect(draft.note(day: day, chatID: nil).kind == .insight && draft.title == "Afternoon urges")
    }
    if ProcessInfo.processInfo.environment["ASCEND_LIVE_CLAUDE"] == "1" {
        count += 1
        do {
            guard let executable = ClaudeAssistant.locateExecutable(override: "") else { throw NoteFailure(message: "Claude Code not found") }
            let messages = [ChatMessage(fromUser: true, text: "I keep skipping evening gym because I'm tired after work. Should I switch?"),
                            ChatMessage(fromUser: false, text: "Mornings would suit you: you wake at 6. Try gym at 6:30 on Mon, Wed, Fri, Sat and pack your bag the night before."),
                            ChatMessage(fromUser: true, text: "Ok let's do that from Monday 26 Oct.")]
            let output = try await ProcessClaudeLauncher(timeout: 180).run(ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.noteArguments(model: .haiku, effort: .medium),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: ClaudeAssistant.defaultConfigDirectory),
                directory: FileManager.default.temporaryDirectory, input: try ClaudeAssistant.noteInput(messages: messages, today: day)))
            let note = try ClaudeAssistant.decodeNote(output).note(day: day, chatID: chat)
            print("  live note: [\(note.kind.rawValue)] \(note.title) · \(note.actions.count) actions\n\(note.body.prefix(400))")
            try expect([.plan, .decision].contains(note.kind) && note.body.localizedCaseInsensitiveContains("6:30") && !note.actions.isEmpty)
            print("PASS: live Claude summarizes a chat into a note")
        } catch { failures += 1; print("FAIL: live Claude summarizes a chat into a note: \(error)") }
    }
    return (count, failures)
}
