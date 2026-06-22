import Foundation

/// Errors thrown by ``AuthNetClient``.
///
/// A *declined* card is **not** an error — it comes back as a
/// ``TransactionResult`` with ``TransactionResult/approved`` `== false`. These
/// cases cover transport problems, malformed responses, and gateway-level
/// failures (bad credentials, validation errors) where no transaction was
/// processed at all.
public enum AuthNetError: Error, Sendable, Equatable {
    /// The underlying URLSession request failed (no/again network, TLS, etc.).
    case network(String)

    /// The HTTP response was missing, non-200, or otherwise unusable.
    case invalidResponse

    /// The response body could not be decoded as a known Authorize.net payload.
    case decoding(String)

    /// The gateway rejected the request before processing a transaction.
    /// `code` is the Authorize.net message code (e.g. `E00007` for bad auth).
    case apiError(code: String, text: String)
}

extension AuthNetError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .network(let m):              return "Network error: \(m)"
        case .invalidResponse:             return "Invalid response from gateway."
        case .decoding(let m):             return "Failed to decode gateway response: \(m)"
        case .apiError(let code, let text): return "Gateway error [\(code)]: \(text)"
        }
    }
}
