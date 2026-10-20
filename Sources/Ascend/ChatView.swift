import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AscendCore

/// Ask Ascend as a full screen: saved chats on the left, the conversation in a centred column and a composer at the bottom.
struct ChatView: View {
    @ObservedObject var store: TrackerStore
    @ObservedObject var controller: ChatController
    var settings: () -> Void
    @AppStorage("ascend.chat.showList") private var showList = true
    @State private var draft = ""
    @State private var search = ""
    @State private var confirmApply = false
    @State private var pickingProgress = false
    @State private var renaming: ChatThread?
    @State private var newTitle = ""
    @State private var deleting: ChatThread?
    @State private var copied = false
    @State private var showPrivacy = false
    @FocusState private var composerFocused: Bool
    private let column: CGFloat = 760
    init(store: TrackerStore, settings: @escaping () -> Void) { self.store = store; controller = store.assistant; self.settings = settings }

    var body: some View {
        HStack(spacing: 0) {
            if showList { chatList.frame(width: 252).transition(.move(edge: .leading)) }
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Ink.line).frame(height: 1)
                if (controller.current?.messages ?? []).isEmpty && controller.proposal == nil && !controller.working { welcome } else { conversation }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !controller.working else { return false }
            controller.addPhotos(urls); return true
        }
        .onAppear { composerFocused = true }
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

