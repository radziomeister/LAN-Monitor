import SwiftUI

struct StatusDropdownView: View {
    @EnvironmentObject private var state: MonitorState

    var onOpenLog: () -> Void
    var onOpenSettings: () -> Void
    var onRedetect: () -> Void
    var onQuit: () -> Void
    var onStartSpeedTest: () -> Void
    var onCancelSpeedTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pingowanie na żywo")
                        .font(.subheadline).bold()
                    Spacer()
                    speedLabel(systemImage: "arrow.down", value: state.downloadMbps, color: .blue)
                    speedLabel(systemImage: "arrow.up", value: state.uploadMbps, color: .orange)
                }
                PingSparkline(samples: state.recentPings)
                    .frame(height: 32)
                lastPingRow
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text("Informacje o połączeniu")
                    .font(.subheadline).bold()
                infoRow("Brama", state.gateway ?? "nie wykryto")
                infoRow("Adres IP", state.localIP ?? "—")
                infoRow("Usługa sieciowa", state.serviceName ?? "—")
                infoRow("DNS", state.dnsServers.isEmpty ? "—" : state.dnsServers.joined(separator: ", "))
                infoRow("Ostatnia przerwa", state.lastOutageText)
            }

            Divider()

            speedTestSection

            Divider()

            VStack(spacing: 3) {
                Button(action: onOpenLog) {
                    Label("Otwórz plik logów", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onRedetect) {
                    Label("Wykryj bramę ponownie", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onOpenSettings) {
                    Label("Ustawienia…", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onQuit) {
                    Label("Zakończ", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 290)
    }

    @ViewBuilder
    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Test łącza")
                .font(.subheadline).bold()

            switch state.speedTestPhase {
            case .idle:
                Button("Rozpocznij test (~30 s)", action: onStartSpeedTest)
                    .frame(maxWidth: .infinity)

            case .downloading, .uploading:
                let isDown = state.speedTestPhase == .downloading
                HStack {
                    Text(isDown ? "Pobieranie…" : "Wysyłanie…")
                        .font(.callout).bold()
                    Spacer()
                    Text(String(format: "%.1f Mb/s", state.speedTestCurrentMbps))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isDown ? .blue : .orange)
                }
                ProgressView(value: min(state.speedTestElapsed, 15), total: 15)
                    .tint(isDown ? .blue : .orange)
                Button("Anuluj", action: onCancelSpeedTest)
                    .frame(maxWidth: .infinity)

            case .done:
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pobieranie").font(.caption2).foregroundStyle(.secondary)
                        resultRow("Maks.", state.speedTestMaxDownloadMbps, .blue)
                        resultRow("Śr.", state.speedTestAvgDownloadMbps, .blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wysyłanie").font(.caption2).foregroundStyle(.secondary)
                        resultRow("Maks.", state.speedTestMaxUploadMbps, .orange)
                        resultRow("Śr.", state.speedTestAvgUploadMbps, .orange)
                    }
                }
                Button("Testuj ponownie", action: onStartSpeedTest)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func resultRow(_ label: String, _ mbps: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%.0f Mb/s", mbps))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private var statusHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(state.isOnline ? Color.green : Color.red)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isOnline ? "Online" : "Brak połączenia")
                    .font(.title3).bold()
                if let latency = state.latencyMs, state.isOnline {
                    Text(String(format: "%.0f ms", latency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var lastPingRow: some View {
        HStack {
            if let last = state.recentPings.last {
                Text("Ostatni pomiar: \(Self.timeFormatter.string(from: last.timestamp))")
                    .foregroundStyle(.secondary)
                Spacer()
                if let ms = last.latencyMs {
                    Text(String(format: "%.0f ms", ms))
                } else {
                    Text("timeout").foregroundStyle(.red)
                }
            } else {
                Text("Zbieranie danych…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
    }

    private func speedLabel(systemImage: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(String(format: value < 10 ? "%.2f" : "%.1f", value) + " Mb/s")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(color)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

private struct PingSparkline: View {
    let samples: [PingSample]

    var body: some View {
        GeometryReader { geo in
            let maxLatency = max(samples.compactMap(\.latencyMs).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(samples) { sample in
                    let heightFraction = sample.latencyMs.map { max($0 / maxLatency, 0.08) } ?? 1.0
                    RoundedRectangle(cornerRadius: 1)
                        .fill(sample.latencyMs == nil ? Color.red : Color.green)
                        .frame(height: geo.size.height * heightFraction)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }
}
