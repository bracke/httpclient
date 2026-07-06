# Diagnostics

Diagnostics are opt-in and structured. Observers receive bounded events intended for tracing, metrics, and debugging. Redaction is the default for secrets, credentials, cookies, bodies, TLS material, QUIC material, client-certificate material, cache encryption keys, and proxy credentials.

Diagnostic message strings are for humans and are not programmatic API. Applications should branch on `Http_Client.Errors.Result_Status`, status categories, and documented structured event fields.
## Metrics and timings

`Snapshot (Context)` returns bounded per-context counters for request counts, bytes, cache outcomes, retries, redirects, connection reuse, HTTP/2, HTTP/3, upload, multipart, TLS failure, and callback-failure events. Counters are opt-in with the diagnostics context and are not global.

`Timing (Context)` returns bounded aggregate lifecycle timings derived from emitted events. The timing snapshot tracks completed request count/total milliseconds and TLS handshake count/total milliseconds. Buffered request completion and streaming response close/failure paths both contribute request-finish timings when diagnostics are enabled. QUIC/HTTP/3 connection-failure diagnostics also carry elapsed milliseconds for the attempted backend/QUIC span. `Average_Request_Milliseconds` and `Average_TLS_Handshake_Milliseconds` return guarded whole-millisecond averages and return `0` when the corresponding count is zero. Diagnostics do not retain per-request timing history.
Streaming `Request_Finish` and `Streaming_Response_Closed` events include elapsed milliseconds, final HTTP status code when response headers were seen, redirect count, retry attempt count, and protocol label.
`Retry_Decision` events are emitted only for actual retry attempts. They include the completed attempt number, operation result, retryable HTTP status code when applicable, planned backoff milliseconds, and a bounded reason message that includes request-body replayability.
