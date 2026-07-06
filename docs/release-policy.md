# Release policy

The released crate is versioned as `1.0.0`. Stable packages listed in `PUBLIC_PACKAGES.md` and `RELEASE_SURFACE_MANIFEST.md` carry the 1.0 compatibility promise. Experimental HTTP/3 and QUIC packages may change before production backend support is finalized.

Minor releases may add APIs, add optional features disabled by default, improve documentation, fix bugs, reject unsafe malformed input more strictly, improve diagnostics redaction, and optimize internals while preserving public behavior. Major releases are required for intentional incompatible API removals or semantic changes after the compatibility promise begins.
