
import Foundation

@testable import GraphQLWS

/// Messenger for simple testing that doesn't require starting up a websocket server.
///
/// Note that this only retains a weak reference to 'other', so the client should retain references
/// or risk them being deinitialized early
class TestMessenger: Messenger {
    weak var other: TestMessenger?
    var onRecieve: (String) -> Void = { _ in }
    var onClose: () -> Void = { }
    let queue: DispatchQueue = .init(label: "Test messenger")
    
    init() {}
    
    func send<S>(_ message: S) where S: Collection, S.Element == Character {
        guard let other = other else {
            return
        }
        
        // Run the other message asyncronously to avoid nesting issues
        queue.async {
            other.onRecieve(String(message))
        }
    }
    
    func onRecieve(callback: @escaping (String) -> Void) {
        self.onRecieve = callback
    }
    
    func onClose(callback: @escaping () -> Void) {
        self.onClose = callback
    }
    
    func error(_ message: String, code: Int) {
        self.send("\(code): \(message)")
    }
    
    func close() {
        // This is a testing no-op
        self.onClose()
    }
}
