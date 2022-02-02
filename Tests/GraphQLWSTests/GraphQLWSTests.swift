// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation

import GraphQL
import NIO
import XCTest

@testable import GraphQLWS

class GraphqlWsTests: XCTestCase {
    var clientMessenger: TestMessenger!
    
    override func setUp() {
        clientMessenger = TestMessenger()
        let serverMessenger = TestMessenger()
        
        clientMessenger.other = serverMessenger
        serverMessenger.other = clientMessenger
        
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        let api = TestAPI()
        let context = TestContext()
        
        let server = Server(
            auth: { _ in },
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
            },
            onExit: {}
        )
        server.attach(to: serverMessenger)
    }
    
    func testSingleOp() throws {
        let encoder = GraphQLJSONEncoder()
        let id = UUID().description
        
        // Test single-op conversation
        var messages = [String]()
        let completeExpectation = XCTestExpectation()
        
        let client = Client(
            onMessage: { message in
                messages.append(message)
            },
            onConnectionAck: { _ in
                self.clientMessenger.send(StartRequest(
                    payload: GraphQLRequest(
                        query: """
                        query {
                            hello
                        }
                        """
                    ),
                    id: id
                ).toJSON(encoder))
            },
            onError: { _ in
                completeExpectation.fulfill()
            },
            onComplete: { _ in
                completeExpectation.fulfill()
            }
        )
        client.attach(to: clientMessenger)
        
        clientMessenger.send(
            ConnectionInitRequest(
                payload: ConnectionInitAuth(
                    authToken: ""
                )
            ).toJSON(encoder)
        )
        
        wait(for: [completeExpectation], timeout: 2)
        XCTAssertEqual(
            messages.count,
            3, // 1 connection_ack, 1 data, 1 complete
            "Messages: \(messages.description)"
        )
    }
    
    func testStreaming() throws {
        let encoder = GraphQLJSONEncoder()
        let id = UUID().description
        
        // Test streaming conversation
        var messages = [String]()
        let completeExpectation = XCTestExpectation()
        
        var dataIndex = 1
        let dataIndexMax = 3
        
        let client = Client(
            onMessage: { message in
                messages.append(message)
            },
            onConnectionAck: { _ in
                self.clientMessenger.send(StartRequest(
                    payload: GraphQLRequest(
                        query: """
                        subscription {
                            hello
                        }
                        """
                    ),
                    id: id
                ).toJSON(encoder))
                
                // Short sleep to allow for server to register subscription
                usleep(3000)
                
                pubsub.onNext("hello \(dataIndex)")
            },
            onData: { _ in
                dataIndex = dataIndex + 1
                if dataIndex <= dataIndexMax {
                    pubsub.onNext("hello \(dataIndex)")
                } else {
                    pubsub.onCompleted()
                }
            },
            onError: { _ in
                completeExpectation.fulfill()
            },
            onComplete: { _ in
                completeExpectation.fulfill()
            }
        )
        client.attach(to: clientMessenger)
        
        clientMessenger.send(
            ConnectionInitRequest(
                payload: ConnectionInitAuth(
                    authToken: ""
                )
            ).toJSON(encoder)
        )
        
        wait(for: [completeExpectation], timeout: 2)
        XCTAssertEqual(
            messages.count,
            5, // 1 connection_ack, 3 data, 1 complete
            "Messages: \(messages.description)"
        )
    }
}
