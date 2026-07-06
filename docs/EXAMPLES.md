# Examples

For a first build/test path and minimal GET example, start with `docs/QUICKSTART.md`.

The `examples/` project contains compile-oriented examples for the intended public surface. They are intentionally small and conservative; most do not perform live network I/O.

Build all examples with:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

## Complete example manifest

The following files are listed in `examples/examples.gpr` and are expected to compile as part of the examples project:

- `alt_svc_parse.adb`
- `async_submit.adb`
- `basic_auth.adb`
- `bearer_auth.adb`
- `cache_config.adb`
- `client_certificate_config.adb`
- `connection_pool_policy.adb`
- `cookie_session.adb`
- `decompression_config.adb`
- `diagnostics_observer.adb`
- `download_to_file.adb`
- `digest_auth.adb`
- `enable_http2.adb`
- `enable_http3_experimental.adb`
- `http3_force_no_backend.adb`
- `http3_prefer_with_fallback.adb`
- `encrypted_cache_config.adb`
- `http_proxy_config.adb`
- `https_svcb_record.adb`
- `manual_request.adb`
- `multipart_upload.adb`
- `pac_wpad_config.adb`
- `persistent_cache_config.adb`
- `protocol_discovery_config.adb`
- `redirect_client.adb`
- `retry_policy.adb`
- `simple_get.adb`
- `socks_proxy_config.adb`
- `stabilized_defaults.adb`
- `status_categories.adb`
- `git_info_refs_stream.adb`
- `git_info_refs_https_proxy_stream.adb`
- `git_info_refs_https_socks_stream.adb`
- `git_info_refs_http3_buffered.adb`
- `git_info_refs_http2_buffered.adb`
- `git_upload_pack_http2_stream.adb`
- `git_upload_pack_stream.adb`
- `git_receive_pack_fixed_upload.adb`
- `git_receive_pack_chunked_upload.adb`
- `git_receive_pack_chunked_upload_trailers.adb`
- `git_info_refs_http3_stream.adb`
- `streaming_download.adb`
- `streaming_upload.adb`
- `streaming_get_with_cancellation.adb`
- `git_info_refs_streaming_get.adb`
- `git_upload_pack_post_buffered.adb`
- `git_chunked_upload_with_trailers.adb`
- `git_receive_pack_expect_continue.adb`
- `git_https_custom_ca.adb`
- `git_https_proxy_connect.adb`
- `git_socks5_https.adb`
- `git_streaming_decompression.adb`
- `git_http2_streaming_fetch_shape.adb`
- `git_redirect_policy.adb`
- `git_retry_policy.adb`
- `git_streaming_with_timeout_and_cancellation.adb`
- `git_binary_safe_transport_shape.adb`

If a file is added to or removed from `examples/examples.gpr`, update this manifest in the same change so documentation and compile coverage stay aligned.

## Example purpose matrix

