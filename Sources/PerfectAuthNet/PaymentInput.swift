import Foundation

/// How a payment is funded for a transaction.
///
/// For a mobile or web storefront, prefer ``opaqueData(descriptor:value:)`` (or
/// the ``nonce(value:descriptor:)`` convenience): the client SDK (Accept.js /
/// Accept Mobile) tokenizes the card and your backend never handles the raw PAN,
/// which keeps you out of most PCI scope. Use ``creditCard(number:expiration:code:)``
/// only for server-to-server flows or testing.
public enum PaymentInput: Sendable {
    /// A raw card. `expiration` is `YYYY-MM` (e.g. `"2027-12"`); `code` is the CVV/CVC.
    case creditCard(number: String, expiration: String, code: String? = nil)

    /// A payment nonce produced by Accept.js / Accept Mobile.
    /// `descriptor` is the data descriptor; `value` is the opaque data value.
    case opaqueData(descriptor: String, value: String)

    /// Convenience for an in-app/web Accept payment nonce, defaulting the
    /// descriptor to `COMMON.ACCEPT.INAPP.PAYMENT`.
    public static func nonce(value: String,
                             descriptor: String = "COMMON.ACCEPT.INAPP.PAYMENT") -> PaymentInput {
        .opaqueData(descriptor: descriptor, value: value)
    }
}

/// The `payment` object as the Authorize.net JSON API expects it. Internal —
/// callers use ``PaymentInput``.
struct PaymentPayload: Encodable {
    let creditCard: CreditCard?
    let opaqueData: OpaqueData?

    struct CreditCard: Encodable {
        let cardNumber: String
        let expirationDate: String
        let cardCode: String?
    }
    struct OpaqueData: Encodable {
        let dataDescriptor: String
        let dataValue: String
    }

    init(_ input: PaymentInput) {
        switch input {
        case .creditCard(let number, let expiration, let code):
            creditCard = CreditCard(cardNumber: number, expirationDate: expiration, cardCode: code)
            opaqueData = nil
        case .opaqueData(let descriptor, let value):
            creditCard = nil
            opaqueData = OpaqueData(dataDescriptor: descriptor, dataValue: value)
        }
    }
}

/// Optional billing address attached to a transaction.
public struct BillingAddress: Sendable, Encodable {
    public var firstName: String?
    public var lastName: String?
    public var company: String?
    public var address: String?
    public var city: String?
    public var state: String?
    public var zip: String?
    public var country: String?

    public init(firstName: String? = nil, lastName: String? = nil, company: String? = nil,
                address: String? = nil, city: String? = nil, state: String? = nil,
                zip: String? = nil, country: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.address = address
        self.city = city
        self.state = state
        self.zip = zip
        self.country = country
    }
}

/// Optional order metadata (invoice number + description) attached to a transaction.
public struct OrderInfo: Sendable, Encodable {
    public var invoiceNumber: String?
    public var description: String?

    public init(invoiceNumber: String? = nil, description: String? = nil) {
        self.invoiceNumber = invoiceNumber
        self.description = description
    }
}
