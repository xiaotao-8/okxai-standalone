import Foundation
import SwiftUI
import UserNotifications

/// 全局状态：OKX 配置 + AI 配置 + 行情/账户/聊天
@MainActor
final class AppStore: ObservableObject {

    // MARK: - OKX 配置
    @Published var okxKey = "" { didSet { saveConfig() } }
    @Published var okxSecret = "" { didSet { saveConfig() } }
    @Published var okxPassphrase = "" { didSet { saveConfig() } }
    @Published var demoTrading = true { didSet { saveConfig() } }

    // MARK: - AI 配置
    @Published var aiBaseURL = "http://127.0.0.1:10099/v1" { didSet { saveConfig() } }
    @Published var aiKey = "" { didSet { saveConfig() } }
    @Published var aiModel = "gpt-4.1" { didSet { saveConfig() } }

    // MARK: - 应用
    @Published var appName = "OKXAI" { didSet { saveConfig() } }

    // MARK: - 行情
    @Published var tickers: [Ticker] = []
    @Published var candles: [Candle] = []
    @Published var activeInstId: String = "BTC-USDT"
    @Published var marketTrades: [Trade] = []
    @Published var book: BookSnapshot?
    @Published var candleBar: String = "1H"

    // MARK: - 交易
    @Published var tradeMode: String = "spot"      // spot / swap
    @Published var posSide: String = "long"        // long / short
    @Published var lever: String = "1"
    @Published var mgnMode: String = "isolated"    // isolated / cross

    // MARK: - 账户
    @Published var balances: [BalanceDetail] = []
    @Published var positions: [Position] = []
    @Published var bills: [Bill] = []
    @Published var equityHistory: [EquityPoint] = []
    @Published var loggedIn = false
    @Published var loggingIn = false
    @Published var loginError = ""

    // MARK: - 委托
    @Published var pendingOrders: [Order] = []
    @Published var historyOrders: [Order] = []
    @Published var fills: [Fill] = []
    @Published var pendingCount: Int = 0

    // MARK: - AI 聊天 / 策略
    @Published var chat: [ChatMessage] = []
    @Published var busy = false
    @Published var strategyEnabled = false {
        didSet { strategyTimer?.invalidate(); if strategyEnabled { strategyTimer = Timer.scheduledTimer(withTimeInterval: strategyInterval, repeats: true) { _ in Task { await self.runStrategyCycle() } } } }
    }
    @Published var strategyAutoTrade = false
    @Published var strategyAmount = "0.001"
    @Published var strategyInterval: Double = 300
    @Published var strategyLog: [String] = []
    @Published var strategyRunning = false
    private var strategyTimer: Timer?

    // MARK: - 预测
    @Published var prediction: PricePrediction?
    @Published var predicting = false
    @Published var predictionRecords: [PredictionRecord] = []
    @Published var predictionHits = 0
    @Published var predictionTotal = 0

    // MARK: - 实时行情（WebSocket）
    @Published var wsEnabled = false
    @Published var wsConnected = false
    private var ws: OKXWebSocket?

    // MARK: - 自选 / 预警
    @Published var watchlist: [String] = []
    @Published var alerts: [PriceAlert] = []

    // MARK: - 回测
    @Published var backtest: BacktestResult?
    @Published var backtesting = false
    @Published var backtestFast: Double = 5
    @Published var backtestSlow: Double = 20

    // MARK: - 安全 / 提示
    @Published var lockEnabled = false { didSet { locked = lockEnabled && AppLock.isAvailable; saveConfig() } }
    @Published var locked = false
    @Published var notice = ""

    let okx = OKXAPI.shared
    private let ai = AIClient()
    private let defaults = UserDefaults.standard

