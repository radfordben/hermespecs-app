/*
 * OpenClaw Device Identity
 * Ed25519 密钥对生成、存储和签名
 * 用于 Gateway node 模式的设备认证
 */

import Foundation
import CryptoKit
import Security

struct OpenClawDeviceIdentity {
    let deviceId: String       // SHA256(publicKey raw) hex
    let publicKeyBase64Url: String  // raw 32-byte Ed25519 public key, base64url
    let privateKey: Curve25519.Signing.PrivateKey

    // MARK: - Sign connect payload (v3 format)

    func sign(
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String?,
        nonce: String,
        platform: String,
        deviceFamily: String?
    ) -> String {
        let scopeStr = scopes.joined(separator: ",")
        let tokenStr = token ?? ""
        let platformStr = normalizeForAuth(platform)
        let deviceFamilyStr = normalizeForAuth(deviceFamily)

        let payload = [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopeStr,
            String(signedAtMs),
            tokenStr,
            nonce,
            platformStr,
            deviceFamilyStr
        ].joined(separator: "|")

        let payloadData = Data(payload.utf8)
        guard let signature = try? privateKey.signature(for: payloadData) else {
            return ""
        }
        return base64UrlEncode(Data(signature))
    }

    // MARK: - Helpers

    private func normalizeForAuth(_ value: String?) -> String {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !v.isEmpty else { return "" }
        // Only allow [a-z0-9._-]
        return String(v.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) ||
            $0 == "." || $0 == "_" || $0 == "-"
        })
    }
}

// MARK: - Identity Store

class OpenClawDeviceIdentityStore {
    private static let keychainService = "com.smartview.glassai.openclaw.device"
    private static let privateKeyAccount = "ed25519_private_key"

    static func loadOrCreate() -> OpenClawDeviceIdentity {
        // Try to load existing
        if let privateKeyData = loadFromKeychain() {
            if let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) {
                return makeIdentity(from: privateKey)
            }
        }

        // Generate new
        let privateKey = Curve25519.Signing.PrivateKey()
        saveToKeychain(privateKey.rawRepresentation)
        return makeIdentity(from: privateKey)
    }

    private static func makeIdentity(from privateKey: Curve25519.Signing.PrivateKey) -> OpenClawDeviceIdentity {
        let publicKeyRaw = privateKey.publicKey.rawRepresentation
        let deviceId = SHA256.hash(data: publicKeyRaw)
            .map { String(format: "%02x", $0) }
            .joined()
        let publicKeyBase64Url = base64UrlEncode(publicKeyRaw)

        return OpenClawDeviceIdentity(
            deviceId: deviceId,
            publicKeyBase64Url: publicKeyBase64Url,
            privateKey: privateKey
        )
    }

    private static func loadFromKeychain() -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: privateKeyAccount,
            kSecReturnData: true
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func saveToKeychain(_ data: Data) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: privateKeyAccount
        ] as CFDictionary)

        SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: privateKeyAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ] as CFDictionary, nil)
    }
}

// MARK: - Base64URL helpers

func base64UrlEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
