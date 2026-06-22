# Perfect-AuthNet

A small, modern Swift 6 client for the [Authorize.net](https://developer.authorize.net/) payment gateway — a sibling to Perfect-Stripe for stacks that process card payments through Authorize.net.

- **Zero dependencies** — Foundation only (`URLSession` + `Codable`).
- Targets the **modern Authorize.net JSON API** (`request.api`), not the legacy AIM/SIM name-value interface.
- Built for **mobile and web storefronts**: charge Accept.js / Accept Mobile payment nonces (`opaqueData`) so raw card numbers never touch your backend.
- Swift 6 strict concurrency; everything is `Sendable`.

## Install

```swift
.package(path: "../Perfect-AuthNet"),   // or your fork's URL
```

```swift
.product(name: "PerfectAuthNet", package: "Perfect-AuthNet"),
```

## Quick start

```swift
import PerfectAuthNet

let client = AuthNetClient(
    loginID: "your_api_login_id",
    transactionKey: "your_transaction_key",
    environment: .sandbox          // .production when you go live
)

// Mobile/web: charge a tokenized nonce from Accept.js / Accept Mobile.
let result = try await client.charge(
    amount: 49.99,
    payment: .nonce(value: opaqueDataValueFromClient),
    order: OrderInfo(invoiceNumber: "INV-1001", description: "Scrubs set")
)

if result.approved {
    print("charged — transaction \(result.transactionID)")
} else {
    print("declined: \(result.error ?? "unknown reason")")
}
```

A **declined** card is a normal returned `TransactionResult` with `approved == false` — not a thrown error. Errors are thrown only for transport failures, malformed responses, and gateway-level rejections (bad credentials, validation), via `AuthNetError`.

## Payment input

```swift
// Preferred for storefronts — a nonce from the Accept.js / Accept Mobile SDK:
.nonce(value: "<opaque data value>")
.opaqueData(descriptor: "COMMON.ACCEPT.INAPP.PAYMENT", value: "<value>")

// Server-to-server or testing only — a raw card (you own the PCI scope):
.creditCard(number: "4111111111111111", expiration: "2030-12", code: "123")
```

## Operations

```swift
// Authorize + capture in one step (a standard charge)
try await client.charge(amount: 49.99, payment: .nonce(value: nonce))

// Authorize now, capture later
let auth = try await client.authorize(amount: 49.99, payment: .nonce(value: nonce))
try await client.capture(transactionID: auth.transactionID)            // full amount
try await client.capture(transactionID: auth.transactionID, amount: 40) // or a lower amount

// Refund a settled transaction (needs the original card's last 4 + expiration)
try await client.refund(transactionID: txnID, amount: 49.99,
                        cardLastFour: "1111", expiration: "2030-12")

// Void an unsettled transaction
try await client.void(transactionID: txnID)
```

## Result

```swift
public struct TransactionResult {
    let responseCode: ResponseCode   // .approved / .declined / .error / .heldForReview
    let transactionID: String        // use to capture, refund, or void later
    let authCode: String?
    let accountNumber: String?       // masked, e.g. "XXXX1111"
    let accountType: String?         // e.g. "Visa"
    let avsResultCode: String?
    let cvvResultCode: String?
    let message: String?             // "code: description"
    let error: String?               // "code: text" for declines/errors
    var approved: Bool               // responseCode == .approved
}
```

## Testing

Offline tests (request encoding, response decoding, BOM handling, amount formatting) run with no network via a mocked `URLSession`:

```sh
swift test
```

Live sandbox tests are gated — supply sandbox credentials to run them against `apitest.authorize.net`:

```sh
AUTHNET_TESTS=1 AUTHNET_LOGIN_ID=... AUTHNET_TRANSACTION_KEY=... swift test
```

## Notes

- The JSON API returns responses prefixed with a UTF-8 BOM; the client strips it before decoding (a common integration gotcha).
- Pass a custom `URLSession` to `AuthNetClient(urlSession:)` for certificate pinning or test injection.
- **Not yet covered:** customer profiles (CIM / saved cards), recurring billing (ARB), and webhooks — the natural phase 2 once the storefront needs stored payment methods.
