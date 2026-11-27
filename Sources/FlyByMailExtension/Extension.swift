import AppKit
import MailKit
import os
import SwiftUI

// Compose-window extension: the FlyBy button opens a native picker; at send time the choice becomes an X-FlyBy header.
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

    /// Tells the menu-bar app what the user picked in this compose window (nothing picked = due 0). Test of the extension->app channel.
    func announce(_ sessionID: UUID, _ pick: Pick?) {
        let due = pick?.due()?.timeIntervalSince1970 ?? 0
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("app.legba.flybymail.pick"), object: nil,
            userInfo: ["session": sessionID.uuidString, "due": due, "noreply": true],
            deliverImmediately: true)
        log.info("announced due=\(due) session=\(sessionID.uuidString, privacy: .public)")
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        announce(session.sessionID, nil)
        log.info("compose end session=\(session.sessionID.uuidString, privacy: .public) hadPick=\(self.picks[session.sessionID] != nil)")
        picks[session.sessionID] = nil
    }

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        log.info("view requested session=\(session.sessionID.uuidString, privacy: .public)")
        return PickerViewController(session: session, handler: self)
    }

    func annotateAddressesForSession(_ session: MEComposeSession, completion: @escaping ([MEEmailAddress: MEAddressAnnotation]) -> Void) {
        guard let pick = picks[session.sessionID], let due = pick.due() else { completion([:]); return }
        let text = "FlyBy: comes back \(friendly(due)) if nobody replies"
        let note = MEAddressAnnotation.success(withLocalizedDescription: text)
        var map: [MEEmailAddress: MEAddressAnnotation] = [:]
        let message = session.mailMessage
        for address in message.toAddresses + message.ccAddresses { map[address] = note }
        log.info("annotate: \(map.count) recipient(s) '\(text, privacy: .public)' session=\(session.sessionID.uuidString, privacy: .public)")
        completion(map)
    }

    func additionalHeaders(for session: MEComposeSession) -> [String: [String]] {
        guard let pick = picks[session.sessionID], let due = pick.due() else {
            log.info("headers: none session=\(session.sessionID.uuidString, privacy: .public)")
            return [:]
        }
        let value = "v=1; due=\(Int(due.timeIntervalSince1970)); noreply=1"
        log.info("headers: X-FlyBy: \(value, privacy: .public) session=\(session.sessionID.uuidString, privacy: .public)")
        return ["X-FlyBy": [value]]
    }
}

final class PickerViewController: MEExtensionViewController {
    private let session: MEComposeSession
    private let handler: ComposeHandler
    private let model = PickerModel()

    init(session: MEComposeSession, handler: ComposeHandler) {
        self.session = session
        self.handler = handler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        // Come back to a choice made earlier in this same compose window.
        if let pick = handler.picks[session.sessionID] {
            model.choice = pick.choice
            if case .custom(let d) = pick.choice { model.customDate = d }
        }
        let sessionID = session.sessionID
        let session = self.session
        model.onChange = { [weak handler] choice in
            let pick = Pick(choice: choice)
            handler?.picks[sessionID] = pick
            handler?.announce(sessionID, pick)
            log.info("picked choice=\(String(describing: pick.choice), privacy: .public) session=\(sessionID.uuidString, privacy: .public)")
            if pick.choice != .none { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
            session.reload()   // asks Mail to redraw the recipient annotation
        }
        let host = NSHostingView(rootView: PickerView(model: model, hint: "All set. Click anywhere outside to close."))
        view = host
        preferredContentSize = host.fittingSize
    }
}
