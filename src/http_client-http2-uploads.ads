with Http_Client.Errors;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Frames;
with Http_Client.Request_Bodies;

package Http_Client.HTTP2.Uploads is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/2 request-body upload adapter.
   --
   --  This package sends the existing Request_Bodies producer model
   --  through the HTTP/2 connection state as DATA frame payload accounting.
   --  It does not expose bidirectional streaming or an async task pool. DATA
   --  frame serialization, TLS, proxy CONNECT, HPACK, retries, redirects,
   --  cookies, caching, and diagnostics remain layered above or below this
   --  bounded adapter. Multipart/form-data works because it is an ordinary
   --  producer-backed request body whose bytes are preserved exactly.

   type Upload_Result is record
      Bytes_Sent     : Natural := 0;
      Data_Frames    : Natural := 0;
      End_Stream_Sent : Boolean := False;
      Trailer_Headers : Natural := 0;
   end record;
   --  Deterministic upload accounting. B contents are never recorded here.
   --  Trailer_Headers counts a trailing HTTP/2 HEADERS block; HTTP/2 request
   --  trailers are never modeled as DATA and never use chunked transfer
   --  encoding.

   function Send_Body
     (Connection : in out Http_Client.HTTP2.Connection.Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      B       : Http_Client.Request_Bodies.Request_Body;
      Result     : out Upload_Result) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param B Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Send B as HTTP/2 DATA accounting on Stream. Explicit request trailers,
   --  when attached to B, are sent after body DATA as one trailing HEADERS
   --  block with END_STREAM. Empty bodies with trailers send no DATA. Empty
   --  bodies without trailers end the local stream without DATA. Buffered and
   --  fixed-length producer bodies must match
   --  their declared lengths exactly. Unknown-length producers are rejected
   --  unless the connection options explicitly allow DATA END_STREAM framing.
   --  Producer reads are bounded by the peer max frame size and current send
   --  windows; exhausted windows return Timeout rather than reading more bytes.
   --  Fixed-length producers are checked for early EOF and overproduction; an
   --  overproducing producer returns Body_Length_Mismatch before END_STREAM is
   --  reported as sent by this adapter.
   --  A reset or failed stream stops producer reads and returns the stream
   --  status. Retry and redirect replay remain controlled by the caller through
   --  Request_Bodies.Is_Replayable and existing policy.
end Http_Client.HTTP2.Uploads;
