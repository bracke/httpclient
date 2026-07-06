# Git smart HTTP Expect: 100-continue completeness pass

This pass tightens the explicit HTTP/1.1 `Expect: 100-continue` behavior added for Git-style uploads.

## Correctness fixes

* Buffered request bodies are no longer serialized together with the header block when the request contains `Expect: 100-continue`.
* For `Expect: 100-continue`, the HTTP/1.1 client now serializes headers only, waits for an interim response, and writes buffered bytes only after a `100 Continue` response.
* The same header-only behavior is used by the streaming response execution path.
* Unknown-length streaming bodies still use `Transfer-Encoding: chunked`; the chunked upload is also withheld until `100 Continue` is received.
* If the server returns a final response instead of `100 Continue`, the request body is not sent.

## Added tests

The AUnit suite now includes loopback tests that prove:

* a buffered POST with `Expect: 100-continue` sends only headers before the interim response;
* the buffered body is sent after `100 Continue`;
* the final response after the upload is returned normally;
* a final `417 Expectation Failed` response before `100 Continue` is exposed to the caller; and
* the request body is not sent when the server rejects the expectation.

## Git impact

Git smart HTTP can use `Expect: 100-continue` for large upload-pack or receive-pack request bodies without risking premature upload bytes before the server has accepted the request. The feature remains explicit: the library does not add `Expect` automatically.
