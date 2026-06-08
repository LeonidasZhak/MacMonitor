import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Root

struct PopoverView: View {
    @ObservedObject var model: SystemStatsModel
    let openSettings: () -> Void
    @State private var appearanceRevision = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Header(model: model, openSettings: openSettings)
                if model.helperMissing {
                    HelperMissingBanner()
                }
                sep
                CPUSection(model: model)
                sep
                GPUSection(model: model)
                if model.fanRPM > 0 {
                    sep
                    FanSection(model: model)
                }
                sep
                MemorySection(model: model)
                sep
                BatterySection(model: model)
                sep
                NetworkDiskSection(model: model)
                sep
                PowerSection(model: model)
                sep
                ProcessSection(model: model)
                if model.tokenTrackerStatus != nil {
                    sep
                    TokenTrackerSection(model: model)
                }
                sep
                CompanionSection()
                sep
                FooterBar(model: model)
            }
        }
        .frame(width: 340)
        .background(Color.theme(.background))
        .onReceive(NotificationCenter.default.publisher(for: .appearanceChanged)) { _ in
            appearanceRevision += 1
        }
        .id(appearanceRevision)
    }

    private var sep: some View {
        Rectangle()
            .fill(Color.theme(.separator).opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

// MARK: - Helper missing banner

private struct HelperMissingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "FF9F0A"))
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("System helper not installed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "FF9F0A"))
                Text("Run Install.command from the DMG to enable GPU, temps, and power data.")
                    .font(.system(size: 10))
                    .foregroundColor(Color.theme(.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "FF9F0A").opacity(0.08))
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: SystemStatsModel
    let openSettings: () -> Void
    @ObservedObject private var updater = UpdateChecker.shared

    var thermalColor: Color {
        switch model.thermalState {
        case "Normal":   return Color(hex: "30D158")
        case "Fair":     return Color(hex: "FFD60A")
        default:         return Color(hex: "FF453A")
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.chipName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.theme(.primaryText))
                HStack(spacing: 5) {
                    Circle().fill(thermalColor).frame(width: 6, height: 6)
                    Text(model.thermalState)
                        .font(.system(size: 11))
                        .foregroundColor(thermalColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f W", model.totalPower))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.theme(.primaryText))
                Text("total power")
                    .font(.system(size: 10))
                    .foregroundColor(Color.theme(.secondaryText))
            }
            Button { openSettings() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(Color.theme(.secondaryText))
                        .padding(.leading, 12)
                    if updater.updateAvailable {
                        Circle()
                            .fill(Color(hex: "FF9F0A"))
                            .frame(width: 7, height: 7)
                            .offset(x: -2, y: 1)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - CPU

private struct CPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "cpu", title: "CPU") {
            Row(label: "Overall") { StatBar(pct: model.cpuUsage, color: Color.theme(.cpu)) }
            if model.eCoreCount > 0 {
                Row(label: "E-cluster  \(model.eCoresMHz) MHz") {
                    StatBar(pct: model.eCoresPct, color: Color(hex: "64D2FF"))
                }
                Row(label: "P-cluster  \(model.pCoresMHz) MHz") {
                    StatBar(pct: model.pCoresPct, color: Color(hex: "BF5AF2"))
                }
                // M5+ Super cluster — only shown when present
                if model.sClusterPct > 0 || model.sClusterMHz > 0 {
                    Row(label: "S-cluster  \(model.sClusterMHz) MHz") {
                        StatBar(pct: model.sClusterPct, color: Color(hex: "FF6B6B"))
                    }
                }
            }
            if !model.perCoreCPU.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(model.perCoreCPU.enumerated()), id: \.offset) { i, pct in
                        CoreTile(index: i, pct: pct, isE: i < model.eCoreCount)
                    }
                }
                .padding(.top, 4)
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.cpuTemp),
                     color: tempColor(model.cpuTemp))
                if model.cpuDieHotspot > 0 {
                    Pill(icon: "thermometer.sun.fill",
                         val: String(format: "%.0f°C", model.cpuDieHotspot),
                         color: tempColor(model.cpuDieHotspot))
                }
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.2f W", model.cpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Fan (hidden on fanless models)

private struct FanSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "fan", title: "Fan") {
            Row(label: "Speed") {
                HStack {
                    Text("\(model.fanRPM) RPM")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color.theme(.primaryText))
                    Spacer()
                }
            }
        }
    }
}

// MARK: - GPU

