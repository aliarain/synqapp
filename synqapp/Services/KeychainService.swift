
//  KeychainService.swift
//  SynqApp — secure API key storage in the system Keychain
//  Never store API keys in UserDefaults or AppStorage

import Foundation
import Security

enum KeychainKey: String {
    case openAIKey      = "com.synqapp.openai.apikey"
    case livekitURL     = "com.synqapp.livekit.url"
    case livekitToken   = "com.synqapp.livekit.tokenurl"
}

final class KeychainService {

    static let shared = KeychainService()
    private init() {}

    // MARK: - Save

    @discardableResult
    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing first
        delete(key)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key.rawValue,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlocked
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Load

    func load(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key.rawValue,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Delete

    @discardableResult
    func delete(_ key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrAccount as String:  key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Convenience

    var openAIKey: String? { load(.openAIKey) }
    var livekitURL: String? { load(.livekitURL) }
    var livekitTokenURL: String? { load(.livekitToken) }

    var hasOpenAIKey: Bool { !(openAIKey?.isEmpty ?? true) }
    var hasLiveKitConfig: Bool {
        !(livekitURL?.isEmpty ?? true) && !(livekitTokenURL?.isEmpty ?? true)
    }
}
