import Foundation

func claudePath() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // The Claude desktop app keeps its own copy here, one folder per version, for people without the CLI.
    let desktop = "\(home)/Library/Application Support/Claude/claude-code"
    let versions = ((try? FileManager.default.contentsOfDirectory(atPath: desktop)) ?? [])
        .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    return (["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + versions.map { "\(desktop)/\($0)/claude.app/Contents/MacOS/claude" })
        .first(where: FileManager.default.isExecutableFile(atPath:))
}

/// Claude Code with `arguments` for a profile's folder (nil for ~/.claude), its output discarded. Nil when not installed.
func claude(_ arguments: [String], configDir: String?) -> Process? {
    guard let path = claudePath() else { return nil }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    // Not CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it also blocks the usage fetch itself.
    // Its own folder first: installed with npm, claude is a node script and node sits next to it.
    var environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "USER": NSUserName(), "LANG": "en_US.UTF-8",
                       "PATH": (path as NSString).deletingLastPathComponent + ":/usr/bin:/bin:/usr/sbin:/sbin",
                       "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1", "DISABLE_AUTOUPDATER": "1"]
    // Claude Code keys its login by this variable, so ~/.claude goes without it: set, it would look for another login.
    environment["CLAUDE_CONFIG_DIR"] = configDir
    process.environment = environment
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    return process
}

/// Asks the installed, unmodified Claude Code for its /usage data through a `get_usage` control request.
/// Claude Code uses its own login, so this app never touches a credential. No prompt is sent: zero tokens.
/// `configDir` is a profile's Claude Code folder, nil for ~/.claude.
func fetchUsage(configDir: String?) async -> UsageResult {
    // Empty setting sources: no hooks, plugins or MCP servers run. Nothing is saved as a session.
    guard let process = claude(["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                                "--no-session-persistence", "--strict-mcp-config", "--setting-sources", ""],
                               configDir: configDir) else { return .notFound }
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output

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

func accountEmail(configDir: String?) async -> String? {
    guard let process = claude(["auth", "status", "--json"], configDir: configDir) else { return nil }
    let output = Pipe()
    process.standardOutput = output
    do {
        try process.run()
        // Line by line, not as JSON: Claude Code draws this for a terminal, so a long value can wrap.
        for try await line in output.fileHandleForReading.bytes.lines {
            if let match = line.firstMatch(of: /"email": "([^"]+)"/) { return String(match.output.1) }
        }
    } catch {}
    return nil
}

/// Where Add profile signs in: ~/.claude while there is no profile, else the first free ~/.claude-2, ~/.claude-3…
nonisolated func nextProfile(after list: [String], home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
    guard !list.isEmpty else { return "" }
    var number = 2
    while list.contains("\(home)/.claude-\(number)") { number += 1 }
    return "\(home)/.claude-\(number)"
}

/// The folder's name without its leading dot: ~/.claude-work is "claude-work".
nonisolated func folderName(_ path: String) -> String {
    path.isEmpty ? "claude" : String(URL(fileURLWithPath: path).lastPathComponent.drop { $0 == "." })
}

nonisolated func profileName(_ path: String) -> String {
    UserDefaults.standard.dictionary(forKey: "names")?[path] as? String ?? folderName(path)
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
    /// Claude Code logs each session to a transcript under its folder's projects as it goes. Only the shown profiles count.
    func watchSessions() {
        if let sessions {
            FSEventStreamStop(sessions)
            FSEventStreamInvalidate(sessions)
            FSEventStreamRelease(sessions)
            self.sessions = nil
        }
        midReply = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude").path
        let projects = shown.map { ($0.isEmpty ? home : $0) + "/projects" }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let changed: FSEventStreamCallback = { _, info, _, paths, _, _ in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(info!).takeUnretainedValue()
            let files = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            // The stream runs on the main queue.
            MainActor.assumeIsolated { delegate.sessionsChanged(files) }
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        guard !projects.isEmpty, let stream = FSEventStreamCreate(nil, changed, &context, projects as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(flags)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        sessions = stream
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
