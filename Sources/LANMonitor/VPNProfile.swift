import Foundation

// Codable model matching Apple's Configuration Profile Reference for an IKEv2 VPN payload.
// Encoded to XML plist and installed via the system's Profile installer (no special app
// entitlements or paid developer account required).

struct IKEv2SecurityAssociationParameters: Encodable {
    var diffieHellmanGroup = 14
    var encryptionAlgorithm = "AES-256"
    var integrityAlgorithm = "SHA2-256"
    var lifeTimeInMinutes = 1440

    enum CodingKeys: String, CodingKey {
        case diffieHellmanGroup = "DiffieHellmanGroup"
        case encryptionAlgorithm = "EncryptionAlgorithm"
        case integrityAlgorithm = "IntegrityAlgorithm"
        case lifeTimeInMinutes = "LifeTimeInMinutes"
    }
}

struct IKEv2Settings: Encodable {
    var authenticationMethod: String
    var childSA = IKEv2SecurityAssociationParameters()
    var ikeSA = IKEv2SecurityAssociationParameters()
    var deadPeerDetectionRate = "Medium"
    var disableMOBIKE = 0
    var disableRedirect = 0
    var enablePFS = true
    var enableCertificateRevocationCheck = 0
    var localIdentifier: String?
    var remoteAddress: String
    var remoteIdentifier: String
    var useConfigurationAttributeInternalIPSubnet = 0
    var extendedAuthEnabled: Int
    var authName: String?
    var authPassword: String?
    var sharedSecret: Data?

    enum CodingKeys: String, CodingKey {
        case authenticationMethod = "AuthenticationMethod"
        case childSA = "ChildSecurityAssociationParameters"
        case ikeSA = "IKESecurityAssociationParameters"
        case deadPeerDetectionRate = "DeadPeerDetectionRate"
        case disableMOBIKE = "DisableMOBIKE"
        case disableRedirect = "DisableRedirect"
        case enablePFS = "EnablePFS"
        case enableCertificateRevocationCheck = "EnableCertificateRevocationCheck"
        case localIdentifier = "LocalIdentifier"
        case remoteAddress = "RemoteAddress"
        case remoteIdentifier = "RemoteIdentifier"
        case useConfigurationAttributeInternalIPSubnet = "UseConfigurationAttributeInternalIPSubnet"
        case extendedAuthEnabled = "ExtendedAuthEnabled"
        case authName = "AuthName"
        case authPassword = "AuthPassword"
        case sharedSecret = "SharedSecret"
    }
}

struct VPNIPv4Settings: Encodable {
    var overridePrimary = 1
    enum CodingKeys: String, CodingKey { case overridePrimary = "OverridePrimary" }
}

struct VPNProxiesSettings: Encodable {
    var httpEnable = 0
    var httpsEnable = 0
    enum CodingKeys: String, CodingKey {
        case httpEnable = "HTTPEnable"
        case httpsEnable = "HTTPSEnable"
    }
}

struct VPNPayload: Encodable {
    var ikev2: IKEv2Settings
    var ipv4 = VPNIPv4Settings()
    var proxies = VPNProxiesSettings()
    var payloadDescription = "Konfiguruje połączenie VPN"
    var payloadDisplayName: String
    var payloadIdentifier: String
    var payloadType = "com.apple.vpn.managed"
    var payloadUUID: String
    var payloadVersion = 1
    var userDefinedName: String
    var vpnType = "IKEv2"

    enum CodingKeys: String, CodingKey {
        case ikev2 = "IKEv2"
        case ipv4 = "IPv4"
        case proxies = "Proxies"
        case payloadDescription = "PayloadDescription"
        case payloadDisplayName = "PayloadDisplayName"
        case payloadIdentifier = "PayloadIdentifier"
        case payloadType = "PayloadType"
        case payloadUUID = "PayloadUUID"
        case payloadVersion = "PayloadVersion"
        case userDefinedName = "UserDefinedName"
        case vpnType = "VPNType"
    }
}

struct VPNConfigurationProfile: Encodable {
    var payloadContent: [VPNPayload]
    var payloadDisplayName: String
    var payloadIdentifier: String
    var payloadRemoveDisallowed = false
    var payloadType = "Configuration"
    var payloadUUID: String
    var payloadVersion = 1

    enum CodingKeys: String, CodingKey {
        case payloadContent = "PayloadContent"
        case payloadDisplayName = "PayloadDisplayName"
        case payloadIdentifier = "PayloadIdentifier"
        case payloadRemoveDisallowed = "PayloadRemoveDisallowed"
        case payloadType = "PayloadType"
        case payloadUUID = "PayloadUUID"
        case payloadVersion = "PayloadVersion"
    }
}

enum VPNProfileGenerator {
    struct Input {
        var name: String
        var serverAddress: String
        var remoteID: String
        var localID: String?
        var useSharedSecret: Bool
        var sharedSecret: String?
        var useUsernamePassword: Bool
        var username: String?
        var password: String?
    }

    enum GeneratorError: LocalizedError {
        case missingSharedSecret
        case missingCredentials

        var errorDescription: String? {
            switch self {
            case .missingSharedSecret: return "Podaj Shared Secret."
            case .missingCredentials: return "Podaj nazwę użytkownika i hasło."
            }
        }
    }

    /// Builds the .mobileconfig file and writes it to a temp location. Does not install it —
    /// the caller opens it with NSWorkspace to trigger the system Profile installer sheet.
    static func generate(_ input: Input) throws -> URL {
        if input.useSharedSecret, (input.sharedSecret ?? "").isEmpty {
            throw GeneratorError.missingSharedSecret
        }
        if input.useUsernamePassword, (input.username ?? "").isEmpty || (input.password ?? "").isEmpty {
            throw GeneratorError.missingCredentials
        }

        let payloadUUID = UUID().uuidString
        let profileUUID = UUID().uuidString

        var ike = IKEv2Settings(
            authenticationMethod: input.useSharedSecret ? "SharedSecret" : "None",
            remoteAddress: input.serverAddress,
            remoteIdentifier: input.remoteID,
            extendedAuthEnabled: input.useUsernamePassword ? 1 : 0
        )
        ike.localIdentifier = (input.localID?.isEmpty ?? true) ? nil : input.localID
        if input.useUsernamePassword {
            ike.authName = input.username
            ike.authPassword = input.password
        }
        if input.useSharedSecret, let secret = input.sharedSecret {
            ike.sharedSecret = Data(secret.utf8)
        }

        let payload = VPNPayload(
            ikev2: ike,
            payloadDisplayName: input.name,
            payloadIdentifier: "com.local.lanmonitor.vpn.\(payloadUUID)",
            payloadUUID: payloadUUID,
            userDefinedName: input.name
        )

        let profile = VPNConfigurationProfile(
            payloadContent: [payload],
            payloadDisplayName: "LAN Monitor VPN — \(input.name)",
            payloadIdentifier: "com.local.lanmonitor.vpnprofile.\(profileUUID)",
            payloadUUID: profileUUID
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(profile)

        let safeName = input.name.isEmpty ? "VPN" : input.name.replacingOccurrences(of: "/", with: "-")
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).mobileconfig")
        try data.write(to: fileURL)
        return fileURL
    }
}
