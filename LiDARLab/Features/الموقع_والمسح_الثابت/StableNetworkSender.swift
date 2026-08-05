import Foundation

struct StableNetworkQueueSnapshot: Sendable {
    let queuedPackets: Int
    let queuedBytes: UInt64
    let sentPackets: UInt64
    let sentBytes: UInt64
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
    private var connected = false

    var onState: (@Sendable (Bool, String) -> Void)?
    var onStatistics: (@Sendable (StableNetworkQueueSnapshot) -> Void)?

    func connect(to url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            self.task?.cancel(with: .goingAway, reason: nil)
            let newTask = URLSession.shared.webSocketTask(with: url)
            self.task = newTask
            self.connected = true
            newTask.resume()
            self.onState?(true, "تم فتح قناة الإرسال. البيانات المحلية مستقلة عنها.")
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
            self.connected = false
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
        queue.sync {
            StableNetworkQueueSnapshot(
                queuedPackets: pendingCount,
                queuedBytes: queuedBytes,
                sentPackets: sentPackets,
                sentBytes: sentBytes
            )
        }
    }

    private var pendingCount: Int { max(0, packets.count - headIndex) }

    private func sendNextIfNeeded() {
        guard connected, !isSending, let task, headIndex < packets.count else { return }
        isSending = true
        let packet = packets[headIndex]
        task.send(.data(packet)) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                if let error {
                    self.connected = false
                    self.onState?(false, "توقف إرسال الشبكة: \(error.localizedDescription). التسجيل المحلي مستمر.")
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
        guard connected, let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success:
                    self.receiveNext()
                case .failure(let error):
                    self.connected = false
                    self.isSending = false
                    self.onState?(false, "انقطع رد المستقبل: \(error.localizedDescription). التسجيل المحلي مستمر.")
                }
            }
        }
    }

    private func publishStatistics() {
        onStatistics?(StableNetworkQueueSnapshot(
            queuedPackets: pendingCount,
            queuedBytes: queuedBytes,
            sentPackets: sentPackets,
            sentBytes: sentBytes
        ))
    }
}
