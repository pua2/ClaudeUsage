import AppKit

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
    var cacheCreationTokens: Int = 0
    var sessions: Set<String> = []
    var byModel: [String: ModelStats] = [:]
    var toolsByName: [String: Int] = [:]
    var stopReasons: [String: Int] = [:]
    var responsesBySession: [String: Int] = [:]

    var sessionCount: Int { sessions.count }
    /// Total tokens sent to Claude: raw input + cache reads + cache creation.
    var totalInputTokens: Int { inputTokens + cacheReadTokens + cacheCreationTokens }
    var cacheHitRate: Double {
        let total = cacheReadTokens + cacheCreationTokens + inputTokens
        guard total > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(total) * 100
    }
    var avgResponsesPerSession: Double {
        guard sessionCount > 0 else { return 0 }
        return Double(messages) / Double(sessionCount)
    }
    var avgTokensPerResponse: Int {
        guard messages > 0 else { return 0 }
        return outputTokens / messages
    }
    var longestSession: Int {
        responsesBySession.values.max() ?? 0
    }
}

// MARK: - StatsModel

final class StatsModel: ObservableObject {
    @Published private(set) var todayStats = DayStats()
    @Published private(set) var weekStats = DayStats()
    @Published private(set) var last7Days: [(date: String, stats: DayStats)] = []
    @Published private(set) var isLoading = false
    @Published private(set) var usage: UsageData?
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var updateAvailable = false
    @Published private(set) var isUpdating = false

    private var pendingUpdate: (repo: String, remoteSHA: String, commits: String)?
    private var autoUpdateTimer: Timer?
    private static let autoUpdateKey = "autoUpdateCheckEnabled"
    private static let lastCheckKey = "lastAutoUpdateCheck"
    private static let skippedSHAKey = "skippedUpdateSHA"

