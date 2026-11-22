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

// MARK: - 资金：充币地址 / 划转结果 / 账单
struct DepositAddress: Codable {
    enum CodingKeys: String, CodingKey {
        case addr, tag, memo, chain, ccy
    }
    let addr: String
    let tag: String?
    let memo: String?
    let chain: String?
    let ccy: String?
}

struct TransferResult: Codable {
    enum CodingKeys: String, CodingKey {
        case transId
    }
    let transId: String
}

struct Bill: Identifiable, Codable {
    enum CodingKeys: String, CodingKey {
        case billId, ccy, balChg, bal, type, ts, instId
    }
    let billId: String
    let ccy: String
    let balChg: String
    let bal: String
    let type: String
    let ts: String
    let instId: String?
    var id: String { billId }
    var changeValue: Double { Double(balChg) ?? 0 }
    var timeText: String {
        guard let ms = Double(ts) else { return ts }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - 价格预测
struct PricePrediction {
    var target: Double
    var pct: Double
    var reason: String
    var source: String = "AI"
}

// MARK: - 聊天消息
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String // user / assistant / system / tool
    var text: String
    /// AI 生成的、等待用户确认的订单草稿
    var orderDraft: OrderDraft?
}

/// AI 提议但尚未执行的订单
struct OrderDraft: Codable {
    let instId: String
    let side: String      // buy / sell
    let ordType: String   // market / limit
    let sz: String
    let px: String?
}

// MARK: - K 线（OKX 返回的是数组：[ts, o, h, l, c, vol, volCcy]）
struct Candle: Identifiable, Decodable {
    var id: String { ts }
    let ts: String
    let o: String
    let h: String
    let l: String
    let c: String
    let vol: String

    init?(arr: [String]) {
        guard arr.count >= 5 else { return nil }
        ts = arr[0]; o = arr[1]; h = arr[2]; l = arr[3]; c = arr[4]
        vol = arr.count > 5 ? arr[5] : "0"
    }

    var open: Double { Double(o) ?? 0 }
    var close: Double { Double(c) ?? 0 }
    var high: Double { Double(h) ?? 0 }
    var low: Double { Double(l) ?? 0 }

    var timeLabel: String {
        guard let ms = Double(ts) else { return ts }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
