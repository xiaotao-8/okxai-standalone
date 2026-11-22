import SwiftUI

/// 全局主题：对齐主流交易所 App 的深色风格
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    static let appBg       = Color(hex: 0x0B0E11)
    static let cardBg      = Color(hex: 0x161A1E)
    static let cardBg2     = Color(hex: 0x1F2630)
    static let line        = Color(hex: 0x2B3139)
    static let upGreen     = Color(hex: 0x0ECB81)
    static let downRed     = Color(hex: 0xF6465D)
    static let accent      = Color(hex: 0x3B82F6)
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: 0x848E9C)
}

/// 数字统一等宽，涨跌用红涨绿跌（欧易/币安习惯：绿涨红跌）
struct PriceText: View {
    let value: String
    var color: Color = .textPrimary
    var body: some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(color)
    }
}

/// 涨跌幅徽标
struct ChangeBadge: View {
    let pct: Double
    var body: some View {
        Text(String(format: "%+.2f%%", pct))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(pct >= 0 ? Color.upGreen : Color.downRed)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 币种圆形图标（无真实 logo，用首字母占位）
struct CoinIcon: View {
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            Circle().fill(Color.cardBg2)
            Text(String(symbol.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color.accent)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 玻璃拟态卡片（iOS 原生 .ultraThinMaterial）

struct GlassCard: ViewModifier {
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glassCard(radius: CGFloat = 20) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

// MARK: - 按压缩放按钮（原生弹簧手感）

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - 渐变 Hero 背景

struct GradientHero: View {
    var body: some View {
        LinearGradient(
            colors: [Color.accent.opacity(0.45), Color(hex: 0x6A5CFF).opacity(0.25), Color.appBg],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - 分区标题（原生大写风格）

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}
