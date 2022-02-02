// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL

/// Adds client-side [graphql-ws protocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
/// support, namely parsing and adding callbacks for each type of server respose.
class Client {
    let messenger: Messenger
    
    let onMessage: (String) -> Void
    let onConnectionError: (ConnectionErrorResponse) -> Void
    let onConnectionAck: (ConnectionAckResponse) -> Void
    let onConnectionKeepAlive: (ConnectionKeepAliveResponse) -> Void
    let onData: (DataResponse) -> Void
    let onError: (ErrorResponse) -> Void
    let onComplete: (CompleteResponse) -> Void
    
    let encoder = GraphQLJSONEncoder()
    let decoder = JSONDecoder()
    
    /// Create a new client.
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the client to.
    ///   - onConnectionError: Callback run on receipt of a `connection_error` message
    ///   - onConnectionAck: Callback run on receipt of a `connection_ack` message
    ///   - onData: Callback run on receipt of a `data` message
    ///   - onError: Callback run on receipt of an `error` message
    ///   - onComplete: Callback run on receipt of a `complete` message
    ///   - onMessage: Callback run on receipt of any message
    init(
        messenger: Messenger,
        onConnectionError: @escaping (ConnectionErrorResponse) -> Void = { _ in () },
        onConnectionAck: @escaping (ConnectionAckResponse) -> Void = { _ in () },
        onConnectionKeepAlive: @escaping (ConnectionKeepAliveResponse) -> Void = { _ in () },
        onData: @escaping (DataResponse) -> Void = { _ in () },
        onError: @escaping (ErrorResponse) -> Void = { _ in () },
        onComplete: @escaping (CompleteResponse) -> Void = { _ in () },
        onMessage: @escaping (String) -> Void = { _ in () }
    ) {
        self.messenger = messenger
        self.onMessage = onMessage
        self.onConnectionError = onConnectionError
        self.onConnectionAck = onConnectionAck
        self.onConnectionKeepAlive = onConnectionKeepAlive
        self.onData = onData
        self.onError = onError
        self.onComplete = onComplete
        
        self.messenger.onRecieve { [weak self] message in
            guard let self = self else { return }
            
            self.onMessage(message)
            
            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }
            
            guard let json = message.data(using: .utf8) else {
                let error = GraphQLWSError.invalidEncoding()
                self.messenger.error(error.message, code: error.code)
                return
            }
            
            let response: Response
            do {
                response = try self.decoder.decode(Response.self, from: json)
            }
            catch {
                let error = GraphQLWSError.noType()
                self.messenger.error(error.message, code: error.code)
                return
            }
            
            switch response.type {
                case .GQL_CONNECTION_ERROR:
                    guard let connectionErrorResponse = try? self.decoder.decode(ConnectionErrorResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionError(connectionErrorResponse)
                case .GQL_CONNECTION_ACK:
                    guard let connectionAckResponse = try? self.decoder.decode(ConnectionAckResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_ACK)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionAck(connectionAckResponse)
                case .GQL_CONNECTION_KEEP_ALIVE:
                    guard let connectionKeepAliveResponse = try? self.decoder.decode(ConnectionKeepAliveResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_KEEP_ALIVE)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionKeepAlive(connectionKeepAliveResponse)
                case .GQL_DATA:
                    guard let nextResponse = try? self.decoder.decode(DataResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_DATA)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onData(nextResponse)
                case .GQL_ERROR:
                    guard let errorResponse = try? self.decoder.decode(ErrorResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_ERROR)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onError(errorResponse)
                case .GQL_COMPLETE:
                    guard let completeResponse = try? self.decoder.decode(CompleteResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_COMPLETE)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onComplete(completeResponse)
                case .unknown:
                    let error = GraphQLWSError.invalidType()
                    self.messenger.error(error.message, code: error.code)
            }
        }
    }
    
    /// Send a `connection_init` request through the messenger
    func sendConnectionInit(payload: ConnectionInitAuth?) {
        messenger.send(
            ConnectionInitRequest(
                payload: payload
            ).toJSON(encoder)
        )
    }
    
    /// Send a `start` request through the messenger
    func sendStart(payload: GraphQLRequest, id: String) {
        messenger.send(
            StartRequest(
                payload: payload,
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send a `stop` request through the messenger
    func sendStop(id: String) {
        messenger.send(
            StopRequest(
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send a `connection_terminate` request through the messenger
    func sendConnectionTerminate() {
        messenger.send(
            ConnectionTerminateRequest().toJSON(encoder)
        )
    }
}
