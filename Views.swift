import SwiftUI

// MARK: - 行情

struct MarketView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List(store.tickers) { t in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.instId).font(.headline)
                        Text("高 \(t.high24h) · 低 \(t.low24h)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(t.last)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Text(String(format: "%+.2f%%", t.changePct))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((t.changePct >= 0 ? Color.green : Color.red).opacity(0.15))
                            .foregroundStyle(t.changePct >= 0 ? .green : .red)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .refreshable { await store.refreshMarket() }
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

// MARK: - AI 智能体（欧易专属，可替用户操作）

struct AIChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var input = ""

    private let quickPrompts = ["BTC 现在什么价？", "查一下我的持仓", "查一下我的余额", "市价买 0.001 个 BTC"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if store.demoTrading {
                    Text("模拟盘模式 · 下单零风险")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.top, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if store.chat.isEmpty && !store.busy {
                                emptyState
                            }
                            ForEach(store.chat) { m in
                                messageRow(m)
                                    .id(m.id)
                            }
                            if store.busy {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(store.agentStatus ?? "思考中…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 4)
                                .id("status")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: store.chat.count) { _ in
                        withAnimation {
                            if let last = store.chat.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: store.busy) { _ in
                        if store.busy {
                            withAnimation { proxy.scrollTo("status", anchor: .bottom) }
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { p in
                            Button(p) { send(p) }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                                .disabled(store.busy)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 6)
                HStack(spacing: 8) {
                    TextField("让智能体替你操作，如：帮我买 0.001 个 BTC", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    Button { send(input) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(store.busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("智能体")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !store.busy else { return }
        input = ""
        Task { await store.sendChat(t) }
    }

    /// 空态：智能体介绍 + 能力说明
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text("你好，我是你的欧易智能体")
                .font(.title3)
                .fontWeight(.semibold)
            Text("行情、余额、持仓、下单，我都能替你办。说一句话就行，下单前一定先请你确认。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func messageRow(_ m: ChatMessage) -> some View {
        switch m.role {
        case "user":
            HStack {
                Spacer()
                Text(m.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        case "tool":
            if let tc = m.toolCall {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: tc.icon)
                            .foregroundStyle(.blue)
                        Text(tc.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: tc.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(tc.success ? .green : .red)
                    }
                    Text(m.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        case "system":
            HStack {
                Spacer()
                Text(m.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        default: // assistant
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.blue)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.text)
                        .font(.body)
                    if let d = m.orderDraft {
                        orderDraftCard(d, messageId: m.id)
                    }
                }
            }
        }
    }

    /// 订单草稿卡：确认才真下单，取消直接丢弃
    private func orderDraftCard(_ d: OrderDraft, messageId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("订单草稿")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(d.side == "buy" ? "买入" : "卖出")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((d.side == "buy" ? Color.green : Color.red).opacity(0.15))
                    .foregroundStyle(d.side == "buy" ? .green : .red)
                    .clipShape(Capsule())
            }
            draftRow("交易对", d.instId)
            draftRow("类型", d.ordType == "market" ? "市价" : "限价")
            draftRow("数量", d.sz)
            if let px = d.px { draftRow("价格", px) }
            HStack(spacing: 8) {
                Button("确认下单") {
                    Task { await store.confirmDraft(d) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("取消") {
                    store.dismissDraft(id: messageId)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
    }

    private func draftRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
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
