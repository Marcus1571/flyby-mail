import SwiftUI

// Host app: only exists to carry the Mail extension. Mail lists the extension under Settings > Extensions
// once this app has been opened at least once from /Applications.
@main
struct FlyByMailApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FlyBy for Apple Mail").font(.title2.bold())
            Text("Spike 1: a button in Mail's Compose window that stamps an X-FlyBy header on the message.")
                .foregroundStyle(.secondary)
            Divider()
            Text("1. Open Mail ▸ Settings ▸ Extensions")
            Text("2. Tick “FlyBy”")
            Text("3. Write a new message: a FlyBy button appears in the Compose toolbar")
        }
        .padding(28)
        .frame(width: 460)
    }
}
