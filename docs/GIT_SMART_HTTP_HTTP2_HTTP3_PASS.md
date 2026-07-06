# Git smart HTTP HTTP/2 and HTTP/3 pass

This pass adds explicit buffered Git smart HTTP protocol selection for HTTP/2 and HTTP/3 and prepares the later explicit pull-streaming protocol policy contract.

## Public protocol policy

`Http_Client.Clients.Protocol_Selection_Policy` now contains:

* `Protocol_From_Configuration`
* `Force_HTTP_1_1`
* `Prefer_HTTP_2`
* `Force_HTTP_2`
* `Prefer_HTTP_3`
* `Force_HTTP_3`

`Prefer_HTTP_2` enables h2 ALPN with HTTP/1.1 fallback before request bytes are sent. `Force_HTTP_2` requires h2 for HTTPS requests. `Prefer_HTTP_3` enables the experimental HTTP/3 candidate path with before-send fallback. `Force_HTTP_3` requires the experimental HTTP/3 candidate path and disables fallback.

`Force_HTTP_1_1` now also disables HTTP/2 ALPN for that execution path. It already disables HTTP/3 candidate execution and protocol discovery.

## Git semantics

HTTP/2 and HTTP/3 request mapping preserve Git headers as ordinary lowercase fields:

* `Git-Protocol: version=2`
* `Content-Type: application/x-git-upload-pack-request`
* `Content-Type: application/x-git-receive-pack-request`
* `Accept: application/x-git-upload-pack-result`
* `Accept: application/x-git-receive-pack-result`
* `Accept-Encoding: identity`

Buffered binary request bodies continue to use `Ada.Streams.Stream_Element_Array` through `Http_Client.Request_Bodies.From_Bytes`, with no UTF-8 validation, newline rewriting, NUL stripping, or character-set conversion.

## Boundary of support

HTTP/2 support is available through TLS ALPN, the existing single-stream core, the lower-level HTTP/2 body-stream adapter, and the explicit `Response_Streams` HTTP/2 streaming policy. HTTP/1.1 remains the default large-packfile path unless the caller opts into HTTP/2.

HTTP/3 support remains experimental and depends on a configured QUIC backend. Public HTTP/3 streaming and streaming upload remain outside this release. HTTP/3 does not bypass configured proxy restrictions and rejects unsupported proxy/client-certificate combinations deterministically before unsafe request bytes are sent.

## Tests and examples

Added tests:

* `Test_HTTP2_Git_Metadata_And_Binary_Body`
* `Test_HTTP3_Git_Metadata_And_Binary_Body`

Added examples:

* `git_info_refs_http2_buffered.adb`
* `git_info_refs_http3_buffered.adb`
