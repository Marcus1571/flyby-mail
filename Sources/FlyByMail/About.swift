import AppKit
import SwiftUI

/// The About window, the same mini page as UsageBar and NeverSleep: icon, version, a PayPal donation card (QR + tiers + link),
/// a bug-report card, license and code, and a one-line tagline.
struct AboutView: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityLabel("FlyBy for Mail app icon")
                VStack(alignment: .leading, spacing: 3) {
                    Text("FlyBy for Mail").font(.title2).fontWeight(.bold)
                    Text("Version \(version) (build \(build))").font(.subheadline).foregroundColor(.secondary)
                }
            }
            supportCard
            bugCard
            licenseCard
            Divider()
            Text("Bring a mail back to your Inbox when nobody has answered. Pick a time in Apple Mail's compose window; FlyBy does the rest.")
                .font(.footnote).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 300)
    }

    /// Card builder: badge + bold title on top, content below, soft rounded background (same pattern as the sibling apps).
    private func card(badge: String, tint: Color, title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: badge).foregroundColor(tint)
                Text(title).font(.headline)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private var supportCard: some View {
        card(badge: "heart.fill", tint: .blue, title: "Support FlyBy") {
            VStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "paypal-qr", withExtension: "png"), let qr = NSImage(contentsOf: url) {
                    Image(nsImage: qr).resizable().interpolation(.high).frame(width: 88, height: 88)
                        .accessibilityLabel("PayPal donation QR code")
                }
                HStack(spacing: 8) {
                    tierLink("☕️", "€1", "1eur")
                    tierLink("🍔", "€5", "5eur")
                    tierLink("🍣", "€10", "10eur")
                }
                Link("paypal.me/marcodalmoro", destination: URL(string: "https://paypal.me/marcodalmoro")!).font(.caption)
                Text("Scan the code, tap the link, or pick a coffee — a coffee (€1), a burger (€5), a sushi night (€10). Thank you!")
                    .font(.caption2).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var bugCard: some View {
        card(badge: "ladybug.fill", tint: .orange, title: "Report a Bug") {
            Link("github.com/Marcus1571/flyby-mail/issues", destination: URL(string: "https://github.com/Marcus1571/flyby-mail/issues")!).font(.caption)
        }
    }

    private var licenseCard: some View {
        card(badge: "doc.text", tint: .gray, title: "License & code") {
            VStack(alignment: .leading, spacing: 5) {
                Text("© 2026 Marcus1571").font(.caption)
                Text("MIT").font(.caption2).foregroundColor(.secondary)
                Link("github.com/Marcus1571/flyby-mail", destination: URL(string: "https://github.com/Marcus1571/flyby-mail")!).font(.caption)
            }
        }
    }

    private func tierLink(_ emoji: String, _ amount: String, _ path: String) -> some View {
        Link(destination: URL(string: "https://paypal.me/marcodalmoro/\(path)")!) {
            VStack(spacing: 2) {
                Text(emoji).font(.system(size: 17))
                Text(amount).font(.caption).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Color(red: 0.0, green: 0.41, blue: 0.77), in: RoundedRectangle(cornerRadius: 9))
            .foregroundColor(.white)
        }
        .accessibilityLabel("Donate \(amount) via PayPal")
    }
}
