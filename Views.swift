import SwiftUI
import Charts
import UIKit

// MARK: - 行情

struct MarketView: View {
    @EnvironmentObject var store: AppStore
    @Binding var tab: Int
    @State private var search = ""
    @State private var scope = 0
    @State private var path: [String] = []

    private var filtered: [Ticker] {
        guard !search.isEmpty else { return store.tickers }
        return store.tickers.filter { $0.instId.uppercased().contains(search.uppercased()) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(filtered) { t in
                        NavigationLink(value: t.instId) {
                            TickerRow(ticker: t)
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
                    .foregroundStyle(.textSecondary)
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
                    Button { tab = 4 } label: {
                        Label("智能体", systemImage: "sparkles")
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            .task {
                await store.refreshMarket()
                // 模拟器验证参数：直接打开指定币种的详情页（K 线）
                for arg in CommandLine.arguments where arg.hasPrefix("-PreviewDetail=") {
                    path = [String(arg.dropFirst("-PreviewDetail=".count))]
                }
            }
        }
    }
}

struct TickerRow: View {
    let ticker: Ticker
    var body: some View {
        HStack(spacing: 12) {
            CoinIcon(symbol: ticker.instId.replacingOccurrences(of: "-USDT", with: ""))
            VStack(alignment: .leading, spacing: 2) {
                Text(ticker.instId.components(separatedBy: "-").first ?? ticker.instId)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                Text(ticker.instId)
                    .font(.caption2)
                    .foregroundStyle(.textSecondary)
            }
            Spacer()
            PriceText(value: ticker.last)
                .frame(width: 104, alignment: .trailing)
            ChangeBadge(pct: ticker.changePct)
                .frame(width: 78, alignment: .trailing)
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
                                .foregroundStyle(.textSecondary)
                        }
                        Spacer()
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
                        ForEach(["1m", "5m", "15m", "1H", "4H", "1D"], id: \.self) { b in
                            Button(b) {
                                bar = b
                                Task { await store.loadCandles(instId: instId, bar: b) }
                            }
                            .font(.caption)
                            .foregroundStyle(bar == b ? .appBg : .textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(bar == b ? Color.accent : Color.cardBg2, in: Capsule())
                        }
                    }
                    Chart(sortedCandles) { c in
                        RuleMark(x: .value("时间", c.timeLabel),
                                 yStart: .value("高", c.high), yEnd: .value("低", c.low))
                            .foregroundStyle(c.close >= c.open ? Color.upGreen : Color.downRed)
                        BarMark(x: .value("时间", c.timeLabel),
                                yStart: .value("开", c.open), yEnd: .value("收", c.close))
                            .foregroundStyle(c.close >= c.open ? Color.upGreen : Color.downRed)
                    }
                    .frame(height: 220)

                    Chart(sortedCandles) { c in
                        BarMark(x: .value("时间", c.timeLabel), y: .value("量", Double(c.vol) ?? 0))
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                    }
                    .frame(height: 60)
                    .chartYAxis(.hidden)
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
                            Text("正在生成预测…").font(.caption).foregroundStyle(.textSecondary)
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
                                .foregroundStyle(.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    } else {
                        Text("点击右上角刷新，生成 24h 价格预测")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
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
                await store.loadCandles(instId: instId, bar: bar)
                await store.predict(instId: instId, currentPrice: ticker?.lastPrice ?? 0)
            }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.textSecondary)
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                                .foregroundStyle(.textSecondary)
                            Button { hideBalance.toggle() } label: {
                                Image(systemName: hideBalance ? "eye.slash" : "eye")
                                    .foregroundStyle(.textSecondary)
                            }
                            Spacer()
                            Text(store.demoTrading ? "模拟盘" : "实盘")
                                .font(.caption2)
                                .foregroundStyle(store.demoTrading ? Color.accent : Color.upGreen)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((store.demoTrading ? Color.accent : Color.upGreen).opacity(0.15), in: Capsule())
                        }
                        Text(hideBalance ? "****" : String(format: "$ %.2f", total))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(.textPrimary)
                            .contentTransition(.numericText())
                    }
                    .padding()
                    .glassCard()

                    // 余额
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "余额")
                        if store.balances.isEmpty {
                            Text("暂无数据").font(.caption).foregroundStyle(.textSecondary)
                        }
                        ForEach(store.balances) { b in
                            HStack {
                                CoinIcon(symbol: b.ccy, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.ccy).font(.system(.body, weight: .semibold)).foregroundStyle(.textPrimary)
                                    Text("可用 \(b.availBal)").font(.caption2).foregroundStyle(.textSecondary)
                                }
                                Spacer()
                                Text(hideBalance ? "****" : b.eq)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.textPrimary)
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
                            Text("暂无持仓").font(.caption).foregroundStyle(.textSecondary)
                        }
                        ForEach(store.positions) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.instId).font(.system(.body, weight: .semibold)).foregroundStyle(.textPrimary)
                                    Text("\(p.posSide) \(p.pos) · \(p.lever)x")
                                        .font(.caption2).foregroundStyle(.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.2f", p.uplValue))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(p.uplValue >= 0 ? .upGreen : .downRed)
                                    Text("均价 \(p.avgPx)").font(.caption2).foregroundStyle(.textSecondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding()
                    .glassCard()

                    // 资金：充币 / 划转 / 账单
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(title: "资金")
                        NavigationLink { DepositView() } label: {
                            fundRow("充币", "qrcode", "查充币地址")
                        }
                        Divider().background(Color.line)
                        NavigationLink { TransferView() } label: {
                            fundRow("划转", "arrow.left.arrow.right", "资金账户 ↔ 交易账户")
                        }
                        Divider().background(Color.line)
                        NavigationLink { BillsView() } label: {
                            fundRow("账单", "list.clipboard", "资金流水")
                        }
                    }
                    .padding()
                    .glassCard()

                    // 实时通知栏
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("实时通知栏（灵动岛与锁屏显示盈亏）", isOn: $store.liveActivityEnabled)
                            .tint(Color.accent)
                            .onChange(of: store.liveActivityEnabled) { _ in
                                store.saveConfig()
                                store.saveSnapshotAndSyncLiveActivity()
                            }
                        Text("刷新资产后更新；关掉后灵动岛不再显示。")
                            .font(.caption2).foregroundStyle(.textSecondary)
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
        }
    }
}

    private func fundRow(_ title: String, _ icon: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, weight: .semibold)).foregroundStyle(.textPrimary)
                Text(sub).font(.caption2).foregroundStyle(.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 6)
    }

