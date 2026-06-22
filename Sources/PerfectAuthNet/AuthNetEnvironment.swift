import Foundation

/// Selects which Authorize.net gateway the client talks to.
///
/// Both environments use the same JSON API shape; only the host differs. Use
/// ``sandbox`` with sandbox credentials during development, ``production`` with
/// live credentials when going live.
public enum AuthNetEnvironment: Sendable {
    /// The sandbox gateway (`apitest.authorize.net`). Pair with sandbox credentials.
    case sandbox
    /// The live gateway (`api.authorize.net`). Pair with production credentials.
    case production

    /// The full endpoint URL all requests are POSTed to.
    ///
    /// Despite the `/xml/` path, this endpoint accepts and returns JSON when the
    /// request carries `Content-Type: application/json`.
    var endpoint: URL {
        switch self {
        case .sandbox:    return URL(string: "https://apitest.authorize.net/xml/v1/request.api")!
        case .production: return URL(string: "https://api.authorize.net/xml/v1/request.api")!
        }
    }
}
