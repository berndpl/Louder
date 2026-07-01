import SwiftUI
import AppKit

/// "Files" settings tab: everything that happens to the file itself before and
/// around processing — relocating it into a target folder, renaming it to a
/// convention, and how the original is kept.
struct FilesSettingsView: View {
    @AppStorage(MoveToFolder.preferenceKey) private var moveToFolder = false
    @AppStorage(TargetFolder.preferenceKey) private var targetFolderPath = ""
    @AppStorage(RelocationMode.preferenceKey) private var relocationModeRaw = RelocationMode.move.rawValue
    @AppStorage(RenameFile.preferenceKey) private var renameFile = false
    @AppStorage(RenameBody.preferenceKey) private var renameBody = ""
    @AppStorage(AppendDate.preferenceKey) private var appendDate = false
    @AppStorage(RenameOriginal.preferenceKey) private var renameOriginal = true

    private var relocationMode: Binding<RelocationMode> {
        Binding(
            get: { RelocationMode(rawValue: relocationModeRaw) ?? .move },
            set: { relocationModeRaw = $0.rawValue }
        )
    }

    private var previewName: String {
        let body = renameFile
            ? (renameBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "MyRecording"
                : renameBody.trimmingCharacters(in: .whitespacesAndNewlines))
            : "MyRecording"
        let date = appendDate ? " \(AppendDate.formatter.string(from: Date()))" : ""
        return "\(body)\(date)"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Move to target folder", isOn: $moveToFolder)

                HStack {
                    Text("Folder")
                    Spacer()
                    Text(displayFolder)
                        .foregroundStyle(targetFolderPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button("Choose…") { chooseFolder() }
                }
                .disabled(!moveToFolder)

                Picker("On relocation", selection: relocationMode) {
                    ForEach(RelocationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!moveToFolder)
            } header: {
                Text("Target folder")
            }

            Section {
                Toggle("Rename file", isOn: $renameFile)
                TextField("Body", text: $renameBody, prompt: Text("MyRecording"))
                    .disabled(!moveToFolder || !renameFile)

                Toggle("Append date", isOn: $appendDate)
                    .disabled(!moveToFolder)

                if moveToFolder && (renameFile || appendDate) {
                    LabeledContent("Preview", value: previewName)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Filename")
            }

            Section {
                Toggle("Rename original", isOn: $renameOriginal)
                Text("When on, the improved version takes the original file's name and the original is kept alongside it with “ - original” appended. When off, the original file is left untouched and improved versions are saved under new names.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Original")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Files")
        .frame(minHeight: 420)
    }

    private var displayFolder: String {
        guard !targetFolderPath.isEmpty else { return "None chosen" }
        return (targetFolderPath as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if !targetFolderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (targetFolderPath as NSString).expandingTildeInPath)
        }
        if panel.runModal() == .OK, let url = panel.url {
            targetFolderPath = url.path
        }
    }
}

/// "Processing" settings tab: how the audio is transformed.
struct ProcessingSettingsView: View {
    @AppStorage(AudioFades.preferenceKey) private var addFades = true
    @AppStorage(TrimSilence.preferenceKey) private var trimSilence = false

    var body: some View {
        Form {
            Section {
                Toggle("Add 0.25-second fades", isOn: $addFades)
                Text("Adds a short natural fade at the beginning and end of processed audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Trim silence", isOn: $trimSilence)
                Text("Automatically removes dead air at the start and end of the clip. Pauses in the middle are left untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Processing")
        .frame(minHeight: 260)
    }
}

#if DEBUG
#Preview("Files") { FilesSettingsView() }
#Preview("Processing") { ProcessingSettingsView() }
#endif
