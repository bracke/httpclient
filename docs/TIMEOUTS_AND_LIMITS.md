# Timeouts and resource limits

The library is bounded by default. Concrete 1.0.0 values are listed in `DEFAULT_LIMITS.md`. Buffered response paths cap total response bytes, header section bytes, header line bytes, and response body bytes. Decompression caps decoded bytes separately. Caches cap entries, single stored responses, and total body bytes. Diagnostics caps text fields and body previews. Async caps workers and queued requests. HTTP/2 and HTTP/3 foundation packages cap frames, header lists, stream queues, upload queues, and flow-control state.

Timeout fields express caller intent for connect, read, write, TLS handshake, proxy CONNECT, SOCKS negotiation, upload blocking, retry delay, async wait, and cache revalidation boundaries. Some platform socket APIs may enforce these limits only approximately; package comments should be honest where enforcement is best-effort.

Tests should avoid long real-time sleeps. Prefer scripted transports, injected clocks, small retry delays, and deterministic queue/cancellation cases.

A size or timeout failure must return a deterministic status and must not reinterpret truncated or unsupported wire data as a valid body.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.
