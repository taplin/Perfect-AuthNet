import Foundation

/// A client for the Authorize.net JSON API (the modern `request.api` endpoint).
///
/// The client is a value type holding your merchant credentials, the target
/// environment, and a `URLSession`. All methods are async and safe to call
/// concurrently.
///
/// ```swift
/// let client = AuthNetClient(
///     loginID: "your_api_login_id",
///     transactionKey: "your_transaction_key",
///     environment: .sandbox
/// )
///
/// // Mobile/web: charge a tokenized nonce from Accept.js / Accept Mobile.
/// let result = try await client.charge(
///     amount: 49.99,
///     payment: .nonce(value: opaqueDataValueFromClient),
///     order: OrderInfo(invoiceNumber: "INV-1001", description: "Scrubs set")
/// )
/// if result.approved {
///     print("charged, txn \(result.transactionID)")
/// } else {
///     print("declined: \(result.error ?? "unknown")")
/// }
/// ```
public struct AuthNetClient: Sendable {
    public let environment: AuthNetEnvironment
    private let loginID: String
    private let transactionKey: String
    private let urlSession: URLSession

    /// - Parameters:
    ///   - loginID: Your API Login ID.
    ///   - transactionKey: Your Transaction Key.
    ///   - environment: Sandbox or production. Defaults to `.sandbox`.
    ///   - urlSession: Custom session for pinning/testing. Defaults to `.shared`.
    public init(loginID: String, transactionKey: String,
                environment: AuthNetEnvironment = .sandbox,
                urlSession: URLSession = .shared) {
        self.loginID = loginID
        self.transactionKey = transactionKey
        self.environment = environment
        self.urlSession = urlSession
    }

    // MARK: - Transactions

    /// Authorizes and captures a payment in one step (a standard "charge").
    public func charge(amount: Decimal, payment: PaymentInput,
                       order: OrderInfo? = nil, billTo: BillingAddress? = nil,
                       refId: String? = nil) async throws -> TransactionResult {
        let body = TransactionRequestBody(
            transactionType: TransactionType.authCapture.rawValue,
            amount: Self.formatAmount(amount),
            payment: PaymentPayload(payment),
            refTransId: nil, order: order, billTo: billTo
        )
        return try await send(body, refId: refId)
    }

    /// Authorizes a payment without capturing it. Capture later with ``capture(transactionID:amount:)``.
    public func authorize(amount: Decimal, payment: PaymentInput,
                          order: OrderInfo? = nil, billTo: BillingAddress? = nil,
                          refId: String? = nil) async throws -> TransactionResult {
        let body = TransactionRequestBody(
            transactionType: TransactionType.authOnly.rawValue,
            amount: Self.formatAmount(amount),
            payment: PaymentPayload(payment),
            refTransId: nil, order: order, billTo: billTo
        )
        return try await send(body, refId: refId)
    }

    /// Captures a previously authorized transaction.
    /// - Parameter amount: Optional lower amount; omit to capture the full authorized amount.
    public func capture(transactionID: String, amount: Decimal? = nil,
                        refId: String? = nil) async throws -> TransactionResult {
        let body = TransactionRequestBody(
            transactionType: TransactionType.priorAuthCapture.rawValue,
            amount: amount.map(Self.formatAmount),
            payment: nil,
            refTransId: transactionID, order: nil, billTo: nil
        )
        return try await send(body, refId: refId)
    }

    /// Refunds a settled transaction. Authorize.net requires the original card's
    /// last four digits and expiration to refund against it.
    public func refund(transactionID: String, amount: Decimal,
                       cardLastFour: String, expiration: String,
                       refId: String? = nil) async throws -> TransactionResult {
        let body = TransactionRequestBody(
            transactionType: TransactionType.refund.rawValue,
            amount: Self.formatAmount(amount),
            payment: PaymentPayload(.creditCard(number: cardLastFour, expiration: expiration)),
            refTransId: transactionID, order: nil, billTo: nil
        )
        return try await send(body, refId: refId)
    }

    /// Voids an unsettled transaction (cancels it before it settles).
    public func void(transactionID: String, refId: String? = nil) async throws -> TransactionResult {
        let body = TransactionRequestBody(
            transactionType: TransactionType.void.rawValue,
            amount: nil, payment: nil,
            refTransId: transactionID, order: nil, billTo: nil
        )
        return try await send(body, refId: refId)
    }

    // MARK: - Transport

    private func send(_ transaction: TransactionRequestBody, refId: String?) async throws -> TransactionResult {
        let envelope = CreateTransactionRequest(
            createTransactionRequest: .init(
                merchantAuthentication: MerchantAuthentication(name: loginID, transactionKey: transactionKey),
                refId: refId,
                transactionRequest: transaction
            )
        )

        var request = URLRequest(url: environment.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(envelope)
        } catch {
            throw AuthNetError.decoding("request encoding failed: \(error)")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthNetError.network("\(error)")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthNetError.invalidResponse
        }
        return try Self.decodeTransaction(data)
    }

    // MARK: - Decoding & helpers (internal for testing)

    /// Decodes a gateway response into a ``TransactionResult``.
    /// Throws ``AuthNetError/apiError(code:text:)`` when the gateway rejected the
    /// request without processing a transaction (e.g. bad credentials).
    static func decodeTransaction(_ raw: Data) throws -> TransactionResult {
        let data = stripBOM(raw)
        let api: TransactionApiResponse
        do {
            api = try JSONDecoder().decode(TransactionApiResponse.self, from: data)
        } catch {
            throw AuthNetError.decoding("\(error)")
        }

        guard let tr = api.transactionResponse, tr.responseCode != nil else {
            // No transaction processed — surface the gateway-level message.
            let msg = api.messages.message.first
            throw AuthNetError.apiError(code: msg?.code ?? "Unknown",
                                        text: msg?.text ?? "Gateway returned no transactionResponse.")
        }

        let code = ResponseCode(rawValue: tr.responseCode ?? "") ?? .error
        return TransactionResult(
            responseCode: code,
            transactionID: tr.transId ?? "",
            authCode: tr.authCode,
            accountNumber: tr.accountNumber,
            accountType: tr.accountType,
            avsResultCode: tr.avsResultCode,
            cvvResultCode: tr.cvvResultCode,
            message: tr.messages?.first.map { "\($0.code): \($0.description)" },
            error: tr.errors?.first.map { "\($0.errorCode): \($0.errorText)" }
        )
    }

    /// Authorize.net prefixes JSON responses with a UTF-8 BOM, which `JSONDecoder`
    /// chokes on. Strip any leading BOM/whitespace before decoding.
    static func stripBOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.starts(with: bom) {
            return data.subdata(in: data.index(data.startIndex, offsetBy: 3)..<data.endIndex)
        }
        return data
    }

    /// Formats a `Decimal` as a fixed two-decimal string (`"49.99"`), locale-independent.
    static func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00"
    }
}
