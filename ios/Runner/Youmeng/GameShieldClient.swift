// ============================================================
// GameShield iOS SDK (Swift 5.9, iOS 13+, Network.framework + CryptoKit)
// 轻量原则: 全局仅 1 个5秒 timer tick; 游戏未连接时自动休眠(0网络探针);
//           事件回调 onEvent + 批量上报控制面(商户后台"连接日志"据此定位掉线原因)。
// 协议与 node/index.js / Android SDK 完全一致:
//   帧 = [1B type][4B BE len][payload]; DATA = AES-GCM combined(nonce12+ct+tag16)
//
// 用法(自研游戏直连模式):
//   let sdk = GameShieldClient(cp: "https://调度域名", token: sdk_token, aesKeyHex: aes_key)
//   sdk.onEvent = { code, msg, node in print("[盾]", code, msg, node) }   // 可选事件回调
//   sdk.connect(sourcePort: 8000) { result in
//       if case .success(let tun) = result {
//           tun.send(gamePacket)                       // 游戏包 -> 加密进隧道
//           tun.receive { data in handleGame(data) }   // 隧道回包 -> 游戏
//       }
//   }
//
// ⚠️ iOS 平台边界(必读):
//   App Store 不允许改写其他App流量。合规路线:
//   A. 自研游戏引擎直接集成 send/receive —— 最主流做法, 可过审
//   B. 盾壳App企业签名分发 —— 需企业开发者账号, 有风控, 自担
//   C. NEPacketTunnelProvider 全量接管 —— 需 VPN  entitlement, 只适合特殊场景
// ============================================================
import Foundation
import Network
import CryptoKit

let youmengQueue = DispatchQueue(label: "openim.youmeng.network")

public final class GameShieldClient {
    struct Conf {
        var projectId: Int = 0
        var tunnelPort: Int = 20000
        var ports: [Int: Int] = [:]        // localPort -> sourcePort
        var protocolKind: String = "tcp"
    }

    private let cp: String
    private let token: String
    private let key: SymmetricKey
    private var conf = Conf()
    private var nodeIP: String?
    private var nodeQueue: [String] = []      // RTT升序热备队列
    private var tickTimer: DispatchSourceTimer?
    private var tick = 0
    private var ownedTunnels = [UUID: TunnelTLS]()
    private var idleState = true
    // ---- 事件/上报 ----
    /// 事件回调(任意线程): code与 shared/events.js 字典同码
    public var onEvent: ((String, String, String) -> Void)?
    private var outbox = [[String: Any]]()
    private let outLock = NSLock()
    // ---- 活动隧道计数(0=休眠) ----
    private var tunnelCount = 0
    private let cntLock = NSLock()

    public init(cp: String, token: String, aesKeyHex: String) {
        self.cp = cp.hasSuffix("/") ? String(cp.dropLast()) : cp
        self.token = token
        var bytes = [UInt8]()
        let hexDigits = Array(aesKeyHex)
        var i = 0
        while i + 1 < hexDigits.count,
              let byte = UInt8(String(hexDigits[i...i + 1]), radix: 16) {
            bytes.append(byte); i += 2
        }
        precondition(bytes.count == 32, "aes_key 必须为 64 位 hex (32字节)")
        self.key = SymmetricKey(data: bytes)
    }

    // ================= 事件总线: 回调 + 上报队列(随tick 30s批量POST) =================
    func evt(_ code: String, _ msg: String, _ node: String = "") {
        let rec: [String: Any] = [
            "t": Int(Date().timeIntervalSince1970 * 1000), "code": code,
            "msg": String(msg.prefix(480)), "node": node.isEmpty ? (nodeIP ?? "") : node]
        outLock.lock()
        outbox.append(rec)
        if outbox.count > 200 { outbox.removeFirst(outbox.count - 200) }
        outLock.unlock()
        NSLog("[GShield][%@] %@ node=%@", code, msg, rec["node"] as? String ?? "")
        onEvent?(code, msg, rec["node"] as? String ?? "")
    }

