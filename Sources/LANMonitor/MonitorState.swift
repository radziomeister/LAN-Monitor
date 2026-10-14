import Foundation
import Combine

struct PingSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let latencyMs: Double? // nil = timeout / failure
}

/// Shared, observable snapshot of live monitoring state, published by AppDelegate's
/// ping loop and consumed by the SwiftUI status dropdown.
final class MonitorState: ObservableObject {
    @Published var isOnline = true
    @Published var latencyMs: Double?
    @Published var gateway: String?
    @Published var localIP: String?
    @Published var serviceName: String?
    @Published var dnsServers: [String] = []
    @Published var recentPings: [PingSample] = []
    @Published var lastOutageText = "Brak przerw od uruchomienia"
    @Published var downloadMbps: Double = 0
    @Published var uploadMbps: Double = 0

    @Published var speedTestPhase: SpeedTestPhase = .idle
    @Published var speedTestElapsed: Double = 0
    @Published var speedTestCurrentMbps: Double = 0
    @Published var speedTestMaxDownloadMbps: Double = 0
    @Published var speedTestAvgDownloadMbps: Double = 0
    @Published var speedTestMaxUploadMbps: Double = 0
    @Published var speedTestAvgUploadMbps: Double = 0

    private let maxRecentPings = 40

    func addPingSample(_ sample: PingSample) {
        recentPings.append(sample)
        if recentPings.count > maxRecentPings {
            recentPings.removeFirst(recentPings.count - maxRecentPings)
        }
    }
}
