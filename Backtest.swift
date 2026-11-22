import Foundation

// MARK: - 策略回测（双均线交叉）

struct BacktestTrade: Identifiable, Codable {
    let id: UUID
    let idx: Int
    let side: String
    let px: Double
    init(idx: Int, side: String, px: Double) {
        self.id = UUID()
        self.idx = idx
        self.side = side
        self.px = px
    }
}

struct BacktestResult {
    let equity: [EquityPoint]
    let trades: [BacktestTrade]
    let totalReturn: Double      // 百分比
    let winRate: Double          // 百分比
    let maxDrawdown: Double      // 百分比
    let winCount: Int
    let lossCount: Int
    var tradeCount: Int { trades.count }
}

enum Backtest {

    /// 双均线金叉买入 / 死叉卖出，按复利累计净值
    static func run(candles: [Candle], fast: Int = 5, slow: Int = 20) -> BacktestResult? {
        let closes = candles.map { $0.close }
        guard closes.count > slow + 2, fast > 0, slow > fast else { return nil }

        let f = Indicator.ma(closes, fast)
        let s = Indicator.ma(closes, slow)

        var equity = 1.0
        var curve = [EquityPoint]()
        var trades = [BacktestTrade]()
        var wins = 0, losses = 0
        var peak = 1.0, mdd = 0.0
        var inPos = false
        var entry = 0.0

        for i in 1..<closes.count {
            let prev = i - 1
            let fv = f[i], sv = s[i], fp = f[prev], sp = s[prev]
            let valid = !fv.isNaN && !sv.isNaN && !fp.isNaN && !sp.isNaN
            let crossUp = valid && fp < sp && fv >= sv
            let crossDown = valid && fp > sp && fv <= sv

            if !inPos && crossUp {
                inPos = true
                entry = closes[i]
                trades.append(BacktestTrade(idx: i, side: "buy", px: closes[i]))
            } else if inPos && crossDown {
                inPos = false
                let r = closes[i] / entry
                equity *= r
                trades.append(BacktestTrade(idx: i, side: "sell", px: closes[i]))
                if r >= 1 { wins += 1 } else { losses += 1 }
            }

            let v = inPos ? equity * closes[i] / entry : equity
            curve.append(EquityPoint(t: candles[i].time, v: v))
            peak = max(peak, v)
            mdd = max(mdd, peak > 0 ? (peak - v) / peak : 0)
        }

        let closed = wins + losses
        return BacktestResult(
            equity: curve,
            trades: trades,
            totalReturn: (equity - 1) * 100,
            winRate: closed > 0 ? Double(wins) / Double(closed) * 100 : 0,
            maxDrawdown: mdd * 100,
            winCount: wins,
            lossCount: losses
        )
    }
}
