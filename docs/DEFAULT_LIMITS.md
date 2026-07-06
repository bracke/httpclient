# Default limits and conservative settings

This file records the release defaults that users most often need while configuring the client. The owning `.ads` files remain authoritative; this document must be updated whenever those defaults change.

| Area | Default |
| --- | --- |
| Buffered execution total response limit | `Max_Response_Size = 16_777_216` bytes |
| Buffered execution header section limit | `Max_Header_Size = 65_536` bytes |
| Buffered execution header line limit | `Max_Header_Line_Size = 8_192` bytes |
| Buffered execution body limit | `Max_Body_Size = 16_777_216` bytes |
| Download-to-file limit | `Download_Options.Max_Download_Size = Default_Max_Download_Size` by default, currently 1 GiB |
| Read buffer size | `Read_Buffer_Size = 4_096` bytes |
| TCP connect/read/write timeout intent | `0` milliseconds each, meaning normal blocking socket behavior |
| TLS verification | certificate and hostname verification enabled; SNI enabled for DNS names |
| Redirects | disabled; redirect helper cap is `Max_Redirects = 5` |
| HTTPS-to-HTTP redirects | blocked |
| Cross-origin credentials on redirects | stripped |
| Retries | disabled; `Maximum_Attempts = 1` |
| Retry-After cap when enabled | `60_000` milliseconds |
| Cookie jar | absent unless supplied; default jar limits are `300` total cookies, `50` per domain, names `256` bytes, values `4_096` bytes, generated Cookie header `16_384` bytes |
| Decompression | disabled unless configured; decoded-output default cap is `4_194_304` bytes |
| Streaming response limits | headers `65_536`, header line `8_192`, body `16_777_216`, read buffer `4_096` |
| In-memory cache | disabled; enabled defaults are `64` entries, `8 MiB` total body bytes, `1 MiB` per response body |
| Persistent cache | explicit; defaults are `64` entries, `8 MiB` total stored bytes, `1 MiB` body bytes per entry, `64 KiB` metadata, `512` scanned directory entries |
| Encrypted persistent cache | same storage limits as persistent cache; caller supplies key material/configuration explicitly |
| Diagnostics | disabled unless a context is supplied; header values hidden, body previews disabled, preview length `0`, cookie names redacted |
| Connection pooling | disabled; enabled defaults are `8` total idle connections, `2` idle per key, `300` second max connection age, `60` second idle age, `100` requests per connection |
| Async execution | explicit; defaults are `2` workers and `16` queued requests |
| HTTP/2 | high-level buffered execution prefers h2 when TLS ALPN negotiates it; protocol defaults include frame size `16_384`, header list `65_536`, body `16_777_216`, per-stream buffered bytes `16_777_216`, aggregate queued body bytes `67_108_864`, one active streamed response, one active upload stream, local max concurrent streams `1` |
| HTTP/3 | disabled and experimental; defaults include no fallback, unavailable QUIC backend, frame size `16_384`, header list `65_536`, server push disabled, 0-RTT disabled |
| QUIC options | backend unavailable; idle timeout `30_000` ms, connection timeout `10_000` ms, bidirectional streams `1`, unidirectional streams `3`, datagram size `1_200`, 0-RTT disabled |
| Alt-Svc parser | maximum `8` alternatives per header, header length `8_192`, maximum accepted age `86_400` seconds |
| HTTPS/SVCB record model | maximum `8` records and `4` ALPN values per record |
| Protocol discovery cache | disabled; maximum `64` origins and `4` alternatives per origin when explicitly enabled |
| Multipart helper constants | boundary `70`, field name `128`, file name `255`, content type `128`, part header `4_096`, part count `1_024` |

## Compatibility rule

Changing a default that affects security, wire behavior, retry/redirect behavior, cache-key behavior, credential forwarding, diagnostics redaction, ownership, or fallback is a breaking change after the compatibility promise begins. Changing only an internal buffer size may be compatible when public limits, statuses, and observable behavior are preserved.


Explicit file downloads use `Download_To_File` / `Execute_To_File` and stream to disk. They do not use the buffered `Max_Body_Size` cap. Instead, they use the separate `Default_Max_Download_Size` cap, currently 1 GiB. Callers can adjust `Download_Options.Max_Download_Size`; set it to `0` only for no total-file bound.

## Response metadata accessors

`Http_Client.Responses.Content_Type`, `Media_Type`, and `Charset` read already-stored response headers. They do not inspect response bodies, do not sniff MIME types, and do not change the buffered `Max_Body_Size` or download `Max_Download_Size` limits.
