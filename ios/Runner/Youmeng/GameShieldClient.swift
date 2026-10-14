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
        NSLog("[GShield][%@] %@", code, msg)
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
    public func connect(sourcePort: Int, completion: @escaping (Result<TunnelConnection, Error>) -> Void) {
        ensureStarted { [weak self] ok in
            guard let self, ok else { return completion(.failure(GSError.tunnelFail)) }
            let tun = TunnelTLS(key: self.key, projectId: self.conf.projectId, port: sourcePort,
                                tunnelPort: self.conf.tunnelPort,
                                nodeList: { self.nodeQueue.isEmpty ? [self.nodeIP ?? ""].filter { !$0.isEmpty } : self.nodeQueue },
                                markBad: { self.dropAndSwap($0) })
            tun.evtFn = { c, m, n in self.evt(c, m, n) }
            let id = UUID()
            self.ownedTunnels[id] = tun
            var counted = false
            tun.onRelease = { [weak self] in
                if counted { self?.releaseTunnel() }
                self?.ownedTunnels.removeValue(forKey: id)
            }
            var replied = false
            tun.onReady = {
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
        tickTimer?.cancel(); tickTimer = nil
        evt("stop", "SDK停止")
        flushReport()
    }

    // ================= 调度(玩家侧实测排序 + 空闲休眠 + 5秒探活热切) =================
    private var started = false
    private var generation = 0
    private var starting = false
    private var waiters = [(Bool) -> Void]()

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
        nodeQueue = nodes.compactMap { $0["ip"] as? String }
        rankByRtt { [weak self] in self?.nodeIP = self?.nodeQueue.first ?? self?.nodeIP }
    }

    /// 全部候选 PING/PONG 实测RTT, 升序重排队列
    private func rankByRtt(done: (() -> Void)? = nil) {
        let snapshot = nodeQueue
        guard !snapshot.isEmpty else { done?(); return }
        let group = DispatchGroup()
        var rtt: [String: TimeInterval] = [:]
        for ip in snapshot {
            group.enter()
            measureRtt(ip) { ms in rtt[ip] = ms; group.leave() }
        }
        group.notify(queue: youmengQueue) { [weak self] in
            guard let self else { return }
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
                if self.tick % 60 == 0 {
                    self.api("/sdk/v1/nodes?token=\(self.token)") { nj in self.applyNodes(nj) }
                }
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

// ================= 加密隧道连接 =================
public protocol TunnelConnection: AnyObject {
    func send(_ data: Data)
    func receive(_ handler: @escaping (Data?) -> Void)
    func cancel()
}

/// 双通道(主+备)AES-256-GCM隧道, 与 PC/安卓 同设计的毫秒级无缝切换:
///   1. 上行镜像写主/备两路; 主路故障 -> 备路"升主"(数据完整零丢包)
///   2. 备路下行在主用期间静默丢弃(镜像语义, 防重复注入游戏)
///   3. 无备路可升时: 断口帧进 pending(默认64KB) + 0.5s 周期重挂, 30s 宽限期才断游戏
///      (第卅七轮: 10s→30s, 4G↔WiFi切换/弱网瞬断常在10~25秒, 旧窗口会误杀可救的局)
final class TunnelTLS: TunnelConnection {
    private final class Path {
        let ip: String; let conn: NWConnection; let isBackup: Bool
        var rx = Data(); var live = false; var helloSent = false
        var down = false                      // 第卅七轮: pathDown 幂等锁(初拨超时与连接失败双路触发只处理一次)
        var lastBeat = Date()          // 在隧心跳: 任何下行帧刷新(第卅三轮, 哑死判位)
        init(ip: String, conn: NWConnection, backup: Bool) { self.ip = ip; self.conn = conn; isBackup = backup }
    }
    private let key: SymmetricKey
    private let projectId: Int
    private let port: Int
    /// 网关会话锚: 本隧道生命周期内不变, 主/备路径共用同一 sid —— 源站网关据此跨节点归并会话
    private let sid = Data.randomHex(10)
    private let tunnelPort: NWEndpoint.Port?
    private let nodeList: () -> [String]
    private let markBad: (String) -> Void
    private let q = youmengQueue
    private let lock = NSLock()
    private var primary: Path?
    private var backup: Path?
    private var pending = [Data]()
    private var pendingLen = 0
    private var pendingCap = 65536              // 断口缓冲上限(轻量: 默认仅64KB)
    private var deadline = Date.distantFuture
    private var handler: ((Data?) -> Void)?
    private var earlyData = [Data]()
    private var earlyBytes = 0
    var onReady: (() -> Void)?
    var onDead: (() -> Void)?
    /// 事件上报钩子(由 GameShieldClient 注入): 升主/重挂/拒绝等生命周期原因
    var evtFn: ((String, String, String) -> Void)?
    /// 隧道寿命结束钩子(空闲休眠计数的释放)
    var onRelease: (() -> Void)?
    private var released = false
    private var readySent = false
    private var closed = false
    private var lastDialAt = Date.distantPast      // 第卅七轮: 初拨失败重挂窗口内0.5s步进会重复ensurePaths, 限6s一条拨号防堆积

    private func releaseOnce() {
        lock.lock(); let first = !released; released = true; lock.unlock()
        if first { onRelease?() }
    }

    init(key: SymmetricKey, projectId: Int, port: Int, tunnelPort: Int,
         nodeList: @escaping () -> [String], markBad: @escaping (String) -> Void) {
        self.key = key; self.projectId = projectId; self.port = port
        self.nodeList = nodeList; self.markBad = markBad
        let s = NWEndpoint.Port("\(tunnelPort)")
        self.tunnelPort = s
    }

    func start() { q.async { self.ensurePaths(); self.startKeepalive() } }

    private func ensurePaths() {
        let list = nodeList()
        lock.lock()
        let needPrimary = primary == nil, needBackup = backup == nil
        let curIp = primary?.ip
        lock.unlock()
        guard !closed else { return }
        if needPrimary {
            guard let ip = list.first else { beginRetry(); return }
            if Date().timeIntervalSince(lastDialAt) < 6 { return }
            lastDialAt = Date()
            open(ip, backup: false)
            if list.count > 1 { open(list[1], backup: true) }
            return
        }
        if needBackup, let alt = list.first(where: { $0 != curIp }) { open(alt, backup: true) }
    }

    private func open(_ ip: String, backup isB: Bool) {
        guard let tp = tunnelPort else { return }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: tp, using: .tcp)
        let p = Path(ip: ip, conn: conn, backup: isB)
        conn.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            if self.closed { conn.cancel(); return }
            switch st {
            case .ready:
                guard !p.helloSent else { return }
                p.helloSent = true
                conn.send(content: gsFrame(1, Data(self.helloJSON().utf8)), completion: .contentProcessed { _ in })
                p.live = true
                self.lock.lock()
                if isB { self.backup = p; self.lock.unlock(); self.evtFn?("backup_up", "备通道待命(双写镜像)", ip) }
                else {
                    self.primary = p
                    let first = !self.readySent
                    self.readySent = true; self.deadline = .distantFuture
                    // ★第卅七轮: 重挂成功后先补发断口期缓冲(与 PC/安卓 对齐; 旧版初拨失败重挂的积压帧永不投递)
                    let pend = self.pending; self.pending = []; self.pendingLen = 0
                    self.lock.unlock()
                    for f in pend { self.write(p, f) }
                    if first { self.onReady?() }
                    else { self.evtFn?("resume_ok", "已重挂 \(ip), 游戏无掉线", ip) }
                }
                self.pump(p)
            case .failed: self.pathDown(p)
            case .cancelled: p.live = false
            default: break
            }
        }
        conn.start(queue: q)
        q.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            if !p.helloSent {
                self.evtFn?("tunnel_err", "TCP可连但6秒无HELLO响应(\(ip)): 节点丢包/防火墙异常", ip)
                self.pathDown(p)
            }
        }
    }

    private func helloJSON() -> String {
        let nonce = Data.randomHex(8)
        let auth = Data(HMAC<SHA256>.authenticationCode(for: Data("\(projectId):\(port):\(nonce)".utf8), using: key)).hexString
        return "{\"v\":1,\"project_id\":\(projectId),\"port\":\(port),\"nonce\":\"\(nonce)\",\"auth\":\"\(auth)\",\"proto\":\"tcp\",\"sid\":\"\(sid)\"}"
    }

    private func pathDown(_ p: Path) {
        guard !closed else { return }
        lock.lock()
        if p.down { lock.unlock(); return }          // 幂等: 6s无响应超时与连接failed可能双触发
        p.down = true
        p.live = false
        p.conn.cancel()
        if p.isBackup {
            if backup === p { backup = nil }
            lock.unlock()
            return
        }
        if primary === p {
            primary = nil
            let promote: Path? = (backup?.live == true) ? backup : nil
            if let b = promote { backup = nil; primary = b; readySent = true }
            let pend = pending; pending = []; pendingLen = 0
            lock.unlock()
            markBad(p.ip)
            if let b = promote {
                evtFn?("backup_promote", "备通道升主, 原节点\(p.ip)故障, 游戏零丢包毫秒级切换", b.ip)
                for f in pend { write(b, f) }
                ensurePaths()
            } else {
                evtFn?("node_down", "主通道断口(无备通道), 游戏连接保持, 重挂中(缓冲\(pend.count)帧)", p.ip)
                for f in pend { enqueue(f) }        // 无备可升: 断口缓冲
                beginRetry()
            }
        } else {
            // ★第卅七轮: 初次拨号失败(尚未成为主路)旧版静默吞掉 —— connect() 回调永不返回,
            //   iOS 侧"点了就卡死"。现在摘除坏节点并走同一重挂宽限期, 到期才以失败回调收口。
            lock.unlock()
            markBad(p.ip)
            evtFn?("tunnel_err", "建盾失败(\(p.ip)), 自动换节点重试(游戏侧保持等待)", p.ip)
            beginRetry()
        }
    }

    // ---- 在隧心跳看门狗(第卅三轮): 哑死盲区补位 ----
    //   节点被打宕机/断网时 NWConnection 未必进 .failed(半开), 主道冻结+备道下行被镜像丢弃。
    //   每2s对主/备各发一帧 PING 并以 lastBeat 判死: 主道6s无下行=pathDown 走既有
    //   备门升主/重挂(毫秒级); 备道12s无响应=重建镜像备份。与 PC/安卓 同参数。
    private func startKeepalive() {
        q.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.closed else { return }
            self.tickAlive()
            self.startKeepalive()
        }
    }
    private func tickAlive() {
        lock.lock()
        let a = (primary?.live == true) ? primary : nil
        let b = (backup?.live == true) ? backup : nil
        let now = Date()
        let aStale = a.map { now.timeIntervalSince($0.lastBeat) > 6 } ?? false
        let bStale = b.map { now.timeIntervalSince($0.lastBeat) > 12 } ?? false
        lock.unlock()
        let ping = gsFrame(3, Data())              // T.PING
        if let a {
            if aStale { evtFn?("hb_dead", "心跳判主隧道6秒无响应(疑节点宕机/断网哑死), 主动无缝切换", a.ip); pathDown(a) }
            else { write(a, ping) }
        }
        if let b {
            if bStale { evtFn?("hb_backup", "备通道心跳超时, 重建镜像备份", b.ip); pathDown(b); ensurePaths() }
            else { write(b, ping) }
        }
        if a != nil && !aStale && b == nil { ensurePaths() }   // 备通道缺失: 持续补位
    }

    private func beginRetry() {
        lock.lock()
        if primary != nil || closed { lock.unlock(); return }
        if deadline == .distantFuture { deadline = Date().addingTimeInterval(30) }   // ★第卅七轮: 重挂宽限期 10s→30s
        lock.unlock()
        retryStep()
    }
    private func retryStep() {
        lock.lock()
        if primary != nil || closed { lock.unlock(); return }
        let expired = Date() > deadline
        lock.unlock()
        if expired {
            evtFn?("resume_fail", "30秒内无法重挂任何节点(全部失联/握手被拒), 游戏断开", "")
            handler?(nil); cancel(); return
        }
        ensurePaths()
        q.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.retryStep() }
    }

    private func write(_ p: Path, _ frame: Data) { p.conn.send(content: frame, completion: .contentProcessed { _ in }) }
    private func enqueue(_ f: Data) {
        pending.append(f); pendingLen += f.count
        if pendingLen > pendingCap { handler?(nil); cancel() }
    }

    private func pump(_ p: Path) {
        p.conn.receive(minimumIncompleteLength: 1, maximumLength: 655360) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { p.rx.append(data); self.drain(p) }
            if isComplete || error != nil { self.pathDown(p); return }
            self.pump(p)
        }
    }

    private func drain(_ p: Path) {
        while p.rx.count >= 5 {
            let len = Int(gsBeUInt32(p.rx.subdata(in: 1..<5)))
            // 第卅九轮回4: len==0 的 PONG/控制帧必须正常消费 —— 旧 guard len>0 让空帧滞留 rx 头部,
            // 其后所有 DATA 永远读不出(整条隧道冻死)。与 Java 端 readFrame 同源 bug 同批修。
            guard len <= 655360 else { handler?(nil); cancel(); return }
            guard p.rx.count >= 5 + len else { return }
            let type = p.rx[p.rx.startIndex]
            let payload = p.rx.subdata(in: (p.rx.startIndex + 5)..<(p.rx.startIndex + 5 + len))
            p.rx.removeSubrange(p.rx.startIndex..<(p.rx.startIndex + 5 + len))
            p.lastBeat = Date()                    // 任何下行帧(PONG/DATA)=隧道活着
            guard type == 2 else { continue }
            lock.lock(); let isActive = p === primary; lock.unlock()
            guard isActive else { continue }            // 备路下行丢弃(镜像语义)
            if let plain = gcmOpen(payload) {
                if let handler { handler(plain) }
                else {
                    earlyBytes += plain.count
                    guard earlyBytes <= 1048576 else { cancel(); return }
                    earlyData.append(plain)
                }
            } else { handler?(nil); cancel(); return }
        }
    }

    // ---- TunnelConnection ----
    func send(_ data: Data) {
        guard !closed else { return }
        guard let enc = (try? AES.GCM.seal(data, using: key))?.combined else { return }
        let f = gsFrame(2, enc)
        lock.lock()
        let a = primary?.live == true ? primary : nil
        let b = backup?.live == true ? backup : nil
        lock.unlock()
        if let a { write(a, f) }
        if let b { write(b, f) }
        if a == nil { enqueue(f) }
    }
    func receive(_ handler: @escaping (Data?) -> Void) {
        self.handler = handler
        if closed { handler(nil); return }
        let buffered = earlyData; earlyData.removeAll(); earlyBytes = 0
        buffered.forEach { handler($0) }
    }
    func cancel() {
        guard !closed else { return }
        closed = true
        onDead?(); onDead = nil; onReady = nil
        releaseOnce()
        lock.lock(); let ps = [primary, backup].compactMap { $0 }; primary = nil; backup = nil; lock.unlock()
        ps.forEach { $0.conn.cancel() }
    }

    private func gcmOpen(_ raw: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: raw) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

// ================= 帧与工具 =================
private func gsFrame(_ type: UInt8, _ payload: Data) -> Data {
    var h = Data([type])
    var l = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &l) { h.append(contentsOf: $0) }
    return h + payload
}
private func gsBeUInt32(_ d: Data) -> UInt32 {
    var v: UInt32 = 0
    for b in d { v = (v << 8) | UInt32(b) }
    return v
}
extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
    static func randomHex(_ bytes: Int) -> String {
        Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).hexString
    }
}
enum GSError: Error { case noNode, tunnelFail }
