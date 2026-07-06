# Phase 16 SOCKS5 Exact Handshake Fixture Fix Pass

The Ada SOCKS5 release fixture was hardened after the SOCKS5/TLS suite
reported failures across both positive tunnel cases and deterministic negative
SOCKS reply cases.

The SOCKS5 fixture now reads protocol records with exact-length reads instead
of assuming that a single socket receive returns a complete greeting, username
password authentication message, or CONNECT request.  This matches TCP stream
semantics and prevents partial-read dependent fixture failures.

The tunnel pump remains Ada task-based and bounded.  Fixture stop operations
abort outstanding local fixture tasks so failed assertions do not leave stale
server/proxy tasks alive for later tests.

This pass preserves the release policy:

- no C test fixtures;
- no pthread fixture support;
- production TLS/OpenSSL bridge C remains allowed;
- no C zlib bridge;
- no direct `-lz`.
