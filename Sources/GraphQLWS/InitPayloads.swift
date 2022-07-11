// Contains convenient `connection_init` payloads for users of this package

/// `connection_init` `payload` that is empty
public struct EmptyInitPayload: Equatable & Codable { }

/// `connection_init` `payload` that includes an `authToken` field
public struct TokenInitPayload: Equatable & Codable {
    public let authToken: String
    
    public init(authToken: String) {
        self.authToken = authToken
    }
}
