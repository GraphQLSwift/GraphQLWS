import Foundation
import GraphQL

/// Server implements the server-side portion of the protocol, allowing a few callbacks for customization.
///
/// By default, there are no authorization checks
public class Server<InitPayload: Equatable & Codable> {
    // We keep this weak because we strongly inject this object into the messenger callback
    weak var messenger: Messenger?

    let onExecute: (GraphQLRequest) async throws -> GraphQLResult
    let onSubscribe: (GraphQLRequest) async throws -> Result<AsyncThrowingStream<GraphQLResult, Error>, GraphQLErrors>
    var auth: (InitPayload) async throws -> Void

    var onExit: () async throws -> Void = {}
    var onMessage: (String) async throws -> Void = { _ in }
    var onOperationComplete: (String) async throws -> Void = { _ in }
    var onOperationError: (String, [Error]) async throws -> Void = { _, _ in }

    var initialized = false

    let decoder = JSONDecoder()
    let encoder = GraphQLJSONEncoder()

    private var subscriptionTasks = [String: Task<Void, any Error>]()

    /// Create a new server
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the server to.
    ///   - onExecute: Callback run during `start` resolution for non-streaming queries. Typically this is `API.execute`.
    ///   - onSubscribe: Callback run during `start` resolution for streaming queries. Typically this is `API.subscribe`.
    public init(
        messenger: Messenger,
        onExecute: @escaping (GraphQLRequest) async throws -> GraphQLResult,
        onSubscribe: @escaping (GraphQLRequest) async throws -> Result<AsyncThrowingStream<GraphQLResult, Error>, GraphQLErrors>
    ) {
        self.messenger = messenger
        self.onExecute = onExecute
        self.onSubscribe = onSubscribe
        auth = { _ in }

        messenger.onReceive { message in
            guard let messenger = self.messenger else { return }

            try await self.onMessage(message)

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
                request = try self.decoder.decode(Request.self, from: json)
            } catch {
                try await self.error(.noType())
                return
            }

            // handle incoming message
            switch request.type {
            case .GQL_CONNECTION_INIT:
                guard let connectionInitRequest = try? self.decoder.decode(ConnectionInitRequest<InitPayload>.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_INIT))
                    return
                }
                try await self.onConnectionInit(connectionInitRequest, messenger)
            case .GQL_START:
                guard let startRequest = try? self.decoder.decode(StartRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_START))
                    return
                }
                try await self.onStart(startRequest, messenger)
            case .GQL_STOP:
                guard let stopRequest = try? self.decoder.decode(StopRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_STOP))
                    return
                }
                try await self.onStop(stopRequest)
            case .GQL_CONNECTION_TERMINATE:
                guard let connectionTerminateRequest = try? self.decoder.decode(ConnectionTerminateRequest.self, from: json) else {
                    try await self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_TERMINATE))
                    return
                }
                try await self.onConnectionTerminate(connectionTerminateRequest, messenger)
            case .unknown:
                try await self.error(.invalidType())
            }
        }
    }

    /// Define a custom callback run during `connection_init` resolution that allows authorization using the `payload`.
    /// Throw from this closure to indicate that authorization has failed.
    /// - Parameter callback: The callback to assign
    public func auth(_ callback: @escaping (InitPayload) async throws -> Void) {
        auth = callback
    }

    /// Define the callback run when the communication is shut down, either by the client or server
    /// - Parameter callback: The callback to assign
    public func onExit(_ callback: @escaping () -> Void) {
        onExit = callback
    }

    /// Define the callback run on receipt of any message
    /// - Parameter callback: The callback to assign
    public func onMessage(_ callback: @escaping (String) -> Void) {
        onMessage = callback
    }

    /// Define the callback run on the completion a full operation (query/mutation, end of subscription)
    /// - Parameter callback: The callback to assign
    public func onOperationComplete(_ callback: @escaping (String) -> Void) {
        onOperationComplete = callback
    }

    /// Define the callback to run on error of any full operation (failed query, interrupted subscription)
    /// - Parameter callback: The callback to assign
    public func onOperationError(_ callback: @escaping (String, [Error]) -> Void) {
        onOperationError = callback
    }

    private func onConnectionInit(_ connectionInitRequest: ConnectionInitRequest<InitPayload>, _: Messenger) async throws {
        guard !initialized else {
            try await error(.tooManyInitializations())
            return
        }

        do {
            try await auth(connectionInitRequest.payload)
        } catch {
            try await self.error(.unauthorized())
            return
        }
        initialized = true
        try await sendConnectionAck()
        // TODO: Should we send the `ka` message?
    }

    private func onStart(_ startRequest: StartRequest, _ messenger: Messenger) async throws {
        guard initialized else {
            try await error(.notInitialized())
            return
        }

        let id = startRequest.id
        if subscriptionTasks[id] != nil {
            try await error(.subscriberAlreadyExists(id: id))
        }

        let graphQLRequest = startRequest.payload

        var isStreaming = false
        do {
            isStreaming = try graphQLRequest.isSubscription()
        } catch {
            try await sendError(error, id: id)
            return
        }

        if isStreaming {
            do {
                let result = try await onSubscribe(graphQLRequest)
                let stream: AsyncThrowingStream<GraphQLResult, Error>
                do {
                    stream = try result.get()
                } catch {
                    try await sendError(error, id: id)
                    return
                }
                subscriptionTasks[id] = Task {
                    for try await event in stream {
                        try Task.checkCancellation()
                        do {
                            try await self.sendData(event, id: id)
                        } catch {
                            try await self.sendError(error, id: id)
                            throw error
                        }
                    }
                    try await self.sendComplete(id: id)
                }
            } catch {
                try await sendError(error, id: id)
            }
        } else {
            do {
                let result = try await onExecute(graphQLRequest)
                try await sendData(result, id: id)
                try await sendComplete(id: id)
            } catch {
                try await sendError(error, id: id)
            }
            try await messenger.close()
        }
    }

    private func onStop(_ stopRequest: StopRequest) async throws {
        guard initialized else {
            try await error(.notInitialized())
            return
        }

        let id = stopRequest.id
        if let task = subscriptionTasks[id] {
            task.cancel()
            subscriptionTasks.removeValue(forKey: id)
        }
        try await onOperationComplete(id)
    }

    private func onConnectionTerminate(_: ConnectionTerminateRequest, _ messenger: Messenger) async throws {
        for (_, subscriptionTask) in subscriptionTasks {
            subscriptionTask.cancel()
        }
        subscriptionTasks.removeAll()
        try await onExit()
        try await messenger.close()
    }

    /// Send a `connection_ack` response through the messenger
    private func sendConnectionAck(_ payload: [String: Map]? = nil) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            ConnectionAckResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `connection_error` response through the messenger
    private func sendConnectionError(_ payload: [String: Map]? = nil) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            ConnectionErrorResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `ka` response through the messenger
    private func sendConnectionKeepAlive(_ payload: [String: Map]? = nil) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            ConnectionKeepAliveResponse(payload).toJSON(encoder)
        )
    }

    /// Send a `data` response through the messenger
    private func sendData(_ payload: GraphQLResult? = nil, id: String) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            DataResponse(
                payload,
                id: id
            ).toJSON(encoder)
        )
    }

    /// Send a `complete` response through the messenger
    private func sendComplete(id: String) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            CompleteResponse(
                id: id
            ).toJSON(encoder)
        )
        try await onOperationComplete(id)
    }

    /// Send an `error` response through the messenger
    private func sendError(_ errors: [Error], id: String) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(
            ErrorResponse(
                errors,
                id: id
            ).toJSON(encoder)
        )
        try await onOperationError(id, errors)
    }

    /// Send an `error` response through the messenger
    private func sendError(_ error: Error, id: String) async throws {
        try await sendError([error], id: id)
    }

    /// Send an `error` response through the messenger
    private func sendError(_ errorMessage: String, id: String) async throws {
        try await sendError(GraphQLError(message: errorMessage), id: id)
    }

    /// Send an error through the messenger and close the connection
    private func error(_ error: GraphQLWSError) async throws {
        guard let messenger = messenger else { return }
        try await messenger.error(error.message, code: error.code.rawValue)
    }
}
