import Foundation

// MARK: - Request models (Encodable → Authorize.net JSON)

/// Root `createTransactionRequest` envelope.
struct CreateTransactionRequest: Encodable {
    let createTransactionRequest: Body

    struct Body: Encodable {
        let merchantAuthentication: MerchantAuthentication
        let refId: String?
        let transactionRequest: TransactionRequestBody
    }
}

struct MerchantAuthentication: Encodable {
    let name: String
    let transactionKey: String
}

/// The `transactionRequest` object. Field set varies by `transactionType`;
/// unused fields are nil and omitted from the JSON.
struct TransactionRequestBody: Encodable {
    let transactionType: String
    let amount: String?
    let payment: PaymentPayload?
    let refTransId: String?
    let order: OrderInfo?
    let billTo: BillingAddress?
}

/// The Authorize.net transaction type strings.
enum TransactionType: String {
    case authCapture     = "authCaptureTransaction"
    case authOnly        = "authOnlyTransaction"
    case priorAuthCapture = "priorAuthCaptureTransaction"
    case refund          = "refundTransaction"
    case void            = "voidTransaction"
}

// MARK: - Response models (Decodable ← Authorize.net JSON)

struct TransactionApiResponse: Decodable {
    let transactionResponse: TransactionResponseBody?
    let refId: String?
    let messages: Messages

    struct Messages: Decodable {
        let resultCode: String     // "Ok" or "Error"
        let message: [Message]
        struct Message: Decodable {
            let code: String
            let text: String
        }
    }
}

struct TransactionResponseBody: Decodable {
    let responseCode: String?
    let authCode: String?
    let avsResultCode: String?
    let cvvResultCode: String?
    let transId: String?
    let accountNumber: String?
    let accountType: String?
    let messages: [Msg]?
    let errors: [Err]?

    struct Msg: Decodable {
        let code: String
        let description: String
    }
    struct Err: Decodable {
        let errorCode: String
        let errorText: String
    }
}

// MARK: - Public result

/// The outcome of a processed transaction.
///
/// A `responseCode` of ``ResponseCode/approved`` means the charge succeeded;
/// ``ResponseCode/declined`` and ``ResponseCode/heldForReview`` are normal
/// business outcomes (check ``message``/``error`` for the reason), not thrown errors.
public struct TransactionResult: Sendable, Equatable {
    public let responseCode: ResponseCode
    /// The gateway transaction id — needed to later capture, refund, or void.
    public let transactionID: String
    public let authCode: String?
    /// Masked account number, e.g. `"XXXX1111"`.
    public let accountNumber: String?
    /// Card brand, e.g. `"Visa"`.
    public let accountType: String?
    public let avsResultCode: String?
    public let cvvResultCode: String?
    /// Human-readable gateway message (`"code: description"`), when present.
    public let message: String?
    /// First error detail (`"code: text"`) for declines/errors, when present.
    public let error: String?

    /// `true` only when the transaction was approved.
    public var approved: Bool { responseCode == .approved }
}

/// Authorize.net `transactionResponse.responseCode` values.
public enum ResponseCode: String, Sendable, Equatable {
    case approved      = "1"
    case declined      = "2"
    case error         = "3"
    case heldForReview = "4"
}
