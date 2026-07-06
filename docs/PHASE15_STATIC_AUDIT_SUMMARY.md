# Phase 15 static audit summary

This source tree was updated from the Phase 14 ZIP for the Phase 15 final release audit.

Key release-blocking fixes:

* fixed stale `http_client.gpr` references to the actual `httpclient.gpr`;
* fixed `benchmarks/http_client_benchmarks.gpr`;
* removed checkout-local Alire state directories from the package tree;
* removed the root `zlib` path pin and kept `zlib = "*"` as an external dependency declaration;
* updated the Git smart HTTP release guard to check the actual root project and dependency markers;
* replaced stale CI references to missing Python tools with the Ada tools present in `tools/tools.gpr`;
* refreshed `docs/GIT_SMART_HTTP_FINAL_AUDIT_PASS.md`.

`alr` and `gprbuild` were not available in the editing sandbox, so the final build/test commands still need to be run by a maintainer before tagging.

## Completeness pass additions

The follow-up completeness pass also:

* declared `project-files = ["httpclient.gpr"]` in `alire.toml` so Alire exports the intended root project explicitly;
* added the AUnit-suite registration checker to the CI release-tooling sequence;
* replaced stale `with "zlib.gpr";` wording in the Ada Zlib phase note with the actual `with "zlib";` project dependency form;
* reworded the `Retry-After` HTTP-date limitation in the public retry spec so it is an explicit release limitation, not stale future-work language.

* converted checked-in `config/`, `examples/config/`, and `tests/config/` files from host-specific generated Alire artifacts into stable fallback configuration files for direct GPRbuild use;
* made `examples/examples.gpr` import `../httpclient.gpr` explicitly instead of relying on config-project dependency side effects.
