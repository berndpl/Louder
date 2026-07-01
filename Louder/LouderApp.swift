//
//  LouderApp.swift
//  Louder
//
//  Created by Bernd Plontsch on 12.06.26.
//

import SwiftUI

@main
struct LouderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The drop window is managed by AppDelegate so Dock drops and reopen
        // behave correctly; no SwiftUI window scene is needed.
        Settings {
            TabView {
                FilesSettingsView()
                    .tabItem { Label("Files", systemImage: "folder") }
                ProcessingSettingsView()
                    .tabItem { Label("Processing", systemImage: "waveform") }
            }
            .frame(width: 460)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Louder") {
                    BuildInfo.showAboutPanel()
                }
            }
        }
    }
}
