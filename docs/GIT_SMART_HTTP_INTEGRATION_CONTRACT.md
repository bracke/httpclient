# Git smart HTTP integration contract

This crate provides generic HTTP/HTTPS transport primitives for Git smart HTTP.
It does not provide, own, or install `Version.Transport.Http`; that downstream
adapter remains outside this crate.

## Recommended Git path

Use HTTP/1.1 pull streaming first for robust Git fetch/clone behavior:

```ada
Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;
Options.Enable_Decompression := False;
```

Then read with the binary-safe byte-array API:

```ada
while not Http_Client.Response_Streams.End_Of_Body (Stream) loop
   Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
   exit when Status = Http_Client.Errors.End_Of_Stream;
   -- Feed Buffer (Buffer'First .. Last) to the Git pkt-line parser.
end loop;
```

`Ada.Streams.Stream_Element_Array` is the preferred body path for Git packet-line
and packfile data. Body APIs do not perform UTF-8 validation, charset conversion,
line-ending normalization, NUL stripping, or implicit text conversion. Git bytes
above 127 and embedded NUL bytes are preserved.

## Transfer framing contract

The streaming path does not expose HTTP/1.1 chunk framing. Chunk sizes, chunk
extensions, chunk CRLF delimiters, and chunk trailers are decoded or discarded
inside the HTTP layer. `Read_Some` returns HTTP entity bytes only. The streaming
path does not require whole-body buffering.

Supported response streaming covers fixed `Content-Length`, no-body statuses,
HTTP/1.1 `Transfer-Encoding: chunked`, and close-delimited one-shot responses.
Malformed transfer framing is reported with deterministic statuses such as
`Protocol_Error`, `Incomplete_Message`, `Header_Too_Large`, `Response_Too_Large`,
or `Read_Failed`.

## Upload contract

Git upload-pack and receive-pack callers may use:

* `From_Bytes` or `From_String` for replayable in-memory bodies;
* `From_Fixed_Length_Stream` when pack size is known;
* `From_Unknown_Length_Stream` for HTTP/1.1 chunked uploads;
* `From_Unknown_Length_Stream_With_Trailers` when explicit request trailers are
  required.

Fixed-length stream bodies must produce exactly the declared length. Unknown
length bodies are serialized as HTTP/1.1 chunked uploads. Request trailers are
valid only for chunked uploads and are rejected for forbidden framing, routing,
credential, and connection-control fields. The `Trailer` declaration is generated
from the attached trailer fields and must cover all attached trailers.

If the caller sets `Expect: 100-continue`, HTTP/1.1 execution sends headers
first, waits for `100 Continue`, and sends the body only after the interim
response. An early final response is returned without sending the body. The
client does not add `Expect` automatically.

## Encoding and decompression

High-level default client decompression is enabled for ordinary buffered responses. Git smart HTTP callers that need exact bytes should use `Strict_Client_Configuration`, streaming byte-array APIs, or explicit `Accept-Encoding: identity`. Streaming decompression remains opt-in. `Accept-Encoding` is not automatically
added for the basic streaming path. Git consumers may send
`Accept-Encoding: identity` for maximum predictability. Streaming decompression
is opt-in through `Streaming_Options.Enable_Decompression`; buffered decoded
views are opt-in through the explicit decompression APIs or configured-client
settings. Unsupported encodings follow `Decompression_Options.Unsupported_Policy`.
Supported decompression codings are gzip, zlib-wrapped deflate by default, and
raw deflate only when `Decompression_Options.Deflate_Mode` is set to `Raw_Only`
or `Auto_Zlib_Then_Raw`.

## Redirects, retries, cookies, and replay safety

`Default_Client_Configuration` follows safe redirects for ordinary high-level use. Git smart HTTP callers that require exact no-follow behavior should use `Strict_Client_Configuration` or set `Redirects.Follow_Redirects := False`. Rewritten redirect requests that drop the body also drop body-specific headers, including Git `Content-Type`, `Content-Length`, `Digest`, and `Expect: 100-continue`. Retries are
disabled by default unless explicitly configured. Cookies are explicit and
disabled unless a caller-owned cookie jar is supplied.

Non-replayable request bodies must not be retried or replayed across redirects.
Fixed-length or unknown-length producer bodies are replayable only when their
producer declares replayability and `Reset` can restore the identical byte
sequence. Redirects across origins strip credential-bearing headers by default.
HTTPS-to-HTTP downgrades are blocked by default.

## TLS, proxies, and protocol selection

TLS verification is enabled by default. Disabling verification is explicit via
`TLS_Options.Disable_Certificate_Verification` and is unsafe except for local
controlled testing. Custom CA file and CA directory fields are explicit and
validated before OpenSSL use. SNI is enabled by default for suitable DNS names.

