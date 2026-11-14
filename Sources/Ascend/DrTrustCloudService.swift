import SwiftUI
import AppKit
import Security
import AscendCore

/// Mac-only cloud source. Isolated QA runs cannot access the real sign-in unless explicitly enabled.
@MainActor final class DrTrustCloudService: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var awaitingCode = false
    @Published private(set) var needsLogin = false
    @Published private(set) var failed = false
    @Published private(set) var status: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var automatic = true
    let enabled: Bool
    private weak var bodyStore: BodyMeasurementStore?
    private let client = DrTrustCloud()
    private let settingsURL: URL
    private var challenge: DrTrustChallenge?
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var timer: Timer?
    private var lastAttempt: Date?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private struct Settings: Codable { var automatic: Bool; var lastSync: Date? }
    init(enabled: Bool, bodyStore: BodyMeasurementStore) {
        self.enabled = enabled; self.bodyStore = bodyStore
        settingsURL = bodyStore.url.deletingLastPathComponent().appendingPathComponent("drtrust-sync.json")
        if let data = try? Data(contentsOf: settingsURL), let settings = try? JSONDecoder().decode(Settings.self, from: data) {
            automatic = settings.automatic
            if let date = settings.lastSync, date.timeIntervalSince1970.isFinite, date <= Date().addingTimeInterval(300) { lastSync = date }
        }
        if enabled {
            do { connected = try loadSession() != nil }
            catch { failed = true; status = error.localizedDescription }
        }
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.abdul.ascend.drtrust", kSecAttrAccount as String: "session", kSecAttrSynchronizable as String: false]
    }
    private func loadSession() throws -> DrTrustSession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let session = try? JSONDecoder().decode(DrTrustSession.self, from: data) else { throw DrTrustError.keychain }
        try session.validate()
        return session
    }
    private func saveSession(_ session: DrTrustSession, generation expected: Int) throws {
        try Task.checkCancellation()
        guard enabled, generation == expected else { throw CancellationError() }
        try session.validate()
        let attrs = [kSecValueData as String: try JSONEncoder().encode(session), kSecAttrLabel as String: "Ascend · Dr Trust sign-in"] as [String: Any]
        let updated = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updated == errSecItemNotFound {
            var add = query; attrs.forEach { add[$0.key] = $0.value }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw DrTrustError.keychain }
        } else if updated != errSecSuccess { throw DrTrustError.keychain }
    }
    private func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Settings(automatic: automatic, lastSync: lastSync)).write(to: settingsURL, options: .atomic)
        } catch { failed = true; status = "Dr Trust preferences could not be saved. Your body readings are retained." }
    }
    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncIfDue() }
        }
        for (center, name) in [(NotificationCenter.default, NSApplication.didBecomeActiveNotification), (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.syncIfDue() }
            }
            observers.append((center, observer))
        }
        syncIfDue()
    }
    func setAutomatic(_ value: Bool) { automatic = value; saveSettings(); if value { syncIfDue() } }
    private func syncIfDue() {
        guard enabled, automatic, connected, !needsLogin, !busy, !awaitingCode,
              DrTrustSyncSchedule.isDue(lastSync: lastSync, lastAttempt: lastAttempt) else { return }
        lastAttempt = Date()
        sync()
    }
    func cancelLogin() {
        generation += 1; operation?.cancel(); operation = nil
        challenge = nil; awaitingCode = false; busy = false; status = nil
    }
    func requestCode(phone: String) {
        guard enabled, !busy else { return }
        generation += 1; let current = generation
        busy = true; failed = false; status = "Requesting a Dr Trust code…"
        challenge = nil; awaitingCode = false
        operation = Task {
            defer { if generation == current { busy = false } }
            do {
                let pending = try await client.beginSignIn(phone: phone)
                guard generation == current else { return }
                challenge = pending; awaitingCode = true; status = "Enter the code Dr Trust sent to your phone."
            } catch is CancellationError { }
            catch { if generation == current { failed = true; status = error.localizedDescription } }
        }
    }
    func verifyCode(_ code: String) {
        guard enabled, !busy, let challenge else { return }
        let current = generation
        busy = true; failed = false; status = "Verifying your Dr Trust sign-in…"
        operation = Task {
            defer { if generation == current { busy = false } }
            do {
                let session = try await client.verify(challenge, code: code)
                guard generation == current, let bodyStore else { return }
                guard bodyStore.archive.records.allSatisfy({ $0.userID == session.userID }) else { throw DrTrustError.profile }
                try saveSession(session, generation: current)
                connected = true; needsLogin = false; awaitingCode = false; self.challenge = nil
                // The verification operation owns this task until the first complete fetch/save finishes.
                try await performSync(session, generation: current)
            } catch is CancellationError { }
            catch { if generation == current { show(error) } }
        }
    }
    func sync() {
        guard enabled, connected, !needsLogin, !busy, !awaitingCode else { return }
        let current = generation
        busy = true; failed = false; status = "Reading Dr Trust history…"
        operation = Task {
            defer { if generation == current { busy = false } }
            do {
                guard let session = try loadSession() else { throw DrTrustError.expired }
                try await performSync(session, generation: current)
            } catch is CancellationError { }
            catch { if generation == current { show(error) } }
        }
    }
    private func performSync(_ session: DrTrustSession, generation expected: Int) async throws {
        let result = try await client.synchronize(session) { [weak self] renewed in
            guard let self else { throw CancellationError() }
            try await self.saveSession(renewed, generation: expected)
        }
        try Task.checkCancellation()
        guard generation == expected, let bodyStore else { throw CancellationError() }
        guard bodyStore.archive.records.allSatisfy({ $0.userID == result.session.userID }) else { throw DrTrustError.profile }
        try bodyStore.mergeCloud(result.records)
        lastSync = Date(); failed = false
        status = result.records.isEmpty ? "Dr Trust returned no readings. Your stored history is retained." : "Synced \(result.records.count) Dr Trust readings."
        saveSettings()
    }
    private func show(_ error: Error) {
        failed = true; status = error.localizedDescription
        if error as? DrTrustError == .expired { needsLogin = true }
    }
    func signOut() {
        guard enabled else { return }
        cancelLogin()
        let removed = SecItemDelete(query as CFDictionary)
        guard removed == errSecSuccess || removed == errSecItemNotFound else { failed = true; status = "Dr Trust sign-in could not be removed from Keychain."; return }
        connected = false; needsLogin = false; failed = false
        status = "Disconnected. Your imported body readings are retained."
    }
}

