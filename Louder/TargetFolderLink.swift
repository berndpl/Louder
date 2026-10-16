import AppKit
import SwiftUI

enum TargetFolderPicker {
    static func choose(currentPath: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the target folder for relocated files."
        if !currentPath.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (currentPath as NSString).expandingTildeInPath,
                isDirectory: true
            )
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}

struct TargetFolderLink: View {
    @Binding var path: String
    @State private var isPresented = false
    @State private var showRevealError = false

    private var displayPath: String {
        path.isEmpty ? "No folder chosen" : (path as NSString).abbreviatingWithTildeInPath
    }

    private var folderName: String {
        guard !path.isEmpty else { return "target folder" }
        let expandedPath = (path as NSString).expandingTildeInPath
        let name = URL(fileURLWithPath: expandedPath, isDirectory: true).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Text(folderName)
                .underline()
                .truncationMode(.middle)
        }
        .buttonStyle(.link)
        .help(path.isEmpty ? "Choose a target folder" : displayPath)
        .accessibilityLabel("Target folder")
        .accessibilityValue(displayPath)
        .accessibilityHint("Shows the current folder and options to reveal or change it")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Target folder")
                    .font(.headline)
                Text(displayPath)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !path.isEmpty {
                        Button("Show in Finder") {
                            let expandedPath = (path as NSString).expandingTildeInPath
                            if NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expandedPath) {
                                isPresented = false
                            } else {
                                showRevealError = true
                            }
                        }
                    }
                    Button(path.isEmpty ? "Choose Folder…" : "Change Folder…") {
                        isPresented = false
                        if let selectedPath = TargetFolderPicker.choose(currentPath: path) {
                            path = selectedPath
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .alert("Could not show target folder", isPresented: $showRevealError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The folder may have been moved or is unavailable. Choose another target folder.")
            }
        }
    }
}
