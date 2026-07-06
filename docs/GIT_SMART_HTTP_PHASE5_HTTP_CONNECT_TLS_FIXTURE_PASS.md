# Git smart HTTP Phase 5 — HTTPS over HTTP CONNECT TLS fixture pass

Phase 5 adds local deterministic end-to-end coverage for HTTPS requests routed through an explicit HTTP proxy using `CONNECT`.

The tested path is:

```text
client -> local HTTP proxy fixture -> CONNECT origin-host:origin-port -> TLS handshake in tunnel -> local HTTPS origin fixture
```

## Covered behavior

- `tests/src/http_client_connect_proxy_fixture.c` is a loopback-only HTTP proxy fixture and can require an expected `Proxy-Authorization` value.
- `tests/src/http_client-connect_tls_tests.adb` reuses the Phase 4 TLS origin fixture.
- Positive tests use `tests/fixtures/tls/ca.crt`; they do not disable certificate verification.
- CONNECT uses authority-form `CONNECT host:port HTTP/1.1` and a matching `Host: host:port` header.
- TLS starts only after a successful `200 Connection Established` proxy response.
- Certificate validation remains enabled through CONNECT; missing/untrusted CA failure is tested after successful CONNECT.
- Hostname verification and SNI use the origin host, not the proxy host; the `localhost` SNI path is tested separately from numeric loopback.
- The proxy observes only CONNECT/proxy headers before tunnel establishment.
- Origin `Authorization`, `Cookie`, `Git-Protocol`, Git `Content-Type`, and request bodies are sent only inside the TLS tunnel.
- `Proxy-Authorization` is sent only to the proxy, is required by the proxy-auth fixture path, and is not visible to the origin request.
- Buffered HTTPS GET and POST execution work through CONNECT.
- Byte-array streaming response reads work through CONNECT.
- Chunked HTTP/1.1 response decoding works through CONNECT.
- Binary response bytes, including NUL, CR, LF, and bytes above 127, are preserved.
- Negative proxy responses such as 407, 403, 502, malformed CONNECT responses, proxy close before CONNECT response, and tunnel close during TLS handshake map to deterministic statuses.
- Wrong-hostname certificate failure after CONNECT proves hostname verification is against the origin authority.

## Out of scope

SOCKS5 end-to-end fixture coverage remains Phase 6. Real connection pooling/reuse, timeout hardening, and HTTP/2 or HTTP/3 multiplexing over proxy tunnels were outside that historical phase unless implemented elsewhere.
