import SwiftUI
import AscendCore

/// Estimates meal photos with Claude, one at a time, using the chat's Claude settings.
@MainActor final class MealController: ObservableObject {
    @Published private(set) var estimating: Set<UUID> = []
    weak var store: TrackerStore?
    private var queue: [UUID] = []
    private var running = false
    private let launcher: any ClaudeLauncher
    init(launcher: any ClaudeLauncher = ProcessClaudeLauncher(timeout: 300)) { self.launcher = launcher }

    func enqueue(_ id: UUID) {
        guard !queue.contains(id), !estimating.contains(id) else { return }
        queue.append(id); runNext()
    }
    /// Meals that arrived while Claude was unavailable, or before the app quit, get estimated on launch.
    func estimatePending() {
        for meal in store?.document.meals.entries ?? [] where meal.estimate == nil && meal.error == nil && !meal.confirmed { enqueue(meal.id) }
    }
    func retry(_ id: UUID) { store?.setMealEstimate(id, estimate: nil, error: nil); enqueue(id) }
    private func runNext() {
        guard !running, let store, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let meal = store.document.meals.entries.first(where: { $0.id == id }) else { runNext(); return }
        let chat = store.assistant
        guard let executable = chat.executable else {
            store.setMealEstimate(id, estimate: nil, error: "Claude Code wasn’t found. Set it up in Claude settings, then retry."); runNext(); return
        }
        let invocation: ClaudeInvocation
        do {
            invocation = ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.mealArguments(model: chat.defaultModel, effort: chat.defaultEffort),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: chat.configDirectory),
                directory: chat.workspace, input: try ClaudeAssistant.mealInput(photo: store.mealPhotoURL(meal), note: meal.note,
                    takenAt: Date(timeIntervalSince1970: meal.takenAt), timeZone: store.document.timeZoneID))
        } catch { store.setMealEstimate(id, estimate: nil, error: error.localizedDescription); runNext(); return }
        running = true; estimating.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: chat.workspace, withIntermediateDirectories: true)
                let estimate = try ClaudeAssistant.decodeMeal(try await launcher.run(invocation))
                self.store?.setMealEstimate(id, estimate: estimate, error: nil)
            } catch { self.store?.setMealEstimate(id, estimate: nil, error: error.localizedDescription) }
            estimating.remove(id); running = false; runNext()
        }
    }
}
