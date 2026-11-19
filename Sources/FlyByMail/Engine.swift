import Foundation
import os

// The engine: every tick it (1) finds newly sent mail and reads the FlyBy tag, (2) returns tagged mail that is due and
// unanswered, (3) takes the marks off a returned mail once the user has replied to it. Everything goes through Mail's own
// scripting (osascript), so no password is needed. State lives in Application Support; the log in ~/Library/Logs/FlyByMail.

struct Entry: Codable {
    enum Status: String, Codable { case pending, answered, returned, cleared }
    var account: String
    var messageId: String          // without angle brackets
    var sentAt: Date
    var due: Date
    var noreply: Bool
    var status: Status
    var returnedAt: Date?
    var answeredBy: String?
}

struct State: Codable {
    var entries: [String: Entry] = [:]        // key = Message-Id
    var scanned: [String: Date] = [:]         // sent mail already looked at -> its sent date (pruned)
    var replyTargets: [String: Date] = [:]    // Message-Ids the user replied to -> date of that reply
}

struct TickReport {
    var started = Date()
    var sentSeen = 0, newlyScanned = 0, tagged = 0, returned = 0, answered = 0, unmarked = 0
    var errors: [String] = []
    var millis = 0
}

enum EngineLog {
    private static let osLog = Logger(subsystem: "app.legba.flybymail", category: "engine")
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FlyByMail")
    static let file = dir.appendingPathComponent("engine.log")

    /// One JSON object per line: easy to read, easy to grep, rich enough to reconstruct why something did or did not happen.
    static func write(_ event: String, _ fields: [String: Any] = [:]) {
        var obj = fields
        obj["event"] = event
        obj["at"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        osLog.info("\(line, privacy: .public)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        } else {
            try? Data((line + "\n").utf8).write(to: file)
        }
    }
}

final class Engine {
    static let scanDays = 30
    static let pruneDays = 45

    private let stateURL: URL
    private(set) var state: State

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FlyByMail")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appendingPathComponent("state.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        state = (try? decoder.decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
    }

    var pendingCount: Int { state.entries.values.filter { $0.status == .pending }.count }
    var returnedCount: Int { state.entries.values.filter { $0.status == .returned }.count }

    private func save() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    // MARK: running Mail scripts

    private func scriptSource(_ name: String) throws -> String {
        guard let common = Bundle.main.url(forResource: "common", withExtension: "applescript", subdirectory: "engine"),
              let body = Bundle.main.url(forResource: name, withExtension: "applescript", subdirectory: "engine") else {
            throw EngineError.missingScript(name)
        }
        return try String(contentsOf: common) + "\n" + String(contentsOf: body)
    }

    enum EngineError: Error, CustomStringConvertible {
        case missingScript(String), script(name: String, status: Int32, stderr: String), timeout(String)
        var description: String {
            switch self {
            case .missingScript(let n): return "script \(n) missing from the app bundle"
            case .script(let n, let s, let e): return "script \(n) failed (exit \(s)): \(e)"
            case .timeout(let n): return "script \(n) timed out"
            }
        }
    }

