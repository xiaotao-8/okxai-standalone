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

/// Anthropic /v1/messages 响应
struct AnthropicContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}
struct AnthropicResponse: Decodable {
    let content: [AnthropicContentBlock]
}

/// 任意 JSON 值（只为解析 Anthropic 的 tool_use input）
struct AnyCodable: Codable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value } }
        else if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]: try c.encode(v.map { AnyCodable(value: $0) })
        case let v as [String: Any]: try c.encode(v.mapValues { AnyCodable(value: $0) })
        default: try c.encodeNil()
        }
    }
    init(value: Any) { self.value = value }
}

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

/// 模型客户端：OpenAI 兼容（chat/completions）与 Anthropic（messages）双协议
final class AIClient {
    var baseURL = "https://api.longcat.chat/openai/v1"
    var apiKey = ""
    var model = "LongCat-2.5"
    var proto: AIProtocol = .openAI

    // MARK: - 地址归一化

    /// 用户常把完整接口地址粘进来（如带 /chat/completions 或 /v1 后缀），这里统一修成可用的 base
    private func normalizedBase() -> String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { base = String(base.dropLast("/chat/completions".count)) }
        if base.hasSuffix("/v1/chat/completions") { base = String(base.dropLast("/v1/chat/completions".count)) }
        return base
    }

    private func openAIEndpoint() -> URL {
        let base = normalizedBase()
        // LongCat 的 OpenAI 入口是 …/openai，标准路径是 …/openai/v1/chat/completions
        if base.hasSuffix("/openai") {
            return URL(string: base + "/v1/chat/completions")!
        }
        return URL(string: base + "/chat/completions")!
    }

    private func anthropicEndpoint() -> URL {
        var base = normalizedBase()
        if base.hasSuffix("/v1/messages") { base = String(base.dropLast("/v1/messages".count)) }
        return URL(string: base + "/v1/messages")!
    }

    /// 从失败响应里抠出服务商给的错误信息，没有就返回原文截断
    private func providerError(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let m = err["message"] as? String {
                return "HTTP \(status): \(m)"
            }
            if let err = obj["error"] as? String { return "HTTP \(status): \(err)" }
            if let m = obj["message"] as? String { return "HTTP \(status): \(m)" }
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return "HTTP \(status): \(String(text.prefix(300)))"
    }

    // MARK: - 对话（带工具调用）

    func chat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AIMessage {
        switch proto {
        case .openAI: return try await chatOpenAI(messages: messages, tools: tools)
        case .anthropic: return try await chatAnthropic(messages: messages, tools: tools)
        }
    }

    private func chatOpenAI(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AIMessage {
        var req = URLRequest(url: openAIEndpoint())
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(providerError(from: data, status: http.statusCode))
        }
        guard let decoded = try? JSONDecoder().decode(AIResponse.self, from: data),
              let msg = decoded.choices.first?.message else {
            throw AIError.http(providerError(from: data, status: -1))
        }
        return msg
    }

    private func chatAnthropic(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AIMessage {
        let (system, anthropicMessages) = toAnthropicMessages(messages)
        var req = URLRequest(url: anthropicEndpoint())
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages
        ]
        if let system { payload["system"] = system }
        if !tools.isEmpty { payload["tools"] = tools.map { toAnthropicTool($0) } }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(providerError(from: data, status: http.statusCode))
        }
        guard let decoded = try? JSONDecoder().decode(AnthropicResponse.self, from: data) else {
            throw AIError.http(providerError(from: data, status: -1))
        }
        var text = ""
        var calls: [AIToolCall] = []
        for block in decoded.content {
            switch block.type {
            case "text":
                text += block.text ?? ""
            case "tool_use":
                let args: String
                if let input = block.input {
                    let dict = input.mapValues { $0.value }
                    args = String(data: (try? JSONSerialization.data(withJSONObject: dict)) ?? Data(), encoding: .utf8) ?? "{}"
                } else { args = "{}" }
                calls.append(AIToolCall(id: block.id ?? UUID().uuidString, type: "function",
                                        function: AIFunctionCall(name: block.name ?? "", arguments: args)))
            default: break
            }
        }
        return AIMessage(role: "assistant", content: text.isEmpty ? nil : text,
                         tool_calls: calls.isEmpty ? nil : calls)
    }

    // MARK: - 纯文本补全（不带工具）

    func complete(prompt: String) async throws -> String {
        switch proto {
        case .openAI:
            let msg = try await chatOpenAI(messages: [["role": "user", "content": prompt]], tools: [])
            return msg.content ?? ""
        case .anthropic:
            let msg = try await chatAnthropic(messages: [["role": "user", "content": prompt]], tools: [])
            return msg.content ?? ""
        }
    }

    // MARK: - OpenAI 形态 → Anthropic 形态

    /// 把 OpenAI 形态的消息数组转成 Anthropic 的 system + messages
    private func toAnthropicMessages(_ openAI: [[String: Any]]) -> (String?, [[String: Any]]) {
        var system: String?
        var out: [[String: Any]] = []
        for m in openAI {
            let role = m["role"] as? String ?? "user"
            switch role {
            case "system":
                let text = m["content"] as? String ?? ""
                system = (system.map { $0 + "\n" } ?? "") + text
            case "assistant":
                // 带 tool_calls 的助手消息 → content blocks
                if let calls = m["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                    var blocks: [[String: Any]] = []
                    if let text = m["content"] as? String, !text.isEmpty {
                        blocks.append(["type": "text", "text": text])
                    }
                    for call in calls {
                        guard let fn = call["function"] as? [String: Any] else { continue }
                        var input: [String: Any] = [:]
                        if let argStr = fn["arguments"] as? String,
                           let data = argStr.data(using: .utf8),
                           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            input = obj
                        }
                        blocks.append(["type": "tool_use",
                                       "id": call["id"] as? String ?? UUID().uuidString,
                                       "name": fn["name"] as? String ?? "",
                                       "input": input])
                    }
                    out.append(["role": "assistant", "content": blocks])
                } else {
                    out.append(["role": "assistant", "content": m["content"] as? String ?? ""])
                }
            case "tool":
                // 工具结果 → user 消息里的 tool_result 块
                let toolId = m["tool_call_id"] as? String ?? ""
                let content = m["content"] as? String ?? ""
                if var last = out.last, last["role"] as? String == "user",
                   var blocks = last["content"] as? [[String: Any]] {
                    blocks.append(["type": "tool_result", "tool_use_id": toolId, "content": content])
                    last["content"] = blocks
                    out[out.count - 1] = last
                } else {
                    out.append(["role": "user", "content": [["type": "tool_result", "tool_use_id": toolId, "content": content]]])
                }
            default:
                out.append(["role": "user", "content": m["content"] as? String ?? ""])
            }
        }
        // Anthropic 要求 messages 不能为空且首条是 user
        if out.isEmpty { out.append(["role": "user", "content": "你好"]) }
        return (system, out)
    }

    private func toAnthropicTool(_ openAITool: [String: Any]) -> [String: Any] {
        guard let fn = openAITool["function"] as? [String: Any] else { return openAITool }
        return [
            "name": fn["name"] as? String ?? "",
            "description": fn["description"] as? String ?? "",
            "input_schema": fn["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]]
        ]
    }
}
