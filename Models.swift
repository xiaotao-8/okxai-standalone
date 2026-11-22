import Foundation

// MARK: - OKX 通用响应包体
struct OKXResponse<T: Decodable>: Decodable {
    let code: String
    let msg: String
    let data: T
}

// MARK: - 行情
struct Ticker: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case instId, last, open24h, high24h, low24h, vol24h, volCcy24h
    }
    let instId: String
    let last: String
    let open24h: String
    let high24h: String
    let low24h: String
    let vol24h: String
    let volCcy24h: String
    var id: String { instId }

    var lastPrice: Double { Double(last) ?? 0 }
    var openPrice: Double { Double(open24h) ?? 0 }
    /// 24h 涨跌幅（%）
    var changePct: Double {
        guard openPrice != 0 else { return 0 }
        return (lastPrice - openPrice) / openPrice * 100
    }
}

// MARK: - 资产
struct BalanceDetail: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case ccy, eq, cashBal, frozenBal, availBal
    }
    let ccy: String
    let eq: String          // 单币种权益（折 USD）
    let cashBal: String
    let frozenBal: String
    let availBal: String
    var id: String { ccy }
    var eqValue: Double { Double(eq) ?? 0 }
}

// MARK: - 持仓
struct Position: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case instId, pos, posCcy, avgPx, upl, uplRatio, lever, mgnMode
    }
    let instId: String
    let pos: String
    let posCcy: String
    let avgPx: String
    let upl: String
    let uplRatio: String
    let lever: String
    let mgnMode: String
    var id: String { instId }
    var posValue: Double { Double(pos) ?? 0 }
    var uplValue: Double { Double(upl) ?? 0 }
}

// MARK: - 订单
struct Order: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case ordId, instId, side, posSide, tdMode, ordType, sz, px, state, cTime
    }
    let ordId: String
    let instId: String
    let side: String
    let posSide: String
    let tdMode: String
    let ordType: String
    let sz: String
    let px: String
    let state: String
    let cTime: String
    var id: String { ordId }
}

// MARK: - 下单结果
struct OrderResult: Codable {
    enum CodingKeys: String, CodingKey {
        case ordId, clOrdId, sCode, sMsg
    }
    let ordId: String
    let clOrdId: String
    let sCode: String
    let sMsg: String
    var success: Bool { sCode == "0" }
}

// MARK: - 聊天消息
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // user / assistant / system / tool
    var text: String
    /// AI 生成的、等待用户确认的订单草稿
    var orderDraft: OrderDraft?
    /// AI 执行的欧易工具调用（显示为操作卡片）
    var toolCall: ToolCallInfo? = nil
}

/// AI 执行的一次欧易工具调用
struct ToolCallInfo {
    let name: String // get_ticker / get_balance / get_positions / place_order
    let success: Bool
    var title: String {
        switch name {
        case "get_ticker": return "查询行情"
        case "get_balance": return "查询余额"
        case "get_positions": return "查询持仓"
        case "place_order": return "下单"
        default: return name
        }
    }
    var icon: String {
        switch name {
        case "get_ticker": return "magnifyingglass"
        case "get_balance": return "wallet.bifold"
        case "get_positions": return "list.bullet"
        case "place_order": return "cart"
        default: return "bolt"
        }
    }
}

/// AI 提议但尚未执行的订单
struct OrderDraft: Codable {
    let instId: String
    let side: String      // buy / sell
    let ordType: String   // market / limit
    let sz: String
    let px: String?
}
