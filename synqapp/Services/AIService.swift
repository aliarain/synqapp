
//  AIService.swift
//  SynqApp — OpenAI chat completions for text-based Reflect
//  Uses the user's own API key stored in Keychain

import Foundation

// MARK: - Models

struct AIMessage: Codable {
    let role: String
    let content: String
}

struct AIRequest: Codable {
    let model: String
    let messages: [AIMessage]
    let stream: Bool
    let max_tokens: Int
    let temperature: Double
}

struct AIChoice: Codable {
    struct Delta: Codable { let content: String? }
    struct Message: Codable { let content: String? }
    let delta: Delta?
    let message: Message?
    let finish_reason: String?
}

struct AIStreamChunk: Codable {
    let choices: [AIChoice]
}

struct AIResponse: Codable {
    let choices: [AIChoice]
}

// MARK: - Errors

enum AIError: LocalizedError {
    case noAPIKey
    case invalidResponse(Int)
    case decodingFailed
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key set. Add it in Settings."
        case .invalidResponse(let code):
            return code == 401
                ? "Invalid API key. Check your key in Settings."
                : "OpenAI returned an error (HTTP \(code))."
        case .decodingFailed:
            return "Couldn't parse the AI response."
        case .network(let e):
            return "Network error: \(e.localizedDescription)"
        }
    }
}

// MARK: - AIService

final class AIService {

    static let shared = AIService()
    private init() {}

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Streaming chat (for Reflect text mode)

    /// Streams tokens back via `onToken`; calls `onDone` when finished.
    func streamReflect(
        context: String,
        model: String = "gpt-4o-mini",
        onToken: @escaping (String) -> Void,
        onDone: @escaping (Result<Void, AIError>) -> Void
    ) {
        guard let key = KeychainService.shared.openAIKey, !key.isEmpty else {
            onDone(.failure(.noAPIKey))
            return
        }

        let messages: [AIMessage] = [
            AIMessage(role: "system", content: ReflectionService.aiSystemPrompt),
            AIMessage(role: "user", content: context)
        ]

        let body = AIRequest(
            model: model,
            messages: messages,
            stream: true,
            max_tokens: 1024,
            temperature: 0.85
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            onDone(.failure(.network(error)))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { onDone(.failure(.network(error))) }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                DispatchQueue.main.async { onDone(.failure(.invalidResponse(http.statusCode))) }
                return
            }

            guard let data else {
                DispatchQueue.main.async { onDone(.failure(.decodingFailed)) }
                return
            }

            // Parse SSE stream
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                guard line.hasPrefix("data: ") else { continue }
                let json = String(line.dropFirst(6))
                if json == "[DONE]" { break }
                guard let chunkData = json.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(AIStreamChunk.self, from: chunkData),
                      let token = chunk.choices.first?.delta?.content
                else { continue }
                DispatchQueue.main.async { onToken(token) }
            }

            DispatchQueue.main.async { onDone(.success(())) }
        }
        task.resume()
    }

    // MARK: - Single-shot (for quick use)

    func reflect(
        context: String,
        model: String = "gpt-4o-mini",
        completion: @escaping (Result<String, AIError>) -> Void
    ) {
        guard let key = KeychainService.shared.openAIKey, !key.isEmpty else {
            completion(.failure(.noAPIKey))
            return
        }

        let messages: [AIMessage] = [
            AIMessage(role: "system", content: ReflectionService.aiSystemPrompt),
            AIMessage(role: "user", content: context)
        ]

        let body = AIRequest(
            model: model,
            messages: messages,
            stream: false,
            max_tokens: 1024,
            temperature: 0.85
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(.network(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(.network(error))) }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                DispatchQueue.main.async { completion(.failure(.invalidResponse(http.statusCode))) }
                return
            }
            guard let data,
                  let decoded = try? JSONDecoder().decode(AIResponse.self, from: data),
                  let content = decoded.choices.first?.message?.content
            else {
                DispatchQueue.main.async { completion(.failure(.decodingFailed)) }
                return
            }
            DispatchQueue.main.async { completion(.success(content)) }
        }.resume()
    }
}
