import WidgetKit
import SwiftUI
import Foundation
import Darwin

// MARK: - Entry

struct StatsEntry: TimelineEntry {
    let date:     Date
    let cpu:      Int
    let mem:      Int
    let memUsed:  String
    let memTotal: String
    let thermal:  String
    let netDown:  String
    let netUp:    String
    let diskRead: String
    let diskWrite:String
    let topNet:   ProcessRateSummary?
    let topDisk:  ProcessRateSummary?
}

struct ProcessRateSummary {
    let name:  String
    let left:  String
    let right: String
}

// MARK: - Provider (collects own data — no App Groups needed)

struct StatsProvider: TimelineProvider {

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), cpu: 24, mem: 57,
                   memUsed: "9.1 GB", memTotal: "16.0 GB", thermal: "Normal",
                   netDown: "240 KB/s", netUp: "36 KB/s",
                   diskRead: "1.2 MB/s", diskWrite: "420 KB/s",
                   topNet: ProcessRateSummary(name: "Safari", left: "220 KB/s", right: "12 KB/s"),
                   topDisk: ProcessRateSummary(name: "mdworker", left: "1.1 MB/s", right: "80 KB/s"))
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
        let (netDown, netUp) = ratePair(key: "net", current: netCumulative(), minInterval: 1)
        let (diskRead, diskWrite) = ratePair(key: "disk", current: diskCumulative(), minInterval: 1)
        let topNet = topNetworkProcess()
        let topDisk = topDiskProcess()

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
            thermal:  thermal,
            netDown:  fmtRate(netDown),
            netUp:    fmtRate(netUp),
            diskRead: fmtRate(diskRead),
            diskWrite:fmtRate(diskWrite),
            topNet:   topNet,
            topDisk:  topDisk
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

    // MARK: - Network and disk

    private func netCumulative() -> (left: Int64, right: Int64) {
        let out = shell("/usr/sbin/netstat", ["-ib"]).stdout
        var rx = Int64(0), tx = Int64(0), seen = Set<String>()
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 10 else { continue }
            let name = String(cols[0])
            guard name.hasPrefix("en"), !seen.contains(name) else { continue }
            seen.insert(name)
            if let r = Int64(cols[6]), let t = Int64(cols[9]) {
                rx += r
                tx += t
            }
        }
        return (rx, tx)
    }

    private func diskCumulative() -> (left: Int64, right: Int64) {
        let output = shell("/usr/sbin/ioreg", ["-r", "-c", "IOBlockStorageDriver", "-l"]).stdout
        var read = Int64(0), write = Int64(0)
        for linePart in output.split(separator: "\n") {
            let line = String(linePart)
            guard line.contains("\"Statistics\"") else { continue }
            read += firstInteger(in: line, pattern: #""Bytes \(Read\)"\s*=\s*(\d+)"#)
            write += firstInteger(in: line, pattern: #""Bytes \(Write\)"\s*=\s*(\d+)"#)
        }
        return (read, write)
    }

    private func ratePair(
        key: String,
        current: (left: Int64, right: Int64),
        minInterval: TimeInterval
    ) -> (left: Int64, right: Int64) {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        defer {
            defaults.set(current.left, forKey: "io.\(key).left")
            defaults.set(current.right, forKey: "io.\(key).right")
            defaults.set(now, forKey: "io.\(key).time")
        }

        let then = defaults.double(forKey: "io.\(key).time")
        guard then > 0 else { return (0, 0) }
        let dt = max(now - then, minInterval)
        let previousLeft = (defaults.object(forKey: "io.\(key).left") as? NSNumber)?.int64Value ?? 0
        let previousRight = (defaults.object(forKey: "io.\(key).right") as? NSNumber)?.int64Value ?? 0
        return (
            max(0, Int64(Double(current.left - previousLeft) / dt)),
            max(0, Int64(Double(current.right - previousRight) / dt))
        )
    }

    private func topNetworkProcess() -> ProcessRateSummary? {
        let result = shell("/usr/bin/nettop", [
            "-P", "-L", "2", "-d", "-x", "-J", "bytes_in,bytes_out", "-s", "1"
        ], timeout: 3)
        guard result.status == 0 else { return nil }

        var best: (name: String, down: Int64, up: Int64)?
        for line in result.stdout.split(separator: "\n") {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            if columns[0].isEmpty {
                best = nil
                continue
            }
            let processID = String(columns[0])
            guard let dot = processID.lastIndex(of: ".") else { continue }
            let name = String(processID[..<dot])
            guard shouldShowProcess(name) else { continue }
            let down = Int64(String(columns[1]).trimmingCharacters(in: .whitespaces)) ?? 0
            let up = Int64(String(columns[2]).trimmingCharacters(in: .whitespaces)) ?? 0
            guard down + up > 0 else { continue }
            if best == nil || down + up > best!.down + best!.up {
                best = (name, down, up)
            }
        }

        guard let best else { return nil }
        return ProcessRateSummary(name: best.name, left: fmtRate(best.down), right: fmtRate(best.up))
    }

    private func topDiskProcess() -> ProcessRateSummary? {
        let now = Date().timeIntervalSince1970
        let current = diskProcessSamples(sampledAt: now)
        let previous = loadDiskProcessSamples()
        saveDiskProcessSamples(current)

        var best: (name: String, read: Int64, write: Int64)?
        for (pid, sample) in current {
            guard let old = previous[pid] else { continue }
            let dt = max(sample.sampledAt - old.sampledAt, 1)
            let read = max(0, Int64(Double(sample.read - old.read) / dt))
            let write = max(0, Int64(Double(sample.write - old.write) / dt))
            guard read + write > 0, shouldShowProcess(sample.name) else { continue }
            if best == nil || read + write > best!.read + best!.write {
                best = (sample.name, read, write)
            }
        }

        guard let best else { return nil }
        return ProcessRateSummary(name: best.name, left: fmtRate(best.read), right: fmtRate(best.write))
    }

    private struct DiskProcessSample: Codable {
        let name: String
        let read: Int64
        let write: Int64
        let sampledAt: TimeInterval
    }

    private func diskProcessSamples(sampledAt: TimeInterval) -> [String: DiskProcessSample] {
        let pidCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0) / Int32(MemoryLayout<pid_t>.size)
        guard pidCount > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(pidCount))
        let bytes = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        let count = max(0, Int(bytes) / MemoryLayout<pid_t>.size)
        var samples: [String: DiskProcessSample] = [:]

        for pid in pids.prefix(count) where pid > 0 {
            guard let name = processName(pid: Int(pid)), shouldShowProcess(name) else { continue }
            var info = rusage_info_v4()
            let result = withUnsafeMutableBytes(of: &info) { rawBuffer -> Int32 in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return proc_pid_rusage(
                    pid,
                    RUSAGE_INFO_V4,
                    base.assumingMemoryBound(to: rusage_info_t?.self)
                )
            }
            guard result == 0 else { continue }
            samples[String(pid)] = DiskProcessSample(
                name: name,
                read: Int64(clamping: info.ri_diskio_bytesread),
                write: Int64(clamping: info.ri_diskio_byteswritten),
                sampledAt: sampledAt
            )
        }

        return samples
    }

    private func loadDiskProcessSamples() -> [String: DiskProcessSample] {
        guard let data = UserDefaults.standard.data(forKey: "io.disk.processes"),
              let samples = try? JSONDecoder().decode([String: DiskProcessSample].self, from: data)
        else { return [:] }
        return samples
    }

    private func saveDiskProcessSamples(_ samples: [String: DiskProcessSample]) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        UserDefaults.standard.set(data, forKey: "io.disk.processes")
    }

    private func processName(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN))
        let length = proc_name(Int32(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private func shouldShowProcess(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return name != "kernel_task" && !lowered.contains("macmonitor")
    }

    private func shell(
        _ path: String,
        _ args: [String],
        timeout: TimeInterval = 2
    ) -> (stdout: String, stderr: String, status: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            return ("", "launch failed: \(error)", -1)
        }

        let group = DispatchGroup()
        var outData = Data()
        var errData = Data()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outData = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = DispatchTime.now() + timeout
        while task.isRunning && DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if task.isRunning {
            task.terminate()
        }
        task.waitUntilExit()
        _ = group.wait(timeout: .now() + 0.5)

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            task.terminationStatus
        )
    }

    private func firstInteger(in text: String, pattern: String) -> Int64 {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text)
        else { return 0 }
        return Int64(text[range]) ?? 0
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
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)
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
                MiniIORow(label: "NET", leftIcon: "↓", left: e.netDown, rightIcon: "↑", right: e.netUp)
                MiniIORow(label: "DSK", leftIcon: "R", left: e.diskRead, rightIcon: "W", right: e.diskWrite)
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
}