    // MARK: Chat list
    private var chatList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { startNewChat() } label: {
                HStack(spacing: 8) { Image(systemName: "square.and.pencil"); Text("New chat"); Spacer(); Text("⌘N").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.muted) }
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Ink.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.accent.opacity(0.35)))
            }.buttonStyle(.plain).foregroundStyle(Ink.accent).keyboardShortcut("n", modifiers: [.command])
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Ink.muted)
                TextField("Search chats", text: $search).textFieldStyle(.plain).font(.system(size: 12))
            }.padding(.horizontal, 10).padding(.vertical, 7).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let groups = groupedThreads
                    if groups.isEmpty {
                        Text(search.isEmpty ? "Your chats will appear here." : "No chats match “\(search)”.").font(.system(size: 12)).foregroundStyle(Ink.muted).padding(.vertical, 8).padding(.horizontal, 4)
                    }
                    ForEach(groups, id: \.title) { group in
                        Kicker(group.title).padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                        ForEach(group.threads) { thread in row(thread) }
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: settings) {
                HStack(spacing: 8) { Image(systemName: "gearshape"); Text("Claude settings"); Spacer() }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 6)
            }.buttonStyle(.plain).foregroundStyle(Ink.muted)
        }.padding(14).frame(maxHeight: .infinity).background(Color.black.opacity(0.18))
            .overlay(alignment: .trailing) { Rectangle().fill(Ink.line).frame(width: 1) }
    }
    private func row(_ thread: ChatThread) -> some View {
        let selected = thread.id == controller.currentID
        return Button { controller.select(thread.id); draft = "" } label: {
            Text(thread.title).font(.system(size: 13)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(selected ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(selected ? .white : .white.opacity(0.78))
            .help("\(thread.claudeModel.label) · \(thread.messages.count) messages · \(thread.updated.formatted(.relative(presentation: .named)))")
            .contextMenu {
                Button("Rename…") { newTitle = thread.title; renaming = thread }
                Button("Delete…", role: .destructive) { deleting = thread }
            }
    }
    private var groupedThreads: [(title: String, threads: [ChatThread])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let threads = controller.archive.sorted.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) } }
        let calendar = store.engine.calendar, now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
        let buckets: [(String, (Date) -> Bool)] = [("Today", { $0 >= startOfToday }), ("Previous 7 days", { $0 >= weekAgo && $0 < startOfToday }),
                                                   ("Previous 30 days", { $0 >= monthAgo && $0 < weekAgo }), ("Older", { $0 < monthAgo })]
        return buckets.compactMap { title, test in
            let list = threads.filter { test($0.updated) }
            return list.isEmpty ? nil : (title, list)
        }
    }

    // MARK: Top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.18)) { showList.toggle() } } label: { Image(systemName: "sidebar.left").font(.system(size: 14)) }
                .buttonStyle(.plain).foregroundStyle(Ink.muted).help(showList ? "Hide chats" : "Show chats")
            Text(controller.current?.title ?? "New chat").font(.system(size: 14, weight: .medium)).lineLimit(1)
            Spacer()
            modelMenu
            effortMenu
            if let thread = controller.current, !thread.messages.isEmpty {
                Button { store.refreshDay(); controller.draftNote(today: store.today) } label: {
                    Label(controller.drafting ? "Summarizing…" : "Save as note", systemImage: "note.text.badge.plus").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(Ink.muted).disabled(controller.drafting || controller.working).help("Claude summarizes this chat into a note you can edit, then save to Notes")
                Menu {
                    Button("Save chat as note…") { store.refreshDay(); controller.draftNote(today: store.today) }.disabled(controller.drafting || controller.working)
                    Button("Copy Terminal command") { controller.copyTerminalCommand(); copied = true }.disabled(controller.transcriptCommand == nil)
                    Button("Rename…") { newTitle = thread.title; renaming = thread }
                    Divider()
                    Button("Delete chat…", role: .destructive) { deleting = thread }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Chat options")
            }
        }.padding(.horizontal, 20).frame(height: 52)
    }
    private var modelMenu: some View {
        Menu {
            ForEach(ClaudeModel.allCases, id: \.self) { model in
                Button { controller.setModel(model) } label: {
                    if model == controller.model { Label("\(model.label) · \(model.detail)", systemImage: "checkmark") } else { Text("\(model.label) · \(model.detail)") }
                }
            }
        } label: { Text(controller.model.label).font(.system(size: 11)) }
            .menuStyle(.borderlessButton).fixedSize().disabled(controller.working).help("Model for this chat")
    }
    private var effortMenu: some View {
        Menu {
            ForEach(ClaudeEffort.allCases, id: \.self) { effort in
                Button { controller.setEffort(effort) } label: {
                    if effort == controller.effort { Label(effort.label, systemImage: "checkmark") } else { Text(effort.label) }
                }
            }
        } label: { Text("\(controller.effort.label) effort").font(.system(size: 11)) }
            .menuStyle(.borderlessButton).fixedSize().disabled(controller.working).help("Effort for this chat. Higher effort thinks longer and uses more of your plan.")
    }

    // MARK: Empty chat
    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)
            HStack(spacing: 12) {
                AscendMark(size: 34)
                Text(greeting).font(.system(size: 32, weight: .medium)).tracking(-1)
            }
            Text("Ask about your goals, habits or progress, or ask for a plan change you review before it’s saved.").font(.system(size: 13)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
            composer.frame(maxWidth: 680)
            if controller.executable == nil { PrimaryButton(label: "Set up Claude", action: settings) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.text) { s in
                    Button { draft = s.text; composerFocused = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.symbol).font(.system(size: 13)).foregroundStyle(Ink.accent).frame(width: 18)
                            Text(s.text).font(.system(size: 12)).multilineTextAlignment(.leading).foregroundStyle(.white.opacity(0.85))
                            Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Ink.panel, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.line))
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: 680)
            Spacer(minLength: 20)
        }.padding(.horizontal, 28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var greeting: String {
        let hour = store.engine.calendar.component(.hour, from: Date())
        return hour < 5 ? "Up late?" : hour < 12 ? "Good morning." : hour < 17 ? "Good afternoon." : "Good evening."
    }
    private var suggestions: [(symbol: String, text: String)] {
        var list: [(String, String)] = [("chart.line.uptrend.xyaxis", "How is my cycle going so far?"), ("calendar", "Plan tomorrow around my routine")]
        if !store.document.photos.photos.isEmpty { list.append(("person.crop.rectangle.stack", "Which progress photos should I compare next?")) }
        else { list.append(("scope", "What should I focus on this week?")) }
        list.append(("arrow.triangle.2.circlepath", "Move one of my habits to a better time"))
        return list
    }

    // MARK: Conversation
    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(controller.current?.messages ?? []) { message in
                            if message.fromUser { userMessage(message) } else { assistantMessage(message) }
                        }
                        if controller.working { thinking }
                        if let proposal = controller.proposal { proposalView(proposal) }
                        if store.undoLabel == "assistant edit" {
                            Button("Undo last AI edit") { store.undoProgressAction() }.font(.system(size: 12)).buttonStyle(.borderless)
                        }
                        if controller.drafting { HStack { ProgressView().controlSize(.small); Text("Claude is summarizing this chat into a note…").font(.system(size: 12)).foregroundStyle(Ink.muted) } }
                        if let error = controller.error { errorView(error) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: column).padding(.horizontal, 28).padding(.vertical, 28).frame(maxWidth: .infinity)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: controller.currentID) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: controller.current?.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: controller.working) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: controller.proposal?.id) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            composer.frame(maxWidth: column).padding(.horizontal, 28).padding(.bottom, 16).padding(.top, 6)
        }
    }
    private func userMessage(_ message: ChatMessage) -> some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 8) {
                if let chat = controller.currentID, !message.photos.isEmpty {
                    HStack(spacing: 6) { ForEach(message.photos, id: \.self) { PhotoThumbnail(url: controller.photoURL($0, chat: chat), size: 96) } }
                }
                if !message.text.isEmpty {
                    Text(markdown(message.text)).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.contextMenu { Button("Copy text") { copy(message.text) } }
    }
    private func assistantMessage(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AscendMark(size: 26).padding(.top, 1)
            VStack(alignment: .leading, spacing: 10) {
                if let chat = controller.currentID, !message.photos.isEmpty {
                    HStack(spacing: 6) { ForEach(message.photos, id: \.self) { PhotoThumbnail(url: controller.photoURL($0, chat: chat), size: 96) } }
                }
                MessageText(text: message.text)
                HStack(spacing: 14) {
                    Button { copy(message.text) } label: { Image(systemName: "doc.on.doc") }.help("Copy")
                    Button { store.refreshDay(); controller.draftNote(focus: message.id, today: store.today) } label: { Image(systemName: "note.text.badge.plus") }
                        .help("Save this reply as a note").disabled(controller.drafting || controller.working)
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 0)
        }.contextMenu {
            Button("Save reply as note…") { store.refreshDay(); controller.draftNote(focus: message.id, today: store.today) }.disabled(controller.drafting || controller.working)
            Button("Copy text") { copy(message.text) }
        }
    }
    private var thinking: some View {
        HStack(spacing: 14) {
            AscendMark(size: 26, pulsing: true)
            Text("Thinking…").font(.system(size: 13)).foregroundStyle(Ink.muted)
            Spacer()
        }
    }
    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(error).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle") }
                .font(.system(size: 12)).foregroundStyle(.orange)
            if controller.current?.messages.last?.fromUser == true {
                Button("Retry last message") { store.refreshDay(); controller.retryLast(document: store.document, today: store.today) }.font(.system(size: 11)).disabled(controller.working)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Composer
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                if !controller.pendingPhotos.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(controller.pendingPhotos, id: \.self) { url in
                            PhotoThumbnail(url: url, size: 58).overlay(alignment: .topTrailing) {
                                Button { controller.removePendingPhoto(url) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, .black.opacity(0.7)) }
                                    .buttonStyle(.plain).offset(x: 6, y: -6).accessibilityLabel("Remove photo")
                            }
                        }
                        Spacer()
                        Text("\(controller.pendingPhotos.count)/\(ChatPhotos.maxPerMessage)").font(.system(size: 10)).foregroundStyle(Ink.muted)
                    }
                }
                TextField(controller.pendingPhotos.isEmpty ? "Message Ascend…" : "Add a message (optional)…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...10).focused($composerFocused).disabled(controller.working)
                HStack(spacing: 12) {
                    Menu {
                        Button("Choose photos…") { choosePhotos() }
                        Button("Paste from clipboard") { controller.pastePhoto() }
                        Button("From progress photos…") { pickingProgress = true }.disabled(store.document.photos.photos.isEmpty)
                    } label: { Image(systemName: "plus").font(.system(size: 13, weight: .medium)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(controller.working || controller.pendingPhotos.count >= ChatPhotos.maxPerMessage)
                        .help("Attach up to \(ChatPhotos.maxPerMessage) photos, or drag them here")
                    Button { showPrivacy.toggle() } label: { Image(systemName: "lock").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(Ink.muted)
                        .help("What Ascend sends to Claude")
                        .popover(isPresented: $showPrivacy, arrowEdge: .bottom) { privacy }
                    if copied { Text("Command copied. Paste it in Terminal.").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                    Spacer()
                    if controller.working {
                        Button { controller.cancel() } label: {
                            Image(systemName: "stop.fill").font(.system(size: 10)).frame(width: 30, height: 30).background(Color.white.opacity(0.14), in: Circle())
                        }.buttonStyle(.plain).help("Stop")
                    } else {
                        Button { send() } label: {
                            Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 30)
                                .background(canSend ? Ink.accent : Color.white.opacity(0.1), in: Circle()).foregroundStyle(canSend ? Ink.background : Ink.muted)
                        }.buttonStyle(.plain).disabled(!canSend).keyboardShortcut(.return, modifiers: [.command]).help("Send · ⌘↵")
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                .background(Ink.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(composerFocused ? Ink.accent.opacity(0.45) : Color.white.opacity(0.12)))
                .onTapGesture { composerFocused = true }
            if draft.count > ClaudeAssistant.maxPromptLength { Text("Use \(ClaudeAssistant.maxPromptLength.formatted()) characters or fewer.").font(.system(size: 11)).foregroundStyle(.orange) }
            Text("Ascend can make mistakes. Plan changes are only saved after you review them.").font(.system(size: 10)).foregroundStyle(Ink.muted).frame(maxWidth: .infinity)
        }
    }
    private var privacy: some View {
        Text((controller.shareHistory ? "Sends your plan, progress, last 14 days of check-ins and habit notes to Claude through your personal Claude profile. Urges, health and daily journal entries stay on this Mac." : "Sends your plan to Claude through your personal Claude profile. Check-ins, habit notes, urges, health and daily journal entries stay on this Mac.") + " Notes you let Ascend see are included. Photos are sent only when you attach them; location data is removed. From your Photos album, Claude sees only areas, angles and dates until you attach one.")
            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).frame(width: 320).padding(14)
    }
    private var canSend: Bool {
        !controller.working && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !controller.pendingPhotos.isEmpty) && draft.count <= ClaudeAssistant.maxPromptLength
    }
    private func send() {
        guard canSend else { return }
        store.refreshDay(); copied = false
        controller.submit(draft, document: store.document, today: store.today)
        if controller.working { draft = "" }
    }
    private func startNewChat() { controller.newChat(); draft = ""; composerFocused = true }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func choosePhotos() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.message = "Choose up to \(ChatPhotos.maxPerMessage) photos to send to Claude"
        if panel.runModal() == .OK { controller.addPhotos(panel.urls) }
    }
    private func proposalView(_ proposal: PreparedProposal) -> some View {
        let stale = proposal.baseline != store.document || proposal.day != store.today
        return VStack(alignment: .leading, spacing: 14) {
            Label("Review \(proposal.changes.count) change\(proposal.changes.count == 1 ? "" : "s")", systemImage: "checklist").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.accent)
            ForEach(proposal.changes) { change in
                VStack(alignment: .leading, spacing: 5) {
                    Text(change.title).font(.system(size: 13, weight: .medium))
                    HStack(alignment: .top, spacing: 6) { Text("Before").foregroundStyle(Ink.muted).frame(width: 44, alignment: .leading); Text(change.before).foregroundStyle(Ink.muted) }
                    HStack(alignment: .top, spacing: 6) { Text("After").foregroundStyle(Ink.accent).frame(width: 44, alignment: .leading); Text(change.after) }
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Line()
            }
            if stale { Text("Your plan or date changed. Send a new message to refresh this preview.").font(.system(size: 12)).foregroundStyle(.orange) }
            HStack {
                Text("Saved locally with a backup and Undo.").font(.system(size: 10)).foregroundStyle(Ink.muted)
                Spacer()
                Button("Discard") { controller.discardProposal() }.font(.system(size: 12))
                PrimaryButton(label: "Apply changes") { if proposal.isDestructive { confirmApply = true } else { controller.apply(to: store) } }.disabled(stale || controller.working)
            }
        }.padding(16).padding(.leading, 40).background(Ink.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.accent.opacity(0.3)))
    }
}

