import SwiftUI
import AscendCore

struct NotesView: View {
    @ObservedObject var store: TrackerStore
    @State private var filter: NoteKind?
    @State private var search = ""
    @State private var editing: JournalNote?
    private var visible: [JournalNote] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return store.document.notes.sorted.filter { note in
            (filter == nil || note.kind == filter) && (query.isEmpty || [note.title, note.body, note.actions.joined(separator: " ")].contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker("Plans, decisions and reflections worth keeping")
                        Text("Save a chat with Ask Ascend as a note, or write one here. Notes marked “Ascend can see” are remembered in later chats.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    PrimaryButton(label: "New note") { editing = JournalNote(kind: .journal, day: store.today) }
                }
                HStack {
                    Picker("Type", selection: $filter) {
                        Text("All").tag(NoteKind?.none)
                        ForEach(NoteKind.allCases, id: \.self) { Text($0.label).tag(NoteKind?.some($0)) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 380)
                    Spacer()
                    TextField("Search notes", text: $search).textFieldStyle(.roundedBorder).frame(width: 220).font(.system(size: 12))
                }
                if visible.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.document.notes.notes.isEmpty ? "No notes yet." : "No notes match.").font(.system(size: 18, weight: .semibold))
                        Text("In Ask Ascend, open a chat’s ••• menu → Save chat as note, or right-click a reply → Save reply as note. Claude drafts a summary; you edit it before saving.").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).panel()
                }
                ForEach(visible) { note in
                    Button { editing = note } label: { NoteRow(note: note, engine: store.engine) }.buttonStyle(.plain)
                        .contextMenu {
                            Button(note.pinned ? "Unpin" : "Pin") { var n = note; n.pinned.toggle(); store.saveNote(n) }
                            Button(note.shareWithClaude ? "Hide from Ascend" : "Let Ascend see this") { var n = note; n.shareWithClaude.toggle(); store.saveNote(n) }
                            if let chat = note.chatID, store.assistant.archive.thread(chat) != nil { Button("Open chat") { openChat(chat) } }
                        }
                }
                Text("Notes are saved in your tracker data and backups. Only notes marked “Ascend can see” (pinned first, then the 12 most recent) are sent with your chats.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            }.padding(.bottom, 10)
        }
        .sheet(item: $editing) { NoteEditor(store: store, note: $0, openChat: openChat) }
    }
    private func openChat(_ id: UUID) { store.assistant.select(id); store.pendingScreen = "Assistant" }
}
private struct NoteRow: View {
    var note: JournalNote
    var engine: TrackerEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(note.kind.label, systemImage: note.kind.symbol).font(.system(size: 11)).foregroundStyle(Ink.accent)
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                Text(note.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if note.shareWithClaude { Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Ink.muted).help("Ascend can see this note") }
                Text(dateText(note.day, engine: engine, pattern: "d MMM")).font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            if !note.body.isEmpty {
                Text(markdown(note.body)).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            if !note.actions.isEmpty {
                Text(note.actions.prefix(3).map { "☐ \($0)" }.joined(separator: "   ") + (note.actions.count > 3 ? "   +\(note.actions.count - 3)" : "")).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel(padding: 14)
    }
}
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

/// Review and edit a note before saving: drafts from Claude, existing notes and new ones.
struct NoteEditor: View {
    @ObservedObject var store: TrackerStore
    @State var note: JournalNote
    var openChat: ((UUID) -> Void)?
    @State private var actions = ""
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss
    init(store: TrackerStore, note: JournalNote, openChat: ((UUID) -> Void)? = nil) {
        self.store = store; _note = State(initialValue: note); self.openChat = openChat
        _actions = State(initialValue: note.actions.joined(separator: "\n"))
    }
    private var saved: Bool { store.document.notes.notes.contains { $0.id == note.id } }
    var body: some View {
        EditorShell(title: saved ? "Edit note" : "Save note") {
            Picker("Type", selection: Binding(get: { note.kind }, set: { kind in
                // A new note follows its type's default visibility until the user changes it.
                if !saved && note.shareWithClaude == note.kind.sharedByDefault { note.shareWithClaude = kind.sharedByDefault }
                note.kind = kind
            })) { ForEach(NoteKind.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            FieldGroup(label: "Title") { TextField("Title", text: $note.title).labelsHidden() }
            FieldGroup(label: "Note") {
                TextEditor(text: $note.body).font(.system(size: 12)).frame(minHeight: 170).scrollContentBackground(.hidden).padding(6).background(Ink.panel, in: RoundedRectangle(cornerRadius: 6))
            }
            FieldGroup(label: "Action items (one per line)") {
                TextEditor(text: $actions).font(.system(size: 12)).frame(minHeight: 60).scrollContentBackground(.hidden).padding(6).background(Ink.panel, in: RoundedRectangle(cornerRadius: 6))
            }
            Toggle("Ascend can see this in later chats", isOn: $note.shareWithClaude).font(.system(size: 12))
            Toggle("Pin to the top", isOn: $note.pinned).font(.system(size: 12))
            HStack {
                Text(dateText(note.day, engine: store.engine)).font(.system(size: 11)).foregroundStyle(Ink.muted)
                if let chat = note.chatID, let thread = store.assistant.archive.thread(chat) {
                    Text("· from “\(thread.title)”").font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
                    if let openChat { Button("Open chat") { dismiss(); openChat(chat) }.font(.system(size: 11)) }
                }
            }
            if let problem { Text(problem).font(.system(size: 11)).foregroundStyle(.orange) }
        } actions: {
            HStack {
                if saved { Button("Delete…") { confirmDelete = true } }
                Spacer()
                Button("Cancel") { dismiss() }
                PrimaryButton(label: saved ? "Save" : "Save note") {
                    var n = note; n.actions = actions.split(whereSeparator: \.isNewline).map(String.init)
                    if store.saveNote(n) { dismiss() }
                }.disabled(problem != nil)
            }
        }
        .confirmationDialog("Delete “\(note.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete note", role: .destructive) { store.deleteNote(note.id); dismiss() }; Button("Cancel", role: .cancel) {}
        } message: { Text("The chat it came from is kept. Undo is available until your next edit.") }
    }
    private var problem: String? {
        let lines = actions.split(whereSeparator: \.isNewline)
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a title." }
        if note.title.count > JournalNote.maxTitle { return "Use a title of 120 characters or fewer." }
        if note.body.count > JournalNote.maxBody { return "Keep the note under 8,000 characters." }
        if lines.count > JournalNote.maxActions || lines.contains(where: { $0.count > JournalNote.maxAction }) { return "Use up to 20 action items of 200 characters or fewer." }
        return nil
    }
}
