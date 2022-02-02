// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL

/// Adds client-side [graphql-ws protocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
/// support, namely parsing and adding callbacks for each type of server respose.
class Client {
    let messenger: Messenger
    
    var onConnectionError: (ConnectionErrorResponse) -> Void = { _ in }
    var onConnectionAck: (ConnectionAckResponse) -> Void = { _ in }
    var onConnectionKeepAlive: (ConnectionKeepAliveResponse) -> Void = { _ in }
    var onData: (DataResponse) -> Void = { _ in }
    var onError: (ErrorResponse) -> Void = { _ in }
    var onComplete: (CompleteResponse) -> Void = { _ in }
    var onMessage: (String) -> Void = { _ in }
    
    let encoder = GraphQLJSONEncoder()
    let decoder = JSONDecoder()
    
    /// Create a new client.
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the client to.
    init(
        messenger: Messenger
    ) {
        self.messenger = messenger
        
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
    
    /// Define the callback run on receipt of a `connection_error` message
    /// - Parameter callback: The callback to assign
    func onConnectionError(_ callback: @escaping (ConnectionErrorResponse) -> Void) {
        self.onConnectionError = callback
    }
    
    /// Define the callback run on receipt of a `connection_ack` message
    /// - Parameter callback: The callback to assign
    func onConnectionAck(_ callback: @escaping (ConnectionAckResponse) -> Void) {
        self.onConnectionAck = callback
    }
    
    /// Define the callback run on receipt of a `connection_ka` message
    /// - Parameter callback: The callback to assign
    func onConnectionKeepAlive(_ callback: @escaping (ConnectionKeepAliveResponse) -> Void) {
        self.onConnectionKeepAlive = callback
    }
    
    /// Define the callback run on receipt of a `data` message
    /// - Parameter callback: The callback to assign
    func onData(_ callback: @escaping (DataResponse) -> Void) {
        self.onData = callback
    }
    
    /// Define the callback run on receipt of an `error` message
    /// - Parameter callback: The callback to assign
    func onError(_ callback: @escaping (ErrorResponse) -> Void) {
        self.onError = callback
    }
    
    /// Define the callback run on receipt of any message
    /// - Parameter callback: The callback to assign
    func onComplete(_ callback: @escaping (CompleteResponse) -> Void) {
        self.onComplete = callback
    }
    
    /// Define the callback run on receipt of a `complete` message
    /// - Parameter callback: The callback to assign
    func onMessage(_ callback: @escaping (String) -> Void) {
        self.onMessage = callback
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