    init() {
        okxKey = defaults.string(forKey: "okxai.key") ?? ""
        okxSecret = KeychainStore.get("okxai.secret") ?? ""
        okxPassphrase = KeychainStore.get("okxai.pass") ?? ""
        demoTrading = defaults.object(forKey: "okxai.demo") as? Bool ?? true
        aiBaseURL = defaults.string(forKey: "okxai.aibase") ?? "http://127.0.0.1:10099/v1"
        aiKey = defaults.string(forKey: "okxai.aikey") ?? ""
        aiModel = defaults.string(forKey: "okxai.aimodel") ?? "gpt-4.1"
        appName = defaults.string(forKey: "okxai.appname") ?? "OKXAI"

        watchlist = Storage.load([String].self, key: "okxai.watchlist") ?? []
        alerts = Storage.load([PriceAlert].self, key: "okxai.alerts") ?? []
        equityHistory = Storage.load([EquityPoint].self, key: "okxai.equity") ?? []
        predictionRecords = Storage.load([PredictionRecord].self, key: "okxai.predrecords") ?? []
        lockEnabled = defaults.bool(forKey: "okxai.lock")
        recomputePredictionStats()
        locked = lockEnabled && AppLock.isAvailable
    }

    var hasOKXKeys: Bool { !okxKey.isEmpty && !okxSecret.isEmpty && !okxPassphrase.isEmpty }

    /// 合约标的：BTC-USDT → BTC-USDT-SWAP
    var swapInstId: String {
        guard !activeInstId.hasSuffix("-SWAP"), !activeInstId.contains("-USD-") else { return activeInstId }
        return activeInstId + "-SWAP"
    }

    /// 当前交易模式实际下单用的标的
    var orderInstId: String { tradeMode == "swap" ? swapInstId : activeInstId }

    var currentInstType: String { tradeMode == "swap" ? "SWAP" : "SPOT" }

    // MARK: - 配置持久化

    func saveConfig() {
        defaults.set(okxKey, forKey: "okxai.key")
        KeychainStore.set(okxSecret, key: "okxai.secret")
        KeychainStore.set(okxPassphrase, key: "okxai.pass")
        defaults.set(demoTrading, forKey: "okxai.demo")
        defaults.set(aiBaseURL, forKey: "okxai.aibase")
        defaults.set(aiKey, forKey: "okxai.aikey")
        defaults.set(aiModel, forKey: "okxai.aimodel")
        defaults.set(appName, forKey: "okxai.appname")
        defaults.set(lockEnabled, forKey: "okxai.lock")
    }

    /// 清空本地缓存（自选/预警/净值/预测）
    func resetLocalData() {
        watchlist = []; alerts = []; equityHistory = []; predictionRecords = []
        predictionHits = 0; predictionTotal = 0
        Storage.remove("okxai.watchlist"); Storage.remove("okxai.alerts")
        Storage.remove("okxai.equity"); Storage.remove("okxai.predrecords")
        notify("已清空本地数据")
    }

    func logout() {
        loggedIn = false
        chat = []
        balances = []
        equityHistory = []
        stopWebSocket()
        Storage.remove("okxai.equity")
    }

    // MARK: - 登录

    func login() async -> Bool {
        guard hasOKXKeys else { loginError = "请填写完整的 API Key / Secret / Passphrase"; return false }
        loggingIn = true
        loginError = ""
        okx.apiKey = okxKey
        okx.secretKey = okxSecret
        okx.passphrase = okxPassphrase
        okx.demoTrading = demoTrading
        do {
            balances = try await okx.balance()
            loggedIn = true
            loggingIn = false
            Haptics.ok()
            Task { await refreshAccount() }
            return true
        } catch {
            loggingIn = false
            loginError = error.localizedDescription
            return false
        }
    }

    // MARK: - 行情

    func refreshMarket() async {
        tickers = (try? await okx.tickers()) ?? []
        checkAlerts()
    }

    func refreshAccount() async {
        guard hasOKXKeys else { return }
        balances = (try? await okx.balance()) ?? balances
        positions = (try? await okx.positions()) ?? positions
        recordEquity()
    }

