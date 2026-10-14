import Flutter
import Foundation
import Network

/// All SDK and listener state is confined to youmengQueue.
final class YoumengBridge {
    private var channel: FlutterMethodChannel?
    private var sdk: GameShieldClient?
    private var listeners = [NWListener]()
    private var connections = [UUID: YoumengConnection]()
    private var pending: FlutterResult?
    private var ready = false
    private var generation = 0
    private let ports = [10008, 10002, 10001, 8815]

    func attach(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "openim/youmeng", binaryMessenger: messenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            guard call.method == "start" else { result(FlutterMethodNotImplemented); return }
            guard let args = call.arguments as? [String: String],
                  let cp = args["cp"], let url = URL(string: cp), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  let token = args["token"], !token.isEmpty,
                  let key = args["key"], key.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                result(FlutterError(code: "CONFIGURATION", message: "网络保护配置无效", details: nil)); return
            }
            youmengQueue.async { self.start(cp: cp, token: token, key: key, result: result) }
        }
    }

    private func start(cp: String, token: String, key: String, result: @escaping FlutterResult) {
        if ready { DispatchQueue.main.async { result(true) }; return }
        if pending != nil {
            DispatchQueue.main.async { result(FlutterError(code: "BUSY", message: "正在启动网络保护", details: nil)) }; return
        }
        generation += 1
        let attempt = generation
        pending = result
        let client = GameShieldClient(cp: cp, token: token, aesKeyHex: key)
        sdk = client
        client.prepareRules { [weak self] rules in
            guard let self, self.generation == attempt, self.pending != nil else { return }
            guard let rules, self.ports.allSatisfy({ rules[$0] != nil }) else { self.fail(); return }
            do {
                var bound = Set<Int>()
                for port in self.ports {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(port))!)
                    let listener = try NWListener(using: parameters)
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self, self.generation == attempt else { return }
                        switch state {
                        case .ready:
                            bound.insert(port)
                            if bound.count == self.ports.count {
                                self.ready = true
                                let callback = self.pending; self.pending = nil
                                NSLog("[Youmeng] local TCP listeners ready: 10008,10002,10001,8815")
                                DispatchQueue.main.async { callback?(true) }
                            }
                        case .failed: self.fail()
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] socket in
                        guard let self, self.ready, self.generation == attempt else { socket.cancel(); return }
                        let id = UUID()
                        let connection = YoumengConnection(socket: socket, sdk: client, port: rules[port]!) { [weak self] in
                            self?.connections.removeValue(forKey: id)
                        }
                        self.connections[id] = connection
                        connection.start()
                    }
                    self.listeners.append(listener)
                    listener.start(queue: youmengQueue)
                }
            } catch { self.fail() }
        }
        youmengQueue.asyncAfter(deadline: .now() + 40) { [weak self] in
            guard let self, self.generation == attempt, self.pending != nil else { return }
            self.fail()
        }
    }

    private func fail() {
        generation += 1; ready = false
        let callback = pending; pending = nil
        listeners.forEach { $0.cancel() }; listeners.removeAll()
        let active = Array(connections.values); connections.removeAll()
        active.forEach { $0.close() }
        sdk?.stop(); sdk = nil
        DispatchQueue.main.async { callback?(FlutterError(code: "START_FAILED", message: "网络保护启动失败，请检查配置后重试", details: nil)) }
    }
}

private final class YoumengConnection {
    private let socket: NWConnection
    private let sdk: GameShieldClient
    private let port: Int
    private let onClose: () -> Void
    private var tunnel: TunnelConnection?
    private var cancelConnect: (() -> Void)?
    private var input = [Data]()
    private var inputBytes = 0
    private var closed = false
    private var output = [Data]()
    private var outputBytes = 0
    private var sending = false

    init(socket: NWConnection, sdk: GameShieldClient, port: Int, onClose: @escaping () -> Void) {
        self.socket = socket; self.sdk = sdk; self.port = port; self.onClose = onClose
    }
    func start() {
        socket.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state { self.close() }
            if case .cancelled = state { self.close() }
        }
        socket.start(queue: youmengQueue)
        // Read immediately, including EOF while HELLO is pending. Otherwise a
        // timed-out local probe leaves its native dials running in the background.
        read()
        cancelConnect = sdk.connect(sourcePort: port) { [weak self] result in
            guard let self, !self.closed else {
                if case .success(let tunnel) = result { tunnel.cancel() }; return
            }
            switch result {
            case .failure: self.close()
            case .success(let tunnel):
                self.tunnel = tunnel
                tunnel.receive { [weak self] data in
                    guard let self, !self.closed else { return }
                    guard let data else { self.close(); return }
                    self.outputBytes += data.count
                    guard self.outputBytes <= 4 * 1024 * 1024 else { self.close(); return }
                    self.output.append(data); self.flush()
                }
                let buffered = self.input
                self.input.removeAll(); self.inputBytes = 0
                for data in buffered where !self.closed { tunnel.send(data) }
            }
        }
    }
    private func read() {
        socket.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, done, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                if let tunnel = self.tunnel { tunnel.send(data) }
                else {
                    self.inputBytes += data.count
                    guard self.inputBytes <= 65536 else { self.close(); return }
                    self.input.append(data)
                }
            }
            if done || error != nil { self.close() } else { self.read() }
        }
    }
    private func flush() {
        guard !closed, !sending, !output.isEmpty else { return }
        sending = true
        let data = output.removeFirst()
        socket.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            self.sending = false; self.outputBytes -= data.count
            if error != nil { self.close() } else { self.flush() }
        })
    }
    func close() {
        guard !closed else { return }; closed = true
        socket.stateUpdateHandler = nil
        socket.cancel(); tunnel?.cancel(); tunnel = nil
        cancelConnect?(); cancelConnect = nil
        input.removeAll(); inputBytes = 0
        output.removeAll(); outputBytes = 0
        onClose()
    }
}
