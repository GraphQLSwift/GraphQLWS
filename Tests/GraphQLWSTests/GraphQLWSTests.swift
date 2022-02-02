// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation

import GraphQL
import NIO
import XCTest

@testable import GraphQLWS

class GraphqlWsTests: XCTestCase {
    var clientMessenger: TestMessenger!
    var server: Server!
    
    override func setUp() {
        clientMessenger = TestMessenger()
        let serverMessenger = TestMessenger()
        
        clientMessenger.other = serverMessenger
        serverMessenger.other = clientMessenger
        
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        let api = TestAPI()
        let context = TestContext()
        
        server = Server(
            messenger: serverMessenger,
            onExecute: { graphQLRequest in
                api.execute(
                    request: graphQLRequest.query,
                    context: context,
                    on: eventLoop
                )
            },
            onSubscribe: { graphQLRequest in
                api.subscribe(
                    request: graphQLRequest.query,
                    context: context,
                    on: eventLoop
                )
            }
        )
    }
    
    /// Tests that throwing in the authorization callback forces an unauthorized error
    func testAuth() throws {
        server.auth { payload in
            throw TestError.couldBeAnything
        }
        
        var messages = [String]()
        let completeExpectation = XCTestExpectation()
        
        let client = Client(messenger: clientMessenger)
        client.onMessage { message in
            messages.append(message)
            completeExpectation.fulfill()
        }
        
        client.sendConnectionInit(
            payload: ConnectionInitAuth(
                authToken: ""
            )
        )
        
        wait(for: [completeExpectation], timeout: 2)
        XCTAssertEqual(
            messages,
            ["4401: Unauthorized"]
        )
    }
    
    func testSingleOp() throws {
        let id = UUID().description
        
        // Test single-op conversation
        var messages = [String]()
        let completeExpectation = XCTestExpectation()
        
        let client = Client(messenger: clientMessenger)
        
        client.onConnectionAck { [weak client] _ in
            guard let client = client else { return }
            client.sendStart(
                payload: GraphQLRequest(
                    query: """
                    query {
                        hello
                    }
                    """
                ),
                id: id
            )
        }
        client.onError { _ in
            completeExpectation.fulfill()
        }
        client.onComplete { _ in
            completeExpectation.fulfill()
        }
        client.onMessage { message in
            messages.append(message)
        }
        
        client.sendConnectionInit(payload: ConnectionInitAuth(authToken: ""))
        
        wait(for: [completeExpectation], timeout: 2)
        XCTAssertEqual(
            messages.count,
            3, // 1 connection_ack, 1 data, 1 complete
            "Messages: \(messages.description)"
        )
    }
    
    func testStreaming() throws {
        let id = UUID().description
        
        // Test streaming conversation
        var messages = [String]()
        let completeExpectation = XCTestExpectation()
        
        var dataIndex = 1
        let dataIndexMax = 3
        
        let client = Client(messenger: clientMessenger)
        client.onConnectionAck { [weak client] _ in
            guard let client = client else { return }
            client.sendStart(
                payload: GraphQLRequest(
                    query: """
                    subscription {
                        hello
                    }
                    """
                ),
                id: id
            )
            
            // Short sleep to allow for server to register subscription
            usleep(3000)
            
            pubsub.onNext("hello \(dataIndex)")
        }
        client.onData { _ in
            dataIndex = dataIndex + 1
            if dataIndex <= dataIndexMax {
                pubsub.onNext("hello \(dataIndex)")
            } else {
                pubsub.onCompleted()
            }
        }
        client.onError { _ in
            completeExpectation.fulfill()
        }
        client.onComplete { _ in
            completeExpectation.fulfill()
        }
        client.onMessage { message in
            messages.append(message)
        }
        
        client.sendConnectionInit(payload: ConnectionInitAuth(authToken: ""))
        
        wait(for: [completeExpectation], timeout: 2)
        XCTAssertEqual(
            messages.count,
            5, // 1 connection_ack, 3 data, 1 complete
            "Messages: \(messages.description)"
        )
    }
    
    enum TestError: Error {
        case couldBeAnything
    }
}
