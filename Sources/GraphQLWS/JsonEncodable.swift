import Foundation
import GraphQL

/// Indicates an object that can be converted into JSON for websocket messaging
protocol JsonEncodable: Codable {}

extension JsonEncodable {
    /// Converts the object into a JSON string
    /// - Parameter encoder: JSON Encoder used to encode the object into a string
    /// - Returns: The JSON string representation of the object, or an error JSON if not possible
    func toJSON(_ encoder: GraphQLJSONEncoder) -> String {
        let data: Data
        do {
            data = try encoder.encode(self)
        }
        catch {
            return EncodingErrorResponse("Unable to encode response").toJSON(encoder)
        }
        guard let body = String(data: data, encoding: .utf8) else {
            return EncodingErrorResponse("Encoded response can't be cast to string").toJSON(encoder)
        }
        return body
    }
}
