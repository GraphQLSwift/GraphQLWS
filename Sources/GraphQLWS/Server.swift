// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL
import GraphQLRxSwift
import NIO
import RxSwift

/// Server implements the server-side portion of the protocol, allowing a few callbacks for customization.
public class Server {
    // We keep this weak because we strongly inject this object into the messenger callback
    weak var messenger: Messenger?
    
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
    
    /// Define the callback run during `connection_init` resolution that allows authorization using the `payload`.
    /// Throw to indicate that authorization has failed.
    /// - Parameter callback: The callback to assign
    public func auth(_ callback: @escaping (ConnectionInitRequest) throws -> Void) {
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
            subscribeFuture.whenSuccess { result in
                guard let streamOpt = result.stream else {
                    // API issue - subscribe resolver isn't stream
                    let error = GraphQLWSError.internalAPIStreamIssue()
                    messenger.error(error.message, code: error.code)
                    return
                }
                let stream = streamOpt as! ObservableSubscriptionEventStream
                let observable = stream.observable
                observable.subscribe(
                    onNext: { [weak self] resultFuture in
                        guard let self = self, let messenger = self.messenger else { return }
                        resultFuture.whenSuccess { result in
                            messenger.send(DataResponse(result, id: id).toJSON(self.encoder))
                        }
                        resultFuture.whenFailure { error in
                            messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                        }
                    },
                    onError: { [weak self] error in
                        guard let self = self, let messenger = self.messenger else { return }
                        messenger.send(ErrorResponse(error, id: id).toJSON(self.encoder))
                    },
                    onCompleted: { [weak self] in
                        guard let self = self, let messenger = self.messenger else { return }
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
