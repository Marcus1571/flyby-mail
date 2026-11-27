import AppKit
import CryptoKit
import Foundation
import os
import Security

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
    var markId: String?        // Message-Id of the REMINDER mail that carries the marks (nil for older entries: then the copy of the original does)
    var marksPending: Bool?    // the reminder has not been seen in the inbox and marked yet
    var marksTries: Int?       // ticks spent waiting for it
    var source: String?        // "received": a mail the user picked in the Inbox with the menu-bar picker (nil: a mail the user sent, tagged by the compose extension)
}

extension Entry { var markKey: String { markId ?? messageId } }

struct State: Codable {
    var entries: [String: Entry] = [:]        // key = Message-Id
    var scanned: [String: Date] = [:]         // sent mail already looked at -> its sent date (pruned)
    var replyTargets: [String: Date] = [:]    // Message-Ids the user replied to -> date of that reply
    var lastActivityScan: Date?               // last time every inbox was checked for answers to returned mail
}

struct TickReport {
    var started = Date()
    var sentSeen = 0, newlyScanned = 0, tagged = 0, returned = 0, answered = 0, unmarked = 0
    var errors: [String] = []
    var millis = 0
}

/// Optional shared claim service (see backend/): several Macs on one account ask "may I send the reminder for this mail?" before sending, so
/// two engines ticking at the same moment cannot both send. Not configured = single-machine mode, exactly as before.
/// Config: defaults key `backendURL` (or env FLYBY_BACKEND_URL); Keychain services app.legba.flybymail.backend (the Mac's key), .backend.cfid and .backend.cfsecret (Cloudflare Access token), or the env FLYBY_BACKEND_KEY / FLYBY_CF_ID / FLYBY_CF_SECRET.
enum Backend {
    /// done = the holder already sent it (the claim never expires): this Mac drops the mail.
    enum Result: Equatable { case notConfigured, won, lost(String), done(String), unavailable(String) }
    /// An entry this late with the service still unreachable is sent anyway: a dead server must not silence reminders for good.
    static let failOpenAfter: TimeInterval = 1800

