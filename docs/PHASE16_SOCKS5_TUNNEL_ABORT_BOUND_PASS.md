# Phase 16 SOCKS5 Tunnel Abort Bound Pass

This pass hardens the Ada task-based SOCKS5/CONNECT tunnel fixture against
remaining suite blocks.

The tunnel helper now:

- records directional pump completion through a protected `Pump_State`;
- closes both tunnel endpoints when either directional pump finishes or raises;
- bounds the enclosing tunnel wait;
- aborts both local pump tasks after the bounded wait path so the proxy task is
  not held indefinitely by a peer task blocked in `Receive_Socket`;
- applies short client-side TCP/TLS timeout intent in the SOCKS5 TLS tests so a
  fixture regression fails deterministically instead of blocking indefinitely.

The production client and production TLS/OpenSSL bridge are unchanged.  This is
only test-fixture lifecycle hardening.
