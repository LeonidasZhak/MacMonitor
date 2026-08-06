import WidgetKit
import SwiftUI
import Darwin

// MARK: - Entry

struct StatsEntry: TimelineEntry {
    let date:     Date
    let cpu:      Int
    let mem:      Int
    let memUsed:  String
    let memTotal: String
    let thermal:  String
}

// MARK: - Provider (collects own data — no App Groups needed)

struct StatsProvider: TimelineProvider {

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), cpu: 24, mem: 57,
                   memUsed: "9.1 GB", memTotal: "16.0 GB", thermal: "Normal")
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let entry = self.collect()
            let next  = Calendar.current.date(byAdding: .second, value: 5, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // ── Data collection ───────────────────────────────────────────────────────

    private func collect() -> StatsEntry {
        let cpu           = cpuUsage()
        let (used, total) = memStats()
        let thermal       = thermalState()

        func fmt(_ b: Int64) -> String {
            let d = Double(b)
            if d >= 1_073_741_824 { return String(format: "%.1f GB", d / 1_073_741_824) }
            if d >= 1_048_576     { return String(format: "%.0f MB", d / 1_048_576) }
            return "\(b) B"
        }

        return StatsEntry(
            date:     Date(),
            cpu:      cpu,
            mem:      total > 0 ? Int(used * 100 / total) : 0,
            memUsed:  fmt(used),
            memTotal: fmt(total),
            thermal:  thermal
        )
    }

    /// Two-sample CPU delta via Mach kernel (~0.8 s, accurate)
    private func cpuUsage() -> Int {
        func ticks() -> (used: Double, total: Double) {
            var n: natural_t = 0
            var raw: processor_info_array_t?
            var cnt: mach_msg_type_number_t = 0
            guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                      &n, &raw, &cnt) == KERN_SUCCESS,
                  let raw = raw else { return (0, 1) }
            defer {
                vm_deallocate(mach_task_self_,
                              vm_address_t(bitPattern: raw),
                              vm_size_t(cnt) * vm_size_t(MemoryLayout<integer_t>.stride))
            }
            var u = 0.0, t = 0.0
            for i in 0..<Int(n) {
                let b    = i * Int(CPU_STATE_MAX)
                let user = Double(UInt32(bitPattern: raw[b + 0]))
                let sys  = Double(UInt32(bitPattern: raw[b + 1]))
                let idle = Double(UInt32(bitPattern: raw[b + 2]))
                let nice = Double(UInt32(bitPattern: raw[b + 3]))
                u += user + sys + nice
                t += user + sys + idle + nice
            }
            return (u, t)
        }

        let (u1, t1) = ticks()
        Thread.sleep(forTimeInterval: 0.8)
        let (u2, t2) = ticks()
        let dt = t2 - t1
        return dt > 0 ? min(100, Int(((u2 - u1) / dt * 100).rounded())) : 0
    }

    /// Memory via vm_statistics64
    private func memStats() -> (used: Int64, total: Int64) {
        var s = vm_statistics64_data_t()
        var c = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard kr == KERN_SUCCESS else { return (0, total) }
        let pg   = Int64(vm_kernel_page_size)
        let used = (Int64(s.active_count) + Int64(s.wire_count)
                  + Int64(s.compressor_page_count)) * pg
        return (min(max(used, 0), total), total)
    }

    /// Thermal state via ProcessInfo
    private func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "Normal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Normal"
        }
    }
}

// MARK: - Widget views

struct MacMonitorWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium: MediumView(e: entry)
        default:            SmallView(e: entry)
        }
    }
}

