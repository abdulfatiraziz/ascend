import SwiftUI
import AscendCore

/// Signs the personal Claude profile in from the app. Claude Code opens its sign-in page in the browser
/// and finishes once it is approved there; meals and meds that failed for this reason are then retried.
@MainActor final class ClaudeSignInService: ObservableObject {
    enum State: Equatable { case unknown, signedIn(Date?), signedOut, waiting, failed(String) }
    @Published private(set) var state: State = .unknown
    weak var store: TrackerStore?
    private let launcher: any ClaudeLauncher
    private var task: Task<Void, Never>?
    /// Five minutes to approve in the browser.
    init(launcher: any ClaudeLauncher = ProcessClaudeLauncher(timeout: 300)) { self.launcher = launcher }

    private func invocation(_ arguments: [String]) -> ClaudeInvocation? {
        guard let chat = store?.assistant, let executable = chat.executable else { return nil }
        return ClaudeInvocation(executable: executable, arguments: arguments,
            environment: ClaudeAssistant.environment(base: ProcessInfo.processInfo.environment, configDirectory: chat.configDirectory),
            directory: FileManager.default.homeDirectoryForCurrentUser, input: "")
    }
    func refresh() {
        guard state != .waiting, let call = invocation(ClaudeSignIn.statusArguments) else { return }
        Task { [weak self] in
            guard let self, let output = try? await self.launcher.run(call), let status = ClaudeSignIn.status(output.stdout) else { return }
            if self.state != .waiting { self.state = status.signedIn ? .signedIn(status.expires) : .signedOut }
        }
    }
    func signIn() {
        guard state != .waiting else { return }
        guard let call = invocation(ClaudeSignIn.arguments) else { state = .failed("Claude Code wasn’t found. Set its path in Claude settings."); return }
        state = .waiting
        task = Task { [weak self] in
            guard let self else { return }
            let output = try? await self.launcher.run(call)
            guard !Task.isCancelled, self.state == .waiting else { return }
            if let output, output.status == 0, !output.timedOut {
                self.state = .signedIn(nil); self.refresh(); self.store?.retryAfterClaudeSignIn()
            } else {
                self.state = .failed(output?.timedOut == true ? "Sign-in timed out. Try again and approve it in the browser." : "Sign-in didn’t finish. Try again.")
            }
        }
    }
    func cancel() { task?.cancel(); task = nil; if state == .waiting { state = .signedOut } }
}

/// A Claude error under a meal or medicine. A signed-out error gets a short message and the sign-in button
/// (the item retries by itself once signed in); anything else shows as it is, with Retry when given.
struct ClaudeErrorLine: View {
    let error: String
    @ObservedObject var service: ClaudeSignInService
    var retry: (() -> Void)?
    var body: some View {
        if ClaudeSignIn.needed(error) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ClaudeSignIn.message).font(.bt(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                ClaudeSignInButton(service: service)
            }
        } else {
            HStack {
                Text(error).font(.bt(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                if let retry { Button("Retry", action: retry).font(.bt(size: 11)) }
            }
        }
    }
}

/// "Sign in to Claude", or the wait for the browser while Claude Code finishes signing in.
struct ClaudeSignInButton: View {
    @ObservedObject var service: ClaudeSignInService
    var title = "Sign in to Claude"
    var body: some View {
        switch service.state {
        case .waiting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Approve it in your browser…").font(.bt(size: 11)).foregroundStyle(Ink.muted)
                Button("Cancel") { service.cancel() }.font(.bt(size: 11))
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message).font(.bt(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button(title) { service.signIn() }.font(.bt(size: 11))
            }
        default:
            Button(title) { service.signIn() }.font(.bt(size: 11))
        }
    }
}
