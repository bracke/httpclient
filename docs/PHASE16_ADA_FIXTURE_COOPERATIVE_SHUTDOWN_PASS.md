# Phase 16 Ada Fixture Cooperative Shutdown Pass

This pass fixes the release-test symptom where the AUnit executable can appear to
finish executing tests but fail to return a final report because an Ada fixture
task remains alive during program shutdown.

The fix is intentionally limited to the Ada task-based test fixtures.

## Changes

- `tests/src/http_client-ada_test_fixtures.adb`
  - Added tracked socket handles for TLS, CONNECT proxy, and SOCKS5 proxy
    fixture tasks.
  - `Stop_TLS`, `Stop_CONNECT_Proxy`, and `Stop_SOCKS5_Proxy` now close active
    listener/client/origin sockets before using task abort as a fallback.
  - Stop operations wait briefly for normal task termination before aborting.
  - Fixture task handles are cleared after shutdown.
  - Tunnel pump shutdown remains bounded and socket-driven.

## Rationale

Aborting a task that is blocked in `Accept_Socket`, `Receive_Socket`, TLS
accept/read, or tunnel forwarding is not a deterministic fixture shutdown
strategy. Closing the sockets first unblocks the task so it can leave its task
body and allow AUnit/process finalization to complete.

## Constraints preserved

- No C test fixtures.
- No pthread fixture support.
- No warning suppression.
- Production TLS/OpenSSL bridge files remain unchanged.
