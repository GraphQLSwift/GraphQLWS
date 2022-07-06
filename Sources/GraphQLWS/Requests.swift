// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL

/// We also require that an 'authToken' field is provided in the 'payload' during the connection
/// init message. For example:
/// ```
/// {
///     "type": 'connection_init',
///     "payload": {
///         "authToken": "eyJhbGciOiJIUz..."
///     }
/// }
/// ```

/// A general request. This object's type is used to triage to other, more specific request objects.
struct Request: Equatable, JsonEncodable {
    let type: RequestMessageType
}

/// A websocket `connection_init` request from the client to the server
public struct ConnectionInitRequest<InitPayload: Codable & Equatable>: Equatable, JsonEncodable {
    var type = RequestMessageType.GQL_CONNECTION_INIT
    let payload: InitPayload
}

/// A websocket `start` request from the client to the server
struct StartRequest: Equatable, JsonEncodable {
    var type = RequestMessageType.GQL_START
    let payload: GraphQLRequest
    let id: String
}

/// A websocket `stop` request from the client to the server
struct StopRequest: Equatable, JsonEncodable {
    var type = RequestMessageType.GQL_STOP
    let id: String
}

/// A websocket `connection_terminate` request from the client to the server
struct ConnectionTerminateRequest: Equatable, JsonEncodable {
    var type = RequestMessageType.GQL_CONNECTION_TERMINATE
}

/// The supported websocket request message types from the client to the server
enum RequestMessageType: String, Codable {
    case GQL_CONNECTION_INIT = "connection_init"
    case GQL_START = "start"
    case GQL_STOP = "stop"
    case GQL_CONNECTION_TERMINATE = "connection_terminate"
    case unknown
    
    init(from decoder: Decoder) throws {
        guard let value = try? decoder.singleValueContainer().decode(String.self) else {
            self = .unknown
            return
        }
        self = RequestMessageType(rawValue: value) ?? .unknown
    }
}
