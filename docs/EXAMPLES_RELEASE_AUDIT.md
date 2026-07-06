# Examples release audit

Phase 15 examples audit result: the examples are current by static release-audit criteria, subject to final real-toolchain compilation.

## Scope checked

The audit compared:

* `examples/examples.gpr` main entries;
* files present under `examples/src`;
* `docs/EXAMPLES.md` manifest entries;
* public `with Http_Client.*` package references;
* release-critical safety rules for Git examples;
* stale/prohibited source patterns.

## Static results

* `examples/examples.gpr` lists 56 executable example mains.
* All 56 listed mains exist under `examples/src`.
* No executable example under `examples/src` is omitted from `examples/examples.gpr`; an obsolete unlisted `examples.adb` file was removed during this pass.
* `example_helpers.adb` is intentionally a helper body and is not an executable main.
* `docs/EXAMPLES.md` lists every compile-checked example main.
* Every `with Http_Client.*` package reference in examples resolves to a matching `src/*.ads` package by static package-name mapping.
* No `Response_Body` string-path usage was found in `examples/src`.
* No positive HTTPS example sets `Disable_Certificate_Verification` to `True`.
* No `Version.Transport.Http` or downstream adapter package is present in examples.
* No removed C zlib bridge names, direct `-lz`, or C zlib API symbols were found in examples.
* No release-blocker marker was found in examples.

## Release guard update

The release guard now checks the complete compile-checked example manifest, not only the Git smart HTTP subset. For every example main it requires:

* source file exists under `examples/src`;
* the file is listed in `examples/examples.gpr`;
* the file is listed in `docs/EXAMPLES.md`.

The Git smart HTTP subset still receives stricter checks for binary-body safety, TLS verification defaults, README visibility, and reserved-origin policy.

## Known limitation

This audit is static. The final proof that examples are correct requires:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

or, in the Alire release-verification path:

```sh
alr exec -- gprbuild -P examples/examples.gpr
```

The current sandbox does not provide `alr`, `gprbuild`, or `gnat1`, so this document does not claim that compilation was executed here.