    private func flushReport() {
        outLock.lock()
        let batch = Array(outbox.prefix(50))
        if !batch.isEmpty { outbox.removeFirst(batch.count) }
        outLock.unlock()
        guard !batch.isEmpty else { return }
        apiPost("/sdk/v1/log", ["token": token, "client": "ios/1.3", "events": batch]) { [weak self] ok in
            guard let self, !ok else { return }
            self.outLock.lock()
            self.outbox.insert(contentsOf: batch, at: 0)
            if self.outbox.count > 200 { self.outbox.removeFirst(self.outbox.count - 200) }
            self.outLock.unlock()
        }
    }

    private func addTunnel() { cntLock.lock(); tunnelCount += 1; cntLock.unlock() }
    private func releaseTunnel() { cntLock.lock(); tunnelCount = max(0, tunnelCount - 1); cntLock.unlock() }

    // ================= 对外: 建立游戏到源站端口的加密隧道(双通道会话保持) =================
    @discardableResult
    public func connect(sourcePort: Int, completion: @escaping (Result<TunnelConnection, Error>) -> Void) -> () -> Void {
        var cancelled = false
        var connecting: TunnelTLS?
        ensureStarted { [weak self] ok in
            guard !cancelled else { return }
            guard let self, ok else { return completion(.failure(GSError.tunnelFail)) }
            let tun = TunnelTLS(key: self.key, projectId: self.conf.projectId, port: sourcePort,
                                tunnelPort: self.conf.tunnelPort,
                                nodeList: { [weak self] in
                                    guard let self else { return [] }
                                    if self.nodeQueue.isEmpty { self.refreshNodes() }
                                    return self.nodeQueue
                                },
                                markBad: { [weak self] in self?.dropAndSwap($0) })
            connecting = tun
            tun.evtFn = { [weak self] c, m, n in self?.evt(c, m, n) }
            let id = UUID()
            self.ownedTunnels[id] = tun
            var counted = false
            tun.onRelease = { [weak self] in
                if counted { self?.releaseTunnel() }
                self?.ownedTunnels.removeValue(forKey: id)
            }
            var replied = false
            tun.onReady = { [weak self, weak tun] in
                guard let self, let tun else { return }
                if !replied {
                    replied = true
                    self.addTunnel()
                    counted = true
                    completion(.success(tun))
                }
            }
            tun.onDead = { if !replied { replied = true; completion(.failure(GSError.noNode)) } }
            tun.start()
        }
        return {
            youmengQueue.async {
                cancelled = true
                connecting?.cancel()
                connecting = nil
            }
        }
    }

    /// 隧道池: conf.ports 每个源站端口预建一条长隧道 (localPort -> TunnelConnection)
    public func startTunnelPool(completion: (([Int: TunnelConnection]) -> Void)?) {
        ensureStarted { [weak self] ok in
            guard let self, ok else { completion?([:]); return }
            var pool = [Int: TunnelConnection]()
            let group = DispatchGroup()
            for (lp, sp) in self.conf.ports {
                group.enter()
                self.connect(sourcePort: sp) { r in
                    if case let .success(c) = r { pool[lp] = c }
                    group.leave()
                }
            }
            group.notify(queue: youmengQueue) { completion?(pool) }
        }
    }

    public func stop() {
        let tunnels = Array(ownedTunnels.values); ownedTunnels.removeAll()
        tunnels.forEach { $0.cancel() }
        generation += 1; started = false; finishStart(false)
        refreshingNodes = false; lastNodeRefresh = .distantPast
        tickTimer?.cancel(); tickTimer = nil
        evt("stop", "SDK停止")
        flushReport()
    }

    // ================= 调度(玩家侧实测排序 + 空闲休眠 + 5秒探活热切) =================
    private var started = false
    private var generation = 0
    private var starting = false
    private var waiters = [(Bool) -> Void]()
    private var refreshingNodes = false
    private var lastNodeRefresh = Date.distantPast

