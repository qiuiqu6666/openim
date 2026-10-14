import Foundation
import Network
import CryptoKit

public protocol TunnelConnection: AnyObject {
    func send(_ data: Data)
    func receive(_ handler: @escaping (Data?) -> Void)
    func cancel()
}

/// All state and callbacks belong to youmengQueue. TCP readiness is not a
/// successful tunnel: the server must acknowledge HELLO with a PONG first.
final class TunnelTLS: TunnelConnection {
    private final class Path {
        let ip: String
        let conn: NWConnection
        var rx = Data()
        var live = false
        var helloSent = false
        var down = false
        var lastBeat = Date()
        init(ip: String, conn: NWConnection) { self.ip = ip; self.conn = conn }
    }
    private let key: SymmetricKey
    private let projectId: Int
    private let port: Int
    private let sid = Data.randomHex(10)
    private let tunnelPort: NWEndpoint.Port?
    private let nodeList: () -> [String]
    private let markBad: (String) -> Void
    private let makeConnection: (String, NWEndpoint.Port) -> NWConnection
    private let handshakeTimeout: TimeInterval
    private let retryTimeout: TimeInterval
    private let q = youmengQueue
    // Slots include pending dials, preventing duplicate connections and allowing
    // cancellation even before TCP or HELLO has completed. Roles are mutable.
    private var primary: Path?
    private var backup: Path?
    private var pending = [Data]()
    private var pendingLen = 0
    private var deadline = Date.distantFuture
    private var retryScheduled = false
    private var handler: ((Data?) -> Void)?
    private var earlyData = [Data]()
    private var earlyBytes = 0
    private var readySent = false
    private var closed = false
    var onReady: (() -> Void)?
    var onDead: (() -> Void)?
    var onRelease: (() -> Void)?
    var evtFn: ((String, String, String) -> Void)?

    init(key: SymmetricKey, projectId: Int, port: Int, tunnelPort: Int,
         nodeList: @escaping () -> [String], markBad: @escaping (String) -> Void,
         handshakeTimeout: TimeInterval = 6, retryTimeout: TimeInterval = 30,
         makeConnection: @escaping (String, NWEndpoint.Port) -> NWConnection = {
             NWConnection(host: NWEndpoint.Host($0), port: $1, using: .tcp)
         }) {
        self.key = key; self.projectId = projectId; self.port = port
        self.nodeList = nodeList; self.markBad = markBad
        self.tunnelPort = NWEndpoint.Port("\(tunnelPort)")
        self.makeConnection = makeConnection
        self.handshakeTimeout = handshakeTimeout; self.retryTimeout = retryTimeout
    }

    private func event(_ code: String, _ message: String, _ ip: String = "") {
        evtFn?(code, "port=\(port) \(message)", ip)
    }

    func start() {
        q.async { [weak self] in
            guard let self, !self.closed else { return }
            self.beginRetry()
            self.startKeepalive()
        }
    }

    private func ensurePaths() {
        guard !closed else { return }
        let list = nodeList()
        if primary == nil, let ip = list.first(where: { $0 != backup?.ip }) {
            open(ip, backup: false)
        }
        if backup == nil, let ip = list.first(where: { $0 != primary?.ip }) {
            open(ip, backup: true)
        }
    }

    private func open(_ ip: String, backup isBackup: Bool) {
        guard let tp = tunnelPort, !closed else { return }
        let conn = makeConnection(ip, tp)
        let path = Path(ip: ip, conn: conn)
        if isBackup { backup = path } else { primary = path }
        conn.stateUpdateHandler = { [weak self, weak path] state in
            guard let self, let path, !self.closed, !path.down else { return }
            switch state {
            case .ready:
                guard !path.helloSent else { return }
                path.helloSent = true
                self.write(path, gsFrame(1, Data(self.helloJSON().utf8)))
                self.pump(path)
            case .failed: self.pathDown(path, reason: "TCP连接失败")
            case .cancelled: self.pathDown(path, reason: "连接关闭")
            default: break
            }
        }
        conn.start(queue: q)
        q.asyncAfter(deadline: .now() + handshakeTimeout) { [weak self, weak path] in
            guard let self, let path, !self.closed, !path.down, !path.live else { return }
            self.pathDown(path, reason: path.helloSent ? "HELLO确认超时" : "TCP连接超时")
        }
    }

    private func helloJSON() -> String {
        let nonce = Data.randomHex(8)
        let auth = Data(HMAC<SHA256>.authenticationCode(
            for: Data("\(projectId):\(port):\(nonce)".utf8), using: key)).hexString
        return "{\"v\":1,\"project_id\":\(projectId),\"port\":\(port),\"nonce\":\"\(nonce)\",\"auth\":\"\(auth)\",\"proto\":\"tcp\",\"sid\":\"\(sid)\"}"
    }

    private func acknowledged(_ path: Path) {
        guard !closed, !path.down, !path.live else { return }
        path.live = true
        // First authenticated path wins, including when the preferred dial is
        // still pending. Retain that pending dial as the prospective backup.
        if primary?.live != true, backup === path {
            backup = primary
            primary = path
        }
        if primary === path { activate(path) }
        else { event("backup_up", "备通道HELLO已确认，待命", path.ip) }
    }

    private func activate(_ path: Path) {
        deadline = .distantFuture
        let frames = pending; pending.removeAll(); pendingLen = 0
        frames.forEach { write(path, $0) }
        let first = !readySent
        readySent = true
        event(first ? "tunnel_ready" : "resume_ok", "主通道HELLO已确认", path.ip)
        if first {
            let callback = onReady; onReady = nil
            callback?()
        }
        ensurePaths()
    }

