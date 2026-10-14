import Foundation

enum SpeedTestPhase: Equatable {
    case idle
    case downloading
    case uploading
    case done
}

struct SpeedTestResult {
    let maxDownloadMbps: Double
    let avgDownloadMbps: Double
    let maxUploadMbps: Double
    let avgUploadMbps: Double
}

/// Runs a real-traffic bandwidth test against Cloudflare's public speed-test endpoints
/// (the same ones used by speed.cloudflare.com): ~15s of sustained download followed by
/// ~15s of sustained upload, sampling instantaneous throughput every ~300ms to find peak
/// and average speed in each direction. This consumes real data, unlike the passive
/// interface-counter throughput readout shown elsewhere in the app.
final class SpeedTestController: NSObject {
    var onPhaseChange: ((SpeedTestPhase) -> Void)?
    var onProgress: ((SpeedTestPhase, Double, Double) -> Void)? // phase, currentMbps, elapsedInPhase
    var onComplete: ((SpeedTestResult) -> Void)?

    private let phaseDuration: TimeInterval = 15
    private let sampleInterval: TimeInterval = 0.3
    // Cloudflare's __down endpoint silently returns ~0 bytes above ~75-100MB per request,
    // so requests loop with a safely smaller chunk size instead of one huge request.
    private let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!
    private let uploadURL = URL(string: "https://speed.cloudflare.com/__up")!
    private lazy var uploadBody = Data(count: 100_000_000)

    private var session: URLSession?
    private var currentTask: URLSessionTask?
    private var phaseTimer: Timer?
    private var isCancelled = false

    private var phase: SpeedTestPhase = .idle
    private var phaseStartTime = Date()
    private var lastSampleTime = Date()
    private var bytesSinceLastSample: Int64 = 0
    private var lastUploadTotalSent: Int64 = 0

    private var downloadSamples: [Double] = []
    private var uploadSamples: [Double] = []
    private var partialMaxDownload = 0.0
    private var partialAvgDownload = 0.0

    func start() {
        isCancelled = false
        downloadSamples = []
        uploadSamples = []
        let config = URLSessionConfiguration.ephemeral
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        beginDownloadPhase()
    }

    func cancel() {
        isCancelled = true
        phaseTimer?.invalidate()
        currentTask?.cancel()
        session?.invalidateAndCancel()
        phase = .idle
    }

    // MARK: - Download phase

    private func beginDownloadPhase() {
        phase = .downloading
        DispatchQueue.main.async { [weak self] in self?.onPhaseChange?(.downloading) }
        phaseStartTime = Date()
        lastSampleTime = phaseStartTime
        bytesSinceLastSample = 0
        armPhaseTimer()
        fireDownloadRequest()
    }

    private func fireDownloadRequest() {
        guard !isCancelled else { return }
        guard Date().timeIntervalSince(phaseStartTime) < phaseDuration else {
            finishDownloadPhase()
            return
        }
        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 20
        let task = session!.dataTask(with: request)
        currentTask = task
        task.resume()
    }

    private func finishDownloadPhase() {
        partialMaxDownload = downloadSamples.max() ?? 0
        partialAvgDownload = downloadSamples.isEmpty ? 0 : downloadSamples.reduce(0, +) / Double(downloadSamples.count)
        beginUploadPhase()
    }

    // MARK: - Upload phase

    private func beginUploadPhase() {
        guard !isCancelled else { return }
        phase = .uploading
        DispatchQueue.main.async { [weak self] in self?.onPhaseChange?(.uploading) }
        phaseStartTime = Date()
        lastSampleTime = phaseStartTime
        lastUploadTotalSent = 0
        armPhaseTimer()
        fireUploadRequest()
    }

    private func fireUploadRequest() {
        guard !isCancelled else { return }
        guard Date().timeIntervalSince(phaseStartTime) < phaseDuration else {
            finishUploadPhase()
            return
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        lastUploadTotalSent = 0
        let task = session!.uploadTask(with: request, from: uploadBody)
        currentTask = task
        task.resume()
    }

    private func finishUploadPhase() {
        let maxU = uploadSamples.max() ?? 0
        let avgU = uploadSamples.isEmpty ? 0 : uploadSamples.reduce(0, +) / Double(uploadSamples.count)
        phase = .done
        let result = SpeedTestResult(
            maxDownloadMbps: partialMaxDownload,
            avgDownloadMbps: partialAvgDownload,
            maxUploadMbps: maxU,
            avgUploadMbps: avgU
        )
        DispatchQueue.main.async { [weak self] in
            self?.onPhaseChange?(.done)
            self?.onComplete?(result)
        }
    }

    // MARK: - Timing

    /// Forces the in-flight request to end once the phase's time budget is up; the resulting
    /// completion callback re-checks elapsed time and transitions to the next phase.
    private func armPhaseTimer() {
        phaseTimer?.invalidate()
        let timer = Timer(timeInterval: phaseDuration, repeats: false) { [weak self] _ in
            self?.currentTask?.cancel()
        }
        RunLoop.main.add(timer, forMode: .common)
        phaseTimer = timer
    }
}

extension SpeedTestController: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard phase == .downloading, !isCancelled else { return }
        bytesSinceLastSample += Int64(data.count)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        if elapsed >= sampleInterval {
            let mbps = Double(bytesSinceLastSample) * 8 / elapsed / 1_000_000
            downloadSamples.append(mbps)
            let totalElapsed = now.timeIntervalSince(phaseStartTime)
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(.downloading, mbps, totalElapsed)
            }
            bytesSinceLastSample = 0
            lastSampleTime = now
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard phase == .uploading, !isCancelled else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSampleTime)
        if elapsed >= sampleInterval {
            let deltaBytes = totalBytesSent - lastUploadTotalSent
            let mbps = Double(deltaBytes) * 8 / elapsed / 1_000_000
            uploadSamples.append(mbps)
            let totalElapsed = now.timeIntervalSince(phaseStartTime)
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(.uploading, mbps, totalElapsed)
            }
            lastUploadTotalSent = totalBytesSent
            lastSampleTime = now
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isCancelled else { return }
        if phase == .downloading {
            fireDownloadRequest()
        } else if phase == .uploading {
            fireUploadRequest()
        }
    }
}