    /// Failed initial dials are still demand. An exhausted pool must recover
    /// without requiring an established tunnel (or a full SDK restart).
    private func refreshNodes() {
        guard started, !refreshingNodes,
              Date().timeIntervalSince(lastNodeRefresh) >= 5 else { return }
        refreshingNodes = true
        lastNodeRefresh = Date()
        let attempt = generation
        api("/sdk/v1/nodes?token=\(token)") { [weak self] document in
            guard let self, attempt == self.generation else { return }
            self.refreshingNodes = false
            guard document?["code"] as? Int == 0 else {
                self.evt("sched_fail", "重新获取节点失败，将自动重试"); return
            }
            self.applyNodes(document)
            self.evt("sched_refresh", "重新获取候选节点: \(self.nodeQueue.count)")
        }
    }

    public func prepareRules(_ completion: @escaping ([Int: Int]?) -> Void) {
        ensureStarted { ok in completion(ok ? self.conf.ports : nil) }
    }

    private func ensureStarted(_ then: @escaping (Bool) -> Void) {
        youmengQueue.async {
            if self.started { then(true); return }
            self.waiters.append(then)
            if self.starting { return }
            self.starting = true
            let attempt = self.generation
            let documents = DispatchGroup()
            var configuration: [String: Any]?
            var nodeDocument: [String: Any]?
            documents.enter()
            self.api("/sdk/v1/conf?token=\(self.token)") { json in
                configuration = json
                documents.leave()
            }
            documents.enter()
            self.api("/sdk/v1/nodes?token=\(self.token)") { nodes in
                nodeDocument = nodes
                documents.leave()
            }
            documents.notify(queue: youmengQueue) {
                guard attempt == self.generation else { return }
                let json = configuration
                guard json?["code"] as? Int == 0,
                      let d = json?["data"] as? [String: Any],
                      let project = d["project_id"] as? Int, project > 0,
                      let port = d["tunnel_port"] as? Int, (1...65535).contains(port),
                      let ports = d["ports"] as? [String: Int], !ports.isEmpty,
                      ["tcp", "all"].contains(d["protocol"] as? String ?? "tcp") else {
                    self.finishStart(false); return
                }
                self.conf.projectId = project
                self.conf.tunnelPort = port
                self.conf.ports = [:]
                for (key, value) in ports {
                    guard let local = Int(key), (1...65535).contains(local), (1...65535).contains(value) else {
                        self.finishStart(false); return
                    }
                    self.conf.ports[local] = value
                }
                do {
                    let nodes = nodeDocument
                    guard attempt == self.generation else { return }
                    guard nodes?["code"] as? Int == 0 else { self.finishStart(false); return }
                    self.applyNodes(nodes)
                    guard !self.nodeQueue.isEmpty else { self.finishStart(false); return }
                    self.startScheduler()
                    self.finishStart(true)
                }
            }
        }
    }

    private func finishStart(_ ok: Bool) {
        starting = false
        started = ok
        let callbacks = waiters
        waiters.removeAll()
        callbacks.forEach { $0(ok) }
    }

    private func applyNodes(_ nj: [String: Any]?) {
        guard let nodes = (nj?["data"] as? [String: Any])?["nodes"] as? [[String: Any]] else {
            evt("sched_fail", "节点列表获取失败", "")
            return
        }
        nodeQueue = nodes.compactMap { $0["ip"] as? String }.filter { !$0.isEmpty }
        nodeIP = nodeQueue.first
        rankByRtt { [weak self] in self?.nodeIP = self?.nodeQueue.first ?? self?.nodeIP }
    }

    /// 全部候选 PING/PONG 实测RTT, 升序重排队列
    private func rankByRtt(done: (() -> Void)? = nil) {
        let attempt = generation
        let snapshot = nodeQueue
        guard !snapshot.isEmpty else { done?(); return }
        let group = DispatchGroup()
        var rtt: [String: TimeInterval] = [:]
        for ip in snapshot {
            group.enter()
            measureRtt(ip) { ms in rtt[ip] = ms; group.leave() }
        }
        group.notify(queue: youmengQueue) { [weak self] in
            guard let self, attempt == self.generation else { return }
            self.nodeQueue.sort { (rtt[$0] ?? .greatestFiniteMagnitude) < (rtt[$1] ?? .greatestFiniteMagnitude) }
            let desc = self.nodeQueue.map { ip in ip + "=" + (rtt[ip] == .greatestFiniteMagnitude ? "超时" : "\(Int(rtt[ip] ?? 0))ms") }.joined(separator: " | ")
            self.evt("sched_ok", "测速排序: " + desc, "")
            done?()
        }
    }

