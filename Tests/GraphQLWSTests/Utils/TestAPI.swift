import Foundation
import Graphiti
import GraphQL

struct TestAPI: API {
    let resolver = TestResolver()
    let context = TestContext()

    let schema = try! Schema<TestResolver, TestContext> {
        Query {
            Field("hello", at: TestResolver.hello)
        }
        Subscription {
            SubscriptionField("hello", as: String.self, atSub: TestResolver.subscribeHello)
        }
    }
}

final class TestContext: Sendable {
    let publisher = SimplePubSub<String>()

    func hello() -> String {
        "world"
    }
}

struct TestResolver {
    func hello(context: TestContext, arguments _: NoArguments) -> String {
        context.hello()
    }

    func subscribeHello(context: TestContext, arguments _: NoArguments) -> AsyncThrowingStream<String, Error> {
        context.publisher.subscribe()
    }
}

/// A very simple publish/subscriber used for testing
class SimplePubSub<T: Sendable>: @unchecked Sendable {
    private var subscribers: [Subscriber<T>]

    init() {
        subscribers = []
    }

    func emit(event: T) {
        for subscriber in subscribers {
            subscriber.callback(event)
        }
    }

    func cancel() {
        for subscriber in subscribers {
            subscriber.cancel()
        }
    }

    func subscribe() -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream<T, Error> { continuation in
            let subscriber = Subscriber<T>(
                callback: { newValue in
                    continuation.yield(newValue)
                },
                cancel: {
                    continuation.finish()
                }
            )
            subscribers.append(subscriber)
        }
    }
}

struct Subscriber<T> {
    let callback: (T) -> Void
    let cancel: () -> Void
}