private struct GPUSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "rectangle.3.group", title: "GPU  ·  \(model.gpuCoreCount) cores") {
            Row(label: "\(model.gpuMHz) MHz") {
                StatBar(pct: model.gpuUsage, color: Color(hex: "FF9F0A"))
            }
            HStack {
                Pill(icon: "thermometer", val: String(format: "%.0f°C", model.gpuTemp),
                     color: tempColor(model.gpuTemp))
                Spacer()
                Pill(icon: "bolt", val: String(format: "%.3f W", model.gpuPower),
                     color: Color(hex: "FFD60A"))
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Memory

private struct MemorySection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "memorychip", title: "Memory") {
            Row(label: "\(fmtB(model.memUsed)) / \(fmtB(model.memTotal))") {
                StatBar(pct: model.memPct, color: Color.theme(.memory))
            }
            HStack(spacing: 16) {
                KV("DRAM BW",  String(format: "%.1f GB/s", model.dramBW))
                KV("Swap", model.swapTotal > 0
                    ? "\(fmtB(model.swapUsed)) / \(fmtB(model.swapTotal))" : "None")
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Battery

private struct BatterySection: View {
    @ObservedObject var model: SystemStatsModel

    var statusLabel: String {
        if model.batteryCharged  { return "Fully Charged" }
        if model.batteryCharging { return "Charging" }
        return "On Battery"
    }

    var batteryColor: Color {
        model.batteryPct < 20 ? Color(hex: "FF453A")
            : (model.batteryCharging || model.batteryCharged)
                ? Color.theme(.battery) : Color(hex: "FFD60A")
    }

    var body: some View {
        SectionBox(icon: "battery.75percent", title: "Battery") {
            Row(label: statusLabel) {
                StatBar(pct: model.batteryPct, color: batteryColor)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    KV("Source",     model.batteryOnAC ? "AC Power" : "Battery")
                    KV("Remaining",  model.batteryTimeLeft)
                }
                GridRow {
                    KV("Adapter",    model.adapterWatts > 0
                        ? String(format: "%.0f W", model.adapterWatts) : "—")
                    KV("Charge rate",model.chargingWatts > 0
                        ? String(format: "%.1f W", model.chargingWatts) : "—")
                }
                GridRow {
                    KV("Temp",       model.batteryTempC > 0
                        ? String(format: "%.1f °C", model.batteryTempC) : "—")
                    KV("Cycles",     model.batteryCycles > 0
                        ? "\(model.batteryCycles)" : "—")
                }
                GridRow {
                    KV("Health",     "\(model.batteryHealthPct)%")
                    KV("Capacity",   model.batteryMaxMAh > 0
                        ? "\(model.batteryMaxMAh) / \(model.batteryDesignMAh) mAh" : "—")
                }
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Network + Disk

private struct NetworkDiskSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        HStack(spacing: 0) {
            SectionBox(icon: "wifi", title: "Network") {
                IORow(icon: "arrow.down", val: fmtB(model.netInBps)  + "/s", color: Color.theme(.networkDown))
                IORow(icon: "arrow.up",   val: fmtB(model.netOutBps) + "/s", color: Color.theme(.networkUp))
                if !model.topNetworkProcs.isEmpty {
                    IOHeader(left: "App", right: "Down / Up")
                        .padding(.top, 3)
                    ForEach(model.topNetworkProcs.prefix(3)) { p in
                        IOProcessRow(
                            name: p.name,
                            leftValue: fmtB(p.downBps) + "/s",
                            rightValue: fmtB(p.upBps) + "/s",
                            leftColor: Color.theme(.networkDown),
                            rightColor: Color.theme(.networkUp)
                        )
                    }
                }
            }
            Rectangle().fill(Color.theme(.separator).opacity(0.06)).frame(width: 1)
            SectionBox(icon: "internaldrive", title: "Disk I/O") {
                IORow(icon: "arrow.down", val: String(format: "%.0f KB/s", model.diskReadKBs),  color: Color.theme(.diskRead))
                IORow(icon: "arrow.up",   val: String(format: "%.0f KB/s", model.diskWriteKBs), color: Color.theme(.diskWrite))
                if !model.topDiskProcs.isEmpty {
                    IOHeader(left: "App", right: "Read / Write")
                        .padding(.top, 3)
                    ForEach(model.topDiskProcs.prefix(3)) { p in
                        IOProcessRow(
                            name: p.name,
                            leftValue: fmtB(p.readBps) + "/s",
                            rightValue: fmtB(p.writeBps) + "/s",
                            leftColor: Color.theme(.diskRead),
                            rightColor: Color.theme(.diskWrite)
                        )
                    }
                }
            }
        }
    }
}

private struct IORow: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(color)
            Text(val)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "EBEBF5"))
            Spacer()
        }
    }
}

