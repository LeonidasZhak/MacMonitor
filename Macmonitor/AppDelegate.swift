import AppKit
import SwiftUI
import Combine
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {

    var statusItem: NSStatusItem?
    var popover    = NSPopover()
    var welcomeWin: NSWindow?
    var settingsWin: NSWindow?
    let model      = SystemStatsModel()

    // Anchor tracking for the popover — see beginTrackingAnchor(_:).
    private var anchorObservers: [NSObjectProtocol] = []
    private var anchorOrigin: NSPoint?

    // Subscribe to model changes so the label updates in sync with each tick,
    // not on a separate independent timer that may fire before data is ready.
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        model.startMonitoring()

        // Drive the label from published model values — fires immediately on change
        Publishers.CombineLatest3(model.$cpuUsage, model.$memPct, model.$cpuTemp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, mem, temp in
                self?.updateLabel(cpu: cpu, mem: mem, temp: temp)
            }
            .store(in: &cancellables)

        // Restore Open at Login state on launch
        if UserDefaults.standard.bool(forKey: "openAtLogin") {
            try? SMAppService.mainApp.register()
        }

        // Show welcome window on very first launch
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showWelcomeWindow()
            }
        }

        // Check for updates in the background — non-blocking
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) {
            UpdateChecker.shared.check()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.title  = "🟢 CPU --%  MEM --%"
            btn.target = self
            btn.action = #selector(handleClick)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 340, height: 640)
        popover.behavior    = .transient
        popover.animates    = true
        popover.delegate    = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model).preferredColorScheme(.dark)
        )
    }

    private func updateLabel(cpu: Int, mem: Int, temp: Double) {
        guard let btn = statusItem?.button else { return }
        let dot = cpu >= 85 || mem >= 85 ? "🔴"
                : cpu >= 60 || mem >= 60 ? "🟡" : "🟢"
        let tempStr = temp > 0 ? String(format: " %.0f°", temp) : ""
        btn.title = "\(dot) CPU \(cpu)%\(tempStr)  MEM \(mem)%"
    }

    // MARK: - Click handling

    @objc func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            beginTrackingAnchor(sender)
        }
    }

    // MARK: - Anchor tracking

    /// The popover is positioned relative to the status item button. In native
    /// full-screen mode the menu bar auto-hides, which slides the button's window
    /// off the top of the screen. AppKit keeps the popover attached to that anchor,
    /// so it flashes and lands in the top-right corner with its top edge clipped.
    ///
    /// Rather than fight AppKit's positioning, dismiss the popover as soon as the
    /// anchor stops being a valid thing to point at.
    private func beginTrackingAnchor(_ button: NSStatusBarButton) {
        endTrackingAnchor()

        guard let anchorWindow = button.window else { return }
        anchorOrigin = anchorWindow.frame.origin

        let center = NotificationCenter.default

        // The menu bar retracting moves the status item's window.
        anchorObservers.append(
            center.addObserver(forName: NSWindow.didMoveNotification,
                               object: anchorWindow,
                               queue: .main) { [weak self] _ in
                self?.closeIfAnchorInvalid(anchorWindow)
            }
        )

        // Display or Space changes can also relocate the anchor.
        anchorObservers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil,
                               queue: .main) { [weak self] _ in
                self?.closeIfAnchorInvalid(anchorWindow)
            }
        )
    }

    private func closeIfAnchorInvalid(_ anchorWindow: NSWindow) {
        guard popover.isShown else { return }

        // Only a *vertical* move means the menu bar itself retracted.
        //
        // The status item uses NSStatusItem.variableLength and its title is rewritten
        // on every metrics tick, so the label's width changes whenever a value gains or
        // loses a digit. Menu bar items are laid out from the right, so a width change
        // shifts the anchor window's origin.x — which is not a reason to dismiss.
        // Comparing the full origin here closed the popover roughly once a second and
        // made the dashboard impossible to interact with.
        if let origin = anchorOrigin, abs(anchorWindow.frame.origin.y - origin.y) > 1 {
            popover.performClose(nil)
            return
        }

        // Anchor left its screen entirely — nothing valid to point at. Deliberately
        // checks for *no* intersection rather than full containment, so a status item
        // that is merely clipped by a crowded menu bar doesn't dismiss the popover.
        if let screen = anchorWindow.screen, !screen.frame.intersects(anchorWindow.frame) {
            popover.performClose(nil)
        }
    }

    private func endTrackingAnchor() {
        for observer in anchorObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        anchorObservers.removeAll()
        anchorOrigin = nil
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        endTrackingAnchor()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Drop the reference so the next "Settings…" builds a fresh window rather
        // than trying to reuse a closed one. Covers both Done and the close button.
        if (notification.object as? NSWindow) === settingsWin {
            settingsWin = nil
        }
    }

    func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard",
                                action: #selector(openPopover), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacMonitor",
                                action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openPopover() {
        if let btn = statusItem?.button { togglePopover(btn) }
    }

    // MARK: - Welcome window

    func showWelcomeWindow() {
        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask:    [.titled, .closable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.titlebarAppearsTransparent  = true
        win.titleVisibility             = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor             = NSColor(Color(hex: "0E0E12"))
        win.contentViewController       = NSHostingController(rootView: WelcomeView())
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWin = win
    }

    // MARK: - Settings window

    @objc func openSettings() {
        // Reuse the existing window instead of stacking a new one on every invocation.
        if let existing = settingsWin {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 320, height: 280),
            styleMask:    [.titled, .closable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.title                      = "MacMonitor Settings"
        win.titlebarAppearsTransparent = true
        win.backgroundColor            = NSColor(Color(hex: "1C1C1E"))
        win.isReleasedWhenClosed       = false

        // SettingsSheet drives dismissal through its isPresented binding. As a
        // standalone window this used to be passed .constant(true), which is
        // read-only — so tapping Done wrote to nothing and the window never closed.
        // Back the binding with an actual close, weakly so the window and its
        // content view don't retain each other.
        let dismiss = Binding<Bool>(
            get: { true },
            set: { [weak win] shouldPresent in
                if !shouldPresent { win?.performClose(nil) }
            }
        )

        win.contentViewController = NSHostingController(
            rootView: SettingsSheet(isPresented: dismiss)
                .preferredColorScheme(.dark)
        )
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWin = win
    }
}
