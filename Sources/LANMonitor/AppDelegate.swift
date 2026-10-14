import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor = PingMonitor()
    private let networkInfo = NetworkSettingsManager()
    private let throughputMonitor = ThroughputMonitor()
    private let speedTestController = SpeedTestController()
    private let state = MonitorState()
    private var popoverController: StatusPopoverController?

    private var interfaceDevice: String?
    private var throughputTimer: Timer?
    private let throughputInterval: TimeInterval = 0.5

    private var gateway: String?
    private var isOnline = true
    private var outageHistory: [OutageEvent] = []
    private let maxHistoryEntries = 100

    private var timer: Timer?
    private let checkInterval: TimeInterval = 3.0
    private let pingTimeoutSeconds = 2
    private var checkCount = 0

    private let logFileURL: URL
    private var settingsWindowController: SettingsWindowController?

    override init() {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/LANMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("outages.csv")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureLogHeader()

        popoverController = StatusPopoverController(statusItem: statusItem, state: state)
        popoverController?.onOpenLog = { [weak self] in self?.openLog() }
        popoverController?.onOpenSettings = { [weak self] in self?.openSettings() }
        popoverController?.onRedetect = { [weak self] in self?.redetectGateway() }
        popoverController?.onQuit = { NSApp.terminate(nil) }
        popoverController?.onStartSpeedTest = { [weak self] in self?.startSpeedTest() }
        popoverController?.onCancelSpeedTest = { [weak self] in self?.speedTestController.cancel() }

        speedTestController.onPhaseChange = { [weak self] phase in
            self?.state.speedTestPhase = phase
            self?.state.speedTestElapsed = 0
        }
        speedTestController.onProgress = { [weak self] _, currentMbps, elapsed in
            self?.state.speedTestCurrentMbps = currentMbps
            self?.state.speedTestElapsed = elapsed
        }
        speedTestController.onComplete = { [weak self] result in
            self?.state.speedTestMaxDownloadMbps = result.maxDownloadMbps
            self?.state.speedTestAvgDownloadMbps = result.avgDownloadMbps
            self?.state.speedTestMaxUploadMbps = result.maxUploadMbps
            self?.state.speedTestAvgUploadMbps = result.avgUploadMbps
        }

        redetectGateway()
        refreshConnectionInfo()
        updateIcon(online: true)
        startMonitoring()
        startThroughputMonitoring()
    }

    private func startSpeedTest() {
        state.speedTestPhase = .downloading
        state.speedTestCurrentMbps = 0
        state.speedTestElapsed = 0
        speedTestController.start()
    }

    // MARK: - Actions

    private func redetectGateway() {
        gateway = monitor.detectGateway()
        state.gateway = gateway
    }

    private func refreshConnectionInfo() {
        interfaceDevice = networkInfo.activeInterfaceDevice()
        guard let service = networkInfo.activeServiceName() else { return }
        let info = networkInfo.info(for: service)
        state.serviceName = service
        state.localIP = info.ipAddress
        state.dnsServers = info.dnsServers
    }

    private func openLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    // MARK: - Monitoring loop

    private func startMonitoring() {
        performCheck()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
    }

    private func performCheck() {
        checkCount += 1
        if checkCount % 20 == 0 {
            refreshConnectionInfo()
        }

        guard let gw = gateway ?? monitor.detectGateway() else {
            DispatchQueue.main.async { [weak self] in
                self?.updateIcon(online: false)
            }
            return
        }
        gateway = gw

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.monitor.ping(host: gw, timeoutSeconds: self.pingTimeoutSeconds)
            DispatchQueue.main.async {
                self.handleResult(success: result.success, latencyMs: result.latencyMs)
            }
        }
    }

    private func handleResult(success: Bool, latencyMs: Double?) {
        let now = Date()
        state.addPingSample(PingSample(timestamp: now, latencyMs: success ? latencyMs : nil))

        if success {
            if !isOnline, var lastEvent = outageHistory.last, lastEvent.end == nil {
                lastEvent.end = now
                outageHistory[outageHistory.count - 1] = lastEvent
                appendToLog(lastEvent)
                state.lastOutageText = formatted(lastEvent)
                let duration = lastEvent.durationSeconds ?? 0
                notify(
                    title: "Połączenie LAN przywrócone",
                    message: "Brama \(gateway ?? "") znów odpowiada po \(formatDuration(duration))."
                )
            }
            isOnline = true
            state.isOnline = true
            state.latencyMs = latencyMs
            updateIcon(online: true)
        } else {
            if isOnline {
                outageHistory.append(OutageEvent(start: now, end: nil))
                if outageHistory.count > maxHistoryEntries {
                    outageHistory.removeFirst()
                }
                notify(
                    title: "Przerwa w sieci LAN",
                    message: "Brak odpowiedzi od bramy \(gateway ?? "nieznana")."
                )
            }
            isOnline = false
            state.isOnline = false
            state.latencyMs = nil
            updateIcon(online: false)
        }
    }

    // MARK: - Throughput

    private func startThroughputMonitoring() {
        throughputTimer = Timer.scheduledTimer(withTimeInterval: throughputInterval, repeats: true) { [weak self] _ in
            self?.sampleThroughput()
        }
    }

    private func sampleThroughput() {
        guard let iface = interfaceDevice else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let sample = self.throughputMonitor.sample(interface: iface) else { return }
            DispatchQueue.main.async {
                self.state.downloadMbps = sample.downloadMbps
                self.state.uploadMbps = sample.uploadMbps
            }
        }
    }

    // MARK: - UI helpers

    private func updateIcon(online: Bool) {
        guard let button = statusItem.button else { return }
        let color: NSColor = online ? .systemGreen : .systemRed
        button.image = Self.makeStatusDot(color: color)
        button.title = ""
    }

    /// Draws a filled, white-outlined circle for the menu bar status item —
    /// more legible against varying menu bar backgrounds than a plain dot.
    private static func makeStatusDot(color: NSColor, diameter: CGFloat = 14, borderWidth: CGFloat = 1.5) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            let circleRect = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = NSBezierPath(ovalIn: circleRect)
            color.setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func formatted(_ event: OutageEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        let start = formatter.string(from: event.start)
        if let end = event.end, let duration = event.durationSeconds {
            return "\(start) → \(formatter.string(from: end))  (\(formatDuration(duration)))"
        }
        return "\(start) → trwa..."
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    // MARK: - Logging

    private func ensureLogHeader() {
        guard !FileManager.default.fileExists(atPath: logFileURL.path) else { return }
        let header = "start,end,duration_seconds\n"
        try? header.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private func appendToLog(_ event: OutageEvent) {
        let iso = ISO8601DateFormatter()
        let startStr = iso.string(from: event.start)
        let endStr = event.end.map { iso.string(from: $0) } ?? ""
        let duration = event.durationSeconds ?? 0
        let line = "\(startStr),\(endStr),\(String(format: "%.1f", duration))\n"

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    // MARK: - Notifications

    private func notify(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
    }
}
