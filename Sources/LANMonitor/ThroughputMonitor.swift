import Foundation

struct ThroughputSample {
    let downloadMbps: Double
    let uploadMbps: Double
}

/// Samples cumulative interface byte counters via `netstat -I <iface> -b` and computes
/// instantaneous throughput as the delta between consecutive samples — the same technique
/// Activity Monitor's Network tab uses, not a synthetic speed test (no data is downloaded).
final class ThroughputMonitor {
    private var lastBytesIn: UInt64?
    private var lastBytesOut: UInt64?
    private var lastTimestamp: Date?
    private var lastInterface: String?

    func sample(interface: String) -> ThroughputSample? {
        guard let (bytesIn, bytesOut) = currentCounters(interface: interface) else { return nil }
        let now = Date()

        defer {
            lastBytesIn = bytesIn
            lastBytesOut = bytesOut
            lastTimestamp = now
            lastInterface = interface
        }

        guard interface == lastInterface,
              let prevIn = lastBytesIn, let prevOut = lastBytesOut, let prevTime = lastTimestamp,
              bytesIn >= prevIn, bytesOut >= prevOut else {
            return nil
        }

        let elapsed = now.timeIntervalSince(prevTime)
        guard elapsed > 0.05 else { return nil }

        let downMbps = Double(bytesIn - prevIn) * 8 / elapsed / 1_000_000
        let upMbps = Double(bytesOut - prevOut) * 8 / elapsed / 1_000_000
        return ThroughputSample(downloadMbps: downMbps, uploadMbps: upMbps)
    }

    private func currentCounters(interface: String) -> (UInt64, UInt64)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-I", interface, "-b"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.split(separator: "\n") {
            guard line.contains("Link#") else { continue }
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 10, cols[0] == interface else { continue }
            guard let ibytes = UInt64(cols[6]), let obytes = UInt64(cols[9]) else { continue }
            return (ibytes, obytes)
        }
        return nil
    }
}
