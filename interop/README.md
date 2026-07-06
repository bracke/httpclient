# Optional interoperability harness

This project is outside the default offline AUnit suite. It is for local or live
compatibility probes against controlled endpoints and proxy daemons.

Build:

```sh
cd interop
gprbuild -P interop.gpr
```

Run every configured probe:

```sh
HTTPCLIENT_INTEROP_HTTP_URL=http://127.0.0.1:8080/ \
HTTPCLIENT_INTEROP_HTTPS_URL=https://127.0.0.1:8443/ \
HTTPCLIENT_INTEROP_HTTP2_URL=https://127.0.0.1:8444/ \
./bin/interop_runner
```

Run one probe:

```sh
./bin/interop_runner --case=http2
```

Supported case names are `http`, `https`, `http2`, `stream`, `http-proxy`,
`socks5-proxy`, and `http3-boundary`.

Environment variables:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `HTTPCLIENT_INTEROP_HTTP_URL` | `http`, `stream` fallback | Direct HTTP URL. |
| `HTTPCLIENT_INTEROP_HTTPS_URL` | `https` | Direct HTTPS URL. |
| `HTTPCLIENT_INTEROP_HTTP2_URL` | `http2` | HTTPS URL that must negotiate h2. |
| `HTTPCLIENT_INTEROP_STREAM_URL` | `stream` | Optional streaming URL. |
| `HTTPCLIENT_INTEROP_PROXY_TARGET_URL` | proxy cases | Origin URL fetched through a proxy. |
| `HTTPCLIENT_INTEROP_HTTP_PROXY_URL` | `http-proxy` | Explicit `http://host:port` proxy URI. |
| `HTTPCLIENT_INTEROP_SOCKS5_PROXY_URL` | `socks5-proxy` | Explicit `socks5://host:port` or `socks5h://host:port` proxy URI. |
| `HTTPCLIENT_INTEROP_HTTP3_URL` | `http3-boundary` | HTTPS URL used to verify deterministic forced-HTTP/3 handling. |

The runner treats any parsed HTTP status code as a successful transport probe.
For example, a controlled `404` still proves that connection setup, request
framing, response parsing, and configured routing worked. Operation-level
statuses such as DNS, TLS, protocol, timeout, and proxy failures are reported as
failed probes.

The `http3-boundary` probe currently passes when forced HTTP/3 reaches the
experimental boundary and returns deterministic `QUIC_Unsupported` without
silently falling back. When a production QUIC backend is linked, the same probe
can become a real HTTP/3 execution check.
