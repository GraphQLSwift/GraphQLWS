// Copyright (c) 2021 PassiveLogic, Inc.

struct GraphQLWSError: Error {
    let message: String
    let code: Int
    
    init(_ message: String, code: Int) {
        self.message = message
        self.code = code
    }
    
    static func unauthorized() -> Self {
        return self.init(
            "Unauthorized",
            code: 4401
        )
    }
    
    static func tooManyInitializations() -> Self {
        return self.init(
            "Too many initialisation requests",
            code: 4429
        )
    }
    
    static func notInitialized() -> Self {
        return self.init(
            "Connection not initialized",
            code: 4407
        )
    }
    
    static func subscriberAlreadyExists(id: String) -> Self {
        return self.init(
            "Subscriber for \(id) already exists",
            code: 4409
        )
    }
    
    static func invalidEncoding() -> Self {
        return self.init(
            "Message was not encoded in UTF8",
            code: 4400
        )
    }
    
    static func noType() -> Self {
        return self.init(
            "Message has no 'type' field",
            code: 4400
        )
    }
    
    static func invalidType() -> Self {
        return self.init(
            "Message 'type' value does not match supported types",
            code: 4400
        )
    }
    
    static func invalidRequestFormat(messageType: RequestMessageType) -> Self {
        return self.init(
            "Request message doesn't match '\(messageType.rawValue)' JSON format",
            code: 4400
        )
    }
    
    static func invalidResponseFormat(messageType: ResponseMessageType) -> Self {
        return self.init(
            "Response message doesn't match '\(messageType.rawValue)' JSON format",
            code: 4400
        )
    }
    
    static func internalAPIStreamIssue() -> Self {
        return self.init(
            "API Response did not result in a stream type",
            code: 4400
        )
    }
    
    static func graphQLError(_ error: Error) -> Self {
        return self.init(
            "\(error)",
            code: 4400
        )
    }
}
