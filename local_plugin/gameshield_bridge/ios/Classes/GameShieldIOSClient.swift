#if canImport(GameShieldSDK)
import Foundation
import Network
import UIKit
import GameShieldSDK

private enum GameShieldClientError: Error { case version, initialization, endpoints }

/// All methods and notifications execute on the bridge's serial worker queue.
final class GameShieldIOSClient {
    private let native: MobileClient
    private let worker: DispatchQueue
    private var monitor: NWPathMonitor?
    private var observer: NSObjectProtocol?
    private var lastPath: String?
    let version: String

    init(token: String, worker: DispatchQueue) throws {
        self.worker = worker
        version = MobileVersion()
        guard version == "60.1.10" else { throw GameShieldClientError.version }
        var directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("GameShield", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        var error: NSError?
        let value = MobileNewClientWithToken(token, directory.path, &error)
        if let error = error { throw error }
        guard let client = value else { throw GameShieldClientError.initialization }
        native = client
    }

    func start() throws {
        try native.setAutoChangePort(true)
        try native.start()
        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self, self.monitor != nil, path.status == .satisfied else { return }
            let names = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }
                .map { $0.name }.sorted()
            let signature = "\(names)|\(path.supportsIPv4)|\(path.supportsIPv6)|\(path.supportsDNS)"
            guard self.lastPath != signature else { return }
            self.lastPath = signature
            self.native.notifyNetworkChanged()
        }
        pathMonitor.start(queue: worker)
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.worker.async { [weak self] in
                guard let self = self, self.monitor != nil else { return }
                self.native.notifyForeground()
                self.native.notifyNetworkChanged()
            }
        }
    }

    func snapshot() throws -> [String: Any] {
        let count = native.endpointCount()
        guard count >= 0 && count <= 1024 else { throw GameShieldClientError.endpoints }
        var endpoints = [[String: Any]]()
        for index in 0..<count {
            var error: NSError?
            let json = native.endpoint(at: index, error: &error)
            if let error = error { throw error }
            guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                let appId = value["app_id"] as? String,
                let group = value["group_name"] as? String,
                let host = value["virtual_ip"] as? String,
                let port = value["virtual_port"] as? Int,
                let proto = value["protocol"] as? String else { throw GameShieldClientError.endpoints }
            endpoints.append(["appId": appId, "groupName": group, "host": host,
                "port": port, "protocol": proto])
        }
        var tcpPorts = [String: Int]()
        for originalPort in [10008, 10002, 10001, 8815] {
            tcpPorts[String(originalPort)] = Int(native.currentTCPPort(originalPort))
        }
        return ["ready": native.ready(), "sdkVersion": version,
            "activeTunnels": native.activeTunnels(), "endpoints": endpoints,
            "tcpPorts": tcpPorts]
    }

    func stop() {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        monitor?.pathUpdateHandler = nil
        monitor?.cancel()
        monitor = nil
        lastPath = nil
        native.stop()
    }
}
#endif