    /// Runs one engine script with osascript (reads the script from stdin, arguments follow). 90 s deadline.
    func run(_ name: String, _ args: [String]) throws -> String {
        let source = try scriptSource(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-"] + args
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
        try p.run()
        inPipe.fileHandleForWriting.write(Data(source.utf8)); try? inPipe.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(90)
        var out = Data(), err = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { out = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { err = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning { if Date() > deadline { p.terminate(); throw EngineError.timeout(name) }; usleep(100_000) }
        group.wait()
        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0 else {
            throw EngineError.script(name: name, status: p.terminationStatus, stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }

    // MARK: one tick

    @discardableResult
    func tick(now: Date = Date()) -> TickReport {
        var report = TickReport(started: now)
        let t0 = Date()
        func fail(_ what: String, _ error: Error) {
            report.errors.append("\(what): \(error)")
            EngineLog.write("error", ["step": what, "error": "\(error)"])
        }

        // 1. newly sent mail -> read headers once -> find tagged mail and replies the user wrote
        var fresh: [String: [String: Date]] = [:]   // account -> messageId -> sentAt
        do {
            let out = try run("sent-ids", ["\(Engine.scanDays)"])
            for line in out.split(separator: "\n") {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count == 3, let age = Double(f[2]) else { continue }
                report.sentSeen += 1
                let sentAt = now.addingTimeInterval(-age)
                if state.scanned[f[1]] == nil { fresh[f[0], default: [:]][f[1]] = sentAt }
            }
        } catch { fail("sent-ids", error) }

        for (account, ids) in fresh {
            let list = Array(ids.keys)
            for batch in stride(from: 0, to: list.count, by: 20).map({ Array(list[$0..<min($0 + 20, list.count)]) }) {
                do {
                    let out = try run("headers", [account] + batch)
                    for line in out.split(separator: "\n") {
                        var f = line.split(separator: "\t", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
                        while f.count < 3 { f.append("") }   // osascript trims a trailing empty field's tab
                        guard let sentAt = ids[f[0]] else { continue }
                        if f[1].hasPrefix("ERROR") { EngineLog.write("header-read-failed", ["id": f[0], "detail": f[1]]); continue }
                        state.scanned[f[0]] = sentAt
                        report.newlyScanned += 1
                        if let tag = Self.parseTag(f[1]) {
                            state.entries[f[0]] = Entry(account: account, messageId: f[0], sentAt: sentAt, due: tag.due, noreply: tag.noreply, status: .pending)
                            report.tagged += 1
                            EngineLog.write("tagged", ["account": account, "id": f[0], "due": ISO8601DateFormatter().string(from: tag.due), "noreply": tag.noreply])
                        }
                        for target in f[2].split(whereSeparator: { " <>".contains($0) }) where !target.isEmpty {
                            let key = String(target)
                            state.replyTargets[key] = max(state.replyTargets[key] ?? .distantPast, sentAt)
                        }
                    }
                } catch { fail("headers", error) }
            }
        }

        // 2. due and still pending -> answered, or return
        for var entry in state.entries.values where entry.status == .pending && entry.due <= now {
            let age = max(1, Int(now.timeIntervalSince(entry.sentAt)))
            var answeredBy: String?
            if entry.noreply {
                do { answeredBy = try run("replies", [entry.account, entry.messageId, "\(age)"]).split(separator: "\n").first.map(String.init) }
                catch { fail("replies", error); continue }   // unknown: try again next tick rather than returning blindly
            }
            if let who = answeredBy {
                entry.status = .answered; entry.answeredBy = who; report.answered += 1
                EngineLog.write("answered", ["id": entry.messageId, "by": who, "due": ISO8601DateFormatter().string(from: entry.due), "decision": "not returned"])
            } else {
                do {
                    let result = try run("return", [entry.account, entry.messageId])
                    entry.status = .returned; entry.returnedAt = now; report.returned += 1
                    EngineLog.write("returned", ["id": entry.messageId, "noreply": entry.noreply, "result": result,
                                                 "late_by_s": Int(now.timeIntervalSince(entry.due))])
                } catch { fail("return", error); continue }
            }
            state.entries[entry.messageId] = entry
        }

        // 3. returned and the user replied afterwards -> take the marks off
        for var entry in state.entries.values where entry.status == .returned {
            guard let returnedAt = entry.returnedAt, let repliedAt = state.replyTargets[entry.messageId], repliedAt > returnedAt else { continue }
            do {
                let result = try run("unmark", [entry.account, entry.messageId])
                entry.status = .cleared; report.unmarked += 1
                EngineLog.write("unmarked", ["id": entry.messageId, "result": result, "replied_at": ISO8601DateFormatter().string(from: repliedAt)])
                state.entries[entry.messageId] = entry
            } catch { fail("unmark", error) }
        }

        // 4. housekeeping
        let cutoff = now.addingTimeInterval(-Double(Engine.pruneDays) * 86400)
        state.scanned = state.scanned.filter { $0.value > cutoff }
        state.replyTargets = state.replyTargets.filter { $0.value > cutoff }
        state.entries = state.entries.filter { $0.value.status == .pending || $0.value.status == .returned || $0.value.sentAt > cutoff }
        save()

        report.millis = Int(Date().timeIntervalSince(t0) * 1000)
        EngineLog.write("tick", ["sent_seen": report.sentSeen, "newly_scanned": report.newlyScanned, "tagged": report.tagged,
                                 "returned": report.returned, "answered": report.answered, "unmarked": report.unmarked,
                                 "pending": pendingCount, "errors": report.errors.count, "ms": report.millis])
        return report
    }

    /// "v=1; due=1795089346; noreply=1"
    static func parseTag(_ value: String) -> (due: Date, noreply: Bool)? {
        var due: TimeInterval?, noreply = true
        for part in value.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            if kv[0] == "due" { due = TimeInterval(kv[1]) }
            if kv[0] == "noreply" { noreply = kv[1] != "0" }
        }
        guard let d = due else { return nil }
        return (Date(timeIntervalSince1970: d), noreply)
    }
}