// MARK: - 充币（查地址，只读）

struct DepositView: View {
    @EnvironmentObject var store: AppStore
    @State private var ccy = "USDT"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("币种").font(.caption).foregroundStyle(.textSecondary)
                    TextField("USDT", text: $ccy)
                        .autocapitalization(.allCharacters)
                        .padding(12)
                        .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.textPrimary)
                    Button {
                        Task { await store.fetchDepositAddress(ccy: ccy.uppercased()) }
                    } label: {
                        Text("查询充币地址")
                            .font(.system(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressScale())
                }
                .padding()
                .glassCard()

                if !store.depositAddress.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        if !store.depositChain.isEmpty {
                            Text("链：\(store.depositChain)").font(.caption).foregroundStyle(.textSecondary)
                        }
                        Text(store.depositAddress)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.textPrimary)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = store.depositAddress
                        } label: {
                            Label("复制地址", systemImage: "doc.on.doc")
                                .font(.system(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(PressScale())
                    }
                    .padding()
                    .glassCard()
                } else if !store.depositChain.isEmpty {
                    Text(store.depositChain).font(.caption).foregroundStyle(.textSecondary)
                }

                Text("只向该地址充 \(ccy.uppercased())，错链会丢币；充币前请核对链名。")
                    .font(.caption2).foregroundStyle(.textSecondary)
            }
            .padding()
        }
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle("充币")
    }
}

// MARK: - 划转（资金账户 ↔ 交易账户）

