//
//  BuildInfo.swift
//  Louder
//
//  Surfaces the version, build number, and the date/time this build was
//  produced, so you can tell at a glance whether you are running the latest
//  build. The build date is stamped into Info.plist by the "Stamp Build Date"
//  run-script build phase on every build.
//

import AppKit

enum BuildInfo {
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// ISO 8601 (UTC) string stamped at build time, e.g. `2026-06-14T08:41:03Z`.
    static var buildDateRaw: String? {
        guard let value = Bundle.main.infoDictionary?["BuildDate"] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var buildDate: Date? {
        guard let raw = buildDateRaw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Localized date + time in the user's timezone, e.g. `Jun 14, 2026 at 9:41 AM`.
    static var buildDateDisplay: String {
        guard let date = buildDate else { return "unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// e.g. `Version 1.1 (build 4)`.
    static var versionLine: String {
        "Version \(marketingVersion) (build \(buildNumber))"
    }

    /// e.g. `Version 1.1 (build 4) · Built Jun 14, 2026 at 9:41 AM`.
    static var summary: String {
        "\(versionLine) · Built \(buildDateDisplay)"
    }

    /// Shows the standard macOS About panel, enriched with the build date/time.
    @MainActor
    static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Built \(buildDateDisplay)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}
