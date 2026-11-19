import AppKit
import ServiceManagement
import SwiftUI

// Host app = the engine's home: a menu-bar app that checks Mail every 5 minutes (and carries the Mail extension).

extension Engine: @unchecked Sendable {}

@MainActor
final class AppModel: ObservableObject {
    let engine = Engine()
    @Published var lastCheck: Date?
    @Published var pending = 0
    @Published var returned = 0
    @Published var lastError: String?
    @Published var busy = false
    private var timer: Timer?

    init() {
        pending = engine.pendingCount
        returned = engine.returnedCount
        EngineLog.write("app-start", ["pending": pending, "returned": returned])
        Task { await checkNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkNow() }
        }
    }

    func checkNow() async {
        guard !busy else { return }
        busy = true
        let engine = self.engine
        let report = await Task.detached(priority: .utility) { engine.tick() }.value
        pending = engine.pendingCount
        returned = engine.returnedCount
        lastCheck = Date()
        lastError = report.errors.first
        busy = false
    }
}

@main
struct FlyByMailApp: App {
    @StateObject private var model = AppModel()

    private static let icon: NSImage = {
        let image = NSImage(named: "FlyByTemplate") ?? NSImage(systemSymbolName: "airplane.departure", accessibilityDescription: "FlyBy")!
        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: Self.icon)
        }
        Window("FlyBy for Mail", id: "welcome") { WelcomeView() }
            .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(model.pending == 0 ? "No mail waiting to come back" : "Watching \(model.pending) mail\(model.pending == 1 ? "" : "s")")
        if model.returned > 0 { Text("\(model.returned) returned, marked orange in your Inbox") }
        if let last = model.lastCheck { Text("Last check \(last.formatted(date: .omitted, time: .shortened))") }
        if let error = model.lastError { Text("⚠︎ \(error)").lineLimit(2) }
        Divider()
        Button(model.busy ? "Checking…" : "Check now") { Task { await model.checkNow() } }
            .keyboardShortcut("r").disabled(model.busy)
        Toggle("Open at login", isOn: $atLogin)
            .onChange(of: atLogin) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { EngineLog.write("login-item-failed", ["error": "\(error)"]); atLogin = SMAppService.mainApp.status == .enabled }
            }
        Button("Show log") { NSWorkspace.shared.open(EngineLog.file) }
        Button("Welcome…") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "welcome") }
        Divider()
        Button("Quit FlyBy") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FlyBy for Apple Mail").font(.title2.bold())
            Text("Bring a mail back to your Inbox when nobody has answered.").foregroundStyle(.secondary)
            Divider()
            step("1", "Turn the extension on", "Mail ▸ Settings ▸ Extensions ▸ tick “FlyBy”.")
            step("2", "Allow FlyBy to control Mail", "macOS asks once. It is how FlyBy finds your sent mails and brings them back, no password needed.")
            step("3", "Write a mail as usual", "Click the airplane in the toolbar of the new message and pick when it should come back.")
            Divider()
            Text("FlyBy lives in the menu bar. A returned mail has an orange flag and an orange background.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 480)
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).frame(width: 24, height: 24).background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary) }
        }
    }
}
