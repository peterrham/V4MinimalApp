//
//  OpenAIChatService.swift
//  V4MinimalApp
//
//  OpenAI Chat Completions service with SSE streaming
//

import Foundation

/// Error types for OpenAI API calls
enum OpenAIError: Error {
    case apiKeyNotConfigured
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case streamParsingFailed

    var localizedDescription: String {
        switch self {
        case .apiKeyNotConfigured:
            return "OpenAI API key not configured"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .streamParsingFailed:
            return "Failed to parse streaming response"
        }
    }
}

/// A single chat message for display in the log
struct ChatLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let role: String // "user" or "assistant"
    let content: String
}

/// Service for sending text to OpenAI Chat Completions API with SSE streaming
@MainActor
class OpenAIChatService: ObservableObject {

    // MARK: - Published State

    @Published var responseText: String = ""
    @Published var isStreaming: Bool = false
    @Published var error: String?
    @Published var requestLog: [ChatLogEntry] = []

    // MARK: - Configuration

    private let apiKey: String
    private let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o-mini"

    // Conversation history for multi-turn chat
    private var conversationHistory: [[String: String]] = []

    // MARK: - Initialization

    init() {
        if let key = Self.loadFromInfoPlist(), !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI API key loaded from Info.plist (length: \(key.count))", category: "OpenAI")
        } else if let key = Self.loadFromConfig(), !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI API key loaded from Config.plist (length: \(key.count))", category: "OpenAI")
        } else if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI API key loaded from environment (length: \(key.count))", category: "OpenAI")
        } else {
            self.apiKey = ""
            NetworkLogger.shared.error("OpenAI API key not found in any source", category: "OpenAI")
        }
    }

    private static func loadFromInfoPlist() -> String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            return nil
        }
        return key
    }

    private static func loadFromConfig() -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let key = config["OpenAIAPIKey"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }

    // MARK: - Public Methods

    /// Send a message and stream the response via SSE
    func sendMessage(_ text: String) async {
        guard !apiKey.isEmpty else {
            error = OpenAIError.apiKeyNotConfigured.localizedDescription
            NetworkLogger.shared.error("Cannot send: API key not configured", category: "OpenAI")
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Log the user message
        let userEntry = ChatLogEntry(timestamp: Date(), role: "user", content: text)
        requestLog.append(userEntry)

        // Add to conversation history
        conversationHistory.append(["role": "user", "content": text])

        // Reset state
        responseText = ""
        error = nil
        isStreaming = true

        NetworkLogger.shared.info("Sending message to OpenAI: \(text.prefix(100))", category: "OpenAI")

        do {
            let request = try createStreamingRequest()
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                // Read error body from byte stream
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                let errorBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                NetworkLogger.shared.error("OpenAI API error \(httpResponse.statusCode): \(errorBody.prefix(300))", category: "OpenAI")
                throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            // Parse SSE stream
            var accumulated = ""
            for try await line in bytes.lines {
                // SSE lines start with "data: "
                guard line.hasPrefix("data: ") else { continue }

                let payload = String(line.dropFirst(6))

                // Stream end signal
                if payload == "[DONE]" {
                    break
                }

                // Parse JSON chunk
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else {
                    continue
                }

                accumulated += content
                responseText = accumulated
            }

            // Log the assistant response
            let assistantEntry = ChatLogEntry(timestamp: Date(), role: "assistant", content: accumulated)
            requestLog.append(assistantEntry)

            // Add to conversation history
            conversationHistory.append(["role": "assistant", "content": accumulated])

            NetworkLogger.shared.info("OpenAI response complete: \(accumulated.count) chars", category: "OpenAI")

        } catch let openAIError as OpenAIError {
            error = openAIError.localizedDescription
            NetworkLogger.shared.error("OpenAI error: \(openAIError.localizedDescription)", category: "OpenAI")
        } catch {
            self.error = error.localizedDescription
            NetworkLogger.shared.error("OpenAI unexpected error: \(error.localizedDescription)", category: "OpenAI")
        }

        isStreaming = false
    }

    /// Clear conversation history and log
    func clearConversation() {
        conversationHistory.removeAll()
        requestLog.removeAll()
        responseText = ""
        error = nil
    }

    /// Whether the API key is configured
    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Private

    private func createStreamingRequest() throws -> URLRequest {
        guard let url = URL(string: apiEndpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": conversationHistory,
            "stream": true,
            "max_tokens": 1024,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
