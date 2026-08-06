import Foundation

struct StableNetworkQueueSnapshot: Sendable {
    let queuedPackets: Int
    let queuedBytes: UInt64
    let sentPackets: UInt64
    let sentBytes: UInt64
    let socketOpen: Bool
    let receiverReady: Bool
    let lastAcknowledgedFrameID: UInt64
    let acknowledgedPosePackets: UInt64
    let acknowledgedScanPackets: UInt64
    let protocolErrors: UInt64
}

final class StableNetworkSender: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.essam.3elidar.stable-network", qos: .utility)
    private var task: URLSessionWebSocketTask?
    private var packets: [Data] = []
    private var headIndex = 0
    private var queuedBytes: UInt64 = 0
    private var sentPackets: UInt64 = 0
    private var sentBytes: UInt64 = 0
    private var isSending = false
    private var socketOpen = false
    private var receiverReady = false
    private var lastAcknowledgedFrameID: UInt64 = 0
    private var acknowledgedPosePackets: UInt64 = 0
    private var acknowledgedScanPackets: UInt64 = 0
    private var protocolErrors: UInt64 = 0

    var onState: (@Sendable (Bool, String) -> Void)?
    var onReceiverReady: (@Sendable (Bool, String) -> Void)?
    var onAcknowledgement: (@Sendable (UInt64, String) -> Void)?
    var onStatistics: (@Sendable (StableNetworkQueueSnapshot) -> Void)?

    /// Starts a clean transport epoch. This never touches the local session file.
    func prepareForNewSession() {
        queue.sync {
            packets.removeAll(keepingCapacity: true)
            headIndex = 0
            queuedBytes = 0
            sentPackets = 0
            sentBytes = 0
            lastAcknowledgedFrameID = 0
            acknowledgedPosePackets = 0
            acknowledgedScanPackets = 0
            protocolErrors = 0
            receiverReady = false
            publishStatistics()
        }
    }

    func connect(to url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.task?.cancel(with: .goingAway, reason: nil)
            let newTask = URLSession.shared.webSocketTask(with: url)
            self.task = newTask
            self.socketOpen = true
            self.receiverReady = false
            newTask.resume()
            self.onState?(true, "تم بدء قناة WebSocket. ننتظر تأكيد البروتوكول من Windows.")
            self.onReceiverReady?(false, "لم يصل hello_ack بعد")
            self.publishStatistics()
            self.receiveNext()
            self.sendNextIfNeeded()
        }
    }

    /// Adds a packet without blocking ARKit. There is no silent queue truncation.
    func enqueue(_ packet: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.packets.append(packet)
            self.queuedBytes &+= UInt64(packet.count)
            self.publishStatistics()
            self.sendNextIfNeeded()
        }
    }

    func disconnect(keepPendingPackets: Bool = true) {
        queue.async { [weak self] in
            guard let self else { return }
            self.socketOpen = false
            self.receiverReady = false
            self.isSending = false
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            if !keepPendingPackets {
                self.packets.removeAll(keepingCapacity: false)
                self.headIndex = 0
                self.queuedBytes = 0
            }
            self.onState?(false, keepPendingPackets
                ? "تم قطع الاتصال. الحزم غير المرسلة ما زالت في قائمة الانتظار."
                : "تم قطع الاتصال ومسح قائمة الشبكة فقط؛ ملف الجلسة المحلي لم يتغير.")
            self.onReceiverReady?(false, "المستقبل غير مؤكد")
            self.publishStatistics()
        }
    }

    func resetStatisticsWhenIdle() {
        queue.async { [weak self] in
            guard let self, self.pendingCount == 0 else { return }
            self.sentPackets = 0
            self.sentBytes = 0
            self.publishStatistics()
        }
    }

    func snapshot() -> StableNetworkQueueSnapshot {
        queue.sync { makeSnapshot() }
    }

    private var pendingCount: Int { max(0, packets.count - headIndex) }

    private func sendNextIfNeeded() {
        guard socketOpen, !isSending, let task, headIndex < packets.count else { return }
        isSending = true
        let packet = packets[headIndex]
        task.send(.data(packet)) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                if let error {
                    self.socketOpen = false
                    self.receiverReady = false
                    self.onState?(false, "توقف إرسال الشبكة: \(error.localizedDescription). التسجيل المحلي مستمر.")
                    self.onReceiverReady?(false, "لم يؤكد Windows الاستلام")
                    self.publishStatistics()
                    return
                }

                self.headIndex += 1
                self.queuedBytes = self.queuedBytes >= UInt64(packet.count)
                    ? self.queuedBytes - UInt64(packet.count)
                    : 0
                self.sentPackets &+= 1
                self.sentBytes &+= UInt64(packet.count)

                if self.headIndex > 512, self.headIndex * 2 > self.packets.count {
                    self.packets.removeFirst(self.headIndex)
                    self.headIndex = 0
                }
                self.publishStatistics()
                self.sendNextIfNeeded()
            }
        }
    }

    private func receiveNext() {
        guard socketOpen, let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success(let message):
                    self.handleIncoming(message)
                    self.receiveNext()
                case .failure(let error):
                    self.socketOpen = false
                    self.receiverReady = false
                    self.isSending = false
                    self.onState?(false, "انقطع رد المستقبل: \(error.localizedDescription). التسجيل المحلي مستمر.")
                    self.onReceiverReady?(false, "المستقبل لم يعد متاحًا")
                    self.publishStatistics()
                }
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let value):
            data = value
        @unknown default:
            return
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "hello_ack":
            receiverReady = true
            let version = object["protocol_version"] ?? 1
            onReceiverReady?(true, "Windows أكد بروتوكول 3ELD v\(version)")
        case "session_control_ack":
            if let action = object["action"] as? String, action == "start" {
                receiverReady = true
                onReceiverReady?(true, "Windows فتح الجلسة ويستقبل البيانات")
            }
        case "localization_result":
            let frame = Self.uint64Value(object["frame_id"])
            let status = object["status"] as? String ?? "recorded"
            lastAcknowledgedFrameID = max(lastAcknowledgedFrameID, frame)
            if status == "pose_recorded" { acknowledgedPosePackets &+= 1 }
            if status == "scan2d_recorded" { acknowledgedScanPackets &+= 1 }
            receiverReady = true
            onAcknowledgement?(frame, status)
        case "protocol_error":
            protocolErrors &+= 1
            let message = object["message"] as? String ?? "Protocol error"
            onReceiverReady?(false, "خطأ بروتوكول من Windows: \(message)")
        default:
            break
        }
        publishStatistics()
    }

    private func publishStatistics() {
        onStatistics?(makeSnapshot())
    }

    private func makeSnapshot() -> StableNetworkQueueSnapshot {
        StableNetworkQueueSnapshot(
            queuedPackets: pendingCount,
            queuedBytes: queuedBytes,
            sentPackets: sentPackets,
            sentBytes: sentBytes,
            socketOpen: socketOpen,
            receiverReady: receiverReady,
            lastAcknowledgedFrameID: lastAcknowledgedFrameID,
            acknowledgedPosePackets: acknowledgedPosePackets,
            acknowledgedScanPackets: acknowledgedScanPackets,
            protocolErrors: protocolErrors
        )
    }

    private static func uint64Value(_ value: Any?) -> UInt64 {
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String, let number = UInt64(text) { return number }
        return 0
    }
}
