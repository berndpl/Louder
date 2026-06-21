import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSWindowDelegate {
    private static let undoItemIdentifier = NSToolbarItem.Identifier("Louder.Undo")

    let queue = DropQueue()
    let comparisonPlayer = ComparisonPlayer()
    private var window: NSWindow?
    private weak var toolbar: NSToolbar?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        queue.onAllDone = { [weak self] failures in
            self?.batchFinished(failures: failures)
        }
        queue.onStateChange = { [weak self] in self?.updateToolbar() }
        queue.onWillBeginBatch = { [weak self] in self?.comparisonPlayer.stop() }
        queue.onWillUndo = { [weak self] in self?.comparisonPlayer.stop() }
        showWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        queue.enqueue(
            urls,
            preset: .persisted,
            compare: queue.compareMode,
            addFades: AudioFades.persisted,
            trimSilence: TrimSilence.persisted,
            renameOriginal: RenameOriginal.persisted,
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
        [.flexibleSpace, Self.undoItemIdentifier]
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
        case Self.undoItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Undo"
            item.paletteLabel = "Undo"
            item.toolTip = "Undo the latest batch"
            item.autovalidates = false
            let button = NSHostingView(rootView:
                Button {
                    self.undoLatestBatch()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .accessibilityLabel("Undo latest batch")
            )
            button.translatesAutoresizingMaskIntoConstraints = false
            item.view = button
            item.isEnabled = true
            return item

        default:
            return nil
        }
    }

    @objc private func undoLatestBatch() {
        comparisonPlayer.stop()
        queue.undoLatestBatch()
    }

    private func updateToolbar() {
        guard let toolbar else { return }

        let undoIndex = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == Self.undoItemIdentifier
        })
        if queue.canUndo, undoIndex == nil {
            toolbar.insertItem(
                withItemIdentifier: Self.undoItemIdentifier,
                at: toolbar.items.count
            )
        } else if !queue.canUndo, let undoIndex {
            toolbar.removeItem(at: undoIndex)
        }
    }
}
