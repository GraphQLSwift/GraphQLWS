import Foundation

/// Protocol for an object that can send and recieve messages. This allows mocking in tests
public protocol Messenger: AnyObject & Sendable {
    // AnyObject compliance requires that the implementing object is a class and we can reference it weakly

    /// Send a message through this messenger
    /// - Parameter message: The message to send
    func send<S>(_ message: S) async throws -> Void where S: Collection, S.Element == Character

    /// Set the callback that should be run when a message is recieved
    func onReceive(callback: @escaping (String) async throws -> Void)

    /// Close the messenger
    func close() async throws

    /// Indicate that the messenger experienced an error.
    /// - Parameters:
    ///   - message: The message describing the error
    ///   - code: An error code
    func error(_ message: String, code: Int) async throws
}

extension Messenger {
    /// Send an error through the messenger and close the connection
    func error(_ error: GraphQLWSError) async throws {
        try await self.error(error.message, code: error.code.rawValue)
    }
}
