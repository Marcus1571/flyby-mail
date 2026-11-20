import AppKit
import ServiceManagement
import SwiftUI
#if SPARKLE
import Sparkle
#endif

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
    private var quickRetry: Task<Void, Never>?

    init() {
        pending = engine.pendingCount
        returned = engine.returnedCount
        EngineLog.write("app-start", ["pending": pending, "returned": returned])
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.legba.flybymail.pick"), object: nil, queue: .main) { note in
            EngineLog.write("ext-pick", ["info": note.userInfo.map { "\($0)" } ?? "(no userInfo)"])
        }
        Task { await checkNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkNow() }
        }
    }

    func clearSelected() async {
        let engine = self.engine
        _ = await Task.detached(priority: .utility) { engine.clearSelected() }.value
        returned = engine.returnedCount
    }

    func markNotJunk() async {
        let engine = self.engine
        _ = await Task.detached(priority: .utility) { engine.markSelectedNotJunk() }.value
    }

    func clearAll() async {
        let engine = self.engine
        _ = await Task.detached(priority: .utility) { engine.clearAll() }.value
        returned = engine.returnedCount
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
        // A reminder that has been sent but has not reached the inbox yet (Yahoo can take minutes): look again in 30 s instead of waiting 5 minutes.
        quickRetry?.cancel()
        if engine.marksPendingCount > 0 {
            quickRetry = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if !Task.isCancelled { await self?.checkNow() }
            }
        }
    }
}

@main
struct FlyByMailApp: App {
    @StateObject private var model = AppModel()
    #if SPARKLE
    // Only the packaged build carries Sparkle; it checks the appcast daily (Info.plist) and installs updates itself.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    private static let icon: NSImage = {
        let image = NSImage(named: "FlyByTemplate") ?? NSImage(systemSymbolName: "airplane.departure", accessibilityDescription: "FlyBy")!
        image.isTemplate = true
        return image
    }()

    init() {
        // Self-check for the About page's look: `FlyByMail --snapshot-about <dir>` writes about-light.png and about-dark.png and exits.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-about"), CommandLine.arguments.count > i + 1 {
            let dir = CommandLine.arguments[i + 1]
            _ = NSApplication.shared
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                // A real hosting view in an offscreen window: ImageRenderer cannot draw SwiftUI Links.
                let host = NSHostingView(rootView: AboutView())
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/about-\(name).png"))
                }
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            #if SPARKLE
            MenuView(model: model, checkForUpdates: { updater.checkForUpdates(nil) })
            #else
            MenuView(model: model, checkForUpdates: nil)
            #endif
        } label: {
            Image(nsImage: Self.icon)
        }
        Window("FlyBy for Mail", id: "welcome") { WelcomeView() }
            .windowResizability(.contentSize)
        Window("About FlyBy", id: "about") { AboutView() }
            .windowResizability(.contentSize)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    let checkForUpdates: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(model.pending == 0 ? "No mail waiting to come back" : "Watching \(model.pending) mail\(model.pending == 1 ? "" : "s")")
        if model.returned > 0 { Text("\(model.returned) returned, marked orange in your Inbox") }
        if let last = model.lastCheck { Text("Last check \(last.formatted(date: .omitted, time: .shortened))") }
        if let error = model.lastError { Text("⚠︎ \(error)").lineLimit(2) }
        Button("Mark selected mail as Not Junk") { Task { await model.markNotJunk() } }
        Divider()
        Button(model.busy ? "Checking…" : "Check now") { Task { await model.checkNow() } }
            .keyboardShortcut("r").disabled(model.busy)
        Button("Clear marks on selected mail") { Task { await model.clearSelected() } }.disabled(model.returned == 0)
        Button("Clear marks on all returned mails (\(model.returned))") { Task { await model.clearAll() } }.disabled(model.returned == 0)
        Divider()
        Toggle("Open at login", isOn: $atLogin)
            .onChange(of: atLogin) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { EngineLog.write("login-item-failed", ["error": "\(error)"]); atLogin = SMAppService.mainApp.status == .enabled }
            }
        Button("Show log") { NSWorkspace.shared.open(EngineLog.file) }
        if let checkForUpdates { Button("Check for Updates…", action: checkForUpdates) }
        Button("About FlyBy…") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "about") }
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
