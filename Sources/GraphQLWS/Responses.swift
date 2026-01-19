import Foundation
import GraphQL

/// A general response. This object's type is used to triage to other, more specific response objects.
public struct Response: Equatable, JsonEncodable {
    public let type: ResponseMessageType
}

/// A websocket `connection_ack` response from the server to the client
public struct ConnectionAckResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_CONNECTION_ACK
    public let payload: [String: Map]?

    public init(payload: [String: Map]?) {
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_CONNECTION_ACK {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_CONNECTION_ACK.type)`"
            ))
        }
        payload = try container.decodeIfPresent([String: Map].self, forKey: .payload)
    }
}

/// A websocket `connection_error` response from the server to the client
public struct ConnectionErrorResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_CONNECTION_ERROR
    public let payload: [String: Map]?

    public init(payload: [String: Map]? = nil) {
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_CONNECTION_ERROR {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_CONNECTION_ERROR.type)`"
            ))
        }
        payload = try container.decodeIfPresent([String: Map].self, forKey: .payload)
    }
}

/// A websocket `ka` response from the server to the client
public struct ConnectionKeepAliveResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_CONNECTION_KEEP_ALIVE
    public let payload: [String: Map]?

    public init(payload: [String: Map]?) {
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_CONNECTION_KEEP_ALIVE {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_CONNECTION_KEEP_ALIVE.type)`"
            ))
        }
        payload = try container.decodeIfPresent([String: Map].self, forKey: .payload)
    }
}

/// A websocket `data` response from the server to the client
public struct DataResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_DATA
    public let payload: GraphQLResult?
    public let id: String

    public init(payload: GraphQLResult?, id: String) {
        self.payload = payload
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_DATA {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_DATA.type)`"
            ))
        }
        payload = try container.decodeIfPresent(GraphQLResult.self, forKey: .payload)
        id = try container.decode(String.self, forKey: .id)
    }
}

/// A websocket `complete` response from the server to the client
public struct CompleteResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_COMPLETE
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_COMPLETE {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_COMPLETE.type)`"
            ))
        }
        id = try container.decode(String.self, forKey: .id)
    }
}

/// A websocket `error` response from the server to the client
public struct ErrorResponse: Equatable, JsonEncodable {
    public let type: ResponseMessageType = .GQL_ERROR
    public let payload: [GraphQLError]
    public let id: String

    init(_ errors: [Error], id: String) {
        let graphQLErrors = errors.map { error -> GraphQLError in
            switch error {
            case let graphQLError as GraphQLError:
                return graphQLError
            default:
                return GraphQLError(error)
            }
        }
        payload = graphQLErrors
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(ResponseMessageType.self, forKey: .type) != .GQL_ERROR {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(ResponseMessageType.GQL_ERROR.type)`"
            ))
        }
        payload = try container.decode([GraphQLError].self, forKey: .payload)
        id = try container.decode(String.self, forKey: .id)
    }
}

/// The supported websocket response message types from the server to the client
public struct ResponseMessageType: Equatable, Codable, Sendable {
    // This is implemented as a struct with only public static properties, backed by an internal enum
    // in order to grow the list of accepted response types in a non-breaking way.

    let type: ResponseType

    init(type: ResponseType) {
        self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        type = try container.decode(ResponseType.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(type)
    }

    public static let GQL_CONNECTION_ACK: Self = .init(type: .GQL_CONNECTION_ACK)
    public static let GQL_CONNECTION_ERROR: Self = .init(type: .GQL_CONNECTION_ERROR)
    public static let GQL_CONNECTION_KEEP_ALIVE: Self = .init(type: .GQL_CONNECTION_KEEP_ALIVE)
    public static let GQL_DATA: Self = .init(type: .GQL_DATA)
    public static let GQL_ERROR: Self = .init(type: .GQL_ERROR)
    public static let GQL_COMPLETE: Self = .init(type: .GQL_COMPLETE)

    enum ResponseType: String, Codable {
        case GQL_CONNECTION_ACK = "connection_ack"
        case GQL_CONNECTION_ERROR = "connection_error"
        case GQL_CONNECTION_KEEP_ALIVE = "ka"
        case GQL_DATA = "data"
        case GQL_ERROR = "error"
        case GQL_COMPLETE = "complete"
    }
}

/// A websocket `error` response from the server to the client that indicates an issue with encoding
/// a response JSON
struct EncodingErrorResponse: Equatable, Codable, JsonEncodable {
    let type: ResponseMessageType
    let payload: [String: String]

    init(_ errorMessage: String) {
        type = .GQL_ERROR
        payload = ["error": errorMessage]
    }
}
