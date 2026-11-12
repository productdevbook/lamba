import Foundation
import LambaCore

/// Records light, charger, focus and notification activity into the local log.
final class ActivityTracker {
    private let store: ActivityStore
    private lazy var lightSegments = SegmentRecorder(kind: .light) { [store] in store.append($0) }
    private lazy var chargeSegments = SegmentRecorder(kind: .charge) { [store] in store.append($0) }

    /// Fires after anything was written, so open statistics views can refresh.
    var onRecord: (() -> Void)?

    init(store: ActivityStore = ActivityStore()) {
        self.store = store
        store.prune()
    }

    func lightModeChanged(_ mode: LightMode) {
        lightSegments.update(mode.name)
    }

    func chargeStateChanged(_ state: ChargeState) {
        chargeSegments.update(state.name)
    }

    func focusEnded(start: Date, end: Date, completed: Bool) {
        let record = ActivityRecord(kind: .focus, start: start, end: end, value: completed ? ActivityRecord.completed : ActivityRecord.partial)
        guard record.duration >= 60 || completed else { return } // ignore accidental starts
        store.append(record)
        onRecord?()
    }

    func flashed(_ color: LightState) {
        let now = Date()
        store.append(ActivityRecord(kind: .flash, start: now, end: now, value: color.rawValue))
        onRecord?()
    }

    /// Closes open segments; call on quit.
    func flush() {
        lightSegments.close()
        chargeSegments.close()
    }

    /// Builds a report; open segments are included up to now without being written.
    func report(days: Int) -> ActivityReport {
        var records = store.load()
        records += openSegments()
        return ActivityReport(records: records, dayCount: days)
    }

    func clearHistory() {
        store.removeAll()
        onRecord?()
    }

    private func openSegments() -> [ActivityRecord] {
        let now = Date()
        return [lightSegments, chargeSegments].compactMap { $0.snapshot(at: now) }
    }
}
