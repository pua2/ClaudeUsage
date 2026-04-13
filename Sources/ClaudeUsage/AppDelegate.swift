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
        stats.scheduleAutoUpdateCheck()

        cancellable = stats.$usage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBar() }

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
        updateStatusBar()
    }

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }
        guard let u = stats.usage else {
            button.image = nil
            button.title = "—"
            return
        }

        let hasSession = u.sessionResetsAt != nil
        let sessionTime = u.sessionResetsAt.map { StatsModel.compactTime(until: $0) }
        let weeklyTime = u.weeklyResetsAt.map { StatsModel.compactTime(until: $0) }

        button.image = drawStatusIcon(
            sessionPct: hasSession ? u.sessionPct : nil,
            weeklyPct: u.weeklyPct,
            sessionTime: hasSession ? sessionTime : nil,
            weeklyTime: weeklyTime
        )
        button.imagePosition = .imageOnly
        button.title = ""
    }

    // MARK: - Ring Drawing

    private let sessionColor: NSColor = .systemOrange
    private let weeklyColor: NSColor = .systemPurple

    private func drawStatusIcon(
        sessionPct: Double?,
        weeklyPct: Double,
        sessionTime: String?,
        weeklyTime: String?
    ) -> NSImage {
        let height: CGFloat = 18
        let iconGap: CGFloat = 1
        let timeGap: CGFloat = 3
        let iconSize: CGFloat = 18
        let hasSession = sessionPct != nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)

        let pctColWidth: CGFloat = hasSession ? 24 : 0
        let timeColWidth: CGFloat = 22
        let totalWidth = pctColWidth + (hasSession ? iconGap : 0) + iconSize + timeGap + timeColWidth

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { _ in
            var cursorX: CGFloat = 0

            if let sPct = sessionPct {
                // Left column — stacked percentages (use label color to match time text)
                let sessionAttrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor.labelColor
                ]
                let weeklyAttrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor.labelColor
                ]
                let topText = NSString(string: "\(Int(sPct.rounded()))%")
                let topSize = topText.size(withAttributes: sessionAttrs)
                topText.draw(at: NSPoint(x: pctColWidth - topSize.width, y: 1), withAttributes: sessionAttrs)
                let botText = NSString(string: "\(Int(weeklyPct.rounded()))%")
                let botSize = botText.size(withAttributes: weeklyAttrs)
                botText.draw(at: NSPoint(x: pctColWidth - botSize.width, y: 10), withAttributes: weeklyAttrs)
                cursorX = pctColWidth + iconGap
            }

            // Center — app icon
            if let appIcon = NSImage(named: "AppIcon") {
                let iconRect = NSRect(x: cursorX + (iconSize - iconSize) / 2,
                                      y: (height - iconSize) / 2,
                                      width: iconSize, height: iconSize)
                appIcon.draw(in: iconRect)
            }
            cursorX += iconSize + timeGap

            // Right column — stacked time text
            let textColor = NSColor.labelColor
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: textColor
            ]

            if let sTime = sessionTime, let wTime = weeklyTime {
                let top = NSString(string: sTime)
                top.draw(at: NSPoint(x: cursorX, y: 1), withAttributes: timeAttrs)
                let bot = NSString(string: wTime)
                bot.draw(at: NSPoint(x: cursorX, y: 10), withAttributes: timeAttrs)
            } else if let wTime = weeklyTime {
                let text = NSString(string: wTime)
                text.draw(at: NSPoint(x: cursorX, y: 5), withAttributes: timeAttrs)
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func drawRing(center: NSPoint, radius: CGFloat, lineWidth: CGFloat,
                          pct: Double, color: NSColor) {
        // Track
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.gray.withAlphaComponent(0.25).setStroke()
        track.stroke()

        // Filled arc (clockwise from 12 o'clock in flipped coordinates)
        guard pct > 0 else { return }
        let startAngle: CGFloat = -90
        let endAngle = -90 + CGFloat(pct / 100) * 360
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
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
