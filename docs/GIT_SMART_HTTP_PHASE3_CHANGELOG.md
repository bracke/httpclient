# Phase 3 local change log

Implemented against `HttpClient_phase2_streaming_decompression_raw_deflate.zip`.

## Source changes

- Hardened HTTP/1.1 `Transfer-Encoding` response analysis so only the supported `chunked` transfer coding is accepted by the streaming path; malformed comma-separated values and unsupported codings fail deterministically.
- Added per-stream response trailer accounting fields.
- Bounded chunked response trailer lines and aggregate trailer bytes using the existing configured header limits.
- Oversized chunked response trailers now fail as `Header_Too_Large`; invalid trailer syntax remains `Invalid_Header`; early EOF remains `Incomplete_Message`.

## Test changes

- Added `Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer` for one-byte socket sends, one-byte caller buffers, chunk extensions, split chunk metadata, and binary entity-byte preservation.
- Added `Test_Response_Stream_Chunked_Trailer_Line_Limit` for deterministic single trailer-line bound failure after body bytes have been exposed.
- Added `Test_Response_Stream_Chunked_Trailer_Total_Limit` for deterministic aggregate trailer-section bound failure after body bytes have been exposed.
- Registered both new tests in the response streaming AUnit section.

## Documentation and release guard

- Added `GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md`.
- Linked the new document from `DOCUMENTATION_INDEX.md`.
- Added Phase 3 notes to streaming/upload, Git integration, audit, verification, and README docs.
- Extended `check_git_smart_http_release` to require Phase 3 document and test coverage markers.

## Verification note

This environment does not provide `alr`, `gprbuild`, or GNAT Ada tooling, so I could not run the required Ada build/test commands here.

## Completeness pass update

- Corrected the trailer line-limit test so normal response headers remain within the configured line bound and the failure occurs at the chunked trailer parser, not during initial response-header parsing.
- Added aggregate response-trailer-size coverage to prove bounded trailer discard does not depend only on per-line limits.
