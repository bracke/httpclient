# Git smart HTTP Phase 9 — HTTP/2 multiplexing pass

Phase 9 promotes the HTTP/2 connection model from a conservative single-stream boundary to an explicitly enabled, bounded multiplexing state model while preserving the default HTTP/1.1 Git smart HTTP path.

## Implemented scope

The HTTP/2 support contract is now:

- HTTP/2 remains opt-in through `Prefer_HTTP_2`, `Force_HTTP_2`, or `HTTP2_Options.Mode`.
- `Force_HTTP_2` never silently falls back to HTTP/1.1.
- Plain `http://` with forced HTTP/2 still rejects deterministically because h2c is not implemented.
- Bounded multiplexing is enabled only when `HTTP2_Options.Enable_Multiplexing` is true.
- Multiple client-initiated streams can be tracked on one connection up to the effective local/peer concurrent-stream limit.
- Interleaved HEADERS, CONTINUATION, DATA, WINDOW_UPDATE, RST_STREAM, GOAWAY, SETTINGS, and PING frames are demultiplexed through the connection state.
- Response DATA is queued per stream and exposed as decoded entity-body bytes only.
- `Stream_Element_Array` reads preserve Git packet-line and packfile bytes, including NUL, CR/LF, and bytes above 127.
- Request-body producers are accounted as HTTP/2 DATA frames; HTTP/1.1 chunked transfer framing is not used for HTTP/2 uploads.
- Per-stream and connection-level flow-control windows are tracked.
- Per-stream queued-byte limits and aggregate queued-byte limits prevent unbounded buffering when readers are slow.
- GOAWAY records `last-stream-id`, prevents new streams, classifies streams above the last processed ID, and lets already accepted lower streams complete where the connection state remains clean.
- RST_STREAM fails only the addressed stream where possible.
- Connection-level protocol errors retire the HTTP/2 connection.

## Conservative limits

`HTTP2_Options` includes the relevant Phase 9 bounds:

- `Local_Max_Concurrent_Streams`
- `Max_Per_Stream_Buffered_Bytes`
- `Max_Total_Queued_Body_Bytes`
- `Max_Frame_Size`
- `Max_Header_List_Size`
- `Initial_Stream_Window_Size`
- `Initial_Connection_Window_Size`
- public response-stream and upload-stream activity caps

Defaults remain conservative and HTTP/1.1-compatible because HTTP/2 is disabled unless the caller opts in.

## Deliberately out of scope

The following remain unsupported with deterministic statuses or documented rejection:

- h2c
- server push
- priority tree scheduling
- extended CONNECT
- WebSocket-over-H2
- HTTP/2 request trailers
- HTTP/3 production execution

## Verification markers

Offline AUnit coverage includes stream limits, GOAWAY classification, accepted stream completion after GOAWAY, interleaved DATA routing, stream reset isolation, flow-control accounting, frame validation, invalid transition non-mutation, header-continuation failure non-commit, padded/priority HEADERS metadata accounting, content-length/bodyless response checks, public body-stream reads, byte-array Git-byte preservation, upload DATA accounting, per-stream queue compaction, aggregate queued-body bounding, terminal stream error cleanup, cancellation/reset slot release, and Git HTTP/2 metadata/binary body preservation.

## Completeness pass 2 — HEADERS metadata accounting

The multiplexed connection now accounts only HPACK header-block fragment bytes against header-list bounds when a HEADERS frame carries PADDED and/or PRIORITY metadata. Padding length, padding octets, and the five-octet priority section are validated as frame metadata and are not counted as decoded header-list bytes. Continuation accounting composes with the stripped initial fragment length, so a later CONTINUATION can still fail only the affected stream if the aggregate header block exceeds the configured limit. Regression coverage is provided by `Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted`.
