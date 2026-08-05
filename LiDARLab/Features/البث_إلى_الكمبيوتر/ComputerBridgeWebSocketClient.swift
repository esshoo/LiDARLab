import Foundation

actor ComputerBridgeWebSocketClient {
    enum ClientError: LocalizedError {
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "لا يوجد اتصال نشط بالكمبيوتر."
            }
        }
    }

    private var task: URLSessionWebSocketTask?

    func connect(to url: URL) {
        disconnect()
        let newTask = URLSession.shared.webSocketTask(with: url)
        task = newTask
        newTask.resume()
    }

    func send(_ data: Data) async throws {
        guard let task else { throw ClientError.notConnected }
        try await task.send(.data(data))
    }

    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let task else { throw ClientError.notConnected }
        return try await task.receive()
    }

    func sendPing() async throws {
        guard let task else { throw ClientError.notConnected }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