HTTP proxies and SOCKS5 proxies are configured explicitly with
`Http_Client.Proxies.Proxy_Config`. HTTPS over an HTTP proxy uses CONNECT before
origin TLS. HTTPS over SOCKS5 performs SOCKS negotiation before origin TLS. Proxy
authorization is scoped to the proxy boundary and must not leak into the origin
TLS stream.

HTTP/2 is optional and is not the default safest Git streaming path. Use
`Prefer_HTTP_2`, `Force_HTTP_2`, `Streaming_Prefer_HTTP_2`, or
`Streaming_Force_HTTP_2` only when the Git caller deliberately wants the h2
boundary. `Force_HTTP_2` rejects plain `http://` because h2c is not implemented.

HTTP/3 is experimental and backend-dependent. `Prefer_HTTP_3`, `Force_HTTP_3`,
`Streaming_Prefer_HTTP_3`, and `Streaming_Force_HTTP_3` must fail
deterministically when QUIC or the requested boundary is unavailable, when a
proxy/client-certificate combination is unsupported, or when fallback is not
allowed before request bytes are sent.

## Error mapping guidance

Treat `Invalid_URI`, `Invalid_Header`, and `Invalid_Request` as request
construction/configuration failures. Treat `DNS_Failed`, `Connection_Failed`,
`Proxy_Connection_Failed`, `SOCKS_*`, `TLS_*`,
`Certificate_Verification_Failed`, and `Hostname_Verification_Failed` as
transport establishment failures. Treat `Protocol_Error`, `Incomplete_Message`,
malformed chunk outcomes, and invalid response headers as remote protocol
failures. Treat `Response_Too_Large`, `Decoded_Body_Too_Large`,
`Upload_Too_Large`, and `Body_Length_Mismatch` as bounded resource or upload
contract failures. Treat `Body_Producer_Failed` as a local upload-source failure.


## Phase 3 HTTP/1.1 streaming correctness

HTTP/1.1 streaming reads expose entity bytes, not transfer framing. Chunked response decoding is supported, including chunk extensions, split chunk metadata, bounded response trailers, and arbitrary binary body bytes. Unknown-length request streams use chunked upload; request trailers are restricted to HTTP/1.1 chunked uploads; `Expect: 100-continue` is explicit and withholds the body until `100 Continue`. Decompression remains opt-in. Close-delimited, malformed, incomplete, failed-upload, and decompression-failed streams are closed/discarded rather than reused. See `docs/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md`.


## TLS verification boundary

HTTPS execution uses `Http_Client.Transports.TLS` for `https://` URIs. Certificate validation and hostname/IP-address verification are enabled by default through `Default_TLS_Options`; Git smart HTTP integrations should provide `TLS_Options.CA_File` or `TLS_Options.CA_Directory` only when they intentionally use a custom trust store. `Disable_Certificate_Verification` is explicit, unsafe, and not suitable for production Git transport. The Phase 4 loopback HTTPS fixture proves direct TLS success with a configured CA, negative behavior without that CA, wrong-hostname failure, binary response preservation, streaming reads, chunked responses, chunked uploads, request trailers, and `Expect: 100-continue` before proxy-tunnel end-to-end fixtures are layered on top.

## HTTPS over HTTP CONNECT proxy contract

For Git smart HTTP over an explicit HTTP proxy, HTTPS remotes use HTTP/1.1 CONNECT to the origin authority before TLS starts. The CONNECT request uses `host:port` authority-form. Origin request headers, cookies, Git protocol headers, request bodies, and request trailers are not sent before the tunnel is established. `Proxy-Authorization` belongs only to the proxy-facing CONNECT request and must not appear in the tunneled origin request.

TLS certificate validation remains enabled by default. Hostname verification and SNI use the origin host from the HTTPS URI, not the proxy host. Git integrations should still prefer `Force_HTTP_1_1` and explicit `Accept-Encoding: identity` unless they intentionally enable and consume streaming decompression.


## HTTPS over SOCKS5 proxy contract

For Git smart HTTP over an explicit SOCKS5 proxy, HTTPS remotes use SOCKS5 negotiation and CONNECT to the origin authority before TLS starts. Origin request headers, cookies, Git protocol headers, request bodies, and request trailers are not sent before the SOCKS tunnel is established. SOCKS username/password credentials belong only to SOCKS authentication and must not appear in the tunneled origin request. Hostname verification and SNI use the origin hostname, not the SOCKS proxy hostname. Positive local fixture tests use the configured test CA and keep certificate verification enabled.


