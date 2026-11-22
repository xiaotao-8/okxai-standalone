import SwiftUI

// MARK: - 行情

struct MarketView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List(store.tickers) { t in
                HStack {
                    Text(t.instId).font(.headline)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(t.last).font(.system(.body, design: .monospaced))
                        Text(String(format: "%+.2f%%", t.changePct))
                            .font(.caption)
                            .foregroundStyle(t.changePct >= 0 ? .green : .red)
                    }
                }
            }
            .navigationTitle("行情")
            .toolbar {
                Button("刷新") { Task { await store.refreshMarket() } }
            }
            .task { await store.refreshMarket() }
        }
    }
}

// MARK: - 资产

struct AccountView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section("余额") {
                    if store.balances.isEmpty { Text("点击右上角刷新").foregroundStyle(.secondary) }
                    ForEach(store.balances) { b in
                        HStack {
                            Text(b.ccy)
                            Spacer()
                            Text(String(format: "%.4f", b.eqValue))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                Section("持仓") {
                    if store.positions.isEmpty { Text("无持仓").foregroundStyle(.secondary) }
                    ForEach(store.positions) { p in
                        HStack {
                            Text(p.instId)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(p.pos)
                                Text(String(format: "盈亏 %.2f", p.uplValue))
                                    .font(.caption)
                                    .foregroundStyle(p.uplValue >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("资产")
            .toolbar {
                Button("刷新") { Task { await store.refreshAccount() } }
            }
        }
    }
}

// MARK: - 交易

struct TradeView: View {
    @EnvironmentObject var store: AppStore
    @State private var instId = "BTC-USDT"
    @State private var side = "buy"
    @State private var ordType = "market"
    @State private var sz = "0.001"
    @State private var px = ""
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("交易对") {
                    TextField("如 BTC-USDT", text: $instId)
                }
                Section("方向") {
                    Picker("方向", selection: $side) {
                        Text("买入").tag("buy")
                        Text("卖出").tag("sell")
                    }.pickerStyle(.segmented)
                }
                Section("类型") {
                    Picker("类型", selection: $ordType) {
                        Text("市价").tag("market")
                        Text("限价").tag("limit")
                    }.pickerStyle(.segmented)
                }
                Section("数量") {
                    TextField("数量", text: $sz)
                        .keyboardType(.decimalPad)
                }
                if ordType == "limit" {
                    Section("价格") {
                        TextField("价格", text: $px)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Button {
                        Task {
                            message = await store.placeOrder(instId: instId, side: side,
                                                              ordType: ordType, sz: sz,
                                                              px: px.isEmpty ? nil : px)
                        }
                    } label: {
                        Text("下单").frame(maxWidth: .infinity)
                    }
                    .disabled(!store.hasOKXKeys)
                }
                if !message.isEmpty {
                    Section { Text(message).font(.caption) }
                }
            }
            .navigationTitle("交易")
        }
    }
}

// MARK: - AI 对话

struct AIChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack {
                ScrollViewReader { proxy in
                    List(store.chat) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.role.uppercased())
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(m.text)
                            if let d = m.orderDraft {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(d.instId) \(d.side) \(d.ordType) 数量 \(d.sz)")
                                        .font(.caption)
                                    Button("确认下单") {
                                        Task { await store.confirmDraft(d) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(Color.yellow.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .id(m.id)
                    }
                    .onChange(of: store.chat.count) { _ in
                        if let last = store.chat.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                HStack {
                    TextField("问 AI：查行情 / 买 0.001 BTC …", text: $input)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let text = input; input = ""
                        Task { await store.sendChat(text) }
                    } label: { Image(systemName: "paperplane.fill") }
                        .disabled(store.busy || input.isEmpty)
                }
                .padding()
            }
            .navigationTitle("AI 助手")
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var saved = false

    var body: some View {
        NavigationStack {
            Form {
                Section("欧易 OKX") {
                    TextField("API Key", text: $store.okxKey)
                    SecureField("Secret Key", text: $store.okxSecret)
                    SecureField("Passphrase", text: $store.okxPassphrase)
                    Toggle("模拟盘模式（零风险）", isOn: $store.demoTrading)
                }
                Section("AI 模型（OpenAI 兼容）") {
                    TextField("Base URL", text: $store.aiBaseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    SecureField("API Key", text: $store.aiKey)
                    TextField("模型", text: $store.aiModel)
                        .autocapitalization(.none)
                }
                Section {
                    Button {
                        store.saveConfig()
                        saved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    } label: {
                        Text(saved ? "已保存 ✓" : "保存设置").frame(maxWidth: .infinity)
                    }
                }
                Section {
                    Text("密钥保存在 iOS 钥匙串，不会上传。API Key 请在欧易后台只开通「交易」权限，不要开通提币。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
