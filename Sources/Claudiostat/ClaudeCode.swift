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
    process.environment = ["HOME": home, "USER": NSUserName(), "LANG": "en_US.UTF-8",
                           "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"]
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
