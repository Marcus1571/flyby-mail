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

// MARK: model

enum Choice: Equatable {
    case none
    case preset(Preset)
    case custom(Date)
}

struct Pick {
    var choice: Choice
    var onlyIfNoReply: Bool
    func due(now: Date = Date()) -> Date? {
        switch choice {
        case .none: return nil
        case .preset(let p): return p.date(from: now)
        case .custom(let d): return d
        }
    }
}

/// The ten times of the Gmail pop-up, in the same order, plus a short test time (remove before release).
enum Preset: String, CaseIterable, Identifiable {
    case hour1, hours2, hours4, tomorrowMorning, tomorrowAfternoon, days2, days4, week1, weeks2, month1, test2min
    var id: String { rawValue }

    static let main: [Preset] = [.hour1, .hours2, .hours4, .tomorrowMorning, .tomorrowAfternoon, .days2, .days4, .week1, .weeks2, .month1]

    var title: String {
        switch self {
        case .hour1: return "In 1 hour"
        case .hours2: return "In 2 hours"
        case .hours4: return "In 4 hours"
        case .tomorrowMorning: return "Tomorrow morning"
        case .tomorrowAfternoon: return "Tomorrow afternoon"
        case .days2: return "In 2 days"
        case .days4: return "In 4 days"
        case .week1: return "In 1 week"
        case .weeks2: return "In 2 weeks"
        case .month1: return "In 1 month"
        case .test2min: return "In 2 minutes (test)"
        }
    }

    func date(from now: Date) -> Date {
        let cal = Calendar.current
        func tomorrow(at hour: Int) -> Date {
            let t = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: t)!
        }
        switch self {
        case .hour1: return now.addingTimeInterval(3600)
        case .hours2: return now.addingTimeInterval(2 * 3600)
        case .hours4: return now.addingTimeInterval(4 * 3600)
        case .tomorrowMorning: return tomorrow(at: 8)
        case .tomorrowAfternoon: return tomorrow(at: 14)
        case .days2: return cal.date(byAdding: .day, value: 2, to: now)!
        case .days4: return cal.date(byAdding: .day, value: 4, to: now)!
        case .week1: return cal.date(byAdding: .day, value: 7, to: now)!
        case .weeks2: return cal.date(byAdding: .day, value: 14, to: now)!
        case .month1: return cal.date(byAdding: .month, value: 1, to: now)!
        case .test2min: return now.addingTimeInterval(120)
        }
    }
}

/// "14:05" when it is today, "Thu 20 Nov, 08:00" otherwise.
func friendly(_ date: Date, now: Date = Date()) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
}

final class PickerModel: ObservableObject {
    @Published var choice: Choice = .none { didSet { changed() } }
    @Published var onlyIfNoReply = true { didSet { changed() } }
    @Published var customDate = Date().addingTimeInterval(86400)
    var onChange: ((Pick) -> Void)?
    private func changed() { onChange?(Pick(choice: choice, onlyIfNoReply: onlyIfNoReply)) }

    var summary: String {
        guard let due = Pick(choice: choice, onlyIfNoReply: onlyIfNoReply).due() else { return "No reminder: nothing is added to this mail" }
        return (onlyIfNoReply ? "Comes back " : "Comes back, whatever happens, ") + friendly(due)
    }
}

// MARK: view

struct PickerView: View {
    @ObservedObject var model: PickerModel
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "airplane.departure").foregroundStyle(.orange).imageScale(.large)
                Text("Bring this mail back").font(.headline)
                Spacer()
                if model.choice != .none { Button("Clear") { model.choice = .none }.buttonStyle(.link) }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Preset.main) { preset in
                    PresetButton(preset: preset, selected: model.choice == .preset(preset)) { model.choice = .preset(preset) }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Or pick a date and time").font(.subheadline).foregroundStyle(.secondary)
                DatePicker("Date and time", selection: Binding(get: { model.customDate }, set: { model.customDate = $0; model.choice = .custom($0) }),
                           in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            Toggle(isOn: $model.onlyIfNoReply) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Only if nobody replies")
                    Text("Off: it comes back even if someone answered").font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            HStack(spacing: 6) {
                Image(systemName: model.choice == .none ? "clock.badge.xmark" : "clock").foregroundStyle(.secondary)
                Text(model.summary).font(.callout).foregroundStyle(model.choice == .none ? .secondary : .primary)
            }
            .accessibilityElement(children: .combine)

            Button("Test: in 2 minutes") { model.choice = .preset(.test2min) }   // TODO remove before release
                .buttonStyle(.link).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct PresetButton: View {
    let preset: Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(preset.title).font(.system(size: 12, weight: .medium))
                Text(friendly(preset.date(from: Date()))).font(.system(size: 10)).opacity(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .orange : nil)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.orange : Color.clear, lineWidth: 1.5))
        .accessibilityLabel("\(preset.title), \(friendly(preset.date(from: Date())))")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            model.onlyIfNoReply = pick.onlyIfNoReply
            if case .custom(let d) = pick.choice { model.customDate = d }
        }
        let sessionID = session.sessionID
        model.onChange = { [weak handler] pick in
            handler?.picks[sessionID] = pick
            log.info("picked choice=\(String(describing: pick.choice), privacy: .public) noreply=\(pick.onlyIfNoReply) session=\(sessionID.uuidString, privacy: .public)")
        }
        let host = NSHostingView(rootView: PickerView(model: model))
        view = host
        preferredContentSize = host.fittingSize
    }
}
