import SwiftUI
import AscendCore

/// Pairing and status for Ascend Bridge on the same Wi-Fi.
struct PhoneLinkPanel: View {
    @ObservedObject var link: PhoneLinkService
    @State private var showInstall = false
    @State private var forgetting: PairedPhone?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: link.listening ? "wifi" : "wifi.exclamationmark").foregroundStyle(link.listening ? Ink.accent : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(link.status).font(.system(size: 12))
                    Text(link.phones.isEmpty ? "No phone paired yet." : "Open Ascend Bridge and tap Sync to Mac. Health data and meal photos arrive here.").font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
                Spacer()
                Button("Pair phone…") { link.openPairing() }.disabled(!link.listening || link.pairingOpen)
                Button("Install phone app…") { link.shareAPK(); showInstall = true }.disabled(!link.listening)
            }.font(.system(size: 11))
            if link.pairingOpen { pairingBox }
            ForEach(link.phones) { phone in
                HStack {
                    Image(systemName: "iphone").foregroundStyle(Ink.muted)
                    Text(phone.name).font(.system(size: 12))
                    Text(phone.lastSync.map { "Last sync \($0.formatted(.relative(presentation: .named)))" } ?? "Paired \(phone.paired.formatted(.relative(presentation: .named)))").font(.system(size: 11)).foregroundStyle(Ink.muted)
                    Spacer()
                    Button("Forget") { forgetting = phone }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.muted)
                }
            }
            if let activity = link.activity { Text(activity).font(.system(size: 11)).foregroundStyle(Ink.muted) }
        }.panel(padding: 12)
            .sheet(isPresented: $showInstall, onDismiss: { link.stopSharingAPK() }) { InstallPhoneAppSheet(link: link) }
            .confirmationDialog("Forget \(forgetting?.name ?? "this phone")?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
                Button("Forget phone", role: .destructive) { if let phone = forgetting { link.forget(phone) }; forgetting = nil }
                Button("Cancel", role: .cancel) { forgetting = nil }
            } message: { Text("It can no longer send data until you pair it again. Data already imported stays.") }
    }
    @ViewBuilder private var pairingBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let request = link.pairing {
                Text("“\(request.phoneName)” wants to pair. Check that your phone shows this code:").font(.system(size: 12))
                Text("\(request.code.prefix(3)) \(request.code.suffix(3))").font(.system(size: 30, weight: .semibold, design: .monospaced)).tracking(2)
                HStack {
                    Button("Decline") { link.respond(accept: false, to: request) }
                    Spacer()
                    PrimaryButton(label: "Codes match · Pair") { link.respond(accept: true, to: request) }
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your phone. Open Ascend Bridge and tap Pair with Mac. Both devices must be on the same Wi-Fi.").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Cancel") { link.cancelPairing() }.font(.system(size: 11))
                }
            }
        }.padding(12).background(Ink.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}
struct InstallPhoneAppSheet: View {
    @ObservedObject var link: PhoneLinkService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        EditorShell(title: "Install Ascend Bridge") {
            if let url = link.downloadURL {
                HStack(alignment: .top, spacing: 18) {
                    if let qr = link.qrCode(for: url) { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 170, height: 170).background(.white).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Point your Pixel’s camera at the code and open the link.\n2. Download the app, then allow your browser to install it when asked.\n3. Tap Update (or Install). Your Health Connect permissions are kept.\n4. Open Ascend Bridge → Pair with Mac.").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Text(url.absoluteString).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.muted).textSelection(.enabled)
                    }
                }
                Text("The download works only on this Wi-Fi while this window is open (up to 15 minutes). No developer options or USB debugging are needed.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            } else {
                Text("Connect this Mac to Wi-Fi to share the phone app.").font(.system(size: 12)).foregroundStyle(.orange)
            }
        } actions: { HStack { Spacer(); PrimaryButton(label: "Done") { dismiss() } } }
    }
}
