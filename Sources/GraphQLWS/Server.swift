// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL
import GraphQLRxSwift
import NIO
import RxSwift

/// Server implements the server-side portion of the protocol, allowing a few callbacks for customization.
public class Server<InitPayload: Equatable & Codable> {
    // We keep this weak because we strongly inject this object into the messenger callback
    weak var messenger: Messenger?
    
    let onExecute: (GraphQLRequest) -> EventLoopFuture<GraphQLResult>
    let onSubscribe: (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>
    
    var auth: (InitPayload) throws -> Void = { _ in }
    var onExit: () -> Void = { }
    var onMessage: (String) -> Void = { _ in }
    
    var initialized = false
    
    let disposeBag = DisposeBag()
    let decoder = JSONDecoder()
    let encoder = GraphQLJSONEncoder()
    
    /// Create a new server
    ///
    /// - Parameters:
    ///   - messenger: The messenger to bind the server to.
    ///   - onExecute: Callback run during `start` resolution for non-streaming queries. Typically this is `API.execute`.
    ///   - onSubscribe: Callback run during `start` resolution for streaming queries. Typically this is `API.subscribe`.
    public init(
        messenger: Messenger,
        onExecute: @escaping (GraphQLRequest) -> EventLoopFuture<GraphQLResult>,
        onSubscribe: @escaping (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>
    ) {
        self.messenger = messenger
        self.onExecute = onExecute
        self.onSubscribe = onSubscribe
        
        messenger.onRecieve { message in
            guard let messenger = self.messenger else { return }
            
            self.onMessage(message)
            
            // Detect and ignore error responses.
            if message.starts(with: "44") {
                // TODO: Determine what to do with returned error messages
                return
            }
            
            guard let json = message.data(using: .utf8) else {
                self.error(.invalidEncoding())
                return
            }
            
            let request: Request
            do {
                request = try self.decoder.decode(Request.self, from: json)
            }
            catch {
                self.error(.noType())
                return
            }
            
            switch request.type {
                case .GQL_CONNECTION_INIT:
                    guard let connectionInitRequest = try? self.decoder.decode(ConnectionInitRequest<InitPayload>.self, from: json) else {
                        self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_INIT))
                        return
                    }
                    self.onConnectionInit(connectionInitRequest, messenger)
                case .GQL_START:
                    guard let startRequest = try? self.decoder.decode(StartRequest.self, from: json) else {
                        self.error(.invalidRequestFormat(messageType: .GQL_START))
                        return
                    }
                    self.onStart(startRequest, messenger)
                case .GQL_STOP:
                    guard let stopRequest = try? self.decoder.decode(StopRequest.self, from: json) else {
                        self.error(.invalidRequestFormat(messageType: .GQL_STOP))
                        return
                    }
                    self.onStop(stopRequest, messenger)
                case .GQL_CONNECTION_TERMINATE:
                    guard let connectionTerminateRequest = try? self.decoder.decode(ConnectionTerminateRequest.self, from: json) else {
                        self.error(.invalidRequestFormat(messageType: .GQL_CONNECTION_TERMINATE))
                        return
                    }
                    self.onConnectionTerminate(connectionTerminateRequest, messenger)
                case .unknown:
                    self.error(.invalidType())
            }
        }
    }
    
    /// Define the callback run during `connection_init` resolution that allows authorization using the `payload`.
    /// Throw from this closure to indicate that authorization has failed.
    /// - Parameter callback: The callback to assign
    public func auth(_ callback: @escaping (InitPayload) throws -> Void) {
        self.auth = callback
    }
    
    /// Define the callback run when the communication is shut down, either by the client or server
    /// - Parameter callback: The callback to assign
    public func onExit(_ callback: @escaping () -> Void) {
        self.onExit = callback
    }
    
    /// Define the callback run on receipt of any message
    /// - Parameter callback: The callback to assign
    public func onMessage(_ callback: @escaping (String) -> Void) {
        self.onMessage = callback
    }
    
    private func onConnectionInit(_ connectionInitRequest: ConnectionInitRequest<InitPayload>, _ messenger: Messenger) {
        guard !initialized else {
            self.error(.tooManyInitializations())
            return
        }
        
        do {
            try self.auth(connectionInitRequest.payload)
        }
        catch {
            self.error(.unauthorized())
            return
        }
        initialized = true
        self.sendConnectionAck()
        // TODO: Should we send the `ka` message?
    }
    