| Example | Purpose |
| --- | --- |
| `alt_svc_parse.adb` | Parses Alt-Svc metadata without opening a network connection. |
| `async_submit.adb` | Shows bounded async client configuration and submit shape. |
| `basic_auth.adb` | Builds a request using Basic authorization helper APIs. |
| `bearer_auth.adb` | Builds a request using Bearer authorization helper APIs. |
| `cache_config.adb` | Configures in-memory cache policy. |
| `client_certificate_config.adb` | Configures client certificate/key fields for TLS. |
| `connection_pool_policy.adb` | Configures bounded connection pooling. |
| `cookie_session.adb` | Configures an explicit caller-owned cookie jar; no browser-like implicit cookie store is introduced. |
| `decompression_config.adb` | Shows explicit decompression opt-in and size policy. |
| `download_to_file.adb` | Demonstrates the download-to-file convenience API, `Max_Download_Size`, and atomic replacement. |
| `diagnostics_observer.adb` | Initializes diagnostics context with redaction-aware observer hook configuration. |
| `digest_auth.adb` | Builds digest authorization input shape. |
| `enable_http2.adb` | Shows explicit HTTP/2 preference/force configuration. |
| `enable_http3_experimental.adb` | Shows experimental/backend-dependent HTTP/3 policy configuration. |
| `encrypted_cache_config.adb` | Configures encrypted persistent-cache settings. |
| `http_proxy_config.adb` | Configures HTTP proxy routing. |
| `http3_force_no_backend.adb` | Demonstrates deterministic forced-HTTP/3 no-backend handling. |
| `http3_prefer_with_fallback.adb` | Demonstrates preferred HTTP/3 fallback before request bytes are sent. |
| `https_svcb_record.adb` | Demonstrates HTTPS/SVCB record data handling. |
| `manual_request.adb` | Constructs a request manually from URI, method, headers, and body shape. |
| `multipart_upload.adb` | Builds multipart upload payload metadata/body shape. |
| `pac_wpad_config.adb` | Shows PAC/WPAD proxy discovery configuration. |
| `persistent_cache_config.adb` | Configures persistent cache storage. |
| `protocol_discovery_config.adb` | Configures protocol discovery policy. |
| `redirect_client.adb` | Shows explicit redirect policy configuration. |
| `retry_policy.adb` | Shows explicit retry policy configuration. |
| `simple_get.adb` | Minimal buffered GET status-handling shape with server-declared `Content-Type`, media type, and charset reporting. |
| `socks_proxy_config.adb` | Configures SOCKS5 proxy routing and credentials. |
| `stabilized_defaults.adb` | Asserts important security/default configuration choices. |
| `status_categories.adb` | Shows status category helpers. |
| `streaming_download.adb` | Configures bounded streaming download options. |
| `streaming_get_with_cancellation.adb` | Shows streaming GET timeout and cancellation fields. |
| `streaming_upload.adb` | Shows request body construction and replayability check. |
| `git_binary_safe_transport_shape.adb` | Demonstrates opaque binary Git body bytes including NUL and high bytes. |
| `git_chunked_upload_with_trailers.adb` | Demonstrates unknown-length chunked Git upload with valid request trailers. |
| `git_http2_streaming_fetch_shape.adb` | Demonstrates explicit HTTP/2 streaming policy for Git fetch-style traffic. |
| `git_https_custom_ca.adb` | Demonstrates custom CA configuration while keeping TLS verification enabled. |
| `git_https_proxy_connect.adb` | Demonstrates HTTPS origin access through an HTTP CONNECT proxy. |
| `git_info_refs_http2_buffered.adb` | Demonstrates buffered Git info/refs with explicit HTTP/2 policy. |
| `git_info_refs_http3_buffered.adb` | Demonstrates buffered Git info/refs with experimental HTTP/3 policy. |
| `git_info_refs_http3_stream.adb` | Demonstrates streaming Git info/refs HTTP/3 boundary handling. |
| `git_info_refs_https_proxy_stream.adb` | Demonstrates streaming Git info/refs through HTTPS-over-CONNECT. |
| `git_info_refs_https_socks_stream.adb` | Demonstrates streaming Git info/refs through HTTPS-over-SOCKS5. |
| `git_info_refs_stream.adb` | Demonstrates binary-safe streaming Git info/refs GET. |
| `git_info_refs_streaming_get.adb` | Demonstrates compile-targeted Git info/refs GET with Git protocol headers and byte-array reads. |
| `git_receive_pack_chunked_upload.adb` | Demonstrates unknown-length Git receive-pack upload. |
| `git_receive_pack_chunked_upload_trailers.adb` | Demonstrates Git receive-pack chunked upload with trailers. |
| `git_receive_pack_expect_continue.adb` | Demonstrates explicit `Expect: 100-continue` for receive-pack upload. |
| `git_receive_pack_fixed_upload.adb` | Demonstrates fixed-length Git receive-pack producer upload. |
| `git_redirect_policy.adb` | Demonstrates explicit redirect policy for Git discovery traffic. |
| `git_retry_policy.adb` | Demonstrates explicit bounded retry policy for safe Git discovery traffic. |
| `git_socks5_https.adb` | Demonstrates HTTPS Git origin routing through SOCKS5. |
| `git_streaming_decompression.adb` | Demonstrates explicit streaming decompression policy selection. |
| `git_streaming_with_timeout_and_cancellation.adb` | Demonstrates Git streaming timeout and cancellation fields. |
| `git_upload_pack_http2_stream.adb` | Demonstrates upload-pack streaming shape under HTTP/2 policy. |
| `git_upload_pack_post_buffered.adb` | Demonstrates binary-safe buffered upload-pack POST. |
| `git_upload_pack_stream.adb` | Demonstrates upload-pack streaming request shape. |


