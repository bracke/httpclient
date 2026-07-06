# Phase 16 Warning Cleanup Pass 10

This pass addresses the build errors reported after warning-cleanup pass 9.

## Changes

- Restored package-body visibility for `Ada.Strings.Fixed` and `Ada.Strings.Unbounded` in:
  - `tests/src/http_client-redirects-tests.adb`
  - `tests/src/http_client-release_core-tests.adb`

These test bodies use short-form string helpers such as `Unbounded_String`, `To_String`, `Null_Unbounded_String`, `Append`, and `Index`. The previous warning cleanup left the `with` clauses in place but removed the package-body `use` visibility required by those short-form references.

## Constraints preserved

- No warning suppression was added.
- No C test fixtures were added.
- No direct `-lz` or `-pthread` was added.
- TLS defaults were not weakened.
