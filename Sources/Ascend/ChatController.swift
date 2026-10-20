import SwiftUI
import AppKit
import AscendCore

@MainActor final class ChatController: ObservableObject {
    @Published private(set) var archive: ChatArchive
    @Published private(set) var currentID: UUID?
    /// Model and effort for the next new chat; an open chat keeps its own.
    @Published var draftModel: ClaudeModel
    @Published var draftEffort: ClaudeEffort
    /// Photos picked for the next message; they are copied into the chat when it is sent.
    @Published private(set) var pendingPhotos: [URL] = []
    /// What each attached progress photo shows, added to the message so Claude knows which photo is which.
    private var pendingCaptions: [URL: String] = [:]
    @Published private(set) var working = false
    @Published private(set) var proposal: PreparedProposal?
    @Published var error: String?
    @Published private(set) var connectionStatus = "No connection test yet"
    @Published var executableOverride: String { didSet { defaults.set(executableOverride, forKey: "claude.executable") } }
    @Published var configDirectory: String { didSet { defaults.set(configDirectory, forKey: "claude.configDirectory") } }
    @Published var defaultModel: ClaudeModel { didSet { defaults.set(defaultModel.rawValue, forKey: "claude.defaultModel") } }
    @Published var defaultEffort: ClaudeEffort { didSet { defaults.set(defaultEffort.rawValue, forKey: "claude.defaultEffort") } }
    @Published var shareHistory: Bool { didSet { defaults.set(shareHistory, forKey: "claude.shareHistory") } }
    let workspace: URL
    private let archiveURL: URL
    private let launcher: any ClaudeLauncher
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(folder: URL, launcher: any ClaudeLauncher = ProcessClaudeLauncher()) {
        workspace = folder; archiveURL = folder.appendingPathComponent("chats.json"); self.launcher = launcher
        // QA runs keep their preferences apart from the personal profile.
        defaults = ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil ? .standard : UserDefaults(suiteName: "com.abdul.ascend.qa")!
        executableOverride = defaults.string(forKey: "claude.executable") ?? ""
        configDirectory = defaults.string(forKey: "claude.configDirectory") ?? ClaudeAssistant.defaultConfigDirectory
        let model = defaults.string(forKey: "claude.defaultModel").flatMap(ClaudeModel.init(rawValue:)) ?? ClaudeAssistant.defaultModel
        defaultModel = model; draftModel = model
        let effort = defaults.string(forKey: "claude.defaultEffort").flatMap(ClaudeEffort.init(rawValue:)) ?? ClaudeAssistant.defaultEffort
        defaultEffort = effort; draftEffort = effort
        shareHistory = defaults.object(forKey: "claude.shareHistory") as? Bool ?? true
        let loaded = ChatArchive.load(from: archiveURL)
        archive = loaded.archive; error = loaded.notice
        currentID = archive.sorted.first?.id
    }
    var current: ChatThread? { archive.thread(currentID) }
    var model: ClaudeModel { current?.claudeModel ?? draftModel }
    var effort: ClaudeEffort { current?.claudeEffort ?? draftEffort }
    var executable: URL? { ClaudeAssistant.locateExecutable(override: executableOverride) }
    var transcriptCommand: String? { current.flatMap { $0.sessionStarted ? ClaudeAssistant.terminalCommand(session: $0.id, workspace: workspace) : nil } }
    func photoURL(_ name: String, chat: UUID) -> URL { ChatPhotos.folder(chat: chat, workspace: workspace).appendingPathComponent(name) }

    func newChat() { cancel(); currentID = nil; proposal = nil; error = nil; draftModel = defaultModel; draftEffort = defaultEffort }
    func select(_ id: UUID) {
        guard id != currentID else { return }
        cancel(); currentID = id; proposal = nil; error = nil
    }
    func setModel(_ model: ClaudeModel) {
        guard let id = currentID else { draftModel = model; return }
        archive.update(id) { $0.model = model.rawValue }; persist()
    }
    func setEffort(_ effort: ClaudeEffort) {
        guard let id = currentID else { draftEffort = effort; return }
        archive.update(id) { $0.effort = effort.rawValue }; persist()
    }
    func rename(_ id: UUID, to title: String) { archive.rename(id, to: title); persist() }
    /// Removes the chat here, its photos and its Claude Code session transcript.
    func delete(_ id: UUID) {
        if id == currentID { cancel(); proposal = nil; error = nil }
        try? FileManager.default.removeItem(at: ClaudeAssistant.transcriptURL(session: id, workspace: workspace, configDirectory: configDirectory))
        try? FileManager.default.removeItem(at: ChatPhotos.folder(chat: id, workspace: workspace))
        archive.remove(id); persist()
        if id == currentID { currentID = archive.sorted.first?.id }
    }
    func copyTerminalCommand() {
        guard let command = transcriptCommand else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
    }

