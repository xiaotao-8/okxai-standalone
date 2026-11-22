import Foundation
import SwiftUI

/// 全局状态：配置 + 行情/资产 + AI 对话
@MainActor
final class AppStore: ObservableObject {
    // OKX 配置
    @Published var okxKey = ""
    @Published var okxSecret = ""
    @Published var okxPassphrase = ""
    @Published var demoTrading = true { didSet { OKXAPI.shared.demoTrading = demoTrading } }

    // AI 配置
    @Published var aiBaseURL = "https://api.openai.com/v1"
    @Published var aiKey = ""
    @Published var aiModel = "gpt-4o-mini"

    // 数据
    @Published var tickers: [Ticker] = []
    @Published var balances: [BalanceDetail] = []
    @Published var positions: [Position] = []

    // 聊天
    @Published var chat: [ChatMessage] = []
    @Published var busy = false

    private let okx = OKXAPI.shared
    private let ai = AIClient()

    // MARK: - 配置读写

    func loadConfig() {
        okxKey = KeychainStore.get("okx_key") ?? ""
        okxSecret = KeychainStore.get("okx_secret") ?? ""
        okxPassphrase = KeychainStore.get("okx_pass") ?? ""
        aiKey = KeychainStore.get("ai_key") ?? ""
        aiBaseURL = UserDefaults.standard.string(forKey: "ai_base") ?? aiBaseURL
        aiModel = UserDefaults.standard.string(forKey: "ai_model") ?? aiModel
        demoTrading = UserDefaults.standard.object(forKey: "demo") == nil ? true : UserDefaults.standard.bool(forKey: "demo")
        syncToAPI()
    }

    func saveConfig() {
        KeychainStore.set(okxKey, key: "okx_key")
        KeychainStore.set(okxSecret, key: "okx_secret")
        KeychainStore.set(okxPassphrase, key: "okx_pass")
        KeychainStore.set(aiKey, key: "ai_key")
        UserDefaults.standard.set(aiBaseURL, forKey: "ai_base")
        UserDefaults.standard.set(aiModel, forKey: "ai_model")
        UserDefaults.standard.set(demoTrading, forKey: "demo")
        syncToAPI()
    }

    private func syncToAPI() {
        okx.apiKey = okxKey
        okx.secretKey = okxSecret
        okx.passphrase = okxPassphrase
        okx.demoTrading = demoTrading
        ai.baseURL = aiBaseURL
        ai.apiKey = aiKey
        ai.model = aiModel
    }

    // MARK: - 数据拉取

    func refreshMarket() async {
        do { tickers = try await okx.tickers() }
        catch { appendChat("system", error.localizedDescription) }
    }

    func refreshAccount() async {
        guard hasOKXKeys else {
            appendChat("system", "请先在「设置」填入欧易 API Key")
            return
        }
        do {
            balances = try await okx.balance()
            positions = try await okx.positions()
        } catch {
            appendChat("system", error.localizedDescription)
        }
    }

    var hasOKXKeys: Bool { !okxKey.isEmpty && !okxSecret.isEmpty && !okxPassphrase.isEmpty }

    // MARK: - 手动下单 / 撤单

    func placeOrder(instId: String, side: String, ordType: String,
                    sz: String, px: String?) async -> String {
        do {
            let r = try await okx.placeOrder(instId: instId, side: side,
                                             ordType: ordType, sz: sz, px: px)
            if let first = r.first, first.success {
                return "下单成功 ordId=\(first.ordId)"
            } else {
                return "下单失败：\(r.first?.sMsg ?? "未知错误")"
            }
        } catch { return "下单异常：\(error.localizedDescription)" }
    }

    // MARK: - AI 对话

    private func appendChat(_ role: String, _ text: String, draft: OrderDraft? = nil) {
        chat.append(ChatMessage(role: role, text: text, orderDraft: draft))
    }

