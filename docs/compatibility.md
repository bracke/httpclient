# Compatibility

A breaking change includes removing or renaming a stable public package, type, field, status value, or subprogram; changing documented default security behavior; changing status-return semantics; changing wire serialization for equivalent requests; changing cache-key semantics; changing redirect or retry policy; weakening diagnostics redaction; changing exception/status policy; or changing documented ownership and lifetime semantics.

Allowed compatible changes include additive APIs, new optional features disabled by default, new statuses only when existing control-flow guarantees remain meaningful, stricter rejection of unsafe malformed input, documentation fixes, warning cleanup, and internal optimization that preserves public behavior.

Deprecated APIs should be documented with a replacement, preserved for a defined compatibility window where practical, and removed only in a major version. Compiler-level deprecation pragmas may be used consistently, but they should not turn normal builds into failures unexpectedly.
