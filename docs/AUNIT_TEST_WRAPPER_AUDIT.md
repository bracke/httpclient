# AUnit Test Wrapper Audit

Phase 15 follow-up pass.

## Purpose

This pass reviewed registered AUnit routines that only delegated to another
`Test_*` procedure.  The objective was to remove pointless indirection while
preserving fixture cleanup wrappers where the wrapper contributes behavior.

## Result

- Registered AUnit routines: 390
- Directly registered real `Test_*` routines after this pass: 380
- Remaining `AUnit_Test_*` wrapper registrations: 10
- Trivial delegate-only wrappers removed: 319
- Pre-existing direct registered routines normalized to AUnit-compatible
  signatures: 56

The remaining wrappers are intentional.  They are not simple delegation-only
wrappers; they preserve fixture cleanup or other AUnit-boundary behavior.

## Rationale

AUnit registered routines need a registration-compatible profile.  Tests that
need no wrapper now use that profile directly:

```ada
procedure Test_Name
  (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
is
   pragma Unreferenced (Case_Context);
begin
   ...
end Test_Name;
```

This keeps the registered routine and the actual test body as the same
subprogram.  It avoids the previous pattern where a registered
`AUnit_Test_*` routine called a separate parameterless `Test_*` procedure
without adding any behavior.

## Remaining wrapper justification

Remaining `AUnit_Test_*` wrappers are limited to fixture-sensitive tests, such
as asynchronous client cleanup. They are kept at
the AUnit boundary so an unexpected exception still executes the required
cleanup before the exception is re-raised to AUnit.

## Toolchain note

This was a static source pass.  The sandbox used for this audit does not provide
`alr` or `gprbuild`, so the real Ada toolchain must still run the normal release
verification commands.
