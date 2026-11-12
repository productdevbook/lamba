import AppKit

/// What Spotify or Music is playing, from the notifications both apps broadcast on every change.
/// Reading needs no permission; controls use Apple Events (macOS asks once per app).
final class NowPlayingMonitor: ObservableObject {
    struct Track: Equatable {
        let player: Player
        let title: String
        let artist: String
        var isPlaying: Bool
    }

    enum Player: String {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"

        var appName: String { self == .spotify ? "Spotify" : "Music" }
        var notification: Notification.Name {
            Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
        }
    }

    /// A paused track stays visible this long, then the capsule goes away.
    private static let pausedVisibleFor: TimeInterval = 60

    @Published private(set) var track: Track?
    private var observers: [NSObjectProtocol] = []
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let center = DistributedNotificationCenter.default()
        for player in [Player.spotify, .music] {
            observers.append(center.addObserver(forName: player.notification, object: nil, queue: .main) { [weak self] note in
                self?.update(player: player, info: note.userInfo ?? [:])
            })
        }
    }

    deinit {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
    }

    private func update(player: Player, info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? "Stopped"
        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            if track?.player == player { track = nil }
            return
        }
        // Another player pausing must not replace the one that is playing.
        if let current = track, current.player != player, current.isPlaying, state != "Playing" { return }

        track = Track(player: player, title: title, artist: info["Artist"] as? String ?? "", isPlaying: state == "Playing")
        hideWorkItem?.cancel()
        if state != "Playing" {
            let work = DispatchWorkItem { [weak self] in
                if self?.track?.isPlaying == false { self?.track = nil }
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pausedVisibleFor, execute: work)
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func openPlayer() {
        guard let player = track?.player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    var playerIcon: NSImage? {
        guard let player = track?.player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        let source = "tell application id \"\(player.rawValue)\" to \(command)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
