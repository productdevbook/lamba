import AppKit
import Combine

struct DockItem: Identifiable, Equatable {
    let path: String
    let name: String
    let icon: NSImage
    var isPinned: Bool
    var isRunning: Bool
    var isActive: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    static func == (lhs: DockItem, rhs: DockItem) -> Bool {
        lhs.path == rhs.path && lhs.isPinned == rhs.isPinned && lhs.isRunning == rhs.isRunning && lhs.isActive == rhs.isActive
    }
}

/// Pinned and running apps for the Lamba Dock, kept in sync with NSWorkspace.
final class DockModel: ObservableObject {
    @Published private(set) var pinned: [DockItem] = []
    @Published private(set) var others: [DockItem] = []

    private var pinnedPaths: [String] {
        didSet { Preferences.dockPinnedPaths = pinnedPaths }
    }

    private var icons: [String: NSImage] = [:]
    private var names: [String: String] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        pinnedPaths = Preferences.dockPinnedPaths ?? AppleDock.pinnedAppPaths()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningPaths = Set(running.compactMap { $0.bundleURL?.path })
        let activePath = NSWorkspace.shared.frontmostApplication?.bundleURL?.path

        func item(_ path: String, pinned: Bool) -> DockItem {
            DockItem(
                path: path,
                name: name(for: path),
                icon: icon(for: path),
                isPinned: pinned,
                isRunning: runningPaths.contains(path),
                isActive: path == activePath
            )
        }

        let newPinned = pinnedPaths.map { item($0, pinned: true) }
        let pinnedSet = Set(pinnedPaths)
        let newOthers = running.compactMap(\.bundleURL?.path)
            .filter { !pinnedSet.contains($0) }
            .map { item($0, pinned: false) }
        if newPinned != pinned { pinned = newPinned }
        if newOthers != others { others = newOthers }
    }

    /// The apps for an island: `paths` in order, then (optionally) every other running app.
    ///
    /// Derived from `pinned` and `others`, which are kept in sync with NSWorkspace, so it is cheap
    /// enough to call while a view renders and always agrees with them.
    func items(forPaths paths: [String], includeOtherRunning: Bool) -> [DockItem] {
        let known = Dictionary((pinned + others).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var result = paths.map { path in
            known[path] ?? DockItem(path: path, name: name(for: path), icon: icon(for: path), isPinned: pinnedPaths.contains(path), isRunning: false, isActive: false)
        }
        if includeOtherRunning {
            let listed = Set(paths)
            result += (pinned + others).filter { $0.isRunning && !listed.contains($0.path) }
        }
        return result
    }

    // MARK: Actions

    /// Launches the app, or brings it forward (reopening a window) if it is running.
    func open(_ item: DockItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration)
    }

    func open(_ files: [URL], with item: DockItem) {
        NSWorkspace.shared.open(files, withApplicationAt: item.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func hide(_ item: DockItem) {
        runningApp(item)?.hide()
    }

    func quit(_ item: DockItem) {
        runningApp(item)?.terminate()
    }

    func showInFinder(_ item: DockItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func pin(_ item: DockItem) {
        guard !pinnedPaths.contains(item.path) else { return }
        pinnedPaths.append(item.path)
        refresh()
    }

    func unpin(_ item: DockItem) {
        guard item.path != AppleDock.finderPath else { return }
        pinnedPaths.removeAll { $0 == item.path }
        refresh()
    }

    func move(_ item: DockItem, by offset: Int) {
        guard let index = pinnedPaths.firstIndex(of: item.path) else { return }
        let target = index + offset
        // Finder stays first, like in the system Dock.
        guard target >= 1, target < pinnedPaths.count, index >= 1 else { return }
        pinnedPaths.swapAt(index, target)
        refresh()
    }

    func reimportFromAppleDock() {
        pinnedPaths = AppleDock.pinnedAppPaths()
        refresh()
    }

    static func moveToTrash(_ files: [URL]) {
        for file in files {
            try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
    }

    static func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    private func runningApp(_ item: DockItem) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == item.path }
    }

    private func name(for path: String) -> String {
        if let cached = names[path] { return cached }
        let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        names[path] = name
        return name
    }

    private func icon(for path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
