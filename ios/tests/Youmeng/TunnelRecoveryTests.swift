import Foundation
import Network
import CryptoKit

// This harness uses the production parser, encryption, timers and path state,
// with real local TCP peers. No project token, control plane or phone is needed.
private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

private func wait(_ message: String, seconds: TimeInterval = 3, _ condition: @escaping () -> Bool) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if youmengQueue.sync(execute: condition) { return }
        Thread.sleep(forTimeInterval: 0.01)
    }
    fatalError("Timed out: \(message)")
}

private final class Relay {
    let listener: NWListener
    var port: NWEndpoint.Port { listener.port! }
    var peers = [NWConnection]()
    var hellos = [NWConnection]()
    var closed = 0
    var autoAck = false
    var payloads = [Data]()

    init(autoAck: Bool = false) throws {
        self.autoAck = autoAck
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] peer in
            guard let self else { return }
            self.peers.append(peer)
            peer.start(queue: youmengQueue)
            self.read(peer, buffer: Data())
        }
        listener.start(queue: youmengQueue)
        check(ready.wait(timeout: .now() + 3) == .success, "Relay not listening")
    }

    func send(_ peer: NWConnection, _ data: Data) {
        peer.send(content: data, completion: .contentProcessed { _ in })
    }

    func acknowledgeAll() {
        for peer in hellos { send(peer, gsFrame(4, Data())) }
    }

    func encrypted(_ data: Data) -> Data {
        gsFrame(2, try! AES.GCM.seal(data, using: key).combined!)
    }

    private func read(_ peer: NWConnection, buffer: Data) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 655360) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            while buffer.count >= 5 {
                let start = buffer.startIndex
                let length = buffer[(start + 1)..<(start + 5)].reduce(0) { ($0 << 8) | Int($1) }
                guard buffer.count >= 5 + length else { break }
                let type = buffer[start]
                let body = buffer.subdata(in: (start + 5)..<(start + 5 + length))
                buffer.removeSubrange(start..<(start + 5 + length))
                switch type {
                case 1:
                    self.hellos.append(peer)
                    if self.autoAck { self.send(peer, gsFrame(4, Data())) }
                case 2:
                    let data = try! AES.GCM.open(AES.GCM.SealedBox(combined: body), using: key)
                    self.payloads.append(data)
                    self.send(peer, self.encrypted(data))
                case 3: self.send(peer, gsFrame(4, Data()))
                default: break
                }
            }
            if done || error != nil { self.closed += 1; return }
            self.read(peer, buffer: buffer)
        }
    }

    func stop() { listener.cancel(); peers.forEach { $0.cancel() } }
}

private func tunnel(_ relays: [String: Relay], nodes: @escaping () -> [String],
                    bad: @escaping (String) -> Void = { _ in },
                    handshake: TimeInterval = 6, retry: TimeInterval = 30) -> TunnelTLS {
    TunnelTLS(key: key, projectId: 1, port: 10008, tunnelPort: 20000,
              nodeList: nodes, markBad: bad, handshakeTimeout: handshake,
              retryTimeout: retry, makeConnection: { name, _ in
                  NWConnection(host: "127.0.0.1", port: relays[name]!.port, using: .tcp)
              })
}

@main
private struct TunnelRecoveryTests {
    static func main() throws {
        try handshakeAndFrames()
        try backupWinsAndRecoversAgain()
        try cancelledDialsStayClosed()
        try handshakeDeadline()
        print("PASS: 4 native tunnel recovery scenarios")
    }

    static func handshakeAndFrames() throws {
        let relay = try Relay()
        var ready = 0
        var received = [Data]()
        let subject = tunnel(["a": relay], nodes: { ["a"] })
        youmengQueue.sync {
            subject.onReady = { ready += 1 }
            subject.receive { if let data = $0 { received.append(data) } }
            subject.start()
        }
        wait("HELLO sent") { relay.hellos.count == 1 }
        Thread.sleep(forTimeInterval: 0.1)
        youmengQueue.sync {
            check(ready == 0, "TCP ready must not report tunnel ready")
            let peer = relay.hellos[0]
            // Fragmented empty PONG followed by coalesced DATA and another PONG.
            let bytes = gsFrame(4, Data()) + relay.encrypted(Data("first".utf8)) + gsFrame(4, Data())
            relay.send(peer, bytes.prefix(2))
            youmengQueue.asyncAfter(deadline: .now() + 0.02) { relay.send(peer, bytes.dropFirst(2)) }
        }
        wait("fragmented/coalesced frames") { ready == 1 && received == [Data("first".utf8)] }
        youmengQueue.sync { subject.send(Data("echo".utf8)) }
        wait("encrypted round trip") { received.last == Data("echo".utf8) }
        youmengQueue.sync { subject.cancel(); relay.stop() }
    }

    static func backupWinsAndRecoversAgain() throws {
        let a = try Relay(), b = try Relay(autoAck: true), c = try Relay(autoAck: true)
        var nodes = ["a", "b"]
        var events = [(String, String)]()
        var ready = 0
        let subject = tunnel(["a": a, "b": b, "c": c], nodes: { nodes }, bad: { bad in nodes.removeAll { $0 == bad } })
        youmengQueue.sync {
            subject.onReady = { ready += 1 }
            subject.evtFn = { code, _, node in events.append((code, node)) }
            subject.start()
        }
        wait("backup beats pending primary", seconds: 2) { ready == 1 && events.contains { $0 == ("tunnel_ready", "b") } }
        wait("primary HELLO pending") { a.hellos.count == 1 }
        youmengQueue.sync { a.acknowledgeAll() }
        wait("old primary becomes backup") { events.contains { $0 == ("backup_up", "a") } }
        youmengQueue.sync { b.stop() }
        wait("promoted backup failure recovers") { events.contains { $0 == ("backup_promote", "a") } }
        youmengQueue.sync { nodes = ["c"]; a.stop() }
        wait("second failure redials third node") { events.contains { $0 == ("resume_ok", "c") } }
        youmengQueue.sync {
            check(ready == 1, "connect completion must only run once")
            subject.cancel(); c.stop()
        }
    }

    static func cancelledDialsStayClosed() throws {
        let relay = try Relay()
        var ready = 0, released = 0
        let subject = tunnel(["a": relay], nodes: { ["a"] })
        youmengQueue.sync {
            subject.onReady = { ready += 1 }
            subject.onRelease = { released += 1 }
            subject.start()
        }
        wait("pending HELLO") { relay.hellos.count == 1 }
        youmengQueue.sync { subject.cancel(); subject.cancel(); relay.acknowledgeAll() }
        wait("pending TCP closed") { relay.closed == 1 }
        youmengQueue.sync {
            check(ready == 0 && released == 1, "late ACK resurrected cancelled tunnel")
            relay.stop()
        }
    }

    static func handshakeDeadline() throws {
        let relay = try Relay()
        var nodes = ["a"], ready = 0, dead = 0
        let subject = tunnel(["a": relay], nodes: { nodes }, bad: { _ in nodes = [] }, handshake: 0.1, retry: 0.2)
        youmengQueue.sync {
            subject.onReady = { ready += 1 }; subject.onDead = { dead += 1 }
            subject.start()
        }
        wait("no HELLO ACK reaches bounded failure") { dead == 1 }
        youmengQueue.sync {
            check(ready == 0 && relay.hellos.count == 1, "unacknowledged path accepted or duplicate dial")
            relay.stop()
        }
    }
}
