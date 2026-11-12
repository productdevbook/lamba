import AppKit
import LambaCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Contexts: the list on the left, the selected context's details on the right.
struct ContextSettingsView: View {
    @ObservedObject var contexts: ContextEngine
    @State private var selection: UUID?
    @State private var pendingDelete: DockContext?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
            }
            Divider()
            footer
        }
        .onAppear { if selection == nil { selection = contexts.current?.id ?? contexts.contexts.first?.id } }
        .confirmationDialog(
            pendingDelete.map { L10n.ctxDeleteTitle($0.name) } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.ctxDeleteConfirm, role: .destructive) {
                if let victim = pendingDelete { remove(victim.id) }
                pendingDelete = nil
            }
            Button(L10n.ctxCancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L10n.ctxDeleteBody)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                ForEach(contexts.contexts) { context in
                    ContextRow(context: context, isCurrent: contexts.current?.id == context.id)
                        .tag(context.id)
                        .contextMenu {
                            Button(L10n.ctxSwitchTo) { contexts.select(context.id) }
                            Divider()
                            Button(L10n.ctxDelete, role: .destructive) { pendingDelete = context }
                                .disabled(contexts.contexts.count <= 1)
                        }
                }
                .onMove { contexts.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.sidebar)
            Button {
                let created = contexts.add(name: L10n.ctxNewName)
                selection = created.id
            } label: {
                Label(L10n.ctxNew, systemImage: "plus")
            }
            .padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ctxListNote1)
                Text(L10n.ctxListNote2)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding([.horizontal, .bottom], 10)
        }
        .padding(.top, 6)
        .frame(width: 210)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let context = contexts.contexts.first(where: { $0.id == selection }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        if contexts.current?.id == context.id {
                            Label(L10n.ctxNow, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                        } else {
                            Button(L10n.ctxSwitchTo) { contexts.select(context.id) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    ContextDetailHeader(context: binding(for: context))
                    ContextAppsEditor(context: binding(for: context))
                    ContextRuleEditor(context: binding(for: context), currentSSID: contexts.currentSSID)
                    ContextLookEditor(context: binding(for: context), tryNow: { contexts.preview(context.id) })
                    HStack {
                        Spacer()
                        Button(L10n.ctxDelete, role: .destructive) { pendingDelete = context }
                            .disabled(contexts.contexts.count <= 1)
                            .help(contexts.contexts.count <= 1 ? L10n.ctxLastOne : "")
                    }
                }
                .padding(18)
            }
            .id(context.id)
        } else {
            Spacer().frame(maxWidth: .infinity)
        }
    }

    private func binding(for context: DockContext) -> Binding<DockContext> {
        let id = context.id
        return Binding(
            get: { contexts.contexts.first { $0.id == id } ?? context },
            set: { contexts.update($0) }
        )
    }

    private func remove(_ id: UUID) {
        guard contexts.contexts.count > 1 else { return }
        let index = contexts.contexts.firstIndex { $0.id == id } ?? 0
        contexts.delete(id)
        let rest = contexts.contexts
        selection = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(L10n.ctxDefault).foregroundStyle(.secondary)
            Picker(L10n.ctxDefault, selection: Binding(
                get: { contexts.defaultID ?? contexts.contexts.first?.id },
                set: { if let id = $0 { contexts.setDefault(id) } }
            )) {
                ForEach(contexts.contexts) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

private struct ContextRow: View {
    let context: DockContext
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: context.color.color))
                .frame(width: 12, height: 12)
            Text(context.name).lineLimit(1)
            Spacer(minLength: 4)
            if isCurrent {
                Text(L10n.ctxNow)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Name and color

private struct ContextDetailHeader: View {
    @Binding var context: DockContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.ctxName).frame(width: 50, alignment: .leading)
                TextField(L10n.ctxName, text: $context.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text(L10n.ctxColor).frame(width: 50, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(ContextColor.allCases, id: \.self) { color in
                        Button { context.color = color } label: {
                            Circle()
                                .fill(Color(nsColor: color.color))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: context.color == color ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue.capitalized)
                        .accessibilityAddTraits(context.color == color ? .isSelected : [])
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Apps

private struct ContextAppsEditor: View {
    @Binding var context: DockContext

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if context.appPaths.isEmpty {
                    Text(L10n.ctxAppsEmpty).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(Array(context.appPaths.enumerated()), id: \.offset) { index, path in
                        AppIconCell(path: path, onRemove: { context.appPaths.remove(at: index) })
                            .contextMenu {
                                Button(L10n.ctxMoveLeft) { context.appPaths.swapAt(index, index - 1) }
                                    .disabled(index == 0)
                                Button(L10n.ctxMoveRight) { context.appPaths.swapAt(index, index + 1) }
                                    .disabled(index == context.appPaths.count - 1)
                                Button(L10n.ctxRemoveApp(AppPicker.name(of: path)), role: .destructive) {
                                    context.appPaths.remove(at: index)
                                }
                            }
                    }
                    Button {
                        let picked = AppPicker.pick(multiple: true).map(\.path)
                        context.appPaths.append(contentsOf: picked.filter { !context.appPaths.contains($0) })
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.ctxAddApp)
                    .help(L10n.ctxAddApp)
                }
                Toggle(L10n.ctxShowOthers, isOn: $context.showOtherRunningApps)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(L10n.ctxApps).font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct AppIconCell: View {
    let path: String
    let onRemove: () -> Void

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel(L10n.ctxRemoveApp(AppPicker.name(of: path)))
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
            .help(AppPicker.name(of: path))
            .accessibilityElement(children: .contain)
    }
}

/// `NSOpenPanel` helpers for apps and images.
enum AppPicker {
    static func pick(multiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func pickImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func name(of path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    static func bundleID(of url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }
}
