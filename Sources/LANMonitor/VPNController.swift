import Foundation

struct ConfiguredVPNService {
    let name: String
    let status: String
    let type: String
}

/// Wraps `scutil --nc` to list/start/stop VPN services already configured in the system
/// (e.g. via an installed .mobileconfig profile). Operates on the current user's own
/// configured services, no elevated privileges required.
final class VPNController {

    func listServices() -> [ConfiguredVPNService] {
        guard let output = run(["--nc", "list"]) else { return [] }
        let pattern = #"\((.*?)\)\s+[0-9A-Fa-f-]+\s+"(.*?)"\s+\[(.*?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var results: [ConfiguredVPNService] = []
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: line) else { return "" }
                return String(line[r])
            }
            results.append(ConfiguredVPNService(name: group(2), status: group(1), type: group(3)))
        }
        return results
    }

    func start(service: String) {
        _ = run(["--nc", "start", service])
    }

    func stop(service: String) {
        _ = run(["--nc", "stop", service])
    }

    private func run(_ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
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
