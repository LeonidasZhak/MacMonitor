import AppKit
import SwiftUI
import Combine
import ServiceManagement

extension Notification.Name {
    static let menuBarLayoutChanged = Notification.Name("menuBarLayoutChanged")
    static let companionSettingsChanged = Notification.Name("companionSettingsChanged")
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case network
    case disk
    case power
    case battery
    case weather
    case tokenTracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu:          return "CPU"
        case .memory:       return "Memory"
        case .network:      return "Network"
        case .disk:         return "Disk I/O"
        case .power:        return "Power"
        case .battery:      return "Battery"
        case .weather:      return "Weather"
        case .tokenTracker: return "Token Tracker"
        }
    }

    var shortLabel: String {
        switch self {
        case .cpu:          return "CPU"
        case .memory:       return "MEM"
        case .network:      return "NET"
        case .disk:         return "DSK"
        case .power:        return "PWR"
        case .battery:      return "BAT"
        case .weather:      return "WX"
        case .tokenTracker: return "TOK"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu:          return "cpu"
        case .memory:       return "memorychip"
        case .network:      return "wifi"
        case .disk:         return "internaldrive"
        case .power:        return "bolt.fill"
        case .battery:      return "battery.75percent"
        case .weather:      return "cloud.sun"
        case .tokenTracker: return "number.square"
        }
    }

    var defaultVisible: Bool {
        switch self {
        case .cpu, .memory, .network, .disk:
            return true
        case .power, .battery, .weather, .tokenTracker:
            return false
        }
    }

    var help: String {
        switch self {
        case .cpu:          return "Overall load and CPU temperature."
        case .memory:       return "Current memory pressure."
        case .network:      return "Download and upload throughput."
        case .disk:         return "Read and write throughput."
        case .power:        return "Total system power draw."
        case .battery:      return "Battery percentage when available."
        case .weather:      return "Optional Open-Meteo weather for your saved location."
        case .tokenTracker: return "Optional local TokenTracker snapshot, if installed."
        }
    }

    func titleFragment(model: SystemStatsModel) -> String? {
        switch self {
        case .cpu:
            let temp = model.cpuTemp > 0 ? String(format: " %.0f°", model.cpuTemp) : ""
            return "\(shortLabel) \(model.cpuUsage)%\(temp)"
        case .memory:
            return "\(shortLabel) \(model.memPct)%"
        case .network:
            let label = MenuBarLayoutStore.isLabelVisible(self) ? "\(shortLabel) " : ""
            return "\(label)↓\(Self.formatRate(model.netInBps)) ↑\(Self.formatRate(model.netOutBps))"
        case .disk:
            let read = Int64(model.diskReadKBs * 1024)
            let write = Int64(model.diskWriteKBs * 1024)
            let label = MenuBarLayoutStore.isLabelVisible(self) ? "\(shortLabel) " : ""
            return "\(label)R\(Self.formatRate(read)) W\(Self.formatRate(write))"
        case .power:
            guard model.totalPower > 0 else { return nil }
            return "\(shortLabel) \(String(format: "%.1fW", model.totalPower))"
        case .battery:
            guard model.batteryPct > 0 else { return nil }
            return "\(shortLabel) \(model.batteryPct)%"
        case .weather:
            guard !model.weatherText.isEmpty else { return nil }
            return model.weatherText
        case .tokenTracker:
            guard let status = model.tokenTrackerStatus else { return nil }
            return status.menuSummary(includeLabel: MenuBarLayoutStore.isLabelVisible(self))
        }
    }

    private static func formatRate(_ bytesPerSecond: Int64) -> String {
        let value = Double(max(0, bytesPerSecond))
        if value >= 1_048_576 { return String(format: "%.1fM/s", value / 1_048_576) }
        if value >= 1_024 { return String(format: "%.0fK/s", value / 1_024) }
        return "\(Int(value))B/s"
    }
}

enum MenuBarLayoutStore {
    private static let orderKey = "menuBarMetricOrder"
    private static let visiblePrefix = "menuBarMetricVisible."
    private static let labelPrefix = "menuBarMetricLabelVisible."

    static func orderedMetrics() -> [MenuBarMetric] {
        let saved = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        var metrics = saved.compactMap(MenuBarMetric.init(rawValue:))
        for metric in MenuBarMetric.allCases where !metrics.contains(metric) {
            metrics.append(metric)
        }
        return metrics
    }