private struct IOHeader: View {
    let left: String; let right: String
    var body: some View {
        HStack {
            Text(left)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(right)
                .frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 8))
        .foregroundColor(Color.theme(.secondaryText))
    }
}

private struct IOProcessRow: View {
    let name: String
    let leftValue: String
    let rightValue: String
    let leftColor: Color
    let rightColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "EBEBF5"))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(leftValue)
                    .foregroundColor(leftColor)
                Text(rightValue)
                    .foregroundColor(rightColor)
            }
            .font(.system(size: 9, design: .monospaced))
            .frame(width: 72, alignment: .trailing)
        }
    }
}

// MARK: - Power rails

private struct PowerSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "bolt.fill", title: "Power Rails") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                PowerTile(label: "CPU",   val: model.cpuPower)
                PowerTile(label: "GPU",   val: model.gpuPower)
                PowerTile(label: "ANE",   val: model.anePower)
                PowerTile(label: "DRAM",  val: model.dramPower)
                PowerTile(label: "SYS",   val: model.sysPower)
                PowerTile(label: "TOTAL", val: model.totalPower, highlight: true)
            }
        }
    }
}

private struct PowerTile: View {
    let label: String; let val: Double; var highlight: Bool = false
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(highlight ? Color.theme(.power) : Color(hex:"888899"))
            Spacer()
            Text(String(format: val >= 1 ? "%.2f W" : "%.3f W", val))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(highlight ? Color.theme(.power) : .white)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.white.opacity(highlight ? 0.07 : 0.03))
        .cornerRadius(6)
    }
}

// MARK: - Processes

private struct ProcessSection: View {
    @ObservedObject var model: SystemStatsModel
    var body: some View {
        SectionBox(icon: "list.bullet", title: "Top Processes") {
            HStack {
                Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 40, alignment: .trailing)
                Text("Memory").frame(width: 64, alignment: .trailing)
            }
            .font(.system(size: 9)).foregroundColor(Color.theme(.secondaryText))

            ForEach(model.topProcs) { p in
                HStack(spacing: 0) {
                    Text(p.name)
                        .font(.system(size: 11)).foregroundColor(Color.theme(.primaryText))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f%%", p.cpu))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(cpuClr(p.cpu))
                        .frame(width: 40, alignment: .trailing)
                    Text(fmtB(p.mem))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.theme(.memory))
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
    func cpuClr(_ v: Double) -> Color {
        v >= 50 ? Color(hex:"FF453A") : v >= 20 ? Color(hex:"FFD60A") : Color(hex:"30D158")
    }
}

// MARK: - Token Tracker

private struct TokenTrackerSection: View {
    @ObservedObject var model: SystemStatsModel

    var body: some View {
        if let tracker = model.tokenTrackerStatus {
            SectionBox(icon: "number.square", title: "Token Tracker") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    TokenTile(label: "Today", tokens: tracker.todayTokens, cost: tracker.todayCost)
                    TokenTile(label: "7 days", tokens: tracker.weekTokens, cost: tracker.weekCost)
                    TokenTile(label: "30 days", tokens: tracker.monthTokens, cost: tracker.monthCost)
                }

                if !tracker.topModels.isEmpty {
                    VStack(spacing: 5) {
                        ForEach(tracker.topModels.prefix(3)) { item in
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.theme(.primaryText))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 96, alignment: .leading)
                                StatBar(pct: min(100, Int(item.sharePercent.rounded())), color: Color.theme(.tokenTracker))
                                Text(TokenTrackerStatus.compactCount(item.tokens))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.theme(.secondaryText))
                                    .frame(width: 42, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if !tracker.limits.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tracker.limits.prefix(2)) { limit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(limit.label)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.theme(.secondaryText))
                                    .lineLimit(1)
                                StatBar(pct: min(100, max(0, Int((limit.fraction * 100).rounded()))),
                                        color: Color.theme(.tokenTracker))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TokenTile: View {
    let label: String
    let tokens: Double
    let cost: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Color.theme(.secondaryText))
            Text(TokenTrackerStatus.compactCount(tokens))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color.theme(.primaryText))
            Text(TokenTrackerStatus.compactUsd(cost))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.theme(.tokenTracker))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }
}

// MARK: - Companion

