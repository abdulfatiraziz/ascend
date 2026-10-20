import SwiftUI
import AscendCore

/// Sorts medicine photo batches and re-reads single medicines with Claude, one job at a time, using the chat's Claude settings.
@MainActor final class MedController: ObservableObject {
    enum Job: Hashable { case batch(UUID), medicine(UUID) }
    @Published private(set) var working: Set<Job> = []
    weak var store: TrackerStore?
    private var queue: [Job] = []
    private var running = false
    private let launcher: any ClaudeLauncher
    init(launcher: any ClaudeLauncher = ProcessClaudeLauncher(timeout: 300)) { self.launcher = launcher }

    func enqueue(_ job: Job) {
        guard !queue.contains(job), !working.contains(job) else { return }
        queue.append(job); runNext()
    }
    /// Complete batches that arrived while Claude was unavailable, or before the app quit, are sorted on launch.
    func resumePending() {
        guard let cabinet = store?.document.meds else { return }
        for batch in cabinet.batches where cabinet.ready(batch) { enqueue(.batch(batch.id)) }
    }
    func sortNow(_ batch: UUID) { store?.sortMedBatchNow(batch); enqueue(.batch(batch)) }
    func reRead(_ medicine: UUID) { store?.setMedReading(medicine, reading: nil, error: nil); enqueue(.medicine(medicine)) }

    private func runNext() {
        guard !running, let store, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let photos: [MedPhoto]
        let files: [URL]
        switch job {
        case .batch(let id):
            photos = Array(store.document.meds.batchPhotos(id).prefix(ClaudeAssistant.maxMedPhotos))
            files = photos.map { store.medPhotoURL($0.photo) }
        case .medicine(let id):
            photos = []
            files = (store.document.meds.medicines.first { $0.id == id }?.photos ?? []).prefix(ClaudeAssistant.maxMedPhotos).map(store.medPhotoURL)
        }
        guard !files.isEmpty else { runNext(); return }
        let chat = store.assistant
        func fail(_ message: String) {
            switch job {
            case .batch(let id): store.setMedBatchError(id, message)
            case .medicine(let id): store.setMedReading(id, reading: nil, error: message)
            }
        }
        guard let executable = chat.executable else { fail("Claude Code wasn’t found. Set it up in Claude settings, then retry."); runNext(); return }
        let invocation: ClaudeInvocation
        do {
            // A batch is sorted into medicines; a single medicine's photos are re-read as one.
            invocation = ClaudeInvocation(executable: executable, arguments: ClaudeAssistant.medArguments(model: chat.defaultModel, effort: chat.defaultEffort),
                environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: chat.configDirectory),
                directory: chat.workspace, input: try ClaudeAssistant.medInput(photos: files, single: { if case .medicine = job { return true }; return false }()))
        } catch { fail(error.localizedDescription); runNext(); return }
        running = true; working.insert(job)
        Task { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: chat.workspace, withIntermediateDirectories: true)
                let sorting = try ClaudeAssistant.decodeMeds(try await launcher.run(invocation), photoCount: files.count)
                switch job {
                case .batch(let id):
                    self.store?.applyMedSorting(batch: id, photos: photos, sorting: sorting)
                    // Batches over the per-request limit continue with the remaining photos.
                    if let cabinet = self.store?.document.meds, !cabinet.batchPhotos(id).isEmpty { self.queue.append(job) }
                case .medicine(let id):
                    guard let reading = sorting.medicines.first else { throw ValidationError(message: "Claude couldn’t read a medicine in these photos.") }
                    self.store?.setMedReading(id, reading: reading, error: nil)
                }
            } catch { fail(error.localizedDescription) }
            working.remove(job); running = false; runNext()
        }
    }
}
