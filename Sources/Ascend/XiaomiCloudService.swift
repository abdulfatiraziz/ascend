import SwiftUI
import AppKit
import AscendCore

/// Syncs heart rate, SpO2, stress and resting heart rate from the Mi Fitness cloud every hour.
/// The sign-in lives in the Keychain, never in tracker backups.
@MainActor final class XiaomiCloudService: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var signingIn = false
    @Published private(set) var syncing = false
    @Published private(set) var status: String?
    @Published private(set) var failed = false
    weak var store: TrackerStore?
    let enabled: Bool
    private let service = "com.abdul.ascend.xiaomi"
    private var timer: Timer?
    private var signIn: Task<Void, Never>?

    init(enabled: Bool) {
        self.enabled = enabled
        connected = enabled && loadSession() != nil
    }
    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        if connected { Task { try? await Task.sleep(for: .seconds(5)); await sync() } }
    }

    // MARK: Keychain
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "session", kSecAttrSynchronizable as String: false]
    }
    private func loadSession() -> XiaomiSession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(XiaomiSession.self, from: data)
    }
    private func save(_ session: XiaomiSession) throws {
        SecItemDelete(query as CFDictionary)
        var q = query; q[kSecValueData as String] = try JSONEncoder().encode(session); q[kSecAttrLabel as String] = "Ascend · Mi Fitness sign-in"
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw ValidationError(message: "The Mi Fitness sign-in couldn’t be saved in the Keychain (\(status)).") }
    }

    // MARK: Sign-in
    /// Opens Xiaomi's sign-in page in the browser and waits for it. A browser already signed in to Xiaomi approves it at once;
    /// otherwise sign in there, then click Sign in again.
    func beginSignIn() {
        guard enabled, !signingIn else { return }
        signingIn = true; failed = false; status = "Opening Xiaomi sign-in in your browser…"
        signIn = Task {
            defer { signingIn = false }
            do {
                let challenge = try await XiaomiCloud.startSignIn()
                NSWorkspace.shared.open(challenge.loginURL)
                status = "Waiting for you to sign in to Xiaomi in the browser. If it asks you to sign in first, do that, then click Sign in again here."
                let session = try await XiaomiCloud.finishSignIn(challenge)
                try save(session)
                connected = true; status = "Signed in. Reading the last 14 days…"
                await sync()
            } catch is CancellationError {
                status = nil
            } catch { failed = true; status = error.localizedDescription }
        }
    }
    func cancelSignIn() { signIn?.cancel(); signIn = nil }
    /// Forgets the sign-in. Readings already imported stay; phone syncs supply heart rate and SpO2 again.
    func signOut() {
        cancelSignIn()
        SecItemDelete(query as CFDictionary)
        connected = false; failed = false; status = "Signed out. Earlier readings stay; heart rate comes from the phone again."
        store?.disconnectCloud()
    }

    // MARK: Sync
    func sync() async {
        guard enabled, !syncing, var session = loadSession(), let store else { return }
        syncing = true; defer { syncing = false }
        let last = store.document.health.cloudSync
        // First sync reads 14 days; later ones re-read from a day before the last sync, so late watch uploads are caught.
        let days = last.map { min(14, max(2, Int(ceil((Date().timeIntervalSince1970 - $0) / 86_400)) + 1)) } ?? 14
        let zone = TimeZone(identifier: store.document.timeZoneID) ?? .current
        do {
            let result: (records: [HealthRecord], range: ClosedRange<Double>)
            do { result = try await XiaomiCloud.fetch(session, days: days, timeZone: zone) }
            catch XiaomiCloudError.signInExpired {
                session = try await XiaomiCloud.renew(session)
                try save(session)
                result = try await XiaomiCloud.fetch(session, days: days, timeZone: zone)
            }
            guard store.importCloud(result.records, range: result.range) else { throw ValidationError(message: store.notice ?? "The readings couldn’t be saved.") }
            let heart = result.records.filter { $0.metric == .heartRate }.count, stress = result.records.filter { $0.metric == .stress }.count
            failed = false; status = "Synced \(heart) heart-rate and \(stress) stress readings · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch XiaomiCloudError.signInExpired {
            failed = true; status = XiaomiCloudError.signInExpired.localizedDescription
        } catch { failed = true; status = error.localizedDescription }
    }
}

/// Sign-in and status for the Mi Fitness cloud sync.
struct XiaomiCloudPanel: View {
    @ObservedObject var cloud: XiaomiCloudService
    @State private var confirmSignOut = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: cloud.connected ? "icloud.and.arrow.down" : "icloud.slash").foregroundStyle(cloud.failed ? .orange : cloud.connected ? Ink.accent : Ink.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cloud.connected ? "Mi Fitness cloud · all-day heart rate, stress, SpO2 and resting heart rate, hourly" : "Mi Fitness cloud: not signed in").font(.bt(size: 12))
                    Text(cloud.connected ? "Mi Fitness sends only workout heart rate to Health Connect, so these come straight from your Xiaomi account. Sleep, steps and workouts still come from the phone."
                         : "Sign in with your Xiaomi account to get all-day heart rate, stress and resting heart rate. Mi Fitness doesn’t share them with Health Connect.")
                        .font(.bt(size: 11)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if cloud.signingIn {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { cloud.cancelSignIn() }
                } else if cloud.connected {
                    if cloud.syncing { ProgressView().controlSize(.small) }
                    Button("Sync now") { Task { await cloud.sync() } }.disabled(cloud.syncing)
                    Button("Sign out…") { confirmSignOut = true }
                } else {
                    Button("Sign in with Xiaomi…") { cloud.beginSignIn() }.disabled(!cloud.enabled)
                }
            }.font(.bt(size: 11))
            if let status = cloud.status { Text(status).font(.bt(size: 11)).foregroundStyle(cloud.failed ? .orange : Ink.muted).fixedSize(horizontal: false, vertical: true) }
        }.panel(padding: 12)
            .confirmationDialog("Sign out of the Mi Fitness cloud?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { cloud.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Cipher forgets the sign-in. Readings already imported stay; heart rate and SpO2 come from the phone again.") }
    }
}
