# Git smart HTTP Phase 1 completeness pass

This pass tightens the Phase 1 public API inventory freeze after the initial
archive update.

Completed adjustments:

* documented that `http_client-redirects.ads` and `http_client-configuration.ads`
  are not current source files; the redirect and reusable configuration surface
  is exported by `Http_Client.Clients`;
* added the configured-client, retry-helper, decompression-helper, URI/cookie,
  proxy, TCP/TLS, and HTTP/2/HTTP/3 body-stream public surface to
  `GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md`;
* extended the compile-only API stability source to exercise
  `From_Unknown_Length_Stream` without trailers, `Client_Configuration`,
  default header mutation, configuration validation, and client configuration;
* added the exact Phase 1 command set to `RELEASE_VERIFICATION.md`;
* kept the crate generic: no downstream `Version.Transport.Http` adapter was
  added;
* kept the C zlib bridge removed and did not add direct `-lz` linkage.

The intended verification command remains:

```sh
alr build
alr exec -- gprbuild -P tests/tests.gpr
./tests/bin/tests
alr exec -- gprbuild -P tests/api_stability/api_stability.gpr
alr exec -- gprbuild -P examples/examples.gpr
alr exec -- gprbuild -P tools/tools.gpr
./tools/bin/check_git_smart_http_release
```
