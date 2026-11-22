import SwiftUI
import WidgetKit

// MARK: - 小组件：当前持仓 + 盈利亏损

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: AccountSnapshot.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: AccountSnapshot.load() ?? .empty)
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: AccountSnapshot
}

private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
private func fmtSigned(_ v: Double) -> String { String(format: "%+.2f", v) }

struct OKXAIWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: largeView
        }
    }

    private var uplColor: Color { entry.snapshot.totalUpl >= 0 ? .green : .red }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("浮动盈亏")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(fmtSigned(entry.snapshot.totalUpl))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(uplColor)
            Text("权益 $\(fmt(entry.snapshot.totalEquity))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.snapshot.positions.isEmpty ? "暂无持仓" : "\(entry.snapshot.positions.count) 个持仓")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("浮动盈亏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fmtSigned(entry.snapshot.totalUpl))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(uplColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("总权益")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("$\(fmt(entry.snapshot.totalEquity))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            Divider()
            if entry.snapshot.positions.isEmpty {
                Text("暂无持仓，打开 App 刷新资产后同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.snapshot.positions.prefix(2), id: \.instId) { p in
                    positionRow(p)
                }
            }
        }
        .padding()
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("浮动盈亏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fmtSigned(entry.snapshot.totalUpl))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(uplColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("总权益")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("$\(fmt(entry.snapshot.totalEquity))")
                        .font(.headline)
                }
            }
            Divider()
            if entry.snapshot.positions.isEmpty {
                Text("暂无持仓，打开 App 刷新资产后同步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.snapshot.positions.prefix(5), id: \.instId) { p in
                    positionRow(p)
                }
            }
            Spacer()
            Text("更新于 \(entry.snapshot.updatedAt, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func positionRow(_ p: PositionSnapshot) -> some View {
        HStack {
            Text(p.instId)
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            Text("持有 \(p.pos)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(fmtSigned(p.upl))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(p.upl >= 0 ? .green : .red)
        }
    }
}

struct OKXAIWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OKXAIWidget", provider: Provider()) { entry in
            OKXAIWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("欧易持仓")
        .description("实时查看持仓与盈亏")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 实时通知栏（灵动岛 / 锁屏）

@available(iOS 16.1, *)
struct OKXLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OKXLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("欧易持仓")
                        .font(.headline)
                    Spacer()
                    Text("权益 $\(fmt(context.state.totalEquity))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(fmtSigned(context.state.totalUpl))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(context.state.totalUpl >= 0 ? .green : .red)
                Text("\(context.state.positionCount) 个持仓 · \(context.state.topInstId) \(fmtSigned(context.state.topUpl))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("欧易")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(fmtSigned(context.state.totalUpl))
                        .font(.headline)
                        .foregroundStyle(context.state.totalUpl >= 0 ? .green : .red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("权益 $\(fmt(context.state.totalEquity))")
                        Spacer()
                        Text("\(context.state.topInstId) \(fmtSigned(context.state.topUpl))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("OKX")
                    .font(.caption)
                    .fontWeight(.semibold)
            } compactTrailing: {
                Text(fmtSigned(context.state.totalUpl))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(context.state.totalUpl >= 0 ? .green : .red)
            } minimal: {
                Text(fmtSigned(context.state.totalUpl))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(context.state.totalUpl >= 0 ? .green : .red)
            }
        }
    }
}

@main
struct OKXAIWidgetBundle: WidgetBundle {
    var body: some Widget {
        OKXAIWidget()
        if #available(iOS 16.1, *) {
            OKXLiveActivityWidget()
        }
    }
}
