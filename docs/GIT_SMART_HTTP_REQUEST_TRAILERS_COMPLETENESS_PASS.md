# Git Smart HTTP Request Trailers Completeness Pass

This pass completes the crate-local request-trailer audit for the Git smart HTTP transport work.

## Confirmed behavior

* Request trailers are explicit and are attached to `Http_Client.Request_Bodies.Request_Body`, not mixed into ordinary request headers.
* HTTP/1.1 request trailers are valid only for `Unknown_Length_Stream` bodies serialized with `Transfer-Encoding: chunked`.
* Header serialization synthesizes `Trailer: ...` when attached trailer fields are present and no explicit declaration exists.
* An explicit `Trailer` header is accepted only when it covers every attached trailer field name.
* An explicit `Trailer` header without attached request-body trailers is rejected deterministically.
* Attached trailer fields with forbidden framing, routing, connection-control, or credential names are rejected deterministically.
* Trailer fields are emitted after the terminating zero-size chunk and are followed by the final empty line.
* Fixed-length, buffered, and empty request bodies reject attached trailers.
* HTTP/2 and HTTP/3 execution paths reject request trailers instead of silently dropping them.

## Added coverage

The request/header AUnit coverage now checks:

* synthesized `Trailer` declarations;
* explicit covering `Trailer` declarations;
* incomplete explicit `Trailer` declarations;
* orphan `Trailer` declarations with no attached request-body trailer fields;
* rejection of trailers on fixed-length bodies;
* rejection of forbidden trailer field names;
* loopback wire emission of chunked body bytes followed by trailer fields.

## Scope boundary

This does not require Git smart HTTP to use request trailers. The normal Git upload path should still prefer fixed-length request streaming when the pack length is known. Unknown-length chunked uploads can carry trailers when a caller explicitly attaches them.