// ── Medium ─────────────────────────────────────────────────────────────────────
struct MediumView: View {
    let e: StatsEntry
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)
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
                    InfoRow(label: "NET ↓ / ↑", val: "\(e.netDown) / \(e.netUp)", color: .green)
                    InfoRow(label: "DSK R / W", val: "\(e.diskRead) / \(e.diskWrite)", color: .cyan)
                    if let topNet = e.topNet {
                        ProcessSummaryRow(label: "Top net", summary: topNet, leftPrefix: "↓", rightPrefix: "↑")
                    }
                    if let topDisk = e.topDisk {
                        ProcessSummaryRow(label: "Top disk", summary: topDisk, leftPrefix: "R", rightPrefix: "W")
                    }
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

struct MiniIORow: View {
    let label: String
    let leftIcon: String
    let left: String
    let rightIcon: String
    let right: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 24, alignment: .leading)
            Text("\(leftIcon)\(left)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(rightIcon)\(right)")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundColor(.white)
        .lineLimit(1)
    }
}

struct ProcessSummaryRow: View {
    let label: String
    let summary: ProcessRateSummary
    let leftPrefix: String
    let rightPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
            HStack(spacing: 4) {
                Text(summary.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(leftPrefix)\(summary.left)")
                Text("\(rightPrefix)\(summary.right)")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white)
        }
    }
}

private func fmtRate(_ bps: Int64) -> String {
    let d = Double(max(0, bps))
    if d >= 1_073_741_824 { return String(format: "%.1f GB/s", d / 1_073_741_824) }
    if d >= 1_048_576 { return String(format: "%.1f MB/s", d / 1_048_576) }
    if d >= 1_024 { return String(format: "%.0f KB/s", d / 1_024) }
    return "\(Int(d)) B/s"
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

// MARK: - Widget declaration

@main
struct MacMonitorWidget: Widget {
    let kind = "MacMonitorWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            MacMonitorWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("MacMonitor")
        .description("Live CPU, memory, network, and disk I/O — works standalone")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