/// A reply's Markdown with block structure: headings, bullet and numbered lists and paragraphs; inline styles via `markdown()`.
struct MessageText: View {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let line): Text(markdown(line)).font(.system(size: 15, weight: .semibold)).padding(.top, 4)
                case .item(let marker, let line, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(Ink.muted).frame(minWidth: 14, alignment: .trailing)
                        Text(markdown(line))
                    }.padding(.leading, CGFloat(depth) * 18)
                case .paragraph(let line): Text(markdown(line))
                }
            }
        }.font(.system(size: 14)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
    enum Block { case heading(String), item(String, String, Int), paragraph(String) }
    private var blocks: [Block] {
        var result: [Block] = [], paragraph: [String] = []
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] } }
        for raw in text.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count, line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush(); result.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); result.append(.item("•", String(line.dropFirst(2)), indent / 2))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].count <= 3, Int(line[..<dot]) != nil, line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); result.append(.item(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...]), indent / 2))
            } else { paragraph.append(line) }
        }
        flush()
        return result
    }
}

/// Ascend's "A↗" mark in a small rounded tile; it pulses while Claude is thinking.
struct AscendMark: View {
    var size: CGFloat
    var pulsing = false
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text("A↗").font(.system(size: size * 0.42, weight: .bold)).tracking(-size * 0.04).foregroundStyle(Ink.background)
            .frame(width: size, height: size).background(Ink.accent, in: RoundedRectangle(cornerRadius: size * 0.3))
            .opacity(pulsing && dim ? 0.45 : 1)
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityHidden(true)
    }
}
