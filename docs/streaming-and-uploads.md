# Streaming and uploads

This document describes the public streaming and upload contracts used by both
generic HTTP callers and Git smart HTTP callers.

## Response streaming

`Http_Client.Response_Streams.Open` sends one request and returns after response
headers are parsed. The caller owns the returned `Streaming_Response` and must
read to `End_Of_Body` or call `Close`.

The preferred binary read API is:

```ada
function Read_Some
  (Stream : in out Streaming_Response;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
   return Http_Client.Errors.Result_Status;
```

`Last` is the last written array index, or `Buffer'First - 1` when no data was
returned. `Ok` with data means progress. `End_Of_Stream` with no data means clean
EOF. Ordinary network, timeout, framing, size, and misuse failures are returned
as deterministic `Result_Status` values.

HTTP/1.1 response streaming supports `Content-Length`, no-body responses,
chunked transfer decoding, and one-shot close-delimited bodies. Chunked response
framing is decoded incrementally. Chunk extensions and bounded trailers are
parsed and discarded; body reads return entity bytes only. Close-delimited
responses are not reusable because EOF is the delimiter.

HTTP/2 and HTTP/3 body streams expose DATA payload bytes only. They do not expose
frame metadata, HPACK/QPACK data, QUIC stream framing, trailers, or flow-control
frames to the caller.

## Streaming decompression

Streaming decompression is opt-in:

```ada
Options.Enable_Decompression := True;
Options.Decompression := Http_Client.Decompression.Default_Decompression_Options;
```

When disabled, `Read_Some` returns transfer-decoded but content-encoded entity
bytes. When enabled, supported gzip, zlib-wrapped deflate, and explicitly
configured raw-deflate encodings are decoded incrementally after transfer
decoding. Unsupported encodings follow `Unsupported_Policy`. HTTP `deflate`
defaults to `Zlib_Wrapped_Only`; callers may set `Raw_Only` or
`Auto_Zlib_Then_Raw` through `Decompression_Options.Deflate_Mode`.

## Fixed-length request streaming

Use fixed-length streaming when the upload size is known:

```ada
Body := Http_Client.Request_Bodies.From_Fixed_Length_Stream
  (Producer   => Producer'Unchecked_Access,
   Length     => Exact_Byte_Count,
   Replayable => Can_Reset_Identically);
```

The producer must return exactly `Length` bytes. Early EOF returns
`Body_Length_Mismatch`. Too much data, producer failure, timeout, or write
failure returns a deterministic status and prevents connection reuse. Replayable
fixed-length bodies may be retried or redirected only when `Reset` restores the
same byte sequence.

## Unknown-length chunked request upload

Use unknown-length streaming when the size is not known in advance:

```ada
Body := Http_Client.Request_Bodies.From_Unknown_Length_Stream
  (Producer   => Producer'Unchecked_Access,
   Replayable => False);
```

HTTP/1.1 execution serializes this as `Transfer-Encoding: chunked`. Each
producer output becomes a chunk. `Ok` with zero bytes terminates the upload with
a zero-size chunk. Unknown-length bodies are never sent by connection-close
delimiting.

## Request trailers

Request trailers are explicit and valid only for unknown-length chunked uploads:

```ada
Body := Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
  (Producer   => Producer'Unchecked_Access,
   Trailers   => Trailer_Headers,
   Replayable => False);
```

The HTTP/1.1 serializer declares the attached trailer names with `Trailer` and
emits trailer fields after the terminating chunk. It rejects trailers on empty,
buffered, and fixed-length bodies. It also rejects forbidden trailer names such
as framing, routing, authentication, cookie, proxy, connection-control, host,
content-length, transfer-encoding, TE, upgrade, and trailer declaration fields.

## Expect: 100-continue

The client honors an explicit `Expect: 100-continue` header. It sends headers,
waits for `100 Continue`, then sends the body. If the server sends an early final
response, the client does not send the body and exposes the final response as
normal metadata/body data. The client does not add `Expect` automatically and
unsupported `Expect` values fail deterministically.

## Connection reuse rules and current limitations

