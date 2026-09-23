import Foundation

// MARK: - Providers and models

public struct AIModelOption: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let blurb: String
}

public enum AIProvider: String, CaseIterable, Sendable, Identifiable {
    case anthropic
    case openAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openAI:    return "OpenAI"
        }
    }

    public var suggestedModels: [AIModelOption] {
        switch self {
        case .anthropic:
            return [
                AIModelOption(id: "claude-opus-5", name: "Opus 5", blurb: "Deepest, most insightful reflection"),
                AIModelOption(id: "claude-sonnet-5", name: "Sonnet 5", blurb: "Fast and thoughtful, lower cost"),
                AIModelOption(id: "claude-haiku-4-5", name: "Haiku 4.5", blurb: "Quickest replies, lowest cost"),
            ]
        case .openAI:
            return [
                AIModelOption(id: "gpt-4o-mini", name: "GPT-4o mini", blurb: "Fast and cheap"),
                AIModelOption(id: "gpt-4o", name: "GPT-4o", blurb: "Smarter, slower"),
            ]
        }
    }

    public var defaultModel: String { suggestedModels[0].id }

    public var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openAI:    return "sk-..."
        }
    }

    public var keyConsoleURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI:    return URL(string: "https://platform.openai.com/api-keys")!
        }
    }
}

// MARK: - Conversation

public struct ChatTurn: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIRequest: Sendable {
    public var provider: AIProvider
    public var model: String
    public var apiKey: String
    public var system: String
    public var turns: [ChatTurn]
    public var maxTokens: Int

    public init(provider: AIProvider, model: String, apiKey: String, system: String, turns: [ChatTurn], maxTokens: Int = 16_000) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.system = system
        self.turns = turns
        self.maxTokens = maxTokens
    }
}

public enum AIError: LocalizedError, Equatable {
    case missingKey(AIProvider)
    case http(provider: AIProvider, status: Int, message: String?)
    case refused
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let p):
            return "No \(p.displayName) API key set. Add it in Settings."
        case .http(let p, let status, let message):
            if status == 401 { return "\(p.displayName) rejected the API key. Check it in Settings." }
            if status == 429 { return "\(p.displayName) is rate-limiting requests. Try again in a moment." }
            return "\(p.displayName) returned an error (HTTP \(status))" + (message.map { ": \($0)" } ?? ".")
        case .refused:
            return "The model declined to respond to this entry."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

public enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case done
    case refusal
    case failure(String)
}

// MARK: - Wire format

public enum AIWire {

    static let anthropicVersion = "2023-06-01"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    public static func urlRequest(for req: AIRequest) throws -> URLRequest {
        guard !req.apiKey.isEmpty else { throw AIError.missingKey(req.provider) }
        let messages = req.turns.map { ["role": $0.role.rawValue, "content": $0.text] }
        var body: [String: Any]
        var request: URLRequest

        switch req.provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(req.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            body = [
                "model": req.model,
                "max_tokens": req.maxTokens,
                "system": req.system,
                "messages": messages,
                "stream": true,
            ]
            if supportsEffort(req.model) {
                // Conversational replies don't need deep deliberation; medium keeps them quick.
                body["output_config"] = ["effort": "medium"]
            }
            if req.model == "claude-opus-5" {
                request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
                body["fallbacks"] = "default"
            }
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(req.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": req.model,
                "messages": [["role": "system", "content": req.system]] + messages,
                "stream": true,
            ]
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.timeoutInterval = 120
        return request
    }

    public static func keyCheckRequest(provider: AIProvider, key: String) -> URLRequest {
        switch provider {
        case .anthropic:
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
            return request
        case .openAI:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    /// Interprets one line of a server-sent-event stream. Returns nil for lines that carry nothing to show.
    public static func parse(line: String, provider: AIProvider) -> AIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let error = json["error"] as? [String: Any] {
            return .failure(error["message"] as? String ?? "Unknown error")
        }

        switch provider {
        case .anthropic:
            switch json["type"] as? String {
            case "content_block_delta":
                let delta = json["delta"] as? [String: Any]
                guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String else { return nil }
                return .text(text)
            case "message_delta":
                let delta = json["delta"] as? [String: Any]
                return delta?["stop_reason"] as? String == "refusal" ? .refusal : nil
            case "message_stop":
                return .done
            default:
                return nil
            }
        case .openAI:
            let choice = (json["choices"] as? [[String: Any]])?.first
            if let text = (choice?["delta"] as? [String: Any])?["content"] as? String, !text.isEmpty {
                return .text(text)
            }
            return nil
        }
    }

    public static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func supportsEffort(_ model: String) -> Bool {
        model.hasPrefix("claude-") && !model.hasPrefix("claude-haiku")
    }
}

// MARK: - Client

public struct AIClient: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Streams reply text as it is generated.
    public func stream(_ req: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try AIWire.urlRequest(for: req)
                    let (bytes, response) = try await session.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw AIError.http(provider: req.provider, status: status, message: AIWire.errorMessage(from: body))
                    }
                    for try await line in bytes.lines {
                        switch AIWire.parse(line: line, provider: req.provider) {
                        case .text(let text): continuation.yield(text)
                        case .done: continuation.finish(); return
                        case .refusal: throw AIError.refused
                        case .failure(let message): throw AIError.network(message)
                        case nil: continue
                        }
                    }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func complete(_ req: AIRequest) async throws -> String {
        var text = ""
        for try await chunk in stream(req) { text += chunk }
        return text
    }

    public func validateKey(provider: AIProvider, key: String) async -> Result<Void, AIError> {
        do {
            let (data, response) = try await session.data(for: AIWire.keyCheckRequest(provider: provider, key: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
                ? .success(())
                : .failure(.http(provider: provider, status: status, message: AIWire.errorMessage(from: data)))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
