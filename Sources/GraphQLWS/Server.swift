// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL
import GraphQLRxSwift
import NIO
import RxSwift

/// Adds server-side [graphql-ws subprotocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
/// support, namely parsing and adding callbacks for each type of client request.
class Server {
    let auth: (ConnectionInitRequest) throws -> Void
    let onExecute: (GraphQLRequest) -> EventLoopFuture<GraphQLResult>
    let onSubscribe: (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>
    let onExit: () -> Void
    let onMessage: (String) -> Void
    
    var initialized = false
    
    let disposeBag = DisposeBag()
    let decoder = JSONDecoder()
    let encoder = GraphQLJSONEncoder()
    
    init(
        auth: @escaping (ConnectionInitRequest) throws -> Void,
        onExecute: @escaping (GraphQLRequest) -> EventLoopFuture<GraphQLResult>,
        onSubscribe: @escaping (GraphQLRequest) -> EventLoopFuture<SubscriptionResult>,
        onExit: @escaping () -> Void,
        onMessage: @escaping (String) -> Void = { _ in () }
    ) {
        self.auth = auth
        self.onExecute = onExecute
        self.onSubscribe = onSubscribe
        self.onExit = onExit
        self.onMessage = onMessage
    }
    
    /// Attaches the responder to the provided Messenger in order to recieve and transmit messages
    /// - Parameter messenger: The Messenger to use for communication
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
            
            let request: Request
            do {
                request = try self.decoder.decode(Request.self, from: json)
            }
            catch {
                let error = GraphQLWSError.noType()
                messenger.error(error.message, code: error.code)
                return
            }
            
            switch request.type {
                case .GQL_CONNECTION_INIT:
                    guard let connectionInitRequest = try? self.decoder.decode(ConnectionInitRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_CONNECTION_INIT)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionInit(connectionInitRequest, messenger)
                case .GQL_START:
                    guard let startRequest = try? self.decoder.decode(StartRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_START)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onStart(startRequest, messenger)
                case .GQL_STOP:
                    guard let stopRequest = try? self.decoder.decode(StopRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_STOP)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onStop(stopRequest, messenger)
                case .GQL_CONNECTION_TERMINATE:
                    guard let connectionTerminateRequest = try? self.decoder.decode(ConnectionTerminateRequest.self, from: json) else {
                        let error = GraphQLWSError.invalidRequestFormat(messageType: .GQL_CONNECTION_TERMINATE)
                        messenger.error(error.message, code: error.code)
                        return
                    }
                    self.onConnectionTerminate(connectionTerminateRequest, messenger)
                case .unknown:
                    let error = GraphQLWSError.invalidType()
                    messenger.error(error.message, code: error.code)
            }
        }
        
        // Clean up any uncompleted subscriptions
        // TODO: Re-enable this
//        messenger.onClose {
//            _ = self.context?.cleanupSubscription()
//        }
    }
    
    private func onConnectionInit(_ connectionInitRequest: ConnectionInitRequest, _ messenger: Messenger) {
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
    
    private func onStart(_ startRequest: StartRequest, _ messenger: Messenger) {
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
                    messenger.error(error.message, code: error.code)
                    return
                }
                let stream = streamOpt as! ObservableSubscriptionEventStream
                let observable = stream.observable
                observable.subscribe(
                    onNext: { resultFuture in
                        resultFuture.whenSuccess { result in
                            messenger.send(DataResponse(result, id: id).toJSON(self.encoder))
                        }
                        resultFuture.whenFailure { error in
                            messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                        }
                    },
                    onError: { error in
                        messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                    },
                    onCompleted: {
                        messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
                        _ = messenger.close()
                    }
                ).disposed(by: self.disposeBag)
            }
            subscribeFuture.whenFailure { error in
                let error = GraphQLWSError.graphQLError(error)
                _ = messenger.error(error.message, code: error.code)
            }
        }
        else {
            let executeFuture = onExecute(graphQLRequest)
            executeFuture.whenSuccess { result in
                messenger.send(DataResponse(result, id: id).toJSON(self.encoder))
                messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
            }
            executeFuture.whenFailure { error in
                messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                messenger.send(CompleteResponse(id: id).toJSON(self.encoder))
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
    
    private func onConnectionTerminate(_: ConnectionTerminateRequest, _ messenger: Messenger) {
        onExit()
        _ = messenger.close()
    }
}