Current examples cover basic GET construction, manual request construction, conservative defaults, redirects, cookies, Basic/Bearer/Digest helper usage, HTTP proxy and SOCKS proxy configuration, in-memory cache configuration, persistent-cache configuration, encrypted persistent-cache configuration, diagnostics context setup, async client setup, client-certificate validation, streaming option construction, fixed-length upload bodies, multipart bodies, status-category use, HTTP/2 enablement and bounded multiplexing configuration, Git smart HTTP binary streaming (`git_info_refs_stream.adb`, `git_upload_pack_stream.adb`, `git_receive_pack_fixed_upload.adb`, `git_receive_pack_chunked_upload.adb`, `git_receive_pack_chunked_upload_trailers.adb`, `git_info_refs_https_proxy_stream.adb`, `git_info_refs_https_socks_stream.adb`), buffered HTTP/2/HTTP/3 Git examples (`git_info_refs_http2_buffered.adb`, `git_info_refs_http3_buffered.adb`), and the experimental HTTP/3 unsupported-execution boundary.


## HTTP/2 and HTTP/3 Git smart HTTP support

Git smart HTTP calls may explicitly select HTTP/2 or HTTP/3 in buffered execution and may explicitly select HTTP/2 or HTTP/3 in pull streaming through `Http_Client.Response_Streams.Streaming_Options.Protocol_Policy`. HTTP/3 remains experimental and QUIC-backend dependent.

Examples: `git_info_refs_http2_buffered.adb` and `git_info_refs_http3_buffered.adb`.

## Buffered Git smart HTTP over HTTP/2 and HTTP/3

* `git_info_refs_http2_buffered.adb` demonstrates explicit `Prefer_HTTP_2` selection for a buffered Git `info/refs` request.
* `git_info_refs_http3_buffered.adb` demonstrates explicit `Prefer_HTTP_3` selection for a buffered Git `info/refs` request when an HTTP/3 QUIC backend is configured.

The public pull-based streaming API defaults to HTTP/1.1 but also exposes explicit HTTP/2 and HTTP/3 streaming policy values for deployments that verify those protocol paths. HTTP/2 streaming reads expose entity bytes only and are protected by per-stream and aggregate queued-body limits.

- `git_upload_pack_http2_stream.adb` — Git upload-pack POST using the public streaming API with explicit HTTP/2 preference.
- `git_info_refs_http3_stream.adb` — Git info/refs streaming shape using the explicit HTTP/3 policy and deterministic no-backend handling.


## Git smart HTTP examples verified by the release guard

The examples project currently compile-checks these Git smart HTTP examples:

* `git_info_refs_stream.adb` — HTTP/1.1 streaming `info/refs` GET with binary reads.
* `git_upload_pack_stream.adb` — streaming upload-pack POST shape.
* `git_receive_pack_fixed_upload.adb` — receive-pack with fixed-length upload body.
* `git_receive_pack_chunked_upload.adb` — receive-pack with unknown-length chunked upload.
* `git_receive_pack_chunked_upload_trailers.adb` — chunked upload with request trailers.
* `git_info_refs_https_proxy_stream.adb` — HTTPS streaming through an HTTP CONNECT proxy.
* `git_info_refs_https_socks_stream.adb` — HTTPS streaming through SOCKS5.
* `git_info_refs_http2_buffered.adb` — explicit buffered HTTP/2 Git request shape.
* `git_info_refs_http3_buffered.adb` — explicit buffered HTTP/3 boundary shape.
* `git_upload_pack_http2_stream.adb` — HTTP/2 streaming upload-pack boundary shape.
* `git_info_refs_http3_stream.adb` — experimental HTTP/3 streaming boundary shape.
* `http3_force_no_backend.adb` — local-only forced HTTP/3 no-backend deterministic failure example.
* `http3_prefer_with_fallback.adb` — local-only preferred HTTP/3 before-send fallback policy example that preserves proxy routing.

