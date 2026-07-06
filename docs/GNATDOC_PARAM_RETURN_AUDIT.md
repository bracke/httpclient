# GNATdoc `@param` / `@return` Audit

This pass audited all Ada specification files in the release tree for
GNATdoc-style subprogram parameter and result documentation.

Scope checked:

- `src/**/*.ads`
- `tests/**/*.ads`
- `examples/**/*.ads`
- `tools/**/*.ads`
- generated-fallback `config/**/*.ads` files, where present

The audit looked for every visible Ada subprogram specification whose first
line begins with `function`, `procedure`, `overriding function`, or
overriding `procedure`. For each declaration it checked the adjacent GNATdoc
comment block before or after the declaration for:

- one `@param <Name>` entry for every declared formal parameter;
- one `@return` entry for every function.

## Fixes made

The pass added or corrected GNATdoc tags for the remaining undocumented
subprogram specs in:

- `src/http_client-responses.ads`
- `src/http_client-zlib_decompression.ads`
- `src/http_client-http3-frames.ads`
- `src/http_client-request_bodies.ads`
- `src/http_client-cancellation.ads`
- `src/http_client-multipart.ads`
- `src/http_client-transports-tls.ads`
- `src/http_client-transports-tcp.ads`
- `src/http_client-response_streams.ads`
- `src/http_client-async.ads`
- `examples/src/example_helpers.ads`
- `tools/src/check_support.ads`
- `tests/src/all_suites.ads`
- `tests/src/http_suite.ads`
- `tests/src/http_client-binary_test_data.ads`
- AUnit section test-case specs under `tests/src/*tests.ads` and
  `tests/src/*_tests.ads`.

The pass also corrected a stale parameter tag in
`src/http_client-http3-frames.ads`: `Parse_Frame` documents its `D` formal as
`@param D`, not `@param Data`.

## Static result

```text
TOTAL_ADS_FILES_CHECKED       108
TOTAL_SUBPROGRAM_SPECS        634
MISSING_GNATDOC_TAGS          0
```

This was a documentation-only pass. It did not change public API signatures or
runtime behavior.

The real Ada build remains required before release publication:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```
