with Ada.Calendar;
with Ada.Finalization;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Http_Client.Cancellation;
with Http_Client.Cookies;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP3;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Zlib_Decompression;

package Http_Client.Response_Streams is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Public streaming response-body API for explicit Git-safe pull execution.
   --
   --  A streaming response parses and exposes response metadata before the
   --  response body is fully read. The underlying TCP or TLS connection remains
   --  owned by the Streaming_Response object until End_Of_Body is reached or
   --  Close is called. This stream implementation does not retain live
   --  connections in a pool. HTTP/2 and HTTP/3 protocol selection is explicit
   --  through Streaming_Options.Protocol_Policy. HTTP/1.1 remains the default;
   --  HTTP/2/HTTP/3 are used only when requested and expose decoded protocol
   --  DATA/body bytes through the same byte-array Read_Some contract. No async
   --  API, caching, multipart handling, or broad authentication workflow is
   --  implemented here.

   type Streaming_Protocol_Policy is
     (Streaming_HTTP_1_1_Only,
      Streaming_Prefer_HTTP_2,
      Streaming_Force_HTTP_2,
      Streaming_Prefer_HTTP_3,
      Streaming_Force_HTTP_3);
   --  Protocol selection policy for pull-based streaming response execution.
   --
   --  Streaming_HTTP_1_1_Only preserves exact HTTP/1.1 transfer-decoding
   --  semantics and disables HTTP/2/HTTP/3 candidates. Streaming_Prefer_HTTP_2
   --  advertises h2 and uses the HTTP/2 streaming-compatible path when ALPN
   --  selects h2, otherwise it falls back to HTTP/1.1 before request bytes are
   --  sent. Streaming_Force_HTTP_2 requires https:// plus h2 ALPN and rejects
   --  plain HTTP because h2c is not implemented. Streaming_Prefer_HTTP_3 and
   --  Streaming_Force_HTTP_3 route through the experimental HTTP/3 execution
   --  boundary; they never bypass configured proxy or QUIC capability checks.

   type Streaming_Options is record
      Max_Header_Size       : Natural := 65_536;
      Max_Header_Line_Size  : Natural := 8_192;
      Max_Body_Size         : Natural := 1_048_576;
      Read_Buffer_Size      : Positive := 4_096;
      Timeouts              : Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
      Cancellation          : Http_Client.Cancellation.Cancellation_Token_Access := null;
      TLS                   : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Add_Connection_Close  : Boolean := True;
      Cookie_Jar            : Http_Client.Cookies.Cookie_Jar_Access := null;
      Strict_Cookies        : Boolean := False;
      Merge_Jar_Cookies     : Boolean := False;
      Enable_Decompression : Boolean := False;
      Decompression        : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
      HTTP3                : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      Proxy                 : Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.No_Proxy_Config;
      Diagnostics           : Http_Client.Diagnostics.Context_Access := null;
      Protocol_Policy       : Streaming_Protocol_Policy := Streaming_HTTP_1_1_Only;
   end record;
   --  Bounds and transport options for streaming response execution. Fixed-length
   --  request-body producers are sent with Content-Length before response
   --  headers are parsed. Unknown-length producers are sent with HTTP/1.1
   --  Transfer-Encoding: chunked. Explicit trailers attached to the request body
   --  are declared with Trailer and emitted after the terminating chunk. If the request
   --  contains `Expect: 100-continue`, streaming execution sends headers first,
   --  waits for `100 Continue`, and sends no body when the server replies with
   --  a final status instead. That early final response remains available as
   --  normal metadata from Open, and its decoded entity body is read with
   --  Read_Some.
   --
   --  @field Max_Header_Size Maximum status-line plus header bytes, including
   --         the terminating CRLF CRLF.
   --  @field Max_Header_Line_Size Maximum bytes in one status or header line,
   --         excluding CRLF.
   --  @field Max_Body_Size Maximum body bytes returned by Read_Some across the
   --         whole stream. This bound still applies even though the body is not
   --         retained in memory.
   --  @field Read_Buffer_Size Preferred low-level transport read size.
   --  @field Timeouts Timeout intent for plain TCP reads and connects. Zero disables that timeout.
   --  @field Cancellation Optional cooperative cancellation token. Null preserves
   --         existing behavior. Cancellation before Open or during Read_Some
   --         returns Cancelled and discards the underlying connection.
   --  @field TLS TLS verification, SNI, CA-location, optional explicit
   --         client-certificate credential, and timeout options for https://
   --         streaming. Verification remains enabled by default. A valid
   --         credential scoped to a different origin is not presented on this
   --         streaming TLS connection.
   --  @field Add_Connection_Close Add a temporary Connection: close header when
   --         absent. The caller's Request object is not mutated.
   --  @field Cookie_Jar Optional jar. Set-Cookie headers are stored after
   --         headers are parsed and before the stream is returned.
   --  @field Strict_Cookies Report malformed Set-Cookie fields when True.
   --  @field Merge_Jar_Cookies Merge jar cookies with an explicit Cookie header
   --         when True; otherwise explicit caller Cookie wins.
   --  @field Enable_Decompression Opt-in streaming content decompression.
   --         When False, Read_Some returns transfer-decoded but still
   --         content-encoded entity bytes. When True, gzip, zlib-wrapped
   --         deflate, and explicitly configured raw-deflate Content-Encoding
   --         values are decoded incrementally after HTTP transfer decoding and
   --         before bytes are returned. Unsupported
   --         encodings follow Decompression.Unsupported_Policy.
   --  @field Decompression Bounded streaming decoded-output options.
   --         Maximum_Decoded_Body_Size is enforced across the decoded stream.
   --  @field HTTP3 Explicit HTTP/3/QUIC options used only when the streaming
   --         protocol policy selects or permits HTTP/3. The default disabled
   --         options preserve HTTP/1.1-only behavior.
   --  @field Proxy Explicit HTTP or SOCKS5 proxy configuration. Plain HTTP
   --         through an HTTP proxy uses absolute-form requests. Plain HTTP
   --         through SOCKS5 uses a SOCKS CONNECT tunnel and origin-form
   --         requests. HTTPS over an explicit HTTP proxy uses CONNECT first,
   --         then starts origin TLS inside the tunnel
   --         before request headers or bodies are sent. Proxy-Authorization from
   --         the proxy config is sent only on CONNECT and is not sent inside the
   --         TLS stream. HTTPS over an explicit SOCKS5 proxy performs SOCKS
   --         CONNECT first, then starts origin TLS inside the SOCKS tunnel.
   --         SOCKS credentials are used only during SOCKS negotiation and are
   --         not serialized as HTTP headers.
   --  @field Protocol_Policy Explicit protocol guard. Streaming_HTTP_1_1_Only
   --         forces HTTP/1.1. The prefer/force HTTP/2 and HTTP/3 values opt in
   --         to protocol-specific streaming-compatible execution boundaries and
   --         never perform implicit browser-style upgrade discovery.
   --  @field Diagnostics Optional caller-owned diagnostics context. Null keeps
   --         streaming execution silent; non-null emits bounded stream-open,
   --         header, body-progress, close, and failure events without buffering
   --         response bodies.

   Default_Streaming_Options : constant Streaming_Options :=
     (Max_Header_Size       => 65_536,
      Max_Header_Line_Size  => 8_192,
      Max_Body_Size         => 1_048_576,
      Read_Buffer_Size      => 4_096,
      Timeouts              => Http_Client.Transports.TCP.Default_Timeouts,
      Cancellation          => null,
      TLS                   => Http_Client.Transports.TLS.Default_TLS_Options,
      Add_Connection_Close  => True,
      Cookie_Jar            => null,
      Strict_Cookies        => False,
      Merge_Jar_Cookies     => False,
      Enable_Decompression => False,
      Decompression        => Http_Client.Decompression.Default_Decompression_Options,
      HTTP3                => Http_Client.HTTP3.Default_HTTP3_Options,
      Proxy                 => Http_Client.Proxies.No_Proxy_Config,
      Diagnostics           => null,
      Protocol_Policy       => Streaming_HTTP_1_1_Only);

   type Streaming_Response is new Ada.Finalization.Limited_Controlled with private;
   --  Owned streaming response handle.
   --
   --  Successful Open leaves this object open and owning exactly one TCP or TLS
   --  connection. Read_Some returns body bytes incrementally. Close is explicit
   --  and idempotent; finalization closes any still-open connection as a safety
   --  net. The object is not synchronized for concurrent task access.

   overriding procedure Finalize (Item : in out Streaming_Response);
   --  GNATdoc contract.
   --  @param Item Streaming response being finalized.
   --  Close any still-open transport owned by Item.

   function Open
     (Request   : Http_Client.Requests.Request;
      Stream    : in out Streaming_Response;
      Options   : Streaming_Options := Default_Streaming_Options;
      Final_URI : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirect_Count : Natural := 0;
      Retry_Attempt_Count : Natural := 1)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Final_URI Subprogram parameter.
   --  @return Subprogram result.
   --  Open a one-shot HTTP or HTTPS request and return after response headers.
   --
   --  Request may contain an empty, buffered, fixed-length streaming, or
   --  unknown-length streaming request body. Fixed-length producers are sent
   --  completely before response headers are read. Unknown-length producers are
   --  framed as HTTP/1.1 chunks and terminated with a zero-size chunk. The
   --  request is serialized and sent, the response header section is read and
   --  parsed under the configured bounds, and body framing is determined. On
   --  success the stream owns the live connection and metadata is available via
   --  Metadata, Status_Code, Reason_Phrase, Headers, Effective_URI,
   --  Redirect_Count, and Retry_Attempt_Count. On
   --  failure no open stream is returned. HTTP/1.1 chunked transfer coding is
   --  decoded incrementally before bytes are returned for HTTP/1.1. HTTP/2 and
   --  HTTP/3 expose DATA-frame payload bytes only, never frame metadata. Valid
   --  HTTP/1.1 chunk extensions and bounded trailers are parsed and discarded.
   --  When Options.Enable_Decompression is True, gzip
   --  and zlib-wrapped deflate content encodings are decoded incrementally
   --  after transfer decoding. When it is False, response body bytes are raw
   --  content bytes.

   function Metadata
     (Stream : Streaming_Response) return Http_Client.Responses.Response;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return parsed response metadata. Body_Data is always empty for streaming
   --  metadata because the body is read through Read_Some.

   function Status_Code
     (Stream : Streaming_Response) return Http_Client.Types.Status_Code;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed response status code.

   function Reason_Phrase (Stream : Streaming_Response) return String;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed reason phrase.

   function Redirect_Count (Stream : Streaming_Response) return Natural;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of redirects followed before this final stream.

   function Retry_Attempt_Count (Stream : Streaming_Response) return Natural;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the open-attempt count used to obtain this final stream.

   function Headers
     (Stream : Streaming_Response) return Http_Client.Headers.Header_List;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return a copy of the parsed response headers.

   function Effective_URI
     (Stream : Streaming_Response) return Http_Client.URI.URI_Reference;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the final URI associated with this stream. Direct opens return the
   --  request URI unless a caller supplies Final_URI after redirect handling.

   function Is_Open (Stream : Streaming_Response) return Boolean;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return True while the stream owns a live transport and has not reached
   --  end-of-body, failure, or explicit close.

   function End_Of_Body (Stream : Streaming_Response) return Boolean;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return True after the body has been fully consumed, or immediately for
   --  HEAD, 1xx, 204, 205, and 304 responses.

   function Last_Status
     (Stream : Streaming_Response) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the most recent stream status. Ok means the last read returned
   --  body bytes successfully. End_Of_Stream means ordinary end-of-body after
   --  the stream has been consumed. Mid-body framing, size-limit, timeout,
   --  network, or misuse failures are reported here and by Read_Some.

   function Read_Some
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Last Number of bytes written into Buffer.
   --  @return Subprogram result.
   --  Read the next decoded body bytes into Buffer.
   --
   --  Ok with Last > 0 means body bytes were returned. End_Of_Stream with
   --  Last = 0 means ordinary end-of-body. Protocol_Error, Response_Too_Large,
   --  Timeout, Read_Failed, Unsupported_Feature, and Not_Connected describe
   --  deterministic failure or caller misuse cases. Read after Close returns
   --  Not_Connected. Exceptions are not used for ordinary EOF or network
   --  failures.

   function Read_Some
     (Stream : in out Streaming_Response;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Last Last written array index, or Buffer'First - 1 for no data.
   --  @return Subprogram result.
   --  Read the next decoded body octets into Buffer. This is the preferred Git
   --  smart HTTP API and preserves every octet exactly, including NUL bytes and
   --  bytes above 127.

   function Close
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Close the underlying TCP or TLS connection. Closing early discards unread
   --  response bytes by closing the one-shot connection. Closing twice returns
   --  Ok.

private
   type Transport_State is (No_Transport, Plain_Transport, TLS_Transport);
   type Stream_Protocol_State is (Protocol_HTTP_1_1, Protocol_HTTP_2);
   type Body_Mode is (No_Body, Fixed_Length, Chunked, Close_Delimited);
   type Chunk_State is
     (Reading_Chunk_Size,
      Reading_Chunk_Data,
      Reading_Chunk_Data_CRLF,
      Reading_Trailers,
      Chunk_Done);

   type Streaming_Response is new Ada.Finalization.Limited_Controlled with record
      Transport       : Transport_State := No_Transport;
      Protocol        : Stream_Protocol_State := Protocol_HTTP_1_1;
      Diagnostic_Protocol : Http_Client.Diagnostics.Protocol_Version :=
        Http_Client.Diagnostics.Protocol_Unknown;
      TCP             : Http_Client.Transports.TCP.Connection;
      TLS_Conn        : Http_Client.Transports.TLS.Connection;
      Opened          : Boolean := False;
      Had_Response    : Boolean := False;
      Finished        : Boolean := True;
      Failed          : Boolean := False;
      Mode            : Body_Mode := No_Body;
      Remaining       : Natural := 0;
      Chunk_Remaining : Natural := 0;
      Chunk_Phase     : Chunk_State := Reading_Chunk_Size;
      Body_Read       : Natural := 0;
      Max_Body        : Natural := 0;
      H2_Stream       : Http_Client.HTTP2.Frames.Stream_ID := 0;
      H2_Continuation : Http_Client.HTTP2.Frames.Continuation_State;
      H2_Decoder      : Http_Client.HTTP2.HPACK.Decoder :=
        Http_Client.HTTP2.HPACK.Create_Decoder;
      H2_Headers_Done : Boolean := False;
      H2_Bodyless     : Boolean := False;
      H2_Content_Length_Set : Boolean := False;
      H2_Content_Length     : Natural := 0;
      H2_Peer_Max_Frame_Size : Natural := 16_384;
      H2_Conn_Window  : Natural := 65_535;
      H2_Stream_Window : Natural := 65_535;
      Max_Trailer_Size      : Natural := 0;
      Max_Trailer_Line_Size : Natural := 0;
      Trailer_Read          : Natural := 0;
      Read_Quantum    : Positive := 4_096;
      Lookahead       : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Meta            : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      URI_Value       : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirects_Followed : Natural := 0;
      Retry_Attempts  : Natural := 1;
      Last_Result     : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Diagnostics     : Http_Client.Diagnostics.Context_Access := null;
      Request_ID      : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID   : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Request_Start_Time : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Cancellation    : Http_Client.Cancellation.Cancellation_Token_Access := null;
      Decode_Active    : Boolean := False;
      Decode_Finished  : Boolean := False;
      Decode_End_Seen  : Boolean := False;
      Decode_Auto      : Boolean := False;
      Decode_Selected  : Boolean := True;
      Decode_Format    : Http_Client.Zlib_Decompression.Wrapper_Format :=
        Http_Client.Zlib_Decompression.Gzip;
      Decode_Auto_Prefix : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Decode_Context   : Http_Client.Zlib_Decompression.Decoder;
      Decode_Buffer    : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Decode_Read      : Natural := 0;
      Decode_Max       : Natural := 0;
   end record;
end Http_Client.Response_Streams;
