# Header and protocol semantics

Header handling is deliberately conservative.

Header names are validated as HTTP field names and matched case-insensitively. Iteration and serialization are deterministic. Header values are treated as HTTP field-value bytes with validation; they are not arbitrary Unicode strings.

The client distinguishes end-to-end headers, hop-by-hop headers, proxy credentials, origin credentials, cookies, content framing, and protocol pseudo-headers. Default headers configured on a high-level client cannot inject routing, framing, hop-by-hop, cookie, authorization, proxy-authorization, or protocol-specific pseudo-header fields.

HTTP/1.1 serialization controls `Host`, `Content-Length`, and `Connection` according to request and execution options. Unknown-length HTTP/1.1 request uploads synthesize `Transfer-Encoding: chunked`; fixed-length uploads use `Content-Length`. HTTP/1.1 `Transfer-Encoding: chunked` responses are decoded before body bytes are exposed; unsupported response transfer codings are rejected rather than treated as body bytes.

HTTP/2 and HTTP/3 mapping rejects forbidden connection-specific headers. Origin authority is represented through the relevant request URI and protocol-specific mapping; ordinary users do not need to construct pseudo-headers. Sensitive fields such as `Authorization`, `Proxy-Authorization`, `Cookie`, and `Set-Cookie` must remain redacted in diagnostics and must not be indexed by HPACK/QPACK helpers.

Redirect handling strips sensitive credentials on cross-origin hops by default. HTTPS-to-HTTP downgrades are blocked unless explicitly allowed.

Response models remain protocol-neutral where feasible. HTTP/2 and HTTP/3 do not have reason phrases; callers should use status code, protocol metadata, ALPN/selection metadata, cache metadata, retry/redirect counts, and diagnostics summaries rather than relying on HTTP/1.1-only details.
