import Foundation
import GraphQL

public extension Messenger {
    /// Register protocol client responses to the messenger.
    ///
    /// - Parameters:
    ///   - onConnectionAck: Callback run when a connection acknowledgment is received.
    ///   - onConnectionKeepAlive: Callback run when a connection keep-alive message is received.
    ///   - onConnectionError: Callback run when a connection error is received.
    ///   - onData: Callback run when data is received.
    ///   - onComplete: Callback run when a complete message is received.
    ///   - onError: Callback run when an error message is received.
    ///   - onMessage: Callback run on receipt of any message. Typically used for logging/debugging.
    func registerClient(
        onConnectionAck: @escaping (ConnectionAckResponse, Self) async throws -> Void = { _, _ in },
        onConnectionKeepAlive: @escaping (ConnectionKeepAliveResponse, Self) async throws -> Void = { _, _ in },
        onConnectionError: @escaping (ConnectionErrorResponse, Self) async throws -> Void = { _, _ in },
        onData: @escaping (DataResponse, Self) async throws -> Void = { _, _ in },
        onComplete: @escaping (CompleteResponse, Self) async throws -> Void = { _, _ in },
        onError: @escaping (ErrorResponse, Self) async throws -> Void = { _, _ in },
        onMessage: @escaping (String, Self) async throws -> Void = { _, _ in }
    ) {
        onReceive { message in
            try await onMessage(message, self)

            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }

            guard let json = message.data(using: .utf8) else {
                try await self.error(.invalidEncoding())
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
                    try await self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                    return
                }
                try await onConnectionError(connectionErrorResponse, self)
            case .GQL_CONNECTION_ACK:
                guard let connectionAckResponse = try? decoder.decode(ConnectionAckResponse.self, from: json) else {
                    try await self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                    return
                }
                try await onConnectionAck(connectionAckResponse, self)
            case .GQL_CONNECTION_KEEP_ALIVE:
                guard let connectionKeepAliveResponse = try? decoder.decode(ConnectionKeepAliveResponse.self, from: json) else {
                    try await self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_KEEP_ALIVE))
                    return
                }
                try await onConnectionKeepAlive(connectionKeepAliveResponse, self)
            case .GQL_DATA:
                guard let nextResponse = try? decoder.decode(DataResponse.self, from: json) else {
                    try await self.error(.invalidResponseFormat(messageType: .GQL_DATA))
                    return
                }
                try await onData(nextResponse, self)
            case .GQL_ERROR:
                guard let errorResponse = try? decoder.decode(ErrorResponse.self, from: json) else {
                    try await self.error(.invalidResponseFormat(messageType: .GQL_ERROR))
                    return
                }
                try await onError(errorResponse, self)
            case .GQL_COMPLETE:
                guard let completeResponse = try? decoder.decode(CompleteResponse.self, from: json) else {
                    try await self.error(.invalidResponseFormat(messageType: .GQL_COMPLETE))
                    return
                }
                try await onComplete(completeResponse, self)
            case .unknown:
                try await self.error(.invalidType())
            }
        }
    }

    /// Send a `connection_init` request through the messenger
    func sendConnectionInit<InitPayload: Codable>(payload: InitPayload) async throws {
        try await send(
            ConnectionInitRequest(
                payload: payload
            ).toJSON(encoder)
        )
    }

    /// Send a `start` request through the messenger
    func sendStart(payload: GraphQLRequest, id: String) async throws {
        try await send(
            StartRequest(
                payload: payload,
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `stop` request through the messenger
    func sendStop(id: String) async throws {
        try await send(
            StopRequest(
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `connection_terminate` request through the messenger
    func sendConnectionTerminate() async throws {
        try await send(
            ConnectionTerminateRequest().toJSON(encoder)
        )
    }
}

private let encoder = GraphQLJSONEncoder()
private let decoder = JSONDecoder()
