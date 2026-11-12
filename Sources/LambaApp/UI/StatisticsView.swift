import Charts
import LambaCore
import SwiftUI

/// Statistics tab: range filter, KPI tiles, daily focus chart, light and charger usage.
struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @State private var dayCount = 7
    @State private var report: ActivityReport?

    private static let ranges = [7, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                toolbar
                if let report {
                    KPIRow(report: report)
                    FocusChartCard(report: report, dayCount: dayCount)
                    HStack(alignment: .top, spacing: 12) {
                        UsageCard(title: L10n.lightUsage, shares: report.light, name: L10n.lightName, swatch: { LightSwatch(name: $0) })
                        UsageCard(title: L10n.chargerUsage, shares: report.charge, name: L10n.chargeName, swatch: { ChargeSwatch(name: $0) })
                    }
                }
                footer
            }
            .padding(20)
        }
        .onAppear(perform: reload)
        .onChange(of: dayCount) { _ in reload() }
        .onChange(of: model.activityRevision) { _ in reload() }
    }

    private func reload() {
        report = model.report(days: dayCount)
    }

    /// Filters sit in one row above everything they scope.
    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(Self.ranges, id: \.self) { days in
                RangeChip(title: L10n.days(days), isSelected: dayCount == days) { dayCount = days }
            }
            Spacer()
            Menu {
                Button(L10n.exportCSV) { report.map(model.exportCSV) }
                Button(L10n.exportCopy) { report.map(model.copySummary) }
            } label: {
                Label(L10n.export, systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var footer: some View {
        HStack {
            Label(L10n.statsPrivacy, systemImage: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(L10n.statsClear, action: model.clearHistory)
                .controlSize(.small)
        }
    }
}

// MARK: - KPI tiles

private struct KPIRow: View {
    let report: ActivityReport

    var body: some View {
        HStack(spacing: 10) {
            StatTile(label: L10n.kpiFocus, value: L10n.duration(report.focusSeconds), delta: focusDelta)
            StatTile(label: L10n.kpiSessions, value: "\(report.completedSessions)")
            StatTile(label: L10n.kpiStreak, value: L10n.streakDays(report.streakDays))
            StatTile(label: L10n.kpiFlashes, value: "\(report.flashes)")
        }
    }

    /// Change vs the previous period of the same length; hidden when there is nothing to compare.
    private var focusDelta: StatTile.Delta? {
        guard report.previousFocusSeconds > 0 else { return nil }
        let change = (report.focusSeconds - report.previousFocusSeconds) / report.previousFocusSeconds
        let percent = change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(L10n.locale))
        return StatTile.Delta(text: percent, help: L10n.vsPrevious(percent), isUp: change >= 0)
    }
}

private struct StatTile: View {
    struct Delta {
        let text: String
        let help: String
        let isUp: Bool
    }

    let label: String
    let value: String
    var delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let delta {
                // Direction is carried by the arrow icon and its color; the text stays in text ink.
                HStack(spacing: 3) {
                    Image(systemName: delta.isUp ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(delta.isUp ? ChartPalette.good : ChartPalette.bad)
                    Text(delta.text).foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .help(delta.help)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .padding(10)
        .background(Card())
    }
}

// MARK: - Daily focus chart

private struct FocusChartCard: View {
    let report: ActivityReport
    let dayCount: Int
    @State private var hovered: ActivityReport.Day?

    private var hasData: Bool { report.focusSeconds > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.dailyFocus).font(.system(size: 13, weight: .semibold))
                Spacer()
                if hasData {
                    Text(L10n.average(L10n.duration(report.averageFocusPerDay)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if hasData {
                chart.frame(height: 170)
            } else {
                Text(L10n.statsEmpty)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .background(Card())
    }

    private var chart: some View {
        Chart(report.days) { day in
            // Crosshair first, so the bar draws on top of it.
            if let hovered, hovered.date == day.date {
                RuleMark(x: .value(L10n.dailyFocus, day.date, unit: .day))
                    .foregroundStyle(Color.primary.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 4) {
                        Tooltip(day: day)
                    }
            }

            BarMark(
                x: .value(L10n.dailyFocus, day.date, unit: .day),
                y: .value(L10n.chartMinutes, day.focusSeconds / 60),
                width: .fixed(dayCount <= 7 ? 24 : 8) // capped thickness; the rest of the band is air
            )
            .foregroundStyle(ChartPalette.focus)
            .cornerRadius(dayCount <= 7 ? 4 : 2)
            .opacity(hovered == nil || hovered?.date == day.date ? 1 : 0.45)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Color.secondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: dayCount <= 7 ? 1 : 7)) { _ in
                AxisValueLabel(format: dayCount <= 7
                    ? .dateTime.weekday(.abbreviated).locale(L10n.locale)
                    : .dateTime.day().month(.abbreviated).locale(L10n.locale))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .environment(\.locale, L10n.locale)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            hovered = day(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
    }

    /// The crosshair snaps to the nearest day, so the whole column band is the hit target.
    private func day(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> ActivityReport.Day? {
        let x = location.x - geometry[proxy.plotAreaFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return report.days.min { abs($0.date.addingTimeInterval(43_200).timeIntervalSince(date)) < abs($1.date.addingTimeInterval(43_200).timeIntervalSince(date)) }
    }
}

/// Value leads, label follows.
private struct Tooltip: View {
    let day: ActivityReport.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.duration(day.focusSeconds)).font(.system(size: 12, weight: .semibold))
            Text("\(day.date.formatted(.dateTime.weekday(.wide).day().month().locale(L10n.locale))) · \(day.completedSessions) \(L10n.kpiSessions.lowercased(with: L10n.locale))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        )
        .fixedSize()
    }
}

// MARK: - Usage lists

/// Meter list: name, bar and figure per row, largest first, bars in one neutral hue.
/// Identity comes from the swatch beside the name, never from the bar or text color.
private struct UsageCard<Swatch: View>: View {
    let title: String
    let shares: [ActivityReport.Share]
    let name: (String) -> String
    @ViewBuilder let swatch: (String) -> Swatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if shares.isEmpty {
                Text("—").foregroundStyle(.secondary)
            }
            let largest = shares.first?.seconds ?? 1
            ForEach(shares.prefix(5)) { share in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        swatch(share.name)
                        Text(name(share.name)).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(L10n.duration(share.seconds))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(ChartPalette.neutral)
                                .frame(width: max(4, geometry.size.width * share.seconds / largest))
                        }
                    }
                    .frame(height: 6)
                }
                .help("\(name(share.name)): \(L10n.duration(share.seconds))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Card())
    }
}

private struct LightSwatch: View {
    let name: String

    var body: some View {
        let mode: LightMode = name == LightPattern.alternate.name
            ? .pattern(.alternate)
            : .solid(LightState(rawValue: name) ?? .system)
        LEDView(appearance: LightAppearance(mode: mode), size: 8)
    }
}

private struct ChargeSwatch: View {
    let name: String

    var body: some View {
        let symbol: String
        switch name {
        case ChargeState.charging.name: symbol = "bolt.fill"
        case ChargeState.notCharging.name: symbol = "powerplug.fill"
        default: symbol = "battery.75"
        }
        return Image(systemName: symbol)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(width: 10)
    }
}

// MARK: - Shared

private struct RangeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.07)))
    }
}

/// Chart colors, validated with the dataviz palette checker against light and dark surfaces.
enum ChartPalette {
    /// Focus bars: one hue (orange #d97706 passes lightness band and 3:1 contrast in both modes).
    static let focus = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x06 / 255)
    /// Ranked usage bars: neutral, so the LED swatch carries identity.
    static let neutral = Color.primary.opacity(0.35)
    static let good = Color(red: 0.16, green: 0.62, blue: 0.33)
    static let bad = Color(red: 0.82, green: 0.26, blue: 0.22)
}
