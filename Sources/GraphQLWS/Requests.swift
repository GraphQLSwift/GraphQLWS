import Foundation
import GraphQL

/// A general request. This object's type is used to triage to other, more specific request objects.
public struct Request: Equatable, JsonEncodable {
    public let type: RequestMessageType
}

/// A websocket `connection_init` request from the client to the server
public struct ConnectionInitRequest<InitPayload: Codable & Equatable>: Equatable, JsonEncodable {
    public let type: RequestMessageType = .GQL_CONNECTION_INIT
    public let payload: InitPayload

    public init(payload: InitPayload) {
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(RequestMessageType.self, forKey: .type) != .GQL_CONNECTION_INIT {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(RequestMessageType.GQL_CONNECTION_INIT.type)`"
            ))
        }
        payload = try container.decode(InitPayload.self, forKey: .payload)
    }
}

/// A websocket `start` request from the client to the server
public struct StartRequest: Equatable, JsonEncodable {
    public let type: RequestMessageType = .GQL_START
    public let payload: GraphQLRequest
    public let id: String

    public init(payload: GraphQLRequest, id: String) {
        self.payload = payload
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(RequestMessageType.self, forKey: .type) != .GQL_START {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(RequestMessageType.GQL_START.type)`"
            ))
        }
        payload = try container.decode(GraphQLRequest.self, forKey: .payload)
        id = try container.decode(String.self, forKey: .id)
    }
}

/// A websocket `stop` request from the client to the server
public struct StopRequest: Equatable, JsonEncodable {
    public let type: RequestMessageType = .GQL_STOP
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(RequestMessageType.self, forKey: .type) != .GQL_CONNECTION_TERMINATE {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(RequestMessageType.GQL_STOP.type)`"
            ))
        }
        id = try container.decode(String.self, forKey: .id)
    }
}

/// A websocket `connection_terminate` request from the client to the server
public struct ConnectionTerminateRequest: Equatable, JsonEncodable {
    public let type: RequestMessageType = .GQL_CONNECTION_TERMINATE

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Self.CodingKeys.self)
        if try container.decode(RequestMessageType.self, forKey: .type) != .GQL_CONNECTION_TERMINATE {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "type must be `\(RequestMessageType.GQL_CONNECTION_TERMINATE.type)`"
            ))
        }
    }
}

/// The supported websocket request message types from the client to the server
public struct RequestMessageType: Equatable, Codable, Sendable {
    // This is implemented as a struct with only public static properties, backed by an internal enum
    // in order to grow the list of accepted response types in a non-breaking way.

    let type: RequestType

    init(type: RequestType) {
        self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        type = try container.decode(RequestType.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(type)
    }

    public static let GQL_CONNECTION_INIT: Self = .init(type: .GQL_CONNECTION_INIT)
    public static let GQL_START: Self = .init(type: .GQL_START)
    public static let GQL_STOP: Self = .init(type: .GQL_STOP)
    public static let GQL_CONNECTION_TERMINATE: Self = .init(type: .GQL_CONNECTION_TERMINATE)

    enum RequestType: String, Codable {
        case GQL_CONNECTION_INIT = "connection_init"
        case GQL_START = "start"
        case GQL_STOP = "stop"
        case GQL_CONNECTION_TERMINATE = "connection_terminate"
    }
}
