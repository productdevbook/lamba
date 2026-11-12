import AppKit
import LambaCore
import SwiftUI

/// Capsules that appear in the strip only while something is happening:
/// a coding agent's status, an upcoming meeting, and the song that is playing.
struct LiveCapsules: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meetings: MeetingMonitor
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        if model.permission == nil, model.agent != nil || !model.agentSessions.isEmpty || !model.remoteMachines.isEmpty {
            AgentIcon(model: model).transition(Self.transition)
        }
        LiveItems(model: model, meetings: meetings, nowPlaying: nowPlaying)
    }

    static let transition = AnyTransition.scale(scale: 0.6).combined(with: .opacity)
}

/// The capsules without the agent icon: a permission prompt, the next meeting, the playing song.
/// The strip puts them after the agent icon; the islands Dock gives the icon its own island and
/// shows these in a "live" island only while there is something to show.
struct LiveItems: View {
    @ObservedObject var model: AppModel
    @ObservedObject var meetings: MeetingMonitor
    @ObservedObject var nowPlaying: NowPlayingMonitor

    /// Whether any capsule would be shown, so a host can drop its container when empty.
    static func hasContent(model: AppModel, meetings: MeetingMonitor, nowPlaying: NowPlayingMonitor) -> Bool {
        model.permission != nil || meetings.meeting != nil || nowPlaying.track != nil
    }

    var body: some View {
        if let prompt = model.permission {
            PermissionCapsule(prompt: prompt, answer: model.answerPermission, show: { model.showAgent() }).transition(LiveCapsules.transition)
        }
        if let meeting = meetings.meeting {
            MeetingCapsule(meeting: meeting, join: meetings.join).transition(LiveCapsules.transition)
        }
        if let track = nowPlaying.track {
            MusicCapsule(track: track, monitor: nowPlaying).transition(LiveCapsules.transition)
        }
    }
}

/// Shared look: a soft capsule that fills the strip's height.
private struct CapsuleBackground: ViewModifier {
    var tint: Color = .primary
    var opacity: Double = 0.07

    func body(content: Content) -> some View {
        content
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(Capsule(style: .continuous).fill(tint.opacity(opacity)))
            .contentShape(Capsule())
    }
}

private struct TwoLines: View {
    let title: String
    let subtitle: String
    var maxWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Agent

/// Claude, as a single icon: its look tells the state (spinning = working, pulsing hand = needs
/// you, check = just finished, dim = idle). Click for machines and sessions, finished and running.
struct AgentIcon: View {
    @ObservedObject var model: AppModel
    @State private var frame: CGRect = .zero

    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        symbol
            .frame(width: 40, height: 40)
            .background(Circle().fill(tint.opacity(model.agent == nil ? 0.07 : 0.16)))
            .frame(maxHeight: .infinity)
            .contentShape(Circle())
            .modifier(AnchorReader(frame: $frame))
            .onTapGesture {
                DockPopover.shared.toggle(id: "agents", anchor: frame) {
                    AgentOverview(model: model) { session in
                        DockPopover.shared.close()
                        model.showAgent(session)
                    }
                }
            }
    }

    private var tint: Color {
        switch model.agent {
        case .working?: return Self.claude
        case .waiting?: return Theme.orange
        case .done?: return Theme.green
        case nil: return .white
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch model.agent {
        case .working?:
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Self.claude)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 90))
            }
        case .waiting?:
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .opacity(0.55 + 0.45 * abs(sin(context.date.timeIntervalSinceReferenceDate * 3)))
            }
        case .done?:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.green)
        case nil:
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Self.claude.opacity(0.75))
        }
    }
}

/// Machines (this Mac and SSH hosts, with connection state), each with its sessions:
/// running ones first, then finished ones. Click a session to open its terminal.
private struct AgentOverview: View {
    @ObservedObject var model: AppModel
    let open: (AgentSessionInfo) -> Void

    private struct Machine: Identifiable {
        let id: String
        let title: String
        let isConnected: Bool?
        let sessions: [AgentSessionInfo]
    }

