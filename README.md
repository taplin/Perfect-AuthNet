# Perfect-AuthNet

A small, clean-room Swift 6 client for the [Authorize.net](https://developer.authorize.net/) payment gateway.

**Requirements:** Swift tools 6.2, macOS 26 (Tahoe) — the only platform currently declared in `Package.swift`. No iOS/watchOS/tvOS/Linux target is declared yet, so despite the "mobile and web storefronts" framing below (describing the *payment flows* it supports, i.e. Accept.js/Accept Mobile nonces — not that the package itself runs on iOS today), this only builds on macOS 26+ for now.

**Status:** staged, unintegrated infrastructure. This package has zero consumers in the Perfect-Resurrection ecosystem right now — no other package depends on or imports it, and the live site does not call into it. Authorize.net gateway calls in production today go through raw `Pair()`/`include_url` natives directly in `includes/efs_process.lasso` on the real Lasso site. Perfect-AuthNet is meant to eventually formalize/replace that ad-hoc integration with a proper native Swift client; it is planned future work, not dead code.

- **Zero dependencies** — Foundation only (`URLSession` + `Codable`).
- Targets the **modern Authorize.net JSON API** (`request.api`), not the legacy AIM/SIM name-value interface.
- Supports **mobile and web storefront payment flows**: charge Accept.js / Accept Mobile payment nonces (`opaqueData`) so raw card numbers never touch your backend.
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
- **Not yet covered:** customer profiles (CIM / saved cards), recurring billing (ARB), and webhooks — planned once the storefront needs stored payment methods.
- This is early-stage, single-commit infrastructure (see Status above) — not yet exercised against production traffic.

## License

No `LICENSE` file is present in this repository yet, and none is implied by this README. Until one is added, treat the source as all-rights-reserved; contact the repo owner before reuse.
