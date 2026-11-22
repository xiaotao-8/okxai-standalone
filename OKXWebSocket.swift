import Foundation

// MARK: - OKX v5 WebSocket 客户端（公开行情 + 私有推送）

/// 职责单一：建连、订阅、心跳、断线重连，把收到的 JSON 原样丢给回调。
/// 解析交给 AppStore，避免在并发环境里处理类型转换。
final class OKXWebSocket: NSObject, URLSessionWebSocketDelegate {

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var urlString = ""
    private var subs: [[String: String]] = []
    private var loginArgs: [[String: Any]]?
    private var pingTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private var running = false
    private var isOpen = false
    private var loggedIn = false

    /// 收到任意消息（已解析为字典）
    var onMessage: (([String: Any]) -> Void)?
    /// 连接状态变化
    var onState: ((Bool) -> Void)?

    // MARK: 生命周期

    func start(publicURL: String = "wss://ws.okx.com:8443/ws/v5/public",
               privateURL: String = "wss://ws.okx.com:8443/ws/v5/private",
               loginArgs: [[String: Any]]? = nil,
               subs: [[String: String]],
               onMessage: @escaping ([String: Any]) -> Void,
               onState: @escaping (Bool) -> Void) {
        stop()
        self.subs = subs
        self.loginArgs = loginArgs
        self.onMessage = onMessage
        self.onState = onState
        self.running = true

        urlString = (loginArgs != nil) ? privateURL : publicURL

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session?.webSocketTask(with: URL(string: url)!)
        task?.resume()
    }

    func stop() {
        running = false
        retryWork?.cancel()
        retryWork = nil
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isOpen = false
    }

    // MARK: 订阅

    /// 私有频道登录成功后补订阅
    func sendSubs() {
        guard !subs.isEmpty else { return }
        sendObject(["op": "subscribe", "args": subs])
    }

    private func sendLogin() {
        sendObject(["op": "login", "args": loginArgs ?? []])
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocolName: String?) {
        isOpen = true
        loggedIn = (loginArgs == nil)
        onState?(true)
        if loginArgs != nil { sendLogin() } else { sendSubs() }
        startPing()
        listen()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        handleClose()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        handleClose()
    }

    // MARK: 接收循环

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.handleClose()
            case .success(let message):
                self.handle(message)
                self.listen()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        var text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: break
        }
        guard let text else { return }

        if text == "ping" {
            sendRaw("pong")
            return
        }
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let event = obj["event"] as? String, event == "login" {
                loggedIn = true
                sendSubs()
                return
            }
            onMessage?(obj)
        }
    }

    // MARK: 心跳 / 重连

    private func startPing() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.pingTimer?.invalidate()
            let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in
                self?.sendRaw("ping")
            }
            RunLoop.main.add(timer, forMode: .common)
            self.pingTimer = timer
        }
    }

    private func handleClose() {
        guard isOpen else { return }
        isOpen = false
        pingTimer?.invalidate()
        pingTimer = nil
        onState?(false)
        guard running else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.task = self.session?.webSocketTask(with: URL(string: self.urlString)!)
            self.task?.resume()
        }
        retryWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: 发送

    private func sendRaw(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        task?.send(message) { _ in }
    }

    private func sendObject(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        sendRaw(text)
    }
}
