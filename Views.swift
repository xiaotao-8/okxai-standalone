import SwiftUI
import Charts

// MARK: - 行情

struct MarketView: View {
    @EnvironmentObject var store: AppStore
    @Binding var tab: Int
    @State private var search = ""
    @State private var scope = 0
    @State private var showAlerts = false

    private var filtered: [Ticker] {
        let base = scope == 1 ? store.tickers.filter { store.isWatched($0.instId) } : store.tickers
        guard !search.isEmpty else { return base }
        return base.filter { $0.instId.uppercased().contains(search.uppercased()) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("范围", selection: $scope) {
                        Text("全部").tag(0)
                        Text("自选").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(filtered) { t in
                        NavigationLink(value: t.instId) {
                            TickerRow(ticker: t,
                                      isWatched: store.isWatched(t.instId),
                                      onWatch: { store.toggleWatch(t.instId) })
                        }
                        .listRowBackground(Color.cardBg)
                        .listRowSeparatorTint(Color.line)
                    }
                } header: {
                    HStack {
                        Text("名称 / 交易对")
                        Spacer()
                        Text("最新价")
                        Text("24h涨跌").frame(width: 78, alignment: .trailing)
                    }
                    .textCase(nil)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBg.ignoresSafeArea())
            .searchable(text: $search, prompt: "搜索币种")
            .refreshable { await store.refreshMarket() }
            .navigationTitle("行情")
            .navigationDestination(for: String.self) { instId in
                TickerDetailView(instId: instId, tab: $tab)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 18) {
                        Button { showAlerts = true } label: {
                            Image(systemName: store.alerts.contains(where: { !$0.isTriggered }) ? "bell.badge" : "bell")
                                .foregroundStyle(Color.accent)
                        }
                        Button { tab = 4 } label: {
                            Label("智能体", systemImage: "sparkles")
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAlerts) { AlertsView() }
            .task { await store.refreshMarket() }
        }
    }
}

struct TickerRow: View {
    let ticker: Ticker
    var isWatched: Bool = false
    var onWatch: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            CoinIcon(symbol: ticker.instId.replacingOccurrences(of: "-USDT", with: ""))
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker.instId.components(separatedBy: "-").first ?? ticker.instId)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(ticker.instId)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            PriceText(value: ticker.last)
                .frame(width: 88, alignment: .trailing)
            ChangeBadge(pct: ticker.changePct)
                .frame(width: 68, alignment: .trailing)
            if let onWatch {
                Button(action: onWatch) {
                    Image(systemName: isWatched ? "star.fill" : "star")
                        .font(.caption)
                        .foregroundStyle(isWatched ? Color(hex: 0xF0B90B) : Color.textSecondary)
                        .frame(width: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 行情详情

struct TickerDetailView: View {
    @EnvironmentObject var store: AppStore
    let instId: String
    @Binding var tab: Int
    @State private var bar = "1H"

    private var ticker: Ticker? { store.tickers.first { $0.instId == instId } }

    /// K 线按时间升序（OKX 返回是降序）
    private var sortedCandles: [Candle] {
        store.candles.sorted { (Double($0.ts) ?? 0) < (Double($1.ts) ?? 0) }
    }

    /// AI 信号（由预测涨跌幅推导）
    private var signal: (String, Color) {
        guard let p = store.prediction else { return ("--", .textSecondary) }
        if p.pct >= 2 { return ("强烈买入", .upGreen) }
        if p.pct >= 0.5 { return ("买入", .upGreen) }
        if p.pct > -0.5 { return ("中性", .textSecondary) }
        if p.pct > -2 { return ("卖出", .downRed) }
        return ("强烈卖出", .downRed)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 价格 Hero（玻璃卡片）
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CoinIcon(symbol: instId.components(separatedBy: "-").first ?? "", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instId)
                                .font(.system(.subheadline, weight: .semibold))
                            Text("现价 (USDT)")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button { store.toggleWatch(instId) } label: {
                            Image(systemName: store.isWatched(instId) ? "star.fill" : "star")
                                .foregroundStyle(store.isWatched(instId) ? Color(hex: 0xF0B90B) : Color.textSecondary)
                        }
                        ChangeBadge(pct: ticker?.changePct ?? 0)
                    }
                    Text(ticker?.last ?? "--")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle((ticker?.changePct ?? 0) >= 0 ? .upGreen : .downRed)

                    HStack {
                        stat("24h最高", ticker?.high24h ?? "--")
                        stat("24h最低", ticker?.low24h ?? "--")
                        stat("24h量", ticker?.vol24h ?? "--")
                    }
                }
                .padding()
                .glassCard()

                // K 线
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ForEach(["1m", "5m", "15m", "30m", "1H", "4H", "1D", "1W"], id: \.self) { b in
                            Button(b) {
                                bar = b
                                store.candleBar = b
                                Task { await store.loadCandles(instId: instId, bar: b) }
                            }
                            .font(.caption)
                            .foregroundStyle(bar == b ? .appBg : .textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(bar == b ? Color.accent : Color.cardBg2, in: Capsule())
                        }
                    }
                    Chart {
                        ForEach(sortedCandles) { c in
                            RuleMark(x: .value("时间", c.timeLabel),
                                     yStart: .value("高", c.high), yEnd: .value("低", c.low))
                                .foregroundStyle(c.close >= c.open ? Color.upGreen : Color.downRed)
                            BarMark(x: .value("时间", c.timeLabel),
                                    yStart: .value("开", c.open), yEnd: .value("收", c.close))
                                .foregroundStyle(c.close >= c.open ? Color.upGreen : Color.downRed)
                        }
                        ForEach(maPoints(5)) { p in
                            LineMark(x: .value("时间", p.label), y: .value("MA5", p.v))
                                .foregroundStyle(Color(hex: 0xF0B90B))
                        }
                        ForEach(maPoints(10)) { p in
                            LineMark(x: .value("时间", p.label), y: .value("MA10", p.v))
                                .foregroundStyle(Color(hex: 0x6A5CFF))
                        }
                        ForEach(maPoints(20)) { p in
                            LineMark(x: .value("时间", p.label), y: .value("MA20", p.v))
                                .foregroundStyle(Color(hex: 0x00C2FF))
                        }
                    }
                    .frame(height: 220)

                    HStack(spacing: 14) {
                        legendDot(Color(hex: 0xF0B90B), "MA5")
                        legendDot(Color(hex: 0x6A5CFF), "MA10")
                        legendDot(Color(hex: 0x00C2FF), "MA20")
                        Spacer()
                        Text("共 \(sortedCandles.count) 根")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Chart(sortedCandles) { c in
                        BarMark(x: .value("时间", c.timeLabel), y: .value("量", Double(c.vol) ?? 0))
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                    }
                    .frame(height: 60)
                    .chartYAxis(.hidden)
                }
                .padding()
                .glassCard()

                // 技术指标
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "技术指标")
                    let tech = techValues
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        techCell("RSI(14)", fmt(tech.rsi), rsiColor(tech.rsi))
                        techCell("MACD 柱", fmt(tech.hist), (tech.hist ?? 0) >= 0 ? Color.upGreen : Color.downRed)
                        techCell("MA5", fmt(tech.ma5), .textPrimary)
                        techCell("MA10", fmt(tech.ma10), .textPrimary)
                        techCell("MA20", fmt(tech.ma20), .textPrimary)
                        techCell("BOLL 中轨", fmt(tech.bollMid), .textPrimary)
                    }
                    HStack {
                        Text("DIF \(fmt(tech.dif)) · DEA \(fmt(tech.dea))")
                            .font(.caption2).foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(rsiHint(tech.rsi))
                            .font(.caption2)
                            .foregroundStyle(rsiColor(tech.rsi))
                    }
                }
                .padding()
                .glassCard()

