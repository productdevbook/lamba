import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

extension L10n {
    static let shelfTitle = tr("shelf.title")
    static let shelfAirDrop = tr("shelf.airdrop")
    static let shelfCopyPaths = tr("shelf.copyPaths")
    static let shelfCopied = tr("shelf.copied")
    static let shelfClear = tr("shelf.clear")
    static let shelfShowInFinder = tr("shelf.showInFinder")
    static let shelfRemove = tr("shelf.remove")
    static func shelfTile(_ count: Int) -> String { format("shelf.tile", count) }
    static func shelfCount(_ count: Int) -> String { format("shelf.count", count) }
}

/// Files parked on the Dock shelf, kept across launches.
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []

    static let defaultsKey = "dockShelf"
    static let limit = 20
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        if items.count != paths.count { save() }
    }

    func add(_ urls: [URL]) {
        var new = items
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            if !new.contains(url) { new.append(url) }
        }
        if new.count > Self.limit { new = Array(new.suffix(Self.limit)) }
        guard new != items else { return }
        items = new
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() { defaults.set(items.map(\.path), forKey: Self.defaultsKey) }
}

// MARK: - Thumbnails

private enum Thumbnails {
    static let cache = NSCache<NSString, NSImage>()

    static func key(_ url: URL, _ size: CGFloat) -> NSString { "\(url.path)@\(Int(size))" as NSString }