private struct CompanionSection: View {
    @AppStorage("enableCompanionCat") private var enableCompanionCat = true
    @AppStorage("companionCatMood") private var mood = 2

    private var catFace: String {
        switch mood % 4 {
        case 0: return "=^.^="
        case 1: return "(=^-ω-^=)"
        case 2: return "(=^･ｪ･^=)"
        default: return "(=^‥^=)"
        }
    }

    var body: some View {
        if enableCompanionCat {
            SectionBox(icon: "pawprint.fill", title: "Companion") {
                HStack(spacing: 10) {
                    Text(catFace)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.theme(.weather))
                        .frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu bar companion")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.theme(.primaryText))
                        Text("Lives here while the dashboard is open.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.theme(.secondaryText))
                    }
                    Spacer()
                    Button("Pet") { mood += 1 }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @ObservedObject var model: SystemStatsModel
    @State private var working = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                working = true
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    model.optimize()
                    DispatchQueue.main.async { working = false }
                }
            } label: {
                Label(working ? "Working…" : "Optimize", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent).tint(Color(hex: "FF9F0A")).disabled(working)

            Button { NSApp.terminate(nil) } label: {
                Text("Quit").frame(maxWidth: .infinity)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {
    @Binding var isPresented: Bool
    var onClose: () -> Void = {}
    @AppStorage("enableMenuBar") var enableMenuBar = true
    @AppStorage("enableWidget")  var enableWidget  = false
    @AppStorage("openAtLogin")   var openAtLogin   = false
    @AppStorage("enableCompanionCat") var enableCompanionCat = true
    @AppStorage("weatherLocation") var weatherLocation = ""
    @State private var menuMetrics = MenuBarLayoutStore.orderedMetrics()
    @State private var appearanceRevision = 0
    @ObservedObject private var updater = UpdateChecker.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(Color.theme(.primaryText))

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Menu Bar App", isOn: $enableMenuBar)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                    Text("Live stats in your menu bar. Click to open the full dashboard.")
                        .font(.system(size: 11)).foregroundColor(Color.theme(.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }

                MenuBarLayoutEditor(metrics: $menuMetrics, weatherLocation: $weatherLocation)

                AppearanceEditor()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open at Login", isOn: $openAtLogin)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                        .onChange(of: openAtLogin) { enabled in
                            if enabled {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                    Text("Automatically start MacMonitor when you log in.")
                        .font(.system(size: 11)).foregroundColor(Color.theme(.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Desktop Widget", isOn: $enableWidget)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                    Text("Right-click your desktop → Edit Widgets → find MacMonitor.")
                        .font(.system(size: 11)).foregroundColor(Color.theme(.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Dashboard Companion", isOn: $enableCompanionCat)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
                    Text("Show a small interactive companion in the dashboard popover.")
                        .font(.system(size: 11)).foregroundColor(Color.theme(.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().background(Color.white.opacity(0.1))

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacMonitor  v\(updater.currentVersion)")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.theme(.primaryText))
                        Group {
                            switch updater.updatePhase {
                            case .idle:
                                if updater.updateAvailable {
                                    Text("v\(updater.latestVersion) available")
                                        .foregroundColor(Color(hex: "FF9F0A"))
                                } else {
                                    Text("Apple Silicon  ·  macOS 13+  ·  MIT")
                                        .foregroundColor(Color.theme(.secondaryText))
                                }
                            case .downloading:
                                Text("Downloading v\(updater.latestVersion)…")
                                    .foregroundColor(Color(hex: "FF9F0A"))
                            case .installing:
                                Text("Installing…")
                                    .foregroundColor(Color(hex: "FF9F0A"))
                            case .readyToRelaunch:
                                Text("Ready — relaunch to apply")
                                    .foregroundColor(Color(hex: "30D158"))
                            case .failed(let msg):
                                Text(msg)
                                    .foregroundColor(Color(hex: "FF453A"))
                            }
                        }
                        .font(.system(size: 10))
                    }
                    Spacer()
                    Group {
                        switch updater.updatePhase {
                        case .idle:
                            HStack(spacing: 6) {
                                if updater.updateAvailable {
                                    Button("Update") { updater.startUpdate() }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color(hex: "FF9F0A"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Button("Done") {
                                    isPresented = false
                                    onClose()
                                }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(hex: "0A84FF"))
                            }
                        case .downloading:
                            VStack(alignment: .trailing, spacing: 3) {
                                ProgressView(value: updater.downloadFraction)
                                    .progressViewStyle(.linear)
                                    .tint(Color(hex: "FF9F0A"))
                                    .frame(width: 80)
                                Text("\(Int(updater.downloadFraction * 100))%")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(Color.theme(.secondaryText))
                            }
                        case .installing:
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(Color(hex: "FF9F0A"))
                        case .readyToRelaunch:
                            Button("Relaunch") { updater.relaunch() }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: "30D158"))
                                .font(.system(size: 12, weight: .semibold))
                        case .failed:
                            Button("Dismiss") { updater.dismissUpdateError() }
                                .buttonStyle(.bordered)
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(22)
            .id(appearanceRevision)
        }
        .frame(width: 410, height: 600)
        .background(Color.theme(.panel))
        .preferredColorScheme(.dark)
        .onAppear { menuMetrics = MenuBarLayoutStore.orderedMetrics() }
        .onReceive(NotificationCenter.default.publisher(for: .appearanceChanged)) { _ in
            appearanceRevision += 1
        }
        .onChange(of: weatherLocation) { _ in
            NotificationCenter.default.post(name: .menuBarLayoutChanged, object: nil)
        }
    }
}

private struct AppearanceEditor: View {
    @State private var chartStyle = AppearanceStore.chartStyle()
    @State private var appearanceRevision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Appearance")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.theme(.primaryText))
                Spacer()
                Picker("", selection: Binding(
                    get: { chartStyle },
                    set: { style in
                        chartStyle = style
                        AppearanceStore.setChartStyle(style)
                    }
                )) {
                    ForEach(ChartStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 178)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 6) {
                ForEach(AppearancePreset.allCases) { preset in
                    Button(preset.title) {
                        AppearanceStore.apply(preset)
                        appearanceRevision += 1
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 10, weight: .medium))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(AppearanceColorRole.allCases) { role in
                    ColorRoleEditor(role: role)
                }
            }
            .id(appearanceRevision)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appearanceChanged)) { _ in
            chartStyle = AppearanceStore.chartStyle()
            appearanceRevision += 1
        }
    }
}

private struct ColorRoleEditor: View {
    let role: AppearanceColorRole
    @State private var selectedColor: Color

    init(role: AppearanceColorRole) {
        self.role = role
        _selectedColor = State(initialValue: Color.theme(role))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(role.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "EBEBF5"))
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { selectedColor },
                    set: { color in
                        selectedColor = color
                        if let hex = color.hexRGB() {
                            AppearanceStore.setHex(hex, for: role)
                        }
                    }
                ))
                .labelsHidden()
                .frame(width: 24)
            }

            HStack(spacing: 4) {
                ForEach(AppearanceStore.swatches.prefix(5), id: \.self) { hex in
                    Button {
                        selectedColor = Color(hex: hex)
                        AppearanceStore.setHex(hex, for: role)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 13, height: 13)
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(7)
        .background(Color.white.opacity(0.035))
        .cornerRadius(6)
        .onReceive(NotificationCenter.default.publisher(for: .appearanceChanged)) { _ in
            selectedColor = Color.theme(role)
        }
    }
}

private struct MenuBarLayoutEditor: View {
    @Binding var metrics: [MenuBarMetric]
    @Binding var weatherLocation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Menu Bar Layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.theme(.primaryText))
                Spacer()
                Button("Reset") {
                    MenuBarLayoutStore.reset()
                    metrics = MenuBarLayoutStore.orderedMetrics()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "0A84FF"))
            }

            VStack(spacing: 6) {
                ForEach(metrics) { metric in
                    MenuBarMetricRow(
                        metric: metric,
                        isFirst: metrics.first == metric,
                        isLast: metrics.last == metric,
                        metrics: $metrics
                    )

                    if metric == .weather && MenuBarLayoutStore.isVisible(.weather) {
                        TextField("City or place, e.g. Taipei", text: $weatherLocation)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .padding(.leading, 28)
                    }

                    if metric == .tokenTracker && MenuBarLayoutStore.isVisible(.tokenTracker) {
                        Text("Reads TokenTrackerBar widget-snapshot.json when present.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.theme(.secondaryText))
                            .padding(.leading, 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

private struct MenuBarMetricRow: View {
    let metric: MenuBarMetric
    let isFirst: Bool
    let isLast: Bool
    @Binding var metrics: [MenuBarMetric]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 11))
                .foregroundColor(Color.theme(.secondaryText))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.theme(.primaryText))
                Text(metric.help)
                    .font(.system(size: 9))
                    .foregroundColor(Color.theme(.secondaryText))
                    .lineLimit(1)
            }
            Spacer()
            if MenuBarLayoutStore.canHideLabel(metric) {
                Toggle("Label", isOn: Binding(
                    get: { MenuBarLayoutStore.isLabelVisible(metric) },
                    set: { visible in
                        MenuBarLayoutStore.setLabelVisible(metric, visible)
                        metrics = MenuBarLayoutStore.orderedMetrics()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 10))
                .foregroundColor(Color.theme(.secondaryText))
                .disabled(!MenuBarLayoutStore.isVisible(metric))
            }
            Toggle("", isOn: Binding(
                get: { MenuBarLayoutStore.isVisible(metric) },
                set: { visible in
                    MenuBarLayoutStore.setVisible(metric, visible)
                    metrics = MenuBarLayoutStore.orderedMetrics()
                }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: Color(hex: "30D158")))
            .scaleEffect(0.75)
            HStack(spacing: 2) {
                Button {
                    MenuBarLayoutStore.move(metric, direction: -1)
                    metrics = MenuBarLayoutStore.orderedMetrics()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(isFirst)

                Button {
                    MenuBarLayoutStore.move(metric, direction: 1)
                    metrics = MenuBarLayoutStore.orderedMetrics()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(isLast)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color.theme(.secondaryText))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(MenuBarLayoutStore.isVisible(metric) ? 0.055 : 0.025))
        .cornerRadius(6)
    }
}

// MARK: - Reusable atoms

private struct SectionBox<Content: View>: View {
    let icon: String; let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.theme(.secondaryText))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.theme(.secondaryText)).tracking(0.6)
            }
            content
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct Row<R: View>: View {
    let label: String; @ViewBuilder let right: R
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11)).foregroundColor(Color.theme(.secondaryText))
                .frame(width: 130, alignment: .leading).lineLimit(1)
            right
        }
    }
}

