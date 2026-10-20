import SwiftUI
import AscendCore

/// Compares two progress photos with Claude on request, one pair at a time, using the chat's Claude settings.
@MainActor final class PhotoReviewController: ObservableObject {
    struct Pair: Hashable { var before: UUID; var after: UUID }
    @Published private(set) var working: Pair?
    @Published private(set) var errors: [Pair: String] = [:]
    weak var store: TrackerStore?
    private let launcher: any ClaudeLauncher
    init(launcher: any ClaudeLauncher = ProcessClaudeLauncher(timeout: 300)) { self.launcher = launcher }

    func compare(_ pair: Pair) {
        guard working == nil, let store,
              let before = store.document.photos.photos.first(where: { $0.id == pair.before }),
              let after = store.document.photos.photos.first(where: { $0.id == pair.after }) else { return }
        let chat = store.assistant
        errors[pair] = nil
        guard let executable = chat.executable else { errors[pair] = "Claude Code wasn’t found. Set it up in Claude settings, then retry."; return }
        let invocation: ClaudeInvocation
        do {
            invocation = ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.photoArguments(model: chat.defaultModel, effort: chat.defaultEffort),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: chat.configDirectory),
                directory: chat.workspace, input: try ClaudeAssistant.photoInput(before: before, after: after,
                    beforeFile: store.progressPhotoURL(before), afterFile: store.progressPhotoURL(after)))
        } catch { errors[pair] = error.localizedDescription; return }
        working = pair
        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: chat.workspace, withIntermediateDirectories: true)
                let comparison = try ClaudeAssistant.decodePhotoComparison(try await launcher.run(invocation))
                self.store?.saveReview(before: pair.before, after: pair.after, comparison: comparison)
            } catch { errors[pair] = error.localizedDescription }
            working = nil
        }
    }
}
