# Phase 16 Warning Cleanup Pass 5

This pass responds to the follow-up GNAT warning/error log after warning cleanup pass 4.

The important build blocker in the uploaded log was in `tests/src/http_client-http1-tests.adb`: prior cleanup had removed local `declare` block openers around socket-bound-port and stream-buffer helper declarations. That left repeated local declarations such as `Raw` and `Last` in the same declarative region, producing name conflicts.

Changes:

- Restored local `declare` blocks around runtime `Bound` declarations after `Listen_Socket` calls in HTTP/1 loopback server tasks.
- Restored local `declare` blocks around per-operation `Raw`/`Last` stream buffers after `Accept_Socket` and after previous send/receive blocks.
- Did not add warning suppression switches or pragmas.
- Did not change TLS defaults, fixtures, production code, or suite registration.

Verification to run in a GNAT/Alire environment:

```sh
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
```
