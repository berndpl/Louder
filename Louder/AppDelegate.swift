import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    private static let resetItemIdentifier = NSToolbarItem.Identifier("Louder.Reset")

    let queue = DropQueue()
    let comparisonPlayer = ComparisonPlayer()
    private var window: NSWindow?
    private weak var toolbar: NSToolbar?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        queue.onAllDone = { [weak self] failures in
            self?.batchFinished(failures: failures)
        }
        queue.onStateChange = { [weak self] in self?.updateToolbar() }
        queue.onWillBeginBatch = { [weak self] in self?.comparisonPlayer.stop() }
        queue.onWillUndo = { [weak self] in self?.comparisonPlayer.stop() }
        showWindow()
        installPaletteShortcut()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        queue.enqueue(
            urls,
            preset: .persisted,
            compare: queue.compareMode,
            addFades: AudioFades.persisted,
            trimSilence: TrimSilence.persisted,
            renameOriginal: RenameOriginal.persisted,
            fileHandling: FileHandling.persisted,
            resolution: OutputResolution.persisted,
            stages: StudioBoothStages.all
        )
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return false
    }

    // Never quit while a file is processing.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        queue.isIdle ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        comparisonPlayer.stop()
    }

    // MARK: - Palette shortcuts

    /// Keyboard shortcuts for the OKLCH indicator palette used by the assessment
    /// cards: "P" cycles forward, and the ↑/↓ arrows step to the previous/next
    /// palette. Handled with a local event monitor so they work in the main
    /// window and the Settings picker alike, but never while typing in a field.
    private func installPaletteShortcut() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handlePaletteKey(event) else { return event }
            return nil
        }
    }

    private func handlePaletteKey(_ event: NSEvent) -> Bool {
        // Act in any Louder window (main window or Settings), but stay out of
        // the way whenever the user is typing in a text field.
        guard let keyWindow = NSApp.keyWindow else { return false }
        if keyWindow.firstResponder is NSText { return false }
        let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(modifiers).isEmpty else { return false }

        switch event.keyCode {
        case 126: // up arrow → previous palette
            IndicatorPalette.step(-1)
            return true
        case 125: // down arrow → next palette
            IndicatorPalette.step(1)
            return true
        default:
            break
        }

        guard event.charactersIgnoringModifiers?.lowercased() == "p" else { return false }
        IndicatorPalette.cycle()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        comparisonPlayer.stop()
    }

    private func batchFinished(failures: Int) {
        let total = queue.items.count
        let isComparison = queue.items.contains(where: \.compare)
        let content = UNMutableNotificationContent()
        if failures == 0 {
            content.title = "Louder"
            if isComparison {
                content.body = total == 1
                    ? "Created 3 comparison files."
                    : "Created comparisons for \(total) files."
            } else {
                content.body = total == 1 ? "Made 1 file louder." : "Made \(total) files louder."
            }
        } else {
            content.title = "Louder — \(failures) of \(total) failed"
            content.body = "Open Louder to see what went wrong."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

    }

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: ContentView(
                queue: queue,
                comparisonPlayer: comparisonPlayer
            ))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.toolbarStyle = .unifiedCompact
            let toolbar = NSToolbar(identifier: "Louder.MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .labelOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            newWindow.toolbar = toolbar
            self.toolbar = toolbar
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(hosting.view.fittingSize)
            newWindow.center()
            window = newWindow
            updateToolbar()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.resetItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.resetItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Reset"
            item.paletteLabel = "Reset"
            item.toolTip = "Reset to the initial state"
            item.autovalidates = false
            let button = NSHostingView(rootView:
                Button {
                    self.resetApp()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .accessibilityLabel("Reset to initial state")
            )
            button.translatesAutoresizingMaskIntoConstraints = false
            item.view = button
            item.isEnabled = true
            return item

        default:
            return nil
        }
    }

    @objc private func resetApp() {
        comparisonPlayer.stop()
        guard queue.canReset else { return }

        if queue.wasCompareBatch {
            let count = queue.generatedFileCount
            let alert = NSAlert()
            alert.messageText = "Delete all generated files?"
            alert.informativeText = count == 1
                ? "This removes the 1 generated comparison file and returns to the start."
                : "This removes all \(count) generated comparison files and returns to the start."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                queue.deleteGeneratedFiles()
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Keep the original file?"
            alert.informativeText = "The new louder file will be kept. Choose whether to keep or delete the original."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Keep Original")
            alert.addButton(withTitle: "Delete Original")
            let response = alert.runModal()
            // First button = Keep, second = Delete.
            queue.reset(deleteOriginals: response == .alertSecondButtonReturn)
        }
    }

    private func updateToolbar() {
        guard let toolbar else { return }

        let resetIndex = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == Self.resetItemIdentifier
        })
        if queue.canReset, resetIndex == nil {
            toolbar.insertItem(
                withItemIdentifier: Self.resetItemIdentifier,
                at: toolbar.items.count
            )
        } else if !queue.canReset, let resetIndex {
            toolbar.removeItem(at: resetIndex)
        }
    }
}
