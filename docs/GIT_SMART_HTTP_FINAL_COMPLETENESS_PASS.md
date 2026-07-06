# Git smart HTTP final completeness pass

This pass is limited to the `Http_Client` crate. Downstream VCS adapters are not
part of this repository. In particular, `Version.Transport.Http` remains part of
the separate `version` project and must not be implemented in this crate.

## Static consistency checks performed

The source archive was inspected for stale Git smart HTTP limitations and
cross-document drift after the HTTP/1.1 streaming, upload, proxy, protocol-policy,
and Ada-Zlib decompression passes.

Confirmed in the tree:

* the Git examples list contains the current Git-oriented examples:
  * `git_info_refs_stream.adb`;
  * `git_upload_pack_stream.adb`;
  * `git_receive_pack_fixed_upload.adb`;
  * `git_receive_pack_chunked_upload.adb`;
  * `git_receive_pack_chunked_upload_trailers.adb`;
  * `git_info_refs_https_proxy_stream.adb`;
  * `git_info_refs_https_socks_stream.adb`;
  * `git_info_refs_http2_buffered.adb`;
  * `git_info_refs_http3_buffered.adb`;
  * `git_upload_pack_http2_stream.adb`;
  * `git_info_refs_http3_stream.adb`;
* `examples/examples.gpr` includes the SOCKS Git example as well as the CONNECT
  Git example;
* no `src/c/http_client_zlib_bridge.c` file remains;
* no project, test, example, or benchmark file contains a direct `-lz` linker
  switch;
* no imported C zlib streaming symbols remain;
* `Http_Client.Zlib_Decompression` is the only decompression adapter boundary;
* the README, integration contract, documentation index, and release
  verification procedure now describe Git smart HTTP as a crate-local
  `Http_Client` transport contract rather than as work inside any downstream
  adapter package;
* the public documentation continues to state the remaining intentional
  limitations: successful tunnel/TLS fixtures remain desirable, streaming Git should use HTTP/1.1, and
  release readiness still requires a GNAT/GPRbuild/AUnit run in an Ada toolchain
  environment.

## Git smart HTTP behavior covered by current sources

The current source tree contains code, examples, and/or AUnit coverage for:

* binary-safe buffered bodies;
* binary-safe caller-buffered response streaming;
* HTTP/1.1 chunked response decoding;
* fixed-length streaming upload;
* HTTP/1.1 chunked request upload for unknown-length producers;
* explicit `Expect: 100-continue` for buffered and streaming request bodies;
* early final `Expect` responses with fixed-length or chunked response bodies;
* opt-in streaming gzip and zlib-wrapped deflate decompression through the Ada
  `Zlib` dependency;
* HTTP/1.1 `Force_HTTP_1_1` policy for high-level execution and explicit
  HTTP/1.1/HTTP/2/HTTP/3 streaming protocol policies;
* HTTPS-over-HTTP-proxy CONNECT routing and credential separation;
* HTTPS-over-SOCKS5 tunnel routing, byte-array streaming, chunked response decoding, buffered binary POST, and credential separation remain part of the intended capability surface; the first release package excludes C SOCKS5/TLS fixtures and uses Ada task-based fixtures instead;
* Git-shape pkt-line-like binary response streaming tests.

## Remaining crate-local release gates

The following items remain verification gates rather than additional feature
requirements:

1. Run `alr build` or `gprbuild -P httpclient.gpr` with GNAT/GPRbuild.
2. Build `examples/examples.gpr`.
3. Build and run the AUnit suite.
4. Build with the Ada `zlib` dependency resolved.
5. Keep the Phase 4 direct TLS, Phase 5 HTTPS-over-CONNECT, and Phase 6 HTTPS-over-SOCKS5 loopback fixtures green in release verification.



### HTTPS-over-SOCKS5 Phase 6 completeness pass coverage

Phase 6 includes deterministic local SOCKS5-over-TLS tests for no-auth and username/password negotiation, configured-CA validation, origin-host SNI/hostname verification, credential/header/body isolation before tunnel establishment, byte-array streaming, chunked response decoding, buffered POST, fixed-length streaming upload, unknown-length chunked upload, request trailers, `Expect: 100-continue`, and negative SOCKS/TLS failures. The SOCKS proxy fixture records only SOCKS greeting/auth/CONNECT bytes before tunnel success; origin `Authorization`, cookies, Git headers, request bodies, paths, trailers, and Expect headers are asserted to remain inside the TLS tunnel.
