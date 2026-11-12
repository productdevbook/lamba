import SwiftUI

/// Settings › Integrations: machines whose Claude Code sessions report here over SSH.
/// Adding one runs `lamba ssh-setup <host>`; Lamba then keeps a background tunnel to it.
struct RemoteMachinesSection: View {
    @ObservedObject var model: AppModel
    @State private var host = ""
    @State private var isAdding = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmRemove: String?

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { trimmedHost.range(of: #"^[A-Za-z0-9._@-]+$"#, options: .regularExpression) != nil }

    var body: some View {
        Section {
            if model.remoteMachines.isEmpty {
                Text(L10n.sshEmpty).foregroundStyle(.secondary)
            }
            ForEach(model.remoteMachines) { machine in
                HStack(spacing: 8) {
                    Circle()
                        .fill(machine.isConnected ? Theme.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(machine.name).font(.system(size: 13, weight: .medium))
                    Text(machine.isConnected ? L10n.agentConnected : L10n.agentOffline)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.sshRemove, role: .destructive) { confirmRemove = machine.name }
                        .controlSize(.small)
                }
            }
            HStack {
                TextField(L10n.sshHost, text: $host, prompt: Text(verbatim: "user@server"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .disabled(isAdding)
                if isAdding { ProgressView().controlSize(.small) }
                Button(L10n.sshAdd, action: add).disabled(!isValid || isAdding)
            }
            if let result {
                Label(result.ok ? L10n.sshAdded : L10n.sshFailed,
                      systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.ok ? Theme.green : Theme.orange)
                    .font(.system(size: 12))
                Text(result.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
        } header: {
            Text(L10n.sshSection)
        } footer: {
            Text(L10n.sshFooter).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .confirmationDialog(
            L10n.sshRemoveTitle(confirmRemove ?? ""),
            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })
        ) {
            Button(L10n.sshRemove, role: .destructive) {
                if let name = confirmRemove { model.tunnels?.remove(name) }
                confirmRemove = nil
            }
        } message: {
            Text(L10n.sshRemoveBody)
        }
    }

    private func add() {
        guard isValid, !isAdding, let tunnels = model.tunnels else { return }
        isAdding = true
        result = nil
        tunnels.add(trimmedHost) { ok, output in
            isAdding = false
            result = (ok, output)
            if ok { host = "" }
        }
    }
}

extension L10n {
    static var sshSection: String { tr("ssh.section") }
    static var sshEmpty: String { tr("ssh.empty") }
    static var sshHost: String { tr("ssh.host") }
    static var sshAdd: String { tr("ssh.add") }
    static var sshAdded: String { tr("ssh.added") }
    static var sshFailed: String { tr("ssh.failed") }
    static var sshRemove: String { tr("ssh.remove") }
    static func sshRemoveTitle(_ host: String) -> String { format("ssh.removeTitle", host) }
    static var sshRemoveBody: String { tr("ssh.removeBody") }
    static var sshFooter: String { tr("ssh.footer") }
    static var lightsSection: String { tr("settings.lights") }
}

extension L10n {
    static var connSection: String { tr("conn.section") }
    static var connHooksTitle: String { tr("conn.hooks.title") }
    static var connHooksCaption: String { tr("conn.hooks.caption") }
    static var connMCPTitle: String { tr("conn.mcp.title") }
    static var connMCPCaption: String { tr("conn.mcp.caption") }
    static var connDesktopTitle: String { tr("conn.desktop.title") }
    static var connDesktopCaption: String { tr("conn.desktop.caption") }
    static var connConnect: String { tr("conn.connect") }
    static var connConnected: String { tr("conn.connected") }
    static var connAdvanced: String { tr("conn.advanced") }
}

extension L10n {
    static var sleepDisabled: String { tr("sleep.disabled") }
    static var sleepFooter: String { tr("sleep.footer") }
    static var sleepFailed: String { tr("sleep.failed") }
}