    static func icon(_ url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static func load(_ url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        if let image = cache.object(forKey: key(url, size)) { return completion(image) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation else { return }
            let image = representation.nsImage
            cache.setObject(image, forKey: key(url, size))
            DispatchQueue.main.async { completion(image) }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? Thumbnails.icon(url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .onAppear { load() }
            .onChange(of: url) { _ in image = nil; load() }
    }

    private func load() { Thumbnails.load(url, size: size) { image = $0 } }
}

// MARK: - Tile

/// The shelf tile in the right island: a small stack of the parked files with a count; opens the
/// shelf popover on click. Renders nothing when the shelf is empty.
struct ShelfTile: View {
    @ObservedObject var shelf: ShelfModel
    @State private var frame: CGRect = .zero

    var body: some View {
        if let top = shelf.items.last {
            Button {
                DockPopover.shared.toggle(id: "shelf", anchor: frame) { ShelfPopover(shelf: shelf) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if shelf.items.count > 1 {
                            Thumbnail(url: shelf.items[shelf.items.count - 2], size: 26)
                                .rotationEffect(.degrees(-8))
                                .offset(x: -7, y: -1)
                                .opacity(0.8)
                        }
                        Thumbnail(url: top, size: 28)
                            .rotationEffect(.degrees(4))
                            .offset(x: 4, y: 1)
                    }
                    .frame(width: 52, height: 40)
                    Text("\(shelf.items.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4.5)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(Color.accentColor))
                }
                .frame(width: 52, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shelfTile(shelf.items.count))
            .frame(maxHeight: .infinity)
            .modifier(AnchorReader(frame: $frame))
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

// MARK: - Popover

private struct ShelfPopover: View {
    @ObservedObject var shelf: ShelfModel
    @State private var copied = false

    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.shelfTitle).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L10n.shelfCount(shelf.items.count)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shelf.items, id: \.self) { url in
                        ShelfItem(url: url, shelf: shelf)
                    }
                }
            }
            .frame(height: min(CGFloat((shelf.items.count + 2) / 3) * 104, 312))
            HStack(spacing: 8) {
                action("airplayaudio", L10n.shelfAirDrop, airDrop)
                action(copied ? "checkmark" : "doc.on.doc", copied ? L10n.shelfCopied : L10n.shelfCopyPaths, copyPaths)
                Spacer()
                action("xmark.circle", L10n.shelfClear) {
                    DockPopover.shared.close()
                    shelf.clear()
                }
            }
        }
        .padding(14)
        .frame(width: 282)
        .onChange(of: shelf.items.isEmpty) { empty in if empty { DockPopover.shared.close() } }
    }

    private func action(_ symbol: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func airDrop() {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        DockPopover.shared.close()
        service.perform(withItems: shelf.items)
    }

    private func copyPaths() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(shelf.items.map { $0 as NSURL })
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString(shelf.items.map(\.path).joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

private struct ShelfItem: View {
    let url: URL
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        VStack(spacing: 4) {
            Thumbnail(url: url, size: 64)
                .frame(width: 64, height: 64)
            Text(url.lastPathComponent)
                .font(.system(size: 10.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 80)
        }
        .padding(.vertical, 4)
        .frame(width: 84)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) {
            DockPopover.shared.close()
            NSWorkspace.shared.open(url)
        }
        .contextMenu {
            Button(L10n.shelfShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(L10n.shelfRemove) { shelf.remove(url) }
        }
        .accessibilityLabel(url.lastPathComponent)
    }
}

// MARK: - Drop target

/// The whole right island takes dropped files. While files are dragged over it, it splits into
/// two large targets: park them on the shelf, or shrink and convert them. The half under the
/// pointer decides.
private struct IslandDropTarget: ViewModifier {
    let shelf: ShelfModel
    @AppStorage(Preferences.Key.dockConvert) private var convertEnabled = true
    @State private var targeted = false
    @State private var overConvert = false
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .overlay { if targeted { zones.transition(.opacity) } }
            .animation(.easeOut(duration: 0.15), value: targeted)
            .animation(.easeOut(duration: 0.12), value: overConvert)
            .modifier(AnchorReader(frame: $frame))
            .onDrop(of: [.fileURL], delegate: Delegate(
                width: { frame.width },
                convertEnabled: convertEnabled,
                targeted: $targeted,
                overConvert: $overConvert,
                drop: drop
            ))
    }

    private var zones: some View {
        DropZones(convertEnabled: convertEnabled, overConvert: overConvert)
    }

    private func drop(_ urls: [URL], convert: Bool) {
        if convert {
            MediaConverter.shared.set(urls)
            DockPopover.shared.close()
            DockPopover.shared.toggle(id: "convert", anchor: frame) { ConvertPopover(converter: .shared) }
        } else {
            shelf.add(urls)
        }
    }

    private struct Delegate: DropDelegate {
        let width: () -> CGFloat
        let convertEnabled: Bool
        @Binding var targeted: Bool
        @Binding var overConvert: Bool
        let drop: ([URL], Bool) -> Void

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

        func dropEntered(info: DropInfo) {
            targeted = true
            update(info)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            update(info)
            return DropProposal(operation: .copy)
        }

        func dropExited(info: DropInfo) { targeted = false }

        func performDrop(info: DropInfo) -> Bool {
            let convert = convertEnabled && info.location.x > width() / 2
            targeted = false
            FileDrop.load(info.itemProviders(for: [.fileURL])) { drop($0, convert) }
            return true
        }

        private func update(_ info: DropInfo) {
            overConvert = convertEnabled && info.location.x > width() / 2
        }
    }
}

/// The two targets shown over the right island while files are dragged over it.
struct DropZones: View {
    let convertEnabled: Bool
    let overConvert: Bool

    var body: some View {
        HStack(spacing: 6) {
            zone(symbol: "tray.and.arrow.down.fill", title: L10n.shelfTitle, active: !overConvert)
            if convertEnabled {
                zone(symbol: "wand.and.stars", title: L10n.convertTitle, active: overConvert)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
        .allowsHitTesting(false)
    }

    private func zone(symbol: String, title: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            Text(title).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(active ? Color.white : Color.primary.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Color.accentColor : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(active ? 0 : 0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .scaleEffect(active ? 1 : 0.96)
    }
}

extension View {
    /// Accepts files dropped anywhere on this view (the whole right island): shelf or convert.
    func shelfDropTarget(_ shelf: ShelfModel) -> some View { modifier(IslandDropTarget(shelf: shelf)) }
}
