# Git Smart HTTP HTTP/1.1 Protocol Policy Completeness Pass

This pass tightens the explicit HTTP/1.1 protocol policy added for Git smart
HTTP.

## Fixes

* `Execution_Options.Protocol_Policy = Force_HTTP_1_1` now overrides an
  otherwise `HTTP3_Required` client configuration for the individual execution.
  The request is allowed to use the HTTP/1.1 TCP/TLS path instead of failing
  early with `HTTP3_Unsupported`.
* Cache dispatch now treats `Force_HTTP_1_1` like an HTTP/1.1 execution guard.
  When cache policy is enabled, forced HTTP/1.1 executions enter the existing
  HTTP/1.1 cache wrappers instead of the HTTP/3 fresh-cache lookup branch.
* Added AUnit coverage proving a high-level client configured with
  `HTTP3_Required` can still execute a single plain HTTP loopback request when
  that execution sets `Force_HTTP_1_1`.

## Contract

`Force_HTTP_1_1` is an execution-level override. It disables HTTP/3 candidate
selection, Alt-Svc/HTTPS-SVCB upgrade selection, and HTTP/3-required early
failure for that execution path. It does not mutate the reusable client
configuration and does not enable HTTP/2 or HTTP/3 streaming.
