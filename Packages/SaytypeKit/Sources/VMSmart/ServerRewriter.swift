import Foundation
import VMCore

/// Rewrites with a model served on this Mac: Ollama through its native API, LM Studio through
/// its OpenAI-compatible one.
public struct ServerRewriter: Sendable {
    public enum API: Sendable {
        /// `POST /api/chat`, `GET /api/tags`.
        case ollama
        /// `POST /v1/chat/completions`, `GET /v1/models`.
        case openAI
    }

    public enum Failure: LocalizedError, Equatable {
        case badURL
        case noModel
        case status(Int, String)

        public var errorDescription: String? {
            switch self {
            case .badURL: "Invalid server address"
            case .noModel: "No model selected"
            case .status(let code, let message): message.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(message)"
            }
        }
    }

    public let api: API
    public let base: URL?
    public let model: String
    /// How long Ollama keeps the model in memory after a request.
    public var keepAlive = "30m"

    public init(api: API, url: String, model: String) {
        self.api = api
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        base = URL(string: withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme)
        self.model = model
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    // MARK: Models

    /// Names of the chat models the server has, without embedding models.
    public func models(timeout: TimeInterval = 3) async throws -> [String] {
        switch api {
        case .ollama:
            struct Tags: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let tags: Tags = try await get("api/tags", timeout: timeout)
            return tags.models.map(\.name).filter { !$0.localizedCaseInsensitiveContains("embed") }
        case .openAI:
            struct List: Decodable {
                struct Model: Decodable { let id: String }
                let data: [Model]
            }
            let list: List = try await get("v1/models", timeout: timeout)
            return list.data.map(\.id).filter { !$0.localizedCaseInsensitiveContains("embed") }
        }
    }

    /// Loads the model into the server's memory, so the first dictation does not wait for it.
    public func preload() async throws {
        guard !model.isEmpty else { throw Failure.noModel }
        switch api {
        case .ollama:
            // An empty message list only loads the model.
            let body: [String: Any] = ["model": model, "messages": [[String: String]](), "keep_alive": keepAlive]
            _ = try await post("api/chat", body: body, timeout: 120)
        case .openAI:
            // LM Studio loads a model on its first request.
            let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": "OK"]], "max_tokens": 1, "temperature": 0, "stream": false]
            _ = try await post("v1/chat/completions", body: body, timeout: 120)
        }
    }

    // MARK: Rewrite

    public func rewrite(_ text: String, request: RewriteRequest, timeout: TimeInterval = 60) async throws -> RewriteGeneration {
        guard !model.isEmpty else { throw Failure.noModel }
        let messages = [["role": "system", "content": request.systemPrompt(for: text)], ["role": "user", "content": request.userMessage(text)]]
        let limit = request.maxTokens(inputTokens: RewriteRequest.estimatedTokens(text))
        let start = Date.timeIntervalSinceReferenceDate
        switch api {
        case .ollama:
            var body: [String: Any] = [
                "model": model, "messages": messages, "stream": false, "think": false, "keep_alive": keepAlive,
                "options": ["temperature": 0, "num_predict": limit],
            ]
            var data: Data
            do {
                data = try await post("api/chat", body: body, timeout: timeout)
            } catch Failure.status(400, let message) where message.localizedCaseInsensitiveContains("think") {
                // Older servers and some models refuse the thinking switch.
                body["think"] = nil
                data = try await post("api/chat", body: body, timeout: timeout)
            }
            struct Response: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
                let done_reason: String?
                let prompt_eval_count: Int?
                let eval_count: Int?
                let eval_duration: Int64?
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            let total = Date.timeIntervalSinceReferenceDate - start
            let generation = Double(response.eval_duration ?? 0) / 1e9
            return RewriteGeneration(
                text: response.message.content,
                promptTokens: response.prompt_eval_count ?? 0,
                generatedTokens: response.eval_count ?? 0,
                timeToFirstToken: max(0, total - generation),
                generationSeconds: generation,
                truncated: response.done_reason == "length"
            )
        case .openAI:
            let body: [String: Any] = ["model": model, "messages": messages, "temperature": 0, "max_tokens": limit, "stream": false]
            let data = try await post("v1/chat/completions", body: body, timeout: timeout)
            struct Response: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message
                    let finish_reason: String?
                }
                struct Usage: Decodable {
                    let prompt_tokens: Int?
                    let completion_tokens: Int?
                }
                let choices: [Choice]
                let usage: Usage?
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            let total = Date.timeIntervalSinceReferenceDate - start
            return RewriteGeneration(
                text: response.choices.first?.message.content ?? "",
                promptTokens: response.usage?.prompt_tokens ?? 0,
                generatedTokens: response.usage?.completion_tokens ?? 0,
                timeToFirstToken: total,
                truncated: response.choices.first?.finish_reason == "length"
            )
        }
    }

    // MARK: HTTP

    private func url(_ path: String) throws -> URL {
        guard let base, base.scheme?.hasPrefix("http") == true, base.host() != nil else { throw Failure.badURL }
        return base.appending(path: path)
    }

    private func get<T: Decodable>(_ path: String, timeout: TimeInterval) async throws -> T {
        var request = URLRequest(url: try url(path), timeoutInterval: timeout)
        request.httpMethod = "GET"
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ path: String, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: try url(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Cancelling the task closes the connection; both servers stop generating then.
        let (data, response) = try await Self.session.data(for: request)
        try Self.check(response, data: data)
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (object?["error"] as? String)
                ?? ((object?["error"] as? [String: Any])?["message"] as? String)
                ?? ""
            throw Failure.status(http.statusCode, message)
        }
    }
}
