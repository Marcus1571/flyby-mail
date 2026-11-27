#!/bin/bash
# Runnable check for the engine's flood protection (no Mail needed): swiftc builds Engine.swift with a tiny main and asserts.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/main.swift" <<'SWIFT'
import Foundation
let now = Date()
func ago(_ s: Double) -> Date { now.addingTimeInterval(-s) }
// first seen long after its due time (the Macai case: up to 4 days late): never returned
assert(Engine.isExpiredOnFirstSight(due: ago(340_080), now: now))
assert(Engine.isExpiredOnFirstSight(due: ago(601), now: now))
// within the grace (Mac slept through a tick), due now, or still in the future: kept
assert(!Engine.isExpiredOnFirstSight(due: ago(599), now: now))
assert(!Engine.isExpiredOnFirstSight(due: now, now: now))
assert(!Engine.isExpiredOnFirstSight(due: now.addingTimeInterval(3600), now: now))
assert(Engine.maxReturnsPerTick == 3)
assert(Engine.parseTag("v=1; due=1795089346; noreply=1")?.noreply == true)
if let expect = CommandLine.arguments.dropFirst().first {   // round trip against the real backend/server.py
    let r = Backend.claim(messageId: "check-message-id@example.invalid")
    switch (expect, r) {
    case ("won", .won), ("lost", .lost("mac")), ("down", .unavailable), ("done", .done("mac")): break
    default: fatalError("backend: expected \(expect), got \(r)")
    }
    if expect == "won" { assert(Backend.finish(messageId: "check-message-id@example.invalid") == .won) }   // the holder reports it sent
}
assert(Backend.claim(messageId: "x") == .notConfigured || ProcessInfo.processInfo.environment["FLYBY_BACKEND_URL"] != nil)
print("engine checks ok")
SWIFT
swiftc -o "$T/check" Sources/FlyByMail/Engine.swift "$T/main.swift" 2>&1 | grep -v warning || true
"$T/check"
# backend round trip: the first device wins and reports it sent, a second sees "done by mac", an unreachable service is "unavailable"
FLYBY_KEYS="mac=$(printf k1 | shasum -a 256 | cut -d' ' -f1),macai=$(printf k2 | shasum -a 256 | cut -d' ' -f1)" FLYBY_DB="$T/c.db" PORT=18787 python3 backend/server.py >/dev/null 2>&1 &
SRV=$!; trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT; sleep 1
FLYBY_BACKEND_URL=http://127.0.0.1:18787 FLYBY_BACKEND_KEY=k1 "$T/check" won
FLYBY_BACKEND_URL=http://127.0.0.1:18787 FLYBY_BACKEND_KEY=k2 "$T/check" done   # mac finished it: macai drops it (was: lost, then won after 10 min)
FLYBY_BACKEND_URL=http://127.0.0.1:1 FLYBY_BACKEND_KEY=k1 "$T/check" down
