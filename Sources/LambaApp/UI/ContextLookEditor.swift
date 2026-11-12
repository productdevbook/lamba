import AppKit
import LambaCore
import SwiftUI

/// "When switching to this context": wallpaper, appearance, tint, LED, shortcut, apps to open/hide.
struct ContextLookEditor: View {
    @Binding var context: DockContext
    let tryNow: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                row(L10n.ctxWallpaper) { wallpaper }
                row(L10n.ctxAppearance) {
                    Picker(L10n.ctxAppearance, selection: $context.look.appearance) {
                        Text(L10n.ctxAppearanceLight).tag(ContextLook.Appearance?.some(.light))
                        Text(L10n.ctxAppearanceDark).tag(ContextLook.Appearance?.some(.dark))
                        Text(L10n.ctxAppearanceKeep).tag(ContextLook.Appearance?.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
                Toggle(L10n.ctxTint, isOn: $context.look.tintDock)
                row(L10n.ctxFlash) {
                    Picker(L10n.ctxFlash, selection: $context.look.flashColor) {
                        Text(L10n.ctxFlashGreen).tag(LightState?.some(.green))
                        Text(L10n.ctxFlashOrange).tag(LightState?.some(.orange))
                        Text(L10n.ctxFlashNone).tag(LightState?.none)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }
                VStack(alignment: .leading, spacing: 4) {
                    row(L10n.ctxShortcut) {
                        ShortcutPicker(selection: Binding(
                            get: { context.look.shortcut ?? "" },
                            set: { context.look.shortcut = $0.isEmpty ? nil : $0 }
                        ))
                    }
                    Text(L10n.ctxShortcutHint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                AppListEditor(title: L10n.ctxOpenApps, paths: $context.look.openApps)
                AppListEditor(title: L10n.ctxHideApps, paths: $context.look.hideApps)
                HStack {
                    Spacer()
                    Button(action: tryNow) { Label(L10n.ctxTryNow, systemImage: "play.fill") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(L10n.ctxLook).font(.system(size: 12, weight: .semibold))
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(title).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: Wallpaper

    private var customPath: String? {
        guard let value = context.look.wallpaper, BuiltinWallpaper(reference: value) == nil else { return nil }
        return value
    }

    private var wallpaper: some View {
        HStack(spacing: 8) {
            swatch(selected: context.look.wallpaper == nil, label: L10n.ctxWallpaperKeep) {
                context.look.wallpaper = nil
            } content: {
                Image(systemName: "nosign").foregroundStyle(.secondary)
            }
            ForEach(BuiltinWallpaper.allCases) { paper in
                swatch(selected: context.look.wallpaper == paper.reference, label: paper.rawValue.capitalized) {
                    context.look.wallpaper = paper.reference
                } content: {
                    let colors = paper.colors
                    ZStack {
                        Color(nsColor: colors.base)
                        Circle().fill(Color(nsColor: colors.shapeA)).frame(width: 30, height: 30).offset(x: 10, y: 8)
                        Circle().fill(Color(nsColor: colors.shapeB)).frame(width: 16, height: 16).offset(x: -12, y: -8)
                    }
                }
            }
            swatch(selected: customPath != nil, label: L10n.ctxWallpaperOwn) {
                if let url = AppPicker.pickImage() { context.look.wallpaper = url.path }
            } content: {
                if let path = customPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func swatch<Content: View>(
        selected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 52, height: 36)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A list of app paths with add and remove.
private struct AppListEditor: View {
    let title: String
    @Binding var paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button {
                    let picked = AppPicker.pick(multiple: true).map(\.path)
                    paths.append(contentsOf: picked.filter { !paths.contains($0) })
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.ctxAddApp + ": " + title)
                    .help(L10n.ctxAddApp)
            }
            if paths.isEmpty {
                Text(L10n.ctxListEmpty).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                    Text(AppPicker.name(of: path)).lineLimit(1)
                    Spacer()
                    Button { paths.remove(at: index) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.ctxRemoveApp(AppPicker.name(of: path)))
                }
            }
        }
    }
}

/// Loads the user's shortcuts off the main thread and offers them in a menu. "" means none.
struct ShortcutPicker: View {
    @Binding var selection: String
    @State private var names: [String] = []
    @State private var loaded = false

    var body: some View {
        Picker(L10n.ctxShortcut, selection: $selection) {
            Text(L10n.ctxShortcutNone).tag("")
            if !selection.isEmpty, !names.contains(selection) { Text(selection).tag(selection) }
            ForEach(names, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        .task {
            guard !loaded else { return }
            names = await Task.detached { ShortcutsRunner.list() }.value
            loaded = true
        }
    }
}
