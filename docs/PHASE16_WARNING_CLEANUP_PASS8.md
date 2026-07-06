# Phase 16 Warning Cleanup Pass 8

This pass repairs compile errors introduced by prior warning-cleanup pruning.

Changes:

- Restored local package-body visibility for `Ada.Strings.Fixed` and `Ada.Strings.Unbounded` in test bodies that use short-form string helpers such as `Unbounded_String`, `To_String`, `Length`, `Element`, `Slice`, `Append`, `Null_Unbounded_String`, `To_Unbounded_String`, and `Index`.
- Kept the fix conservative: no warning suppression, no C test fixtures, no pthread-based support, no direct zlib link, and no TLS-default changes.

The intent is to make the test suite compile again after the previous pass removed visibility needed by generated/scaffolded test helpers.