struct DrTrustCloudPanel: View {
    @ObservedObject var cloud: DrTrustCloudService
    @State private var showLogin = false
    @State private var phone = ""
    @State private var code = ""
    @State private var confirmDisconnect = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dr Trust automatic sync").font(.bt(size: 14, weight: .medium))
                    Text(cloud.connected ? "Connected · weight and body composition" : "Sign in once with your Dr Trust phone number.")
                        .font(.bt(size: 12)).foregroundStyle(Ink.muted)
                }
                Spacer()
                if cloud.busy { ProgressView().controlSize(.small) }
                if cloud.connected {
                    Button("Sync now") { cloud.sync() }.disabled(cloud.busy || cloud.needsLogin)
                    Button("Disconnect…") { confirmDisconnect = true }
                }
                if !cloud.connected || cloud.needsLogin {
                    Button(cloud.needsLogin ? "Sign in again…" : "Connect Dr Trust…") { showLogin = true }.disabled(!cloud.enabled || cloud.busy)
                }
            }
            if cloud.connected {
                Toggle("Sync automatically every hour while Ascend is open", isOn: Binding(get: { cloud.automatic }, set: { cloud.setAutomatic($0) }))
                    .font(.bt(size: 12))
                if let date = cloud.lastSync { Text("Last sync \(date.formatted(date: .abbreviated, time: .shortened))").font(.bt(size: 11)).foregroundStyle(Ink.muted) }
            }
            if let status = cloud.status { Text(status).font(.bt(size: 12)).foregroundStyle(cloud.failed ? .orange : Ink.muted).fixedSize(horizontal: false, vertical: true) }
        }.padding(14).background(Ink.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line))
        .sheet(isPresented: $showLogin, onDismiss: { cloud.cancelLogin(); code = ""; phone = "" }) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Dr Trust 360").font(.title2)
                Text("Your sign-in is saved in this Mac’s Keychain. Ascend reads your scale history on connection and checks hourly while open.")
                    .font(.bt(size: 13)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if cloud.awaitingCode {
                    SecureField("Code from Dr Trust", text: $code).textFieldStyle(.roundedBorder)
                    Button("Verify and sync") { cloud.verifyCode(code); code = "" }.disabled(cloud.busy || code.isEmpty)
                    Button("Use another number or resend") { cloud.cancelLogin(); code = "" }.disabled(cloud.busy)
                } else if !cloud.connected || cloud.needsLogin {
                    TextField("Phone number, including +91 or your country code", text: $phone).textFieldStyle(.roundedBorder)
                    Button("Send code") { cloud.requestCode(phone: phone) }.disabled(cloud.busy || phone.isEmpty)
                }
                if cloud.busy { ProgressView() }
                if let status = cloud.status { Text(status).font(.bt(size: 12)).foregroundStyle(cloud.failed ? .orange : Ink.muted).fixedSize(horizontal: false, vertical: true) }
                HStack { Spacer(); Button(cloud.connected && !cloud.awaitingCode && !cloud.needsLogin ? "Done" : "Cancel") { showLogin = false } }
            }.padding(24).frame(width: 440).interactiveDismissDisabled(cloud.busy)
        }
        .confirmationDialog("Disconnect Dr Trust?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { cloud.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Removes this Mac’s Dr Trust sign-in and stops sync. Imported readings stay.") }
    }
}
