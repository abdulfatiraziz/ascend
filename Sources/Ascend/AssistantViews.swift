import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AscendCore

/// A stored or pending chat photo; click opens it in the default viewer.
struct PhotoThumbnail: View {
    var url: URL
    var size: CGFloat
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Group {
                if let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(Ink.muted) }
            }.frame(width: size, height: size).background(Ink.panel).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Ink.line))
        }.buttonStyle(.plain).help("Open photo")
    }
}

struct ClaudeSettingsEditor: View {
    @ObservedObject var controller: ChatController
    @Environment(\.dismiss) private var dismiss
    init(store: TrackerStore) { controller = store.assistant }
    var body: some View {
        EditorShell(title: "Claude settings") {
            Text("Ask Ascend runs on your own Claude Code install and account, the same as `claude --personal` in Terminal. There is no API key to manage.").font(.system(size: 12)).foregroundStyle(Ink.muted)
            FieldGroup(label: "Claude Code") {
                Text(controller.executable?.path ?? "Not found. Install Claude Code or enter its path below.").font(.system(size: 11, design: .monospaced)).foregroundStyle(controller.executable == nil ? .orange : Ink.muted).textSelection(.enabled)
            }
            FieldGroup(label: "Custom path (optional)") { TextField("Detected automatically", text: $controller.executableOverride).labelsHidden() }
            FieldGroup(label: "Claude profile folder") { TextField(ClaudeAssistant.defaultConfigDirectory, text: $controller.configDirectory).labelsHidden() }
            Text("~/.claude-personal is your personal account. If Claude says you aren’t signed in, run `claude --personal` in Terminal once and sign in.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            FieldGroup(label: "Model for new chats") {
                Picker("Model for new chats", selection: $controller.defaultModel) { ForEach(ClaudeModel.allCases, id: \.self) { Text("\($0.label) · \($0.detail)").tag($0) } }.labelsHidden()
            }
            FieldGroup(label: "Effort for new chats") {
                Picker("Effort for new chats", selection: $controller.defaultEffort) { ForEach(ClaudeEffort.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden()
            }
            Text("Applies to every model. Medium suits most chats; higher effort thinks longer and uses more of your plan. Each chat’s effort can be changed from its menu.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            Toggle("Share recent check-ins, progress and habit notes", isOn: $controller.shareHistory).font(.system(size: 12))
            Text("Lets Claude discuss how your cycle is actually going. Your plan is always shared. Urge logs, health data and journal or caffeine entries are never sent.").font(.system(size: 11)).foregroundStyle(Ink.muted)
            HStack {
                Button(controller.working ? "Testing…" : "Send test message") { controller.testConnection() }.disabled(controller.working || controller.executable == nil)
                if controller.working { Button("Cancel") { controller.cancel() } }
            }
            Text(controller.connectionStatus).font(.system(size: 11)).foregroundStyle(Ink.muted)
            if let error = controller.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
            Line()
            Text("Chats are saved on this Mac in \(controller.workspace.path)/chats.json, outside tracker backups. Each chat is also a Claude Code session; use Copy Terminal command in a chat’s menu to continue it in Terminal. Usage counts toward your Claude plan.").font(.system(size: 11)).foregroundStyle(Ink.muted).textSelection(.enabled)
        } actions: { HStack { Spacer(); PrimaryButton(label: "Done") { dismiss() } } }
    }
}
