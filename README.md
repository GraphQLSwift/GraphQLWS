# GraphQLWS

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2FGraphQLWS%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/GraphQLSwift/GraphQLWS)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2FGraphQLWS%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/GraphQLSwift/GraphQLWS)

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
.package(url: "https://github.com/GraphQLSwift/GraphQLWS", from: "<version>"),
```

Then create a concrete type that conforms to the `Messenger` protocol. Here's an example using
[`WebSocketKit`](https://github.com/vapor/websocket-kit):

```swift
import WebSocketKit
import GraphQLWS

/// Messenger wrapper for WebSockets
struct WebSocketMessenger: Messenger {
    let websocket: WebSocket

    func send(_ message: Data) async throws {
        try await websocket.send(String(decoding: message, as: UTF8.self))
    }

    func error(_ message: String, code: Int) async throws {
        try await websocket.close(code: code)
    }

    func close() async throws {
        try await websocket.close()
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
                try await api.execute(
                    request: graphQLRequest.query,
                    context: context,
                    on: self.eventLoop,
                    variables: graphQLRequest.variables,
                    operationName: graphQLRequest.operationName
                )
            },
            onSubscribe: { graphQLRequest in
                try await api.subscribe(
                    request: graphQLRequest.query,
                    context: context,
                    on: self.eventLoop,
                    variables: graphQLRequest.variables,
                    operationName: graphQLRequest.operationName
                )
            }
        )
        let incoming = AsyncStream<Data> { continuation in
            websocket.onText { _, message in
                continuation.yield(Data(message.utf8))
            }
        }
        try await server.listen(to: incoming)
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
