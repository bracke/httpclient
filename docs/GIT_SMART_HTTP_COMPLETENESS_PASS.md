# Git smart HTTP completeness pass

This pass verifies the narrow Git smart HTTP surface after the first implementation round.

## Completed in this pass

* Added `Test_Response_Stream_Git_Pkt_Line_Chunked_Binary` to the AUnit streaming suite.
  * The fixture uses loopback only.
  * It returns a Git-shape `/repo.git/git-upload-pack` response.
  * The response is HTTP/1.1 chunked.
  * The response includes a chunk extension and a bounded trailer.
  * The decoded entity contains NUL and a byte above 127.
  * The caller buffer is smaller than the chunks.
  * The test concatenates all `Read_Some` byte-array results and asserts exact decoded bytes.
* Extended `Test_HTTP1_Response_Reader_Fragmented_And_Framed` with a buffered Git-like chunked binary response.
  * The scripted transport fragments reads at two bytes, so chunk metadata is split across reads.
  * The decoded body is asserted exactly.
* Tightened `Response_Streams.Last_Status` documentation so ordinary EOF is described as `End_Of_Stream`, not `Ok`.
* Updated README and the Git integration contract with the new harness coverage. The HTTPS-over-HTTP-proxy CONNECT limitation recorded at that time was later removed by `GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_PASS.md`.

## Still intentionally not added

* Request trailers for chunked request uploads. Unknown-length HTTP/1.1 request bodies use `Transfer-Encoding: chunked`; explicit request-body trailers are declared with `Trailer` and emitted after the terminating chunk.
* Streaming decompression is now implemented as an explicit `Response_Streams` option; Git examples still request `Accept-Encoding: identity` by default.
* Superseded by `GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_PASS.md` and `GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md`: HTTPS-over-HTTP-proxy CONNECT and HTTPS-over-SOCKS5 are implemented for buffered and streaming HTTP/1.1 paths.
* Successful live backend fixtures for HTTP/2 and HTTP/3 large-packfile streaming. The API and deterministic adapter boundaries exist; production proof still depends on the real h2/QUIC backends and AUnit execution.

## Build status in this sandbox

The sandbox does not include the Ada front end (`gnat1`) or `gprbuild`, so this pass could not execute `alr build`, `gprbuild`, or the AUnit test binary here. The changes are source-level and limited to tests, docs, and one GNATdoc correction.
