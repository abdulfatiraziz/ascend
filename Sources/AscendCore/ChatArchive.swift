import Foundation

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fromUser: Bool
    public var text: String
    public var date: Date
    /// File names in the chat's `ChatPhotos.folder`; optional so older chats still load.
    public var attachments: [String]?
    public init(id: UUID = UUID(), fromUser: Bool, text: String, date: Date = Date(), attachments: [String] = []) {
        self.id = id; self.fromUser = fromUser; self.text = text; self.date = date
        self.attachments = attachments.isEmpty ? nil : attachments
    }
    public var photos: [String] { attachments ?? [] }
}
/// One chat. Its `id` is also the Claude Code session ID, so the same conversation resumes from Terminal.
public struct ChatThread: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var model: String
    /// Optional so chats saved before effort levels existed still load, as the default.
    public var effort: String?
    public var created: Date
    public var updated: Date
    public var sessionStarted: Bool
    public var messages: [ChatMessage]
    public init(id: UUID = UUID(), title: String = "New chat", model: ClaudeModel, effort: ClaudeEffort = ClaudeAssistant.defaultEffort, now: Date = Date()) {
        self.id = id; self.title = title; self.model = model.rawValue; self.effort = effort.rawValue; self.created = now; self.updated = now
        sessionStarted = false; messages = []
    }
    public var claudeModel: ClaudeModel { ClaudeModel(rawValue: model) ?? ClaudeAssistant.defaultModel }
    public var claudeEffort: ClaudeEffort { effort.flatMap(ClaudeEffort.init(rawValue:)) ?? ClaudeAssistant.defaultEffort }
}
/// Stored beside tracker.json, outside tracker backups.
public struct ChatArchive: Codable, Equatable, Sendable {
    public static let maxThreads = 300, maxMessages = 400, maxTitleLength = 60
    public var version = 1
    public var threads: [ChatThread] = []
    public init(threads: [ChatThread] = []) { self.threads = threads }

    public var sorted: [ChatThread] { threads.sorted { $0.updated > $1.updated } }
    public func thread(_ id: UUID?) -> ChatThread? { threads.first { $0.id == id } }
    public mutating func insert(_ thread: ChatThread) {
        threads.removeAll { $0.id == thread.id }
        threads.append(thread)
        if threads.count > Self.maxThreads { threads = Array(sorted.prefix(Self.maxThreads)) }
    }
    public mutating func append(_ message: ChatMessage, to id: UUID) {
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return }
        if message.fromUser && !threads[i].messages.contains(where: \.fromUser) {
            threads[i].title = Self.title(for: message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !message.photos.isEmpty ? "Photo" : message.text)
        }
        threads[i].messages.append(message)
        if threads[i].messages.count > Self.maxMessages { threads[i].messages.removeFirst(threads[i].messages.count - Self.maxMessages) }
        threads[i].updated = max(threads[i].updated, message.date)
    }
    public mutating func update(_ id: UUID, _ change: (inout ChatThread) -> Void) {
        guard let i = threads.firstIndex(where: { $0.id == id }) else { return }
        change(&threads[i])
    }
    public mutating func rename(_ id: UUID, to title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        update(id) { $0.title = String(value.prefix(Self.maxTitleLength)) }
    }
    public mutating func remove(_ id: UUID) { threads.removeAll { $0.id == id } }
    public static func title(for text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return "New chat" }
        return line.count > maxTitleLength ? String(line.prefix(maxTitleLength - 1)) + "…" : line
    }

    /// A missing file is an empty archive. An unreadable file is moved aside, never overwritten.
    public static func load(from url: URL, fileManager: FileManager = .default) -> (archive: ChatArchive, notice: String?) {
        guard fileManager.fileExists(atPath: url.path) else { return (ChatArchive(), nil) }
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url), let archive = try? decoder.decode(ChatArchive.self, from: data) { return (archive, nil) }
        let aside = url.deletingLastPathComponent().appendingPathComponent("chats-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? fileManager.moveItem(at: url, to: aside)
        return (ChatArchive(), "Your saved chats could not be read, so Ascend started a fresh list. The old file was kept as \(aside.lastPathComponent).")
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
