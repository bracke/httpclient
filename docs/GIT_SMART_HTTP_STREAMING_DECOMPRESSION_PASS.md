# Git smart HTTP streaming decompression pass

This pass adds opt-in streaming content decompression to `Http_Client.Response_Streams`.

Implemented behavior:

* `Streaming_Options.Enable_Decompression` defaults to `False`.
* When enabled, `Content-Encoding: gzip` and zlib-wrapped `deflate` are decoded incrementally.
* HTTP transfer decoding still runs first; callers never see chunk-size lines, chunk CRLF, or trailers.
* Decoded-size limits use `Streaming_Options.Decompression.Maximum_Decoded_Body_Size`.
* Malformed compressed data returns `Decompression_Failed`.
* Decoded-size overflow returns `Decoded_Body_Too_Large`.
* Unsupported or stacked content encodings obey `Unsupported_Policy`.
* `Response_Streams.Open` does not add `Accept-Encoding`; callers must request compression explicitly.

Added tests:

* `Test_Response_Stream_Decompression_Chunked_Loopback` verifies chunked gzip streaming with chunk extensions and trailers, using a caller buffer smaller than the decoded body.
* `Test_Response_Stream_Decompression_Malformed_Gzip_Loopback` verifies deterministic failure for malformed compressed response data.

Recommended Git default remains `Accept-Encoding: identity`; streaming decompression is available for callers that intentionally negotiate compressed HTTP entities.

## Dependency update

The original C zlib streaming bridge has been removed. Streaming decompression now uses `Http_Client.Zlib_Decompression`, an Ada adapter over the external Ada `Zlib` library.
