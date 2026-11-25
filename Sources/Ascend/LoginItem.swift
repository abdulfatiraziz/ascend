import SwiftUI
import ServiceManagement

/// Opens Cipher when you log in or restart the Mac. Turned on once by default; after that your choice
/// (here or in System Settings → General → Login Items) is left alone.
@MainActor enum LoginItem {
    private static let decidedKey = "login.openAtLogin.decided"
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func applyDefault() {
        guard ProcessInfo.processInfo.environment["ASCEND_DATA_DIR"] == nil,
              !UserDefaults.standard.bool(forKey: decidedKey) else { return }
        if (try? SMAppService.mainApp.register()) != nil || isOn { UserDefaults.standard.set(true, forKey: decidedKey) }
    }
    static func set(_ on: Bool) throws {
        UserDefaults.standard.set(true, forKey: decidedKey)
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

struct LoginItemToggle: View {
    @State private var on = LoginItem.isOn
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Open Cipher when you log in or restart", isOn: Binding(get: { on }, set: { value in
                do { try LoginItem.set(value); problem = nil } catch { problem = "macOS didn’t accept that. Check System Settings → General → Login Items." }
                on = LoginItem.isOn
            })).font(.bt(size: 12))
            Text(problem ?? (SMAppService.mainApp.status == .requiresApproval
                 ? "Waiting for approval in System Settings → General → Login Items."
                 : "Also listed in System Settings → General → Login Items."))
                .font(.bt(size: 11)).foregroundStyle(problem == nil ? Ink.muted : .orange)
        }
        .onAppear { on = LoginItem.isOn }
    }
}