    var isAutoUpdateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoUpdateKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoUpdateKey)
            if newValue { scheduleAutoUpdateCheck() }
            else { autoUpdateTimer?.invalidate(); autoUpdateTimer = nil }
        }
    }

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

    // MARK: - Compact Time

    /// Formats remaining time as max-3-char string: "35m", "2h", "6d".
    static func compactTime(until date: Date) -> String {
        let total = Int(date.timeIntervalSinceNow)
        if total <= 0 { return "0m" }
        let days = total / 86400
        if days > 0 { return "\(days)d" }
        let hours = total / 3600
        let leftoverMin = (total % 3600) / 60
        if hours > 0 { return "\(hours + (leftoverMin > 0 ? 1 : 0))h" }
        return "\(max(1, leftoverMin))m"
    }

    // MARK: - Updates

    func scheduleAutoUpdateCheck() {
        guard isAutoUpdateEnabled else { return }
        let lastCheck = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        let dayInterval: TimeInterval = 86400
        if Date().timeIntervalSince1970 - lastCheck >= dayInterval {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.checkForUpdates(silent: true)
            }
        }
        autoUpdateTimer?.invalidate()
        autoUpdateTimer = Timer.scheduledTimer(withTimeInterval: dayInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates(silent: true)
        }
    }

    func checkForUpdates(silent: Bool) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            guard let repo = Self.repoDirectory() else {
                if !silent { self.showUpdateAlert(title: "Update Error", message: "Could not find the ClaudeUsage git repository.") }
                return
            }
            guard Self.runGit(["fetch", "origin"], in: repo) != nil else {
                if !silent { self.showUpdateAlert(title: "Update Error", message: "git fetch failed. Check your network connection.") }
                return
            }
            let localHead = Self.runGit(["rev-parse", "HEAD"], in: repo) ?? ""
            let remoteHead = Self.runGit(["rev-parse", "origin/main"], in: repo) ?? ""
            guard localHead != remoteHead else {
                if !silent { self.showUpdateAlert(title: "Up to Date", message: "You're running the latest version.") }
                return
            }

            let commits = Self.runGit(["log", "--oneline", "HEAD..origin/main"], in: repo) ?? "(unknown changes)"
            let skipped = UserDefaults.standard.string(forKey: Self.skippedSHAKey)
            DispatchQueue.main.async {
                self.pendingUpdate = (repo, remoteHead, commits)
                self.updateAvailable = true
            }
            if silent && skipped == remoteHead { return }

            self.showUpdateAlert(
                title: "Update Available",
                message: "New commits on main:\n\n\(commits)",
                showInstall: true,
                remoteSHA: remoteHead
            )
        }
    }

    func installUpdate() {
        guard let pending = pendingUpdate else { return }
        isUpdating = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard Self.runGit(["pull", "origin", "main"], in: pending.repo) != nil else {
                self?.showUpdateAlert(title: "Update Failed", message: "git pull failed.")
                DispatchQueue.main.async { self?.isUpdating = false }
                return
            }
            let make = Process()
            make.executableURL = URL(fileURLWithPath: "/usr/bin/make")
            make.arguments = ["install"]
            make.currentDirectoryURL = URL(fileURLWithPath: pending.repo)
            make.standardOutput = FileHandle.nullDevice
            make.standardError = FileHandle.nullDevice
            do { try make.run() } catch {
                self?.showUpdateAlert(title: "Update Failed", message: "Build failed.")
                DispatchQueue.main.async { self?.isUpdating = false }
                return
            }
            make.waitUntilExit()
            guard make.terminationStatus == 0 else {
                self?.showUpdateAlert(title: "Update Failed", message: "Build failed (exit \(make.terminationStatus)).")
                DispatchQueue.main.async { self?.isUpdating = false }
                return
            }
            // make install kills old process and opens new one — but just in case:
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", "/Applications/ClaudeUsage.app"]
                try? task.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func showUpdateAlert(title: String, message: String, showInstall: Bool = false, remoteSHA: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            if showInstall {
                alert.addButton(withTitle: "Install Now")
                alert.addButton(withTitle: "Skip This Version")
                alert.addButton(withTitle: "Later")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    self?.installUpdate()
                } else if response == .alertSecondButtonReturn, let sha = remoteSHA {
                    UserDefaults.standard.set(sha, forKey: Self.skippedSHAKey)
                }
            } else {
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private static func repoDirectory() -> String? {
        if let saved = UserDefaults.standard.string(forKey: "repoPath"),
           FileManager.default.fileExists(atPath: "\(saved)/.git") {
            return saved
        }
        var url = URL(fileURLWithPath: Bundle.main.executablePath ?? "")
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
        }
        return nil
    }

    private static func runGit(_ arguments: [String], in directory: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
            parseFile(url, modDate: modDate, into: &byDay)
        }
        return byDay
    }

    private static func parseFile(_ url: URL, modDate: Date, into byDay: inout [String: DayStats]) {
        let filePath = url.path
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            // Unreadable file still counts as a session
            let day = f.string(from: modDate)
            byDay[day, default: DayStats()].sessions.insert(filePath)
            return
        }

        var activeDays = Set<String>()

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = obj["timestamp"] as? String else { continue }

            let day = String(ts.prefix(10))
            activeDays.insert(day)

            guard let message = obj["message"] as? [String: Any],
                  message["role"] as? String == "assistant" else { continue }

            let tokenUsage = message["usage"] as? [String: Any] ?? [:]
            let outTokens = tokenUsage["output_tokens"] as? Int ?? 0
            let model = (message["model"] as? String ?? "").lowercased()

            // Every assistant message is a response
            byDay[day, default: DayStats()].messages += 1
            byDay[day]!.outputTokens += outTokens
            byDay[day]!.inputTokens += tokenUsage["input_tokens"] as? Int ?? 0
            byDay[day]!.cacheReadTokens += tokenUsage["cache_read_input_tokens"] as? Int ?? 0
            byDay[day]!.cacheCreationTokens += tokenUsage["cache_creation_input_tokens"] as? Int ?? 0

            let family = extractModelFamily(from: model)
            if !family.isEmpty {
                byDay[day]!.byModel[family, default: ModelStats()].messages += 1
                byDay[day]!.byModel[family, default: ModelStats()].outputTokens += outTokens
            }

            if let arr = message["content"] as? [[String: Any]] {
                let tools = arr.filter { $0["type"] as? String == "tool_use" }
                byDay[day]!.toolCalls += tools.count
                for tool in tools {
                    if let name = tool["name"] as? String {
                        byDay[day]!.toolsByName[name, default: 0] += 1
                    }
                }
            }

            if let stopReason = message["stop_reason"] as? String, !stopReason.isEmpty {
                byDay[day]!.stopReasons[stopReason, default: 0] += 1
            }

            byDay[day]!.responsesBySession[filePath, default: 0] += 1
        }

        // Count this file as one session for every day it had any activity
        if activeDays.isEmpty {
            let day = f.string(from: modDate)
            byDay[day, default: DayStats()].sessions.insert(filePath)
        } else {
            for day in activeDays {
                byDay[day, default: DayStats()].sessions.insert(filePath)
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
            week.cacheCreationTokens += s.cacheCreationTokens
            week.sessions.formUnion(s.sessions)
            for (model, ms) in s.byModel {
                week.byModel[model, default: ModelStats()].messages += ms.messages
                week.byModel[model, default: ModelStats()].outputTokens += ms.outputTokens
            }
            for (tool, count) in s.toolsByName {
                week.toolsByName[tool, default: 0] += count
            }
            for (reason, count) in s.stopReasons {
                week.stopReasons[reason, default: 0] += count
            }
            for (session, count) in s.responsesBySession {
                week.responsesBySession[session, default: 0] += count
            }
        }
        weekStats = week

        last7Days = (0..<7).reversed().map { offset -> (String, DayStats) in
            let dateStr = f.string(from: cal.date(byAdding: .day, value: -offset, to: Date())!)
            return (dateStr, byDay[dateStr] ?? DayStats())
        }
    }
}
