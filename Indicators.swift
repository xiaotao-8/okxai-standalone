import Foundation

// MARK: - 技术指标（MA / EMA / RSI / MACD / BOLL）

/// K 线图表上的均线点
struct MAPoint: Identifiable {
    let id = UUID()
    let label: String
    let v: Double
}

/// 深度图上的累计量点
struct DepthPoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

enum Indicator {

    /// 简单移动平均，不足周期的位置为 NaN
    static func ma(_ src: [Double], _ period: Int) -> [Double] {
        guard period > 0, !src.isEmpty else { return [] }
        var out = [Double]()
        out.reserveCapacity(src.count)
        var sum = 0.0
        for i in 0..<src.count {
            sum += src[i]
            if i >= period { sum -= src[i - period] }
            out.append(i >= period - 1 ? sum / Double(period) : .nan)
        }
        return out
    }

    /// 指数移动平均
    static func ema(_ src: [Double], period: Int) -> [Double] {
        guard period > 0, !src.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var out = [src[0]]
        out.reserveCapacity(src.count)
        for i in 1..<src.count {
            out.append(src[i] * k + out[i - 1] * (1 - k))
        }
        return out
    }

    /// RSI（Wilder 平滑）
    static func rsi(_ src: [Double], period: Int = 14) -> Double {
        guard src.count > period, period > 0 else { return 50 }
        var gain = 0.0, loss = 0.0
        for i in 1...period {
            let d = src[i] - src[i - 1]
            if d >= 0 { gain += d } else { loss -= d }
        }
        var avgG = gain / Double(period)
        var avgL = loss / Double(period)
        if avgL == 0 { return 100 }
        for i in (period + 1)..<src.count {
            let d = src[i] - src[i - 1]
            avgG = (avgG * Double(period - 1) + max(d, 0)) / Double(period)
            avgL = (avgL * Double(period - 1) + max(-d, 0)) / Double(period)
            if avgL == 0 { return 100 }
        }
        let rs = avgG / avgL
        return 100 - 100 / (1 + rs)
    }

    /// MACD（12/26/9）
    static func macd(_ src: [Double]) -> (dif: [Double], dea: [Double], hist: [Double]) {
        let e12 = ema(src, period: 12)
        let e26 = ema(src, period: 26)
        let dif = zip(e12, e26).map { $0.0 - $0.1 }
        let dea = ema(dif, period: 9)
        let hist = zip(dif, dea).map { ($0.0 - $0.1) * 2 }
        return (dif, dea, hist)
    }

    /// 布林带（20 周期，2 倍标准差）
    static func boll(_ src: [Double], period: Int = 20, width: Double = 2) -> (mid: [Double], up: [Double], low: [Double]) {
        let mid = ma(src, period)
        var up = [Double]()
        var low = [Double]()
        up.reserveCapacity(src.count)
        low.reserveCapacity(src.count)
        for i in 0..<src.count {
            guard i >= period - 1, period > 0 else {
                up.append(.nan); low.append(.nan); continue
            }
            let m = mid[i]
            var variance = 0.0
            for j in (i - period + 1)...i {
                variance += (src[j] - m) * (src[j] - m)
            }
            variance /= Double(period)
            let sd = sqrt(max(variance, 0))
            up.append(m + width * sd)
            low.append(m - width * sd)
        }
        return (mid, up, low)
    }

    /// 取数组中最后一个有效值（跳过 NaN）
    static func lastValid(_ arr: [Double]) -> Double? {
        arr.last(where: { !$0.isNaN })
    }
}
