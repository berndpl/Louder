import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    private static let resetItemIdentifier = NSToolbarItem.Identifier("Louder.Reset")
    private static let infoItemIdentifier = NSToolbarItem.Identifier("Louder.SignalChainInfo")
    private static let pickItemIdentifier = NSToolbarItem.Identifier("Louder.PickFile")
    private static let keepOriginalItemIdentifier = NSToolbarItem.Identifier("Louder.KeepOriginal")
    private static let keepOriginalPreferenceKey = "keepOriginalWhenPicking"

    let queue = DropQueue()
    let comparisonPlayer = ComparisonPlayer()
    private var window: NSWindow?
    private weak var toolbar: NSToolbar?
    private let signalChainPopover = NSPopover()
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        queue.onAllDone = { [weak self] failures in
            self?.batchFinished(failures: failures)
        }
        queue.onStateChange = { [weak self] in self?.updateToolbar() }
        queue.onWillBeginBatch = { [weak self] in self?.comparisonPlayer.stop() }
        queue.onWillUndo = { [weak self] in self?.comparisonPlayer.stop() }
        comparisonPlayer.onSelectionChange = { [weak self] in self?.updateToolbar() }
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
            toolbar.displayMode = .iconOnly
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
        [.flexibleSpace, Self.keepOriginalItemIdentifier, Self.pickItemIdentifier, Self.infoItemIdentifier, Self.resetItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.infoItemIdentifier, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.keepOriginalItemIdentifier:
            let item = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                titles: ["Keep Original"],
                selectionMode: .selectAny,
                labels: nil,
                target: self,
                action: #selector(toggleKeepOriginal(_:))
            )
            item.label = "Keep Original"
            item.paletteLabel = "Keep Original"
            item.toolTip = "Also keep the original recording when picking an enhanced version"
            item.controlRepresentation = .expanded
            item.autovalidates = false
            item.setSelected(keepOriginal, at: 0)
            return item

        case Self.pickItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Pick This"
            item.paletteLabel = "Pick This"
            item.title = "Pick This"
            item.autovalidates = false
            item.isBordered = true
            item.style = .prominent
            item.target = self
            item.action = #selector(pickFile)
            return item

        case Self.infoItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Signal chain"
            item.paletteLabel = "Signal chain"
            item.toolTip = "Show the signal chain applied for this preset"
            item.autovalidates = false
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Signal chain")
            item.isBordered = true
            item.target = self
            item.action = #selector(showSignalChain)
            item.isEnabled = true
            return item

        case Self.resetItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Reset"
            item.paletteLabel = "Reset"
            item.toolTip = "Reset to the initial state"
            item.autovalidates = false
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset to initial state")
            item.isBordered = true
            item.target = self
            item.action = #selector(resetApp)
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

    private var keepOriginal: Bool {
        UserDefaults.standard.object(forKey: Self.keepOriginalPreferenceKey) as? Bool ?? true
    }

    @objc private func toggleKeepOriginal(_ sender: NSToolbarItemGroup) {
        UserDefaults.standard.set(sender.isSelected(at: 0), forKey: Self.keepOriginalPreferenceKey)
    }

    @objc private func showSignalChain() {
        guard let item = toolbar?.items.first(where: { $0.itemIdentifier == Self.infoItemIdentifier }) else { return }
        if signalChainPopover.isShown {
            signalChainPopover.close()
            return
        }
        signalChainPopover.behavior = .transient
        signalChainPopover.contentViewController = NSHostingController(
            rootView: SignalChainInfoPopoverContent(queue: queue)
        )
        signalChainPopover.show(relativeTo: item)
    }

    @objc private func pickFile() {
        guard let seriesID = comparisonPlayer.activeSeriesID else { return }
        do {
            let url = try queue.pickFile(seriesID: seriesID, keepOriginal: keepOriginal)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateToolbar() {
        guard let toolbar else { return }

        let selected = queue.series.first { $0.id == comparisonPlayer.activeSeriesID }
        var identifiers = [Self.infoItemIdentifier]
        if queue.canReset {
            identifiers += [Self.resetItemIdentifier, Self.keepOriginalItemIdentifier]
        }
        identifiers.append(.flexibleSpace)
        if queue.canReset, selected != nil {
            identifiers.append(Self.pickItemIdentifier)
        }
        for (index, identifier) in identifiers.enumerated() {
            if index < toolbar.items.count, toolbar.items[index].itemIdentifier == identifier {
                continue
            }
            if let currentIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == identifier }) {
                toolbar.removeItem(at: currentIndex)
            }
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
        while toolbar.items.count > identifiers.count {
            toolbar.removeItem(at: toolbar.items.count - 1)
        }
        if let keepOriginalItem = toolbar.items.first(where: {
            $0.itemIdentifier == Self.keepOriginalItemIdentifier
        }) as? NSToolbarItemGroup {
            keepOriginalItem.setSelected(keepOriginal, at: 0)
        }
        if let pickItem = toolbar.items.first(where: { $0.itemIdentifier == Self.pickItemIdentifier }) {
            pickItem.isEnabled = queue.isIdle && selected != nil
            pickItem.toolTip = selected.map {
                "Keep \($0.url.lastPathComponent), move the other versions to Trash, and reveal it in Finder"
            } ?? "Play a version to select the file to keep"
        }

    }
}
