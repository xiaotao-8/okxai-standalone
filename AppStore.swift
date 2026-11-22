import Foundation
import SwiftUI

/// 全局状态：配置 + 行情/资产 + AI 对话
@MainActor
final class AppStore: ObservableObject {
    // OKX 配置
    @Published var okxKey = ""
    @Published var okxSecret = ""
    @Published var okxPassphrase = ""
    @Published var demoTrading = false { didSet { OKXAPI.shared.demoTrading = demoTrading } }

    // AI 配置（默认 LongCat；“我的”页里可切换所有模型服务）
    @Published var aiProvider = "longcat"
    @Published var aiBaseURL = "https://api.longcat.chat/openai/v1"
    @Published var aiKey = ""
    @Published var aiModel = "LongCat-2.5"
    /// AI 全权执行交易：开 = 智能体下单直接成交，不再逐单等你点确认
    @Published var aiAutoTrade = true
    /// 交易模式：spot 现货 / swap 合约
    @Published var tradeMode = "spot"
    /// 可自定义的 App 名称（登录页/导航栏显示）
    @Published var appName = "OKXAI"

    // 数据
    @Published var tickers: [Ticker] = []
    @Published var balances: [BalanceDetail] = []
    @Published var positions: [Position] = []
    @Published var pendingCount = 0
    @Published var pendingOrders: [Order] = []
    /// 杠杆倍数（合约）
    @Published var lever: String = "1"
    /// 保证金模式：isolated 逐仓 / cross 全仓
    @Published var mgnMode: String = "isolated"
    /// 当前交易/详情页选中的交易对（行情页点买入/卖出会切到这个）
    @Published var activeInstId: String = "BTC-USDT"
    /// 详情页 K 线
    @Published var candles: [Candle] = []
    /// 选中币种的价格预测
    @Published var prediction: PricePrediction?
    @Published var predicting = false

    // 聊天
    @Published var chat: [ChatMessage] = []
    @Published var busy = false

    // 资金：账单 / 充币
    @Published var bills: [Bill] = []
    @Published var depositAddress = ""
    @Published var depositChain = ""

    // 实时通知栏（灵动岛 / 锁屏）
    @Published var liveActivityEnabled = true

    // 登录态
    @Published var loggedIn = false
    @Published var loggingIn = false
    @Published var loginError = ""

    private let okx = OKXAPI.shared
    private let ai = AIClient()

    // MARK: - 配置读写

    func loadConfig() {
        okxKey = KeychainStore.get("okx_key") ?? ""
        okxSecret = KeychainStore.get("okx_secret") ?? ""
        okxPassphrase = KeychainStore.get("okx_pass") ?? ""
        aiKey = KeychainStore.get("ai_key") ?? ""
        aiProvider = UserDefaults.standard.string(forKey: "ai_provider") ?? aiProvider
        aiBaseURL = UserDefaults.standard.string(forKey: "ai_base") ?? aiBaseURL
        aiModel = UserDefaults.standard.string(forKey: "ai_model") ?? aiModel
        aiAutoTrade = UserDefaults.standard.object(forKey: "ai_autotrade") == nil ? true : UserDefaults.standard.bool(forKey: "ai_autotrade")
        tradeMode = UserDefaults.standard.string(forKey: "trade_mode") ?? tradeMode
        liveActivityEnabled = UserDefaults.standard.object(forKey: "live_activity") == nil ? true : UserDefaults.standard.bool(forKey: "live_activity")
        appName = UserDefaults.standard.string(forKey: "app_name") ?? appName
        demoTrading = UserDefaults.standard.object(forKey: "demo") == nil ? false : UserDefaults.standard.bool(forKey: "demo")
        syncToAPI()
        // 模拟器验证参数：跳过登录页，直接进主界面
        loggedIn = CommandLine.arguments.contains("-PreviewAgent") ? true : hasOKXKeys
    }

    func saveConfig() {
        KeychainStore.set(okxKey, key: "okx_key")
        KeychainStore.set(okxSecret, key: "okx_secret")
        KeychainStore.set(okxPassphrase, key: "okx_pass")
        KeychainStore.set(aiKey, key: "ai_key")
        UserDefaults.standard.set(aiProvider, forKey: "ai_provider")
        UserDefaults.standard.set(aiBaseURL, forKey: "ai_base")
        UserDefaults.standard.set(aiModel, forKey: "ai_model")
        UserDefaults.standard.set(aiAutoTrade, forKey: "ai_autotrade")
        UserDefaults.standard.set(tradeMode, forKey: "trade_mode")
        UserDefaults.standard.set(liveActivityEnabled, forKey: "live_activity")
        UserDefaults.standard.set(appName, forKey: "app_name")
        UserDefaults.standard.set(demoTrading, forKey: "demo")
        syncToAPI()
    }

    /// 切换模型服务：一键填好该服务的地址和默认模型，Key 保留你原来填的
    func selectProvider(_ p: ModelProvider) {
        aiProvider = p.id
        if p.id != "custom" {
            aiBaseURL = p.baseURL
            aiModel = p.model
        }
        syncToAPI()
        saveConfig()
    }

