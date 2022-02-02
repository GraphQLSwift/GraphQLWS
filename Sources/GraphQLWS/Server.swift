// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL
import GraphQLRxSwift
import NIO
import RxSwift

/// Adds server-side [graphql-ws subprotocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
/// support. This handles the majority of query processing according to the procol definition, allowing a few callbacks for customization.
class Server {
    let messenger: Messenger
    
    let onExecute: (GraphQLRequest) -> EventLoopFuture<GraphQLResult>
    let onSubscribe: (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>
    
    var auth: (ConnectionInitRequest) throws -> Void = { _ in }
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
    init(
        messenger: Messenger,
        onExecute: @escaping (GraphQLRequest) -> EventLoopFuture<GraphQLResult>,
        onSubscribe: @escaping (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>
    ) {
        self.messenger = messenger
        self.onExecute = onExecute
        self.onSubscribe = onSubscribe
        
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
            
            let request: Request
            do {
                request = try self.decoder.decode(Request.self, from: json)
            }
            catch {
                let error = GraphQLWSError.noType()
                self.messenger.error(error.message, code: error.code)
                return
            }
            
            switch request.type {
                case .GQL_CONNECTION_INIT:
                    guard let connectionInitRequest = try? self.decoder.decode(ConnectionInitRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_CONNECTION_INIT)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionInit(connectionInitRequest)
                case .GQL_START:
                    guard let startRequest = try? self.decoder.decode(StartRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_START)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onStart(startRequest)
                case .GQL_STOP:
                    guard let stopRequest = try? self.decoder.decode(StopRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_STOP)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onStop(stopRequest, self.messenger)
                case .GQL_CONNECTION_TERMINATE:
                    guard let connectionTerminateRequest = try? self.decoder.decode(ConnectionTerminateRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_CONNECTION_TERMINATE)
                        self.messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionTerminate(connectionTerminateRequest)
                case .unknown:
                    let error = GraphQLWSError.invalidType()
                    self.messenger.error(error.message, code: error.code)
            }
        }
        
        // Clean up any uncompleted subscriptions
        // TODO: Re-enable this
        //        messenger.onClose {
        //            _ = self.context?.cleanupSubscription()
        //        }
    }
    
    /// Define the callback run during `connection_init` resolution that allows authorization using the `payload`.
    /// Throw to indicate that authorization has failed.
    /// - Parameter callback: The callback to assign
    func auth(_ callback: @escaping (ConnectionInitRequest) throws -> Void) {
        self.auth = callback
    }
    
    /// Define the callback run when the communication is shut down, either by the client or server
    /// - Parameter callback: The callback to assign
    func onExit(_ callback: @escaping () -> Void) {
        self.onExit = callback
    }
    
    /// Define the callback run on receipt of any message
    /// - Parameter callback: The callback to assign
    func onMessage(_ callback: @escaping (String) -> Void) {
        self.onMessage = callback
    }
    
    private func onConnectionInit(_ connectionInitRequest: ConnectionInitRequest) {
        guard !initialized else {
            let error = GraphQLWSError.tooManyInitializations()
            messenger.error(error.message, code: error.code)
            return
        }
        
        do {
            try self.auth(connectionInitRequest)
        }
        catch {
            let error = GraphQLWSError.unauthorized()
            messenger.error(error.message, code: error.code)
            return
        }
        initialized = true
        messenger.send(
            ConnectionAckResponse().toJSON(self.encoder)
        )
        // TODO: Should we send the `ka` message?
    }
    
    private func onStart(_ startRequest: StartRequest) {
        guard initialized else {
            let error = GraphQLWSError.notInitialized()
            messenger.error(error.message, code: error.code)
            return
        }
        
        let id = startRequest.id
        let graphQLRequest = startRequest.payload
        
        var isStreaming = false
        do {
            isStreaming = try graphQLRequest.isSubscription()
        }
        catch {
            messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
            return
        }
        
        if isStreaming {
            let subscribeFuture = onSubscribe(graphQLRequest)
            subscribeFuture.whenSuccess { [weak self] result in
                guard let self = self else { return }
                guard let streamOpt = result.stream else {
                    // API issue - subscribe resolver isn't stream
                    let error = GraphQLWSError.internalAPIStreamIssue()
                    self.messenger.error(error.message, code: error.code)
                    return
                }
                let stream = streamOpt as! ObservableSubscriptionEventStream
                let observable = stream.observable
                observable.subscribe(
                    onNext: { resultFuture in
                        resultFuture.whenSuccess { result in
                            self.messenger.send(DataResponse(result, id: id).toJSON(self.encoder))
                        }
                        resultFuture.whenFailure { error in
                            self.messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                        }
                    },
                    onError: { error in
                        self.messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                    },
                    onCompleted: {
                        self.messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
                        _ = self.messenger.close()
                    }
                ).disposed(by: self.disposeBag)
            }
            subscribeFuture.whenFailure { error in
                let error = GraphQLWSError.graphQLError(error)
                _ = self.messenger.error(error.message, code: error.code)
            }
        }
        else {
            let executeFuture = onExecute(graphQLRequest)
            executeFuture.whenSuccess { result in
                self.messenger.send(DataResponse(result, id: id).toJSON(self.encoder))
                self.messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
            }
            executeFuture.whenFailure { error in
                self.messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                self.messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
            }
        }
    }
    
    private func onStop(_: StopRequest, _ messenger: Messenger) {
        guard initialized else {
            let error = GraphQLWSError.notInitialized()
            messenger.error(error.message, code: error.code)
            return
        }
        onExit()
    }
    
    private func onConnectionTerminate(_: ConnectionTerminateRequest) {
        onExit()
        _ = messenger.close()
    }
}