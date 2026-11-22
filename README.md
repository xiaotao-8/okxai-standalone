# OKXAI（独立版）—— iOS 原生客户端（欧易 OKX + AI）

Swift / SwiftUI 写的 iOS App：行情、资产、交易、AI 对话下单。
密钥存在 iOS 钥匙串，不上传；行情 / 资产 / 交易 / AI 智能体一体化。

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
4. App「设置」页填入并保存

> 所有请求走 HTTPS + HMAC-SHA256 签名。若出现「请求超时」，多为网络无法访问 `www.okx.com`，请开启代理后重试（登录页可一键测试连通性）。

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

- AI 只能调用 3 个工具：`get_ticker`、`get_balance`、`place_order`
- `place_order` 默认**只生成订单草稿**，必须由你在聊天里点「**确认下单**」才真正提交
- 登录超时先点登录页的「测试与欧易服务器的连接」定位网络问题

## 六、核心交易功能（对齐欧易）

| 功能 | 说明 |
|---|---|
| 现货 / 合约 | 交易页一键切换，合约自动带 `tdMode`、`posSide`、杠杆、保证金模式 |
| 做多 / 做空 | 合约模式下可切换 `long` / `short` 持仓方向 |
| 止盈 / 止损 | 下单时填「止盈价」「止损价」，映射为 `tpTriggerPx` / `slTriggerPx` |
| 计划委托（触发价） | 选「计划」并填触发价 → `ordType=conditional` |
| 跟踪委托 | 选「跟踪」填回调比例（%）+ 激活价 → `ordType=move_order_stop` |
| 杠杆 / 逐仓 / 全仓 | `lever` 1–20x，`isolated`（逐仓）/ `cross`（全仓） |
| 合约标的推导 | 现货 `BTC-USDT` 自动转 `BTC-USDT-SWAP` 下单 |
| 盘口深度 | 详情页买五 / 卖五深度 + 量比横条 |
| 深度图 | 累计买卖盘面积图，直观看到支撑/压力 |
| K 线 + 均线 | 8 档周期（1m→1W）+ MA5 / MA10 / MA20 叠加 |
| 技术指标 | RSI(14)、MACD、MA、BOLL 中轨，含超买/超卖提示 |
| 最新成交 | 详情页最近成交明细（实时推送时自动更新） |
| 委托管理 | 当前委托一键撤单、历史委托与成交明细 |
| 合约风险 | 持仓显示标记价、预估强平价、风险率 |
| 净值曲线 | 每次刷新账户记录净值点，资产页绘制走势（本地持久化） |
| AI 预测命中率 | 预测方向与实际涨跌比对，显示「命中 x/y」（本地持久化） |

## 七、实时行情与智能提醒

| 功能 | 说明 |
|---|---|
| WebSocket 推送 | 「我的 → 实时与提醒」开启；行情/成交/盘口/账户/委托全走推送，断线 3s 自动重连 |
| 私有频道 | 填入 OKX 密钥后自动登录私有频道，委托状态、账户变动实时刷新 |
| 网络诊断 | 登录页一键测试到欧易服务器的连通性与延迟，并给出中文排查建议 |
| 自选 | 行情页/详情页点星标，本地持久化，行情页可筛选「自选」 |
| 价格预警 | 涨破/跌破目标价 → App 本地通知 + 应用内提示，预警列表持久化 |
| 策略回测 | 「智能体」页可调快/慢线，双均线策略在 300 根 1H K 线上回测，输出净值曲线/胜率/最大回撤 |
| 应用锁 | Face ID / 触控 ID 锁定，支持手动立即锁定 |
| 触觉反馈 | 下单、撤单、预警触发均有原生震动反馈 |

## 八、安全须知

- 密钥只存钥匙串（`KeychainStore`），不写明文
- OKX API Key 不给提币权限
- 无后端、无遥测、无数据上传
- 个人工具，风险自担；合约请控制杠杆、先小额验证

## 九、文件结构

```
OKXAI-Standalone/
├── OKXAIApp.swift      # App 入口 + 6 个 Tab
├── Models.swift        # 数据模型 + 聊天消息
├── OKXAPI.swift        # 欧易 v5 客户端（签名/行情/资产/交易/网络诊断）
├── AIClient.swift      # OpenAI 兼容 chat + tools
├── AppStore.swift      # 全局状态 + AI 工具执行 + 下单确认
├── KeychainStore.swift  # 钥匙串读写
├── Theme.swift         # 深色主题 / 通用组件（价格、涨跌徽标、币种图标）
├── Indicators.swift     # MA / EMA / RSI / MACD / BOLL 指标计算
├── Backtest.swift       # 双均线策略回测（净值/胜率/最大回撤）
├── Utils.swift          # 持久化 / 触觉反馈 / Face ID 应用锁
├── OKXWebSocket.swift   # OKX v5 WebSocket（公开+私有频道、心跳、重连）
├── Views.swift         # 行情/详情K线/资产/交易/AI/设置/预警 界面
├── OKXAI-AllInOne.swift # 单文件版（合并以上全部源码，二选一使用）
└── README.md
```

> 两个 zip 的区别：`OKXAI-Standalone.zip` = 多文件工程（推荐，便于阅读维护）；
> `OKXAI-AllInOne.zip` = 只有一个 `.swift` 文件，拖进 Xcode 即可编译。

## 十、已知限制

- 价格预警依赖行情刷新触发检查，App 被杀掉时只能靠本地通知前的最后一次检查（后续可接后台抓取）
- 私有频道会接收真实委托/资产推送，如不需要可在「我的」关闭实时行情
- 无单元测试，未经编译验证，请在 Xcode 中构建确认
