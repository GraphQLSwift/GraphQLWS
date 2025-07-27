
import Foundation

@testable import GraphQLWS

/// Messenger for simple testing that doesn't require starting up a websocket server.
///
/// Note that this only retains a weak reference to 'other', so the client should retain references
/// or risk them being deinitialized early
class TestMessenger: Messenger {
    weak var other: TestMessenger?
    var onReceive: (String) async throws -> Void = { _ in }
    let queue: DispatchQueue = .init(label: "Test messenger")

    init() {}

    func send<S>(_ message: S) async throws where S: Collection, S.Element == Character {
        guard let other = other else {
            return
        }
        try await other.onReceive(String(message))
    }

    func onReceive(callback: @escaping (String) async throws -> Void) {
        onReceive = callback
    }

    func error(_ message: String, code: Int) async throws {
        try await send("\(code): \(message)")
    }

    func close() {
        // This is a testing no-op
    }
}
