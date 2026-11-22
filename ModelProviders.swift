import Foundation

/// 模型协议：OpenAI 兼容（chat/completions）或 Anthropic（messages）
enum AIProtocol: String, Codable {
    case openAI
    case anthropic
}

/// 模型服务预设：选一个就填好地址和默认模型，只剩 Key 自己粘贴
struct ModelProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let model: String
    let proto: AIProtocol

    static let all: [ModelProvider] = [
        ModelProvider(id: "longcat", name: "LongCat", baseURL: "https://api.longcat.chat/openai/v1", model: "LongCat-2.5", proto: .openAI),
        ModelProvider(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", proto: .openAI),
        ModelProvider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", proto: .openAI),
        ModelProvider(id: "claude", name: "Claude", baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-5", proto: .anthropic),
        ModelProvider(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", proto: .openAI),
        ModelProvider(id: "qwen", name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", proto: .openAI),
        ModelProvider(id: "zhipu", name: "智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", proto: .openAI),
        ModelProvider(id: "custom", name: "自定义", baseURL: "", model: "", proto: .openAI),
    ]

    static func byId(_ id: String) -> ModelProvider {
        all.first { $0.id == id } ?? all[0]
    }
}
