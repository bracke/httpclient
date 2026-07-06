# Git smart HTTP CONNECT tunnel fixture pass

This pass adds streaming-path test coverage for the successful HTTP proxy
CONNECT handshake shape used by HTTPS Git smart HTTP.

The fixture is intentionally local and deterministic. It accepts an HTTP/1.1
CONNECT request from `Response_Streams.Open`, records the request bytes, returns
`HTTP/1.1 200 Connection Established`, and then closes before completing TLS.
The expected client result is therefore a TLS handshake failure, not a proxy
connection or proxy tunnel failure. That distinction proves the streaming path:

* routes HTTPS requests to the configured HTTP proxy;
* sends a CONNECT request targeting the origin authority;
* sends `Proxy-Authorization` only on the CONNECT request when configured;
* does not leak origin request headers, cookies, authorization, Git headers, or
  request methods before origin TLS begins;
* proceeds to the TLS layer after a 2xx CONNECT response.

The test added in this pass is:

* `Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT`

A full successful TLS loopback fixture still requires a local test certificate
and TLS server endpoint. This fixture covers the proxy handshake boundary without
introducing external network dependencies or real credentials.
