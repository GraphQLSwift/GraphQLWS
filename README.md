# GraphQLWS

This implements the [graphql-ws WebSocket subprotocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md).
It is mainly intended for server support, but there is a basic client implementation included.

Features:
- Server implementation that implements defined protocol conversations
- Server and Client message functions on messengers
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
            try await self.onReceive(message)
        }
    }

    func send<S>(_ message: S) async throws where S: Collection, S.Element == Character async throws {
        guard let websocket = websocket else { return }
        try await websocket.send(message)
    }

    func onReceive(callback: @escaping (String) async throws -> Void) {
        self.onReceive = callback
    }

    func error(_ message: String, code: Int) async throws {
        guard let websocket = websocket else { return }
        try await websocket.send("\(code): \(message)")
    }

    func close() async throws {
        guard let websocket = websocket else { return }
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
        messenger.registerServer(
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

messenger.registerServer(
    onExecute: { ... },
    onSubscribe: { ... },
    auth { (payload: UsernameAndPasswordInitPayload) in
        guard payload.username == "admin" else {
            throw Abort(.unauthorized)
        }
    }
)
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
