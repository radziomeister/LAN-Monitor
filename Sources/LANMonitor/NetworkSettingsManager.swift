import Foundation

struct NetworkServiceInfo {
    var serviceName: String
    var isDHCP: Bool
    var ipAddress: String?
    var subnetMask: String?
    var router: String?
    var dnsServers: [String]
}

/// Reads and writes macOS network service configuration via `networksetup`.
/// Write operations require administrator privileges (prompted per call via `osascript`).
final class NetworkSettingsManager {

    func listServices() -> [String] {
        guard let output = run("/usr/sbin/networksetup", ["-listallnetworkservices"]) else { return [] }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    /// The raw interface device used by the default route, e.g. "en0".
    func activeInterfaceDevice() -> String? {
        guard let routeOutput = run("/sbin/route", ["-n", "get", "default"]) else { return nil }
        for line in routeOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                return trimmed.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Maps the interface used by the default route (e.g. "en0") to its network service name (e.g. "Wi-Fi").
    func activeServiceName() -> String? {
        guard let iface = activeInterfaceDevice(), let hpOutput = run("/usr/sbin/networksetup", ["-listallhardwareports"]) else {
            return nil
        }

        var currentPort: String?
        for rawLine in hpOutput.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Hardware Port: ") {
                currentPort = String(line.dropFirst("Hardware Port: ".count))
            } else if line.hasPrefix("Device: ") {
                let device = String(line.dropFirst("Device: ".count))
                if device == iface {
                    return currentPort
                }
            }
        }
        return nil
    }

    func info(for service: String) -> NetworkServiceInfo {
        let output = run("/usr/sbin/networksetup", ["-getinfo", service]) ?? ""
        var isDHCP = true
        var ip: String?
        var mask: String?
        var router: String?

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.contains("Manually Configured") { isDHCP = false }
            if let v = value(after: "IP address:", in: line) { ip = v }
            if let v = value(after: "Subnet mask:", in: line) { mask = v }
            if let v = value(after: "Router:", in: line) { router = v }
        }

        let dnsOutput = run("/usr/sbin/networksetup", ["-getdnsservers", service]) ?? ""
        var dns: [String] = []
        if !dnsOutput.lowercased().contains("there aren't any dns servers") {
            dns = dnsOutput.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        return NetworkServiceInfo(serviceName: service, isDHCP: isDHCP, ipAddress: ip, subnetMask: mask, router: router, dnsServers: dns)
    }

    func setDHCP(service: String) throws {
        try runPrivileged("/usr/sbin/networksetup -setdhcp \(shellQuote(service))")
    }

    func setManual(service: String, ip: String, subnet: String, router: String) throws {
        try runPrivileged(
            "/usr/sbin/networksetup -setmanual \(shellQuote(service)) \(shellQuote(ip)) \(shellQuote(subnet)) \(shellQuote(router))"
        )
    }

    func setDNS(service: String, servers: [String]) throws {
        let args = servers.isEmpty ? "Empty" : servers.map(shellQuote).joined(separator: " ")
        try runPrivileged("/usr/sbin/networksetup -setdnsservers \(shellQuote(service)) \(args)")
    }

    // MARK: - Helpers

    private func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let v = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runPrivileged(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "NetworkSettingsManager",
                code: Int(task.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: (msg?.isEmpty == false ? msg! : "Operacja anulowana lub nieudana")]
            )
        }
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
