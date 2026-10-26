import Foundation
import Testing
@testable import ClaudioStat

// What the desktop widget reads (Sources/ClaudioStatWidget/Usage.swift): pct, reset in epoch seconds, src, S and W
// speeds per hour.
@MainActor @Test func widgetReadsTheProfilesNumbers() throws {
    let now = ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z")!, epoch = Int(now.timeIntervalSince1970)
    func usage(_ session: Int, _ week: Int) -> Usage {
        Usage(session: Limit(percent: session, resetsAt: now.addingTimeInterval(3600), severity: "normal"),
              week: Limit(percent: week, resetsAt: now.addingTimeInterval(3 * 86400)))
    }
    // S rose 10 in the last half hour, W 2 in the last hour.
    let account = Account(usage: usage(30, 13), samples: [Sample(at: now.addingTimeInterval(-3600), usage: usage(10, 11)),
                                                          Sample(at: now.addingTimeInterval(-1800), usage: usage(20, 12)),
                                                          Sample(at: now, usage: usage(30, 13))],
                          updated: now, problem: "signed_out")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = String(decoding: try encoder.encode(widgetReply(account)), as: UTF8.self)
    #expect(json == """
        {"checkedAt":\(epoch),"loginNeeded":true,"snap":{"s":{"locked":false,"pct":30,"reset":\(epoch + 3600),"severity":"normal"},\
        "src":"app","w":{"locked":false,"pct":13,"reset":\(epoch + 3 * 86400)}},"speed":{"s":20,"w":2}}
        """)
    #expect(widgetReply(Account()) == nil)
}