// ── Small ──────────────────────────────────────────────────────────────────────
struct SmallView: View {
    let e: StatsEntry
    var body: some View {
        // No opaque background here on purpose — see widgetContainerBackground().
        VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(dotColor(e.thermal)).frame(width: 7, height: 7)
                    Text("MacMonitor")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                WBar(label: "CPU", pct: e.cpu,  color: barColor(e.cpu))
                WBar(label: "MEM", pct: e.mem,  color: barColor(e.mem))
                Spacer(minLength: 0)
                Text("\(e.memUsed) / \(e.memTotal)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                HStack {
                    Circle().fill(dotColor(e.thermal)).frame(width: 5, height: 5)
                    Text(e.thermal).font(.system(size: 9)).foregroundColor(dotColor(e.thermal))
                    Spacer()
                    Text(e.date, style: .time).font(.system(size: 9)).foregroundColor(.gray)
                }
            Link(destination: URL(string: "https://razorpay.me/@ryyansafar")!) {
                Text("by ryyansafar · support ♥")
                    .font(.system(size: 8))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .padding(11)
    }
}

// ── Medium ─────────────────────────────────────────────────────────────────────
struct MediumView: View {
    let e: StatsEntry
    var body: some View {
        // No opaque background here on purpose — see widgetContainerBackground().
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(dotColor(e.thermal)).frame(width: 7, height: 7)
                    Text("MacMonitor")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                }
                WBar(label: "CPU", pct: e.cpu, color: barColor(e.cpu))
                WBar(label: "MEM", pct: e.mem, color: barColor(e.mem))
                Spacer(minLength: 0)
                Text(e.date, style: .time).font(.system(size: 9)).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)

            Divider().background(Color.gray.opacity(0.3))

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Thermal",  val: e.thermal,  color: dotColor(e.thermal))
                InfoRow(label: "RAM used", val: e.memUsed,  color: .white)
                InfoRow(label: "RAM total",val: e.memTotal, color: .gray)
                InfoRow(label: "CPU load", val: "\(e.cpu)%",color: barColor(e.cpu))
                Spacer(minLength: 0)
                Link(destination: URL(string: "https://razorpay.me/@ryyansafar")!) {
                    Text("by ryyansafar · support ♥")
                        .font(.system(size: 8))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(13)
    }
}

// MARK: - Reusable components

struct WBar: View {
    let label: String
    let pct:   Int
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 24, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: g.size.width * CGFloat(min(pct, 100)) / 100)
                        .animation(.easeInOut(duration: 0.5), value: pct)
                }
            }
            .frame(height: 6)
            Text("\(pct)%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

struct InfoRow: View {
    let label: String
    let val:   String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
            Text(val).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
        }
    }
}

private func dotColor(_ s: String) -> Color {
    switch s {
    case "Normal": return .green
    case "Fair":   return .yellow
    default:       return .red
    }
}

private func barColor(_ v: Int) -> Color {
    v >= 85 ? .red : v >= 60 ? .yellow : .green
}

/// The widget's background colour. Supplied through `containerBackground` rather than
/// painted inside the views — see `widgetContainerBackground()`.
private let widgetBackground = Color(red: 0.08, green: 0.08, blue: 0.12)

private extension View {
    /// Supplies the widget background via `containerBackground` on macOS 14+.
    ///
    /// This must not be an opaque `Color` inside the view hierarchy. macOS renders
    /// desktop widgets through "content layers" and derives a tint mask from the
    /// content, so a full-bleed opaque background makes the mask cover the entire
    /// widget — which rendered as one solid tinted block instead of the stats.
    /// `containerBackground` is understood by WidgetKit as chrome and excluded from
    /// that mask, which is exactly why macOS 14 made it mandatory.
    ///
    /// On macOS 13 the modifier does not exist and desktop widgets do not either; the
    /// widget appears in Notification Center, so paint the background directly there.
    @ViewBuilder
    func widgetContainerBackground() -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(widgetBackground, for: .widget)
        } else {
            background(widgetBackground)
        }
    }
}

// MARK: - Widget declaration

@main
struct MacMonitorWidget: Widget {
    let kind = "MacMonitorWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            MacMonitorWidgetView(entry: entry)
                .widgetContainerBackground()
        }
        .configurationDisplayName("MacMonitor")
        .description("Live CPU & memory — works standalone")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
