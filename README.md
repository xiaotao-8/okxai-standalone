# OKXAI（独立版）—— iOS 原生客户端（欧易 OKX + AI）

Swift / SwiftUI 写的 iOS App：行情、资产、交易、AI 对话下单。
密钥存在 iOS 钥匙串，不上传；支持**模拟盘**零风险运行。

> ⚠️ 本工程由 AI 在 Linux 环境生成，**未经编译验证**。请在 Mac + Xcode 中编译，如有小问题按报错微调。
>
> 说明：这是**自包含单 Target** 版本，不依赖任何第三方库，拷进 Xcode 即可编译。

---

## 一、环境要求

| 项 | 要求 |
|---|---|
| macOS | 任意能跑 Xcode 15 的版本 |
| Xcode | 15+ |
| 部署目标 | iOS 16+ |
| 真机安装 | Apple 开发者账号（$99/年）；模拟器免费 |

## 二、导入步骤（3 步）

1. Xcode → **File → New → Project → iOS → App**
   - Product Name：`OKXAI`
   - Interface：**SwiftUI**，Language：**Swift**
   - 保存后删掉自动生成的 `ContentView.swift`（本工程已自带）
2. 把本目录所有 `.swift` 文件拖进 Xcode 工程导航器，勾选 **Copy items if needed** + Target
3. `Cmd+R` 编译运行

## 三、配置欧易 API Key

1. 登录 [okx.com](https://www.okx.com) → 头像 → **API** → 创建 API Key
2. 权限**只勾「交易」**，❌ 不要勾提币；建议绑定 IP 白名单
3. 记录：`API Key` / `Secret Key` / `Passphrase`
4. App「设置」页填入，打开**模拟盘模式**，保存

> 模拟盘模式下所有私有请求自动带 `x-simulated-trading: 1`。

## 四、配置 AI（OpenAI 兼容即可）

支持任意 **OpenAI 兼容 `/v1/chat/completions`** 服务 + function calling。

| 服务 | Base URL 示例 | 模型示例 |
|---|---|---|
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` |
| Kimi | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` |
| Ollama 本地 | `http://你的IP:11434/v1` | 本地模型名 |

在「设置」页填 Base URL / API Key / 模型名。

## 五、AI 如何下单（安全设计）

- AI 只能调用 4 个工具：`get_ticker`、`get_balance`、`get_positions`、`place_order`
- `place_order` 默认**只生成订单草稿**，必须由你在聊天里点「**确认下单**」才真正提交
- 建议常开模拟盘，实盘前先验证策略

## 六、安全须知

- 密钥只存钥匙串（`KeychainStore`），不写明文
- OKX API Key 不给提币权限
- 无后端、无遥测、无数据上传
- 个人工具，风险自担；先小额、先模拟盘

## 七、文件结构

```
OKXAI-Standalone/
├── OKXAIApp.swift      # App 入口 + 5 个 Tab
├── Models.swift        # 数据模型 + 聊天消息
├── OKXAPI.swift        # 欧易 v5 客户端（签名/模拟盘/行情/资产/交易）
├── AIClient.swift      # OpenAI 兼容 chat + tools
├── AppStore.swift      # 全局状态 + AI 工具执行 + 下单确认
├── KeychainStore.swift  # 钥匙串读写
├── Views.swift         # 行情/资产/交易/AI/设置 界面
└── README.md
```

## 八、已知限制

- 无 K 线图（可加 Swift Charts）
- 行情走 REST 轮询，非 WebSocket
- 合约仅基础参数（`tdMode`/`posSide` 可扩展）
- 无单元测试