    static func visibleMetrics() -> [MenuBarMetric] {
        orderedMetrics().filter { isVisible($0) }
    }

    static func isVisible(_ metric: MenuBarMetric) -> Bool {
        let key = visiblePrefix + metric.rawValue
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return metric.defaultVisible
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setVisible(_ metric: MenuBarMetric, _ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: visiblePrefix + metric.rawValue)
        notify()
    }

    static func canHideLabel(_ metric: MenuBarMetric) -> Bool {
        switch metric {
        case .network, .disk, .tokenTracker:
            return true
        case .cpu, .memory, .power, .battery, .weather:
            return false
        }
    }

    static func isLabelVisible(_ metric: MenuBarMetric) -> Bool {
        guard canHideLabel(metric) else { return true }
        let key = labelPrefix + metric.rawValue
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setLabelVisible(_ metric: MenuBarMetric, _ visible: Bool) {
        guard canHideLabel(metric) else { return }
        UserDefaults.standard.set(visible, forKey: labelPrefix + metric.rawValue)
        notify()
    }

    static func move(_ metric: MenuBarMetric, direction: Int) {
        var metrics = orderedMetrics()
        guard let index = metrics.firstIndex(of: metric) else { return }
        let target = index + direction
        guard metrics.indices.contains(target) else { return }
        metrics.swapAt(index, target)
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: orderKey)
        notify()
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        for metric in MenuBarMetric.allCases {
            UserDefaults.standard.removeObject(forKey: visiblePrefix + metric.rawValue)
            UserDefaults.standard.removeObject(forKey: labelPrefix + metric.rawValue)
        }
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .menuBarLayoutChanged, object: nil)
    }
}

enum ChartStyle: String, CaseIterable, Identifiable {
    case glow
    case flat
    case outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glow:    return "Glow"
        case .flat:    return "Flat"
        case .outline: return "Outline"
        }
    }
}

enum AppearanceColorRole: String, CaseIterable, Identifiable {
    case background
    case panel
    case primaryText
    case secondaryText
    case separator
    case cpu
    case memory
    case networkDown
    case networkUp
    case diskRead
    case diskWrite
    case power
    case battery
    case weather
    case tokenTracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background:   return "Background"
        case .panel:        return "Panel"
        case .primaryText:  return "Primary Text"
        case .secondaryText:return "Muted Text"
        case .separator:    return "Separator"
        case .cpu:          return "CPU"
        case .memory:       return "Memory"
        case .networkDown:  return "Net Down"
        case .networkUp:    return "Net Up"
        case .diskRead:     return "Disk Read"
        case .diskWrite:    return "Disk Write"
        case .power:        return "Power"
        case .battery:      return "Battery"
        case .weather:      return "Weather"
        case .tokenTracker: return "Token"
        }
    }

    var defaultHex: String {
        switch self {
        case .background:   return "0E0E12"
        case .panel:        return "1C1C1E"
        case .primaryText:  return "FFFFFF"
        case .secondaryText:return "888899"
        case .separator:    return "FFFFFF"
        case .cpu:          return "30D158"
        case .memory:       return "0A84FF"
        case .networkDown:  return "30D158"
        case .networkUp:    return "FF9F0A"
        case .diskRead:     return "64D2FF"
        case .diskWrite:    return "FF9F0A"
        case .power:        return "FFD60A"
        case .battery:      return "30D158"
        case .weather:      return "64D2FF"
        case .tokenTracker: return "BF5AF2"
        }
    }
}