The direct streaming implementation still owns and closes its transport handle.
The high-level buffered HTTP/1.1 client now attaches real TCP/TLS handles to the
client-owned pool when pooling is enabled. It suppresses synthetic
`Connection: close`, reuses only clean fixed-length or fully decoded chunked
responses, and discards uncertain connections.

A response read fully to EOF may be reusable only when protocol framing leaves
the connection in a clean reusable state. Early close, malformed framing,
timeout, read failure, upload failure, unknown close-delimited EOF, proxy/TLS key
mismatch, explicit `Connection: close`, and response-body size violations all
prevent reuse.

For Git, the conservative default remains HTTP/1.1 streaming with decompression
disabled and `Accept-Encoding: identity` supplied by the caller when maximum
wire predictability is desired.


## Phase 3 HTTP/1.1 streaming correctness

HTTP/1.1 streaming reads expose entity bytes, not transfer framing. Chunked response decoding is supported, including chunk extensions, split chunk metadata, bounded response trailers, and arbitrary binary body bytes. Unknown-length request streams use chunked upload; request trailers are restricted to HTTP/1.1 chunked uploads; `Expect: 100-continue` is explicit and withholds the body until `100 Continue`. Decompression remains opt-in. Close-delimited, malformed, incomplete, failed-upload, and decompression-failed streams are closed/discarded rather than reused. See `docs/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md`.


## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.


### HTTP/2 trailers

HTTP/2 trailers are trailing HEADERS, not HTTP/1.1 chunk trailers. Request trailers do not require an HTTP/1.1 Trailer declaration and never use Transfer-Encoding. Pseudo-headers plus framing, connection-specific, and sensitive names are rejected. Response body reads expose only DATA bytes; buffered responses expose validated trailer fields through `Http_Client.Responses.Trailers`, while the HTTP/2 connection model also records per-stream trailer receipt.

## HTTP/3 streaming boundary

`Streaming_Force_HTTP_3` enters the experimental HTTP/3 execution boundary and, without a production QUIC backend, fails deterministically before HTTP/1.1 or HTTP/2 request bytes are sent. `Streaming_Prefer_HTTP_3` may fall back only before request bytes are sent and only according to the documented fallback policy. The compile-visible `Http_Client.HTTP3.Body_Streams` byte-array append/read API remains binary-safe for future backend integration.

## Phase 12 redirect/retry upload safety

Streaming upload producers are treated as one-shot unless the body is explicitly marked replayable and `Reset` succeeds. Retry and redirect code must not replay non-replayable request bodies. This is especially important for Git `git-receive-pack` uploads: large chunked push streams should normally be non-replayable, so write failures, partial uploads, timeouts, and 307/308 redirects fail deterministically instead of resending consumed pack data. Buffered byte-array bodies preserve exact bytes and may be replayed only when the caller enables the relevant retry or redirect policy. When a 301/302/303 redirect rewrite drops the body, the redirected request also drops stale body metadata, including `Content-Length`, Git `Content-Type`, `Content-Encoding`, `Content-MD5`, `Digest`, and `Expect: 100-continue`.

## Phase 13 binary-safety note

For Git smart HTTP, prefer `Ada.Streams.Stream_Element_Array` upload and response-read paths. Body bytes are opaque: NUL, CR, LF, CRLF, CRLFCRLF, high-byte values, Git pkt-line data, Git packfile data, and compressed-looking bytes are preserved as entity bytes. Header operations, trailer parsing, and transfer-framing decoding must not mutate or reinterpret those bytes.


## Git smart HTTP example shapes

The compile-targeted Git examples under `examples/src` demonstrate the intended streaming/upload
shape for consumers: body bytes are opaque, `Ada.Streams.Stream_Element_Array` is used for Git
request and response body paths, producer-backed receive-pack uploads are non-replayable by default,
unknown-length uploads do not supply `Content-Length` and do not manually frame chunks, and
`Expect: 100-continue` is opt-in through an explicit request header. Use
`git_info_refs_streaming_get.adb`, `git_upload_pack_post_buffered.adb`,
`git_receive_pack_fixed_upload.adb`, `git_receive_pack_chunked_upload.adb`,
`git_chunked_upload_with_trailers.adb`, and `git_receive_pack_expect_continue.adb` as the
compile-checked references.
