import SwiftUI
import AppKit

// MARK: - Root View

struct MenuBarView: View {
    @EnvironmentObject private var stats: StatsModel
    @State private var weeklyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let usage = stats.usage {
                divider
                usageSection(usage)
            }
            divider
            statsSection(title: "Today", s: stats.todayStats)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.title3)
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if stats.isLoading {
                ProgressView().scaleEffect(0.6)
            }
            settingsMenu
        }
    }

    private var settingsMenu: some View {
        Menu {
            Button(action: copyDebugInfo) {
                Label("Copy Debug Info", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button(action: { stats.load() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(stats.isLoading)
            Divider()
            Toggle(isOn: Binding(
                get: { stats.isAutoUpdateEnabled },
                set: { stats.isAutoUpdateEnabled = $0 }
            )) {
                Label("Auto Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            if stats.updateAvailable {
                Button(action: { stats.installUpdate() }) {
                    Label("Update Available — Install Now", systemImage: "arrow.down.circle.fill")
                }
            } else {
                Button(action: { stats.checkForUpdates(silent: false) }) {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
            }
            Divider()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
    }

    // MARK: - Usage Limits

    private func usageSection(_ u: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Plan Usage Limits")

            if u.sessionPct > 0 || u.sessionResetsAt != nil {
                limitRow(
                    label: "Current session",
                    pct: u.sessionPct,
                    color: color(for: u.sessionPct),
                    reset: u.sessionResetsAt,
                    expandable: false
                )
            }
            limitRow(
                label: "Weekly",
                pct: u.weeklyPct,
                color: color(for: u.weeklyPct),
                reset: u.weeklyResetsAt,
                expandable: true
            )
        }
    }

    private func limitRow(
        label: String,
        pct: Double,
        color: Color,
        reset: Date?,
        expandable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if expandable {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { weeklyExpanded.toggle() } }) {
                        Image(systemName: weeklyExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(pct.rounded()))% used")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }

            progressBar(pct: pct, color: color)

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

            if expandable && weeklyExpanded {
                modelBreakdown
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func progressBar(pct: Double, color: Color) -> some View {
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
    }

    // MARK: - Model Breakdown (dynamic, under Weekly)

    private var modelBreakdown: some View {
        let totalMessages = max(1, stats.weekStats.messages)
        let models = stats.weekStats.byModel.keys.sorted {
            (stats.weekStats.byModel[$0]?.messages ?? 0) > (stats.weekStats.byModel[$1]?.messages ?? 0)
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(models, id: \.self) { model in
                let ms = stats.weekStats.byModel[model] ?? ModelStats()
                let pct = Double(ms.messages) / Double(totalMessages) * 100
                modelRow(
                    name: model,
                    messages: ms.messages,
                    tokens: ms.outputTokens,
                    pct: pct,
                    color: modelColor(model)
                )
            }
        }
        .padding(.leading, 12)
    }

    private func modelColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "sonnet": return .blue
        case "opus":   return .purple
        case "haiku":  return .green
        default:       return .orange
        }
    }

    private func modelRow(name: String, messages: Int, tokens: Int, pct: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                Text("\(fmt(messages)) msgs")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            progressBar(pct: pct, color: color)
        }
    }

    // MARK: - Stats Sections

    private func statsSection(title: String, s: DayStats) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel(title)
            statRow("Responses", value: fmt(s.messages), icon: "message")
            statRow("Tool calls", value: fmt(s.toolCalls), icon: "wrench.and.screwdriver")
            statRow("Sessions", value: "\(s.sessionCount)", icon: "terminal")
            statRow("Output tokens", value: fmt(s.outputTokens), icon: "arrow.up.circle")
            statRow("Input tokens", value: fmt(s.totalInputTokens), icon: "arrow.down.circle")
            statRow("Cache read", value: fmt(s.cacheReadTokens), icon: "arrow.triangle.2.circlepath")
            statRow("Cache created", value: fmt(s.cacheCreationTokens), icon: "plus.circle")
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Responses / Day")
            ActivityBarChart(days: stats.last7Days)
                .frame(height: 72)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Group {
            if let t = stats.lastRefreshed {
                Text("Updated \(refreshedLabel(t))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions

    private func copyDebugInfo() {
        let info = stats.debugInfo
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }

    // MARK: - Helpers

    private var divider: some View { Divider().padding(.vertical, 8) }

    private func color(for pct: Double) -> Color {
        switch pct {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
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

    private func refreshedLabel(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Bar Chart

struct ActivityBarChart: View {
    let days: [(date: String, stats: DayStats)]

    private var maxCount: Int { max(1, days.map(\.stats.messages).max() ?? 1) }

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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return s == f.string(from: Date())
    }
}

struct BarColumn: View {
    let date: String
    let count: Int
    let maxCount: Int
    let isToday: Bool

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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return "" }
        f.dateFormat = "E"
        return String(f.string(from: d).prefix(1))
    }
}
