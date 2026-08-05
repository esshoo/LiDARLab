import Foundation
import Network

private final class UnifiedOneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func run(_ action: () -> Void) {
        lock.lock()
        guard !hasRun else {
            lock.unlock()
            return
        }
        hasRun = true
        lock.unlock()
        action()
    }
}


actor UnifiedAppleDirectTCPClient {
    enum ClientError: LocalizedError {
        case invalidPort
        case connectionFailed(String)
        case notConnected

        var errorDescription: String? {
            switch self {
            case .invalidPort:
                "المنفذ غير صالح."
            case .connectionFailed(let message):
                "فشل الاتصال المباشر: \(message)"
            case .notConnected:
                "لا يوجد اتصال مباشر نشط."
            }
        }
    }

    private var connection: NWConnection?

    func connect(host: String, port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ClientError.invalidPort
        }
        try await connect(endpoint: .hostPort(host: NWEndpoint.Host(host), port: nwPort))
    }

    func connect(endpoint: NWEndpoint) async throws {
        disconnect()
        let newConnection = NWConnection(to: endpoint, using: .tcp)
        connection = newConnection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = UnifiedOneShotGate()
            newConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.run { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    gate.run {
                        continuation.resume(throwing: ClientError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    gate.run {
                        continuation.resume(throwing: ClientError.connectionFailed("تم إلغاء الاتصال."))
                    }
                default:
                    break
                }
            }
            newConnection.start(queue: DispatchQueue(label: "com.essam.3elidar.tcp.sender"))
        }
    }

    func send(_ data: Data) async throws {
        guard let connection else { throw ClientError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: ClientError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }
}

@MainActor
final class UnifiedAppleReceiverBrowser: ObservableObject {
    @Published private(set) var receivers: [UnifiedDiscoveredReceiver] = []
    @Published private(set) var statusText = "لم يبدأ البحث."

    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]

    func start() {
        stop()
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_3eld._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    self.statusText = "جارٍ البحث عن أجهزة استقبال 3ELiDAR."
                case .waiting(let error):
                    self.statusText = "البحث متوقف مؤقتًا: \(error.localizedDescription)"
                case .failed(let error):
                    self.statusText = "فشل البحث: \(error.localizedDescription)"
                case .cancelled:
                    self.statusText = "توقف البحث."
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                var mapped: [UnifiedDiscoveredReceiver] = []
                var endpoints: [String: NWEndpoint] = [:]
                for result in results {
                    let id = String(describing: result.endpoint)
                    endpoints[id] = result.endpoint
                    mapped.append(
                        UnifiedDiscoveredReceiver(
                            id: id,
                            name: Self.displayName(for: result.endpoint),
                            endpointDescription: id
                        )
                    )
                }
                self.endpoints = endpoints
                self.receivers = mapped.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.statusText = mapped.isEmpty ? "لا توجد أجهزة استقبال ظاهرة." : "تم العثور على \(mapped.count) جهاز."
            }
        }

        browser.start(queue: DispatchQueue(label: "com.essam.3elidar.bonjour.browser"))
    }

    func endpoint(for receiverID: String) -> NWEndpoint? {
        endpoints[receiverID]
    }

    func stop() {
        browser?.cancel()
        browser = nil
        endpoints.removeAll()
        receivers.removeAll()
    }

    private static func displayName(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return String(describing: endpoint)
        }
    }
}

final class UnifiedAppleDirectReceiverServer {
    enum ServerError: LocalizedError {
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .invalidPort: "منفذ الاستقبال غير صالح."
            }
        }
    }

    private final class Peer {
        let connection: NWConnection
        let decoder = UnifiedPacketStreamDecoder()

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let queue = DispatchQueue(label: "com.essam.3elidar.tcp.receiver")
    private var listener: NWListener?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var onPacket: (@Sendable (Data) -> Void)?
    private var onStatus: (@Sendable (String) -> Void)?

    func start(
        port: UInt16,
        serviceName: String,
        onPacket: @escaping @Sendable (Data) -> Void,
        onStatus: @escaping @Sendable (String) -> Void
    ) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw ServerError.invalidPort }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.service = NWListener.Service(name: serviceName, type: "_3eld._tcp")
        self.listener = listener
        self.onPacket = onPacket
        self.onStatus = onStatus

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onStatus?("الاستقبال المباشر جاهز على المنفذ \(port).")
            case .waiting(let error):
                self?.onStatus?("الاستقبال ينتظر: \(error.localizedDescription)")
            case .failed(let error):
                self?.onStatus?("فشل الاستقبال: \(error.localizedDescription)")
            case .cancelled:
                self?.onStatus?("توقف الاستقبال المباشر.")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for peer in peers.values {
            peer.connection.cancel()
        }
        peers.removeAll()
        onPacket = nil
        onStatus = nil
    }

    private func accept(_ connection: NWConnection) {
        let peer = Peer(connection: connection)
        let key = ObjectIdentifier(connection)
        peers[key] = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else { return }
            switch state {
            case .ready:
                self.onStatus?("اتصل جهاز مرسل مباشر.")
                self.receive(from: peer)
            case .failed(let error):
                self.onStatus?("انقطع جهاز مرسل: \(error.localizedDescription)")
                self.remove(peer)
            case .cancelled:
                self.remove(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(from peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self, weak peer] data, _, isComplete, error in
            guard let self, let peer else { return }
            if let data, !data.isEmpty {
                for packet in peer.decoder.append(data) {
                    self.onPacket?(packet)
                }
            }
            if let error {
                self.onStatus?("خطأ استقبال: \(error.localizedDescription)")
                self.remove(peer)
                return
            }
            if isComplete {
                self.remove(peer)
                return
            }
            self.receive(from: peer)
        }
    }

    private func remove(_ peer: Peer) {
        peer.connection.cancel()
        peers.removeValue(forKey: ObjectIdentifier(peer.connection))
        onStatus?("تم فصل جهاز مرسل. المتصلون الآن: \(peers.count)")
    }
}
