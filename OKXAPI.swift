import Foundation
import CryptoKit

enum OKXError: Error, LocalizedError {
    case http(Int, String)
    case api(String, String)
    case badURL

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        case .api(let code, let msg):  return "OKX 错误 \(code): \(msg)"
        case .badURL:                 return "无效的请求地址"
        }
    }
}

/// 欧易 OKX v5 API 客户端（含请求签名 / 模拟盘头）
final class OKXAPI {
    static let shared = OKXAPI()

    var apiKey = ""
    var secretKey = ""
    var passphrase = ""
    /// 模拟盘开关：打开后所有私有请求带 x-simulated-trading: 1
    var demoTrading = true

    private let base = URL(string: "https://www.okx.com")!
    private let session: URLSession = .shared

    // MARK: - 签名

    /// OKX 时间戳格式：2025-01-01T00:00:00.000Z（UTC，毫秒）
    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func sign(_ message: String) -> String {
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(code).base64EncodedString()
    }

    // MARK: - 通用请求

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        auth: Bool = false,
        as type: T.Type
    ) async throws -> T {
        guard var comps = URLComponents(url: base.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else {
            throw OKXError.badURL
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw OKXError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15

        var bodyData: Data?
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = bodyData
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        if auth {
            let ts = timestamp()
            let bodyStr = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestPath = path + (comps.query.map { "?\($0)" } ?? "")
            let message = ts + method + requestPath + bodyStr

            req.setValue(apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
            req.setValue(sign(message), forHTTPHeaderField: "OK-ACCESS-SIGN")
            req.setValue(ts, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
            req.setValue(passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
            if demoTrading {
                req.setValue("1", forHTTPHeaderField: "x-simulated-trading")
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw OKXError.http(-1, "无法解析响应")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            throw OKXError.http(http.statusCode, text)
        }
        let decoded = try JSONDecoder().decode(OKXResponse<T>.self, from: data)
        guard decoded.code == "0" else {
            throw OKXError.api(decoded.code, decoded.msg)
        }
        return decoded.data
    }

    // MARK: - 行情（公共接口）

    func tickers(instType: String = "SPOT") async throws -> [Ticker] {
        try await request("/api/v5/market/tickers",
                          query: ["instType": instType],
                          as: [Ticker].self)
    }

    func ticker(instId: String) async throws -> [Ticker] {
        try await request("/api/v5/market/ticker",
                          query: ["instId": instId],
                          as: [Ticker].self)
    }

    // MARK: - 资产（私有接口）

    func balance(ccy: String? = nil) async throws -> [BalanceDetail] {
        var query: [String: String] = [:]
        if let ccy, !ccy.isEmpty { query["ccy"] = ccy }
        return try await request("/api/v5/account/balance",
                                 query: query, auth: true,
                                 as: [BalanceDetail].self)
    }

    func positions(instType: String = "SWAP") async throws -> [Position] {
        try await request("/api/v5/account/positions",
                          query: ["instType": instType], auth: true,
                          as: [Position].self)
    }

    // MARK: - 交易（私有接口）

    /// 下单。参数示例：instId=BTC-USDT, side=buy, ordType=market, sz=0.001, tdMode=cash
    func placeOrder(instId: String, side: String, ordType: String,
                    sz: String, px: String? = nil,
                    tdMode: String = "cash", posSide: String? = nil) async throws -> [OrderResult] {
        var body: [String: Any] = [
            "instId": instId, "side": side, "ordType": ordType,
            "sz": sz, "tdMode": tdMode
        ]
        if let px, !px.isEmpty { body["px"] = px }
        if let posSide, !posSide.isEmpty { body["posSide"] = posSide }
        return try await request("/api/v5/trade/order", method: "POST",
                                 body: body, auth: true,
                                 as: [OrderResult].self)
    }

    func pendingOrders(instType: String = "SPOT") async throws -> [Order] {
        try await request("/api/v5/trade/orders-pending",
                          query: ["instType": instType], auth: true,
                          as: [Order].self)
    }

    func cancelOrder(instId: String, ordId: String) async throws -> [OrderResult] {
        let body: [String: Any] = ["instId": instId, "ordId": ordId]
        return try await request("/api/v5/trade/cancel-order", method: "POST",
                                 body: body, auth: true,
                                 as: [OrderResult].self)
    }
}
