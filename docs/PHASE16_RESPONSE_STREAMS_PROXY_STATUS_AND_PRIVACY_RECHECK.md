# Phase 16 Response Streams Proxy Status and Privacy Recheck

This pass fixes the remaining `Http_Client.Response_Streams.Tests` proxy failures after the response-stream suite stopped blocking AUnit reporting.

Changes:

- The unreachable HTTPS-over-CONNECT streaming proxy-attempt test now disables certificate verification for that negative route test so the result cannot be masked by host CA-store configuration before proxy connection failure is reached.
- The unreachable HTTPS-over-SOCKS5 streaming proxy-attempt test now disables certificate verification for the same reason.
- The CONNECT request-shape privacy check no longer treats `Proxy-Authorization` as leaked origin `Authorization`; it checks only for an origin `Authorization` header line.

No warning suppression was added.