    /// A secret from the environment (tests) or the Keychain (service name below); nil when absent.
    static func secret(env: String, service: String) -> String? {
        if let k = ProcessInfo.processInfo.environment[env] { return k }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func claim(messageId: String) -> Result { post(messageId: messageId, finished: false) }
    /// After sending: tell the service, so the other Macs drop the mail instead of retrying once the claim would have expired.
    static func finish(messageId: String) -> Result { post(messageId: messageId, finished: true) }

    private static func post(messageId: String, finished: Bool) -> Result {
        let urlString = ProcessInfo.processInfo.environment["FLYBY_BACKEND_URL"] ?? UserDefaults.standard.string(forKey: "backendURL")
        guard let urlString, !urlString.isEmpty, let base = URL(string: urlString) else { return .notConfigured }
        guard let key = secret(env: "FLYBY_BACKEND_KEY", service: "app.legba.flybymail.backend"), !key.isEmpty else { return .unavailable("no key in the Keychain") }
        var req = URLRequest(url: base.appendingPathComponent("claim"), timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        // Cloudflare Access service token (door 1), only when set: the service itself checks the Mac's key (door 2).
        if let id = secret(env: "FLYBY_CF_ID", service: "app.legba.flybymail.backend.cfid"),
           let sec = secret(env: "FLYBY_CF_SECRET", service: "app.legba.flybymail.backend.cfsecret") {
            req.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id"); req.setValue(sec, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
        let id = SHA256.hash(data: Data(messageId.utf8)).map { String(format: "%02x", $0) }.joined()
        var body: [String: Any] = ["id": id]
        if finished { body["done"] = true }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var result = Result.unavailable("no answer")
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { done.signal() }
            if let err { result = .unavailable(err.localizedDescription); return }
            guard let code = (resp as? HTTPURLResponse)?.statusCode, code == 200,
                  let obj = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any], let won = obj["won"] as? Bool else {
                result = .unavailable("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"); return
            }
            let holder = obj["holder"] as? String ?? "?"
            result = won ? .won : (obj["done"] as? Bool == true ? .done(holder) : .lost(holder))
        }.resume()
        _ = done.wait(timeout: .now() + 8)
        return result
    }
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
    /// A tagged mail seen for the first time after its due time (plus this grace, for a Mac that slept through a tick) is never returned:
    /// a new machine or a wiped state.json must not replay old reminders (Macai flood, 2026-11-23).
    static let graceSeconds: TimeInterval = 600
    /// At most this many reminder mails are sent per tick; the rest wait for the next tick.
    static let maxReturnsPerTick = 3

    static func isExpiredOnFirstSight(due: Date, now: Date) -> Bool { due < now.addingTimeInterval(-graceSeconds) }

    private let lock = NSLock()   // a tick and a menu action must not run at the same time
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
    var marksPendingCount: Int { state.entries.values.filter { $0.status == .returned && $0.marksPending == true }.count }
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
        lock.lock(); defer { lock.unlock() }
        var report = TickReport(started: now)
        var rescuedReturned = Set<String>()   // returned mails whose reply was just rescued from Junk
        let t0 = Date()

        // Talking to Mail through AppleScript starts Mail if it is not running. Never do that behind the user's back:
        // with Mail closed there is nothing new to see, so skip. Only when a reminder is due do we start Mail, hidden and in the background.
        func mailIsRunning() -> Bool { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" } }
        if !mailIsRunning() {
            guard state.entries.values.contains(where: { $0.status == .pending && $0.due <= now }) else {
                EngineLog.write("tick-skipped", ["reason": "Mail is not running and nothing is due"])
                return report
            }
            EngineLog.write("starting-mail", ["reason": "a reminder is due and Mail is closed; starting it hidden"])
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = ["-g", "-j", "-a", "Mail"]
            try? opener.run(); opener.waitUntilExit()
            for _ in 0..<40 where !mailIsRunning() { Thread.sleep(forTimeInterval: 0.5) }
            Thread.sleep(forTimeInterval: 5)   // let Mail load its accounts before scripting it
        }
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
                        if let tag = Self.parseTag(f[1]), Self.isExpiredOnFirstSight(due: tag.due, now: now) {
                            EngineLog.write("expired", ["account": account, "id": f[0], "due": ISO8601DateFormatter().string(from: tag.due),
                                                        "late_by_s": Int(now.timeIntervalSince(tag.due)), "decision": "first seen after its due time, not returned"])
                        } else if let tag = Self.parseTag(f[1]) {
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

        // 1b. A reply can be filed as junk (Yahoo Bulk, Gmail Spam, or Mail's own filter): look in the junk mailboxes and move real replies back to the Inbox.
        let tracked = state.entries.values.filter { $0.status == .returned || ($0.status == .pending && $0.noreply) }
        if !tracked.isEmpty {
            let age = min(max(Int(now.timeIntervalSince(tracked.map(\.sentAt).min() ?? now)) + 120, 60), 14 * 86400)
            do {
                let out = try run("rescue", ["\(age)"] + tracked.map(\.messageId))
                for line in out.split(separator: "\n") {
                    let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard f.count >= 2, var entry = state.entries[f[0]] else { continue }
                    EngineLog.write("rescued", ["id": f[0], "from": f[1], "account": f.count > 2 ? f[2] : "", "note": "reply was in Junk, moved to the Inbox"])
                    if entry.status == .pending {
                        entry.status = .answered; entry.answeredBy = f[1]; report.answered += 1
                        state.entries[f[0]] = entry
                    } else { rescuedReturned.insert(f[0]) }
                }
            } catch { fail("rescue", error) }
        }

        // 2. due and still pending -> answered, or return
        var justReturned: [Entry] = []
        var deferred = 0
        for var entry in state.entries.values.filter({ $0.status == .pending && $0.due <= now }).sorted(by: { $0.due < $1.due }) {
            let age = max(1, Int(now.timeIntervalSince(entry.sentAt)))
            var answeredBy: String?
            // You replied to your own mail since sending it (from any account in Mail): you have dealt with it, nothing to bring back.
            // Only for "only if nobody replies": a plain timed reminder comes back whatever happens (like Gmail with the switch off).
            if entry.noreply, let followUp = state.replyTargets[entry.messageId], followUp > entry.sentAt {
                entry.status = .answered; entry.answeredBy = "you"; report.answered += 1
                EngineLog.write("answered", ["id": entry.messageId, "by": "you", "followup_at": ISO8601DateFormatter().string(from: followUp),
                                             "due": ISO8601DateFormatter().string(from: entry.due), "decision": "not returned"])
                state.entries[entry.messageId] = entry
                continue
            }
            if entry.noreply {
                do { answeredBy = try run("replies", [entry.account, entry.messageId, "\(age)"]).split(separator: "\n").first.map(String.init) }
                catch { fail("replies", error); continue }   // unknown: try again next tick rather than returning blindly
            }
            if let who = answeredBy {
                entry.status = .answered; entry.answeredBy = who; report.answered += 1
                EngineLog.write("answered", ["id": entry.messageId, "by": who, "due": ISO8601DateFormatter().string(from: entry.due), "decision": "not returned"])
            } else {
                if report.returned >= Engine.maxReturnsPerTick { deferred += 1; continue }   // cap per tick: stays pending, next tick
                let claim = Backend.claim(messageId: entry.messageId)
                switch claim {
                case .notConfigured, .won: break
                case .done(let holder):   // another Mac sent it and said so: nothing left to do here (that Mac marks and later unmarks the reminder)
                    entry.status = .cleared; state.entries[entry.messageId] = entry
                    EngineLog.write("claim-done", ["id": entry.messageId, "holder": holder, "decision": "sent by \(holder), dropped"]); continue
                case .lost(let holder):   // another Mac is sending it: it stays pending, next tick finds that reminder in Sent and reuses it
                    EngineLog.write("claim-lost", ["id": entry.messageId, "holder": holder]); continue
                case .unavailable(let why):
                    let late = now.timeIntervalSince(entry.due)
                    EngineLog.write("claim-unavailable", ["id": entry.messageId, "why": why, "late_by_s": Int(late), "decision": late > Backend.failOpenAfter ? "sending anyway" : "wait"])
                    if late <= Backend.failOpenAfter { continue }
                }
                do {
                    let result = try run("remind", [entry.account, entry.messageId, entry.noreply ? "1" : "0", entry.source ?? "sent"])
                    if result.hasPrefix("original-missing") {   // the picked mail was deleted or moved out of reach: nothing to bring back
                        entry.status = .cleared; state.entries[entry.messageId] = entry
                        EngineLog.write("original-missing", ["id": entry.messageId, "decision": "dropped, not returned"])
                        continue
                    }
                    entry.status = .returned; entry.returnedAt = now; report.returned += 1
                    if result.hasPrefix("reminder "), !result.hasPrefix("reminder-") {
                        entry.markId = String(result.dropFirst("reminder ".count)).trimmingCharacters(in: .whitespaces)
                        entry.marksPending = true; entry.marksTries = 0
                    }
                    justReturned.append(entry)
                    if claim == .won {
                        let r = Backend.finish(messageId: entry.messageId)
                        if r != .won { EngineLog.write("finish-failed", ["id": entry.messageId, "result": "\(r)", "effect": "claim expires after 10 min as before"]) }
                    }
                    EngineLog.write("returned", ["id": entry.messageId, "noreply": entry.noreply, "reminder_id": entry.markId ?? "unknown", "result": result,
                                                 "late_by_s": Int(now.timeIntervalSince(entry.due))])
                } catch { fail("return", error); continue }
            }
            state.entries[entry.messageId] = entry
        }

        if deferred > 0 {
            EngineLog.write("cap-reached", ["sent_this_tick": report.returned, "deferred": deferred, "cap": Engine.maxReturnsPerTick])
            Self.notify("FlyByMail sent \(report.returned) reminders and holds back \(deferred) more until the next check.")
        }

        // 2b. The reminder mail needs a few seconds to arrive in the inbox. Mark it (orange flag + background, unread) as soon as it is there: poll for up to
        //     a minute right after sending, and keep trying on later ticks (up to 12 ticks, an hour) for any reminder still waiting.
        let rounds = justReturned.isEmpty ? 1 : 6
        for round in 0..<rounds {
            let waiting = state.entries.values.filter { $0.status == .returned && $0.marksPending == true }
            if waiting.isEmpty { break }
            if round > 0 { Thread.sleep(forTimeInterval: 10) }
            for (account, entries) in Dictionary(grouping: waiting, by: \.account) {
                do {
                    let out = try run("ensure-marks", [account] + entries.map(\.markKey))
                    EngineLog.write("marks-checked", ["account": account, "round": round, "result": out.replacingOccurrences(of: "\n", with: " | ")])
                    let done = Set(out.split(separator: "\n").compactMap { line -> String? in
                        line.contains("flagged=true") && line.contains("color=orange") ? line.split(separator: " ").first.map(String.init) : nil
                    })
                    for var e in entries where done.contains(e.markKey) { e.marksPending = false; state.entries[e.messageId] = e }
                } catch { fail("ensure-marks", error) }
            }
        }
        for var e in state.entries.values where e.status == .returned && e.marksPending == true {
            e.marksTries = (e.marksTries ?? 0) + 1
            // Give up after an hour, counted in time: the 30 s quick retry makes the tick count a bad clock (12 ticks were only 6 minutes).
            if now.timeIntervalSince(e.returnedAt ?? now) > 3600 { e.marksPending = false; EngineLog.write("marks-gave-up", ["id": e.messageId, "reminder_id": e.markKey, "tries": e.marksTries ?? 0]) }
            state.entries[e.messageId] = e
        }

        // 3. returned mail that has been answered (by you from Mail, or by anyone, landing in any account) -> take the marks off
        let returnedEntries = state.entries.values.filter { $0.status == .returned }
        if !returnedEntries.isEmpty {
            var reasons: [String: String] = [:]
            for e in returnedEntries {
                // A follow-up written BEFORE the reminder came back (possible when "only if nobody replies" is off) is not an answer to the reminder.
                let repliedAt = [state.replyTargets[e.messageId], state.replyTargets[e.markKey]].compactMap { $0 }.max()
                if let repliedAt, repliedAt > (e.returnedAt ?? e.sentAt) { reasons[e.messageId] = "you replied" }
            }
            // Per mail: only mail that arrived AFTER that reminder came back (and since the last look, minus a margin) can be an answer to it.
            // A reply that landed before the return (switch off, answered ahead of time) must not clear the new marks.
            let pairs = returnedEntries.map { e -> String in
                let since = max(e.returnedAt ?? e.sentAt, (state.lastActivityScan ?? .distantPast).addingTimeInterval(-120))
                let age = min(max(Int(now.timeIntervalSince(since)), 60), 14 * 86400)
                return "\(e.messageId)|\(age)"
            }
            do {
                let out = try run("activity", pairs)
                for id in out.split(separator: "\n").map(String.init) where reasons[id] == nil { reasons[id] = "a reply arrived" }
                for id in rescuedReturned where reasons[id] == nil { reasons[id] = "a reply arrived (rescued from Junk)" }
                state.lastActivityScan = now
            } catch { fail("activity", error) }
            for (id, reason) in reasons {
                guard var entry = state.entries[id] else { continue }
                do {
                    let result = try run("unmark", [entry.account, entry.markKey])
                    entry.status = .cleared; report.unmarked += 1
                    EngineLog.write("unmarked", ["id": id, "reason": reason, "result": result])
                    state.entries[id] = entry
                } catch { fail("unmark", error) }
            }
        }

        // 3b. dismissed by the user: flag clicked off, or the mail moved/deleted. (Mails returned in this tick are left alone, their marks are still settling.)
        let justIds = Set(justReturned.map(\.messageId))
        let looked = state.entries.values.filter { $0.status == .returned && $0.marksPending != true && !justIds.contains($0.messageId) }
        for (account, entries) in Dictionary(grouping: looked, by: \.account) {
            let byMark = Dictionary(entries.map { ($0.markKey, $0.messageId) }, uniquingKeysWith: { first, _ in first })
            do {
                let out = try run("check-dismissed", [account] + entries.map(\.markKey))
                for line in out.split(separator: "\n") {
                    let f = line.split(separator: "\t", maxSplits: 1).map(String.init)
                    guard f.count == 2, let key = byMark[f[0]], var entry = state.entries[key] else { continue }
                    entry.status = .cleared; report.unmarked += 1
                    state.entries[key] = entry
                    EngineLog.write("unmarked", ["id": key, "reason": f[1] == "gone" ? "the mail left the Inbox" : "you cleared the flag"])
                }
            } catch { fail("check-dismissed", error) }
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

    // MARK: reminders on a mail you pick (menu-bar picker)

    struct SelectedMail { var account: String, messageId: String, subject: String, sender: String }

    /// The mail selected in Mail right now (nil when Mail is closed or nothing is selected). Never starts Mail.
    func selectedMail() -> SelectedMail? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" }) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let out = try? run("selected-mail", []), !out.isEmpty else { return nil }
        let f = out.split(separator: "\t", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard f.count >= 4 else { return nil }
        return SelectedMail(account: f[0], messageId: f[1], subject: f[2], sender: f[3])
    }

    /// The reminder state of a mail (by its own Message-Id, or by the Message-Id of the reminder mail that stands for it), for the panel.
    func entry(for id: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return state.entries[id] ?? state.entries.values.first { $0.markId == id }
    }

    /// Cancels a reminder that has not come back yet.
    func cancel(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        guard var e = state.entries[id], e.status == .pending else { return }
        e.status = .cleared; state.entries[id] = e; save()
        EngineLog.write("cancelled", ["id": id, "reason": "cancelled from the panel"])
    }

    /// Starts watching a received mail: if nobody (you or anyone) replies after now, it comes back at `due` like a mail you sent.
    func track(_ mail: SelectedMail, due: Date) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        state.entries[mail.messageId] = Entry(account: mail.account, messageId: mail.messageId, sentAt: now, due: due, noreply: true, status: .pending, source: "received")
        save()
        EngineLog.write("tagged", ["account": mail.account, "id": mail.messageId, "due": ISO8601DateFormatter().string(from: due), "noreply": true,
                                   "source": "received", "subject_chars": mail.subject.count])
    }

    // MARK: menu actions (clear marks by hand)

    /// Clears the marks of the returned mails that are selected in Mail right now. Returns how many.
    func clearSelected() -> Int {
        lock.lock(); defer { lock.unlock() }
        let returned = state.entries.values.filter { $0.status == .returned }
        guard !returned.isEmpty else { return 0 }
        do {
            let byMark = Dictionary(returned.map { ($0.markKey, $0.messageId) }, uniquingKeysWith: { first, _ in first })
            let out = try run("unmark-selection", returned.map(\.markKey))
            var n = 0
            for markKey in out.split(separator: "\n").map(String.init) {
                guard let id = byMark[markKey], var e = state.entries[id] else { continue }
                e.status = .cleared; state.entries[id] = e; n += 1
                EngineLog.write("unmarked", ["id": id, "reason": "cleared from the menu (selected mail)"])
            }
            save(); return n
        } catch { EngineLog.write("error", ["step": "unmark-selection", "error": "\(error)"]); return 0 }
    }

    /// Menu: clears the junk status of the mails selected in Mail (moving them out of Junk/Bulk/Spam). Returns how many.
    func markSelectedNotJunk() -> Int {
        lock.lock(); defer { lock.unlock() }
        do {
            let n = Int(try run("notjunk-selection", [])) ?? 0
            EngineLog.write("not-junk", ["count": n, "via": "menu"])
            return n
        } catch { EngineLog.write("error", ["step": "notjunk-selection", "error": "\(error)"]); return 0 }
    }

    /// Clears the marks of every returned mail. Returns how many.
    func clearAll() -> Int {
        lock.lock(); defer { lock.unlock() }
        var n = 0
        for var e in state.entries.values where e.status == .returned {
            do {
                _ = try run("unmark", [e.account, e.markKey])
                e.status = .cleared; state.entries[e.messageId] = e; n += 1
                EngineLog.write("unmarked", ["id": e.messageId, "reason": "cleared from the menu (all)"])
            } catch { EngineLog.write("error", ["step": "unmark", "error": "\(error)"]) }
        }
        save(); return n
    }

    static func notify(_ text: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv\ndisplay notification (item 1 of argv) with title \"FlyByMail\"\nend run", text]
        try? p.run()
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
