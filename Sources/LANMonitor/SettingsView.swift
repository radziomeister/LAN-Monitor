import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            NetworkSettingsView()
                .tabItem { Label("Sieć", systemImage: "network") }
            VPNSettingsView()
                .tabItem { Label("VPN", systemImage: "lock.shield") }
        }
        .frame(width: 500, height: 480)
    }
}

// MARK: - Network tab

struct NetworkSettingsView: View {
    @State private var services: [String] = []
    @State private var selectedService = ""
    @State private var isDHCP = true
    @State private var ip = ""
    @State private var subnet = "255.255.255.0"
    @State private var router = ""
    @State private var dnsText = ""
    @State private var statusMessage = ""
    @State private var isWorking = false

    private let manager = NetworkSettingsManager()

    var body: some View {
        Form {
            Section {
                Picker("Interfejs sieciowy", selection: $selectedService) {
                    ForEach(services, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: selectedService) { _ in reload() }
            }

            Section {
                Picker("Tryb", selection: $isDHCP) {
                    Text("Automatyczny (DHCP)").tag(true)
                    Text("Ręczny").tag(false)
                }
                .pickerStyle(.segmented)

                TextField("Adres IP", text: $ip)
                    .disabled(isDHCP)
                TextField("Maska podsieci", text: $subnet)
                    .disabled(isDHCP)
                TextField("Brama (Router)", text: $router)
                    .disabled(isDHCP)
                TextField("Serwery DNS (oddzielone przecinkami)", text: $dnsText)
            }

            Section {
                HStack {
                    Button("Odśwież") { reload() }
                    Spacer()
                    Button(isWorking ? "Zapisywanie…" : "Zastosuj") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || selectedService.isEmpty)
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Zmiana ustawień poprosi o hasło administratora (jak w Ustawieniach systemowych).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            services = manager.listServices()
            if let active = manager.activeServiceName(), services.contains(active) {
                selectedService = active
            } else {
                selectedService = services.first ?? ""
            }
            reload()
        }
    }

    private func reload() {
        guard !selectedService.isEmpty else { return }
        let info = manager.info(for: selectedService)
        isDHCP = info.isDHCP
        ip = info.ipAddress ?? ""
        subnet = info.subnetMask ?? "255.255.255.0"
        router = info.router ?? ""
        dnsText = info.dnsServers.joined(separator: ", ")
        statusMessage = ""
    }

    private func apply() {
        isWorking = true
        statusMessage = ""
        let service = selectedService
        let dhcp = isDHCP
        let ipVal = ip
        let subnetVal = subnet
        let routerVal = router
        let dnsServers = dnsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if dhcp {
                    try manager.setDHCP(service: service)
                } else {
                    try manager.setManual(service: service, ip: ipVal, subnet: subnetVal, router: routerVal)
                }
                try manager.setDNS(service: service, servers: dnsServers)
                DispatchQueue.main.async {
                    statusMessage = "Ustawienia zapisane."
                    isWorking = false
                    reload()
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Błąd: \(error.localizedDescription)"
                    isWorking = false
                }
            }
        }
    }
}

// MARK: - VPN tab

struct VPNSettingsView: View {
    @State private var name = "Moje VPN"
    @State private var server = ""
    @State private var remoteID = ""
    @State private var localID = ""
    @State private var useSharedSecret = true
    @State private var sharedSecret = ""
    @State private var useUserPass = true
    @State private var username = ""
    @State private var password = ""
    @State private var statusMessage = ""

    @State private var configuredServices: [ConfiguredVPNService] = []
    private let vpn = VPNController()

    var body: some View {
        Form {
            Section("Nowy profil IKEv2") {
                TextField("Nazwa profilu", text: $name)
                TextField("Adres serwera (host lub IP)", text: $server)
                TextField("Remote ID (domyślnie = adres serwera)", text: $remoteID)
                TextField("Local ID (opcjonalnie)", text: $localID)

                Toggle("Shared Secret (PSK)", isOn: $useSharedSecret)
                if useSharedSecret {
                    SecureField("Shared Secret", text: $sharedSecret)
                }

                Toggle("Nazwa użytkownika i hasło", isOn: $useUserPass)
                if useUserPass {
                    TextField("Nazwa użytkownika", text: $username)
                    SecureField("Hasło", text: $password)
                }

                Button("Zainstaluj profil VPN…") { install() }
                    .disabled(server.isEmpty || name.isEmpty)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Otworzy się okno instalatora profilu macOS — potwierdź je i podaj hasło administratora.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Skonfigurowane VPN") {
                if configuredServices.isEmpty {
                    Text("Brak skonfigurowanych połączeń VPN.")
                        .foregroundStyle(.secondary)
                }
                ForEach(configuredServices, id: \.name) { svc in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(svc.name).bold()
                            Text("\(svc.type) — \(svc.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Połącz") { vpn.start(service: svc.name); refreshServices() }
                        Button("Rozłącz") { vpn.stop(service: svc.name); refreshServices() }
                    }
                }
                Button("Odśwież listę") { refreshServices() }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshServices() }
    }

    private func refreshServices() {
        configuredServices = vpn.listServices()
    }

    private func install() {
        if useUserPass, !username.isEmpty, !password.isEmpty {
            KeychainHelper.save(service: "LANMonitor.VPN.\(name)", account: username, password: password)
        }
        let input = VPNProfileGenerator.Input(
            name: name,
            serverAddress: server,
            remoteID: remoteID.isEmpty ? server : remoteID,
            localID: localID.isEmpty ? nil : localID,
            useSharedSecret: useSharedSecret,
            sharedSecret: sharedSecret.isEmpty ? nil : sharedSecret,
            useUsernamePassword: useUserPass,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
        do {
            let url = try VPNProfileGenerator.generate(input)
            NSWorkspace.shared.open(url)
            statusMessage = "Otwieram instalator profilu — potwierdź w Ustawieniach systemowych."
        } catch {
            statusMessage = "Błąd: \(error.localizedDescription)"
        }
    }
}