    private var machines: [Machine] {
        let grouped = Dictionary(grouping: model.agentSessions) { $0.host?.machine ?? "" }
        func ordered(_ sessions: [AgentSessionInfo]) -> [AgentSessionInfo] {
            sessions.filter { $0.state.event != .done } + sessions.filter { $0.state.event == .done }
        }
        var result = [Machine(id: "", title: L10n.agentThisMac, isConnected: nil, sessions: ordered(grouped[""] ?? []))]
        let remote = model.remoteMachines
        for machine in remote {
            result.append(Machine(id: machine.name, title: machine.name, isConnected: machine.isConnected, sessions: ordered(grouped[machine.name] ?? [])))
        }
        // Sessions from hosts that aren't registered here (reached some other way).
        for (name, sessions) in grouped where !name.isEmpty && !remote.contains(where: { $0.name == name }) {
            result.append(Machine(id: name, title: name, isConnected: nil, sessions: ordered(sessions)))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(machines) { machine in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: machine.isConnected == nil ? "laptopcomputer" : "server.rack")
                            .font(.system(size: 10, weight: .semibold))
                        Text(machine.title).font(.system(size: 11, weight: .semibold))
                        if let connected = machine.isConnected {
                            Circle().fill(connected ? Theme.green : Color.secondary).frame(width: 6, height: 6)
                            Text(connected ? L10n.agentConnected : L10n.agentOffline)
                                .font(.system(size: 10.5))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                    if machine.sessions.isEmpty {
                        Text(L10n.agentNoSessions)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    ForEach(machine.sessions) { session in
                        AgentSessionRow(session: session).onTapGesture { open(session) }
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 330)
    }
}

struct AgentSessionRow: View {
    let session: AgentSessionInfo
    @State private var isHovered = false

    private var isDone: Bool { session.state.event == .done }

    var body: some View {
        HStack(spacing: 10) {
            StateMark(event: session.state.event)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name ?? session.host?.folder ?? L10n.agentSession)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .opacity(isDone ? 0.6 : 1)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(time(at: context.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        [session.name != nil ? session.host?.folder : nil, session.activityLine].compactMap { $0 }.joined(separator: " · ")
    }

    /// Running: how long the session has been going. Finished: how long ago.
    private func time(at now: Date) -> String {
        let since = isDone ? session.state.updated : session.state.started
        let text = Duration.seconds(max(60, now.timeIntervalSince(since)))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(L10n.locale))
        return isDone ? L10n.agentAgo(text) : text
    }
}

struct StateMark: View {
    let event: AgentEvent

    var body: some View {
        Group {
            switch event {
            case .working:
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    Image(systemName: "sparkle")
                        .foregroundStyle(AgentIcon.claude)
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 90))
                }
            case .waiting:
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            }
        }
        .font(.system(size: 12, weight: .bold))
        .frame(width: 16)
    }
}

extension AgentSessionInfo {
    /// "Editing · Dock.swift"
    var activityLine: String {
        let activity: String
        switch state.event {
        case .working: activity = state.detail.map { L10n.agentActivity($0.tool) } ?? L10n.agentWorking
        case .waiting: activity = L10n.agentWaiting
        case .done: activity = L10n.agentDone
        }
        return [activity, state.event == .working ? state.detail?.target : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct PermissionCapsule: View {
    let prompt: PermissionPrompt
    let answer: (PermissionDecision) -> Void
    let show: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .opacity(0.55 + 0.45 * abs(sin(context.date.timeIntervalSinceReferenceDate * 3)))
            }
            TwoLines(
                title: L10n.permissionTitle(L10n.agentActivity(prompt.detail.tool)),
                subtitle: prompt.detail.target ?? "",
                maxWidth: 120
            )
            .help([prompt.detail.tool, prompt.detail.target].compactMap { $0 }.joined(separator: " · "))
            RoundButton(symbol: "xmark", fill: Color.primary.opacity(0.16), foreground: .primary, help: L10n.permissionDeny) { answer(.deny) }
            RoundButton(symbol: "checkmark", fill: Theme.green, help: L10n.permissionAllow) { answer(.allow) }
        }
        .modifier(CapsuleBackground(tint: Theme.orange, opacity: 0.2))
        .padding(.trailing, -6)
        .contextMenu {
            Button(L10n.permissionAllow) { answer(.allow) }
            Button(L10n.permissionDeny) { answer(.deny) }
            Divider()
            Button(L10n.permissionAsk) {
                answer(.ask)
                show()
            }
        }
    }
}

private struct RoundButton: View {
    let symbol: String
    let fill: Color
    var foreground: Color = .white
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(foreground)
            .frame(width: 28, height: 28)
            .background(Circle().fill(fill))
            .brightness(isHovered ? 0.12 : 0)
            .scaleEffect(isHovered ? 1.06 : 1)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .help(help)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Meeting

struct MeetingCapsule: View {
    let meeting: MeetingMonitor.Meeting
    let join: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            HStack(spacing: 9) {
                Circle().fill(Color(nsColor: meeting.color)).frame(width: 8, height: 8)
                TwoLines(title: meeting.title, subtitle: when(at: context.date), maxWidth: 130)
                if meeting.link != nil {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.green))
                }
            }
        }
        .modifier(CapsuleBackground(tint: Color(nsColor: meeting.color), opacity: 0.14))
        .padding(.trailing, meeting.link != nil ? -6 : 0)
        .onTapGesture(perform: join)
        .contextMenu {
            if meeting.link != nil { Button(L10n.meetingJoin, action: join) }
            Button(L10n.meetingOpenCalendar) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            }
        }
    }

    private func when(at date: Date) -> String {
        let minutes = Int(ceil(meeting.start.timeIntervalSince(date) / 60))
        return minutes <= 0 ? L10n.meetingNow : L10n.meetingIn(minutes)
    }
}

// MARK: - Music

struct MusicCapsule: View {
    let track: NowPlayingMonitor.Track
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 9) {
            if let icon = monitor.playerIcon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            }
            TwoLines(title: track.title, subtitle: track.artist, maxWidth: 140)
                .opacity(track.isPlaying ? 1 : 0.6)
            Equalizer(isPlaying: track.isPlaying)
        }
        .modifier(CapsuleBackground())
        .padding(.leading, -4)
        .onTapGesture(perform: monitor.playPause)
        .contextMenu {
            Button(track.isPlaying ? L10n.pomodoroPause : L10n.pomodoroResume, action: monitor.playPause)
            Button(L10n.musicNext, action: monitor.next)
            Button(L10n.musicPrevious, action: monitor.previous)
            Divider()
            Button(L10n.musicOpen(track.player.appName), action: monitor.openPlayer)
        }
    }
}

/// Three bars that dance while music plays and rest when paused.
private struct Equalizer: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: 3, height: isPlaying ? 4 + 10 * abs(sin(t * (2.6 + Double(index) * 0.9) + Double(index))) : 3)
                }
            }
            .frame(height: 14, alignment: .bottom)
            .animation(.linear(duration: 1 / 12), value: t)
        }
    }
}
