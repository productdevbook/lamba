import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension L10n {
    static let convertTitle = tr("convert.title")
    static let convertDropHint = tr("convert.dropHint")
    static let convertImages = tr("convert.images")
    static let convertVideos = tr("convert.videos")
    static let convertFormat = tr("convert.format")
    static let convertSameFormat = tr("convert.sameFormat")
    static let convertSize = tr("convert.size")
    static let convertOriginalSize = tr("convert.originalSize")
    static let convertQuality = tr("convert.quality")
    static let convertVideoSmaller = tr("convert.video.smaller")
    static let convertVideoMP4 = tr("convert.video.mp4")
    static let convertVideo720 = tr("convert.video.720")
    static let convertStart = tr("convert.start")
    static let convertShow = tr("convert.show")
    static let convertDone = tr("convert.done")
    static let convertClear = tr("convert.clear")
    static let convertShowTile = tr("convert.showTile")
    static let convertNothing = tr("convert.nothing")
    static let convertFooter = tr("convert.footer")
    static func convertCount(_ images: Int, _ videos: Int) -> String { format("convert.count", images, videos) }
}

/// Shrinks and converts images (ImageIO) and videos (AVFoundation). Results go to ~/Downloads,
/// so they show up in Recent Downloads; a dropped folder becomes a new folder with the same layout.
final class MediaConverter: ObservableObject {
    static let shared = MediaConverter()

    enum ImageFormat: String, CaseIterable, Identifiable {
        case same, jpeg, png, heic
        var id: Self { self }
        var type: UTType? {
            switch self {
            case .same: return nil
            case .jpeg: return .jpeg
            case .png: return .png
            case .heic: return .heic
            }
        }
    }

    enum VideoPreset: String, CaseIterable, Identifiable {
        /// HEVC at the source size: about half the size, same look.
        case smaller
        /// H.264 MP4 up to 1080p: plays everywhere.
        case mp4
        /// H.264 MP4 at 720p: smallest.
        case p720
        var id: Self { self }
        var exportPreset: String {
            switch self {
            case .smaller: return AVAssetExportPresetHEVCHighestQuality
            case .mp4: return AVAssetExportPreset1920x1080
            case .p720: return AVAssetExportPreset1280x720
            }
        }
    }

    struct Job: Identifiable, Equatable {
        let id = UUID()
        let source: URL
        let output: URL
        let isVideo: Bool
        var progress: Double = 0
        var resultSize: Int64?
        var error: String?
        var isDone: Bool { resultSize != nil || error != nil }
    }

    /// One dropped item: a file, or a folder whose media keep their relative paths.
    private struct Input {
        let file: URL
        let relativeDirectory: String?
        let rootName: String?
    }

    @Published private(set) var inputs: [URL] = []
    @Published private(set) var imageCount = 0
    @Published private(set) var videoCount = 0
    @Published var imageFormat: ImageFormat = .same
    /// Longest edge in pixels; 0 keeps the size.
    @Published var maxPixels = 0
    @Published var quality = 0.8
    @Published var videoPreset: VideoPreset = .smaller
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var isRunning = false