private struct StatBar: View {
    let pct: Int; var color: Color = Color(hex: "30D158")
    private var chartStyle: ChartStyle { AppearanceStore.chartStyle() }
    private var barColor: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A") : color
    }
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    switch chartStyle {
                    case .glow:
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.07))
                        RoundedRectangle(cornerRadius: 3).fill(barColor)
                            .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                            .shadow(color: barColor.opacity(0.35), radius: 3)
                            .animation(.easeInOut(duration: 0.4), value: pct)
                    case .flat:
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2).fill(barColor.opacity(0.9))
                            .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                            .animation(.easeInOut(duration: 0.25), value: pct)
                    case .outline:
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 3).fill(barColor.opacity(0.32))
                            .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                            .animation(.easeInOut(duration: 0.4), value: pct)
                    }
                }
            }
            .frame(height: 7)
            Text("\(pct)%")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(Color.theme(.primaryText))
                .frame(width: 32, alignment: .trailing)
        }
    }
}

private struct CoreTile: View {
    let index: Int; let pct: Double; let isE: Bool
    var color: Color {
        pct >= 85 ? Color(hex:"FF453A") : pct >= 60 ? Color(hex:"FFD60A")
            : (isE ? Color(hex:"64D2FF") : Color(hex:"BF5AF2"))
    }
    var body: some View {
        HStack(spacing: 5) {
            Text("C\(index)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(color.opacity(0.7))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 22, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.theme(.separator).opacity(0.06))
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: g.size.width * CGFloat(min(pct,100)) / 100)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 5)
            Text("\(Int(pct))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(hex:"666680"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

private struct Pill: View {
    let icon: String; let val: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(val).font(.system(size: 10, design: .monospaced))
        }
        .foregroundColor(color)
    }
}

private struct KV: View {
    let k: String; let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundColor(Color.theme(.secondaryText))
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundColor(Color.theme(.primaryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Helpers

private func fmtB(_ b: Int64) -> String {
    let d = Double(b)
    if d >= 1_073_741_824 { return String(format: "%.1f GB", d/1_073_741_824) }
    if d >= 1_048_576     { return String(format: "%.1f MB", d/1_048_576) }
    if d >= 1_024         { return String(format: "%.0f KB", d/1_024) }
    return "\(b) B"
}

private func tempColor(_ t: Double) -> Color {
    t >= 80 ? Color(hex:"FF453A") : t >= 65 ? Color(hex:"FFD60A") : Color(hex:"888899")
}

// MARK: - Hex colour helper

extension Color {
    static func theme(_ role: AppearanceColorRole) -> Color {
        Color(hex: AppearanceStore.hex(for: role))
    }

    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double((int)       & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    func hexRGB() -> String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
