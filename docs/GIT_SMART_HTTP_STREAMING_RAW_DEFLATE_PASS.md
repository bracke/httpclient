# Git smart HTTP streaming raw-deflate pass

Phase 2 completes the response decompression surface needed by Git smart HTTP consumers without changing the safest Git default.

Implemented behavior:

- streaming decompression remains opt-in through `Streaming_Options.Enable_Decompression`;
- the basic streaming path still does not add `Accept-Encoding` automatically;
- `Content-Encoding: gzip` remains supported;
- `Content-Encoding: deflate` defaults to zlib-wrapped deflate through `Zlib_Wrapped_Only`;
- raw deflate is available explicitly through `Raw_Only`;
- tolerant `deflate` handling is available through `Auto_Zlib_Then_Raw`;
- decompression still runs after HTTP transfer decoding, so chunk framing and trailers are not exposed as body bytes;
- decoded-size limits are enforced on the decoded stream;
- decoded bytes remain binary data suitable for Git pkt-line and packfile consumers;
- the standalone Ada `Zlib` dependency remains isolated behind `Http_Client.Zlib_Decompression`;
- no C zlib bridge and no direct `-lz` dependency are introduced.

Git callers that need maximum predictability should still send `Accept-Encoding: identity` and leave streaming decompression disabled. Phase 2 adds capability for callers that explicitly choose compressed responses.
