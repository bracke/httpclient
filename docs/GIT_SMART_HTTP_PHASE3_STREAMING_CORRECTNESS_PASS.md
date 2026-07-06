# Git smart HTTP Phase 3 streaming correctness pass

Phase 3 hardens the HTTP/1.1 streaming and upload contract needed by Git smart HTTP consumers. The goal is not a new high-level feature surface; it is a correctness proof around entity-byte streaming, transfer framing removal, bounded parsing, deterministic failure, and conservative connection retirement.

## Confirmed response-streaming contract

`Http_Client.Response_Streams.Read_Some` on the byte-array overload remains the Git-critical path. It exposes HTTP entity bytes only:

- fixed `Content-Length` responses are read incrementally;
- `Content-Length: 0`, `HEAD`, `204`, `205`, and `304` responses end without body bytes;
- close-delimited responses read until EOF and are not reusable;
- HTTP/1.1 chunked responses are transfer-decoded before bytes are returned;
- chunk extensions are accepted;
- split chunk-size metadata, split chunk data, split CRLF, and split terminating chunk state are covered by AUnit tests;
- response trailers are parsed and discarded, never exposed as entity bytes;
- trailer line and aggregate limits are enforced with deterministic status;
- arbitrary binary bytes, including NUL, CR, LF, and bytes above 127, are preserved.

The recommended Git loop remains:

```ada
while not Http_Client.Response_Streams.End_Of_Body (Stream) loop
   Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
   exit when Status = Http_Client.Errors.End_Of_Stream;
   exit when Status /= Http_Client.Errors.Ok;
   Feed_Git_Pkt_Line_Parser (Buffer (Buffer'First .. Last));
end loop;
```

## Transfer-coding hardening

The HTTP/1.1 response analyzer now parses the `Transfer-Encoding` field instead of relying on a raw exact string comparison. The streaming path supports the ordinary `chunked` transfer coding only. Unsupported codings or malformed comma-separated values fail deterministically rather than being treated as body bytes or accepted accidentally.

## Bounded response trailers

Chunked response trailers are bounded using the configured header size and header-line limits. Oversized trailers return `Header_Too_Large`; invalid trailer syntax returns `Invalid_Header`; early EOF in the trailer section returns `Incomplete_Message`. Trailer bytes are never delivered through `Read_Some`.

## Upload and request-trailer contract retained

Unknown-length producers are serialized as HTTP/1.1 chunked uploads. Fixed-length producers are serialized with `Content-Length`. Request trailers remain valid only for unknown-length chunked uploads, are declared through `Trailer`, and are serialized after the terminating zero chunk. Forbidden trailer names continue to be rejected, including `Content-Length`, `Transfer-Encoding`, `Host`, `Connection`, `Authorization`, `Proxy-Authorization`, and `Cookie`.

## Expect: 100-continue retained

`Expect: 100-continue` is explicit only. Streaming execution sends headers first, withholds the body until `100 Continue`, and preserves an early final response body without uploading the request body. Duplicate or unsupported `Expect` values are deterministic failures.

## Decompression composition retained

Decompression remains opt-in. When disabled, `Read_Some` returns transfer-decoded but still content-encoded entity bytes. When enabled, gzip, zlib-wrapped deflate, and explicitly configured raw-deflate are decoded incrementally after HTTP transfer decoding. Framing errors and decoded-size-limit failures retire the stream rather than permitting unsafe reuse.

## Connection reuse safety

Direct streaming remains conservative. Cleanly consumed fixed-length and chunked streams are the only candidates for future reuse; close-delimited, malformed, incomplete, timed-out, failed-upload, producer-failed, and decompression-failed streams are closed/discarded. For Git correctness, losing reuse is acceptable; corrupting a pkt-line or packfile byte stream is not.

## Phase 3 coverage markers

The AUnit suite now contains explicit Phase 3 coverage markers:

- `Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer`
- `Test_Response_Stream_Chunked_Trailer_Line_Limit`
- `Test_Response_Stream_Chunked_Trailer_Total_Limit`
- existing fixed-length fragmented streaming tests
- existing close-delimited streaming tests
- existing Git pkt-line chunked binary byte-array tests
- existing early-final `Expect: 100-continue` chunked response tests
- existing request trailer tests
- existing streaming decompression tests for gzip, zlib-wrapped deflate, and raw deflate

The release guard checks for the split chunk metadata, trailer line-limit, and trailer total-limit markers so later changes cannot silently drop the Phase 3 coverage surface.