    func addPhotos(_ urls: [URL]) {
        let images = urls.filter(ChatPhotos.isImage)
        if images.count < urls.count { error = "Only image files can be attached." }
        for url in images where !pendingPhotos.contains(url) {
            guard pendingPhotos.count < ChatPhotos.maxPerMessage else { error = "Attach up to \(ChatPhotos.maxPerMessage) photos per message."; break }
            pendingPhotos.append(url)
        }
    }
    func removePendingPhoto(_ url: URL) { pendingPhotos.removeAll { $0 == url }; pendingCaptions[url] = nil }
    /// Attaches photos from the Photos album, each with a caption like "Hair · top · 2 Oct 2026".
    func attachProgressPhotos(_ photos: [(url: URL, caption: String)]) {
        for photo in photos where !pendingPhotos.contains(photo.url) {
            guard pendingPhotos.count < ChatPhotos.maxPerMessage else { error = "Attach up to \(ChatPhotos.maxPerMessage) photos per message."; break }
            pendingPhotos.append(photo.url); pendingCaptions[photo.url] = photo.caption
        }
    }
    /// Adds image files or image data (such as a ⌃⇧⌘4 screenshot) from the clipboard.
    func pastePhoto() {
        let board = NSPasteboard.general
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], files.contains(where: ChatPhotos.isImage) {
            addPhotos(files.filter(ChatPhotos.isImage)); return
        }
        guard let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { error = "There’s no image on the clipboard."; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ascend-pasted-\(UUID().uuidString).png")
        do { try png.write(to: url); addPhotos([url]) } catch { self.error = "The pasted image could not be read." }
    }

