import Foundation
import GraphQL

/// Client is an open-ended implementation of the client side of the protocol. It parses and adds callbacks for each type of server respose.
public actor Client<InitPayload: Equatable & Codable> {
    /// We keep this weak because we strongly inject this object into the messenger callback
    let messenger: Messenger

    let onConnectionError: (ConnectionErrorResponse, Client) async throws -> Void
    let onConnectionAck: (ConnectionAckResponse, Client) async throws -> Void
    let onConnectionKeepAlive: (ConnectionKeepAliveResponse, Client) async throws -> Void
    let onData: (DataResponse, Client) async throws -> Void
    let onError: (ErrorResponse, Client) async throws -> Void
    let onComplete: (CompleteResponse, Client) async throws -> Void
    let onMessage: (String, Client) async throws -> Void

    let encoder = GraphQLJSONEncoder()
    let decoder = JSONDecoder()

    /// Create a new client.
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the client to.
    ///   - onConnectionError: The callback run on receipt of a `connection_error` message
    ///   - onConnectionAck: The callback run on receipt of a `connection_ack` message
    ///   - onConnectionKeepAlive: The callback run on receipt of a `connection_ka` message
    ///   - onData: The callback run on receipt of a `data` message
    ///   - onError: The callback run on receipt of an `error` message
    ///   - onComplete: The callback run on receipt of a `complete` message
    ///   - onMessage: The callback run on receipt of any message
    public init(
        messenger: Messenger,
        onConnectionError: @escaping (ConnectionErrorResponse, Client) async throws -> Void = { _, _ in },
        onConnectionAck: @escaping (ConnectionAckResponse, Client) async throws -> Void = { _, _ in },
        onConnectionKeepAlive: @escaping (ConnectionKeepAliveResponse, Client) async throws -> Void = { _, _ in },
        onData: @escaping (DataResponse, Client) async throws -> Void = { _, _ in },
        onError: @escaping (ErrorResponse, Client) async throws -> Void = { _, _ in },
        onComplete: @escaping (CompleteResponse, Client) async throws -> Void = { _, _ in },
        onMessage: @escaping (String, Client) async throws -> Void = { _, _ in }
    ) {
        self.messenger = messenger
        self.onConnectionError = onConnectionError
        self.onConnectionAck = onConnectionAck
        self.onConnectionKeepAlive = onConnectionKeepAlive
        self.onData = onData
        self.onError = onError
        self.onComplete = onComplete
        self.onMessage = onMessage
    }

    /// Listen and react to the provided async sequence of server messages. This function will block until the stream is completed.
    /// - Parameter incoming: The server message sequence that the client should react to.
    public func listen<A: AsyncSequence & Sendable>(to incoming: A) async throws -> Void where A.Element == String {
        for try await message in incoming {
            try await onMessage(message, self)

            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }

            guard let json = message.data(using: .utf8) else {
                try await error(.invalidEncoding())
                return
            }

            let response: Response
            do {
                response = try decoder.decode(Response.self, from: json)
            } catch {
                try await self.error(.noType())
                return
            }

            switch response.type {
            case .GQL_CONNECTION_ERROR:
                guard let connectionErrorResponse = try? decoder.decode(ConnectionErrorResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                    return
                }
                try await onConnectionError(connectionErrorResponse, self)
            case .GQL_CONNECTION_ACK:
                guard let connectionAckResponse = try? decoder.decode(ConnectionAckResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                    return
                }
                try await onConnectionAck(connectionAckResponse, self)
            case .GQL_CONNECTION_KEEP_ALIVE:
                guard let connectionKeepAliveResponse = try? decoder.decode(ConnectionKeepAliveResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_CONNECTION_KEEP_ALIVE))
                    return
                }
                try await onConnectionKeepAlive(connectionKeepAliveResponse, self)
            case .GQL_DATA:
                guard let nextResponse = try? decoder.decode(DataResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_DATA))
                    return
                }
                try await onData(nextResponse, self)
            case .GQL_ERROR:
                guard let errorResponse = try? decoder.decode(ErrorResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_ERROR))
                    return
                }
                try await onError(errorResponse, self)
            case .GQL_COMPLETE:
                guard let completeResponse = try? decoder.decode(CompleteResponse.self, from: json) else {
                    try await error(.invalidResponseFormat(messageType: .GQL_COMPLETE))
                    return
                }
                try await onComplete(completeResponse, self)
            default:
                try await error(.invalidType())
            }
        }
    }

    /// Send a `connection_init` request through the messenger
    public func sendConnectionInit(payload: InitPayload) async throws {
        try await messenger.send(
            ConnectionInitRequest(
                payload: payload
            ).toJSON(encoder)
        )
    }

    /// Send a `start` request through the messenger
    public func sendStart(payload: GraphQLRequest, id: String) async throws {
        try await messenger.send(
            StartRequest(
                payload: payload,
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `stop` request through the messenger
    public func sendStop(id: String) async throws {
        try await messenger.send(
            StopRequest(
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `connection_terminate` request through the messenger
    public func sendConnectionTerminate() async throws {
        try await messenger.send(
            ConnectionTerminateRequest().toJSON(encoder)
        )
    }

    /// Send an error through the messenger and close the connection
    private func error(_ error: GraphQLWSError) async throws {
        try await messenger.error(error.message, code: error.code.rawValue)
    }
}