    /// TCP连隧道口发PING量PONG往返; 超时=Inf
    private func measureRtt(_ ip: String, _ done: @escaping (TimeInterval) -> Void) {
        let t0 = Date()
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: NWEndpoint.Port("\(conf.tunnelPort)")!, using: .tcp)
        var finished = false
        let lock = NSLock()
        func finish(_ v: TimeInterval) { lock.lock(); defer { lock.unlock() }; if !finished { finished = true; conn.cancel(); done(v) } }
        youmengQueue.asyncAfter(deadline: .now() + 1.5) { finish(.greatestFiniteMagnitude) }
        conn.stateUpdateHandler = { st in
            if case .ready = st { conn.send(content: gsFrame(3, Data()), completion: .contentProcessed { _ in }) }
            if case .failed = st { finish(.greatestFiniteMagnitude) }
        }
        conn.receive(minimumIncompleteLength: 5, maximumLength: 5) { data, _, isComplete, _ in
            if let data, data.count >= 5, data[data.startIndex] == 4 { finish(Date().timeIntervalSince(t0) * 1000) }
            else if isComplete { finish(.greatestFiniteMagnitude) }
        }
        conn.start(queue: youmengQueue)
    }

    /// 探活: 当前节点失联/劣化 -> 摘除热切下一个(仅活跃隧道时由tick驱动)
    private func probeCurrent() {
        guard let cur = nodeIP else { return }
        measureRtt(cur) { [weak self] ms in
            guard let self else { return }
            if ms == .greatestFiniteMagnitude {
                self.evt("node_down", "主节点失联(疑被攻击/宕机), 热切", cur)
                self.dropAndSwap(cur)
            } else if ms > 2000 {
                self.evt("rtt_bad", "主节点延迟劣化 \(Int(ms))ms", cur)
                self.dropAndSwap(cur)
            }
        }
    }

    private func dropAndSwap(_ bad: String) {
        nodeQueue.removeAll { $0 == bad }
        if bad == nodeIP {
            nodeIP = nodeQueue.first
            evt(nodeIP == nil ? "sched_fail" : "node_switch",
                "摘除节点 \(bad)" + (nodeIP.map { " -> 热切 \($0)" } ?? "(无备选, 等待重调度)"), bad)
        }
    }

    /// 全局唯一周期timer: 5s tick。空闲=0网络活动; 30s批量上报; 300s全量重排(仅活跃时)
    private func startScheduler() {
        let p = DispatchSource.makeTimerSource(queue: youmengQueue)
        p.schedule(deadline: .now() + 5, repeating: 5)
        p.setEventHandler { [weak self] in
            guard let self else { return }
            self.tick += 1
            self.cntLock.lock(); let active = self.tunnelCount > 0; self.cntLock.unlock()
            if active && self.idleState {
                self.idleState = false
                self.evt("idle_exit", "游戏连接到达, 恢复调度探测")
            }
            if active {
                self.probeCurrent()
                if self.tick % 60 == 0 { self.refreshNodes() }
            } else if !self.idleState {
                self.idleState = true
                self.evt("idle_enter", "游戏隧道全部关闭, 休眠(零网络活动)")
            }
            if self.tick % 6 == 0 { self.flushReport() }
        }
        p.resume(); tickTimer = p
    }

    private func api(_ path: String, _ completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: cp + path) else { return completion(nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let valid = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            youmengQueue.async { completion(valid ? json : nil) }
        }.resume()
    }

    private func apiPost(_ path: String, _ body: [String: Any], _ done: @escaping (Bool) -> Void) {
        guard let url = URL(string: cp + path) else { return done(false) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return done(false) }
            done((200...299).contains(http.statusCode))
        }.resume()
    }
}
