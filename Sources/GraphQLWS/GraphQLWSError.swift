import GraphQL

struct GraphQLWSError: Error {
    let message: String
    let code: ErrorCode
    
    init(_ message: String, code: ErrorCode) {
        self.message = message
        self.code = code
    }
    
    static func unauthorized() -> Self {
        return self.init(
            "Unauthorized",
            code: .unauthorized
        )
    }
    
    static func notInitialized() -> Self {
        return self.init(
            "Connection not initialized",
            code: .notInitialized
        )
    }
    
    static func tooManyInitializations() -> Self {
        return self.init(
            "Too many initialisation requests",
            code: .tooManyInitializations
        )
    }
    
    static func subscriberAlreadyExists(id: String) -> Self {
        return self.init(
            "Subscriber for \(id) already exists",
            code: .subscriberAlreadyExists
        )
    }
    
    static func invalidEncoding() -> Self {
        return self.init(
            "Message was not encoded in UTF8",
            code: .invalidEncoding
        )
    }
    
    static func noType() -> Self {
        return self.init(
            "Message has no 'type' field",
            code: .noType
        )
    }
    
    static func invalidType() -> Self {
        return self.init(
            "Message 'type' value does not match supported types",
            code: .invalidType
        )
    }
    
    static func invalidRequestFormat(messageType: RequestMessageType) -> Self {
        return self.init(
            "Request message doesn't match '\(messageType.rawValue)' JSON format",
            code: .invalidRequestFormat
        )
    }
    
    static func invalidResponseFormat(messageType: ResponseMessageType) -> Self {
        return self.init(
            "Response message doesn't match '\(messageType.rawValue)' JSON format",
            code: .invalidResponseFormat
        )
    }
    
    static func internalAPIStreamIssue(errors: [GraphQLError]) -> Self {
        return self.init(
            "API Response did not result in a stream type, contained errors\n\(errors.map { $0.message}.joined(separator: "\n"))",
            code: .internalAPIStreamIssue
        )
    }
    
    static func graphQLError(_ error: Error) -> Self {
        return self.init(
            "\(error)",
            code: .graphQLError
        )
    }
}

/// Error codes for miscellaneous issues
public enum ErrorCode: Int, CustomStringConvertible {
    // Miscellaneous
    case miscellaneous = 4400
    
    // Internal errors
    case graphQLError = 4401
    case internalAPIStreamIssue = 4402
    
    // Message errors
    case invalidEncoding = 4410
    case noType = 4411
    case invalidType = 4412
    case invalidRequestFormat = 4413
    case invalidResponseFormat = 4414
    
    // Initialization errors
    case unauthorized = 4430
    case notInitialized = 4431
    case tooManyInitializations = 4432
    case subscriberAlreadyExists = 4433
    
    public var description: String {
        return "\(self.rawValue)"
    }
}
