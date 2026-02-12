import Foundation

import GraphQL
import Testing

import GraphQLWS

@Suite
struct GraphqlTransportWSTests {
    let clientMessenger = TestMessenger()
    let serverMessenger = TestMessenger()

    /// Tests that trying to run methods before `connection_init` is not allowed
    @Test func initialize() async throws {
        let api = TestAPI()
        let context = TestContext()
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                ).get()
                return subscription
            }
        )
        let (messageStream, messageContinuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let client = Client<TokenInitPayload>(
            messenger: clientMessenger,
            onError: { message, _ in
                messageContinuation.finish(throwing: message.payload[0])
            },
            onMessage: { message, _ in
                messageContinuation.yield(message)
                // Expect only one message
                messageContinuation.finish()
            }
        )
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
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
        #expect(
            messages ==
            ["\(ErrorCode.notInitialized): Connection not initialized"]
        )
    }

    /// Tests that throwing in the authorization callback forces an unauthorized error
    @Test func authWithThrow() async throws {
        let api = TestAPI()
        let context = TestContext()
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in
                throw TestError.couldBeAnything
            },
            onExecute: { graphQLRequest, _ in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                ).get()
                return subscription
            }
        )
        let (messageStream, messageContinuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let client = Client<TokenInitPayload>(
            messenger: clientMessenger,
            onError: { message, _ in
                messageContinuation.finish(throwing: message.payload[0])
            },
            onMessage: { message, _ in
                messageContinuation.yield(message)
                // Expect only one message
                messageContinuation.finish()
            }
        )
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }

        try await client.sendConnectionInit(
            payload: TokenInitPayload(
                authToken: ""
            )
        )

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        #expect(
            messages ==
            ["\(ErrorCode.unauthorized): Unauthorized"]
        )
    }

    /// Test single op message flow works as expected
    @Test func singleOp() async throws {
        let api = TestAPI()
        let context = TestContext()
        let id = UUID().description

        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                ).get()
                return subscription
            }
        )
        let (messageStream, messageContinuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let client = Client<TokenInitPayload>(
            messenger: clientMessenger,
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
            onError: { message, _ in
                messageContinuation.finish(throwing: message.payload[0])
            },
            onComplete: { _, _ in
                messageContinuation.finish()
            },
            onMessage: { message, _ in
                messageContinuation.yield(message)
            }
        )
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }

        try await client.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        #expect(
            messages.count == 3, // 1 connection_ack, 1 data, 1 complete
            "Messages: \(messages.description)"
        )
    }

    /// Test streaming message flow works as expected
    @Test func streaming() async throws {
        let api = TestAPI()
        let context = TestContext()
        let id = UUID().description
        var dataIndex = 1
        let dataIndexMax = 3
        
        let (subscribeReadyStream, subscribeReadyContinuation) = AsyncStream<Void>.makeStream()
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context
                ).get()
                subscribeReadyContinuation.finish()
                return subscription
            }
        )
        let (messageStream, messageContinuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let client = Client<TokenInitPayload>(
            messenger: clientMessenger,
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

                // Wait until server has registered subscription
                for await _ in subscribeReadyStream {}
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
            onError: { message, _ in
                messageContinuation.finish(throwing: message.payload[0])
            },
            onComplete: { _, _ in
                messageContinuation.finish()
            },
            onMessage: { message, _ in
                messageContinuation.yield(message)
            }
        )
        let clientStream = clientMessenger.stream
        let serverStream = serverMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }

        try await client.sendConnectionInit(payload: TokenInitPayload(authToken: ""))

        let messages = try await messageStream.reduce(into: [String]()) { result, message in
            result.append(message)
        }
        #expect(
            messages.count == 5, // 1 connection_ack, 3 next, 1 complete
            "Messages: \(messages.description)"
        )
    }

    enum TestError: Error {
        case couldBeAnything
    }
}