    private var files: [Input] = []
    /// `LAMBA_CONVERT_OUT` redirects the output for development.
    let outputRoot = ProcessInfo.processInfo.environment["LAMBA_CONVERT_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)

    var hasWork: Bool { imageCount + videoCount > 0 }
    var isFinished: Bool { !jobs.isEmpty && jobs.allSatisfy(\.isDone) }

    func set(_ urls: [URL]) {
        guard !isRunning else { return }
        jobs = []
        inputs = urls
        files = urls.flatMap(Self.expand)
        imageCount = files.filter { Self.isImage($0.file) }.count
        videoCount = files.filter { Self.isVideo($0.file) }.count
    }

    func clear() {
        guard !isRunning else { return }
        set([])
    }

    func start() {
        guard hasWork, !isRunning else { return }
        isRunning = true
        var reserved = Set<String>()
        jobs = files.compactMap { input in
            let isVideo = Self.isVideo(input.file)
            guard isVideo || Self.isImage(input.file) else { return nil }
            let output = outputURL(for: input, isVideo: isVideo, reserved: &reserved)
            return Job(source: input.file, output: output, isVideo: isVideo)
        }
        let settings = (imageFormat, maxPixels, quality, videoPreset)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for job in await self.currentJobs() {
                let result: Result<Int64, Error>
                if job.isVideo {
                    result = await Self.convertVideo(job.source, to: job.output, preset: settings.3) { progress in
                        Task { @MainActor in self.update(job.id) { $0.progress = progress } }
                    }
                } else {
                    result = Result { try Self.convertImage(job.source, to: job.output, format: settings.0, maxPixels: settings.1, quality: settings.2) }
                }
                await MainActor.run {
                    self.update(job.id) {
                        $0.progress = 1
                        switch result {
                        case let .success(size): $0.resultSize = size
                        case let .failure(error): $0.error = error.localizedDescription
                        }
                    }
                }
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    func showResults() {
        let outputs = jobs.filter { $0.resultSize != nil }.map(\.output)
        NSWorkspace.shared.activateFileViewerSelecting(outputs.isEmpty ? [outputRoot] : outputs)
    }

    @MainActor private func currentJobs() -> [Job] { jobs }

    @MainActor private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    // MARK: Naming

    private func outputURL(for input: Input, isVideo: Bool, reserved: inout Set<String>) -> URL {
        var directory = outputRoot
        if let root = input.rootName {
            directory.appendPathComponent("\(root) (Lamba)", isDirectory: true)
            if let relative = input.relativeDirectory, !relative.isEmpty { directory.appendPathComponent(relative, isDirectory: true) }
        }
        let base = input.file.deletingPathExtension().lastPathComponent
        let ext: String
        if isVideo {
            ext = "mp4"
        } else {
            ext = Self.imageType(for: input.file, format: imageFormat).preferredFilenameExtension ?? "jpg"
        }
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) || reserved.contains(candidate.path) || candidate.standardizedFileURL == input.file.standardizedFileURL {
            candidate = directory.appendingPathComponent("\(base) \(number).\(ext)")
            number += 1
        }
        reserved.insert(candidate.path)
        return candidate
    }

    // MARK: Inputs

    private static func expand(_ url: URL) -> [Input] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return [] }
        guard isFolder.boolValue else { return [Input(file: url, relativeDirectory: nil, rootName: nil)] }
        let root = url.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var found: [Input] = []
        while let file = enumerator?.nextObject() as? URL {
            guard isImage(file) || isVideo(file) else { continue }
            let parent = file.deletingLastPathComponent().standardizedFileURL.path
            let relative = parent.hasPrefix(root) ? String(parent.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : nil
            found.append(Input(file: file, relativeDirectory: relative, rootName: url.lastPathComponent))
        }
        return found
    }

    private static func type(of url: URL) -> UTType? { UTType(filenameExtension: url.pathExtension.lowercased()) }
    static func isImage(_ url: URL) -> Bool { type(of: url)?.conforms(to: .image) == true }
    static func isVideo(_ url: URL) -> Bool { type(of: url)?.conforms(to: .movie) == true }

    /// "Same format" keeps formats ImageIO can write; anything else (WebP, RAW…) becomes JPEG.
    private static func imageType(for url: URL, format: ImageFormat) -> UTType {
        if let chosen = format.type { return chosen }
        let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        if let source = type(of: url), writable.contains(source.identifier), source != .gif { return source }
        return .jpeg
    }

    // MARK: Converting

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static func convertImage(_ source: URL, to output: URL, format: ImageFormat, maxPixels: Int, quality: Double) throws -> Int64 {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw Failure(errorDescription: "Unreadable image") }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let resize = maxPixels > 0 && longest > maxPixels

        // The thumbnail path applies the EXIF orientation, so the result needs none.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: resize ? maxPixels : max(longest, 1),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw Failure(errorDescription: "Unreadable image")
        }

