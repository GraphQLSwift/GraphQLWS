// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import NIO

/// Protocol for an object that can send and recieve messages
public protocol Messenger: AnyObject {
    // AnyObject compliance requires that the implementing object is a class and we can reference it weakly
    func send<S>(_ message: S) -> Void where S: Collection, S.Element == Character
    func send<S>(_ message: S) async throws -> Void where S: Collection, S.Element == Character
    func onRecieve(callback: @escaping (String) -> Void) -> Void
    func onClose(callback: @escaping () -> Void) -> Void
    func close() -> Void
    func error(_ message: String, code: Int) -> Void
}