    /// 发送用户消息，驱动「模型 → 工具 → 模型」循环
    func sendChat(_ input: String) async {
        guard !aiKey.isEmpty else {
            appendChat("system", "请先在「设置」填入 AI 的 API Key 与 Base URL")
            return
        }
        appendChat("user", input)
        busy = true
        defer { busy = false }

        var messages: [[String: Any]] = [
            ["role": "system", "content": "你是交易助手，运行在用户本地。可用工具查询行情/资产，或生成订单草稿。任何真实下单必须先得到用户确认，confirmed 参数只能由用户确认后置为 true。"]
        ]
        for m in chat { messages.append(["role": m.role, "content": m.text]) }

        do {
            var reply = try await ai.chat(messages: messages, tools: Self.toolSchemas)
            // 处理工具调用（最多循环 2 轮，防止无限递归）
            for _ in 0..<2 {
                guard let calls = reply.tool_calls, !calls.isEmpty else { break }
                var toolMsgs: [[String: Any]] = []
                for call in calls {
                    let result = await runTool(name: call.function.name,
                                               arguments: call.function.arguments)
                    toolMsgs.append(["role": "tool", "tool_call_id": call.id, "content": result])
                    // 下单工具返回待确认草稿
                    if call.function.name == "place_order",
                       let draft = parseDraft(call.function.arguments) {
                        appendChat("assistant", "已生成订单草稿，请确认：", draft: draft)
                    }
                }
                var next = messages
                next.append(["role": "assistant", "tool_calls": try JSONSerialization.jsonObject(with: JSONEncoder().encode(calls))])
                next.append(contentsOf: toolMsgs)
                reply = try await ai.chat(messages: next, tools: Self.toolSchemas)
            }
            appendChat("assistant", reply.content ?? "（无内容）")
        } catch {
            appendChat("system", error.localizedDescription)
        }
    }

    // MARK: - 工具定义（OpenAI function calling 格式）

    static let toolSchemas: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "get_ticker",
                "description": "查询指定交易对最新行情，如 BTC-USDT",
                "parameters": [
                    "type": "object",
                    "properties": ["instId": ["type": "string", "description": "交易对，如 BTC-USDT"]],
                    "required": ["instId"]
                ]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_balance",
                "description": "查询账户资产余额",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "get_positions",
                "description": "查询当前持仓",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ],
        [
            "type": "function",
            "function": [
                "name": "place_order",
                "description": "下单。默认只生成草稿；confirmed 为 true 时才真正提交（需用户在界面确认）",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "instId": ["type": "string"],
                        "side": ["type": "string", "description": "buy 或 sell"],
                        "ordType": ["type": "string", "description": "market 或 limit"],
                        "sz": ["type": "string", "description": "数量"],
                        "px": ["type": "string", "description": "限价单价格，市价单可空"],
                        "confirmed": ["type": "boolean", "description": "是否用户已确认提交"]
                    ],
                    "required": ["instId", "side", "ordType", "sz"]
                ]
            ]
        ]
    ]

    // MARK: - 工具执行

    private func parseArgs(_ s: String) -> [String: Any] {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func parseDraft(_ s: String) -> OrderDraft? {
        let p = parseArgs(s)
        guard let instId = p["instId"] as? String,
              let side = p["side"] as? String,
              let ordType = p["ordType"] as? String,
              let sz = p["sz"] as? String else { return nil }
        return OrderDraft(instId: instId, side: side, ordType: ordType,
                          sz: sz, px: p["px"] as? String)
    }

    /// 执行 AI 请求的工具，返回 JSON 字符串
    private func runTool(name: String, arguments: String) async -> String {
        let p = parseArgs(arguments)
        switch name {
        case "get_ticker":
            let instId = (p["instId"] as? String) ?? "BTC-USDT"
            do {
                let t = try await okx.ticker(instId: instId)
                return (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(t)))?.jsonString ?? "查询失败"
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "get_balance":
            do {
                let b = try await okx.balance()
                return (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(b)))?.jsonString ?? "查询失败"
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "get_positions":
            do {
                let r = try await okx.positions()
                return (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(r)))?.jsonString ?? "查询失败"
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "place_order":
            guard let draft = parseDraft(arguments) else { return "参数不完整" }
            let confirmed = (p["confirmed"] as? Bool) ?? false
            guard confirmed else {
                // 未确认：只返回草稿 JSON
                let d = (try? JSONEncoder().encode(draft)) ?? Data()
                return "订单草稿（未提交）：\(String(data: d, encoding: .utf8) ?? "")"
            }
            let msg = await placeOrder(instId: draft.instId, side: draft.side,
                                       ordType: draft.ordType, sz: draft.sz, px: draft.px)
            return msg

        default:
            return "未知工具"
        }
    }

    /// 用户点击「确认下单」
    func confirmDraft(_ draft: OrderDraft) async {
        let msg = await placeOrder(instId: draft.instId, side: draft.side,
                                   ordType: draft.ordType, sz: draft.sz, px: draft.px)
        appendChat("system", msg)
    }
}

// 小工具：Any -> JSON 字符串
private extension Any {
    var jsonString: String {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: [.prettyPrinted]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
