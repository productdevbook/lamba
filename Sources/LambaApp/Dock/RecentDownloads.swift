import AppKit
import SwiftUI

extension L10n {
    static let downloadsTitle = tr("downloads.title")
    static let downloadsEmpty = tr("downloads.empty")
    static let downloadsOpenFolder = tr("downloads.openFolder")
    static let downloadsShowInFinder = tr("downloads.showInFinder")
    static let downloadsMoveToTrash = tr("downloads.moveToTrash")
    static let downloadsInProgress = tr("downloads.inProgress")
    static let dockShowDownloads = tr("downloads.show")
}

/// The newest files in ~/Downloads, kept up to date with a folder watcher.
final class RecentDownloads: ObservableObject {
    static let shared = RecentDownloads()

    struct File: Identifiable, Equatable {
        let url: URL
        let date: Date
        let size: Int64?
        /// Still being written by a browser (.crdownload, .download, .part).
        let inProgress: Bool
        var id: URL { url }
        var name: String { inProgress ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
    }

    @Published private(set) var files: [File] = []
    /// Downloads added since the popover was last opened.
    @Published private(set) var unseen = 0

    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<URL> = []
    private var started = false
    private let limit = 12
    private let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    /// Reading ~/Downloads asks for permission once, so it starts only when a Dock shows the tile.
    func start() {
        guard !started else { return }
        started = true
        reload(markSeen: true)
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            // Browsers rename the partial file when done; give them a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.reload(markSeen: false) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.source = source
    }

    func markSeen() {
        seen.formUnion(files.map(\.url))
        unseen = 0
    }

    func open(_ file: File) {
        guard !file.inProgress else { return showInFinder(file) }
        NSWorkspace.shared.open(file.url)
    }

    func showInFinder(_ file: File) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
    func openFolder() { NSWorkspace.shared.open(folder) }

    func trash(_ file: File) {
        try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        reload(markSeen: false)
    }

    private func reload(markSeen: Bool) {
        let folder = self.folder, limit = self.limit, partial = partialExtensions
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .fileSizeKey, .isDirectoryKey, .isPackageKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let files: [File] = urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                let date = values.addedToDirectoryDate ?? values.creationDate ?? .distantPast
                let isFolder = values.isDirectory == true && values.isPackage != true
                return File(url: url, date: date, size: isFolder ? nil : values.fileSize.map(Int64.init),
                            inProgress: partial.contains(url.pathExtension.lowercased()))
            }
            let newest = Array(files.sorted { $0.date > $1.date }.prefix(limit))
            DispatchQueue.main.async {
                guard let self else { return }
                if markSeen { self.seen = Set(newest.map(\.url)) }
                if self.files != newest { self.files = newest }
                self.unseen = newest.filter { !$0.inProgress && !self.seen.contains($0.url) }.count
            }
        }
    }
}

// MARK: - Tile

/// A fanned stack of the two newest downloads with a down-arrow badge; a dot counts new ones.
struct DownloadsTile: View {
    @ObservedObject var downloads = RecentDownloads.shared
    /// The strip is always dark; the islands follow the system appearance.
    var onDark = false
    @State private var frame: CGRect = .zero

    private var ink: Color { onDark ? .white : .primary }

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .bottomTrailing) {
                stack.frame(width: 40, height: 40)
                badge.offset(x: 2, y: 1)
            }
            .frame(width: 44, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ink.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.downloadsTitle)
        .accessibilityLabel(L10n.downloadsTitle)
        .frame(maxHeight: .infinity)
        .modifier(AnchorReader(frame: $frame))
        .onAppear { downloads.start() }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: downloads.files.first?.id)
    }

    @ViewBuilder private var stack: some View {
        let files = downloads.files
        if files.isEmpty {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(ink.opacity(0.7))
        } else {
            ZStack {
                if files.count > 1 {
                    Thumbnail(url: files[1].url, size: 24)
                        .rotationEffect(.degrees(-9))
                        .offset(x: -5, y: -1)
                        .opacity(0.75)
                }
                Thumbnail(url: files[0].url, size: 27)
                    .rotationEffect(.degrees(5))
                    .offset(x: 3, y: 1)
                    .id(files[0].id)
                    .transition(.offset(y: -14).combined(with: .opacity))
            }
        }
    }

    private var badge: some View {
        ZStack {
            Circle().fill(downloads.unseen > 0 ? Color.accentColor : Color(white: 0.35))
            if downloads.unseen > 0 {
                Text("\(min(downloads.unseen, 9))")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
            } else {
                Image(systemName: "arrow.down").font(.system(size: 7.5, weight: .heavy))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 15, height: 15)
    }

    private func toggle() {
        downloads.markSeen()
        DockPopover.shared.toggle(id: "downloads", anchor: frame) { DownloadsPopover(downloads: downloads) }
    }
}

// MARK: - Popover

struct DownloadsPopover: View {
    @ObservedObject var downloads: RecentDownloads

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.downloadsTitle, systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(TintedIconLabel())
                Spacer()
                Button(action: open) {
                    Text(L10n.downloadsOpenFolder)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if downloads.files.isEmpty {
                Text(L10n.downloadsEmpty)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(downloads.files) { DownloadRow(file: $0, downloads: downloads) }
                    }
                }
                .frame(height: min(CGFloat(downloads.files.count) * 50, 400))
            }
        }
        .padding(12)
        .frame(width: 320)
        .onChange(of: downloads.files.count) { _ in downloads.markSeen() }
    }

    private func open() {
        DockPopover.shared.close()
        downloads.openFolder()
    }
}

private struct TintedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.accentColor)
            configuration.title
        }
    }
}

private struct DownloadRow: View {
    let file: RecentDownloads.File
    let downloads: RecentDownloads
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: file.url, size: 36)
                .frame(width: 38, height: 38)
                .opacity(file.inProgress ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if hovered && !file.inProgress {
                Button { downloads.showInFinder(file) } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help(L10n.downloadsShowInFinder)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovered ? 0.09 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            DockPopover.shared.close()
            downloads.open(file)
        }
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .contextMenu {
            Button(L10n.downloadsShowInFinder) { downloads.showInFinder(file) }
            Button(L10n.downloadsMoveToTrash) { downloads.trash(file) }
        }
    }

    private var detail: String {
        if file.inProgress { return L10n.downloadsInProgress }
        let ago = RelativeDateTimeFormatter()
        ago.locale = L10n.locale
        ago.unitsStyle = .short
        let when = file.date > Date().addingTimeInterval(-50) ? ago.localizedString(fromTimeInterval: 0) : ago.localizedString(for: file.date, relativeTo: Date())
        guard let size = file.size else { return when }
        return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · \(when)"
    }
}
