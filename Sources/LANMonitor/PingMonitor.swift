import Foundation

/// Detects the default LAN gateway and measures reachability to it via ICMP ping.
final class PingMonitor {

    /// Runs `route -n get default` and parses the `gateway:` line.
    func detectGateway() -> String? {
        let output = runProcess("/sbin/route", ["-n", "get", "default"])
        guard let output else { return nil }
        for rawLine in output.split(separator: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    /// Sends a single ICMP echo request to `host`, bounded by `timeoutSeconds`.
    /// Returns whether it succeeded and, if so, the round-trip latency in milliseconds.
    func ping(host: String, timeoutSeconds: Int = 2) -> (success: Bool, latencyMs: Double?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-t", "\(timeoutSeconds)", host]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return (false, nil)
        }
        task.waitUntilExit()

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let success = task.terminationStatus == 0

        var latency: Double?
        if success, let range = output.range(of: "time=") {
            let after = output[range.upperBound...]
            let numStr = after.prefix(while: { $0.isNumber || $0 == "." })
            latency = Double(numStr)
        }
        return (success, latency)
    }

    private func runProcess(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
