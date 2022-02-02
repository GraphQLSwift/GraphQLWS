// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation

/// Adds client-side [graphql-ws protocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
/// support, namely parsing and adding callbacks for each type of server respose.
class Client {
    let onMessage: (String) -> Void
    let onConnectionError: (ConnectionErrorResponse) -> Void
    let onConnectionAck: (ConnectionAckResponse) -> Void
    let onConnectionKeepAlive: (ConnectionKeepAliveResponse) -> Void
    let onData: (DataResponse) -> Void
    let onError: (ErrorResponse) -> Void
    let onComplete: (CompleteResponse) -> Void
    
    let decoder = JSONDecoder()
    
    /// Create a new client.
    ///
    /// - Parameters:
    ///   - onMessage: callback run on receipt of any message
    ///   - onConnectionError: callback run on receipt of a `connection_error` message
    ///   - onConnectionAck: callback run on receipt of a `connection_ack` message
    ///   - onData: callback run on receipt of a `data` message
    ///   - onError: callback run on receipt of an `error` message
    ///   - onComplete: callback run on receipt of a `complete` message
    init(
        onMessage: @escaping (String) -> Void = { _ in () },
        onConnectionError: @escaping (ConnectionErrorResponse) -> Void = { _ in () },
        onConnectionAck: @escaping (ConnectionAckResponse) -> Void = { _ in () },
        onConnectionKeepAlive: @escaping (ConnectionKeepAliveResponse) -> Void = { _ in () },
        onData: @escaping (DataResponse) -> Void = { _ in () },
        onError: @escaping (ErrorResponse) -> Void = { _ in () },
        onComplete: @escaping (CompleteResponse) -> Void = { _ in () }
    ) {
        self.onMessage = onMessage
        self.onConnectionError = onConnectionError
        self.onConnectionAck = onConnectionAck
        self.onConnectionKeepAlive = onConnectionKeepAlive
        self.onData = onData
        self.onError = onError
        self.onComplete = onComplete
    }
    
    func attach(to messenger: Messenger) {
        messenger.onRecieve { message in
            self.onMessage(message)
            
            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }
            
            guard let json = message.data(using: .utf8) else {
                let error = GraphQLWSError.invalidEncoding()
                messenger.error(error.message, code: error.code)
                return
            }
            
            let response: Response
            do {
                response = try self.decoder.decode(Response.self, from: json)
            }
            catch {
                let error = GraphQLWSError.noType()
                messenger.error(error.message, code: error.code)
                return
            }
            
            switch response.type {
                case .GQL_CONNECTION_ERROR:
                    guard let connectionErrorResponse = try? self.decoder.decode(ConnectionErrorResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionError(connectionErrorResponse)
                case .GQL_CONNECTION_ACK:
                    guard let connectionAckResponse = try? self.decoder.decode(ConnectionAckResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_ACK)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionAck(connectionAckResponse)
                case .GQL_CONNECTION_KEEP_ALIVE:
                    guard let connectionKeepAliveResponse = try? self.decoder.decode(ConnectionKeepAliveResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_CONNECTION_KEEP_ALIVE)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionKeepAlive(connectionKeepAliveResponse)
                case .GQL_DATA:
                    guard let nextResponse = try? self.decoder.decode(DataResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_DATA)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onData(nextResponse)
                case .GQL_ERROR:
                    guard let errorResponse = try? self.decoder.decode(ErrorResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_ERROR)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onError(errorResponse)
                case .GQL_COMPLETE:
                    guard let completeResponse = try? self.decoder.decode(CompleteResponse.self, from: json) else {
                        let error = GraphQLWSError.invalidResponseFormat(messageType: .GQL_COMPLETE)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onComplete(completeResponse)
                case .unknown:
                    let error = GraphQLWSError.invalidType()
                    messenger.error(error.message, code: error.code)
            }
        }
    }
}
