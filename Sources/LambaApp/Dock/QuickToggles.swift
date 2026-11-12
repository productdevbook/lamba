import AppKit
import SwiftUI

extension L10n {
    static let togglesButton = tr("toggles.button")
    static let togglesDND = tr("toggles.dnd")
    static let togglesDNDNoShortcut = tr("toggles.dnd.noShortcut")
    static let togglesKeepAwake = tr("toggles.keepAwake")
    static let togglesDarkMode = tr("toggles.darkMode")
    static let togglesMic = tr("toggles.mic")
    static let togglesOn = tr("toggles.on")
    static let togglesOff = tr("toggles.off")
    static let togglesMuted = tr("toggles.muted")
    static let togglesNoSleep = tr("toggles.noSleep")
    static let togglesNoSleepOn = tr("toggles.noSleep.on")
}

/// Keep awake, never sleep, dark mode, microphone.
final class QuickToggles: ObservableObject {
    @Published var keepAwake = false
    @Published var sleepDisabled = false
    @Published var darkMode = false
    @Published var micMuted = false

    init() {
        refresh()
    }

    func refresh() {
        darkMode = SystemAppearance.isDark
        micMuted = Microphone.isMuted
        keepAwake = KeepAwake.isOn
        objectWillChange.send()
        SystemSleep.read { [weak self] in self?.sleepDisabled = $0 }
    }

    /// `pmset disablesleep` through the root helper; the real state is read back afterwards.
    func toggleSleepDisabled() {
        sleepDisabled.toggle()
        try? SystemSleep.set(disabled: sleepDisabled)
        SystemSleep.read { [weak self] in self?.sleepDisabled = $0 }
    }


    func toggleKeepAwake() {
        keepAwake.toggle()
        KeepAwake.set(keepAwake)
    }

    func toggleDarkMode() {
        darkMode.toggle()
        SystemAppearance.setDark(darkMode)
    }

    func toggleMic() {
        micMuted.toggle()
        Microphone.setMuted(micMuted)
    }
}

/// The toggles button in the right island (sliders icon, 40×40); opens a 2×2 toggle grid popover.
struct QuickTogglesButton: View {
    @ObservedObject var toggles: QuickToggles
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            toggles.refresh()
            DockPopover.shared.toggle(id: "toggles", anchor: frame) { TogglesPopover(toggles: toggles) }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.togglesButton)
        .frame(maxHeight: .infinity)
        .modifier(AnchorReader(frame: $frame))
    }
}

private struct TogglesPopover: View {
    @ObservedObject var toggles: QuickToggles

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(104), spacing: 8), count: 2)
        LazyVGrid(columns: columns, spacing: 8) {
            tile("cup.and.saucer.fill", L10n.togglesKeepAwake, toggles.keepAwake ? L10n.togglesOn : L10n.togglesOff,
                 on: toggles.keepAwake, tint: Theme.orange, action: toggles.toggleKeepAwake)
            tile("moon.zzz.fill", L10n.togglesNoSleep, toggles.sleepDisabled ? L10n.togglesNoSleepOn : L10n.togglesOff,
                 on: toggles.sleepDisabled, tint: .blue, action: toggles.toggleSleepDisabled)
            tile("circle.lefthalf.filled", L10n.togglesDarkMode, toggles.darkMode ? L10n.togglesOn : L10n.togglesOff,
                 on: toggles.darkMode, tint: .purple, action: toggles.toggleDarkMode)
            tile(toggles.micMuted ? "mic.slash.fill" : "mic.fill", L10n.togglesMic, toggles.micMuted ? L10n.togglesMuted : L10n.togglesOn,
                 on: toggles.micMuted, tint: .red, action: toggles.toggleMic)
        }
        .padding(10)
    }

    private func tile(_ symbol: String, _ title: String, _ state: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? tint : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(state).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? tint.opacity(0.22) : Color.white.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(state)")
    }
}
