import Foundation

// MARK: - Data Models

struct DayStats {
    var messages: Int = 0
    var toolCalls: Int = 0
    var outputTokens: Int = 0
    var inputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var sessions: Set<String> = []
    var sessionCount: Int { sessions.count }
}

// MARK: - StatsModel

final class StatsModel: ObservableObject {
    @Published private(set) var todayStats   = DayStats()
    @Published private(set) var weekStats    = DayStats()
    @Published private(set) var last7Days: [(date: String, stats: DayStats)] = []
    @Published private(set) var menuBarLabel = "—"
    @Published private(set) var isLoading     = false
    @Published private(set) var usage: UsageData?
    @Published private(set) var lastRefreshed: Date?

    private let projectsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/projects")

    func load() {
        guard !isLoading else { return }
        isLoading = true

        let dir = projectsDir
        Task { [weak self] in
            // Start both fetches concurrently
            async let usageFetch = ClaudeAuth.fetchUsage()
            async let statsFetch: [String: DayStats] = withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: StatsModel.parseFiles(in: dir))
                }
            }

            // Apply usage as soon as it arrives (fast — API call)
            let fetchedUsage = await usageFetch
            await MainActor.run { [weak self] in
                self?.usage = fetchedUsage
                if let u = fetchedUsage {
                    let pct = u.sessionResetsAt != nil ? u.sessionPct : u.weeklyPct
                    self?.menuBarLabel = "\(Int(pct.rounded()))%"
                }
            }

            // Apply local stats (may take a moment — 500+ files)
            let fetchedStats = await statsFetch
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apply(fetchedStats)
                self.lastRefreshed = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Parsing (static so it can be called off-actor)

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
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts   = obj["timestamp"] as? String else { continue }

            let day       = String(ts.prefix(10))
            let sessionId = obj["sessionId"] as? String ?? url.path

            guard let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "assistant" else { continue }

            let usage = message["usage"] as? [String: Any] ?? [:]
            let outTokens = usage["output_tokens"] as? Int ?? 0
            guard outTokens > 0 else { continue }

            byDay[day, default: DayStats()].messages      += 1
            byDay[day]!.outputTokens   += outTokens
            byDay[day]!.inputTokens    += usage["input_tokens"] as? Int ?? 0
            byDay[day]!.cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
            byDay[day]!.sessions.insert(sessionId)

            if let arr = message["content"] as? [[String: Any]] {
                byDay[day]!.toolCalls += arr.filter { $0["type"] as? String == "tool_use" }.count
            }
        }
    }

    // MARK: - Apply

    private func apply(_ byDay: [String: DayStats]) {
        let cal = Calendar.current
        let f   = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today    = f.string(from: Date())
        let weekAgo  = f.string(from: cal.date(byAdding: .day, value: -6, to: Date())!)

        todayStats = byDay[today] ?? DayStats()

        var week = DayStats()
        for (day, s) in byDay where day >= weekAgo {
            week.messages      += s.messages
            week.toolCalls     += s.toolCalls
            week.outputTokens  += s.outputTokens
            week.inputTokens   += s.inputTokens
            week.cacheReadTokens += s.cacheReadTokens
            week.sessions.formUnion(s.sessions)
        }
        weekStats = week

        last7Days = (0..<7).reversed().map { offset -> (String, DayStats) in
            let dateStr = f.string(from: cal.date(byAdding: .day, value: -offset, to: Date())!)
            return (dateStr, byDay[dateStr] ?? DayStats())
        }
    }
}