    private func pathDown(_ path: Path, reason: String) {
        guard !closed, !path.down else { return }
        path.down = true; path.live = false
        path.conn.stateUpdateHandler = nil
        path.conn.cancel()
        // Use current slot identity, never the role assigned at construction.
        if primary === path { primary = nil }
        if backup === path { backup = nil }
        event("tunnel_err", reason, path.ip)
        markBad(path.ip)
        if primary == nil, let next = backup {
            primary = next; backup = nil
            if next.live {
                event("backup_promote", "备用通道接替主通道", next.ip)
                activate(next)
            }
        }
        if primary?.live == true { ensurePaths() }
        else { beginRetry() }
    }

    private func startKeepalive() {
        q.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.closed else { return }
            let now = Date()
            for path in [self.primary, self.backup].compactMap({ $0 }) where path.live && !path.down {
                let limit: TimeInterval = path === self.primary ? 6 : 12
                if now.timeIntervalSince(path.lastBeat) > limit {
                    self.pathDown(path, reason: "心跳超时")
                } else { self.write(path, gsFrame(3, Data())) }
            }
            self.ensurePaths()
            self.startKeepalive()
        }
    }

    private func beginRetry() {
        guard !closed, primary?.live != true else { return }
        if deadline == .distantFuture { deadline = Date().addingTimeInterval(retryTimeout) }
        retryStep()
    }

    private func retryStep() {
        guard !closed, primary?.live != true, !retryScheduled else { return }
        if Date() >= deadline {
            event("resume_fail", "30秒内未建立可用隧道")
            cancel(); return
        }
        ensurePaths()
        retryScheduled = true
        q.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.retryStep()
        }
    }

    private func write(_ path: Path, _ frame: Data) {
        guard !closed, !path.down else { return }
        path.conn.send(content: frame, completion: .contentProcessed { [weak self, weak path] error in
            guard let self, let path, error != nil else { return }
            self.pathDown(path, reason: "隧道写入失败")
        })
    }

    private func pump(_ path: Path) {
        guard !closed, !path.down else { return }
        path.conn.receive(minimumIncompleteLength: 1, maximumLength: 655360) { [weak self, weak path] data, _, done, error in
            guard let self, let path, !self.closed, !path.down else { return }
            if let data { path.rx.append(data); self.drain(path) }
            if done || error != nil { self.pathDown(path, reason: "远端关闭隧道"); return }
            self.pump(path)
        }
    }

    private func drain(_ path: Path) {
        while !closed && !path.down && path.rx.count >= 5 {
            let start = path.rx.startIndex
            let length = Int(gsBeUInt32(path.rx[(start + 1)..<(start + 5)]))
            guard length <= 655360 else { pathDown(path, reason: "无效帧长度"); return }
            guard path.rx.count >= 5 + length else { return }
            let type = path.rx[start]
            let payload = path.rx.subdata(in: (start + 5)..<(start + 5 + length))
            path.rx.removeSubrange(start..<(start + 5 + length))
            path.lastBeat = Date()
            if !path.live {
                guard type == 4 else { pathDown(path, reason: "HELLO被拒绝或协议不匹配"); return }
                acknowledged(path)
                continue
            }
            if type == 3 { write(path, gsFrame(4, Data())); continue }
            guard type == 2, path === primary else { continue }
            guard let box = try? AES.GCM.SealedBox(combined: payload),
                  let plain = try? AES.GCM.open(box, using: key) else {
                event("decrypt_fail", "业务数据解密失败", path.ip)
                cancel(); return
            }
            if let handler { handler(plain) }
            else {
                earlyBytes += plain.count
                guard earlyBytes <= 1048576 else { cancel(); return }
                earlyData.append(plain)
            }
        }
    }

    func send(_ data: Data) {
        guard !closed else { return }
        guard let encrypted = (try? AES.GCM.seal(data, using: key))?.combined else { cancel(); return }
        let frame = gsFrame(2, encrypted)
        if let path = primary, path.live { write(path, frame) }
        else {
            pending.append(frame); pendingLen += frame.count
            if pendingLen > 65536 { cancel(); return }
        }
        if let path = backup, path.live { write(path, frame) }
    }

    func receive(_ handler: @escaping (Data?) -> Void) {
        if closed { handler(nil); return }
        self.handler = handler
        let buffered = earlyData; earlyData.removeAll(); earlyBytes = 0
        for data in buffered where !closed { handler(data) }
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        let paths = [primary, backup].compactMap { $0 }
        primary = nil; backup = nil
        paths.forEach { $0.down = true; $0.conn.stateUpdateHandler = nil; $0.conn.cancel() }
        pending.removeAll(); pendingLen = 0; earlyData.removeAll(); earlyBytes = 0
        let dead = onDead, release = onRelease, receiver = handler
        onDead = nil; onRelease = nil; onReady = nil; handler = nil
        dead?(); release?(); receiver?(nil)
    }
}

func gsFrame(_ type: UInt8, _ payload: Data) -> Data {
    var header = Data([type])
    var length = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
    return header + payload
}

private func gsBeUInt32(_ data: Data) -> UInt32 {
    data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
    static func randomHex(_ bytes: Int) -> String {
        Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).hexString
    }
}

enum GSError: Error { case noNode, tunnelFail }
