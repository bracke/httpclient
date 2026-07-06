# Git Smart HTTP HTTP/2 / HTTP/3 Completeness Pass

This pass tightens the buffered HTTP/2 / HTTP/3 Git smart HTTP support added for `Http_Client`.

## Corrections

* `Force_HTTP_2` now rejects plain `http://` requests with `HTTP2_Unsupported_Feature` before opening a TCP connection. The crate does not implement h2c upgrade or prior-knowledge h2c for Git smart HTTP.
* `Force_HTTP_3` remains a high-level buffered HTTPS policy. The low-level one-shot HTTP/1.1 execution path rejects direct `Force_HTTP_3` use with `HTTP3_Unsupported` instead of silently executing HTTP/1.1.
* Documentation now states that HTTP/2 Git support is HTTPS/TLS-ALPN based. `Prefer_HTTP_2` may fall back to HTTP/1.1 before request bytes are sent; `Force_HTTP_2` requires h2.

## Tests added

* `Test_High_Level_Client_Force_HTTP2_Rejects_Plain_HTTP`

The test verifies that a high-level client configured with `Execution.Protocol_Policy := Force_HTTP_2` rejects a plain HTTP Git-shaped request deterministically before attempting a network connection.

## Stable Git transport boundary

* Pull-based `Http_Client.Response_Streams` now exposes explicit HTTP/2 and HTTP/3 streaming policies, with HTTP/1.1 remaining the default.
* Buffered Git discovery/RPC calls may explicitly select `Prefer_HTTP_2`, `Force_HTTP_2`, `Prefer_HTTP_3`, or `Force_HTTP_3`.
* HTTP/3 remains experimental and requires a configured QUIC backend.