        let type = imageType(for: source, format: format)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure(errorDescription: "Can't write \(type.preferredFilenameExtension ?? "image")")
        }
        var outProperties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let color = properties[kCGImagePropertyProfileName] { outProperties[kCGImagePropertyProfileName] = color }
        CGImageDestinationAddImage(destination, image, outProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure(errorDescription: "Couldn't save") }
        return fileSize(output)
    }

    private static func convertVideo(_ source: URL, to output: URL, preset: VideoPreset, progress: @escaping (Double) -> Void) async -> Result<Int64, Error> {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset.exportPreset) else {
            return .failure(Failure(errorDescription: "This video can't be converted"))
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let ticker = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        await session.export()
        ticker.cancel()
        if session.status == .completed { return .success(fileSize(output)) }
        try? FileManager.default.removeItem(at: output)
        return .failure(session.error ?? Failure(errorDescription: "Export failed"))
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - Tile

/// Drop images, videos or folders here to shrink or convert them.
struct ConvertTile: View {
    @ObservedObject var converter = MediaConverter.shared
    var onDark = false
    /// In the islands Dock the whole right island takes the drop instead.
    var acceptsDrop = true
    @State private var frame: CGRect = .zero
    @State private var targeted = false

    private var ink: Color { onDark ? .white : .primary }

    var body: some View {
        Button(action: open) {
            ZStack {
                Image(systemName: converter.isRunning ? "arrow.triangle.2.circlepath" : "wand.and.stars")
                    .font(.system(size: 17))
                    .foregroundStyle(targeted ? Color.accentColor : ink.opacity(0.75))
                    .rotationEffect(.degrees(converter.isRunning ? 360 : 0))
                    .animation(converter.isRunning ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .default, value: converter.isRunning)
            }
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(targeted ? Color.accentColor.opacity(0.2) : ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(targeted ? 1.08 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: targeted)
        }
        .buttonStyle(.plain)
        .help(L10n.convertTitle)
        .accessibilityLabel(L10n.convertTitle)
        .frame(maxHeight: .infinity)
        .modifier(AnchorReader(frame: $frame))
        .onDrop(of: acceptsDrop ? [.fileURL] : [], isTargeted: $targeted) { providers in
            FileDrop.load(providers) { urls in
                converter.set(urls)
                DockPopover.shared.close()
                open()
            }
            return true
        }
    }

    private func open() {
        DockPopover.shared.toggle(id: "convert", anchor: frame) { ConvertPopover(converter: converter) }
    }
}

// MARK: - Popover

struct ConvertPopover: View {
    @ObservedObject var converter: MediaConverter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !converter.jobs.isEmpty {
                results
            } else if converter.hasWork {
                options
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text(converter.inputs.isEmpty ? L10n.convertDropHint : L10n.convertNothing)
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
            Text(L10n.convertFooter).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars").foregroundStyle(Color.accentColor)
            Text(L10n.convertTitle)
            Spacer()
            if converter.hasWork {
                Text(L10n.convertCount(converter.imageCount, converter.videoCount))
                    .font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }

    @ViewBuilder private var options: some View {
        if converter.imageCount > 0 {
            section(L10n.convertImages) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text(L10n.convertFormat).foregroundStyle(.secondary)
                        Picker("", selection: $converter.imageFormat) {
                            Text(L10n.convertSameFormat).tag(MediaConverter.ImageFormat.same)
                            Text("JPEG").tag(MediaConverter.ImageFormat.jpeg)
                            Text("PNG").tag(MediaConverter.ImageFormat.png)
                            Text("HEIC").tag(MediaConverter.ImageFormat.heic)
                        }
                        .labelsHidden()
                    }
                    GridRow {
                        Text(L10n.convertSize).foregroundStyle(.secondary)
                        Picker("", selection: $converter.maxPixels) {
                            Text(L10n.convertOriginalSize).tag(0)
                            ForEach([3840, 2560, 1920, 1280, 800], id: \.self) { Text("\($0) px").tag($0) }
                        }
                        .labelsHidden()
                    }
                    if converter.imageFormat != .png {
                        GridRow {
                            Text(L10n.convertQuality).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Slider(value: $converter.quality, in: 0.3...1).controlSize(.small)
                                Text("\(Int(converter.quality * 100))%").font(.system(size: 11).monospacedDigit()).frame(width: 34, alignment: .trailing)
                            }
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        if converter.videoCount > 0 {
            section(L10n.convertVideos) {
                Picker("", selection: $converter.videoPreset) {
                    Text(L10n.convertVideoSmaller).tag(MediaConverter.VideoPreset.smaller)
                    Text(L10n.convertVideoMP4).tag(MediaConverter.VideoPreset.mp4)
                    Text(L10n.convertVideo720).tag(MediaConverter.VideoPreset.p720)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }
        HStack {
            Button(L10n.convertClear, action: converter.clear).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
            Button(action: converter.start) {
                Text(L10n.convertStart)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(converter.jobs) { JobRow(job: $0) }
                }
            }
            .frame(height: min(CGFloat(converter.jobs.count) * 40, 280))
            if converter.isFinished {
                HStack {
                    Label(L10n.convertDone, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    Spacer()
                    Button(L10n.convertClear, action: converter.clear).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Button(action: {
                        DockPopover.shared.close()
                        converter.showResults()
                    }) {
                        Text(L10n.convertShow)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium))
            content().font(.system(size: 11.5))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct JobRow: View {
    let job: MediaConverter.Job

    var body: some View {
        HStack(spacing: 8) {
            Thumbnail(url: job.resultSize != nil ? job.output : job.source, size: 28).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.output.lastPathComponent).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                if let error = job.error {
                    Text(error).font(.system(size: 10)).foregroundStyle(Theme.orange).lineLimit(1)
                } else if let size = job.resultSize {
                    Text(sizes(size)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    ProgressView(value: job.progress).progressViewStyle(.linear).controlSize(.mini)
                }
            }
        }
    }

    private func sizes(_ result: Int64) -> String {
        let before = MediaConverter.fileSize(job.source)
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        guard before > 0 else { return format(result) }
        let change = Int((Double(result) / Double(before) - 1) * 100)
        return "\(format(before)) → \(format(result))  (\(change > 0 ? "+" : "")\(change)%)"
    }
}