                // 价格预测（AI / 技术）
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("价格预测", systemImage: "wand.and.stars")
                            .font(.system(.subheadline, weight: .semibold))
                        Spacer()
                        if let p = store.prediction {
                            Text(p.source)
                                .font(.caption2)
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accent.opacity(0.15), in: Capsule())
                            Text(signal.0)
                                .font(.caption2)
                                .foregroundStyle(signal.1)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(signal.1.opacity(0.15), in: Capsule())
                            if store.predictionTotal > 0 {
                                Text("命中率 \(store.predictionHits)/\(store.predictionTotal)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.cardBg2, in: Capsule())
                            }
                        }
                        Button {
                            Task { await store.predict(instId: instId,
                                                     currentPrice: ticker?.lastPrice ?? 0) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.predicting)
                    }

                    if store.predicting {
                        HStack {
                            ProgressView()
                            Text("正在生成预测…").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    } else if let p = store.prediction {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%.4f", p.target))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(p.pct >= 0 ? .upGreen : .downRed)
                                Text(String(format: "%+.2f%%", p.pct))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(p.pct >= 0 ? .upGreen : .downRed)
                            }
                            Spacer()
                            Text(p.reason)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text("点击右上角刷新，生成 24h 价格预测")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding()
                .glassCard()

                // 最新成交
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "最新成交")
                    if store.marketTrades.isEmpty {
                        Text("暂无数据").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    ForEach(store.marketTrades.prefix(8)) { t in
                        HStack {
                            Text(t.side == "buy" ? "买" : "卖")
                                .font(.caption2)
                                .foregroundStyle(t.side == "buy" ? .upGreen : .downRed)
                            Text(t.px ?? "--")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(t.sz ?? "--")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding()
                .glassCard()

                // 盘口深度
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "盘口深度")
                    if let b = store.book {
                        let asks = Array(b.asks.prefix(5).reversed())
                        let bids = Array(b.bids.prefix(5))
                        let maxSz = max(
                            asks.compactMap { $0.count > 1 ? Double($0[1]) : nil }.max() ?? 1,
                            bids.compactMap { $0.count > 1 ? Double($0[1]) : nil }.max() ?? 1,
                            1
                        )
                        ForEach(Array(asks.enumerated()), id: \.offset) { _, lv in
                            depthRow(price: lv.first ?? "--",
                                     size: lv.count > 1 ? lv[1] : "--",
                                     pct: (lv.count > 1 ? Double(lv[1]) ?? 0 : 0) / maxSz,
                                     color: .downRed, alignRight: true)
                        }
                        Divider().background(Color.line)
                        ForEach(Array(bids.enumerated()), id: \.offset) { _, lv in
                            depthRow(price: lv.first ?? "--",
                                     size: lv.count > 1 ? lv[1] : "--",
                                     pct: (lv.count > 1 ? Double(lv[1]) ?? 0 : 0) / maxSz,
                                     color: .upGreen, alignRight: false)
                        }
                    } else {
                        Text("暂无盘口数据").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                .padding()
                .glassCard()

                // 深度图（累计）
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "深度图")
                    if depthSeries.bids.isEmpty && depthSeries.asks.isEmpty {
                        Text("暂无深度数据").font(.caption).foregroundStyle(Color.textSecondary)
                    } else {
                        Chart {
                            ForEach(depthSeries.bids) { d in
                                AreaMark(x: .value("价格", d.x), y: .value("深度", d.y))
                                    .foregroundStyle(Color.upGreen.opacity(0.35))
                                LineMark(x: .value("价格", d.x), y: .value("深度", d.y))
                                    .foregroundStyle(Color.upGreen)
                            }
                            ForEach(depthSeries.asks) { d in
                                AreaMark(x: .value("价格", d.x), y: .value("深度", d.y))
                                    .foregroundStyle(Color.downRed.opacity(0.35))
                                LineMark(x: .value("价格", d.x), y: .value("深度", d.y))
                                    .foregroundStyle(Color.downRed)
                            }
                        }
                        .frame(height: 140)
                        .chartYAxis(.hidden)
                        HStack {
                            Text("买盘 \(depthTotal(true))")
                                .font(.caption2).foregroundStyle(Color.upGreen)
                            Spacer()
                            Text("卖盘 \(depthTotal(false))")
                                .font(.caption2).foregroundStyle(Color.downRed)
                        }
                    }
                }
                .padding()
                .glassCard()

                // 买卖
                HStack(spacing: 12) {
                    tradeButton("买入", "buy", Color.upGreen)
                    tradeButton("卖出", "sell", Color.downRed)
                }
            }
            .padding()
        }
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle(instId)
        .navigationBarTitleDisplayMode(.inline)
            .task {
                store.candleBar = bar
                await store.loadCandles(instId: instId, bar: bar)
                await store.loadMarketTrades(instId: instId)
                await store.loadBook(instId: instId)
                await store.predict(instId: instId, currentPrice: ticker?.lastPrice ?? 0)
            }
    }

    // MARK: - 指标计算

    private var closes: [Double] { sortedCandles.map { $0.close } }

    private func maPoints(_ period: Int) -> [MAPoint] {
        let ma = Indicator.ma(closes, period)
        return zip(sortedCandles, ma).compactMap { pair -> MAPoint? in
            guard !pair.1.isNaN else { return nil }
            return MAPoint(label: pair.0.timeLabel, v: pair.1)
        }
    }

    private var techValues: (ma5: Double?, ma10: Double?, ma20: Double?, rsi: Double,
                              dif: Double?, dea: Double?, hist: Double?,
                              bollUp: Double?, bollMid: Double?, bollLow: Double?) {
        let ma5 = Indicator.ma(closes, 5)
        let ma10 = Indicator.ma(closes, 10)
        let ma20 = Indicator.ma(closes, 20)
        let m = Indicator.macd(closes)
        let b = Indicator.boll(closes)
        return (Indicator.lastValid(ma5), Indicator.lastValid(ma10), Indicator.lastValid(ma20),
                Indicator.rsi(closes),
                Indicator.lastValid(m.dif), Indicator.lastValid(m.dea), Indicator.lastValid(m.hist),
                Indicator.lastValid(b.up), Indicator.lastValid(b.mid), Indicator.lastValid(b.low))
    }

    private func fmt(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "--" }

    private func rsiColor(_ v: Double) -> Color {
        if v >= 70 { return .downRed }
        if v <= 30 { return .upGreen }
        return .textSecondary
    }

    private func rsiHint(_ v: Double) -> String {
        if v >= 70 { return "超买区" }
        if v >= 55 { return "偏强" }
        if v > 45 { return "中性" }
        if v > 30 { return "偏弱" }
        return "超卖区"
    }

    private func techCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - 深度图

    private var depthSeries: (bids: [DepthPoint], asks: [DepthPoint]) {
        guard let b = store.book else { return ([], []) }
        func parse(_ lv: [String]) -> (Double, Double)? {
            guard lv.count > 1, let p = Double(lv[0]), let s = Double(lv[1]) else { return nil }
            return (p, s)
        }
        let bidLv = b.bids.compactMap(parse).sorted { $0.0 > $1.0 }
        let askLv = b.asks.compactMap(parse).sorted { $0.0 < $1.0 }
        var cum = 0.0
        let bids = bidLv.map { v -> DepthPoint in cum += v.1; return DepthPoint(x: v.0, y: cum) }
        cum = 0.0
        let asks = askLv.map { v -> DepthPoint in cum += v.1; return DepthPoint(x: v.0, y: cum) }
        return (bids, asks)
    }

    private func depthTotal(_ bid: Bool) -> String {
        let arr = bid ? depthSeries.bids : depthSeries.asks
        guard let last = arr.last else { return "--" }
        let v = last.y
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1000 { return String(format: "%.1fK", v / 1000) }
        return String(format: "%.2f", v)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func depthRow(price: String, size: String, pct: Double, color: Color, alignRight: Bool) -> some View {
        HStack(spacing: 8) {
            if alignRight { Spacer(minLength: 0) }
            GeometryReader { g in
                ZStack(alignment: alignRight ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.25))
                        .frame(width: max(2, g.size.width * min(pct, 1)))
                    HStack(spacing: 6) {
                        Text(price).font(.system(.caption2, design: .monospaced))
                        Text(size).font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .frame(height: 18)
            if !alignRight { Spacer(minLength: 0) }
        }
    }

    private func tradeButton(_ title: String, _ value: String, _ color: Color) -> some View {
        Button {
            store.activeInstId = instId
            tab = 2
        } label: {
            Label(title, systemImage: value == "buy" ? "arrow.up" : "arrow.down")
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(PressScale())
    }
}

// MARK: - 资产

struct AccountView: View {
    @EnvironmentObject var store: AppStore
    @State private var hideBalance = false

    private var total: Double { store.balances.reduce(0) { $0 + $1.eqValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 总资产 Hero
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("总资产估值")
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            Button { hideBalance.toggle() } label: {
                                Image(systemName: hideBalance ? "eye.slash" : "eye")
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text("模拟盘")
                                .font(.caption2)
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.accent.opacity(0.15), in: Capsule())
                        }
                        Text(hideBalance ? "****" : String(format: "$ %.2f", total))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                    }
                    .padding()
                    .glassCard()

                    // 余额
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "余额")
                        if store.balances.isEmpty {
                            Text("暂无数据").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        ForEach(store.balances) { b in
                            HStack {
                                CoinIcon(symbol: b.ccy, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.ccy).font(.system(.body, weight: .semibold)).foregroundStyle(Color.textPrimary)
                                    Text("可用 \(b.availBal)").font(.caption2).foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Text(hideBalance ? "****" : b.eq)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(Color.textPrimary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding()
                    .glassCard()

                    // 持仓
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "持仓")
                        if store.positions.isEmpty {
                            Text("暂无持仓").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        ForEach(store.positions) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.instId).font(.system(.body, weight: .semibold)).foregroundStyle(Color.textPrimary)
                                    Text("\(p.posSide) \(p.pos) · \(p.lever)x")
                                        .font(.caption2).foregroundStyle(Color.textSecondary)
                                    if p.liqPxValue > 0 {
                                        Text("强平 \(String(format: "%.2f", p.liqPxValue)) · 风险率 \(String(format: "%.1f", p.riskRatioValue))%")
                                            .font(.caption2)
                                            .foregroundStyle(p.riskRatioValue > 80 ? Color.downRed : Color.textSecondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.2f", p.uplValue))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(p.uplValue >= 0 ? .upGreen : .downRed)
                                    Text("均价 \(p.avgPx)")
                                        .font(.caption2).foregroundStyle(Color.textSecondary)
                                    if p.markPxValue > 0 {
                                        Text("标记 \(String(format: "%.2f", p.markPxValue))")
                                            .font(.caption2).foregroundStyle(Color.textSecondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding()
                    .glassCard()

                    // 资金流水
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "资金流水")
                        if store.bills.isEmpty {
                            Text("暂无流水").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        ForEach(store.bills.prefix(8)) { b in
                            HStack {
                                Text(b.ccy ?? "--").font(.system(.body, weight: .semibold)).foregroundStyle(Color.textPrimary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(b.balChg ?? "--")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle((Double(b.balChg ?? "0") ?? 0) >= 0 ? .upGreen : .downRed)
                                    Text("余额 \(b.bal ?? "--")")
                                        .font(.caption2).foregroundStyle(Color.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .glassCard()

                    // 净值曲线
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "净值曲线")
                        if store.equityHistory.count < 2 {
                            Text("暂无数据（刷新账户后生成）")
                                .font(.caption).foregroundStyle(Color.textSecondary)
                        } else {
                            Chart(store.equityHistory) { p in
                                LineMark(x: .value("时间", p.t), y: .value("净值", p.v))
                                    .foregroundStyle(Color.accent)
                                    .interpolationMethod(.catmullRom)
                            }
                            .frame(height: 140)
                            .chartXAxis(.hidden)
                        }
                    }
                    .padding()
                    .glassCard()
                }
                .padding()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("资产")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refreshAccount() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await store.loadBills() }
        }
    }
}

// MARK: - 交易

struct TradeView: View {
    @EnvironmentObject var store: AppStore
    @State private var tradeTab = 0
    @State private var side = "buy"
    @State private var ordKind = "limit"   // limit / market / conditional / move_order_stop
    @State private var px = ""
    @State private var sz = ""
    @State private var tpPx = ""
    @State private var slPx = ""
    @State private var trigPx = ""
    @State private var trailPct = "1"
    @State private var activePx = ""
    @State private var pct: Double = 0
    @State private var message = ""
    @State private var cancelMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("交易", selection: $tradeTab) {
                        Text("下单").tag(0)
                        Text("当前委托").tag(1)
                        Text("历史").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if tradeTab == 0 {
                        orderForm
                    } else if tradeTab == 1 {
                        ordersList
                    } else {
                        historyList
                    }
                }
                .padding()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("交易")
            .task { await store.loadOrders(); await store.loadHistory() }
        }
    }

    // MARK: 历史委托 / 成交

    private var historyList: some View {
        VStack(spacing: 12) {
            if store.historyOrders.isEmpty && store.fills.isEmpty {
                Text("暂无历史记录").font(.caption).foregroundStyle(Color.textSecondary)
            }
            if !store.historyOrders.isEmpty {
                SectionTitle(title: "历史委托")
                ForEach(store.historyOrders.prefix(10)) { o in
                    HStack {
                        Text(o.instId).font(.system(.body, weight: .semibold))
                        Spacer()
                        Text(o.side.uppercased())
                            .font(.caption)
                            .foregroundStyle(o.side == "buy" ? Color.upGreen : Color.downRed)
                        Text("\(o.ordType) · \(o.sz) · \(o.state)")
                            .font(.caption2).foregroundStyle(Color.textSecondary)
                    }
                    .padding()
                    .glassCard(radius: 14)
                }
            }
            if !store.fills.isEmpty {
                SectionTitle(title: "历史成交")
                ForEach(store.fills.prefix(10)) { f in
                    HStack {
                        Text(f.instId ?? "--").font(.system(.body, weight: .semibold))
                        Spacer()
                        Text(f.side?.uppercased() ?? "--")
                            .font(.caption)
                            .foregroundStyle(f.side == "buy" ? Color.upGreen : Color.downRed)
                        Text("\(f.fillSz ?? "--") @ \(f.fillPx ?? "--")")
                            .font(.caption2).foregroundStyle(Color.textSecondary)
                    }
                    .padding()
                    .glassCard(radius: 14)
                }
            }
        }
    }

    // MARK: 下单表单

    private var orderForm: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                sideButton("买入", "buy", Color.upGreen)
                sideButton("卖出", "sell", Color.downRed)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("交易对").font(.caption).foregroundStyle(Color.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(store.orderInstId)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Color.accent)
                        Text(store.tradeMode == "swap" ? "永续合约" : "现货")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // 交易模式
                Picker("模式", selection: $store.tradeMode) {
                    Text("现货").tag("spot")
                    Text("合约").tag("swap")
                }
                .pickerStyle(.segmented)

                if store.tradeMode == "swap" {
                    Picker("方向", selection: $store.posSide) {
                        Text("做多").tag("long")
                        Text("做空").tag("short")
                    }
                    .pickerStyle(.segmented)
                }

                Picker("类型", selection: $ordKind) {
                    Text("限价").tag("limit")
                    Text("市价").tag("market")
                    Text("计划").tag("conditional")
                    Text("跟踪").tag("move_order_stop")
                }
                .pickerStyle(.segmented)

                if ordKind == "limit" || ordKind == "conditional" || ordKind == "move_order_stop" {
                    field("价格", $px, "USDT")
                }
                field("数量", $sz, store.activeInstId.components(separatedBy: "-").first ?? "")

                Divider().background(Color.line)
                field("止盈价(选填)", $tpPx, "USDT")
                field("止损价(选填)", $slPx, "USDT")

                if ordKind == "conditional" {
                    field("触发价", $trigPx, "USDT")
                }
                if ordKind == "move_order_stop" {
                    field("回调比例(%)", $trailPct, "%")
                    field("激活价(选填)", $activePx, "USDT")
                }

                // 杠杆 & 保证金模式
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("杠杆").font(.caption).foregroundStyle(Color.textSecondary)
                        Spacer()
                        Picker("杠杆", selection: $store.lever) {
                            ForEach(["1", "2", "3", "5", "10", "20"], id: \.self) { Text("\($0)x").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accent)
                    }
                    Picker("保证金模式", selection: $store.mgnMode) {
                        Text("逐仓").tag("isolated")
                        Text("全仓").tag("cross")
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("仓位比例").font(.caption).foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(Int(pct * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.accent)
                    }
                    Slider(value: $pct, in: 0...1, step: 0.25)
                        .tint(Color.accent)
                }
            }
            .padding()
            .glassCard()

            Button {
                Task {
                    message = await store.placeOrder(instId: store.activeInstId, side: side,
                                                      ordType: ordKind, sz: sz,
                                                      px: px.isEmpty ? nil : px,
                                                      tpTriggerPx: tpPx.isEmpty ? nil : tpPx,
                                                      slTriggerPx: slPx.isEmpty ? nil : slPx,
                                                      triggerPx: trigPx.isEmpty ? nil : trigPx,
                                                      callbackRatio: ordKind == "move_order_stop" ? trailPct : nil,
                                                      activePx: activePx.isEmpty ? nil : activePx)
                }
            } label: {
                Text(side == "buy" ? "买入 \(store.activeInstId)" : "卖出 \(store.activeInstId)")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(side == "buy" ? Color.upGreen : Color.downRed,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressScale())
            .disabled(!store.hasOKXKeys)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 当前委托

    private var ordersList: some View {
        VStack(spacing: 12) {
            if store.pendingOrders.isEmpty {
                Text("暂无当前委托").font(.caption).foregroundStyle(Color.textSecondary)
            }
            ForEach(store.pendingOrders) { o in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(o.instId).font(.system(.body, weight: .semibold))
                        Spacer()
                        Text(o.side.uppercased())
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(o.side == "buy" ? Color.upGreen : Color.downRed)
                    }
                    HStack {
                        Text("\(o.ordType) · 数量 \(o.sz) · 价格 \(o.px)")
                            .font(.caption).foregroundStyle(Color.textSecondary)
                        Spacer()
                        Button("撤单") {
                            Task { cancelMsg = await store.cancel(ordId: o.ordId, instId: o.instId) }
                        }
                        .font(.caption)
                        .foregroundStyle(Color.downRed)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.downRed.opacity(0.15), in: Capsule())
                    }
                }
                .padding()
                .glassCard()
            }
            if !cancelMsg.isEmpty {
                Text(cancelMsg).font(.caption).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func sideButton(_ title: String, _ value: String, _ color: Color) -> some View {
        Button { side = value } label: {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(side == value ? color : Color.cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(side == value ? .white : .textSecondary)
        }
        .buttonStyle(PressScale())
    }

    private func field(_ title: String, _ binding: Binding<String>, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Color.textSecondary)
            HStack {
                TextField("0.00", text: binding)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Text(unit).font(.caption).foregroundStyle(Color.textSecondary)
            }
            .padding(12)
            .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - 智能体（AI 聊天）

struct AIChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            strategyCard
                            backtestCard
                            if store.chat.isEmpty {
                                emptyState
                            }
                            ForEach(store.chat) { m in
                                bubble(m).id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.chat.count) { _ in
                        if let last = store.chat.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                // 输入栏
                HStack(spacing: 10) {
                    TextField("问智能体…", text: $input)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .foregroundStyle(Color.textPrimary)
                    Button {
                        let t = input; input = ""
                        Task { await store.sendChat(t) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(store.busy || input.isEmpty ? Color.line : Color.accent, in: Circle())
                    }
                    .disabled(store.busy || input.isEmpty)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: input.isEmpty)
                }
                .padding()
                .background(.bar, in: Rectangle())
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("智能体")
        }
    }

    // MARK: - AI 策略卡

    private var strategyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI 策略", systemImage: "cpu")
                    .font(.system(.subheadline, weight: .semibold))
                Spacer()
                Toggle("开启", isOn: Binding(
                    get: { store.strategyEnabled },
                    set: { _ in store.toggleStrategy() }
                ))
                .tint(Color.accent)
                .labelsHidden()
            }

            if store.strategyEnabled {
                Toggle("自动下单（谨慎，默认仅建议）", isOn: $store.strategyAutoTrade)
                    .tint(Color.accent)
                    .font(.caption)

                HStack {
                    Text("每次数量")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                    Spacer()
                    TextField("0.001", text: $store.strategyAmount)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 100)
                }

                HStack {
                    Text("间隔 \(Int(store.strategyInterval))s")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                    Slider(value: $store.strategyInterval, in: 60...3600, step: 60)
                        .tint(Color.accent)
                }

                HStack {
                    Button("立即执行一轮") {
                        Task { await store.runStrategyCycle() }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accent)
                    Spacer()
                    if store.strategyRunning { ProgressView().controlSize(.small) }
                }

                if !store.strategyLog.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.strategyLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding()
        .glassCard()
    }

    // MARK: - AI 策略回测卡

    private var backtestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("策略回测", systemImage: "chart.xyaxis.line")
                    .font(.system(.subheadline, weight: .semibold))
                Spacer()
                if store.backtesting { ProgressView().controlSize(.small) }
                else {
                    Button(store.backtest == nil ? "运行" : "重新运行") {
                        store.runBacktest(instId: store.activeInstId)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accent)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("快线 \(Int(store.backtestFast))")
                        .font(.caption2).foregroundStyle(Color.textSecondary)
                    Slider(value: $store.backtestFast, in: 2...20, step: 1)
                        .tint(Color.accent)
                        .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("慢线 \(Int(store.backtestSlow))")
                        .font(.caption2).foregroundStyle(Color.textSecondary)
                    Slider(value: $store.backtestSlow, in: 10...60, step: 5)
                        .tint(Color.accent)
                        .frame(width: 120)
                }
            }

            if let r = store.backtest {
                HStack(spacing: 8) {
                    btStat("收益率", String(format: "%+.2f%%", r.totalReturn),
                           r.totalReturn >= 0 ? Color.upGreen : Color.downRed)
                    btStat("胜率", String(format: "%.1f%%", r.winRate), .textPrimary)
                    btStat("最大回撤", String(format: "%.1f%%", r.maxDrawdown), Color.downRed)
                    btStat("交易次数", "\(r.tradeCount)", .textPrimary)
                }
                Chart(r.equity) { p in
                    LineMark(x: .value("时间", p.t), y: .value("净值", p.v))
                        .foregroundStyle(Color.accent)
                        .interpolationMethod(.catmullRom)
                }
                .frame(height: 110)
                .chartXAxis(.hidden)
            } else {
                Text(store.backtesting ? "回测中…" : "双均线策略 · \(store.activeInstId) · 最近 300 根 1H K 线")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding()
        .glassCard()
    }

    private func btStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.accent)
            Text("我是你的智能交易助手")
                .font(.system(.headline))
                .foregroundStyle(Color.textPrimary)
            Text("可以问我行情、查资产，或让我生成订单草稿")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.role == "user" {
            HStack {
                Spacer()
                Text(m.text)
                    .padding(12)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                CoinIcon(symbol: "AI", size: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(Color.textPrimary)
                    if let d = m.orderDraft { orderCard(d) }
                }
                Spacer()
            }
        }
    }

    private func orderCard(_ d: OrderDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("订单确认").font(.caption).foregroundStyle(Color.textSecondary)
            HStack {
                Text(d.instId).font(.system(.body, weight: .semibold))
                Spacer()
                Text(d.side.uppercased())
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(d.side == "buy" ? .upGreen : .downRed)
            }
            Text("\(d.ordType) · 数量 \(d.sz)\(d.px != nil ? " · 价格 \(d.px!)" : "")")
                .font(.caption).foregroundStyle(Color.textSecondary)
            Button {
                Task { await store.confirmDraft(d) }
            } label: {
                Label("确认下单", systemImage: "checkmark.seal.fill")
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressScale())
        }
        .padding(12)
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.accent.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ZStack {
                GradientHero()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 96, height: 96)
                                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                                Text("OKX")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.accent)
                            }
                            Text(store.appName)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.textPrimary)
                            Text("连接你的欧易账户，智能体帮你交易")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.top, 48)

                        VStack(spacing: 0) {
                            LabeledField(title: "API Key", text: $store.okxKey)
                            Divider().background(Color.line)
                            LabeledField(title: "Secret Key", text: $store.okxSecret, secure: true)
                            Divider().background(Color.line)
                            LabeledField(title: "Passphrase", text: $store.okxPassphrase, secure: true)
                            Divider().background(Color.line)
                            Toggle("模拟盘模式（零风险，推荐先用）", isOn: $store.demoTrading)
                                .tint(Color.accent)
                                .padding(.vertical, 10)
                        }
                        .padding()
                        .glassCard()

                        Button {
                            Task { _ = await store.login() }
                        } label: {
                            HStack {
                                if store.loggingIn { ProgressView().tint(.white) }
                                Text(store.loggingIn ? "授权中…" : "授权登录")
                                    .font(.system(.body, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PressScale())
                        .disabled(store.loggingIn)

                        if !store.loginError.isEmpty {
                            Text(store.loginError)
                                .font(.caption)
                                .foregroundStyle(Color.downRed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Text("授权仅用于读取行情/资产与下单，密钥保存在本机钥匙串；API Key 请在欧易只开通「交易」权限，不要开通提币。")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - 我的（原生设置页风格）

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var saved = false
    @State private var showAlerts = false

    private var totalEquity: Double { store.balances.reduce(0) { $0 + $1.eqValue } }

    var body: some View {
        NavigationStack {
            List {
                // 账户信息
                Section {
                    HStack {
                        CoinIcon(symbol: "OKX", size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("欧易账户").font(.system(.body, weight: .semibold))
                            Text(store.demoTrading ? "模拟盘" : "实盘")
                                .font(.caption2)
                                .foregroundStyle(store.demoTrading ? Color.accent : Color.upGreen)
                        }
                        Spacer()
                    }
                    infoRow("账户总估值", String(format: "$ %.2f", totalEquity))
                    infoRow("持仓数量", "\(store.positions.count)")
                    infoRow("当前委托", "\(store.pendingCount)")
                    infoRow("AI 预测命中率", store.predictionTotal > 0 ? "\(store.predictionHits)/\(store.predictionTotal)" : "--")
                }

                Section("应用") {
                    HStack {
                        Text("应用名称")
                        Spacer()
                        TextField("OKXAI", text: $store.appName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("实时与提醒") {
                    Toggle("WebSocket 实时行情", isOn: Binding(
                        get: { store.wsEnabled },
                        set: { _ in store.toggleWebSocket() }
                    ))
                    .tint(Color.accent)

                    HStack {
                        Text("连接状态")
                        Spacer()
                        Text(store.wsConnected ? "已连接" : "未连接")
                            .font(.caption)
                            .foregroundStyle(store.wsConnected ? Color.upGreen : Color.textSecondary)
                    }

                    Button("价格预警（\(store.alerts.count) 条）") { showAlerts = true }
                        .foregroundStyle(Color.accent)

                    if store.alerts.contains(where: { $0.isTriggered }) {
                        Button("清除已触发的预警") { store.clearTriggeredAlerts() }
                            .foregroundStyle(Color.downRed)
                    }
                }

                Section("安全") {
                    Toggle("Face ID 应用锁", isOn: $store.lockEnabled)
                        .tint(Color.accent)
                        .disabled(!AppLock.isAvailable)
                    if !AppLock.isAvailable {
                        Text("此设备不支持生物识别，应用锁不可用")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if store.lockEnabled {
                        Button("立即锁定") { store.lockNow() }
                            .foregroundStyle(Color.accent)
                    }
                }

                Section("欧易 OKX") {
                    keyRow("API Key", text: $store.okxKey)
                    keyRow("Secret", text: $store.okxSecret, secure: true)
                    keyRow("Passphrase", text: $store.okxPassphrase, secure: true)
                    Toggle("模拟盘模式", isOn: $store.demoTrading).tint(Color.accent)
                }

                Section("智能体") {
                    keyRow("Base URL", text: $store.aiBaseURL)
                    keyRow("AI Key", text: $store.aiKey, secure: true)
                    keyRow("模型", text: $store.aiModel)
                }

                Section("数据") {
                    Button("清空本地数据（自选 / 预警 / 净值 / 预测）", role: .destructive) {
                        store.resetLocalData()
                    }
                }

                Section {
                    Button {
                        store.saveConfig()
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    } label: {
                        Text(saved ? "已保存 ✓" : "保存设置")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color.accent)
                    }

                    Button(role: .destructive) {
                        store.logout()
                    } label: {
                        Text("退出登录").frame(maxWidth: .infinity)
                    }
                }

                Section("关于") {
                    infoRow("版本", "1.0.0")
                    infoRow("行情来源", "OKX v5 REST + WebSocket")
                    infoRow("AI 接口", store.aiBaseURL)
                    infoRow("密钥存储", "iOS 钥匙串")
                }

                Section {
                    Text("密钥保存在 iOS 钥匙串，不会上传。合约交易有强平风险，请先使用模拟盘。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("我的")
            .sheet(isPresented: $showAlerts) { AlertsView() }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func keyRow(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if secure {
                SecureField("", text: text)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            } else {
                TextField("", text: text)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .autocapitalization(.none)
            }
        }
    }
}

// MARK: - 价格预警

struct AlertsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var instId = "BTC-USDT"
    @State private var target = ""
    @State private var direction = "above"
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 新增
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: "新增预警")
                        HStack {
                            Text("标的").font(.caption).foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("BTC-USDT", text: $instId)
                                .multilineTextAlignment(.trailing)
                                .autocapitalization(.none)
                                .foregroundStyle(Color.textPrimary)
                        }
                        Picker("方向", selection: $direction) {
                            Text("涨破").tag("above")
                            Text("跌破").tag("below")
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("目标价").font(.caption).foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("0.00", text: $target)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Color.textPrimary)
                        }
                        HStack {
                            Text("备注").font(.caption).foregroundStyle(Color.textSecondary)
                            Spacer()
                            TextField("选填", text: $note)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Color.textPrimary)
                        }
                        Button {
                            if let v = Double(target), v > 0 {
                                store.addAlert(instId: instId.uppercased(), target: v,
                                               direction: direction, note: note)
                                target = ""
                                note = ""
                            }
                        } label: {
                            Text("添加预警")
                                .font(.system(.body, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(PressScale())
                    }
                    .padding()
                    .glassCard()

                    // 列表
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "我的预警 · \(store.alerts.count)")
                        if store.alerts.isEmpty {
                            Text("暂无预警").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        ForEach(store.alerts) { a in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.instId)
                                        .font(.system(.body, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(a.direction == "above" ? "涨破" : "跌破")
                                        .font(.caption2)
                                        .foregroundStyle(a.direction == "above" ? Color.upGreen : Color.downRed)
                                    if !a.note.isEmpty {
                                        Text(a.note)
                                            .font(.caption2).foregroundStyle(Color.textSecondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.4f", a.target))
                                        .font(.system(.body, design: .monospaced))
                                    if a.isTriggered {
                                        Text("已触发")
                                            .font(.caption2).foregroundStyle(Color.accent)
                                    } else if let t = store.tickers.first(where: { $0.instId == a.instId }) {
                                        Text("现价 \(t.last)")
                                            .font(.caption2).foregroundStyle(Color.textSecondary)
                                    }
                                }
                                Button {
                                    store.removeAlert(id: a.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(Color.downRed)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding()
                    .glassCard()
                }
                .padding()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("价格预警")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 通用输入行

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading).foregroundStyle(Color.textSecondary)
            if secure {
                SecureField("", text: $text).foregroundStyle(Color.textPrimary)
            } else {
                TextField("", text: $text)
                    .foregroundStyle(Color.textPrimary)
                    .autocapitalization(.none)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 首页（还原欧易大盘）

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Binding var tab: Int

    private func coin(_ id: String) -> Ticker? { store.tickers.first { $0.instId == id } }

    private var topMovers: [Ticker] {
        store.tickers.filter { $0.instId.hasSuffix("-USDT") }
            .sorted { $0.changePct > $1.changePct }
            .prefix(5).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 公告条
                    HStack(spacing: 8) {
                        Image(systemName: "megaphone").foregroundStyle(Color.accent)
                        Text("\(store.appName) 已接入欧易 API，支持模拟盘零风险体验")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                    }
                    .padding()
                    .glassCard(radius: 14)

                    // 大盘
                    HStack(spacing: 12) {
                        marketCard("BTC-USDT", "比特币")
                        marketCard("ETH-USDT", "以太坊")
                        marketCard("SOL-USDT", "Solana")
                    }

                    // 快捷入口
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "快捷交易")
                        HStack(spacing: 12) {
                            quickAction("买币", "creditcard") { tab = 2 }
                            quickAction("行情", "chart.line.uptrend.xyaxis") { tab = 1 }
                            quickAction("合约", "arrow.left.and.right.square") { tab = 2 }
                            quickAction("智能体", "sparkles") { tab = 4 }
                        }
                    }
                    .padding()
                    .glassCard()

                    // 涨幅榜
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "涨幅榜 · 24h")
                        if topMovers.isEmpty {
                            Text("暂无数据").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                        ForEach(topMovers) { t in
                            HStack {
                                CoinIcon(symbol: t.instId.replacingOccurrences(of: "-USDT", with: ""), size: 30)
                                Text(t.instId.components(separatedBy: "-").first ?? t.instId)
                                    .font(.system(.body, weight: .semibold))
                                Spacer()
                                PriceText(value: t.last)
                                ChangeBadge(pct: t.changePct).frame(width: 76, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .glassCard()
                }
                .padding()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle(store.appName)
            .task { await store.refreshMarket() }
        }
    }

    private func marketCard(_ id: String, _ name: String) -> some View {
        let t = coin(id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption2).foregroundStyle(Color.textSecondary)
            Text(t?.last ?? "--")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(String(format: "%+.2f%%", t?.changePct ?? 0))
                .font(.caption2)
                .foregroundStyle((t?.changePct ?? 0) >= 0 ? .upGreen : .downRed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func quickAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accent)
                Text(title).font(.caption2).foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}
