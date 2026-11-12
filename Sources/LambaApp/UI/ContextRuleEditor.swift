import AppKit
import LambaCore
import SwiftUI

/// "Switch automatically": the rules that make this context active.
struct ContextRuleEditor: View {
    @Binding var context: DockContext
    let currentSSID: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if context.rules.isEmpty {
                    Text(L10n.ctxRulesEmpty).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach($context.rules) { $rule in
                    RuleRow(rule: $rule, currentSSID: currentSSID) {
                        let id = rule.id
                        context.rules.removeAll { $0.id == id }
                    }
                    if rule.id != context.rules.last?.id { Divider() }
                }
                Menu {
                    Button(L10n.ctxRuleTime) {
                        add(.schedule(weekdays: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 18 * 60))
                    }
                    Button(L10n.ctxRuleDisplay) { add(.display(name: NSScreen.screens.last?.localizedName ?? "")) }
                    Button(L10n.ctxRuleWifi) { add(.wifi(ssid: currentSSID ?? "")) }
                    Button(L10n.ctxRuleApp) {
                        if let url = AppPicker.pick(multiple: false).first, let id = AppPicker.bundleID(of: url) {
                            add(.frontApp(bundleID: id))
                        }
                    }
                    Button(L10n.ctxRuleMirroring) { add(.mirroring) }
                } label: {
                    Label(L10n.ctxAddRule, systemImage: "plus")
                }
                .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text(L10n.ctxRules).font(.system(size: 12, weight: .semibold))
        }
    }

    private func add(_ trigger: ContextRule.Trigger) {
        context.rules.append(ContextRule(trigger: trigger))
    }
}

private struct RuleRow: View {
    @Binding var rule: ContextRule
    let currentSSID: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium))
                editor
            }
            Spacer(minLength: 8)
            Toggle(L10n.ctxRuleEnabled, isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.ctxDeleteRule)
                .help(L10n.ctxDeleteRule)
        }
        .opacity(rule.isEnabled ? 1 : 0.6)
    }

    private var title: String {
        switch rule.trigger {
        case .schedule: return L10n.ctxRuleTime
        case .display: return L10n.ctxRuleDisplay
        case .wifi: return L10n.ctxRuleWifi
        case .frontApp: return L10n.ctxRuleApp
        case .mirroring: return L10n.ctxRuleMirroring
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch rule.trigger {
        case let .schedule(weekdays, start, end):
            ScheduleEditor(weekdays: weekdays, start: start, end: end) {
                rule.trigger = .schedule(weekdays: $0, startMinute: $1, endMinute: $2)
            }
        case let .display(name):
            DisplayEditor(name: name) { rule.trigger = .display(name: $0) }
        case let .wifi(ssid):
            HStack {
                TextField(L10n.ctxSsid, text: Binding(get: { ssid }, set: { rule.trigger = .wifi(ssid: $0) }))
                    .textFieldStyle(.roundedBorder)
                if let currentSSID, currentSSID != ssid {
                    Button(L10n.ctxSsidCurrent(currentSSID)) { rule.trigger = .wifi(ssid: currentSSID) }
                        .controlSize(.small)
                }
            }
        case let .frontApp(bundleID):
            HStack {
                Text(Self.appName(bundleID) ?? bundleID).foregroundStyle(.secondary).lineLimit(1)
                Button(L10n.ctxChooseApp) {
                    if let url = AppPicker.pick(multiple: false).first, let id = AppPicker.bundleID(of: url) {
                        rule.trigger = .frontApp(bundleID: id)
                    }
                }
                .controlSize(.small)
            }
        case .mirroring:
            Text(L10n.ctxMirroringHint).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    static func appName(_ bundleID: String) -> String? {
        guard !bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return AppPicker.name(of: url.path)
    }
}

private struct ScheduleEditor: View {
    let weekdays: Set<Int>
    let start: Int
    let end: Int
    let commit: (Set<Int>, Int, Int) -> Void

    private var calendar: Calendar { .current }

    /// Weekday numbers (1 = Sunday) starting at the locale's first weekday.
    private var order: [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(order, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button {
                        var next = weekdays
                        if on { next.remove(day) } else { next.insert(day) }
                        commit(next, start, end)
                    } label: {
                        Text(calendar.veryShortStandaloneWeekdaySymbols[day - 1])
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 24, height: 22)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(calendar.standaloneWeekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack {
                DatePicker(L10n.ctxFrom, selection: time(start) { commit(weekdays, $0, end) }, displayedComponents: .hourAndMinute)
                DatePicker(L10n.ctxTo, selection: time(end) { commit(weekdays, start, $0) }, displayedComponents: .hourAndMinute)
            }
            .fixedSize()
        }
    }

    private func time(_ minute: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: { calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() },
            set: {
                let parts = calendar.dateComponents([.hour, .minute], from: $0)
                set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }
}

private struct DisplayEditor: View {
    let name: String
    let commit: (String) -> Void

    private var names: [String] { NSScreen.screens.map(\.localizedName) }

    var body: some View {
        HStack {
            TextField(L10n.ctxDisplayName, text: Binding(get: { name }, set: commit))
                .textFieldStyle(.roundedBorder)
            Menu(L10n.ctxDisplayPick) {
                ForEach(names, id: \.self) { screen in
                    Button(screen) { commit(screen) }
                }
            }
            .fixedSize()
        }
    }
}