enum AppearancePreset: String, CaseIterable, Identifiable {
    case system
    case graphite
    case neon
    case field
    case studio
    case aurora
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:   return "System"
        case .graphite: return "Graphite"
        case .neon:     return "Neon"
        case .field:    return "Field"
        case .studio:   return "Studio"
        case .aurora:   return "Aurora"
        case .ember:    return "Ember"
        }
    }

    var colors: [AppearanceColorRole: String] {
        switch self {
        case .system:
            return Dictionary(uniqueKeysWithValues: AppearanceColorRole.allCases.map { ($0, $0.defaultHex) })
        case .graphite:
            return [
                .background: "101012", .panel: "1B1B1F", .primaryText: "F4F4F5",
                .secondaryText: "A1A1AA", .separator: "D4D4D8",
                .cpu: "A1A1AA", .memory: "D4D4D8", .networkDown: "86EFAC", .networkUp: "FDE68A",
                .diskRead: "BAE6FD", .diskWrite: "FDBA74", .power: "FACC15", .battery: "A7F3D0",
                .weather: "93C5FD", .tokenTracker: "C4B5FD"
            ]
        case .neon:
            return [
                .background: "07070A", .panel: "141018", .primaryText: "FFFFFF",
                .secondaryText: "B7A8FF", .separator: "45E3FF",
                .cpu: "39FF88", .memory: "00D1FF", .networkDown: "00FFA3", .networkUp: "FFB000",
                .diskRead: "45E3FF", .diskWrite: "FF6B00", .power: "F8FF00", .battery: "50FF6C",
                .weather: "7DD3FC", .tokenTracker: "D946EF"
            ]
        case .field:
            return [
                .background: "0B1110", .panel: "14201D", .primaryText: "F8FAFC",
                .secondaryText: "94A3B8", .separator: "2DD4BF",
                .cpu: "2DD4BF", .memory: "60A5FA", .networkDown: "22C55E", .networkUp: "F59E0B",
                .diskRead: "38BDF8", .diskWrite: "FB923C", .power: "EAB308", .battery: "84CC16",
                .weather: "0EA5E9", .tokenTracker: "A78BFA"
            ]
        case .studio:
            return [
                .background: "111114", .panel: "202126", .primaryText: "F6F7FB",
                .secondaryText: "AAB0BB", .separator: "5E6778",
                .cpu: "7DD3FC", .memory: "C4B5FD", .networkDown: "86EFAC", .networkUp: "FCA5A5",
                .diskRead: "93C5FD", .diskWrite: "FDBA74", .power: "FDE047", .battery: "A7F3D0",
                .weather: "67E8F9", .tokenTracker: "F0ABFC"
            ]
        case .aurora:
            return [
                .background: "07100F", .panel: "10201F", .primaryText: "F1FDF8",
                .secondaryText: "9CCBC0", .separator: "37BDA1",
                .cpu: "34D399", .memory: "5EEAD4", .networkDown: "A3E635", .networkUp: "FBBF24",
                .diskRead: "22D3EE", .diskWrite: "FB7185", .power: "FDE047", .battery: "BEF264",
                .weather: "38BDF8", .tokenTracker: "E879F9"
            ]
        case .ember:
            return [
                .background: "140F0D", .panel: "241B18", .primaryText: "FFF7ED",
                .secondaryText: "D6B9A7", .separator: "B56E4A",
                .cpu: "F97316", .memory: "60A5FA", .networkDown: "4ADE80", .networkUp: "FBBF24",
                .diskRead: "67E8F9", .diskWrite: "FB7185", .power: "FDE047", .battery: "84CC16",
                .weather: "7DD3FC", .tokenTracker: "C084FC"
            ]
        }
    }
}

extension Notification.Name {
    static let appearanceChanged = Notification.Name("appearanceChanged")
}

enum AppearanceStore {
    private static let colorPrefix = "appearanceColor."
    private static let chartStyleKey = "chartStyle"

    static let swatches = [
        "30D158", "0A84FF", "64D2FF", "BF5AF2", "FF9F0A",
        "FFD60A", "FF453A", "F472B6", "A1A1AA", "FFFFFF"
    ]

    static func hex(for role: AppearanceColorRole) -> String {
        UserDefaults.standard.string(forKey: colorPrefix + role.rawValue) ?? role.defaultHex
    }

    static func setHex(_ hex: String, for role: AppearanceColorRole) {
        UserDefaults.standard.set(hex, forKey: colorPrefix + role.rawValue)
        notify()
    }

    static func apply(_ preset: AppearancePreset) {
        for (role, hex) in preset.colors {
            UserDefaults.standard.set(hex, forKey: colorPrefix + role.rawValue)
        }
        notify()
    }

    static func chartStyle() -> ChartStyle {
        let raw = UserDefaults.standard.string(forKey: chartStyleKey) ?? ChartStyle.glow.rawValue
        return ChartStyle(rawValue: raw) ?? .glow
    }

    static func setChartStyle(_ style: ChartStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: chartStyleKey)
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .appearanceChanged, object: nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?
    var companionItem: NSStatusItem?
    var companionView: StatusBarPetView?
    var popover    = NSPopover()
    var welcomeWin: NSWindow?
    var settingsWin: NSWindow?
    let model      = SystemStatsModel()

