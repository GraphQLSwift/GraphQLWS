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

extension Messenger {
    /// Send a message through this messenger
    /// - Parameter message: The message to send
    func send(_ message: Data) async throws {
        // TODO: Ideally Data is our native interface, and String is the extension.
        // Since that change is breaking, we will do it on the next major version.
        if let string = String(data: message, encoding: .utf8) {
            try await send(string)
        }
    }
}
