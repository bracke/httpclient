# Decompression

HttpClient performs content decompression in three explicit places: the high-level buffered client default creates a bounded decoded final-response view, callers may use the buffered decompression API directly, and callers may enable streaming response decompression. The transport, TLS, proxy, chunked-transfer, HTTP/2, and HTTP/3 layers do not directly depend on Zlib.

`Http_Client.Zlib_Decompression` is the only bridge to the standalone Ada `Zlib` crate. The adapter owns a `Zlib.Filter_Type` and maps wrappers as follows:

| HTTP `Content-Encoding` | Zlib header mode | Notes |
| --- | --- | --- |
| `gzip` | `Zlib.GZip` | gzip header, Deflate payload, CRC/ISIZE trailer validation |
| `deflate` | `Zlib.Zlib_Header` by default | zlib-wrapped Deflate with Adler validation |
| `deflate` | raw-deflate header mode when configured | raw Deflate with no zlib wrapper |

HTTP `deflate` is standards-conservative by default: `Decompression_Options.Deflate_Mode = Zlib_Wrapped_Only`. Callers that need raw interoperability set `Raw_Only`; callers that want tolerant handling set `Auto_Zlib_Then_Raw`. `Default_Client_Configuration.Enable_Decompression` is True for ordinary buffered responses, while `Strict_Client_Configuration.Enable_Decompression` is False for exact wire-body callers. Decoded bytes remain binary data and decoded-size limits still apply.

Malformed gzip/zlib/raw-deflate input, truncated compressed bodies, bad gzip CRC/ISIZE values, bad zlib Adler checksums, and adapter lifecycle misuse are reported as `Http_Client.Errors.Decompression_Failed`. `Zlib.Zlib_Error` and `Zlib.Status_Error` are contained inside the adapter and are not part of the public HttpClient error surface.

Streaming decompression runs after transfer decoding. This means chunked transfer framing is removed first; the decompression adapter receives only content-encoded entity bytes. Small caller buffers and compressed-body splits are supported: one compressed input fragment is not assumed to correspond to one decoded output fragment.
