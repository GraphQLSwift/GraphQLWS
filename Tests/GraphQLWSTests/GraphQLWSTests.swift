import Foundation

import GraphQL
import XCTest

@testable import GraphQLWS

class GraphqlWsTests: XCTestCase {
    func setUp(
        auth: @escaping @Sendable (TokenInitPayload) async throws -> Void = { (_: TokenInitPayload) in }
    ) -> (client: TestMessenger, server: TestMessenger, context: TestContext) {
        // Point the client and server at each other
        let clientMessenger = TestMessenger()
        let serverMessenger = TestMessenger()
        clientMessenger.other = serverMessenger
        serverMessenger.other = clientMessenger

        let api = TestAPI()
        let context = TestContext()
        serverMessenger.registerServer(
            onExecute: { graphQLRequest in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest in
                try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            auth: auth
        )

        return (client: clientMessenger, server: serverMessenger, context: context)
    }

    /// Tests that trying to run methods before `connection_init` is not allowed
    func testInitialize() async throws {
        let (clientMessenger, _, _) = setUp()
        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            clientMessenger.registerClient(
                onError: { message, _ in
                    continuation.finish(throwing: message.payload[0])
                },
                onMessage: { message, _ in
                    continuation.yield(message)
                    // Expect only one message
                    continuation.finish()
                }
            )
        }

        try await clientMessenger.sendStart(
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
        let (clientMessenger, _, _) = setUp { _ in
            throw TestError.couldBeAnything
        }

        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            clientMessenger.registerClient(
                onError: { message, _ in
                    continuation.finish(throwing: message.payload[0])
                },
                onMessage: { message, _ in
                    continuation.yield(message)
                    // Expect only one message
                    continuation.finish()
                }
            )
        }

        try await clientMessenger.sendConnectionInit(
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
        let (clientMessenger, _, _) = setUp()
        let id = UUID().description

        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            clientMessenger.registerClient(
                onConnectionAck: { _, client in
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
                },
                onComplete: { _, _ in
                    continuation.finish()
                },
                onError: { message, _ in
                    continuation.finish(throwing: message.payload[0])
                },
                onMessage: { message, _ in
                    continuation.yield(message)
                }
            )
        }

        try await clientMessenger.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

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
        let (clientMessenger, _, context) = setUp()
        let id = UUID().description

        var dataIndex = 1
        let dataIndexMax = 3

        let messageStream = AsyncThrowingStream<String, any Error> { continuation in
            clientMessenger.registerClient(
                onConnectionAck: { _, client in
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

                    // Short sleep to allow for server to register subscription
                    usleep(3000)

                    context.publisher.emit(event: "hello \(dataIndex)")
                },
                onData: { _, _ in
                    dataIndex = dataIndex + 1
                    if dataIndex <= dataIndexMax {
                        context.publisher.emit(event: "hello \(dataIndex)")
                    } else {
                        context.publisher.cancel()
                    }
                },
                onComplete: { _, _ in
                    continuation.finish()
                },
                onError: { message, _ in
                    continuation.finish(throwing: message.payload[0])
                },
                onMessage: { message, _ in
                    continuation.yield(message)
                }
            )
        }

        try await clientMessenger.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

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