    private func onStart(_ startRequest: StartRequest, _ messenger: Messenger) {
        guard initialized else {
            self.error(.notInitialized())
            return
        }
        
        let id = startRequest.id
        let graphQLRequest = startRequest.payload
        
        var isStreaming = false
        do {
            isStreaming = try graphQLRequest.isSubscription()
        }
        catch {
            self.sendError(error, id: id)
            return
        }
        
        if isStreaming {
            let subscribeFuture = onSubscribe(graphQLRequest)
            subscribeFuture.whenSuccess { result in
                guard let streamOpt = result.stream else {
                    // API issue - subscribe resolver isn't stream
                    self.sendError(result.errors, id: id)
                    return
                }
                let stream = streamOpt as! ObservableSubscriptionEventStream
                let observable = stream.observable
                observable.subscribe(
                    onNext: { [weak self] resultFuture in
                        guard let self = self else { return }
                        resultFuture.whenSuccess { result in
                            self.sendData(result, id: id)
                        }
                        resultFuture.whenFailure { error in
                            self.sendError(error, id: id)
                        }
                    },
                    onError: { [weak self] error in
                        guard let self = self else { return }
                        self.sendError(error, id: id)
                    },
                    onCompleted: { [weak self] in
                        guard let self = self else { return }
                        self.sendComplete(id: id)
                    }
                ).disposed(by: self.disposeBag)
            }
            subscribeFuture.whenFailure { error in
                self.sendError(error, id: id)
            }
        }
        else {
            let executeFuture = onExecute(graphQLRequest)
            executeFuture.whenSuccess { result in
                self.sendData(result, id: id)
                self.sendComplete(id: id)
                messenger.close()
            }
            executeFuture.whenFailure { error in
                self.sendError(error, id: id)
                self.sendComplete(id: id)
                messenger.close()
            }
        }
    }
    
    private func onStop(_: StopRequest, _ messenger: Messenger) {
        guard initialized else {
            self.error(.notInitialized())
            return
        }
    }
    
    private func onConnectionTerminate(_: ConnectionTerminateRequest, _ messenger: Messenger) {
        onExit()
        _ = messenger.close()
    }
    
    /// Send a `connection_ack` response through the messenger
    private func sendConnectionAck(_ payload: [String: Map]? = nil) {
        guard let messenger = messenger else { return }
        messenger.send(
            ConnectionAckResponse(payload).toJSON(encoder)
        )
    }
    
    /// Send a `connection_error` response through the messenger
    private func sendConnectionError(_ payload: [String: Map]? = nil) {
        guard let messenger = messenger else { return }
        messenger.send(
            ConnectionErrorResponse(payload).toJSON(encoder)
        )
    }
    
    /// Send a `ka` response through the messenger
    private func sendConnectionKeepAlive(_ payload: [String: Map]? = nil) {
        guard let messenger = messenger else { return }
        messenger.send(
            ConnectionKeepAliveResponse(payload).toJSON(encoder)
        )
    }
    
    /// Send a `data` response through the messenger
    private func sendData(_ payload: GraphQLResult? = nil, id: String) {
        guard let messenger = messenger else { return }
        messenger.send(
            DataResponse(
                payload,
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send a `complete` response through the messenger
    private func sendComplete(id: String) {
        guard let messenger = messenger else { return }
        messenger.send(
            CompleteResponse(
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send an `error` response through the messenger
    private func sendError(_ errors: [Error], id: String) {
        guard let messenger = messenger else { return }
        messenger.send(
            ErrorResponse(
                errors,
                id: id
            ).toJSON(encoder)
        )
    }
    
    /// Send an `error` response through the messenger
    private func sendError(_ error: Error, id: String) {
        self.sendError([error], id: id)
    }
    
    /// Send an `error` response through the messenger
    private func sendError(_ errorMessage: String, id: String) {
        self.sendError(GraphQLError(message: errorMessage), id: id)
    }
    
    /// Send an error through the messenger and close the connection
    private func error(_ error: GraphQLWSError) {
        guard let messenger = messenger else { return }
        messenger.error(error.message, code: error.code.rawValue)
    }
}
