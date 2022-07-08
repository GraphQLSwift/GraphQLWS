// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import NIO

/// Protocol for an object that can send and recieve messages. This allows mocking in tests
public protocol Messenger: AnyObject {
    // AnyObject compliance requires that the implementing object is a class and we can reference it weakly
    
    /// Send a message through this messenger
    /// - Parameter message: The message to send
    func send<S>(_ message: S) -> Void where S: Collection, S.Element == Character
    
    /// Set the callback that should be run when a message is recieved
    func onReceive(callback: @escaping (String) -> Void) -> Void
    
    /// Close the messenger
    func close() -> Void
    
    /// Indicate that the messenger experienced an error.
    /// - Parameters:
    ///   - message: The message describing the error
    ///   - code: An error code
    func error(_ message: String, code: Int) -> Void
}
