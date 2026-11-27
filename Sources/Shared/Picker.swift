import SwiftUI

// The picker shared by the compose extension (popover in Mail) and the menu-bar app (own panel for a mail you select).

// MARK: model

enum Choice: Equatable {
    case none
    case preset(Preset)
    case custom(Date)
}

struct Pick {
    var choice: Choice
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
    if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
}

/// What happened to a reminder that is not pending any more (shown when the panel is opened again on the same mail).
struct PanelNote {
    var symbol: String
    var title: String
    var detail: String
}

final class PickerModel: ObservableObject {
    @Published var note: PanelNote?
    @Published var choice: Choice = .none { didSet { onChange?(choice) } }
    @Published var customDate = Date().addingTimeInterval(86400)
    var onChange: ((Choice) -> Void)?

    var isSet: Bool { choice != .none }
    var when: String { Pick(choice: choice).due().map { friendly($0) } ?? "" }
}

// MARK: view

struct PickerView: View {
    @ObservedObject var model: PickerModel
    var title = "Bring this mail back"
    var subtitle: String? = nil
    /// Compose popover: the date picker applies at once and a click outside closes the popover (Mail owns it).
    /// Own panel: the date picker only proposes, a button commits, and the panel closes itself.
    var commitCustom = false
    var hint: String? = nil
    @State private var draft = Date().addingTimeInterval(86400)
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "airplane.departure").foregroundStyle(.orange).imageScale(.large)
                Text(title).font(.headline)
                Spacer()
                if model.choice != .none { Button(commitCustom ? "Cancel reminder" : "Clear") { model.choice = .none }.buttonStyle(.link) }
            }
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Preset.main) { preset in
                    PresetButton(preset: preset, selected: model.choice == .preset(preset)) { model.choice = .preset(preset) }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Or pick a date and time").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    if commitCustom {
                        DatePicker("Date and time", selection: $draft, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact)
                        Spacer(minLength: 0)
                        Button("Set") { model.choice = .custom(draft) }.keyboardShortcut(.defaultAction)
                    } else {
                        DatePicker("Date and time", selection: Binding(get: { model.customDate }, set: { model.customDate = $0; model.choice = .custom($0) }),
                                   in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact)
                    }
                }
            }

            ConfirmationPanel(model: model, hint: hint)
        }
        .padding(16)
        .frame(width: 340)
    }
}

/// The user must always know where they stand: grey and quiet until a time is set, then a green framed confirmation
/// and an optional hint (the compose popover says that a click outside closes it: Mail owns it, no API closes it from inside).
struct ConfirmationPanel: View {
    @ObservedObject var model: PickerModel
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon).font(.system(size: 26)).foregroundStyle(model.isSet ? Color.green : (model.note != nil ? Color.orange : Color.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if model.isSet { Text("if nobody replies").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(model.isSet ? 0.14 : 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.isSet || model.note != nil ? tint : Color.secondary.opacity(0.3), lineWidth: model.isSet ? 1.5 : 1))
            .accessibilityElement(children: .combine)

            if model.isSet, let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isSet)
    }

    private var tint: Color { model.isSet ? .green : (model.note != nil ? .orange : .secondary) }
    private var icon: String { model.isSet ? "checkmark.circle.fill" : (model.note?.symbol ?? "circle.dashed") }
    private var title: String { model.isSet ? "Reminder set" : (model.note?.title ?? "No reminder yet") }
    private var line: String { model.isSet ? "Comes back \(model.when)" : (model.note?.detail ?? "Choose a time above") }
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