    func submit(_ text: String, document: TrackerDocument, today: String) {
        var message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty || !pendingPhotos.isEmpty, !working else { return }
        message = ClaudeAssistant.captioned(message, captions: pendingPhotos.map { pendingCaptions[$0] })
        guard let executable else { error = "Claude Code wasn’t found. Install it or set its path in Claude settings."; return }
        guard message.count <= ClaudeAssistant.maxPromptLength else { error = "Use \(ClaudeAssistant.maxPromptLength.formatted()) characters or fewer."; return }
        cancel(); error = nil; proposal = nil
        let id = currentID ?? UUID(), folder = ChatPhotos.folder(chat: id, workspace: workspace)
        var stored: [String] = []
        do { for url in pendingPhotos { stored.append(try ChatPhotos.store(url, in: folder)) } }
        catch {
            for name in stored { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
            self.error = error.localizedDescription; return
        }
        for url in pendingPhotos where url.lastPathComponent.hasPrefix("ascend-pasted-") { try? FileManager.default.removeItem(at: url) }
        pendingPhotos = []; pendingCaptions = [:]
        if currentID == nil { archive.insert(ChatThread(id: id, model: draftModel, effort: draftEffort)); currentID = id }
        archive.append(ChatMessage(fromUser: true, text: message, attachments: stored), to: id); persist()
        send(message, photos: stored, chat: id, executable: executable, document: document, today: today)
    }
    /// Sends the last unanswered message again without adding a duplicate.
    func retryLast(document: TrackerDocument, today: String) {
        guard !working, let thread = current, let last = thread.messages.last, last.fromUser else { return }
        guard let executable else { error = "Claude Code wasn’t found. Install it or set its path in Claude settings."; return }
        cancel(); error = nil; proposal = nil
        send(last.text, photos: last.photos, chat: thread.id, executable: executable, document: document, today: today)
    }
    private func send(_ message: String, photos: [String], chat id: UUID, executable: URL, document: TrackerDocument, today: String) {
        let input: String
        do {
            input = try ClaudeAssistant.inputLine(ClaudeAssistant.prompt(message, document: document, today: today, shareHistory: shareHistory, photos: photos.count),
                                                  photos: photos.map { photoURL($0, chat: id) })
        } catch { self.error = error.localizedDescription; return }
        let thread = archive.thread(id)!
        let invocation = ClaudeInvocation(executable: executable,
            arguments: ClaudeAssistant.arguments(model: thread.claudeModel, effort: thread.claudeEffort, session: id, resume: thread.sessionStarted),
            environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: configDirectory),
            directory: workspace, input: input)
        working = true
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                let output = try await launcher.run(invocation)
                guard generation == token else { return }
                if ClaudeAssistant.sessionStarted(output.stdout, session: id) { archive.update(id) { $0.sessionStarted = true } }
                let reply: AssistantReply
                do { reply = try ClaudeAssistant.decode(output) }
                catch let failure as ValidationError where failure.message.contains("No conversation found") {
                    // The Claude Code transcript was removed; the next attempt starts a fresh session.
                    archive.update(id) { $0.sessionStarted = false }
                    throw ValidationError(message: "This chat’s Claude Code session no longer exists. Retry to continue in a fresh session; earlier messages stay visible here but Claude won’t remember them.")
                }
                var response = reply.message
                if !reply.actions.isEmpty {
                    let prepared = try AssistantPlanner.prepare(reply, document: document, today: today, chat: id)
                    if prepared.candidate != document { proposal = prepared }
                    else { response += "\n\nYour plan already matches this. No changes needed." }
                }
                archive.append(ChatMessage(fromUser: false, text: response.isEmpty ? "Review the proposed changes below." : response), to: id)
                persist(); working = false; task = nil
            } catch {
                guard generation == token else { return }
                persist(); working = false; task = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func apply(to store: TrackerStore) {
        guard let proposal, !working, let id = currentID else { return }
        if store.applyProposal(proposal) {
            self.proposal = nil; error = nil
            archive.append(ChatMessage(fromUser: false, text: "Applied \(proposal.changes.count == 1 ? "1 change" : "\(proposal.changes.count) changes") locally. Undo is available until the next edit."), to: id); persist()
        } else { error = store.saveError ?? store.notice ?? "The proposal was not applied." }
    }
    func discardProposal() {
        guard let id = currentID else { return }
        proposal = nil; archive.append(ChatMessage(fromUser: false, text: "Proposal discarded. Your data is unchanged."), to: id); persist()
    }
    /// A note draft ready for review; the panel shows it in the note editor.
    @Published var noteDraft: JournalNote?
    @Published private(set) var drafting = false
    /// Asks Claude to summarize the current chat, or one reply, into a note. Runs unsaved, apart from the chat's session.
    func draftNote(focus: UUID? = nil, today: String) {
        guard !drafting, !working, let thread = current else { return }
        guard let executable else { error = "Claude Code wasn’t found. Install it or set its path in Claude settings."; return }
        let input: String
        do { input = try ClaudeAssistant.noteInput(messages: thread.messages, focus: thread.messages.first { $0.id == focus }, today: today) }
        catch { self.error = error.localizedDescription; return }
        let invocation = ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.noteArguments(model: thread.claudeModel, effort: thread.claudeEffort),
            environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: configDirectory),
            directory: workspace, input: input)
        drafting = true; error = nil
        let chat = thread.id
        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                noteDraft = try ClaudeAssistant.decodeNote(try await launcher.run(invocation)).note(day: today, chatID: chat)
            } catch { self.error = error.localizedDescription }
            drafting = false
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; working = false }
    func testConnection() {
        guard !working else { return }
        guard let executable else { connectionStatus = "Claude Code not found"; return }
        cancel(); error = nil; working = true; connectionStatus = "Testing \(defaultModel.label)…"
        let input: String
        do { input = try ClaudeAssistant.inputLine("This is a connection test. Reply in a few words that the connection works, with no actions.") }
        catch { self.error = error.localizedDescription; working = false; return }
        let invocation = ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.arguments(model: defaultModel, effort: defaultEffort, session: nil, resume: false),
            environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: configDirectory),
            directory: workspace, input: input)
        let token = generation, model = defaultModel
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
                _ = try ClaudeAssistant.decode(try await launcher.run(invocation))
                guard generation == token else { return }
                connectionStatus = "Connected · \(model.label) via your Claude profile"; working = false; task = nil
            } catch {
                guard generation == token else { return }
                connectionStatus = "Connection not confirmed"; working = false; task = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    private func persist() {
        do { try archive.save(to: archiveURL) }
        catch { self.error = "Chats could not be saved: \(error.localizedDescription)" }
    }
}
