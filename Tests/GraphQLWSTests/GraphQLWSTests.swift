import Foundation

import GraphQL
import XCTest

@testable import GraphQLWS

class GraphqlWsTests: XCTestCase {
    var clientMessenger: TestMessenger!
    var serverMessenger: TestMessenger!
    var server: Server<TokenInitPayload, AsyncThrowingStream<GraphQLResult, Error>>!
    var context: TestContext!
    var subscribeReady: Bool! = false

    override func setUp() {
        // Point the client and server at each other
        clientMessenger = TestMessenger()
        serverMessenger = TestMessenger()
        clientMessenger.other = serverMessenger
        serverMessenger.other = clientMessenger

        let api = TestAPI()
        let context = TestContext()

        server = .init(
            messenger: serverMessenger,
            onExecute: { graphQLRequest in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest in
                let subscription = try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                ).get()
                self.subscribeReady = true
                return subscription
            }
        )
        self.context = context
    }

    /// Tests that trying to run methods before `connection_init` is not allowed
    func testInitialize() async throws {
        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            client.onMessage { message, _ in
                continuation.yield(message)
                // Expect only one message
                continuation.finish()
            }
            client.onError { message, _ in
                continuation.finish(throwing: message.payload[0])
            }
        }

        try await client.sendStart(
            payload: GraphQLRequest(
                query: """
                query {
                    hello
                }
                """
            ),
            id: UUID().uuidString
        )

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        XCTAssertEqual(
            messages,
            ["\(ErrorCode.notInitialized): Connection not initialized"]
        )
    }

    /// Tests that throwing in the authorization callback forces an unauthorized error
    func testAuthWithThrow() async throws {
        server.auth { _ in
            throw TestError.couldBeAnything
        }

        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            client.onMessage { message, _ in
                continuation.yield(message)
                // Expect only one message
                continuation.finish()
            }
            client.onError { message, _ in
                continuation.finish(throwing: message.payload[0])
            }
        }

        try await client.sendConnectionInit(
            payload: TokenInitPayload(
                authToken: ""
            )
        )

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        XCTAssertEqual(
            messages,
            ["\(ErrorCode.unauthorized): Unauthorized"]
        )
    }

    /// Test single op message flow works as expected
    func testSingleOp() async throws {
        let id = UUID().description

        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            client.onConnectionAck { _, client in
                try await client.sendStart(
                    payload: GraphQLRequest(
                        query: """
                        query {
                            hello
                        }
                        """
                    ),
                    id: id
                )
            }
            client.onMessage { message, _ in
                continuation.yield(message)
            }
            client.onError { message, _ in
                continuation.finish(throwing: message.payload[0])
            }
            client.onComplete { _, _ in
                continuation.finish()
            }
        }

        try await client.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        XCTAssertEqual(
            messages.count,
            3, // 1 connection_ack, 1 data, 1 complete
            "Messages: \(messages.description)"
        )
    }

    /// Test streaming message flow works as expected
    func testStreaming() async throws {
        let id = UUID().description

        var dataIndex = 1
        let dataIndexMax = 3

        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            client.onConnectionAck { _, client in
                try await client.sendStart(
                    payload: GraphQLRequest(
                        query: """
                        subscription {
                            hello
                        }
                        """
                    ),
                    id: id
                )

                // Wait until server has registered subscription
                var i = 0
                while !self.subscribeReady, i < 50 {
                    usleep(1000)
                    i = i + 1
                }
                if i == 50 {
                    XCTFail("Subscription timeout: Took longer than 50ms to set up")
                }

                self.context.publisher.emit(event: "hello \(dataIndex)")
            }
            client.onData { _, _ in
                dataIndex = dataIndex + 1
                if dataIndex <= dataIndexMax {
                    self.context.publisher.emit(event: "hello \(dataIndex)")
                } else {
                    self.context.publisher.cancel()
                }
            }
            client.onMessage { message, _ in
                continuation.yield(message)
            }
            client.onError { message, _ in
                continuation.finish(throwing: message.payload[0])
            }
            client.onComplete { _, _ in
                continuation.finish()
            }
        }

        try await client.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        XCTAssertEqual(
            messages.count,
            5, // 1 connection_ack, 3 data, 1 complete
            "Messages: \(messages.description)"
        )
    }

    enum TestError: Error {
        case couldBeAnything
    }
}
