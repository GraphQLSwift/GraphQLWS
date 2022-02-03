// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL

/// Client is an open-ended implementation of the client side of the protocol. It parses and adds callbacks for each type of server respose.
public class Client {
    // We keep this weak because we strongly inject this object into the messenger callback
    weak var messenger: Messenger?
    
    var onConnectionError: (ConnectionErrorResponse, Client) -> Void = { _, _ in }
    var onConnectionAck: (ConnectionAckResponse, Client) -> Void = { _, _ in }
    var onConnectionKeepAlive: (ConnectionKeepAliveResponse, Client) -> Void = { _, _ in }
    var onData: (DataResponse, Client) -> Void = { _, _ in }
    var onError: (ErrorResponse, Client) -> Void = { _, _ in }
    var onComplete: (CompleteResponse, Client) -> Void = { _, _ in }
    var onMessage: (String, Client) -> Void = { _, _ in }
    
    let encoder = GraphQLJSONEncoder()
    let decoder = JSONDecoder()
    
    /// Create a new client.
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the client to.
    public init(
        messenger: Messenger
    ) {
        self.messenger = messenger
        messenger.onRecieve { message in
            self.onMessage(message, self)
            
            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }
            
            guard let json = message.data(using: .utf8) else {
                self.error(.invalidEncoding())
                return
            }
            
            let response: Response
            do {
                response = try self.decoder.decode(Response.self, from: json)
            }
            catch {
                self.error(.noType())
                return
            }
            
            switch response.type {
                case .GQL_CONNECTION_ERROR:
                    guard let connectionErrorResponse = try? self.decoder.decode(ConnectionErrorResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                        return
                    }
                    self.onConnectionError(connectionErrorResponse, self)
                case .GQL_CONNECTION_ACK:
                    guard let connectionAckResponse = try? self.decoder.decode(ConnectionAckResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_ERROR))
                        return
                    }
                    self.onConnectionAck(connectionAckResponse, self)
                case .GQL_CONNECTION_KEEP_ALIVE:
                    guard let connectionKeepAliveResponse = try? self.decoder.decode(ConnectionKeepAliveResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_CONNECTION_KEEP_ALIVE))
                        return
                    }
                    self.onConnectionKeepAlive(connectionKeepAliveResponse, self)
                case .GQL_DATA:
                    guard let nextResponse = try? self.decoder.decode(DataResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_DATA))
                        return
                    }
                    self.onData(nextResponse, self)
                case .GQL_ERROR:
                    guard let errorResponse = try? self.decoder.decode(ErrorResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_ERROR))
                        return
                    }
                    self.onError(errorResponse, self)
                case .GQL_COMPLETE:
                    guard let completeResponse = try? self.decoder.decode(CompleteResponse.self, from: json) else {
                        self.error(.invalidResponseFormat(messageType: .GQL_COMPLETE))
                        return
                    }
                    self.onComplete(completeResponse, self)
                case .unknown:
                    self.error(.invalidType())
            }
        }
    }
    
    /// Define the callback run on receipt of a `connection_error` message
    /// - Parameter callback: The callback to assign
    public func onConnectionError(_ callback: @escaping (ConnectionErrorResponse, Client) -> Void) {
        self.onConnectionError = callback
    }
    
    /// Define the callback run on receipt of a `connection_ack` message
    /// - Parameter callback: The callback to assign
    public func onConnectionAck(_ callback: @escaping (ConnectionAckResponse, Client) -> Void) {
        self.onConnectionAck = callback
    }
    
    /// Define the callback run on receipt of a `connection_ka` message
    /// - Parameter callback: The callback to assign
    public func onConnectionKeepAlive(_ callback: @escaping (ConnectionKeepAliveResponse, Client) -> Void) {
        self.onConnectionKeepAlive = callback
    }
    
    /// Define the callback run on receipt of a `data` message
    /// - Parameter callback: The callback to assign
    public func onData(_ callback: @escaping (DataResponse, Client) -> Void) {
        self.onData = callback
    }
    
    /// Define the callback run on receipt of an `error` message
    /// - Parameter callback: The callback to assign
    public func onError(_ callback: @escaping (ErrorResponse, Client) -> Void) {
        self.onError = callback
    }
    
    /// Define the callback run on receipt of any message
    /// - Parameter callback: The callback to assign
    public func onComplete(_ callback: @escaping (CompleteResponse, Client) -> Void) {
        self.onComplete = callback
    }
    
    /// Define the callback run on receipt of a `complete` message
    /// - Parameter callback: The callback to assign
    public func onMessage(_ callback: @escaping (String, Client) -> Void) {
        self.onMessage = callback
    }
    
    /// Send a `connection_init` request through the messenger
    public func sendConnectionInit(payload: ConnectionInitAuth?) {
        guard let messenger = messenger else { return }
        messenger.send(
            ConnectionInitRequest(
                payload: payload
            ).toJSON(encoder)
        )
    }
    
    /// Send a `start` request through the messenger
    public func sendStart(payload: GraphQLRequest, id: String) {
        guard let messenger = messenger else { return }
        messenger.send(
            StartRequest(
                payload: payload,
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send a `stop` request through the messenger
    public func sendStop(id: String) {
        guard let messenger = messenger else { return }
        messenger.send(
            StopRequest(
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send a `connection_terminate` request through the messenger
    public func sendConnectionTerminate() {
        guard let messenger = messenger else { return }
        messenger.send(
            ConnectionTerminateRequest().toJSON(encoder)
        )
    }
    
    /// Send an error through the messenger and close the connection
    private func error(_ error: GraphQLWSError) {
        guard let messenger = messenger else { return }
        messenger.error(error.message, code: error.code.rawValue)
    }
}
