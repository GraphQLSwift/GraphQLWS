# GraphQLWS

This implements the [graphql-ws WebSocket subprotocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md).
It is mainly intended for server support, but there is a basic client implementation included.

Features:
- Server implementation that implements defined protocol conversations
- Client and Server types that wrap messengers
- Codable Server and Client message structures
- Custom authentication support

## Usage

To use this package, include it in your `Package.swift` dependencies:

```swift
.package(url: "git@gitlab.com:PassiveLogic/platform/GraphQLWS.git", from: "<version>"),
```

Then create a class to implement the `Messenger` protocol. Here's an example using
[`WebSocketKit`](https://github.com/vapor/websocket-kit):

```swift
import WebSocketKit
import GraphQLWS

/// Messenger wrapper for WebSockets
class WebSocketMessenger: Messenger {
    private weak var websocket: WebSocket?
    private var onReceive: (String) -> Void = { _ in }
    
    init(websocket: WebSocket) {
        self.websocket = websocket
        websocket.onText { _, message in
            self.onReceive(message)
        }
    }
    
    func send<S>(_ message: S) where S: Collection, S.Element == Character {
        guard let websocket = websocket else { return }
        websocket.send(message)
    }
    
    func onReceive(callback: @escaping (String) -> Void) {
        self.onReceive = callback
    }
    
    func error(_ message: String, code: Int) {
        guard let websocket = websocket else { return }
        websocket.send("\(code): \(message)")
    }
    
    func close() {
        guard let websocket = websocket else { return }
        _ = websocket.close()
    }
}
```

Next create a `Server`, provide the messenger you just defined, and wrap the API `execute` and `subscribe` commands:

```swift
routes.webSocket(
    "graphqlSubscribe",
    onUpgrade: { request, websocket in
        let messenger = WebSocketMessenger(websocket: websocket)
        let server = GraphQLWS.Server<EmptyInitPayload?>(
            messenger: messenger,
            onExecute: { graphQLRequest in
                api.execute(
                    request: graphQLRequest.query,
                    context: context,
                    on: self.eventLoop,
                    variables: graphQLRequest.variables,
                    operationName: graphQLRequest.operationName
                )
            },
            onSubscribe: { graphQLRequest in
                api.subscribe(
                    request: graphQLRequest.query,
                    context: context,
                    on: self.eventLoop,
                    variables: graphQLRequest.variables,
                    operationName: graphQLRequest.operationName
                )
            }
        )
    }
)
```

### Authentication

This package exposes authentication hooks on the `connection_init` message. To perform custom authentication,
provide a codable type to the Server init and define an `auth` callback on the server. For example:

```swift
struct UsernameAndPasswordInitPayload: Equatable & Codable {
    let username: String
    let password: String
}

let server = GraphQLWS.Server<UsernameAndPasswordInitPayload>(
    messenger: messenger,
    onExecute: { ... },
    onSubscribe: { ... }
)
server.auth { payload in
    guard payload.username == "admin" else {
        throw Abort(.unauthorized)
    }
}
```

This example would require `connection_init` message from the client to look like this:

```json
{
    "type": "connection_init",
    "payload": {
        "username": "admin",
        "password": "supersafe"
    }
}
```

If the `payload` field is not required on your server, you may make Server's generic declaration optional like `Server<Payload?>`

## Memory Management

Memory ownership among the Server, Client, and Messenger may seem a little backwards. This is because the Swift/Vapor WebSocket 
implementation persists WebSocket objects long after their callback and they are expected to retain strong memory references to the 
objects required for responses. In order to align cleanly and avoid memory cycles, Server and Client are injected strongly into Messenger
callbacks, and only hold weak references to their Messenger. This means that Messenger objects (or their enclosing WebSocket) must
be persisted to have the connected Server or Client objects function. That is, if a Server's Messenger falls out of scope and deinitializes,
the Server will no longer respond to messages.
