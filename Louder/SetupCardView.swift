import AppKit
import SwiftUI

/// Idle-screen onboarding shown when the required command-line tools are not yet
/// installed. It detects what is missing, hands the user the exact commands to
/// run (Homebrew first when it is also absent), and offers one-tap Copy / Open
/// Terminal / Re-check so they never have to leave the app guessing.
struct SetupCardView: View {
    let status: FFmpeg.ToolchainStatus
    let onRecheck: () -> Void

    private static let homebrewInstall =
        "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    private static let ffmpegInstall = "brew install ffmpeg"

    /// Ordered setup steps, tailored to what is already present.
    private var steps: [SetupStep] {
        var result: [SetupStep] = []
        if !status.homebrew {
            result.append(SetupStep(
                title: "Install Homebrew",
                detail: "The package manager Louder uses to fetch ffmpeg.",
                command: Self.homebrewInstall
            ))
        }
        result.append(SetupStep(
            title: "Install ffmpeg",
            detail: "The audio engine that powers every preset.",
            command: Self.ffmpegInstall
        ))
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("One quick setup step")
                    .font(.headline)
                Text("Louder needs ffmpeg to process audio. Run the command\(steps.count > 1 ? "s" : "") below, then re-check.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    SetupStepRow(index: index + 1, step: step, numbered: steps.count > 1)
                }
            }

            HStack(spacing: 10) {
                Button {
                    openTerminal()
                } label: {
                    Label("Open Terminal", systemImage: "terminal")
                }
                Button {
                    onRecheck()
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            .controlSize(.regular)

            Text("Louder looks in /opt/homebrew/bin and /usr/local/bin.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator, lineWidth: 1)
        )
    }

    private func openTerminal() {
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminalURL, configuration: .init())
    }
}

private struct SetupStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let command: String
}

private struct SetupStepRow: View {
    let index: Int
    let step: SetupStep
    let numbered: Bool
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if numbered {
                    Text("\(index).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(step.command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy command")
                .accessibilityLabel(copied ? "Copied" : "Copy command")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(.quaternary.opacity(0.5))
            )
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(step.command, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { copied = false }
        }
    }
}
