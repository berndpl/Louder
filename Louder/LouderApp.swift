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
            SettingsView()
        }
    }
}
