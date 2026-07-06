# Phase 16 completeness pass

Date: 2026-05-17

This pass re-audits the packaged `httpclient` 1.0.0 source tree after the Phase 16 release packaging step. It is a release-engineering completeness pass only; no runtime protocol behavior or public API shape is changed.

## Findings fixed

- Updated fallback root crate configuration files under `config/` from release metadata to `1.0.0` so non-Alire direct GPRbuild metadata matches `alire.toml` and `Http_Client.Version`.
- Updated example crate metadata under `examples/` from development-version metadata to `1.0.0` so packaged examples no longer carry development-version metadata.
- Updated current release-policy, HTTP/3, proxy, and 1.0.0 release-note wording so current-facing documentation describes the final 1.0.0 release instead of the 1.0.0 release state.
- Reworded the post-release baseline note so unresolved VCS identifier language is not mistaken for published release metadata.

## Package cleanliness checks

The completeness pass checked the unpacked source package for:

- generated object/build outputs (`*.o`, `*.ali`, `obj`, `bin`);
- temporary archives and scratch logs;
- stale release-blocking version strings in active metadata;
- actual C zlib bridge files;
- direct `-lz` linkage in code/project files;
- downstream `Version.Transport.Http` source/example/test adapters;
- incomplete-content markers in active source, docs, examples, tests, and tools.

No changelog-style history is retained for this first release.

## Result

The package is more coherent as a final 1.0.0 source release. The maintainer still must run the Ada/Alire verification commands on a configured toolchain before publishing, because this sandbox does not provide `alr` or `gprbuild`.