    // Subscribe to model changes so the label updates in sync with each tick,
    // not on a separate independent timer that may fire before data is ready.
    private var cancellables = Set<AnyCancellable>()
    private var popoverGlobalEventMonitor: Any?
    private var popoverLocalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMenuBar()
        syncCompanionItem()
        model.startMonitoring()

        // Drive the label from published model values — fires immediately on change.
        // Keep disk/network in the same menu-bar summary so heavy I/O is visible
        // without opening the dashboard.
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateLabel()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .menuBarLayoutChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.model.refreshOptionalMenuBarMetrics()
                self?.updateLabel()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .appearanceChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLabel()
                self?.companionView?.needsDisplay = true
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .companionSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncCompanionItem()
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model) { [weak self] in
                self?.openSettings()
            }
            .preferredColorScheme(.dark)
        )
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(popoverDidClose),
                                               name: NSPopover.didCloseNotification,
                                               object: popover)
    }

    private func syncCompanionItem() {
        let enabled = UserDefaults.standard.object(forKey: "enableCompanionCat") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "enableCompanionCat")
        if enabled {
            if companionItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: 58)
                let view = StatusBarPetView(frame: NSRect(x: 0, y: 0, width: 58, height: 22))
                view.onPrimaryClick = { [weak self] in
                    self?.companionView?.pet()
                }
                view.onSecondaryClick = { [weak self] in
                    if let button = self?.statusItem?.button {
                        self?.togglePopover(button)
                    }
                }
                if let button = item.button {
                    button.title = ""
                    button.image = nil
                    button.addSubview(view)
                    view.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                        view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                        view.topAnchor.constraint(equalTo: button.topAnchor),
                        view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
                    ])
                }
                companionItem = item
                companionView = view
            }
            companionView?.start()
        } else {
            companionView?.stop()
            if let companionItem {
                NSStatusBar.system.removeStatusItem(companionItem)
            }
            companionItem = nil
            companionView = nil
        }
    }

    private func updateLabel() {
        guard let btn = statusItem?.button else { return }
        let cpu = model.cpuUsage
        let mem = model.memPct
        let dot = cpu >= 85 || mem >= 85 ? "🔴"
                : cpu >= 60 || mem >= 60 ? "🟡" : "🟢"
        let fragments = MenuBarLayoutStore.visibleMetrics().compactMap {
            $0.titleFragment(model: model)
        }
        btn.title = ([dot] + (fragments.isEmpty ? ["MacMonitor"] : fragments)).joined(separator: "  ")
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
            startPopoverDismissMonitoring()
        }
    }

    private func startPopoverDismissMonitoring() {
        guard popoverGlobalEventMonitor == nil, popoverLocalEventMonitor == nil else { return }
        popoverGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
        popoverLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
            return event
        }
    }

    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown else { return }
        if let popoverWindow = popover.contentViewController?.view.window,
           event.window == popoverWindow {
            return
        }
        if let button = statusItem?.button,
           event.window == button.window {
            let point = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(point) {
                return
            }
        }
        closePopover()
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        stopPopoverDismissMonitoring()
    }

    @objc private func popoverDidClose() {
        stopPopoverDismissMonitoring()
    }

    private func stopPopoverDismissMonitoring() {
        if let monitor = popoverGlobalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverGlobalEventMonitor = nil
        }
        if let monitor = popoverLocalEventMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalEventMonitor = nil
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
        closePopover()
        if let settingsWin, settingsWin.isVisible {
            settingsWin.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect:  NSRect(x: 0, y: 0, width: 430, height: 640),
            styleMask:    [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing:      .buffered,
            defer:        false
        )
        win.title                      = "MacMonitor Settings"
        win.titlebarAppearsTransparent = true
        win.backgroundColor            = NSColor(Color(hex: "1C1C1E"))
        win.contentViewController      = NSHostingController(
            rootView: SettingsSheet(isPresented: .constant(true)) { [weak self] in
                self?.settingsWin?.close()
            }
                .preferredColorScheme(.dark)
        )
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWin = win
    }
}

final class StatusBarPetView: NSView {
    var onPrimaryClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    private var timer: Timer?
    private var x: CGFloat = 4
    private var direction: CGFloat = 1
    private var blinkFrames = 0
    private var happyFrames = 0
    private var frameTick = 0

