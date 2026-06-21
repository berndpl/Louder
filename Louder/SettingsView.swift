import SwiftUI

struct SettingsView: View {
    @AppStorage(AudioFades.preferenceKey) private var addFades = true
    @AppStorage(RenameOriginal.preferenceKey) private var renameOriginal = true
    @AppStorage(TrimSilence.preferenceKey) private var trimSilence = false

    var body: some View {
        Form {
            Toggle("Add 0.25-second fades", isOn: $addFades)
            Text("Adds a short natural fade at the beginning and end of processed audio.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Trim silence", isOn: $trimSilence)
            Text("Automatically removes dead air at the start and end of the clip. Pauses in the middle are left untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Rename original", isOn: $renameOriginal)
            Text("When on, the improved version takes the original file's name and the original is kept alongside it with “ - original” appended. When off, the original file is left untouched and improved versions are saved under new names.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360, height: 320)
    }
}