struct TransferView: View {
    @EnvironmentObject var store: AppStore
    @State private var ccy = "USDT"
    @State private var amt = ""
    @State private var from = "6"
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("币种").font(.caption).foregroundStyle(.textSecondary)
                    TextField("USDT", text: $ccy)
                        .autocapitalization(.allCharacters)
                        .padding(12)
                        .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.textPrimary)
                    Text("数量").font(.caption).foregroundStyle(.textSecondary)
                    TextField("0.00", text: $amt)
                        .keyboardType(.decimalPad)
                        .padding(12)
                        .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.textPrimary)
                    Picker("从", selection: $from) {
                        Text("资金账户").tag("6")
                        Text("交易账户").tag("18")
                    }
                    .pickerStyle(.segmented)
                    Text("转到：\(from == "6" ? "交易账户" : "资金账户")")
                        .font(.caption).foregroundStyle(.textSecondary)
                    Button {
                        Task { message = await store.transfer(ccy: ccy.uppercased(), amt: amt, from: from, to: from == "6" ? "18" : "6") }
                    } label: {
                        Text("确认划转")
                            .font(.system(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressScale())
                    .disabled(amt.isEmpty)
                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.textSecondary)
                    }
                }
                .padding()
                .glassCard()
            }
            .padding()
        }
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle("划转")
    }
}

// MARK: - 账单（资金流水）

struct BillsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            if store.bills.isEmpty {
                Text("暂无账单").font(.caption).foregroundStyle(.textSecondary)
            }
            ForEach(store.bills) { b in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.type).font(.system(.body, weight: .semibold)).foregroundStyle(.textPrimary)
                        Text("\(b.ccy)\(b.instId.map { " · \($0)" } ?? "") · \(b.timeText)")
                            .font(.caption2).foregroundStyle(.textSecondary)
                    }
                    Spacer()
                    Text((b.changeValue >= 0 ? "+" : "") + b.balChg)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(b.changeValue >= 0 ? .upGreen : .downRed)
                }
                .listRowBackground(Color.cardBg)
                .listRowSeparatorTint(Color.line)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBg.ignoresSafeArea())
        .navigationTitle("账单")
        .refreshable { await store.loadBills() }
        .task { await store.loadBills() }
    }
}

// MARK: - 交易

struct TradeView: View {
    @EnvironmentObject var store: AppStore
    @State private var tradeTab = 0
    @State private var side = "buy"
    @State private var ordType = "limit"
    @State private var px = ""
    @State private var sz = ""
    @State private var pct: Double = 0
    @State private var message = ""
    @State private var cancelMsg = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("市场", selection: $store.tradeMode) {
                        Text("现货").tag("spot")
                        Text("合约").tag("swap")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.tradeMode) { _ in
                        Task { await store.loadOrders() }
                    }

