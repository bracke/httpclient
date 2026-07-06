# Git smart HTTP Phase 8 — Timeout and Cancellation Hardening Pass

Phase 8 adds the public cancellation surface and documents deterministic timeout/cancellation behavior for long-running Git smart HTTP operations.

## Implemented surface

- `Http_Client.Cancellation` exposes `Cancellation_Token`, `Cancellation_Token_Access`, `Cancel`, `Reset`, and `Is_Cancelled`.
- `Http_Client.Errors.Result_Status` includes `Cancelled` as an ordinary transport-category outcome.
- `Http_Client.Clients.Execution_Options.Cancellation` accepts an optional token for buffered execution, retries, redirects, and `Execute_Stream` option propagation.
- `Http_Client.Response_Streams.Streaming_Options.Cancellation` accepts an optional token for streaming `Open` and `Read_Some`.

## Semantics

- Null cancellation token preserves existing behavior.
- A token cancelled before buffered execution returns `Cancelled` before network I/O.
- A token cancelled before streaming `Open` returns `Cancelled` before network I/O and records `Last_Status = Cancelled`.
- A token observed before request-header writes, while waiting for `100 Continue`, during fixed-length or chunked upload loops, before response reads, or during streaming reads returns `Cancelled`, marks the operation failed, and closes/discards the underlying transport.
- Buffered, fixed-length, and chunked upload producers are checked before producer reads, after producer reads, and before transport writes so cancellation does not intentionally send additional body bytes or trailers after observation.
- Cancellation is not retried by `Execute_With_Retry`, including cancellation observed after a retry delay hook returns.
- Timeout remains represented by `Http_Client.Errors.Timeout`; `Timeout_Config` values of `0` mean disabled/no timeout.
- Timeout and cancellation failures must retire/discard affected connections rather than returning them to a pool.

## Verification hooks

Coverage is added through:

- `tests/src/http_client-cancellation_tests.adb`
  - `Test_Token_State`
  - `Test_Cancelled_Status_Category`
  - `Test_Cancellation_Is_Not_Retryable`
  - `Test_Default_Cancellation_Fields_Are_Null`
  - `Test_Buffered_Pre_Cancelled_Execute`
  - `Test_Streaming_Pre_Cancelled_Open`
- `tests/src/http_client-timeout_tests.adb`
  - `Test_Default_Timeouts_Are_Disabled`
  - `Test_Timeout_Status_Category`
  - `Test_Timeout_Retry_Classification_Obeys_Policy`
- `tests/api_stability/src/api_stability_compile.adb`
  - compile-checks the cancellation token API, option fields, and `Cancelled` status.
- `tools/src/check_git_smart_http_release.adb`
  - requires Phase 8 source, test, API-stability, and documentation markers.

## Caveat

The cooperative cancellation model observes cancellation at explicit library checkpoints. It does not claim preemptive interruption of a platform socket or TLS call while that call is blocked; responsiveness during those calls is bounded by the configured transport/TLS timeout behavior.
