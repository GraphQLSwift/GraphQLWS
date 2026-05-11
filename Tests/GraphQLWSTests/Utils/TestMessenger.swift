import Foundation

@testable import GraphQLWS

/// Messenger for simple testing that doesn't require starting up a websocket server.
actor TestMessenger: Messenger {
    /// An async stream of the messages sent through this messenger.
    let stream: AsyncThrowingStream<Data, Error>
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func send<S: Sendable & Collection>(_ message: S) async throws where S.Element == Character {
        if let data = String(message).data(using: .utf8) {
            continuation.yield(data)
        }
    }

    func error(_ message: String, code: Int) async throws {
        continuation.finish(throwing: TestMessengerError(code: code, message: message))
        continuation.finish()
    }

    func close() {
        continuation.finish()
    }
}

struct TestMessengerError: Error, Equatable {
    let code: Int
    let message: String
}