                    Picker("交易", selection: $tradeTab) {
                        Text("下单").tag(0)
                        Text("当前委托").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if tradeTab == 0 {
                        orderForm
                    } else {
                        ordersList
                    }
                }
                .padding()
            }
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("交易")
            .task { await store.loadOrders() }
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
                    Text("交易对").font(.caption).foregroundStyle(.textSecondary)
                    Spacer()
                    Text(store.activeInstId)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }

                Picker("类型", selection: $ordType) {
                    Text("限价").tag("limit")
                    Text("市价").tag("market")
                }
                .pickerStyle(.segmented)

                if ordType == "limit" {
                    field("价格", $px, "USDT")
                }
                field("数量", $sz, store.activeInstId.components(separatedBy: "-").first ?? "")

                // 杠杆 & 保证金模式
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("杠杆").font(.caption).foregroundStyle(.textSecondary)
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
                        Text("仓位比例").font(.caption).foregroundStyle(.textSecondary)
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
                                                      ordType: ordType, sz: sz,
                                                      px: px.isEmpty ? nil : px)
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
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 当前委托

    private var ordersList: some View {
        VStack(spacing: 12) {
            if store.pendingOrders.isEmpty {
                Text("暂无当前委托").font(.caption).foregroundStyle(.textSecondary)
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
                            .font(.caption).foregroundStyle(.textSecondary)
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
                Text(cancelMsg).font(.caption).foregroundStyle(.textSecondary)
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
            Text(title).font(.caption).foregroundStyle(.textSecondary)
            HStack {
                TextField("0.00", text: binding)
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.textPrimary)
                Text(unit).font(.caption).foregroundStyle(.textSecondary)
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
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if store.chat.isEmpty {
                                emptyState
                            }
                            ForEach(store.chat) { m in
                                bubble(m).id(m.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.chat.count) { _ in
                        if let last = store.chat.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                // 输入栏
                HStack(spacing: 10) {
                    TextField("问智能体…", text: $input)
                        .focused($inputFocused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .foregroundStyle(.textPrimary)
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { inputFocused = false }
                        .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.accent)
            Text("我是你的智能交易助手")
                .font(.system(.headline))
                .foregroundStyle(.textPrimary)
            Text(store.demoTrading ? "模拟盘模式 · 下单零风险" : "实盘模式 · 下单为真实交易")
                .font(.caption2)
                .foregroundStyle(store.demoTrading ? Color.accent : Color.downRed)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background((store.demoTrading ? Color.accent : Color.downRed).opacity(0.15), in: Capsule())
            if store.aiAutoTrade {
                Text("AI 全权执行 · 下单直接成交")
                    .font(.caption2)
                    .foregroundStyle(Color.downRed)
            }
            Text("可以问我行情、查资产，或让我直接下单")
                .font(.caption)
                .foregroundStyle(.textSecondary)
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
                        .foregroundStyle(.textPrimary)
                    if let d = m.orderDraft { orderCard(d) }
                }
                Spacer()
            }
        }
    }

    private func orderCard(_ d: OrderDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("订单确认").font(.caption).foregroundStyle(.textSecondary)
            HStack {
                Text(d.instId).font(.system(.body, weight: .semibold))
                Spacer()
                Text(d.side.uppercased())
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(d.side == "buy" ? .upGreen : .downRed)
            }
            Text("\(d.ordType) · 数量 \(d.sz)\(d.px != nil ? " · 价格 \(d.px!)" : "")")
                .font(.caption).foregroundStyle(.textSecondary)
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
                                .foregroundStyle(.textPrimary)
                            Text("连接你的欧易账户，智能体帮你交易")
                                .font(.subheadline)
                                .foregroundStyle(.textSecondary)
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
                            if !store.demoTrading {
                                Text("实盘模式：登录后下单为真实交易，请确认金额与方向。")
                                    .font(.caption2)
                                    .foregroundStyle(Color.downRed)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 10)
                            }
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
                            .foregroundStyle(.textSecondary)
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
    @State private var testResult = ""
    @State private var testing = false

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

                Section("欧易 OKX") {
                    keyRow("API Key", text: $store.okxKey)
                    keyRow("Secret", text: $store.okxSecret, secure: true)
                    keyRow("Passphrase", text: $store.okxPassphrase, secure: true)
                    Toggle("模拟盘模式", isOn: $store.demoTrading).tint(Color.accent)
                }

                Section("智能体") {
                    HStack {
                        Text("模型服务")
                        Spacer()
                        Menu {
                            ForEach(ModelProvider.all) { p in
                                Button(p.name) { store.selectProvider(p) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(ModelProvider.byId(store.aiProvider).name)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.accent)
                        }
                    }
                    keyRow("Base URL", text: $store.aiBaseURL)
                    keyRow("AI Key", text: $store.aiKey, secure: true)
                    keyRow("模型", text: $store.aiModel)
                    Toggle("AI 全权执行交易", isOn: $store.aiAutoTrade).tint(Color.accent)
                    if store.aiAutoTrade {
                        Text("全权模式：智能体下单直接成交，不再逐单等你点确认。")
                            .font(.caption2)
                            .foregroundStyle(Color.downRed)
                    }
                    HStack {
                        Button("测试连接") {
                            testing = true
                            Task {
                                testResult = await store.testAI()
                                testing = false
                            }
                        }
                        .foregroundStyle(Color.accent)
                        Spacer()
                        if testing { ProgressView() }
                    }
                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

                Section {
                    Text("密钥保存在 iOS 钥匙串，不会上传。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBg.ignoresSafeArea())
            .navigationTitle("我的")
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

// MARK: - 通用输入行

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading).foregroundStyle(.textSecondary)
            if secure {
                SecureField("", text: $text).foregroundStyle(.textPrimary)
            } else {
                TextField("", text: $text)
                    .foregroundStyle(.textPrimary)
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
                        Text(store.demoTrading
                             ? "\(store.appName) 已接入欧易 API，模拟盘模式"
                             : "\(store.appName) 已接入欧易 API，实盘模式 · 下单为真实交易")
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
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
                            Text("暂无数据").font(.caption).foregroundStyle(.textSecondary)
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
            Text(name).font(.caption2).foregroundStyle(.textSecondary)
            Text(t?.last ?? "--")
                .font(.system(.caption, weight: .semibold, design: .monospaced))
                .foregroundStyle(.textPrimary)
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
                Text(title).font(.caption2).foregroundStyle(.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.cardBg2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}
