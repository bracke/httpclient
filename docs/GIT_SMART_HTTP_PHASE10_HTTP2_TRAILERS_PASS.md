# Git smart HTTP Phase 10 HTTP/2 trailers pass

Phase 10 adds bounded HTTP/2 request and response trailer handling on top of the Phase 9 multiplexed HTTP/2 connection model.

Implemented semantics:

- HTTP/2 request trailers are modeled as trailing HEADERS with END_STREAM after request DATA.
- Empty HTTP/2 request bodies with trailers send initial request HEADERS, then trailing HEADERS with END_STREAM and no DATA.
- Buffered and producer-backed HTTP/2 request bodies send DATA first and trailing HEADERS only after body completion.
- HTTP/2 trailers never use HTTP/1.1 chunked transfer framing.
- HTTP/2 request trailers do not require an HTTP/1.1 Trailer declaration field.
- Transfer-Encoding is rejected in HTTP/2 trailers and is not part of the HTTP/2 trailer path.
- Pseudo-headers and connection/framing/sensitive names are rejected in trailers.
- HTTP/2 response trailers are accepted as trailing HEADERS after initial response HEADERS and DATA.
- Response trailing HEADERS are tracked per stream and are not exposed as body bytes.
- Buffered HTTP/2 responses expose validated trailers through `Http_Client.Responses.Trailers`; trailers remain separate from ordinary response headers.
- DATA after response trailers is rejected deterministically as a stream-state error.
- Trailer HEADERS are metadata and do not consume DATA flow-control windows.
- HTTP/1.1 trailer behavior remains unchanged.
- HTTP/3 trailer behavior remains unchanged and remains outside this phase.

Current exposure policy:

- Request trailers reuse `Http_Client.Request_Bodies.Trailers`.
- The HTTP/2 connection model exposes deterministic per-stream trailer receipt state through `Response_Trailers_Received` and `Response_Trailer_Block_Bytes`.
- Buffered response values expose validated trailer fields through `Http_Client.Responses.Trailers`.
- `Http_Client.HTTP2.Body_Streams.Read_Some` continues to return DATA payload bytes only.

Verification markers:

- `Test_Request_Trailers_Empty_Body`
- `Test_Request_Trailers_Buffered_Body`
- `Test_Request_Trailer_Forbidden_Names`
- `Test_Response_Trailers_After_Data`
- `Test_Response_Trailer_Pseudo_Rejected`
- `Test_Response_Trailer_Content_Length_Rejected`
- `Test_Data_After_Response_Trailers_Rejected`
- `Test_Response_Trailers_Interleaved_With_Other_Stream`
- trailing HEADERS
- no Transfer-Encoding in HTTP/2 trailers
- pseudo-header trailer rejection
- forbidden trailer name rejection
- trailers not exposed as body bytes
