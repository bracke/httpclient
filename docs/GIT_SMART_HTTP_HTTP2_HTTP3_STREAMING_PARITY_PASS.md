# Git smart HTTP HTTP/2/HTTP/3 streaming parity pass

This pass extends the Git smart HTTP streaming surface beyond the earlier
HTTP/1.1-only public `Response_Streams` contract.

## Public protocol policy

`Http_Client.Response_Streams.Streaming_Protocol_Policy` now includes:

* `Streaming_HTTP_1_1_Only`
* `Streaming_Prefer_HTTP_2`
* `Streaming_Force_HTTP_2`
* `Streaming_Prefer_HTTP_3`
* `Streaming_Force_HTTP_3`

`Streaming_HTTP_1_1_Only` remains the default. It disables HTTP/2 ALPN and the
HTTP/3 candidate path for callers that want deterministic HTTP/1.1 transfer
coding semantics.

`Streaming_Prefer_HTTP_2` advertises h2 and falls back to HTTP/1.1 before any
request bytes are sent when ALPN selects HTTP/1.1. `Streaming_Force_HTTP_2`
requires HTTPS plus h2 ALPN and rejects h2c/plain HTTP.

`Streaming_Prefer_HTTP_3` and `Streaming_Force_HTTP_3` enter the experimental
HTTP/3/QUIC execution boundary. They do not bypass proxy checks, SOCKS checks,
client-certificate checks, or QUIC backend availability checks. Prefer mode may
fall back before request bytes are sent when the configured fallback policy
allows it; force mode fails deterministically.

## Binary stream contract

The public pull API remains byte-oriented:

```ada
Read_Some
  (Stream : in out Streaming_Response;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
```

For HTTP/1.1 it returns transfer-decoded entity bytes. For HTTP/2 and HTTP/3 it
returns DATA payload bytes only. It never exposes chunk metadata, HTTP/2 frame
headers, HTTP/3 frame headers, HPACK/QPACK bytes, QUIC stream metadata, or
trailers merged into ordinary headers.

## HTTP/2 boundary

The HTTP/2 path uses TLS ALPN and the existing conservative HTTP/2 execution
core. The low-level `Http_Client.HTTP2.Body_Streams` adapter already exposes a
binary-safe `Stream_Element_Array` pull API for queued HTTP/2 DATA bytes. This
pass connects the high-level `Response_Streams` protocol policy to the h2 ALPN
selection path so Git callers can request or require h2 explicitly.

## HTTP/3 boundary

This pass adds `Http_Client.HTTP3.Body_Streams`, a binary-safe HTTP/3 DATA
payload adapter. A production QUIC backend feeds decoded DATA payload bytes into
this adapter and then marks END_STREAM. The adapter provides the same status
model as the HTTP/2 body stream: `Ok`, `End_Of_Stream`, `Timeout`, deterministic
size-limit failures, and caller-misuse statuses.

The current crate still has no production QUIC backend in this sandbox. The
HTTP/3 streaming policy therefore remains deterministic: if no backend is
available, `Streaming_Force_HTTP_3` fails with the configured HTTP3/QUIC status
instead of silently falling back or faking HTTP/3 over TCP.

## Tests added

* `Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP`
* `Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend`
* `Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes`

These complement the existing HTTP/2 byte-array body stream and buffered
HTTP/2/HTTP/3 Git metadata/body tests.

## Examples added

* `git_upload_pack_http2_stream.adb`
* `git_info_refs_http3_stream.adb`

The HTTP/3 example is intentionally capability-sensitive: it handles the case
where no QUIC backend is configured.

## Completeness follow-up

See `docs/GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_COMPLETENESS_PASS.md` for the follow-up pass that added the missing AUnit wrappers, the streaming Force_HTTP2 plain-HTTP rejection marker, and cleaned stale package comments.
