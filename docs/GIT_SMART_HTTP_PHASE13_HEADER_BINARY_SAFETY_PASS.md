# Git Smart HTTP Phase 13 Header and Binary Safety Pass

Phase 13 is the final header/body separation and binary-safety audit for Git smart HTTP use cases in `Http_Client`.

## Scope

This pass verifies that Git pkt-line and packfile data are transported as bytes, not as text. The authoritative Git-safe request and response APIs remain `Ada.Streams.Stream_Element_Array` based. Convenience `String` APIs are byte-preserving over Ada `Character` values 0 .. 255 where documented, but Git integrations should use byte-array paths so there is no hidden UTF-8 validation, charset conversion, line-ending normalization, NUL stripping, CR/LF normalization, or text interpretation.

## Header validation

Header names are HTTP token fields. Empty names, whitespace, colon, CR, LF, NUL, DEL, controls, and non-token separators are rejected deterministically. Header lookup is case-insensitive; storage and iteration preserve caller spelling and insertion order. Header values reject CR, LF, CRLF injection, NUL, horizontal tab, DEL, C1 controls, and other controls. Empty values and visible ASCII values are accepted. Leading and trailing space handling is explicit: the `Header_List` API stores supplied spaces, while the HTTP/1.x response parser trims optional whitespace around parsed field values before validation.

## Framing and boundary policy

Framing metadata is security-sensitive. Duplicate `Content-Length` fields, including identical duplicates, are rejected by the buffered HTTP/1.x parser. Conflicting `Content-Length` fields are rejected deterministically. Raw `Transfer-Encoding` in `Parse_Response` is rejected with `Unsupported_Feature` because complete responses handed to that parser must already contain entity bytes, not HTTP/1.1 transfer framing. The HTTP/1.1 streaming reader remains responsible for chunked decoding and trailer consumption. `Transfer-Encoding: chunked` plus `Content-Length` is not accepted as a buffered response shape.

Request serialization emits exactly one CRLFCRLF header/body boundary before buffered body bytes. Body bytes that contain CRLFCRLF, `Header: value`, `Content-Length`, `Transfer-Encoding`, `HTTP/1.1`, NUL, CR, LF, and high-byte values remain body bytes after the boundary and are not re-parsed as headers.

## Binary test corpus

The Phase 13 AUnit package `Http_Client.Binary_Safety_Tests` uses `Http_Client.Binary_Test_Data`, which supplies explicit numeric byte corpora:

- empty body;
- one NUL byte;
- all byte values 0..255;
- CR/LF/CRLF/CRLFCRLF-heavy bodies;
- Git pkt-line-like data;
- Git packfile-like data;
- compressed-looking bytes;
- a long body crossing buffer boundaries.

The tests compare exact `Stream_Element_Array` values. This includes request-body `From_Bytes`, request-body `From_String` octet preservation, buffered response `Response_Body_Bytes`, body bytes containing CRLFCRLF, and Git packfile-like data.

## HTTP/2 and HTTP/3 boundary safety

HTTP/2 DATA bytes are binary entity bytes; HTTP/2 frame headers, HPACK metadata, and trailing HEADERS are not body data. HTTP/2 trailers are validated separately and reject pseudo-headers and HTTP/1.1 transfer-framing names such as `Transfer-Encoding`. HTTP/3 remains experimental/backend-dependent; compile-visible HTTP/3 body-stream helpers remain byte-array oriented, and no-backend execution fails deterministically rather than producing partial header or body state.

## Diagnostics, auth, and cookies

Diagnostics must not log request or response body bytes by default and must redact `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, bearer tokens, and SOCKS passwords. Auth and cookie helpers remain header producers and must pass the same CR/LF injection policy as ordinary headers. Proxy credentials remain proxy-only, and origin credentials remain origin-only.

## Verification markers

The release guard checks for the Phase 13 test package, all-byte corpus, request and response NUL/high-byte preservation tests, CRLFCRLF body-boundary test, duplicate/conflicting `Content-Length` tests, `Transfer-Encoding` plus `Content-Length` rejection, header CR/LF injection rejection, HTTP/2 header validation, diagnostics redaction wording, and documentation that byte-array APIs are the Git-safe APIs.

## Required command set

Run the normal full gate when Alire and GNAT/GPRbuild are available:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```

This pass does not add `Version.Transport.Http` or any downstream adapter code.

Release marker: byte-array APIs are the Git-safe body APIs.
