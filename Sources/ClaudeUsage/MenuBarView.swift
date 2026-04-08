import SwiftUI

// MARK: - Root View

struct MenuBarView: View {
    @EnvironmentObject private var stats: StatsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let usage = stats.usage {
                divider
                usageSection(usage)
            }
            divider
            statsSection(title: "Today",       s: stats.todayStats)
            divider
            statsSection(title: "Last 7 Days", s: stats.weekStats)
            if stats.last7Days.contains(where: { $0.stats.messages > 0 }) {
                divider
                chartSection
            }
            divider
            footer
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { stats.load() }
    }

    // MARK: - Usage Limits

    private func usageSection(_ u: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Plan Usage Limits")

            if u.sessionPct > 0 || u.sessionResetsAt != nil {
                limitRow(
                    label: "Current session",
                    pct:   u.sessionPct,
                    color: color(for: u.sessionPct),
                    reset: u.sessionResetsAt
                )
            }
            limitRow(
                label: "Weekly",
                pct:   u.weeklyPct,
                color: color(for: u.weeklyPct),
                reset: u.weeklyResetsAt
            )
        }
    }

    private func limitRow(label: String, pct: Double, color: Color, reset: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(pct.rounded()))% used")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(pct / 100)), height: 6)
                }
            }
            .frame(height: 6)

            if let reset {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Resets \(resetDateLabel(reset))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(resetCountdown(reset))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
    }

    private func color(for pct: Double) -> Color {
        switch pct {
        case ..<50:  return .green
        case ..<75:  return .yellow
        case ..<90:  return .orange
        default:     return .red
        }
    }

    private func resetDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d 'at' h:mm a"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func resetCountdown(_ date: Date) -> String {
        let diff = Int(date.timeIntervalSinceNow)
        if diff <= 0 { return "any moment now" }
        let d = diff / 86400
        let h = (diff % 86400) / 3600
        let m = (diff % 3600) / 60
        if d > 0 { return "in \(d)d \(h)h \(m)m" }
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.title3)
            Text("Claude Code")
                .font(.headline)
            Spacer()
            if stats.isLoading {
                ProgressView().scaleEffect(0.6)
            }
        }
    }

    private func statsSection(title: String, s: DayStats) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel(title)
            statRow("Responses",     value: fmt(s.messages),     icon: "message")
            statRow("Tool calls",    value: fmt(s.toolCalls),    icon: "wrench.and.screwdriver")
            statRow("Sessions",      value: "\(s.sessionCount)", icon: "terminal")
            statRow("Output tokens", value: fmt(s.outputTokens), icon: "arrow.up.circle")
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Responses / Day")
            ActivityBarChart(days: stats.last7Days)
                .frame(height: 72)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Refresh") { stats.load() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                    .disabled(stats.isLoading)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
            }
            if let t = stats.lastRefreshed {
                Text("Updated \(refreshedLabel(t))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func refreshedLabel(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60  { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    // MARK: - Helpers

    private var divider: some View { Divider().padding(.vertical, 8) }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func statRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.75))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func fmt(_ n: Int) -> String {
        NumberFormatter().also { $0.numberStyle = .decimal }
            .string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private extension NumberFormatter {
    func also(_ configure: (NumberFormatter) -> Void) -> NumberFormatter {
        configure(self); return self
    }
}

// MARK: - Bar Chart

struct ActivityBarChart: View {
    let days: [(date: String, stats: DayStats)]
    private var maxCount: Int { max(1, days.map { $0.stats.messages }.max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(days, id: \.date) { entry in
                BarColumn(
                    date: entry.date,
                    count: entry.stats.messages,
                    maxCount: maxCount,
                    isToday: isToday(entry.date)
                )
            }
        }
    }

    private func isToday(_ s: String) -> Bool {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return s == f.string(from: Date())
    }
}

struct BarColumn: View {
    let date: String; let count: Int; let maxCount: Int; let isToday: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                Spacer(minLength: 0)
                Text(count > 0 ? "\(count)" : "")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(isToday ? .primary : .secondary)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 2)
                    .fill(isToday ? Color.purple : Color.purple.opacity(0.4))
                    .frame(height: max(2, CGFloat(count) / CGFloat(maxCount) * (geo.size.height - 28)))
                Text(dayLabel)
                    .font(.system(size: 8))
                    .foregroundColor(isToday ? .primary : .secondary)
                    .frame(height: 12)
            }
        }
    }

    private var dayLabel: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return "" }
        f.dateFormat = "E"
        return String(f.string(from: d).prefix(1))
    }
}
