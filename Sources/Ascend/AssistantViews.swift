import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AscendCore

/// A stored or pending chat photo; click opens it in the default viewer.
struct PhotoThumbnail: View {
    var url: URL
    var size: CGFloat
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(Ink.muted) }
            }.frame(width: size, height: size).background(Ink.panel).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.line))
        }.buttonStyle(.plain).help("Open photo")
    }
}

struct AssistantPanel: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var controller: ChatController
    var close: () -> Void
    var settings: () -> Void
    @State private var draft = ""
    @State private var confirmApply = false
    @State private var loggedUrge = false
    @State private var pickingProgress = false
    @State private var showChats = false
    @State private var renaming: ChatThread?
    @State private var newTitle = ""
    @State private var deleting: ChatThread?
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(showChats ? "Chats" : "Ask Ascend").font(.system(size: 20, weight: .medium))
                    Text(showChats ? "\(controller.archive.threads.count) saved" : controller.current?.title ?? "New chat").font(.system(size: 10)).foregroundStyle(Ink.muted).lineLimit(1)
                }
                Spacer()
                Button { showChats.toggle() } label: { Image(systemName: showChats ? "bubble.left" : "clock.arrow.circlepath").frame(width: 26, height: 28) }.help(showChats ? "Back to chat" : "Chat history")
                Button { controller.newChat(); showChats = false; draft = "" } label: { Image(systemName: "square.and.pencil").frame(width: 26, height: 28) }.help("New chat")
                Button(action: settings) { Image(systemName: "gearshape").frame(width: 26, height: 28) }.help("Claude settings")
                Button(action: close) { Image(systemName: "xmark").frame(width: 26, height: 28) }.accessibilityLabel("Close AI panel")
            }.buttonStyle(.plain)
            if !showChats { toolbar }
            Line()
            if showChats { chatList } else { conversation }
        }.padding(22)
            .dropDestination(for: URL.self) { urls, _ in
                guard !showChats, !controller.working else { return false }
                controller.addPhotos(urls); return true
            }.frame(width: 400).frame(maxHeight: .infinity).background(Ink.background)
            .overlay(alignment: .leading) { Rectangle().fill(Ink.line).frame(width: 1) }
            .confirmationDialog("Apply this change to your plan?", isPresented: $confirmApply, titleVisibility: .visible) {
                Button("Apply reviewed changes", role: .destructive) { controller.apply(to: store) }
                Button("Keep reviewing", role: .cancel) {}
            } message: { Text("This proposal includes clearing entries, archiving a habit or restarting the cycle. The preview lists its effects. A safety backup and Undo are created before saving.") }
            .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete chat", role: .destructive) { if let id = deleting?.id { controller.delete(id) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("Removes the chat from Ascend, its photos and its Claude Code session. Your plan is not affected.") }
            .sheet(item: $controller.noteDraft) { NoteEditor(store: store, note: $0) }
            .sheet(isPresented: $pickingProgress) {
                ProgressPhotoPicker(store: store, limit: max(1, ChatPhotos.maxPerMessage - controller.pendingPhotos.count)) { store.askAscend(about: $0) }
            }
            .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Save") { if let id = renaming?.id { controller.rename(id, to: newTitle) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ClaudeModel.allCases, id: \.self) { model in
                    Button { controller.setModel(model) } label: {
                        if model == controller.model { Label("\(model.label) · \(model.detail)", systemImage: "checkmark") } else { Text("\(model.label) · \(model.detail)") }
                    }
                }
            } label: { Label("Claude · \(controller.model.label)", systemImage: "sparkles").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).fixedSize().disabled(controller.working).help("Model for this chat")
            Menu {
                ForEach(ClaudeEffort.allCases, id: \.self) { effort in
                    Button { controller.setEffort(effort) } label: {
                        if effort == controller.effort { Label(effort.label, systemImage: "checkmark") } else { Text(effort.label) }
                    }
                }
            } label: { Label("Effort · \(controller.effort.label)", systemImage: "gauge.with.dots.needle.33percent").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).fixedSize().disabled(controller.working).help("Effort for this chat. Higher effort thinks longer and uses more of your plan.")
            Spacer()
            if let thread = controller.current, !thread.messages.isEmpty {
                Button { store.refreshDay(); controller.draftNote(today: store.today) } label: {
                    Label(controller.drafting ? "Summarizing…" : "Save as note", systemImage: "note.text.badge.plus").font(.system(size: 11))
                }.buttonStyle(.plain).disabled(controller.drafting || controller.working).help("Claude summarizes this chat into a note you can edit, then save to Notes")
            }
            if let thread = controller.current {
                Menu {
                    Button("Save chat as note…") { store.refreshDay(); controller.draftNote(today: store.today) }.disabled(thread.messages.isEmpty || controller.drafting || controller.working)
                    Button("Copy Terminal command") { controller.copyTerminalCommand(); copied = true }.disabled(controller.transcriptCommand == nil)
                    Button("Rename…") { newTitle = thread.title; renaming = thread }
                    Divider()
                    Button("Delete chat…", role: .destructive) { deleting = thread }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Chat options")
            }
        }
    }
    private var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if controller.archive.threads.isEmpty { Text("No chats yet. Start one and it will be saved here.").font(.system(size: 12)).foregroundStyle(Ink.muted).padding(.vertical, 8) }
                ForEach(controller.archive.sorted) { thread in
                    Button { controller.select(thread.id); showChats = false } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).font(.system(size: 13, weight: thread.id == controller.currentID ? .semibold : .regular)).lineLimit(1)
                            Text("\(thread.claudeModel.label) · \(thread.claudeEffort.label) · \(thread.updated.formatted(.relative(presentation: .named))) · \(thread.messages.count) messages").font(.system(size: 10)).foregroundStyle(Ink.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(thread.id == controller.currentID ? Ink.accent.opacity(0.12) : Ink.panel, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename…") { newTitle = thread.title; renaming = thread }
                        Button("Delete…", role: .destructive) { deleting = thread }
                    }
                }
            }
        }
    }
    @ViewBuilder private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let messages = controller.current?.messages ?? []
                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Talk it through.").font(.system(size: 18, weight: .medium)).tracking(-0.4)
                            Text("Chat with Claude about your goals, habits and week. Ask it to change your plan and it prepares a preview; nothing is saved until you apply it.").font(.system(size: 12)).foregroundStyle(Ink.muted)
                            ForEach(["How is my cycle going so far?", "Add a note to Take medication: after breakfast", "Move my Monday gym session to Tuesday"], id: \.self) { example in
                                Button { draft = example } label: { HStack { Text(example).font(.system(size: 12)).multilineTextAlignment(.leading); Spacer(); Image(systemName: "arrow.up.left").font(.system(size: 10)) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Ink.panel, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                            }
                            if controller.executable == nil { PrimaryButton(label: "Set up Claude", fullWidth: true, action: settings) }
                        }.padding(.vertical, 6)
                    }
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 7) {
                            Kicker(message.fromUser ? "You" : "Ascend")
                            if let chat = controller.currentID, !message.photos.isEmpty {
                                HStack(spacing: 6) { ForEach(message.photos, id: \.self) { PhotoThumbnail(url: controller.photoURL($0, chat: chat), size: 72) } }
                            }
                            if !message.text.isEmpty {
                                Text(markdown(message.text)).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(message.fromUser ? Ink.accent.opacity(0.1) : Ink.panel, in: RoundedRectangle(cornerRadius: 9))
                            .contextMenu {
                                if !message.fromUser { Button("Save reply as note…") { store.refreshDay(); controller.draftNote(focus: message.id, today: store.today) }.disabled(controller.drafting || controller.working) }
                                Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) }
                            }
                    }
                    if let proposal = controller.proposal { proposalView(proposal) }
                    if store.undoLabel == "assistant edit" {
                        Button("Undo last AI edit") { store.undoProgressAction() }.font(.system(size: 12)).buttonStyle(.borderless)
                    }
                    if controller.drafting { HStack { ProgressView().controlSize(.small); Text("Claude is summarizing this chat into a note…").font(.system(size: 12)).foregroundStyle(Ink.muted) } }
                    if controller.working { HStack { ProgressView().controlSize(.small); Text("Claude is thinking…").font(.system(size: 12)).foregroundStyle(Ink.muted); Spacer(); Button("Stop") { controller.cancel() }.font(.system(size: 11)) } }
                    if let error = controller.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            if messages.last?.fromUser == true {
                                Button("Retry last message") { store.refreshDay(); controller.retryLast(document: store.document, today: store.today) }.font(.system(size: 11)).disabled(controller.working)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: controller.current?.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: controller.working) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        Spacer(minLength: 0)
        Text((controller.shareHistory ? "Sends your plan, progress, last 14 days of check-ins and habit notes to Claude through your personal Claude profile. Urges, health and daily journal entries stay on this Mac." : "Sends your plan to Claude through your personal Claude profile. Check-ins, habit notes, urges, health and daily journal entries stay on this Mac.") + " Notes you let Ascend see are included." + " Photos are sent only when you attach them; location data is removed. From your Photos album, Claude sees only areas, angles and dates until you attach one.").font(.system(size: 10)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        if !controller.pendingPhotos.isEmpty {
            HStack(spacing: 8) {
                ForEach(controller.pendingPhotos, id: \.self) { url in
                    PhotoThumbnail(url: url, size: 54).overlay(alignment: .topTrailing) {
                        Button { controller.removePendingPhoto(url) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .black.opacity(0.7)) }
                            .buttonStyle(.plain).offset(x: 5, y: -5).accessibilityLabel("Remove photo")
                    }
                }
                Spacer()
                Text("\(controller.pendingPhotos.count)/\(ChatPhotos.maxPerMessage)").font(.system(size: 10)).foregroundStyle(Ink.muted)
            }.padding(.top, 4)
        }
        TextField(controller.pendingPhotos.isEmpty ? "Message Claude…" : "Add a message (optional)…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...8).font(.system(size: 13)).disabled(controller.working)
        HStack {
            Menu {
                Button("Choose photos…") { choosePhotos() }
                Button("Paste from clipboard") { controller.pastePhoto() }
                Button("From progress photos…") { pickingProgress = true }.disabled(store.document.photos.photos.isEmpty)
            } label: { Label("Photo", systemImage: "photo.badge.plus").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).fixedSize().disabled(controller.working || controller.pendingPhotos.count >= ChatPhotos.maxPerMessage)
                .help("Attach up to \(ChatPhotos.maxPerMessage) photos, or drag them onto this panel")
            Button { if store.recordUrge() != nil { loggedUrge = true } } label: { Label("Urge", systemImage: "circle.dotted").font(.system(size: 11)) }.buttonStyle(.plain).help("Log an urge locally")
            if copied { Text("Command copied. Paste it in Terminal.").font(.system(size: 10)).foregroundStyle(Ink.muted) }
            Spacer()
            PrimaryButton(label: "Send  ⌘↵") { send() }.keyboardShortcut(.return, modifiers: [.command])
                .disabled(controller.working || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.pendingPhotos.isEmpty) || draft.count > ClaudeAssistant.maxPromptLength)
        }
        if loggedUrge { Text("Urge saved locally. Details are in Urges.").font(.system(size: 10)).foregroundStyle(Ink.muted) }
        if draft.count > ClaudeAssistant.maxPromptLength { Text("Use \(ClaudeAssistant.maxPromptLength.formatted()) characters or fewer.").font(.system(size: 11)).foregroundStyle(.orange) }
    }
    private func send() {
        store.refreshDay(); copied = false
        controller.submit(draft, document: store.document, today: store.today)
        if controller.working { draft = "" }
    }
    private func choosePhotos() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.message = "Choose up to \(ChatPhotos.maxPerMessage) photos to send to Claude"
        if panel.runModal() == .OK { controller.addPhotos(panel.urls) }
    }
    private func proposalView(_ proposal: PreparedProposal) -> some View {
        let stale = proposal.baseline != store.document || proposal.day != store.today
        return VStack(alignment: .leading, spacing: 14) {
            Kicker("Review · \(proposal.changes.count) changes")
            ForEach(proposal.changes) { change in
                VStack(alignment: .leading, spacing: 6) {
                    Text(change.title).font(.system(size: 13, weight: .medium))
                    Text("Before: \(change.before)").foregroundStyle(Ink.muted)
                    Text("After: \(change.after)")
                }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Line()
            }
            if stale { Text("Your plan or date changed. Send a new message to refresh this preview.").font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Button("Discard") { controller.discardProposal() }.font(.system(size: 11))
                Spacer(); PrimaryButton(label: "Apply changes") { if proposal.isDestructive { confirmApply = true } else { controller.apply(to: store) } }.disabled(stale || controller.working)
            }
            Text("Saved locally with a backup and Undo.").font(.system(size: 10)).foregroundStyle(Ink.muted)
        }.padding(14).background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.accent.opacity(0.3)))
    }
}
struct ClaudeSettingsEditor: View {
    @ObservedObject var controller: ChatController
    @Environment(\.dismiss) private var dismiss
    init(store: TrackerStore) { controller = store.assistant }
    var body: some View {
        EditorShell(title: "Claude settings") {
            Text("Ask Ascend runs on your own Claude Code install and account, the same as `claude --personal` in Terminal. There is no API key to manage.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            FieldGroup(label: "Claude Code") {
                Text(controller.executable?.path ?? "Not found. Install Claude Code or enter its path below.").font(.system(size: 11, design: .monospaced)).foregroundStyle(controller.executable == nil ? .orange : Ink.muted).textSelection(.enabled)
            }
            FieldGroup(label: "Custom path (optional)") { TextField("Detected automatically", text: $controller.executableOverride).labelsHidden() }
            FieldGroup(label: "Claude profile folder") { TextField(ClaudeAssistant.defaultConfigDirectory, text: $controller.configDirectory).labelsHidden() }
            Text("~/.claude-personal is your personal account. If Claude says you aren’t signed in, run `claude --personal` in Terminal once and sign in.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            FieldGroup(label: "Model for new chats") {
                Picker("Model for new chats", selection: $controller.defaultModel) { ForEach(ClaudeModel.allCases, id: \.self) { Text("\($0.label) · \($0.detail)").tag($0) } }.labelsHidden()
            }
            FieldGroup(label: "Effort for new chats") {
                Picker("Effort for new chats", selection: $controller.defaultEffort) { ForEach(ClaudeEffort.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden()
            }
            Text("Applies to every model. Medium suits most chats; higher effort thinks longer and uses more of your plan. Each chat’s effort can be changed from its menu.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Toggle("Share recent check-ins, progress and habit notes", isOn: $controller.shareHistory).font(.system(size: 12))
            Text("Lets Claude discuss how your cycle is actually going. Your plan is always shared. Urge logs, health data and journal or caffeine entries are never sent.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            HStack {
                Button(controller.working ? "Testing…" : "Send test message") { controller.testConnection() }.disabled(controller.working || controller.executable == nil)
                if controller.working { Button("Cancel") { controller.cancel() } }
            }
            Text(controller.connectionStatus).font(.system(size: 11)).foregroundStyle(Ink.muted)
            if let error = controller.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
            Line()
            Text("Chats are saved on this Mac in \(controller.workspace.path)/chats.json, outside tracker backups. Each chat is also a Claude Code session; use Copy Terminal command in a chat’s menu to continue it in Terminal. Usage counts toward your Claude plan.").font(.system(size: 11)).foregroundStyle(Ink.muted).textSelection(.enabled)
        } actions: { HStack { Spacer(); PrimaryButton(label: "Done") { dismiss() } } }
    }
}
