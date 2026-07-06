with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Responses;

package Http_Client.HTTP1.Reader is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Bounded HTTP/1.1 response reader and message-framing layer.
   --
   --  This package reads one complete HTTP/1.x response from a raw byte
   --  transport. The transport supplies only Read_Some behavior; this package
   --  owns header-bound detection, Content-Length framing, connection-close
   --  framing, no-body response handling, transfer-encoding rejection, and
   --  in-memory size limits. It does not open sockets, perform TLS, follow
   --  redirects, manage cookies, decompress content, expose streaming bodies,
   --  implement HTTP/2 or HPACK, retry requests, or pool connections.

   type Reader_Options is record
      Max_Response_Size     : Natural := 16_777_216;
      Max_Header_Size       : Natural := 65_536;
      Max_Header_Line_Size  : Natural := 8_192;
      Max_Body_Size         : Natural := 16_777_216;
      Read_Buffer_Size      : Positive := 4_096;
   end record;
   --  Bounds for one in-memory response read.
   --
   --  @field Max_Response_Size Maximum total bytes retained for the single
   --         response. Bytes read beyond the first framed response may be
   --         discarded because this reader closes the connection after one
   --         exchange and does not reuse persistent connections.
   --  @field Max_Header_Size Maximum status-line plus header-section bytes,
   --         including the terminating CRLF CRLF.
   --  @field Max_Header_Line_Size Maximum bytes in a status or header line,
   --         excluding its terminating CRLF.
   --  @field Max_Body_Size Maximum response body bytes retained in memory.
   --  @field Read_Buffer_Size Maximum transport bytes requested per read.

   Default_Reader_Options : constant Reader_Options :=
     (Max_Response_Size    => 16_777_216,
      Max_Header_Size      => 65_536,
      Max_Header_Line_Size => 8_192,
      Max_Body_Size        => 16_777_216,
      Read_Buffer_Size     => 4_096);
   --  Conservative default bounds for simple and test-oriented usage.

   generic
      type Connection_Type is limited private;
      with function Read_Some
        (Item   : in out Connection_Type;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status;
   function Read_Response
     (Connection : in out Connection_Type;
      Context    : Http_Client.Responses.Parse_Context;
      Raw        : out Ada.Strings.Unbounded.Unbounded_String;
      Response   : out Http_Client.Responses.Response;
      Options    : Reader_Options := Default_Reader_Options)
      return Http_Client.Errors.Result_Status;
   --  Read and parse one bounded HTTP/1.x response from Connection.
   --
   --  The reader blocks according to the underlying transport's behavior until
   --  a complete response has been framed, the peer closes a close-delimited
   --  response, or the transport returns an error. Headers must use strict
   --  CRLF line endings. A single valid Content-Length causes exactly that many
   --  body bytes to be consumed. Responses to HEAD and status codes 1xx, 204,
   --  205, and 304 are treated as having no body. Without Content-Length and
   --  without Transfer-Encoding, bodies are read until clean EOF. A final
   --  Transfer-Encoding: chunked field is decoded before Response_Body is
   --  exposed. Chunk extensions are ignored, bounded trailers are parsed and
   --  discarded, and malformed chunk framing returns Protocol_Error or
   --  Incomplete_Message.
   --
   --  @param Connection Transport connection passed to Read_Some.
   --  @param Context Originating request context, especially HEAD handling.
   --  @param Raw Complete raw response bytes passed to the parser on success.
   --  @param Response Parsed response on Ok; default response on failure.
   --  @param Options In-memory and header/body bounds.
   --  @return Ok, Header_Too_Large, Response_Too_Large, Protocol_Error,
   --          Invalid_Header, Unsupported_Feature, Incomplete_Message,
   --          Read_Failed, Timeout, End_Of_Stream-derived outcomes, or another
   --          transport status returned by Read_Some.

end Http_Client.HTTP1.Reader;
