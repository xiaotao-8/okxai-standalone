import Foundation

struct AIToolCall: Codable {
    let id: String
    let type: String
    let function: AIFunctionCall
}

struct AIFunctionCall: Codable {
    let name: String
    /// JSON 字符串，由调用方解析
    let arguments: String
}

struct AIMessage: Codable {
    let role: String?
    let content: String?
    let tool_calls: [AIToolCall]?
}

struct AIChoice: Decodable { let message: AIMessage }
struct AIResponse: Decodable { let choices: [AIChoice] }

enum AIError: Error, LocalizedError {
    case http(String)
    case noChoice
    var errorDescription: String? {
        switch self {
        case .http(let m): return "AI 请求失败: \(m)"
        case .noChoice:   return "AI 未返回内容"
        }
    }
}

/// OpenAI 兼容 /chat/completions 客户端（支持 tools 函数调用）
final class AIClient {
    var baseURL = "https://api.openai.com/v1"
    var apiKey = ""
    var model = "gpt-4o-mini"

    /// 发送对话，返回模型消息（可能包含 tool_calls）
    func chat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AIMessage {
        let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": messages,
            "tools": tools,
            "tool_choice": "auto"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let resp = try? JSONDecoder().decode(AIResponse.self, from: data),
              let msg = resp.choices.first?.message else {
            throw AIError.http(text)
        }
        return msg
    }

    /// 纯文本补全（不带工具），返回模型回复原文
    func complete(prompt: String) async throws -> String {
        let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + "/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let resp = try? JSONDecoder().decode(AIResponse.self, from: data),
              let content = resp.choices.first?.message.content else {
            throw AIError.http(text)
        }
        return content
    }
}