    override var acceptsFirstResponder: Bool { true }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pet() {
        happyFrames = 8
        needsDisplay = true
    }

    private func advance() {
        frameTick += 1
        if frameTick % 17 == 0 {
            blinkFrames = 2
        } else if blinkFrames > 0 {
            blinkFrames -= 1
        }
        if happyFrames > 0 {
            happyFrames -= 1
        }
        x += direction * 1.6
        if x > bounds.width - 27 {
            x = bounds.width - 27
            direction = -1
        } else if x < 4 {
            x = 4
            direction = 1
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onSecondaryClick?()
        } else {
            onPrimaryClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let y = max(3, (bounds.height - 15) / 2)
        let body = NSRect(x: x + 6, y: y + 2, width: 17, height: 10)
        let head = NSRect(x: x + (direction > 0 ? 18 : 0), y: y + 5, width: 11, height: 9)
        let tailStart = NSPoint(x: direction > 0 ? body.minX : body.maxX, y: body.midY + 2)
        let tailEnd = NSPoint(x: tailStart.x - direction * 6, y: tailStart.y + (frameTick % 2 == 0 ? 3 : -1))

        let fill = NSColor(Color.theme(.weather)).withAlphaComponent(happyFrames > 0 ? 0.98 : 0.88)
        let stroke = NSColor(Color.theme(.primaryText)).withAlphaComponent(0.24)
        fill.setFill()
        stroke.setStroke()

        let bodyPath = NSBezierPath(roundedRect: body, xRadius: 5, yRadius: 5)
        bodyPath.fill()
        bodyPath.lineWidth = 0.8
        bodyPath.stroke()

        let headPath = NSBezierPath(roundedRect: head, xRadius: 4, yRadius: 4)
        headPath.fill()
        headPath.stroke()

        let earOffset: CGFloat = direction > 0 ? 2 : 7
        let ear1 = NSBezierPath()
        ear1.move(to: NSPoint(x: head.minX + earOffset, y: head.maxY - 1))
        ear1.line(to: NSPoint(x: head.minX + earOffset + 2, y: head.maxY + 3))
        ear1.line(to: NSPoint(x: head.minX + earOffset + 4, y: head.maxY - 1))
        ear1.close()
        ear1.fill()
        let ear2 = NSBezierPath()
        ear2.move(to: NSPoint(x: head.minX + earOffset + 4, y: head.maxY - 1))
        ear2.line(to: NSPoint(x: head.minX + earOffset + 6, y: head.maxY + 3))
        ear2.line(to: NSPoint(x: head.minX + earOffset + 8, y: head.maxY - 1))
        ear2.close()
        ear2.fill()

        let tail = NSBezierPath()
        tail.move(to: tailStart)
        tail.curve(to: tailEnd,
                   controlPoint1: NSPoint(x: tailStart.x - direction * 2, y: tailStart.y + 5),
                   controlPoint2: NSPoint(x: tailEnd.x + direction * 2, y: tailEnd.y + 2))
        tail.lineWidth = 2
        tail.stroke()

        NSColor(Color.theme(.background)).withAlphaComponent(0.72).setFill()
        let eyeY = head.midY + 1
        if blinkFrames > 0 {
            let blink = NSBezierPath()
            blink.move(to: NSPoint(x: head.midX + direction * 1, y: eyeY))
            blink.line(to: NSPoint(x: head.midX + direction * 4, y: eyeY))
            blink.lineWidth = 1
            blink.stroke()
        } else {
            NSBezierPath(ovalIn: NSRect(x: head.midX + direction * 1.5, y: eyeY - 0.8, width: 2.2, height: 2.2)).fill()
        }

        let legY = body.minY - 1
        NSColor(Color.theme(.weather)).withAlphaComponent(0.82).setStroke()
        for legX in [body.minX + 4, body.maxX - 5] {
            let leg = NSBezierPath()
            leg.move(to: NSPoint(x: legX, y: body.minY + 1))
            leg.line(to: NSPoint(x: legX + (frameTick % 2 == 0 ? 1 : -1), y: legY))
            leg.lineWidth = 1.4
            leg.stroke()
        }

        if happyFrames > 0 {
            NSColor(Color.theme(.power)).withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: x + 28, y: y + 12, width: 3, height: 3)).fill()
        }
    }
}
