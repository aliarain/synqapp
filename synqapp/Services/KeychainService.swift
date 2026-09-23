//  KeychainService.swift
//  SynqApp — API keys live in the system Keychain, never in UserDefaults

import Foundation
import Security
import SynqCore

final class KeychainService {

    static let shared = KeychainService()
    private init() {}

    private func account(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return "com.synqapp.anthropic.apikey"
        case .openAI:    return "com.synqapp.openai.apikey"
        }
    }

    func apiKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    func hasKey(for provider: AIProvider) -> Bool { apiKey(for: provider) != nil }

    @discardableResult
    func setAPIKey(_ key: String, for provider: AIProvider) -> Bool {
        let base: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account(for: provider),
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
