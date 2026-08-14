import Foundation

/// Everything that can go wrong talking to the Porto Bus API, in terms a
/// ViewModel can turn into a message without knowing about URLSession.
public enum APIError: Error, Sendable {
    /// The base URL in settings couldn't be combined with the path into a valid URL.
    case invalidURL
    /// The request failed before a response (offline, connection refused, ATS block).
    case transport(String)
    /// A non-2xx HTTP status. `body` is the truncated response text, when any.
    case http(status: Int, body: String?)
    /// 2xx but the body didn't match the expected shape.
    case decoding(String)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address looks wrong. Check it in Settings."
        case .transport:
            return "Couldn't reach the server. Check your connection and the server address."
        case .http(let status, _):
            switch status {
            case 404: return "Not found."
            case 400: return "That request wasn't valid."
            case 502: return "The bus service upstream isn't responding right now."
            default:  return "The server returned an error (\(status))."
            }
        case .decoding:
            return "The server sent something unexpected."
        }
    }

    /// Detail for logs/diagnostics — not shown to riders.
    public var diagnostic: String {
        switch self {
        case .invalidURL: return "invalidURL"
        case .transport(let m): return "transport: \(m)"
        case .http(let s, let b): return "http \(s): \(b ?? "<no body>")"
        case .decoding(let m): return "decoding: \(m)"
        }
    }
}
