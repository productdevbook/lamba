import AppKit
import ApplicationServices
import SwiftUI

extension L10n {
    static func windowsOf(_ name: String, _ count: Int) -> String { format("islands.windowsOf", name, count) }
    static let windowUntitled = tr("islands.untitled")
    static let windowMinimized = tr("islands.minimized")
    static let windowsNeedAccess = tr("islands.needsAccess")
    static let windowsGrantAccess = tr("islands.grantAccess")
}

/// One window of an app, as the Accessibility API reports it.
struct AppWindow: Identifiable {
    let id: Int
    let title: String
    let isMinimized: Bool
    fileprivate let element: AXUIElement
}

/// Window information for the islands Dock: cheap counts for the bars under app icons, and the
/// titles (which need the Accessibility permission) for the hover list.
enum WindowList {
    /// Open windows per process, minimized and other-Spaces windows included.
    ///
    /// `CGWindowListCopyWindowInfo` needs no Screen Recording permission for counts (only titles
    /// are withheld). Layer 0 is the normal window layer; tiny or transparent windows are helpers
    /// (tooltips, shadows, invisible backing windows), not something the user would call a window.
    static func counts() -> [pid_t: Int] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [pid_t: Int] = [:]
        for window in info {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 80, height >= 50
            else { continue }
            result[pid, default: 0] += 1
        }
        return result
    }

    /// Window counts keyed by app bundle path (what `DockItem.id` is).
    static func countsByPath() -> [String: Int] {
        let byPid = counts()
        var result: [String: Int] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let path = app.bundleURL?.path, let count = byPid[app.processIdentifier] else { continue }
            result[path, default: 0] += count
        }
        return result
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its "grant Accessibility access" prompt.
    static func requestAccess() {
        // The literal avoids touching the C global `kAXTrustedCheckOptionPrompt`.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The app's windows with titles. Empty without Accessibility access.
    static func windows(of item: DockItem) -> [AppWindow] {
        guard isTrusted else { return [] }
        var result: [AppWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.bundleURL?.path == item.path {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app would otherwise block the Dock for the default six seconds.
            AXUIElementSetMessagingTimeout(element, 0.4)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement]
            else { continue }
            for window in windows {
                let title = string(kAXTitleAttribute, of: window) ?? ""
                result.append(AppWindow(
                    id: result.count,
                    title: title.isEmpty ? L10n.windowUntitled : title,
                    isMinimized: bool(kAXMinimizedAttribute, of: window),
                    element: window
                ))
            }
        }
        return result
    }

    /// Brings one window forward (restoring it if minimized) and activates its app.
    static func raise(_ window: AppWindow, of item: DockItem) {
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSWorkspace.shared.runningApplications
            .first { $0.bundleURL?.path == item.path }?
            .activate(options: [.activateIgnoringOtherApps])
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ attribute: String, of element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}

/// Keeps window counts fresh: on request, and every couple of seconds while the Dock is shown.
final class WindowCounts: ObservableObject {
    @Published private(set) var counts: [String: Int] = [:]

    func refresh() {
        let new = WindowList.countsByPath()
        if new != counts { counts = new }
    }
}

/// Hover popover content: "Safari · 3 windows" and a row per window.
struct WindowListPopover: View {
    let item: DockItem
    let windows: [AppWindow]
    /// The count from the window server, for the header when titles aren't available.
    let count: Int
    let select: (AppWindow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.windowsOf(item.name, windows.isEmpty ? count : windows.count))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            if WindowList.isTrusted {
                ForEach(windows) { window in
                    WindowRow(window: window) { select(window) }
                }
            } else {
                Text(L10n.windowsNeedAccess)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                Button(L10n.windowsGrantAccess) {
                    DockPopover.shared.close()
                    WindowList.requestAccess()
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(width: 260, alignment: .leading)
    }
}

private struct WindowRow: View {
    let window: AppWindow
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Filled: on screen. Hollow: minimized.
            Circle()
                .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.2)
                .background(Circle().fill(window.isMinimized ? Color.clear : Color.primary.opacity(0.7)))
                .frame(width: 7, height: 7)
            Text(window.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(window.isMinimized ? 0.65 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
        .accessibilityLabel(window.isMinimized ? "\(window.title), \(L10n.windowMinimized)" : window.title)
        .accessibilityAddTraits(.isButton)
    }
}