The examples project also compile-checks generic examples relevant to Git
callers, including `streaming_download.adb`, `streaming_upload.adb`,
`decompression_config.adb`, `http_proxy_config.adb`, `socks_proxy_config.adb`,
`enable_http2.adb`, `enable_http3_experimental.adb`, `http3_force_no_backend.adb`, and `http3_prefer_with_fallback.adb`.


## Phase 2 raw-deflate streaming decompression

Buffered high-level `Client.Get` enables bounded final-response decompression by default. The basic low-level streaming path remains raw by default and does not add `Accept-Encoding` automatically; configured high-level client streams and file downloads propagate `Client_Configuration.Enable_Decompression` to the streaming reader. When explicitly enabled, gzip, zlib-wrapped deflate, and raw deflate through `Decompression_Options.Deflate_Mode` are supported. The default HTTP `deflate` mode is `Zlib_Wrapped_Only`; `Raw_Only` and `Auto_Zlib_Then_Raw` are explicit interoperability policies. Decoded-size limits are enforced incrementally and decoded bytes remain binary-safe for Git packet-line and packfile data.


## Direct TLS release-fixture note

Direct HTTPS behavior is covered by the offline AUnit fixture rather than by an external-network example. The fixture validates custom CA configuration, default verification failure for the private test CA, hostname verification failure, binary-safe HTTPS bodies, streaming reads, buffered upload, chunked upload, trailers, and `Expect: 100-continue` without contacting GitHub or GitLab.

## HTTPS proxy CONNECT fixture examples

The compile-checked Git HTTPS proxy streaming examples demonstrate proxy configuration shape. End-to-end CONNECT/TLS release coverage is provided by Ada task-based loopback fixtures in the AUnit suite. No example uses external network access for release verification.


## HTTPS SOCKS5 fixture examples

The compile-checked Git HTTPS SOCKS streaming example demonstrates SOCKS5 proxy configuration shape. End-to-end SOCKS/TLS release coverage is provided by Ada task-based loopback fixtures in the AUnit suite. No example uses external network access for release verification.


## Phase 7 connection pooling

The high-level buffered HTTP/1.1 client now has transport-attached connection reuse when `Client_Configuration.Pooling.Enabled` is true. Pooling is bounded, disabled by default, and conservative: fixed-length and fully consumed chunked responses may be reused; close-delimited, malformed, incomplete, failed-upload, timeout, proxy/TLS-failure, and explicit `Connection: close` paths discard the transport. Reuse is keyed by origin, scheme, proxy route, proxy credential identity, TLS verification/CA/SNI settings, and client-certificate identity. Request headers, cookies, authorization fields, and Git headers are never sticky across reused connections. See `docs/GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md`.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.


- `streaming_get_with_cancellation.adb` demonstrates byte-array streaming with explicit connect/read/write timeout values and an optional cooperative cancellation token.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.

## Phase 11 HTTP/3 boundary examples

`http3_force_no_backend.adb` and `http3_prefer_with_fallback.adb` are local-only examples. They deliberately do not contact public HTTP/3 sites. They show the experimental/backend-dependent boundary, deterministic no-backend status handling, no forced fallback, and before-send fallback policy that preserves configured proxy routing.

## Redirect/retry safety note

The Git smart HTTP examples keep redirects and retries explicit. Fetch-style examples may opt into bounded retry/redirect behavior only for replayable or empty bodies. Push-style examples using streaming `git-receive-pack` uploads should keep bodies non-replayable unless a producer can reset and reproduce identical bytes.

## Phase 13 Git binary-safety guidance

Git examples should use byte-array request and response bodies for pkt-line and packfile data. String convenience response APIs are not the Git packet-stream interface; use the byte-array streaming or buffered APIs instead.


## Phase 14 compile-targeted Git smart HTTP examples

These examples are compile-only integration shapes that use reserved `.invalid` origins. They do
not contact public remotes during release verification and do not implement a downstream adapter.
All Git body paths use byte-array-oriented APIs or producer bytes; packet-line and packfile data are
not treated as text.

* `git_info_refs_streaming_get.adb` — HTTPS `info/refs` GET with `Git-Protocol: version=2`,
  `Accept-Encoding: identity`, cookies disabled, decompression disabled, HTTP/1.1 streaming policy,
  and byte-array `Read_Some`.
