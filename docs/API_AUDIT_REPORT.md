# API audit report

This audit records the stabilization decisions applied for the 1.0 1.0.0 release surface.

## Public namespace

The stable public namespace remains Ada-native and package-oriented. Ordinary applications should prefer `Http_Client.Clients` for execution and compose explicit helper packages for URI parsing, request construction, headers, authentication headers, cookies, proxies, cache stores, diagnostics, streaming, uploads, multipart bodies, and async submission.

## Internal and experimental boundaries

HTTP/3 and QUIC remain experimental foundations. OpenSSL bridge details, cache file byte layout, encrypted-cache primitive details, SOCKS negotiation internals, worker queues, and test fixtures are not application-level compatibility promises unless a public specification explicitly documents them.

## Result model hardening

`Http_Client.Errors` now exposes `Result_Category` and `Category` so diagnostics, examples, and callers can group statuses without string matching or collapsing precise statuses. The precise `Result_Status` value remains the primary program-control API.

## Build and examples

The examples project is compile-oriented. It intentionally avoids live-network assumptions except where a high-level method is shown as a normal API call. Persistent-cache examples use caller-supplied paths and keep creation disabled so copying an example does not unexpectedly create cache directories.

## Remaining pre-release checks

Before tagging a final 1.0 release, run the full AUnit suite, build all examples, check warning output under the selected GNAT switches, and verify generated GNATdoc output for every stable public `.ads` file.
