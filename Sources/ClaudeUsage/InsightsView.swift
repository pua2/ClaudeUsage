import SwiftUI

// MARK: - Insights View

struct InsightsView: View {
    let stats: DayStats
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topToolsSection
            divider
            cacheSection
            divider
            stopReasonsSection
            divider
            sessionAveragesSection
        }
    }

    // MARK: - Top Tools

    private var topToolsSection: some View {
        let sorted = stats.toolsByName.sorted { $0.value > $1.value }
        let top = Array(sorted.prefix(8))
        let totalTools = max(1, stats.toolCalls)

        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Top Tools")

            if top.isEmpty {
                emptyLabel
            } else {
                stackedBar(
                    items: top.map { (label: $0.key, count: $0.value) },
                    total: totalTools
                )
                .frame(height: 10)

                ForEach(top, id: \.key) { tool, count in
                    let pct = Double(count) / Double(totalTools) * 100
                    HStack(spacing: 6) {
                        Circle()
                            .fill(toolColor(tool).opacity(0.7))
                            .frame(width: 6, height: 6)
                        Text(tool)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                        Text(fmt(count))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(Int(pct.rounded()))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(toolColor(tool))
                    }
                }
            }
        }
    }

    // MARK: - Cache Efficiency

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Cache Efficiency")

            HStack {
                Text("Hit rate")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.75))
                Spacer()
                Text(String(format: "%.1f%%", stats.cacheHitRate))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(cacheColor)
            }

            cacheBar
                .frame(height: 10)

            HStack(spacing: 16) {
                cacheDetail("Read", value: fmt(stats.cacheReadTokens), color: .green)
                cacheDetail("Created", value: fmt(stats.cacheCreationTokens), color: .blue)
                cacheDetail("Uncached", value: fmt(stats.inputTokens), color: .gray)
            }
            .font(.system(size: 10))
        }
    }

    private var cacheBar: some View {
        let total = max(1, stats.cacheReadTokens + stats.cacheCreationTokens + stats.inputTokens)
        let items: [(label: String, count: Int)] = [
            ("read", stats.cacheReadTokens),
            ("created", stats.cacheCreationTokens),
            ("uncached", stats.inputTokens)
        ]
        return stackedBar(items: items, total: total)
    }

    private var cacheColor: Color {
        switch stats.cacheHitRate {
        case 80...: return .green
        case 50...: return Color(.sRGB, red: 0.9, green: 0.65, blue: 0.0)
        default: return .orange
        }
    }

    private func cacheDetail(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.7)).frame(width: 5, height: 5)
            Text("\(label): \(value)")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Stop Reasons

    private var stopReasonsSection: some View {
        let sorted = stats.stopReasons.sorted { $0.value > $1.value }
        let total = max(1, sorted.reduce(0) { $0 + $1.value })

        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Stop Reasons")

            if sorted.isEmpty {
                emptyLabel
            } else {
                stackedBar(
                    items: sorted.map { (label: $0.key, count: $0.value) },
                    total: total
                )
                .frame(height: 10)

                ForEach(sorted, id: \.key) { reason, count in
                    let pct = Double(count) / Double(total) * 100
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stopReasonColor(reason).opacity(0.7))
                            .frame(width: 6, height: 6)
                        Text(stopReasonLabel(reason))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                        Text(fmt(count))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("\(Int(pct.rounded()))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(stopReasonColor(reason))
                    }
                }
            }
        }
    }

    // MARK: - Session Averages

    private var sessionAveragesSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Session Averages")
            statRow("Avg responses/session", value: String(format: "%.1f", stats.avgResponsesPerSession), icon: "message")
            statRow("Avg tokens/response", value: fmt(stats.avgTokensPerResponse), icon: "arrow.up.circle")
            statRow("Longest session", value: "\(stats.longestSession) msgs", icon: "trophy")
            statRow("Total sessions", value: "\(stats.sessionCount)", icon: "terminal")
        }
    }

    // MARK: - Stacked Bar

    private func stackedBar(items: [(label: String, count: Int)], total: Int) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let fraction = CGFloat(item.count) / CGFloat(total)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForIndex(idx, label: item.label))
                        .frame(width: max(2, fraction * (geo.size.width - CGFloat(items.count - 1))))
                }
            }
        }
    }

    // MARK: - Colors

    private let toolColors: [Color] = [.blue, .purple, .green, .orange, .pink, .cyan, Color(.sRGB, red: 0.9, green: 0.65, blue: 0.0), .red]

    private func toolColor(_ name: String) -> Color {
        let sorted = stats.toolsByName.sorted { $0.value > $1.value }.map(\.key)
        guard let idx = sorted.firstIndex(of: name) else { return .gray }
        return toolColors[idx % toolColors.count]
    }

    private func stopReasonColor(_ reason: String) -> Color {
        switch reason {
        case "end_turn": return .green
        case "tool_use": return .blue
        case "max_tokens": return .red
        case "stop_sequence": return .orange
        default: return .gray
        }
    }

    private func stopReasonLabel(_ reason: String) -> String {
        switch reason {
        case "end_turn": return "Normal end"
        case "tool_use": return "Tool handoff"
        case "max_tokens": return "Token limit"
        case "stop_sequence": return "Stop sequence"
        default: return reason
        }
    }

    private func colorForIndex(_ idx: Int, label: String) -> Color {
        // Cache bar uses fixed colors
        switch label {
        case "read": return .green
        case "created": return .blue
        case "uncached": return .gray
        default: break
        }
        // Tool/stop reason bars use index-based colors
        return toolColors[idx % toolColors.count]
    }

    // MARK: - Helpers

    private var divider: some View { Divider().padding(.vertical, 8) }

    private var emptyLabel: some View {
        Text("No data yet")
            .font(.system(size: 11))
            .foregroundColor(.secondary.opacity(0.6))
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
