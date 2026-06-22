import Testing
import Foundation
@testable import PerfectAuthNet

// MARK: - URLProtocol mock (captures the outgoing request, returns a canned response)

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(from: request)
        Self.lastBody = body
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request, body)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession converts `httpBody` to a stream, so read the stream when needed.
    static func bodyData(from request: URLRequest) -> Data? {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite(.serialized)
struct PerfectAuthNetTests {

    // MARK: Helpers

    private func makeClient(
        environment: AuthNetEnvironment = .sandbox,
        handler: @escaping @Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data)
    ) -> AuthNetClient {
        MockURLProtocol.lastBody = nil
        MockURLProtocol.requestHandler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return AuthNetClient(loginID: "login", transactionKey: "key",
                             environment: environment, urlSession: session)
    }

    private func okResponse(_ body: String) -> @Sendable (URLRequest, Data?) -> (HTTPURLResponse, Data) {
        { req, _ in
            let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, Data(body.utf8))
        }
    }

    private func bodyJSON() -> [String: Any] {
        guard let data = MockURLProtocol.lastBody,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    // Navigate nested dictionaries: dig(json, "a", "b", "c")
    private func dig(_ root: [String: Any], _ keys: String...) -> Any? {
        var current: Any? = root
        for key in keys {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }

    // Sample gateway responses (BOM-prefixed, like the real API).
    private let approvedJSON = "\u{FEFF}" + """
    {"transactionResponse":{"responseCode":"1","authCode":"ABC123","avsResultCode":"Y","cvvResultCode":"P","transId":"40000000001","accountNumber":"XXXX1111","accountType":"Visa","messages":[{"code":"1","description":"This transaction has been approved."}]},"refId":"INV-1001","messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}
    """

    private let declinedJSON = """
    {"transactionResponse":{"responseCode":"2","authCode":"","transId":"40000000002","accountNumber":"XXXX0001","accountType":"Visa","errors":[{"errorCode":"2","errorText":"This transaction has been declined."}]},"messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}
    """

    private let authFailureJSON = """
    {"messages":{"resultCode":"Error","message":[{"code":"E00007","text":"User authentication failed due to invalid authentication values."}]}}
    """

    // MARK: Pure unit tests

    @Test func environmentEndpoints() {
        #expect(AuthNetEnvironment.sandbox.endpoint.absoluteString == "https://apitest.authorize.net/xml/v1/request.api")
        #expect(AuthNetEnvironment.production.endpoint.absoluteString == "https://api.authorize.net/xml/v1/request.api")
    }

    @Test func amountFormattingIsFixedTwoDecimals() {
        #expect(AuthNetClient.formatAmount(Decimal(string: "49.9")!) == "49.90")
        #expect(AuthNetClient.formatAmount(10) == "10.00")
        #expect(AuthNetClient.formatAmount(Decimal(string: "1234.5")!) == "1234.50")
        #expect(AuthNetClient.formatAmount(Decimal(string: "0")!) == "0.00")
    }

    @Test func stripBOMRemovesLeadingMarker() {
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data("{}".utf8)
        #expect(AuthNetClient.stripBOM(withBOM) == Data("{}".utf8))
        let without = Data("{}".utf8)
        #expect(AuthNetClient.stripBOM(without) == without)
    }

    @Test func decodeApprovedResponse() throws {
        let result = try AuthNetClient.decodeTransaction(Data(approvedJSON.utf8))
        #expect(result.approved)
        #expect(result.responseCode == .approved)
        #expect(result.transactionID == "40000000001")
        #expect(result.authCode == "ABC123")
        #expect(result.accountNumber == "XXXX1111")
        #expect(result.accountType == "Visa")
    }

    @Test func decodeDeclinedResponseIsNotApproved() throws {
        let result = try AuthNetClient.decodeTransaction(Data(declinedJSON.utf8))
        #expect(!result.approved)
        #expect(result.responseCode == .declined)
        #expect(result.error == "2: This transaction has been declined.")
    }

    @Test func decodeAuthFailureThrowsApiError() {
        #expect(throws: AuthNetError.apiError(code: "E00007",
                text: "User authentication failed due to invalid authentication values.")) {
            _ = try AuthNetClient.decodeTransaction(Data(authFailureJSON.utf8))
        }
    }

    // MARK: Full-path tests via mock transport

    @Test func chargeApprovedReturnsResultAndSendsCorrectJSON() async throws {
        let client = makeClient(handler: okResponse(approvedJSON))
        let result = try await client.charge(
            amount: Decimal(string: "49.99")!,
            payment: .creditCard(number: "4111111111111111", expiration: "2027-12", code: "123"),
            order: OrderInfo(invoiceNumber: "INV-1001", description: "Scrubs set")
        )
        #expect(result.approved)
        #expect(result.transactionID == "40000000001")

        let json = bodyJSON()
        #expect(dig(json, "createTransactionRequest", "merchantAuthentication", "name") as? String == "login")
        #expect(dig(json, "createTransactionRequest", "transactionRequest", "transactionType") as? String == "authCaptureTransaction")
        #expect(dig(json, "createTransactionRequest", "transactionRequest", "amount") as? String == "49.99")
        #expect(dig(json, "createTransactionRequest", "transactionRequest", "payment", "creditCard", "cardNumber") as? String == "4111111111111111")
        #expect(dig(json, "createTransactionRequest", "transactionRequest", "order", "invoiceNumber") as? String == "INV-1001")
    }

    @Test func chargeWithNonceSendsOpaqueData() async throws {
        let client = makeClient(handler: okResponse(approvedJSON))
        _ = try await client.charge(amount: 20, payment: .nonce(value: "eyJ0b2tlbiI6IjEyMyJ9"))

        let payment = dig(bodyJSON(), "createTransactionRequest", "transactionRequest", "payment") as? [String: Any]
        let opaque = payment?["opaqueData"] as? [String: Any]
        #expect(opaque?["dataDescriptor"] as? String == "COMMON.ACCEPT.INAPP.PAYMENT")
        #expect(opaque?["dataValue"] as? String == "eyJ0b2tlbiI6IjEyMyJ9")
        #expect(payment?["creditCard"] == nil)  // raw card omitted
    }

    @Test func declinedChargeReturnsNotApproved() async throws {
        let client = makeClient(handler: okResponse(declinedJSON))
        let result = try await client.charge(
            amount: 5, payment: .creditCard(number: "4000000000000002", expiration: "2027-12"))
        #expect(!result.approved)
        #expect(result.error?.contains("declined") == true)
    }

    @Test func authFailureFromGatewayThrows() async {
        let client = makeClient(handler: okResponse(authFailureJSON))
        await #expect(throws: AuthNetError.apiError(code: "E00007",
                text: "User authentication failed due to invalid authentication values.")) {
            _ = try await client.charge(amount: 5, payment: .nonce(value: "x"))
        }
    }

    @Test func voidSendsVoidTypeWithoutAmountOrPayment() async throws {
        let client = makeClient(handler: okResponse(approvedJSON))
        _ = try await client.void(transactionID: "40000000001")

        let txn = dig(bodyJSON(), "createTransactionRequest", "transactionRequest") as? [String: Any]
        #expect(txn?["transactionType"] as? String == "voidTransaction")
        #expect(txn?["refTransId"] as? String == "40000000001")
        #expect(txn?["amount"] == nil)
        #expect(txn?["payment"] == nil)
    }

    @Test func captureSendsPriorAuthCapture() async throws {
        let client = makeClient(handler: okResponse(approvedJSON))
        _ = try await client.capture(transactionID: "40000000001", amount: 10)

        let txn = dig(bodyJSON(), "createTransactionRequest", "transactionRequest") as? [String: Any]
        #expect(txn?["transactionType"] as? String == "priorAuthCaptureTransaction")
        #expect(txn?["refTransId"] as? String == "40000000001")
        #expect(txn?["amount"] as? String == "10.00")
    }

    @Test func refundSendsRefundWithCardTail() async throws {
        let client = makeClient(handler: okResponse(approvedJSON))
        _ = try await client.refund(transactionID: "40000000001", amount: Decimal(string: "5.50")!,
                                    cardLastFour: "1111", expiration: "2027-12")

        let txn = dig(bodyJSON(), "createTransactionRequest", "transactionRequest") as? [String: Any]
        #expect(txn?["transactionType"] as? String == "refundTransaction")
        #expect(txn?["amount"] as? String == "5.50")
        #expect(txn?["refTransId"] as? String == "40000000001")
        let card = dig(bodyJSON(), "createTransactionRequest", "transactionRequest", "payment", "creditCard") as? [String: Any]
        #expect(card?["cardNumber"] as? String == "1111")
    }

    // MARK: Live sandbox (gated). Requires sandbox credentials:
    //   AUTHNET_TESTS=1 AUTHNET_LOGIN_ID=... AUTHNET_TRANSACTION_KEY=... swift test
    private var liveEnabled: Bool { ProcessInfo.processInfo.environment["AUTHNET_TESTS"] == "1" }

    @Test func liveSandboxChargeApproves() async throws {
        guard liveEnabled,
              let login = ProcessInfo.processInfo.environment["AUTHNET_LOGIN_ID"],
              let key = ProcessInfo.processInfo.environment["AUTHNET_TRANSACTION_KEY"] else { return }

        let client = AuthNetClient(loginID: login, transactionKey: key, environment: .sandbox)
        let result = try await client.charge(
            amount: Decimal(string: "12.34")!,
            payment: .creditCard(number: "4111111111111111", expiration: "2030-12", code: "123"),
            order: OrderInfo(invoiceNumber: "TEST-\(Int(Date().timeIntervalSince1970))", description: "live sandbox test")
        )
        if !result.approved {
            Issue.record("sandbox charge not approved: \(result.error ?? "unknown")")
        }
        #expect(!result.transactionID.isEmpty)
    }
}
