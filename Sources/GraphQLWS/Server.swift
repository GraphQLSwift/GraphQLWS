import Foundation
import GraphQL

public extension Messenger {
    /// Register protocol server responses to the messenger.
    ///
    /// - Parameters:
    ///   - onExecute: Callback run during `start` resolution for non-streaming queries. Typically this is `API.execute`.
    ///   - onSubscribe: Callback run during `start` resolution for streaming queries. Typically this is `API.subscribe`.
    ///   - auth: Callback run during `connection_init` resolution that allows authorization using the `payload`.
    ///     Throw from this closure to indicate that authorization has failed.
    ///   - onExit: Callback run when the communication is shut down, either by the client or server.
    ///   - onOperationComplete: Callback run on the completion a full operation (query/mutation, end of subscription).
    ///   - onOperationError: Callback to run on error of any full operation (failed query, interrupted subscription).
    ///   - onMessage: Callback run on receipt of any message. Typically used for logging/debugging.
    func registerServer<InitPayload: Equatable & Codable>(
        onExecute: @escaping @Sendable (GraphQLRequest) async throws -> GraphQLResult,
        onSubscribe: @escaping @Sendable (GraphQLRequest) async throws -> Result<AsyncThrowingStream<GraphQLResult, Error>, GraphQLErrors>,
        auth: @escaping @Sendable (InitPayload) async throws -> Void = { (_: BlankInitPayload) in },
        onExit: @escaping @Sendable () async throws -> Void = {},
        onOperationComplete: @escaping @Sendable (String) async throws -> Void = { _ in },
        onOperationError: @escaping @Sendable (String, [Error]) async throws -> Void = { _, _ in },
        onMessage: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        var initialized = false
        var subscriptionTasks = [String: Task<Void, any Error>]()

        onReceive { message in
            try await onMessage(message)

            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }

            guard let json = message.data(using: .utf8) else {
                try await self.error(.invalidEncoding())
                return
            }

            let request: Request
            do {
                request = try decoder.decode(Request.self, from: json)
            } catch {
                try await self.error(.noType())
                return
            }

            // handle incoming message
            switch request.type {
            case .GQL_CONNECTION_INIT:
                guard let connectionInitRequest = try? decoder.decode(ConnectionInitRequest<InitPayload>.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_INIT))
                    return
                }
                guard !initialized else {
                    try await self.error(.tooManyInitializations())
                    return
                }

                do {
                    try await auth(connectionInitRequest.payload)
                } catch {
                    try await self.error(.unauthorized())
                    return
                }
                initialized = true
                try await self.sendConnectionAck()
            // TODO: Should we send the `ka` message?
            case .GQL_START:
                guard let startRequest = try? decoder.decode(StartRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_START))
                    return
                }
                guard initialized else {
                    try await self.error(.notInitialized())
                    return
                }

                let id = startRequest.id
                if subscriptionTasks[id] != nil {
                    try await self.error(.subscriberAlreadyExists(id: id))
                }

                let graphQLRequest = startRequest.payload

                var isStreaming = false
                do {
                    isStreaming = try graphQLRequest.isSubscription()
                } catch {
                    try await self.sendError(error, id: id)
                    try await onOperationError(id, [error])
                    return
                }

                if isStreaming {
                    do {
                        let result = try await onSubscribe(graphQLRequest)
                        let stream: AsyncThrowingStream<GraphQLResult, Error>
                        do {
                            stream = try result.get()
                        } catch {
                            try await self.sendError(error, id: id)
                            try await onOperationError(id, [error])
                            return
                        }
                        subscriptionTasks[id] = Task {
                            for try await event in stream {
                                try Task.checkCancellation()
                                do {
                                    try await self.sendData(event, id: id)
                                } catch {
                                    try await self.sendError(error, id: id)
                                    try await onOperationError(id, [error])
                                    throw error
                                }
                            }
                            try await self.sendComplete(id: id)
                            try await onOperationComplete(id)
                        }
                    } catch {
                        try await self.sendError(error, id: id)
                        try await onOperationError(id, [error])
                    }
                } else {
                    do {
                        let result = try await onExecute(graphQLRequest)
                        try await self.sendData(result, id: id)
                        try await self.sendComplete(id: id)
                        try await onOperationComplete(id)
                    } catch {
                        try await self.sendError(error, id: id)
                        try await onOperationError(id, [error])
                    }
                    try await self.close()
                }
            case .GQL_STOP:
                guard let stopRequest = try? decoder.decode(StopRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_STOP))
                    return
                }
                guard initialized else {
                    try await self.error(.notInitialized())
                    return
                }

                let id = stopRequest.id
                if let task = subscriptionTasks[id] {
                    task.cancel()
                    subscriptionTasks.removeValue(forKey: id)
                }
                try await onOperationComplete(id)
            case .GQL_CONNECTION_TERMINATE:
                guard let _ = try? decoder.decode(ConnectionTerminateRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_TERMINATE))
                    return
                }
                for (_, subscriptionTask) in subscriptionTasks {
                    subscriptionTask.cancel()
                }
                subscriptionTasks.removeAll()
                try await self.close()
                try await onExit()
            case .unknown:
                try await self.error(.invalidType())
            }
        }
    }

    /// Send a `connection_ack` response through the messenger
    func sendConnectionAck(_ payload: [String: Map]? = nil) async throws {
        try await send(
            ConnectionAckResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `connection_error` response through the messenger
    func sendConnectionError(_ payload: [String: Map]? = nil) async throws {
        try await send(
            ConnectionErrorResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `ka` response through the messenger
    func sendConnectionKeepAlive(_ payload: [String: Map]? = nil) async throws {
        try await send(
            ConnectionKeepAliveResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `data` response through the messenger
    func sendData(_ payload: GraphQLResult? = nil, id: String) async throws {
        try await send(
            DataResponse(
                payload,
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `complete` response through the messenger
    func sendComplete(id: String) async throws {
        try await send(
            CompleteResponse(
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send an `error` response through the messenger
    func sendError(_ errors: [Error], id: String) async throws {
        try await send(
            ErrorResponse(
                errors,
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send an `error` response through the messenger
    private func sendError(_ error: Error, id: String) async throws {
        try await sendError([error], id: id)
    }

    /// Send an `error` response through the messenger
    private func sendError(_ errorMessage: String, id: String) async throws {
        try await sendError(GraphQLError(message: errorMessage), id: id)
    }
}

private let decoder = JSONDecoder()
private let encoder = GraphQLJSONEncoder()

public struct BlankInitPayload: Codable, Equatable {}
