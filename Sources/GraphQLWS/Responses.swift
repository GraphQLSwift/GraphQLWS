// Copyright (c) 2021 PassiveLogic, Inc.

import Foundation
import GraphQL

/// Reference for graphql-ws protocol: https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md

/// A general response. This object's type is used to triage to other, more specific response objects.
struct Response: Equatable, JsonEncodable {
    let type: ResponseMessageType
}

/// A websocket `connection_ack` response from the server to the client
struct ConnectionAckResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [String: Map]?
    
    init(_ payload: [String: Map]? = nil) {
        self.type = .GQL_CONNECTION_ACK
        self.payload = payload
    }
}

/// A websocket `connection_error` response from the server to the client
struct ConnectionErrorResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [String: Map]?
    
    init(_ payload: [String: Map]? = nil) {
        self.type = .GQL_CONNECTION_ERROR
        self.payload = payload
    }
}

/// A websocket `ka` response from the server to the client
struct ConnectionKeepAliveResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [String: Map]?
    
    init(_ payload: [String: Map]? = nil) {
        self.type = .GQL_CONNECTION_KEEP_ALIVE
        self.payload = payload
    }
}

/// A websocket `data` response from the server to the client
struct DataResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let payload: GraphQLResult?
    let id: String
    
    init(_ payload: GraphQLResult? = nil, id: String) {
        self.type = .GQL_DATA
        self.payload = payload
        self.id = id
    }
}

/// A websocket `complete` response from the server to the client
struct CompleteResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let id: String
    
    init(_: GraphQLResult? = nil, id: String) {
        self.type = .GQL_COMPLETE
        self.id = id
    }
}

/// A websocket `error` response from the server to the client
struct ErrorResponse: Equatable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [GraphQLError]
    let id: String
    
    init(_ errors: [Error], id: String) {
        let graphQLErrors = errors.map { error -> GraphQLError in
            switch error {
                case let graphQLError as GraphQLError:
                    return graphQLError
                default:
                    return GraphQLError(error)
            }
        }
        self.type = .GQL_ERROR
        self.payload = graphQLErrors
        self.id = id
    }
    
    init(_ error: Error, id: String) {
        self.init([error], id: id)
    }
    
    init(_ errorMessage: String, id: String) {
        self.init(GraphQLError(message: errorMessage), id: id)
    }
}

/// The supported websocket response message types from the server to the client
enum ResponseMessageType: String, Codable {
    case GQL_CONNECTION_ACK = "connection_ack"
    case GQL_CONNECTION_ERROR = "connection_error"
    case GQL_CONNECTION_KEEP_ALIVE = "ka"
    case GQL_DATA = "data"
    case GQL_ERROR = "error"
    case GQL_COMPLETE = "complete"
    case unknown
    
    init(from decoder: Decoder) throws {
        guard let value = try? decoder.singleValueContainer().decode(String.self) else {
            self = .unknown
            return
        }
        self = ResponseMessageType(rawValue: value) ?? .unknown
    }
}

/// A websocket `error` response from the server to the client that indicates an issue with encoding
/// a response JSON
struct EncodingErrorResponse: Equatable, Codable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [String: String]
    
    init(_ errorMessage: String) {
        self.type = .GQL_ERROR
        self.payload = ["error": errorMessage]
    }
}