    func loadCandles(instId: String, bar: String) async {
        candles = (try? await okx.candles(instId: instId, bar: bar, limit: 100)) ?? []
    }

    func loadMarketTrades(instId: String) async {
        marketTrades = (try? await okx.trades(instId: instId)) ?? []
    }

    func loadBook(instId: String) async {
        book = (try? await okx.books(instId: instId))?.first
    }

    func loadBills() async {
        guard hasOKXKeys else { return }
        bills = (try? await okx.bills()) ?? []
    }

    // MARK: - 委托

    func loadOrders() async {
        guard hasOKXKeys else { return }
        pendingOrders = (try? await okx.pendingOrders(instType: currentInstType)) ?? []
        pendingCount = pendingOrders.count
    }

    func loadHistory() async {
        guard hasOKXKeys else { return }
        historyOrders = (try? await okx.historyOrders(instType: currentInstType)) ?? []
        fills = (try? await okx.fillsHistory(instType: currentInstType)) ?? []
    }

    func cancel(ordId: String, instId: String) async -> String {
        do {
            let r = try await okx.cancelOrder(instId: instId, ordId: ordId)
            let first = r.first
            Task { await loadOrders() }
            if first?.success == true { Haptics.ok(); return "撤单成功" }
            return "撤单失败：\(first?.sMsg ?? "")"
        } catch { return "撤单异常：\(error.localizedDescription)" }
    }

    // MARK: - 手动下单 / 撤单

    func placeOrder(instId: String, side: String, ordType: String,
                    sz: String, px: String?,
                    tpTriggerPx: String? = nil, slTriggerPx: String? = nil,
                    triggerPx: String? = nil,
                    callbackRatio: String? = nil, activePx: String? = nil) async -> String {
        let isSwap = tradeMode == "swap"
        let finalInst = isSwap ? swapInstId : instId
        let mgn = isSwap ? mgnMode : nil
        if let lev = lever, !lev.isEmpty, lev != "1", !isSwap { return "现货不支持杠杆" }
        do {
            let r = try await okx.placeOrder(instId: finalInst, side: side,
                                             ordType: ordType, sz: sz, px: px,
                                             tdMode: isSwap ? (mgn ?? "cross") : "cash",
                                             posSide: isSwap ? posSide : nil,
                                             lever: isSwap ? lever : nil,
                                             mgnMode: mgn,
                                             tpTriggerPx: tpTriggerPx,
                                             slTriggerPx: slTriggerPx,
                                             triggerPx: triggerPx,
                                             callbackRatio: callbackRatio,
                                             activePx: activePx)
            if let first = r.first, first.success {
                Haptics.ok()
                Task { await loadOrders() }
                return "下单成功 ordId=\(first.ordId)"
            } else {
                Haptics.fail()
                return "下单失败：\(r.first?.sMsg ?? "未知错误")"
            }
        } catch { Haptics.fail(); return "下单异常：\(error.localizedDescription)" }
    }

    // MARK: - 净值曲线

    /// 每次刷新账户时记录一个净值点（内存 + 本地持久化）
    private func recordEquity() {
        let total = balances.reduce(0.0) { $0 + $1.eqValue }
        guard total > 0 else { return }
        equityHistory.append(EquityPoint(t: Date(), v: total))
        if equityHistory.count > 120 { equityHistory.removeFirst(equityHistory.count - 120) }
        Storage.save(equityHistory, key: "okxai.equity")
    }

    // MARK: - 自选

    func isWatched(_ instId: String) -> Bool { watchlist.contains(instId) }

    func toggleWatch(_ instId: String) {
        if let i = watchlist.firstIndex(of: instId) {
            watchlist.remove(at: i)
        } else {
            watchlist.append(instId)
            Haptics.select()
        }
        Storage.save(watchlist, key: "okxai.watchlist")
    }

    // MARK: - 价格预警

