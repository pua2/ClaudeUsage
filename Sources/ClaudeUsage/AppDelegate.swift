import AppKit
import SwiftUI
import Combine

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?
    private var hostingController: NSViewController?
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
        if button.image == nil, let icon = loadAppIcon() {
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.imagePosition = .imageLeft
        }
        button.title = " \(label)"
    }

    private func loadAppIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.applicationIconName)
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
            let hc = NSHostingController(rootView: MenuBarView().environmentObject(stats))
            hc.sizingOptions = .intrinsicContentSize
            hostingController = hc

            let p = NSPanel(
                contentRect: .zero,
                styleMask:   [.borderless, .nonactivatingPanel],
                backing:     .buffered,
                defer:       false
            )
            p.contentViewController = hc
            p.backgroundColor  = NSColor.windowBackgroundColor
            p.isOpaque         = true
            p.hasShadow        = true
            p.level            = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

            hc.view.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(contentDidResize),
                name: NSView.frameDidChangeNotification, object: hc.view
            )

            panel = p
        }

        positionPanel(below: button, in: buttonWindow)
        panel?.makeKeyAndOrderFront(nil)

        // Dismiss on click outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func positionPanel(below button: NSStatusBarButton? = nil, in buttonWindow: NSWindow? = nil) {
        guard let panel else { return }
        let resolvedButton = button ?? statusItem.button
        let resolvedWindow = buttonWindow ?? resolvedButton?.window
        guard let btn = resolvedButton, let btnWin = resolvedWindow else { return }

        let btnRect    = btn.convert(btn.bounds, to: nil)
        let screenRect = btnWin.convertToScreen(btnRect)
        let panelWidth: CGFloat = 300
        let contentHeight = hostingController?.view.fittingSize.height ?? 500
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 40
        let panelHeight = min(contentHeight, maxHeight)

        var x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        if let screen = NSScreen.main {
            x = max(screen.visibleFrame.minX + 8, min(x, screen.visibleFrame.maxX - panelWidth - 8))
        }

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    @objc private func contentDidResize() {
        guard panel?.isVisible == true else { return }
        positionPanel()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
