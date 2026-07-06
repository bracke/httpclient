# Git smart HTTP Ada Zlib decompression completeness pass

This pass completes the migration away from the temporary C zlib bridge and
adds coverage for the Ada `Zlib`-backed streaming decompression path.

## Implementation consistency checks

* No `src/c/http_client_zlib_bridge.c` file remains in the crate.
* No `http_client_zlib_*` imported C symbols remain in the Ada sources.
* No project file, test project, example project, or benchmark project links
  directly with `-lz`.
* `Http_Client.Decompression` and `Http_Client.Response_Streams` use
  `Http_Client.Zlib_Decompression` as the only decompression adapter.
* `Http_Client.Zlib_Decompression` is an internal package over the external
  Ada `Zlib` dependency declared by `alire.toml` and `httpclient.gpr`.

## Additional streaming test coverage

The AUnit HTTP/1 test package now includes these streaming decompression cases:

* `Test_Response_Stream_Decompression_Chunked_Loopback`
  * gzip content encoding;
  * HTTP/1.1 chunked transfer encoding;
  * chunk extension and trailer parsing before decompression;
  * caller buffer smaller than the decoded payload.
* `Test_Response_Stream_Decompression_Deflate_Loopback`
  * zlib-wrapped `Content-Encoding: deflate`;
  * HTTP/1.1 chunked transfer encoding;
  * byte-array `Read_Some` overload;
  * small caller buffer.
* `Test_Response_Stream_Decompression_Malformed_Gzip_Loopback`
  * malformed gzip data returns `Decompression_Failed` while reading.
* `Test_Response_Stream_Decompression_Decoded_Size_Limit`
  * decoded-size overflow returns `Decoded_Body_Too_Large` while reading.

## Contract retained for Git

Streaming decompression remains opt-in. `Response_Streams.Open` does not add
`Accept-Encoding` automatically. Git smart HTTP examples still request
`Accept-Encoding: identity` by default because Git pkt-line and packfile parsers
should normally see the exact identity Git entity bytes.

When a caller explicitly enables streaming decompression, HTTP transfer decoding
runs first, then gzip or zlib-wrapped deflate content decoding runs
incrementally, and `Read_Some` returns decoded entity bytes subject to the
configured decoded-size limit.

## Verification status

The remaining C bridge files were syntax-checked with GCC:

```sh
gcc -fsyntax-only -Wall -Wextra src/c/http_client_tls_bridge.c
gcc -fsyntax-only -Wall -Wextra src/c/http_client_crypto_bridge.c
```

Ada compilation and AUnit execution still require a GNAT/GPRbuild environment
with the Ada `Zlib` dependency available.
