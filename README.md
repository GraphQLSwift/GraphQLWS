# GraphQLWS

This implements the [graphql-ws WebSocket subprotocol](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md).
It is mainly intended for Server support, but there is a basic client implementation included.

Features:
- Server implementation that implements defined protocol conversations
- Client and Server types that wrap messengers
- Codable Server and Client message structures

## Memory Management

Memory ownership among the Server, Client, and Messager may seem a little backwards. This is because the Swift/Vapor WebSocket 
implementation persists WebSocket objects long after their callback and they are expected to retain strong memory references to the 
objects required for responses. In order to align cleanly and avoid memory cycles, Server and Client are injected strongly into Messager
callbacks, and only hold weak references to their Messager. This means that Messager objects (or their enclosing WebSocket) must
be persisted to have the connected Server or Client objects function. That is, if a Server's Messager falls out of scope and deinitializes,
the Server will no longer respond to messages.
