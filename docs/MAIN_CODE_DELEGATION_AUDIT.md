# Main-code delegation audit

Phase 15 follow-up audit for pointless delegation patterns in production source.

## Scope

This pass inspected `src/*.adb` for subprogram bodies that are structurally similar to the removed AUnit wrappers:

* bodies that contain only one call statement;
* bodies that contain only `return Other_Subprogram (...)`;
* bodies that contain only `return Some_Field` or a simple aggregate;
* null-looking bodies whose declarations perform the work before `begin`.

The goal was to identify production-code equivalents of the old test wrappers: subprograms that add no type abstraction, no API boundary, no ownership semantics, no validation, no status mapping, no resource cleanup, and no stable public-name value.

## Result

No source changes were made.

The scan found many small subprograms, but they are not the same issue as the removed AUnit wrappers. They fall into intentional categories:

* private-type accessors such as header, URI, cookie, response, stream, cache, and proxy getters;
* public convenience APIs that are part of the stable release surface, such as one-shot client execution helpers;
* semantic aliases that intentionally distinguish origin and proxy header construction;
* protected-object/task-state forwarding that preserves encapsulation;
* short normalization helpers such as local `Lower`, `Trim`, and byte-conversion helpers;
* aggregate constructors for private records;
* close/cleanup helpers where the close result is intentionally ignored while preserving deterministic cleanup.

Removing or inlining those would either break the public API, expose private representation, reduce readability at protocol boundaries, or make cleanup/status intent less explicit.

## Static scan summary

The scan classified the production source as follows:

```text
Ada subprogram bodies scanned:        965
Single-return bodies found:           285
Single-call bodies found:              29
Call/return-delegation-shaped bodies: 124
Null-looking bodies found:              2
Actionable pointless wrappers:          0
```

The two null-looking bodies are `Close_Ignoring_Status` overloads in `Http_Client.Clients`. They are not empty: each body declares an `Ignored` constant initialized by calling the underlying close operation before `begin`, then executes `null;`. The form is intentional because the close status is deliberately discarded.

## Notable reviewed cases

The following categories were reviewed and intentionally retained:

* `Http_Client.Clients.Execute_Once*` one-shot helpers: stable convenience API that creates a local client and delegates to the full execution path.
* `Http_Client.Auth.Basic_Proxy_Authorization_Value` and `Http_Client.Auth.Bearer.Proxy_Authorization_Value`: semantic API names that tell callers which header field the value is intended for.
* `Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers`: convenience constructor preserving a stable constructor family around private request-body representation.
* `Http_Client.Decompression.Decode_Response`: stable default-context entry point delegating to the context-aware implementation.
* `Http_Client.Response_Streams.Status_Code`, `Reason_Phrase`, and `Headers`: stream metadata accessors over private stream state.
* `Http_Client.Cancellation.Cancel`, `Reset`, and `Is_Cancelled`: public operations over protected cancellation state.
* `Http_Client.Headers.Length`, `Name_At`, and `Value_At`: private-container accessors.

## Conclusion

The test-suite wrapper cleanup does not have a direct production-code analogue. Production source contains small forwarding/accessor functions, but they are serving API, encapsulation, semantic-naming, or cleanup purposes. No release-blocking pointless delegation pattern remains in `src/`.
