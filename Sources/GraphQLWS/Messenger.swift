import Foundation

/// Protocol for an object that can send messages.
public protocol Messenger: Sendable {
    /// Send a message through this messenger
    /// - Parameter message: The message to send
    func send<S: Sendable & Collection>(_ message: S) async throws where S.Element == Character

    /// Close the messenger
    func close() async throws

    /// Indicate that the messenger experienced an error.
    /// - Parameters:
    ///   - message: The message describing the error
    ///   - code: An error code
    func error(_ message: String, code: Int) async throws
}