### HTTPS-over-SOCKS5 Phase 6 completeness pass coverage

Phase 6 includes deterministic local SOCKS5-over-TLS tests for no-auth and username/password negotiation, configured-CA validation, origin-host SNI/hostname verification, credential/header/body isolation before tunnel establishment, byte-array streaming, chunked response decoding, buffered POST, fixed-length streaming upload, unknown-length chunked upload, request trailers, `Expect: 100-continue`, and negative SOCKS/TLS failures. The SOCKS proxy fixture records only SOCKS greeting/auth/CONNECT bytes before tunnel success; origin `Authorization`, cookies, Git headers, request bodies, paths, trailers, and Expect headers are asserted to remain inside the TLS tunnel.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.


### HTTP/2 trailers

HTTP/2 trailers are trailing HEADERS, not HTTP/1.1 chunk trailers. Request trailers do not require an HTTP/1.1 Trailer declaration and never use Transfer-Encoding. Pseudo-headers plus framing, connection-specific, and sensitive names are rejected. Response body reads expose only DATA bytes; buffered responses expose validated trailer fields through `Http_Client.Responses.Trailers`, while the HTTP/2 connection model also records per-stream trailer receipt.

## Phase 11 HTTP/3 boundary note

Git smart HTTP consumers should continue to use HTTP/1.1 or HTTP/2 as the stable transport paths. HTTP/3 is experimental/backend-dependent. This tree has no built-in production QUIC backend, but buffered execution can call a supplied `Buffered_Backend_Callback`; without one, `Force_HTTP_3` and `Streaming_Force_HTTP_3` fail deterministically and never fall back to HTTP/2 or HTTP/1.1. `Prefer_HTTP_3` and `Streaming_Prefer_HTTP_3` may fall back only before request bytes are sent and must preserve configured HTTP proxy or SOCKS5 proxy routing. HTTP/3 over HTTP proxy, SOCKS5, MASQUE, CONNECT-UDP, WebTransport, 0-RTT, and server push are not implemented.

## Phase 12 redirect/retry Git safety

Redirects and retries remain explicit opt-ins. Git fetch requests may enable tightly bounded redirect/retry policy only when the request body is empty or replayable. Git push / `git-receive-pack` streaming uploads should remain non-replayable unless the producer can reset and emit identical bytes; such uploads are not retried and are not replayed across 307/308 redirects. Cross-origin redirects strip `Authorization`, `Proxy-Authorization`, `Cookie`, `Cookie2`, and `Git-Protocol`; HTTPS-to-HTTP downgrades are blocked by default. Forced protocol policies and configured proxy routes are preserved across redirect/retry chains.

## Phase 13 binary-safe body contract

Git integrations should treat `Ada.Streams.Stream_Element_Array` request and response APIs as authoritative. Git packet-line and packfile payloads must not be routed through text convenience APIs unless a caller deliberately maps Ada `Character` values 0 .. 255 to octets. HttpClient body paths do not perform UTF-8 validation, charset conversion, CR/LF normalization, line-ending rewriting, or NUL stripping. Header APIs reject CR/LF injection, and framing metadata is kept separate from entity body bytes.

Release marker: Ada.Streams.Stream_Element_Array request and response APIs as authoritative for Git packet-line and packfile payloads.


## Phase 14 compile-targeted example references

External Git smart HTTP consumers should start from the compile-checked examples in
`docs/EXAMPLES.md`. The canonical streaming discovery read loop is shown by
`git_info_refs_streaming_get.adb`; buffered upload-pack body setup is shown by
`git_upload_pack_post_buffered.adb`; fixed-length and unknown-length receive-pack producer uploads
are shown by `git_receive_pack_fixed_upload.adb` and `git_receive_pack_chunked_upload.adb`; proxy
routing is shown by `git_https_proxy_connect.adb` and `git_socks5_https.adb`; timeout and
cancellation setup is shown by `git_streaming_with_timeout_and_cancellation.adb`; redirect and retry
safety are shown by `git_redirect_policy.adb` and `git_retry_policy.adb`. These examples use
`Ada.Streams.Stream_Element_Array` request and response APIs as authoritative and keep
`Accept-Encoding: identity` as the conservative Git default.


## High-level default interaction

`Default_Client_Configuration` follows safe redirects and enables bounded final-response decompression for ordinary buffered client use. Git smart HTTP callers that require exact pkt-line or packfile byte preservation should use streaming byte-array APIs, request `Accept-Encoding: identity`, or start buffered client configuration from `Http_Client.Clients.Strict_Client_Configuration`. Strict configuration disables automatic redirects and disables the decoded final-response view while retaining verified TLS defaults.
