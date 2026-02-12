import Foundation

import GraphQL
import XCTest

import GraphQLWS

class GraphqlWsTests: XCTestCase {
    var clientMessenger: TestMessenger!
    var serverMessenger: TestMessenger!
    var subscribeReady: Bool! = false

    let context = TestContext()
    let api = TestAPI()

    override func setUp() {
        clientMessenger = TestMessenger()
        serverMessenger = TestMessenger()
    }

    /// Tests that trying to run methods before `connection_init` is not allowed
    func testInitialize() async throws {
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await self.api.execute(
                    request: graphQLRequest.query,
                    context: self.context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await self.api.subscribe(
                    request: graphQLRequest.query,
                    context: self.context
                ).get()
                self.subscribeReady = true
                return subscription
            }
        )
        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }
        
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
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in
                throw TestError.couldBeAnything
            },
            onExecute: { graphQLRequest, _ in
                try await self.api.execute(
                    request: graphQLRequest.query,
                    context: self.context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await self.api.subscribe(
                    request: graphQLRequest.query,
                    context: self.context
                ).get()
                self.subscribeReady = true
                return subscription
            }
        )
        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }
        
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
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await self.api.execute(
                    request: graphQLRequest.query,
                    context: self.context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await self.api.subscribe(
                    request: graphQLRequest.query,
                    context: self.context
                ).get()
                self.subscribeReady = true
                return subscription
            }
        )
        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }
        
        let id = UUID().description
        
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
        let server = Server<TokenInitPayload, Void, AsyncThrowingStream<GraphQLResult, Error>>(
            messenger: serverMessenger,
            onInit: { _ in },
            onExecute: { graphQLRequest, _ in
                try await self.api.execute(
                    request: graphQLRequest.query,
                    context: self.context
                )
            },
            onSubscribe: { graphQLRequest, _ in
                let subscription = try await self.api.subscribe(
                    request: graphQLRequest.query,
                    context: self.context
                ).get()
                self.subscribeReady = true
                return subscription
            }
        )
        let client = Client<TokenInitPayload>(messenger: clientMessenger)
        let serverStream = serverMessenger.stream
        let clientStream = clientMessenger.stream
        Task {
            try await server.listen(to: clientStream)
        }
        Task {
            try await client.listen(to: serverStream)
        }

        let id = UUID().description

        var dataIndex = 1
        let dataIndexMax = 3

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
