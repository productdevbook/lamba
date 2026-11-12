import Foundation

/// Aggregated statistics for a range of days. Pure: built from records, a range and a calendar.
public struct ActivityReport: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable, Identifiable {
        public var date: Date
        public var focusSeconds: TimeInterval
        public var completedSessions: Int
        public var id: Date { date }
    }

    public struct Share: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var seconds: TimeInterval
        public var id: String { name }
    }

    public var days: [Day]
    public var focusSeconds: TimeInterval
    public var previousFocusSeconds: TimeInterval
    public var completedSessions: Int
    public var streakDays: Int
    public var flashes: Int
    /// Time per light mode, largest first.
    public var light: [Share]
    /// Time per charger state, largest first.
    public var charge: [Share]

    public var averageFocusPerDay: TimeInterval {
        days.isEmpty ? 0 : focusSeconds / Double(days.count)
    }

    /// The `dayCount` days ending with `now`'s day.
    public init(records: [ActivityRecord], dayCount: Int, now: Date = Date(), calendar: Calendar = .current) {
        let dayCount = max(1, dayCount)
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today)!
        let range = DateInterval(start: firstDay, end: now)
        let previousRange = DateInterval(start: calendar.date(byAdding: .day, value: -dayCount, to: firstDay)!, end: firstDay)

        let focus = records.filter { $0.kind == .focus }
        days = (0..<dayCount).map { offset in
            let start = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
            return Day(
                date: start,
                focusSeconds: focus.reduce(0) { $0 + $1.overlap(with: interval) },
                completedSessions: focus.filter { $0.value == ActivityRecord.completed && interval.contains($0.end) }.count
            )
        }
        focusSeconds = days.reduce(0) { $0 + $1.focusSeconds }
        previousFocusSeconds = focus.reduce(0) { $0 + $1.overlap(with: previousRange) }
        completedSessions = days.reduce(0) { $0 + $1.completedSessions }
        flashes = records.filter { $0.kind == .flash && range.contains($0.start) }.count
        light = Self.shares(of: records.filter { $0.kind == .light }, in: range)
        charge = Self.shares(of: records.filter { $0.kind == .charge }, in: range)
        streakDays = Self.streak(focus: focus, today: today, calendar: calendar)
    }

    private static func shares(of records: [ActivityRecord], in range: DateInterval) -> [Share] {
        var totals: [String: TimeInterval] = [:]
        for record in records {
            totals[record.value, default: 0] += record.overlap(with: range)
        }
        return totals.filter { $0.value >= 60 }
            .map { Share(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Consecutive days with at least one completed session, ending today (or yesterday, so an
    /// unfinished today does not break the streak).
    private static func streak(focus: [ActivityRecord], today: Date, calendar: Calendar) -> Int {
        let activeDays = Set(focus.filter { $0.value == ActivityRecord.completed }.map { calendar.startOfDay(for: $0.end) })
        var day = activeDays.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var count = 0
        while activeDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

// MARK: - Export

extension ActivityReport {
    /// One row per day; minutes rounded to one decimal.
    public func csv(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["date,focus_minutes,completed_sessions"]
        for day in days {
            lines.append("\(formatter.string(from: day.date)),\(String(format: "%.1f", day.focusSeconds / 60)),\(day.completedSessions)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Plain-text summary used by the CLI and the MCP `get_report` tool.
    public var summary: String {
        func minutes(_ seconds: TimeInterval) -> String { "\(Int((seconds / 60).rounded())) min" }
        var lines = [
            "Days: \(days.count)",
            "Focus: \(minutes(focusSeconds)) (previous period: \(minutes(previousFocusSeconds)))",
            "Average focus per day: \(minutes(averageFocusPerDay))",
            "Completed sessions: \(completedSessions)",
            "Streak: \(streakDays) day(s)",
            "Notification flashes: \(flashes)",
        ]
        if !light.isEmpty {
            lines.append("Light: " + light.map { "\($0.name) \(minutes($0.seconds))" }.joined(separator: ", "))
        }
        if !charge.isEmpty {
            lines.append("Charger: " + charge.map { "\($0.name) \(minutes($0.seconds))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}
