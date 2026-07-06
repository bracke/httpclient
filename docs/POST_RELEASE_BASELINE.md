# Post-release baseline: 1.0.0

Date: 2026-05-17

This document freezes the intended baseline after packaging the `httpclient` 1.0.0 release. Future feature work should start from a new post-release planning context instead of reopening Phase 16 for feature development.

## Released version

- Crate: `httpclient`
- Version: `1.0.0`
- Suggested tag: `v1.0.0`
- Root project: `httpclient.gpr`
- Alire manifest: `alire.toml`

The real VCS commit and pushed tag are intentionally not asserted by this source package. The maintainer must record the concrete commit and tag in the repository release process when the release is committed and tagged.

## Verification baseline

The release baseline expects the following commands to pass from a clean source checkout and from a clean unpacked source archive:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_release_surface
./tools/bin/check_aunit_suite
./tools/bin/check_security_corpus
./tools/bin/check_git_smart_http_release
alr exec -- gprbuild -P benchmarks/http_client_benchmarks.gpr
```

If any release-blocking packaging or metadata fix is made after this baseline, rerun the full command set and rebuild the source archive.

## Artifact checksum

The Phase 16 source archive checksums are recorded in the accompanying `httpclient-1.0.0.SHA256SUMS` file. If the maintainer rebuilds the archive during publication, regenerate and replace those checksums.

## Public API compatibility expectations

Stable public packages listed in `docs/RELEASE_SURFACE_MANIFEST.md` carry the 1.0 compatibility expectation. Future minor releases may add compatible APIs, add optional features disabled by default, tighten validation for malformed/unsafe input where deterministic statuses are preserved, and improve documentation or internals.

Breaking changes require a major-version plan unless they correct a release-blocking safety issue. Compatibility-sensitive changes include public package removal, type or field renaming, default security weakening, changed status semantics, changed wire serialization, changed redirect/retry defaults, weakened diagnostics redaction, changed exception policy, or changed ownership/lifetime behavior.

Experimental HTTP/3 and QUIC packages remain outside the stable execution promise. They may evolve when a production HTTP/3 backend is deliberately implemented, but forced HTTP/3 unsupported/no-backend behavior must remain deterministic until that implementation exists.

## Deferred work and known limitations

- Production HTTP/3 execution backend is not part of this release.
- h2c is unsupported.
- HTTP/2 server push is unsupported.
- Extended CONNECT, MASQUE, CONNECT-UDP, WebTransport, SOCKS UDP ASSOCIATE, and SOCKS BIND are unsupported.
- Browser behavior is intentionally absent.
- Automatic OS/browser credential-store integration is absent.
- PAC/WPAD and browser proxy discovery are absent.
- Platform CA-store and OpenSSL discovery details remain environment/toolchain concerns.
- Cancellation remains cooperative at documented checkpoints.

## Next development base

Create a new development branch or planning context from the tagged 1.0.0 commit. Do not mix new feature work into the release branch. Accept only release-blocking fixes on the release branch, and rebuild/reverify the archive after any such fix.
