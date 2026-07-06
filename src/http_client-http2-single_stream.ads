with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Transports.TLS;

package Http_Client.HTTP2.Single_Stream is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Deterministic conservative HTTP/2 single-stream execution core.
   --
   --  This package contains the non-multiplexed HTTP/2 request /
   --  response state machine without owning DNS, sockets, TLS, redirects,
   --  retries, cookies, caching, or decompression. Production transports feed
   --  and drain bytes around this core after ALPN has selected h2. Tests may
   --  use Execute_Scripted with an in-memory server byte script.
   --
   --  Limitations are deliberate: one client-initiated stream, buffered
   --  response body, no server push, no trailers, and no live
   --  multiplexed public stream handoff from this core. The higher-level
   --  Response_Streams package may wrap this bounded response into the common
   --  pull API for explicit HTTP/2 Git paths; this package itself still owns a
   --  single buffered exchange and no upload streaming. Response HEADERS after the final response
   --  header block are treated as trailers and rejected deterministically as
   --  HTTP2_Unsupported_Feature. Buffered request bodies are supported only when
   --  they fit in the current frame and flow-control limits. Response HEADERS
   --  with padding/priority metadata and padded DATA frames are rejected
   --  deterministically rather than being decoded incorrectly. Server SETTINGS
   --  are applied before request HEADERS are emitted: the peer header-table
   --  size is passed to the HPACK encoder, peer SETTINGS_MAX_HEADER_LIST_SIZE
   --  bounds the decoded size of emitted request headers, the peer maximum
   --  frame size bounds outbound HEADERS/DATA frames, and the peer initial
   --  stream window bounds
   --  buffered request DATA. Inbound DATA is accepted only within the default
   --  receive flow-control window and Options.Max_Body_Size; this release does
   --  not send WINDOW_UPDATE frames. Post-handshake non-ACK server
   --  SETTINGS are parsed, applied, and acknowledged. Inbound non-ACK PING
   --  frames are acknowledged with the same opaque payload. Valid
   --  connection-level or active-stream WINDOW_UPDATE frames are consumed
   --  deterministically; WINDOW_UPDATE for unrelated streams is rejected.
   --  Response Content-Length
   --  is checked against the
   --  DATA byte count except for HEAD and no-body status responses, where
   --  Content-Length may describe the selected representation while no DATA is
   --  accepted. Buffered request Content-Length, when present, must exactly
   --  match the request payload length before HEADERS/DATA are emitted.

   function Execute_Scripted
     (Request      : Http_Client.Requests.Request;
      Server_Bytes : String;
      Options      : Http_Client.HTTP2.HTTP2_Options;
      Client_Bytes : out Ada.Strings.Unbounded.Unbounded_String;
      Response     : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Server_Bytes Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Client_Bytes Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @return Subprogram result.
   --  Build the client preface, client SETTINGS, SETTINGS ACK, request HEADERS,
   --  optional buffered DATA, then consume scripted server SETTINGS, response
   --  HEADERS/CONTINUATION and DATA frames until END_STREAM. Non-ACK
   --  server SETTINGS encountered during the response loop are acknowledged in
   --  Client_Bytes. The resulting
   --  response is mapped into the existing buffered response model.


   function Execute_TLS
     (Connection : in out Http_Client.Transports.TLS.Connection;
      Request    : Http_Client.Requests.Request;
      Options    : Http_Client.HTTP2.HTTP2_Options;
      Response   : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @return Subprogram result.
   --  Execute one buffered request on an already-open TLS connection whose
   --  negotiated ALPN protocol is h2. The connection is not reused by this
   --  package; callers should close or retire it after success or failure.
end Http_Client.HTTP2.Single_Stream;
