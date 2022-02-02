// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import NIO

/// Protocol for an object that can send and recieve messages
protocol Messenger {
    func send<S>(_ message: S) -> Void where S: Collection, S.Element == Character
    func onRecieve(callback: @escaping (String) -> Void) -> Void
    func close() -> Void
    func error(_ message: String, code: Int) -> Void
}
