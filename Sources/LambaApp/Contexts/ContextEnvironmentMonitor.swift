import AppKit
import CoreLocation
import CoreWLAN
import LambaCore

/// Reads the facts rules are checked against (displays, mirroring, Wi-Fi, front app) and calls
/// `onChange` when something that can matter changes. Location authorization, which macOS 14+
/// requires to read the Wi-Fi name, is only requested once a Wi-Fi rule exists.
final class ContextEnvironmentMonitor: NSObject, CLLocationManagerDelegate {
    var onChange: () -> Void = {}

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var locationManager: CLLocationManager?
    private var lastFrontBundleID: String?

    func start() {
        stop()
        lastFrontBundleID = Self.externalFrontBundleID()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.onChange() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange()
        })
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
    }

    /// Asks for Location (when-in-use) the first time a Wi-Fi rule is enabled.
    func setWiFiNeeded(_ needed: Bool) {
        guard needed, locationManager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange()
    }

    var ssid: String? { CWWiFiClient.shared().interface()?.ssid() }

    func environment() -> ContextEnvironment {
        if let front = Self.externalFrontBundleID() { lastFrontBundleID = front }
        return ContextEnvironment(
            displayNames: NSScreen.screens.map(\.localizedName),
            wifiSSID: ssid,
            frontBundleID: lastFrontBundleID,
            isMirroring: Self.isMirroring())
    }

    /// Lamba's own windows (settings, Dock) don't count as "the front app".
    private static func externalFrontBundleID() -> String? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    private static func isMirroring() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }
}
