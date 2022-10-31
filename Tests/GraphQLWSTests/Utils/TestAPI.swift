import Foundation
import GraphQL
import Graphiti
import GraphQLRxSwift
import RxSwift

let pubsub = PublishSubject<String>()

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

final class TestContext {
    func hello() -> String {
        "world"
    }
}

struct TestResolver {
    func hello(context: TestContext, arguments _: NoArguments) -> String {
        context.hello()
    }
    
    func subscribeHello(context: TestContext, arguments: NoArguments) -> EventStream<String> {
        pubsub.toEventStream()
    }
}
