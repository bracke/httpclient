# Ada Keyword Identifier Audit

Phase 15 keyword-identifier audit pass.

## Scope

This pass searched Ada source and project files for Ada reserved words used where identifiers are expected, with particular attention to:

- object and parameter declarations;
- local variables;
- subprogram names;
- package/type/subtype/entry declarations;
- test-only helper declarations;
- example and tool sources.

The search covered:

- `src/*.ads`
- `src/*.adb`
- `tests/src/*.ads`
- `tests/src/*.adb`
- `examples/src/*.adb`
- `tools/src/*.ads`
- `tools/src/*.adb`
- `*.gpr` project files

## Findings

The pass found compile-relevant uses of `Body` as an object name in test sources. Ada reserved words are case-insensitive, so `Body` is not a valid identifier.

The affected test locals were renamed mechanically:

- `tests/src/http_client-http2-tests.adb`
  - `Body` -> `Stream_Body`
- `tests/src/http_client-http2-trailers_tests.adb`
  - `Body` -> `Request_Body`
- `tests/src/http_client-binary_safety_tests.adb`
  - `Body` -> `Request_Body`

No public API names were changed.

## Result

After the targeted fixes, the keyword scan found no remaining reserved words in declaration positions that appear to be identifiers.

This pass did not run `alr` or `gprbuild` because the audit sandbox does not provide the Ada toolchain. The real release gate remains the Phase 15 verification command sequence documented in `RELEASE_VERIFICATION.md` and `GIT_SMART_HTTP_FINAL_AUDIT_PASS.md`.
