import AppKit
import Carbon.HIToolbox
import SwiftUI

// "Remind me about this mail": the picker for a mail you SELECT in Mail (any folder, any conversation). Mail has no toolbar API, so it opens from the
// menu-bar item or the global shortcut ⌃⌘R. It is the same picker as the compose popover, in a panel that closes itself after the pick.

@MainActor
final class ReminderPanel {
    static let shared = ReminderPanel()
    var engine: Engine?
    private var panel: NSPanel?

    func show() {
        guard let engine else { return }
        panel?.close()
        Task.detached {
            let mail = engine.selectedMail()
            await MainActor.run { self.present(mail, engine) }
        }
    }

    private func present(_ mail: Engine.SelectedMail?, _ engine: Engine) {
        let content: AnyView
        if let mail {
            let model = PickerModel()
            // Opened again on a mail that already has a reminder: show where it stands (set before onChange is attached, so nothing is re-tracked).
            if let e = engine.entry(for: mail.messageId) {
                switch e.status {
                case .pending: model.choice = .custom(e.due)
                case .returned: model.note = PanelNote(symbol: "bell.fill", title: "The reminder came back", detail: "Returned \(friendly(e.returnedAt ?? e.due)). Pick a new time to be reminded again.")
                case .answered: model.note = PanelNote(symbol: "checkmark.bubble.fill", title: "Answered, no reminder needed", detail: e.answeredBy == "you" ? "You replied." : "\(e.answeredBy ?? "Someone") replied.")
                case .cleared: model.note = PanelNote(symbol: "xmark.circle.fill", title: "Reminder dismissed", detail: "Pick a time to start a new one.")
                }
            }
            model.onChange = { [weak self] choice in
                guard let due = Pick(choice: choice).due() else {
                    Task.detached { engine.cancel(mail.messageId) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.panel?.close() }
                    return
                }
                Task.detached { engine.track(mail, due: due) }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self?.panel?.close() }
            }
            let sender = mail.sender.split(separator: "<").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? mail.sender
            content = AnyView(PickerView(model: model, title: "Bring this back", subtitle: "\(mail.subject) · from \(sender)", commitCustom: true))
        } else {
            content = AnyView(NothingSelectedView())
        }
        let host = NSHostingView(rootView: content)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        p.title = "FlyBy"
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.contentView = host
        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }
}

struct NothingSelectedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "airplane.departure").font(.largeTitle).foregroundStyle(.orange)
            Text("Select a mail in Mail first").font(.headline)
            Text("Click a mail or conversation in Mail, then press ⌃⌘R again.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 320)
    }
}

/// A system-wide shortcut that needs no permission (Carbon hot keys are still the supported way for a menu-bar app).
final class HotKey {
    private var ref: EventHotKeyRef?
    nonisolated(unsafe) private static var action: (() -> Void)?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in HotKey.action?(); return noErr }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x464C4252, id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}
