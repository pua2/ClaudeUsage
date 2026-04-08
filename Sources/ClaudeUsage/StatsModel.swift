import Foundation

// MARK: - Data Models

struct ModelStats {
    var messages: Int = 0
    var outputTokens: Int = 0
}

struct DayStats {
    var messages: Int = 0
    var toolCalls: Int = 0
    var outputTokens: Int = 0
    var inputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var sessions: Set<String> = []
    var byModel: [String: ModelStats] = [:]

    var sessionCount: Int { sessions.count }
}

// MARK: - StatsModel

final class StatsModel: ObservableObject {
    @Published private(set) var todayStats = DayStats()
    @Published private(set) var weekStats = DayStats()
    @Published private(set) var last7Days: [(date: String, stats: DayStats)] = []
    @Published private(set) var menuBarLabel = "—"
    @Published private(set) var isLoading = false
    @Published private(set) var usage: UsageData?
    @Published private(set) var lastRefreshed: Date?

    private let projectsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/projects")

    func load() {
        guard !isLoading else { return }
        isLoading = true

        let dir = projectsDir
        Task { [weak self] in
            async let usageFetch = ClaudeAuth.fetchUsage()
            async let statsFetch: [String: DayStats] = withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: StatsModel.parseFiles(in: dir))
                }
            }

            let fetchedUsage = await usageFetch
            await MainActor.run { [weak self] in
                self?.usage = fetchedUsage
                if let u = fetchedUsage {
                    let pct = u.sessionResetsAt != nil ? u.sessionPct : u.weeklyPct
                    self?.menuBarLabel = "\(Int(pct.rounded()))%"
                }
            }

            let fetchedStats = await statsFetch
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(fetchedStats)
                self.lastRefreshed = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Debug Info

    var debugInfo: String {
        var lines = [String]()
        lines.append("ClaudeUsage Debug Info")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Uptime: \(Int(ProcessInfo.processInfo.systemUptime))s")
        lines.append("")

        if let u = usage {
            lines.append("Session: \(Int(u.sessionPct.rounded()))%")
            lines.append("Weekly: \(Int(u.weeklyPct.rounded()))%")
            if let reset = u.weeklyResetsAt {
                lines.append("Weekly resets: \(ISO8601DateFormatter().string(from: reset))")
            }
        } else {
            lines.append("Usage: unavailable")
        }
        lines.append("")

        lines.append("Today: \(todayStats.messages) msgs, \(todayStats.toolCalls) tools, \(todayStats.outputTokens) out tokens")
        for (model, ms) in todayStats.byModel.sorted(by: { $0.value.messages > $1.value.messages }) {
            lines.append("  \(model): \(ms.messages) msgs, \(ms.outputTokens) out tokens")
        }
        lines.append("")

        lines.append("Week: \(weekStats.messages) msgs, \(weekStats.toolCalls) tools, \(weekStats.outputTokens) out tokens")
        for (model, ms) in weekStats.byModel.sorted(by: { $0.value.messages > $1.value.messages }) {
            lines.append("  \(model): \(ms.messages) msgs, \(ms.outputTokens) out tokens")
        }
        lines.append("")

        if let t = lastRefreshed {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lines.append("Last refresh: \(f.string(from: t))")
        }
        lines.append("Projects dir: \(projectsDir.path)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Model Detection

    /// Extracts the model family name (e.g. "Sonnet", "Opus", "Haiku") from a model string.
    /// Handles patterns like "claude-sonnet-4-6", "claude-3-5-sonnet-20241022", etc.
    static func extractModelFamily(from model: String) -> String {
        let parts = model.lowercased().split(separator: "-")
        guard let family = parts.first(where: { $0 != "claude" && !$0.allSatisfy(\.isNumber) }) else {
            return ""
        }
        return String(family).capitalized
    }

    // MARK: - Parsing

    private static func parseFiles(in projectsDir: URL) -> [String: DayStats] {
        var byDay: [String: DayStats] = [:]
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return byDay }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard modDate >= cutoff else { continue }
            parseFile(url, into: &byDay)
        }
        return byDay
    }

    private static func parseFile(_ url: URL, into byDay: inout [String: DayStats]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = obj["timestamp"] as? String else { continue }

            let day = String(ts.prefix(10))
            let sessionId = obj["sessionId"] as? String ?? url.path

            guard let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "assistant" else { continue }

            let tokenUsage = message["usage"] as? [String: Any] ?? [:]
            let outTokens = tokenUsage["output_tokens"] as? Int ?? 0
            guard outTokens > 0 else { continue }

            let model = (message["model"] as? String ?? "").lowercased()

            byDay[day, default: DayStats()].messages += 1
            byDay[day]!.outputTokens += outTokens
            byDay[day]!.inputTokens += tokenUsage["input_tokens"] as? Int ?? 0
            byDay[day]!.cacheReadTokens += tokenUsage["cache_read_input_tokens"] as? Int ?? 0
            byDay[day]!.sessions.insert(sessionId)

            let family = extractModelFamily(from: model)
            if !family.isEmpty {
                byDay[day]!.byModel[family, default: ModelStats()].messages += 1
                byDay[day]!.byModel[family, default: ModelStats()].outputTokens += outTokens
            }

            if let arr = message["content"] as? [[String: Any]] {
                byDay[day]!.toolCalls += arr.filter { $0["type"] as? String == "tool_use" }.count
            }
        }
    }

    // MARK: - Apply

    private func apply(_ byDay: [String: DayStats]) {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let weekAgo = f.string(from: cal.date(byAdding: .day, value: -6, to: Date())!)

        todayStats = byDay[today] ?? DayStats()

        var week = DayStats()
        for (day, s) in byDay where day >= weekAgo {
            week.messages += s.messages
            week.toolCalls += s.toolCalls
            week.outputTokens += s.outputTokens
            week.inputTokens += s.inputTokens
            week.cacheReadTokens += s.cacheReadTokens
            week.sessions.formUnion(s.sessions)
            for (model, ms) in s.byModel {
                week.byModel[model, default: ModelStats()].messages += ms.messages
                week.byModel[model, default: ModelStats()].outputTokens += ms.outputTokens
            }
        }
        weekStats = week

        last7Days = (0..<7).reversed().map { offset -> (String, DayStats) in
            let dateStr = f.string(from: cal.date(byAdding: .day, value: -offset, to: Date())!)
            return (dateStr, byDay[dateStr] ?? DayStats())
        }
    }
}