    /// 测试模型连接：发一句“你好”，返回成功或具体的失败原因
    func testAI() async -> String {
        guard !aiKey.isEmpty else { return "请先填写 AI 的 Key" }
        syncToAPI()
        do {
            let reply = try await ai.complete(prompt: "你好")
            return "连接成功：" + (reply.isEmpty ? "（模型无返回内容）" : String(reply.prefix(120)))
        } catch {
            return error.localizedDescription
        }
    }

    private func syncToAPI() {
        okx.apiKey = okxKey
        okx.secretKey = okxSecret
        okx.passphrase = okxPassphrase
        okx.demoTrading = demoTrading
        ai.baseURL = aiBaseURL
        ai.apiKey = aiKey
        ai.model = aiModel
        ai.proto = ModelProvider.byId(aiProvider).proto
    }

    // MARK: - 小组件 / 实时通知栏同步

    /// 每次刷新资产后写快照：小组件读它，灵动岛也用它更新
    func saveSnapshotAndSyncLiveActivity() {
        let total = balances.reduce(0) { $0 + $1.eqValue }
        let snap = AccountSnapshot(
            totalEquity: total,
            totalUpl: positions.reduce(0) { $0 + $1.uplValue },
            positions: positions.map { PositionSnapshot(instId: $0.instId, pos: $0.pos, upl: $0.uplValue, avgPx: $0.avgPx) },
            updatedAt: Date())
        snap.save()
        if #available(iOS 16.2, *) {
            if liveActivityEnabled {
                LiveActivityManager.startOrUpdate(snapshot: snap)
            } else {
                LiveActivityManager.end()
            }
        }
    }

    // MARK: - 数据拉取

    func refreshMarket() async {
        do { tickers = try await okx.tickers() }
        catch { appendChat("system", error.localizedDescription) }
    }

    func refreshAccount() async {
        guard hasOKXKeys else {
            appendChat("system", "请先登录欧易账户")
            return
        }
        do {
            balances = try await okx.balance()
            positions = try await okx.positions()
            await loadOrders()
            saveSnapshotAndSyncLiveActivity()
        } catch {
            appendChat("system", error.localizedDescription)
        }
    }

    /// 拉取当前委托
    func loadOrders() async {
        pendingOrders = (try? await okx.pendingOrders(instType: tradeMode == "swap" ? "SWAP" : "SPOT")) ?? []
        pendingCount = pendingOrders.count
    }

    // MARK: - 资金：充币 / 划转 / 账单

    /// 查某币种的充币地址（只读，不动钱）
    func fetchDepositAddress(ccy: String) async {
        depositAddress = ""
        depositChain = ""
        do {
            let list = try await okx.depositAddress(ccy: ccy)
            if let first = list.first {
                depositAddress = first.addr
                depositChain = first.chain
            } else {
                depositChain = "该币种暂无充币地址"
            }
        } catch {
            depositChain = error.localizedDescription
        }
    }

    /// 资金划转：默认从资金账户（6）转到交易账户（18）
    func transfer(ccy: String, amt: String, from: String = "6", to: String = "18") async -> String {
        do {
            let r = try await okx.transfer(ccy: ccy, amt: amt, from: from, to: to)
            return r.first != nil ? "划转成功" : "划转失败"
        } catch {
            return "划转异常：\(error.localizedDescription)"
        }
    }

    /// 拉取账单（资金流水）
    func loadBills() async {
        do { bills = try await okx.bills() }
        catch { bills = [] }
    }

    /// 撤单
    func cancel(ordId: String, instId: String) async -> String {
        do {
            let r = try await okx.cancelOrder(instId: instId, ordId: ordId)
            await loadOrders()
            return (r.first?.success ?? false) ? "已撤单" : "撤单失败：\(r.first?.sMsg ?? "")"
        } catch {
            await loadOrders()
            return "撤单异常：\(error.localizedDescription)"
        }
    }

    var hasOKXKeys: Bool { !okxKey.isEmpty && !okxSecret.isEmpty && !okxPassphrase.isEmpty }

    /// 登录 / 授权：真实调用一次账户接口，验证 API Key 是否有效
    func login() async -> Bool {
        guard hasOKXKeys else {
            loginError = "请先填写 API Key / Secret Key / Passphrase"
            return false
        }
        syncToAPI()
        loggingIn = true
        loginError = ""
        defer { loggingIn = false }
        do {
            _ = try await okx.balance()
            saveConfig()
            loggedIn = true
            Task { await refreshAccount() }
            return true
        } catch {
            loginError = "授权失败：\(error.localizedDescription)"
            loggedIn = false
            return false
        }
    }

    /// 退出登录：清除钥匙串中的欧易凭证
    func logout() {
        KeychainStore.delete("okx_key")
        KeychainStore.delete("okx_secret")
        KeychainStore.delete("okx_pass")
        okxKey = ""; okxSecret = ""; okxPassphrase = ""
        loggedIn = false
        if #available(iOS 16.2, *) { LiveActivityManager.end() }
    }

    func loadCandles(instId: String, bar: String = "1H") async {
        do { candles = try await okx.candles(instId: instId, bar: bar) }
        catch { candles = [] }
    }

    // MARK: - 价格预测

    /// 生成选中币种预测：优先 AI；未配置 AI 时用 K 线线性回归
    func predict(instId: String, currentPrice: Double) async {
        guard currentPrice > 0 else { return }
        predicting = true
        defer { predicting = false }
        prediction = nil

        if !aiKey.isEmpty {
            let prompt = """
            你是加密货币短线分析师。当前 \(instId) 价格 \(String(format: "%.4f", currentPrice)) USDT。请预测未来 24 小时走势，只输出 JSON，格式：{"target": 目标价数字, "pct": 预期涨跌幅数字, "reason": "一句话理由"}。不要输出任何其他内容。
            """
            if let text = try? await ai.complete(prompt: prompt),
               let p = parsePrediction(text, base: currentPrice) {
                var r = p; r.source = "AI"
                prediction = r
                return
            }
        }

        // 技术预测：K 线收盘价线性回归
        let cs = candles.sorted { (Double($0.ts) ?? 0) < (Double($1.ts) ?? 0) }
        guard cs.count >= 5 else { return }
        let n = Double(cs.count)
        let xs = (0..<cs.count).map { Double($0) }
        let ys = cs.map { $0.close }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        let slope = den == 0 ? 0 : num / den
        let next = my + slope * (n - mx + 1)
        let pct = (next - currentPrice) / currentPrice * 100
        prediction = PricePrediction(target: next, pct: pct,
                                     reason: "基于最近 \(cs.count) 根 K 线的线性回归",
                                     source: "技术")
    }

    private func parsePrediction(_ text: String, base: Double) -> PricePrediction? {
        guard let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}") else { return nil }
        let jsonStr = String(text[s...e])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let target = (obj["target"] as? NSNumber)?.doubleValue ?? Double(obj["target"] as? String ?? "")
        let pct = (obj["pct"] as? NSNumber)?.doubleValue ?? Double(obj["pct"] as? String ?? "")
        guard let target else { return nil }
        let reason = obj["reason"] as? String ?? "AI 模型预测"
        return PricePrediction(target: target, pct: pct ?? ((target - base) / base * 100),
                               reason: reason, source: "AI")
    }

    // MARK: - 手动下单 / 撤单

    func placeOrder(instId: String, side: String, ordType: String,
                    sz: String, px: String?) async -> String {
        // 现货 tdMode=cash；合约 tdMode=保证金模式，posSide 按方向开多/开空
        let tdMode = tradeMode == "swap" ? mgnMode : "cash"
        let posSide: String? = tradeMode == "swap" ? (side == "buy" ? "long" : "short") : nil
        do {
            let r = try await okx.placeOrder(instId: instId, side: side,
                                             ordType: ordType, sz: sz, px: px,
                                             tdMode: tdMode, posSide: posSide,
                                             lever: lever, mgnMode: mgnMode)
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

        // 全权模式：智能体可直接下单成交；否则下单前必须等用户点确认
        let autoNote = aiAutoTrade
            ? "你可以直接下单成交，无需用户逐单确认；下单前先查行情与账户，数量要合理。"
            : "任何真实下单必须先得到用户确认，confirmed 参数只能由用户确认后置为 true。"
        var messages: [[String: Any]] = [
            ["role": "system", "content": "你是交易助手，运行在用户本地。可用工具查询行情/资产，或生成订单草稿。\(autoNote)"]
        ]
        // 只把 user/assistant 发给模型：system 报错、tool 记录留在本地，不发给模型
        for m in chat where m.role == "user" || m.role == "assistant" {
            messages.append(["role": m.role, "content": m.text])
        }

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
                    // 非全权模式：下单工具返回待确认草稿，等用户点确认
                    if !aiAutoTrade, call.function.name == "place_order",
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
                "description": "下单。全权模式下直接成交；否则只生成草稿，等用户在界面确认后才提交",
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
                let s = jsonString(try? JSONSerialization.jsonObject(with: JSONEncoder().encode(t)))
                return s.isEmpty ? "查询失败" : s
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "get_balance":
            do {
                let b = try await okx.balance()
                let s = jsonString(try? JSONSerialization.jsonObject(with: JSONEncoder().encode(b)))
                return s.isEmpty ? "查询失败" : s
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "get_positions":
            do {
                let r = try await okx.positions()
                let s = jsonString(try? JSONSerialization.jsonObject(with: JSONEncoder().encode(r)))
                return s.isEmpty ? "查询失败" : s
            } catch { return "查询失败：\(error.localizedDescription)" }

        case "place_order":
            guard let draft = parseDraft(arguments) else { return "参数不完整" }
            let confirmed = (p["confirmed"] as? Bool) ?? false
            // 全权模式：模型说下单就直接成交，不等用户逐单确认
            guard confirmed || aiAutoTrade else {
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

// 小工具：Any -> JSON 字符串（Swift 不许扩展 Any，改用自由函数）
func jsonString(_ v: Any?) -> String {
    guard let v, let data = try? JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted]) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
}
