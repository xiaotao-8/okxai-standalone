import SwiftUI

/// 首次进入 App 的欧易授权登录页：引导用户创建 API Key 并真实校验后连接
struct OKXAuthView: View {
    @EnvironmentObject var store: AppStore
    @State private var errorText = ""
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.blue)
                            .clipShape(Circle())
                        Text("连接你的欧易账号")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("授权后，智能体才能替你查行情、查持仓、下单。Key 只在授权时填一次，保存在本机钥匙串，不会上传；设置里不再需要填 Key。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("在欧易 App 里创建 API Key")
                            .font(.headline)
                        stepRow("1", "打开欧易 App → 我的 → API 管理 → 创建 API Key")
                        stepRow("2", "权限只勾「交易」，不要勾提币、不要勾转账")
                        stepRow("3", "把 Key、Secret、Passphrase 粘贴到下面，点连接")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(spacing: 12) {
                        Link("在欧易创建 API Key（官方页面）", destination: URL(string: "https://www.okx.com/account/my-api/create")!)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        TextField("API Key", text: $store.okxKey)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        SecureField("Secret Key", text: $store.okxSecret)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        SecureField("Passphrase", text: $store.okxPassphrase)
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Toggle("模拟盘模式（零风险）", isOn: $store.demoTrading)
                            .padding(.horizontal, 4)
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task {
                            connecting = true
                            defer { connecting = false }
                            if let err = await store.connectOKX() {
                                errorText = err
                            } else {
                                errorText = ""
                            }
                        }
                    } label: {
                        HStack {
                            if connecting { ProgressView().tint(.white) }
                            Text(connecting ? "正在验证…" : "授权并连接")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connecting)

                    Button("稍后再说") {
                        store.dismissAuth()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}
