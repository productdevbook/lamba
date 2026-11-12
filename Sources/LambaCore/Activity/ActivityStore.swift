import Foundation

/// Append-only JSON Lines log of `ActivityRecord`s.
public final class ActivityStore {
    public static let retentionDays = 400

    private let url: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    public init(url: URL = LambaPaths.appSupportDirectory.appendingPathComponent("activity.jsonl")) {
        self.url = url
    }

    public func append(_ record: ActivityRecord) {
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? line.write(to: url, options: .atomic)
        }
    }

    /// All records; malformed lines are skipped.
    public func load() -> [ActivityRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(ActivityRecord.self, from: Data($0)) }
    }

    /// Drops records older than the retention window.
    public func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let records = load()
        let kept = records.filter { $0.end >= cutoff }
        guard kept.count < records.count else { return }
        let lines = kept.compactMap { try? encoder.encode($0) }
        var data = Data(lines.joined(separator: [0x0A]))
        if !data.isEmpty { data.append(0x0A) }
        try? data.write(to: url, options: .atomic)
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Turns a stream of "value changed" calls into closed time segments.
public final class SegmentRecorder {
    private let kind: ActivityRecord.Kind
    private let sink: (ActivityRecord) -> Void
    private var open: (value: String, start: Date)?

    public init(kind: ActivityRecord.Kind, sink: @escaping (ActivityRecord) -> Void) {
        self.kind = kind
        self.sink = sink
    }

    /// Records that `value` holds from `date` on. Repeating the same value does nothing.
    public func update(_ value: String, at date: Date = Date()) {
        if open?.value == value { return }
        close(at: date)
        open = (value, date)
    }

    /// The running segment up to `date`, without closing it.
    public func snapshot(at date: Date = Date()) -> ActivityRecord? {
        open.map { ActivityRecord(kind: kind, start: $0.start, end: date, value: $0.value) }
    }

    /// Closes the current segment (e.g. on quit). Segments under a second are dropped as noise.
    public func close(at date: Date = Date()) {
        guard let open else { return }
        self.open = nil
        let record = ActivityRecord(kind: kind, start: open.start, end: date, value: open.value)
        if record.duration >= 1 { sink(record) }
    }
}
