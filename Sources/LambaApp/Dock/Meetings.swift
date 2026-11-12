import AppKit
import EventKit

/// The next calendar event that starts within a few minutes (or has just started),
/// with its video-call link when one is found.
final class MeetingMonitor: ObservableObject {
    struct Meeting: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let color: NSColor
        let link: URL?
    }

    static let showBefore: TimeInterval = 10 * 60
    static let showAfterStart: TimeInterval = 10 * 60

    @Published private(set) var meeting: Meeting?
    /// Called once per meeting, about a minute before it starts.
    var onStartingSoon: (() -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var announced: Set<String> = []
    private var observer: NSObjectProtocol?

    func start() {
        guard timer == nil else { return }
        requestAccess { [weak self] granted in
            guard granted, let self else { return }
            self.refresh()
            let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            self.observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: self.store, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        meeting = nil
    }

    func join() {
        if let link = meeting?.link {
            NSWorkspace.shared.open(link)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
    }

    private func requestAccess(_ completion: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { granted, _ in DispatchQueue.main.async { completion(granted) } }
        if #available(macOS 14.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: completion(true)
            case .notDetermined: store.requestFullAccessToEvents(completion: finish)
            default: completion(false)
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized: completion(true)
            case .notDetermined: store.requestAccess(to: .event, completion: finish)
            default: completion(false)
            }
        }
    }

    private func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-Self.showAfterStart), end: now.addingTimeInterval(Self.showBefore), calendars: nil)
        let next = store.events(matching: predicate)
            .filter { event in
                !event.isAllDay
                    && event.endDate > now
                    && now.timeIntervalSince(event.startDate) < Self.showAfterStart
                    && event.startDate.timeIntervalSince(now) < Self.showBefore
                    && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .min { $0.startDate < $1.startDate }

        let new = next.map {
            Meeting(
                id: $0.eventIdentifier ?? $0.title,
                title: $0.title ?? "",
                start: $0.startDate,
                end: $0.endDate,
                color: $0.calendar.color,
                link: Self.callLink(in: $0)
            )
        }
        if new != meeting { meeting = new }

        if let new, new.start.timeIntervalSince(now) < 75, !announced.contains(new.id) {
            announced.insert(new.id)
            onStartingSoon?()
        }
    }

    private static let callHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com", "whereby.com"]

    /// First Zoom/Meet/Teams/… link in the event's URL, location or notes.
    static func callLink(in event: EKEvent) -> URL? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let url = matches.compactMap(\.url).first(where: { url in
                callHosts.contains { url.host?.hasSuffix($0) == true }
            }) {
                return url
            }
        }
        return nil
    }
}
