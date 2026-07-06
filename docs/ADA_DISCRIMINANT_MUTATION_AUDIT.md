# Ada discriminant mutation audit

Phase 15 included a static pass for accidental attempts to mutate Ada discriminants after object creation.

## Scope

The pass inspected Ada source and project files for:

* discriminated type declarations;
* direct component assignments to known discriminant names;
* whole-object assignments involving discriminated task/protected objects;
* allocation and initialization sites for discriminated objects;
* misleading field names that could be confused with discriminants.

Files inspected included:

* `src/**/*.ads` and `src/**/*.adb`;
* `tests/**/*.ads` and `tests/**/*.adb`;
* `examples/**/*.adb`;
* `tools/**/*.ads` and `tools/**/*.adb`;
* `benchmarks/**/*.adb`;
* checked-in `.gpr` project files.

## Discriminated types found

The only discriminated Ada types found in the source tree are internal task/protected types in `src/http_client-async.adb`:

* `protected type Work_Queue (Capacity : Positive)`;
* `protected type Worker_Counter (Initial : Natural)`;
* `task type Worker (Owner : State_Access)`.

These discriminants are set only when the corresponding protected/task objects are created:

* `new Work_Queue (Configuration.Max_Queued)`;
* `new Worker_Counter (Configuration.Max_Workers)`;
* `new Worker (Item.Pool_State)`.

## Result

No attempted discriminant assignments were found.

Specifically, no source file assigns to:

* `.Capacity` of a `Work_Queue` object;
* `.Initial` of a `Worker_Counter` object;
* `.Owner` of a `Worker` task object.

No release code was changed by this pass. This audit only added this documentation note and recorded the check in the final Phase 15 audit report.

## Toolchain note

This was a static source audit. The sandbox used for this pass did not provide `alr` or `gprbuild`, so final confirmation still requires the normal release verification build on a real Ada toolchain.
