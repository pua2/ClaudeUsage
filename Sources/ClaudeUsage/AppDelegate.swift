import AppKit
import SwiftUI
import Combine

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private let stats = StatsModel()
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        stats.load()

        cancellable = stats.$menuBarLabel
            .receive(on: RunLoop.main)
            .sink { [weak self] label in self?.updateButton(label: label) }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.stats.load()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePanel)
        button.target = self
        updateButton(label: "—")
    }

    private func updateButton(label: String) {
        guard let button = statusItem.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let img = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude") {
            button.image = img.withSymbolConfiguration(cfg)
            button.imagePosition = .imageLeft
        }
        button.title = " \(label)"
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Build panel on first use
        if panel == nil {
            let hosting = NSHostingController(rootView: MenuBarView().environmentObject(stats))
            hosting.view.frame = NSRect(x: 0, y: 0, width: 300, height: 500)

            let p = NSPanel(
                contentRect: hosting.view.frame,
                styleMask:   [.borderless, .nonactivatingPanel],
                backing:     .buffered,
                defer:       false
            )
            p.contentViewController = hosting
            p.backgroundColor  = NSColor.windowBackgroundColor
            p.isOpaque         = true
            p.hasShadow        = true
            p.level            = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            panel = p
        }

        // Position directly below the status item button
        let btnRect    = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(btnRect)
        let panelWidth: CGFloat  = 300
        let panelHeight: CGFloat = 500

        // Center horizontally on the button, drop below it
        var x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        // Keep within screen bounds
        if let screen = NSScreen.main {
            x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - panelWidth - 8))
        }

        panel?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        panel?.makeKeyAndOrderFront(nil)

        // Dismiss on click outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