* `git_upload_pack_post_buffered.adb` — upload-pack POST with an explicit
  `Ada.Streams.Stream_Element_Array` body through `Request_Bodies.From_Bytes`.
* `git_receive_pack_fixed_upload.adb` — receive-pack fixed-length producer upload with
  `Replayable => False` unless the caller supplies a real resettable producer.
* `git_receive_pack_chunked_upload.adb` — receive-pack unknown-length upload; callers supply entity
  bytes only and `Http_Client` emits HTTP/1.1 chunk framing.
* `git_chunked_upload_with_trailers.adb` — unknown-length upload with valid request trailers and no
  credential-bearing trailer fields.
* `git_receive_pack_expect_continue.adb` — explicit `Expect: 100-continue`; early final responses
  prevent request body upload.
* `git_https_custom_ca.adb` — custom CA file configuration with certificate verification still
  enabled.
* `git_https_proxy_connect.adb` — HTTPS origin through an HTTP CONNECT proxy; proxy credentials stay
  in proxy configuration and origin TLS verification uses the origin host.
* `git_socks5_https.adb` — HTTPS origin through SOCKS5; SOCKS credentials are not origin headers.
* `git_streaming_decompression.adb` — explicit decompression opt-in and deflate policy selection;
  Git callers may still prefer `Accept-Encoding: identity`.
* `git_http2_streaming_fetch_shape.adb` — explicit HTTP/2 streaming policy; no HTTP/1.1 chunk
  assumptions are made on the HTTP/2 path.
* `http3_force_no_backend.adb` — experimental/backend-dependent forced HTTP/3 boundary with
  deterministic unsupported/no-backend handling and no silent fallback.
* `git_redirect_policy.adb` — Git strict-mode redirect policy; explicit safe GET discovery
  following keeps HTTPS downgrade blocked and strips cross-origin credentials.
* `git_retry_policy.adb` — retries remain disabled by default; explicit bounded retry is shown only
  for safe discovery-style GET.
* `git_streaming_with_timeout_and_cancellation.adb` — connect/read/write timeout intent plus an
  optional cancellation token for streaming reads.
* `git_binary_safe_transport_shape.adb` — NUL, CR, LF, CRLF, and high bytes remain opaque body bytes.

Build command:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```


## Ergonomic high-level GET defaults

`examples/src/simple_get.adb` uses the one-shot `Http_Client.Clients.Get` helper, response metadata convenience accessors, and `Http_Client.Clients.Response_Text`. With `Default_Client_Configuration`, safe redirects and bounded final-response decompression are enabled. Examples that need exact Git packet-line or packfile bytes either use streaming byte-array paths, request `Accept-Encoding: identity`, or use `Strict_Client_Configuration` where buffered client configuration is involved.

## IPv6 literal URLs

HTTP and HTTPS URLs may use IPv6 address literals in the standard bracketed authority form:

```ada
Status := Http_Client.Clients.Get
  ("http://[::1]:8080/",
   Result);
```

Support matrix:

| Host form | Status | Notes |
| --- | --- | --- |
| DNS hostnames | Supported | Normal DNS name parsing and TLS DNS-name verification apply. |
| IPv4 literals | Supported | TLS requires a matching IPv4 IP subjectAltName for HTTPS. |
| IPv6 literals | Supported in bracketed URI form, such as `http://[::1]/`. | Socket/TLS code receives the unbracketed address internally; emitted URI authorities and Host headers remain bracketed. |
| IPv6 zone identifiers | Unsupported | Scoped forms such as `http://[fe80::1%25lo0]/` fail deterministically. |
| h2c | Unsupported | Plain HTTP/2 cleartext upgrade remains out of scope. |

HTTPS to an IPv6 literal keeps certificate verification enabled. The certificate must contain a matching IPv6 IP subjectAltName; DNS-only certificates fail hostname/IP verification.



## Download-to-file convenience

`examples/src/download_to_file.adb` demonstrates `Http_Client.Clients.Download_To_File`. This API is intended for ordinary file downloads where buffering the full body in memory is not desirable. Buffered `Get`/`Execute` retain `Max_Body_Size`; file downloads stream to disk and use the separate `Download_Options.Max_Download_Size`, which defaults to a high file-download cap and can be set to `0` for no total-file limit.
