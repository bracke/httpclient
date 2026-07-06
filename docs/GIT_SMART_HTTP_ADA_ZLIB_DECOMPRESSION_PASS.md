# Git smart HTTP Ada Zlib decompression pass

This pass removes the previously introduced C zlib bridge from `Http_Client`.
Compression and decompression now flow through the Ada package
`Http_Client.Zlib_Decompression`, which is the only internal adapter that
references the external Ada `Zlib` library.

## Implemented changes

* Removed `src/c/http_client_zlib_bridge.c` from the crate.
* Removed all imported C zlib symbols from `Http_Client.Decompression`.
* Removed all imported C zlib streaming symbols from
  `Http_Client.Response_Streams`.
* Added `src/http_client-zlib_decompression.ads` and
  `src/http_client-zlib_decompression.adb`.
* Added an explicit `alire.toml` dependency on `zlib`.
* Added `with "zlib";` to `httpclient.gpr`.
* Removed direct `-lz` linker switches from tests, examples, and benchmarks.
* Updated installation, platform, packaging, README, and Git smart HTTP docs to
  describe the Ada Zlib dependency instead of a C zlib bridge.

## Adapter contract

`Http_Client.Zlib_Decompression` expects an Ada `Zlib` package that provides
`Filter_Type`, `Inflate_Init`, `Translate`, `Flush`, `Stream_End`, `Is_Open`,
`Close`, `Header_Type`, `GZip`, and `Zlib_Header`. The adapter maps `Content-Encoding: deflate` to zlib-wrapped Deflate only and maps Zlib exceptions
into deterministic `Http_Client.Errors.Result_Status` values.

## Behavioral contract

Buffered and streaming decompression behavior is unchanged:

* decompression remains opt-in;
* gzip and zlib-wrapped deflate are supported;
* HTTP transfer decoding still runs before content decompression;
* decoded-size limits remain enforced;
* malformed compressed content returns `Decompression_Failed`;
* decoded-size overflow returns `Decoded_Body_Too_Large`;
* unsupported encodings follow `Unsupported_Policy`.

## Verification status

The sandbox still does not contain GNAT/GPRbuild, so Ada compilation and AUnit
execution were not run here. The previous C bridge syntax check is no longer
relevant because the zlib C bridge file has been removed.
