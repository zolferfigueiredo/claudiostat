import Foundation

/// Asks the installed, unmodified Claude Code for its /usage data through a `get_usage` control request.
/// Claude Code uses its own login, so this app never touches a credential. No prompt is sent: zero tokens.
func fetchUsage() async -> UsageResult {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard let path = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        .first(where: FileManager.default.isExecutableFile(atPath:)) else { return .notFound }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    // Empty setting sources: no hooks, plugins or MCP servers run. Nothing is saved as a session.
    process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                         "--no-session-persistence", "--strict-mcp-config", "--setting-sources", ""]
    // Not CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it also blocks the usage fetch itself.
    process.environment = ["HOME": home, "USER": NSUserName(), "LANG": "en_US.UTF-8",
                           "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                           "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1", "DISABLE_AUTOUPDATER": "1"]
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    log.notice("asking Claude Code")
    do { try process.run() } catch { return .failed }
    let timeout = Task {
        try? await Task.sleep(for: .seconds(30))
        process.terminate()
    }
    defer {
        timeout.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
    let request = #"{"type":"control_request","request_id":"1","request":{"subtype":"get_usage","skip_behaviors":true}}"#
    try? input.fileHandleForWriting.write(contentsOf: Data((request + "\n").utf8))

    do {
        for try await line in output.fileHandleForReading.bytes.lines {
            guard let result = parseReply(line) else { continue }
            if result == .failed { log.notice("Claude Code reply: \(line.prefix(300), privacy: .public)") }
            return result
        }
    } catch {}
    // Timed out, or Claude Code exited without answering.
    log.notice("Claude Code ended without an answer, exit \(process.isRunning ? -1 : process.terminationStatus, privacy: .public)")
    return .failed
}

/// Whether a Claude Code session is writing a reply, from the end of its transcript: after a prompt or a tool result
/// it is. A tool call stops it (the tool runs, or waits for you), and so does the reply's final text or pressing Esc.
nonisolated func thinking(_ transcript: String) -> Bool {
    for line in transcript.split(separator: "\n").reversed() {
        guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = entry["message"] as? [String: Any] else { continue }
        let last = (message["content"] as? [[String: Any]])?.last
        switch entry["type"] as? String {
        case "user":
            let text = (last?["text"] ?? last?["content"] ?? message["content"]) as? String ?? ""
            return !text.hasPrefix("[Request interrupted by user")
        case "assistant":
            // A reply is logged block by block: after thinking, or text that comes before a tool call, more follows.
            let kind = last?["type"] as? String
            return kind == "thinking" || kind == "redacted_thinking" || (kind == "text" && message["stop_reason"] as? String == "tool_use")
        default:
            continue
        }
    }
    return false
}

extension AppDelegate {
    /// Claude Code logs each session to a transcript under ~/.claude/projects as it goes.
    func watchSessions() {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects").path
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let changed: FSEventStreamCallback = { _, info, _, paths, _, _ in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(info!).takeUnretainedValue()
            let files = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            // The stream runs on the main queue.
            MainActor.assumeIsolated { delegate.sessionsChanged(files) }
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(nil, changed, &context, [projects] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func sessionsChanged(_ files: [String]) {
        for path in files where path.hasSuffix(".jsonl") {
            // The last megabyte: a single tool result can be large.
            guard let file = FileHandle(forReadingAtPath: path) else { midReply[path] = nil; continue }
            let size = (try? file.seekToEnd()) ?? 0
            try? file.seek(toOffset: size - min(size, 1 << 20))
            let tail = String(decoding: file.readDataToEndOfFile(), as: UTF8.self)
            try? file.close()
            midReply[path] = thinking(tail) ? .now : nil
        }
        render()
    }
}
