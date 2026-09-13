import AppKit

/// `--usage-json` prints the current usage windows as JSON and exits, so other tools
/// (scripts, agents, CI) can read the same numbers the menu bar shows without
/// reimplementing the cookie decryption. Everything else launches the menu bar app.
if CommandLine.arguments.contains("--usage-json") {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 1

    Task { @MainActor in
        defer { semaphore.signal() }
        guard let usage = await ClaudeAuth.fetchUsage() else {
            FileHandle.standardError.write(Data("could not read usage: no credentials or no response\n".utf8))
            return
        }
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "sessionPct": usage.sessionPct,
            "sessionResetsAt": usage.sessionResetsAt.map(iso.string(from:)) ?? NSNull(),
            "weeklyPct": usage.weeklyPct,
            "weeklyResetsAt": usage.weeklyResetsAt.map(iso.string(from:)) ?? NSNull(),
            "fetchedAt": iso.string(from: Date())
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exitCode = 0
    }

    // WKWebView needs a live run loop, so pump it until the task signals.
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(exitCode)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