    func addAlert(instId: String, target: Double, direction: String, note: String = "") {
        guard target > 0 else { return }
        alerts.insert(PriceAlert(instId: instId, target: target, direction: direction, note: note), at: 0)
        Storage.save(alerts, key: "okxai.alerts")
        requestNotificationPermission()
        Haptics.ok()
        notify("已添加\(direction == "above" ? "涨破" : "跌破") \(String(format: "%.4f", target)) 预警")
    }

    func removeAlerts(at offsets: IndexSet) {
        alerts.remove(atOffsets: offsets)
        Storage.save(alerts, key: "okxai.alerts")
    }

    func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
        Storage.save(alerts, key: "okxai.alerts")
    }

    func clearTriggeredAlerts() {
        alerts.removeAll { $0.isTriggered }
        Storage.save(alerts, key: "okxai.alerts")
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 行情刷新时检查预警
    func checkAlerts() {
        guard !alerts.isEmpty else { return }
        var changed = false
        for i in alerts.indices where alerts[i].triggeredAt == nil {
            guard let t = tickers.first(where: { $0.instId == alerts[i].instId }) else { continue }
            let last = t.lastPrice
            guard last > 0 else { continue }
            let hit = alerts[i].direction == "above" ? last >= alerts[i].target : last <= alerts[i].target
            guard hit else { continue }
            alerts[i].triggeredAt = Date()
            changed = true
            Haptics.ok()
            postNotification(
                title: "价格预警 · \(alerts[i].instId)",
                body: "现价 \(t.last) 已\(alerts[i].direction == "above" ? "涨破" : "跌破") \(String(format: "%.4f", alerts[i].target))"
            )
            notify("\(alerts[i].instId) 触发预警：\(t.last)")
        }
        if changed { Storage.save(alerts, key: "okxai.alerts") }
    }

    // MARK: - 实时行情 WebSocket

    func toggleWebSocket() {
        if ws != nil { stopWebSocket() } else { startWebSocket() }
    }

    func startWebSocket() {
        guard ws == nil else { return }
        let socket = OKXWebSocket()
        ws = socket
        let login = hasOKXKeys ? OKXAPI.wsLoginArgs(apiKey: okxKey, secret: okxSecret, passphrase: okxPassphrase) : nil
        socket.start(demo: demoTrading,
                     loginArgs: login,
                     subs: wsChannels(),
                     onMessage: { [weak self] obj in
                         Task { @MainActor in self?.handleWebSocket(obj) }
                     },
                     onState: { [weak self] ok in
                         Task { @MainActor in
                             guard let self else { return }
                             self.wsConnected = ok
                             self.notify(ok ? "实时行情已连接" : "实时行情已断开")
                         }
                     })
        wsEnabled = true
    }

    func stopWebSocket() {
        ws?.stop()
        ws = nil
        wsEnabled = false
        wsConnected = false
    }

    private func wsChannels() -> [[String: String]] {
        var ids = Set(watchlist)
        ids.formUnion(tickers.prefix(20).map { $0.instId })
        ids.insert(activeInstId)
        var channels: [[String: String]] = ids.map { ["channel": "tickers", "instId": $0] }
        channels.append(["channel": "trades", "instId": activeInstId])
        channels.append(["channel": "books", "instId": activeInstId])
        channels.append(["channel": "candle1H", "instId": activeInstId])
        if hasOKXKeys {
            channels.append(["channel": "orders", "instType": "ANY"])
            channels.append(["channel": "account"])
        }
        return channels
    }

    private func handleWebSocket(_ obj: [String: Any]) {
        guard let arg = obj["arg"] as? [String: Any],
              let channel = arg["channel"] as? String,
              let data = obj["data"] as? [[String: Any]] else { return }
        switch channel {
        case "tickers":
            mergeTickers(data)
        case "trades":
            mergeTrades(data)
        case "books":
            mergeBook(data)
        case "candle1H":
            mergeCandles(data)
        case "orders":
            mergeOrders(data)
        case "account":
            mergeAccount(data)
        default:
            break
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from rows: [[String: Any]]) -> [T] {
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func mergeTickers(_ rows: [[String: Any]]) {
        let incoming = decode(Ticker.self, from: rows)
        for t in incoming {
            if let i = tickers.firstIndex(where: { $0.instId == t.instId }) { tickers[i] = t }
            else { tickers.append(t) }
        }
        checkAlerts()
    }

    private func mergeTrades(_ rows: [[String: Any]]) {
        let incoming = decode(Trade.self, from: rows)
        guard !incoming.isEmpty else { return }
        marketTrades.insert(contentsOf: incoming, at: 0)
        if marketTrades.count > 50 { marketTrades.removeLast(marketTrades.count - 50) }
    }

    private func mergeBook(_ rows: [[String: Any]]) {
        guard let b = decode(BookSnapshot.self, from: rows).first else { return }
        book = b
    }

    private func mergeCandles(_ rows: [[String: Any]]) {
        let incoming = decode(Candle.self, from: rows)
        for c in incoming {
            if let i = candles.firstIndex(where: { $0.ts == c.ts }) { candles[i] = c }
            else { candles.append(c) }
        }
        if candles.count > 200 { candles.removeFirst(candles.count - 200) }
    }

    private func mergeOrders(_ rows: [[String: Any]]) {
        let incoming = decode(Order.self, from: rows)
        for o in incoming {
            if let i = pendingOrders.firstIndex(where: { $0.ordId == o.ordId }) {
                if o.state == "filled" || o.state == "canceled" { pendingOrders.remove(at: i) }
                else { pendingOrders[i] = o }
            } else if o.state != "filled" && o.state != "canceled" {
                pendingOrders.insert(o, at: 0)
            }
        }
        pendingCount = pendingOrders.count
    }

    private func mergeAccount(_ rows: [[String: Any]]) {
        balances = decode(BalanceDetail.self, from: rows)
        recordEquity()
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
        var conversation = chat.map { ["role": $0.role, "content": $0.text] }
        var draftForUI: OrderDraft? = nil
        for _ in 0..<8 {
            let reply = try? await ai.chat(messages: conversation, tools: toolSchemas())
            if let d = reply?.toolDraft { draftForUI = d }
            guard let calls = reply?.toolCalls, !calls.isEmpty else {
                if let text = reply?.text, !text.isEmpty {
                    appendChat("assistant", text, draft: draftForUI)
                } else if draftForUI == nil {
                    appendChat("system", "模型没有返回内容（检查 Base URL / 模型名 / 网络）")
                }
                break
            }
            conversation.append(["role": "assistant", "content": NSNull(), "tool_calls": calls.map { $0.json }])
            for call in calls {
                let (name, args, result) = await runTool(call)
                conversation.append(["role": "tool", "tool_call_id": call.id, "name": name, "content": result])
            }
        }
        busy = false
    }

    func confirmDraft(_ d: OrderDraft) async {
        let msg = await placeOrder(instId: d.instId, side: d.side, ordType: d.ordType,
                                   sz: d.sz, px: d.px)
        appendChat("system", msg)
    }

    private func toolSchemas() -> [[String: Any]] {
        [[
            "type": "function",
            "function": [
                "name": "place_order",
                "description": "帮用户下单（需用户确认）",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "instId": ["type": "string"],
                        "side": ["type": "string", "enum": ["buy", "sell"]],
                        "ordType": ["type": "string", "enum": ["limit", "market"]],
                        "sz": ["type": "string"],
                        "px": ["type": ["string", "null"]]
                    ],
                    "required": ["instId", "side", "ordType", "sz"]
                ]
            ]
        ], [
            "type": "function",
            "function": [
                "name": "get_ticker",
                "description": "查询某个交易对的最新行情",
                "parameters": [
                    "type": "object",
                    "properties": ["instId": ["type": "string"]],
                    "required": ["instId"]
                ]
            ]
        ], [
            "type": "function",
            "function": [
                "name": "get_balance",
                "description": "查询账户资产余额",
                "parameters": ["type": "object", "properties": [:]]
            ]
        ]]
    }

    private func runTool(_ call: AIToolCall) async -> (String, [String: Any], String) {
        let args = call.args
        let instId = (args["instId"] as? String) ?? "BTC-USDT"
        switch call.name {
        case "place_order":
            let side = (args["side"] as? String) ?? "buy"
            let ordType = (args["ordType"] as? String) ?? "limit"
            let sz = (args["sz"] as? String) ?? "0.001"
            let px = args["px"] as? String
            let d = OrderDraft(instId: instId, side: side, ordType: ordType, sz: sz, px: px)
            return ("place_order", args, "已生成订单草稿，等待用户确认：\(instId) \(side) \(ordType) 数量 \(sz)")
        case "get_ticker":
            let t = try? await okx.ticker(instId: instId)
            let text = t.map { "\($0.instId) 最新价 \($0.last)，24h 涨跌 \(String(format: "%.2f", $0.changePct))%" } ?? "查询失败"
            return ("get_ticker", args, text)
        case "get_balance":
            let list = (try? await okx.balance()) ?? []
            let text = list.map { "\($0.ccy) 可用 \($0.availBal) 总值 \($0.eq)" }.joined(separator: "；")
            return ("get_balance", args, text.isEmpty ? "无资产数据" : text)
        default:
            return (call.name, args, "未知工具")
        }
    }

    // MARK: - AI 策略

    func toggleStrategy() {
        strategyEnabled.toggle()
        strategyLog.append(strategyEnabled ? "策略已开启" : "策略已停止")
    }

    func runStrategyCycle() async {
        guard strategyRunning else { return }
        strategyRunning = true
        defer { strategyRunning = false }
        guard !aiKey.isEmpty, !activeInstId.isEmpty else { return }
        let prompt = """
你是一个保守的合约交易agent。根据以下行情数据，判断是否开仓。
当前标的：\(activeInstId)
最新价：\(tickers.first { $0.instId == activeInstId }?.last ?? "--")
24h涨跌：\(String(format: "%.2f", tickers.first { $0.instId == activeInstId }?.changePct ?? 0))%
最近K线收盘（旧→新）：\(candles.suffix(6).map { $0.c }.joined(separator: ","))

严格只输出 JSON，不要解释：
{"action": "buy" 或 "sell" 或 "hold", "reason": "一句话理由"}
"""
        guard let reply = try? await ai.complete(prompt: prompt),
              let data = reply.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String, action != "hold" else {
            strategyLog.append("[\(timeString())] hold / 无信号")
            return
        }
        let reason = (obj["reason"] as? String) ?? ""
        let side = action == "buy" ? "buy" : "sell"
        if strategyAutoTrade {
            let msg = await placeOrder(instId: activeInstId, side: side, ordType: "market",
                                       sz: strategyAmount, px: nil)
            strategyLog.append("[\(timeString())] \(side) → \(msg)")
        } else {
            strategyLog.append("[\(timeString())] 建议 \(side)（未自动下单）· \(reason)")
        }
    }

    private func timeString() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - 价格预测

    func predict(instId: String, currentPrice: Double) async {
        guard currentPrice > 0 else { return }
        predicting = true
        let history = candles.suffix(12).map { "\($0.timeLabel):\($0.c)" }.joined(separator: " ")
        let prompt = """
你是资深加密货币分析师。基于以下数据预测 \(instId) 未来 24 小时价格。
当前价：\(String(format: "%.4f", currentPrice))
最近K线（时间:收盘价，旧→新）：\(history)
24h涨跌：\(String(format: "%.2f", tickers.first { $0.instId == instId }?.changePct ?? 0))%

严格只输出 JSON：
{"target": 目标价数字, "pct": 涨跌幅数字, "reason": "中文一句话理由"}
"""
        var result: PricePrediction?
        if !aiKey.isEmpty, let reply = try? await ai.complete(prompt: prompt),
           let data = reply.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let r = Self.parsePrediction(obj, price: currentPrice) {
            result = r
            result?.source = "AI"
        }
        if result == nil {
            let closes = candles.compactMap { Double($0.c) }
            if closes.count >= 5 {
                let n = Double(closes.count)
                let xs = (0..<closes.count).map(Double.init)
                let sumX = xs.reduce(0, +), sumY = closes.reduce(0, +)
                let meanX = sumX / n, meanY = sumY / n
                let cov = zip(xs, closes).reduce(0.0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
                let varX = xs.reduce(0.0) { $0 + ($0 - meanX) * ($0 - meanX) }
                let slope = varX > 0 ? cov / varX : 0
                let target = max(closes.last! + slope * 6, 0.0001)
                let pct = (target - currentPrice) / currentPrice * 100
                result = PricePrediction(target: target, pct: pct, reason: "技术面线性回归外推", source: "技术")
            }
        }
        prediction = result
        predicting = false
        if let r = result {
            predictionRecords.append(PredictionRecord(instId: instId, target: r.target, pct: r.pct,
                                                      price: currentPrice, date: Date()))
            if predictionRecords.count > 200 { predictionRecords.removeFirst(predictionRecords.count - 200) }
            Storage.save(predictionRecords, key: "okxai.predrecords")
            recomputePredictionStats()
        }
    }

    /// 命中率：预测方向与之后实际涨跌方向是否一致
    private func recomputePredictionStats() {
        predictionTotal = predictionRecords.count
        var hits = 0
        var counted = 0
        for i in 1..<predictionRecords.count {
            let prev = predictionRecords[i - 1]
            let cur = predictionRecords[i]
            guard prev.instId == cur.instId, prev.price > 0 else { continue }
            let actual = (cur.price - prev.price) / prev.price * 100
            counted += 1
            if (prev.pct >= 0 && actual >= 0) || (prev.pct < 0 && actual < 0) { hits += 1 }
        }
        predictionHits = hits
        predictionTotal = counted
    }

    private static func parsePrediction(_ obj: [String: Any], price: Double) -> PricePrediction? {
        guard let target = (obj["target"] as? NSNumber)?.doubleValue ?? Double(obj["target"] as? String ?? ""),
              let pct = (obj["pct"] as? NSNumber)?.doubleValue ?? Double(obj["pct"] as? String ?? "")
        else { return nil }
        return PricePrediction(target: target,
                               pct: pct,
                               reason: (obj["reason"] as? String) ?? "AI 综合判断",
                               source: "AI")
    }

    // MARK: - 策略回测

    func runBacktest(instId: String) {
        Task {
            backtesting = true
            let bars = (try? await okx.candles(instId: instId, bar: "1H", limit: 300)) ?? []
            let sorted = bars.sorted { (Double($0.ts) ?? 0) < (Double($1.ts) ?? 0) }
            backtest = Backtest.run(candles: sorted,
                                   fast: max(Int(backtestFast), 1),
                                   slow: max(Int(backtestSlow), Int(backtestFast) + 1))
            backtesting = false
            if backtest != nil { Haptics.ok() } else { Haptics.warn() }
        }
    }

    // MARK: - 安全锁 / 提示

    func unlock() {
        Task {
            let ok = await AppLock.authenticate(reason: "解锁 \(appName)")
            if ok {
                locked = false
                Haptics.ok()
            } else {
                Haptics.fail()
            }
        }
    }

    func lockNow() { locked = true }

    func notify(_ text: String) {
        notice = text
        let captured = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.notice == captured else { return }
            self.notice = ""
        }
    }
}
