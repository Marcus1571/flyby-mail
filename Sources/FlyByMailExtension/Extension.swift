import AppKit
import MailKit
import os

// Spike 1: does a Developer ID-signed Mail extension load, show a Compose button, and stamp a header?
private let log = Logger(subsystem: "app.legba.flybymail", category: "compose")

@objc(FlyByExtension)
final class FlyByExtension: NSObject, MEExtension {
    func handler(for session: MEComposeSession) -> MEComposeSessionHandler { ComposeHandler.shared }
}

final class ComposeHandler: NSObject, MEComposeSessionHandler {
    static let shared = ComposeHandler()
    /// What the user picked, per compose window. Resolved to a due time only when the header is requested (at send).
    var picks: [UUID: Pick] = [:]

    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        log.info("compose begin session=\(session.sessionID.uuidString, privacy: .public)")
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        log.info("compose end session=\(session.sessionID.uuidString, privacy: .public) hadPick=\(self.picks[session.sessionID] != nil)")
        picks[session.sessionID] = nil
    }

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        log.info("view requested session=\(session.sessionID.uuidString, privacy: .public)")
        return PickerViewController(session: session, handler: self)
    }

    func additionalHeaders(for session: MEComposeSession) -> [String: [String]] {
        guard let pick = picks[session.sessionID], let due = pick.due() else {
            log.info("headers: none session=\(session.sessionID.uuidString, privacy: .public)")
            return [:]
        }
        let value = "v=1; due=\(Int(due.timeIntervalSince1970)); noreply=\(pick.onlyIfNoReply ? 1 : 0)"
        log.info("headers: X-FlyBy: \(value, privacy: .public) session=\(session.sessionID.uuidString, privacy: .public)")
        return ["X-FlyBy": [value]]
    }
}

struct Pick {
    var preset: Preset
    var onlyIfNoReply: Bool
    func due() -> Date? { preset.date(from: Date()) }
}

enum Preset: Int, CaseIterable {
    case none, minutes2, hour1, hours4, tomorrow8, days2, week1

    var title: String {
        switch self {
        case .none: return "No reminder"
        case .minutes2: return "In 2 minutes (test)"
        case .hour1: return "In 1 hour"
        case .hours4: return "In 4 hours"
        case .tomorrow8: return "Tomorrow morning, 08:00"
        case .days2: return "In 2 days"
        case .week1: return "In 1 week"
        }
    }

    func date(from now: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .none: return nil
        case .minutes2: return now.addingTimeInterval(120)
        case .hour1: return now.addingTimeInterval(3600)
        case .hours4: return now.addingTimeInterval(4 * 3600)
        case .tomorrow8:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
        case .days2: return now.addingTimeInterval(2 * 86400)
        case .week1: return now.addingTimeInterval(7 * 86400)
        }
    }
}

final class PickerViewController: MEExtensionViewController {
    private let session: MEComposeSession
    private let handler: ComposeHandler
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let check = NSButton(checkboxWithTitle: "Only if nobody replies", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")

    init(session: MEComposeSession, handler: ComposeHandler) {
        self.session = session
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        popup.addItems(withTitles: Preset.allCases.map(\.title))
        check.state = .on
        for control in [popup, check] as [NSControl] { control.target = self; control.action = #selector(changed) }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let title = NSTextField(labelWithString: "Bring this mail back")
        title.font = .boldSystemFont(ofSize: 13)
        let stack = NSStackView(views: [title, popup, check, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        view = stack
        preferredContentSize = NSSize(width: 260, height: 130)

        // Come back to a choice made earlier in this same compose window.
        if let pick = handler.picks[session.sessionID] {
            popup.selectItem(at: pick.preset.rawValue)
            check.state = pick.onlyIfNoReply ? .on : .off
        }
        refreshStatus()
    }

    @objc private func changed() {
        let preset = Preset(rawValue: popup.indexOfSelectedItem) ?? .none
        handler.picks[session.sessionID] = Pick(preset: preset, onlyIfNoReply: check.state == .on)
        refreshStatus()
    }

    private func refreshStatus() {
        let preset = Preset(rawValue: popup.indexOfSelectedItem) ?? .none
        if let due = preset.date(from: Date()) {
            status.stringValue = "Returns " + due.formatted(date: .abbreviated, time: .shortened)
        } else {
            status.stringValue = "Nothing will be added to this mail"
        }
    }
}
