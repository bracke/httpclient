with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;

package Http_Client.Request_Bodies is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Request-body abstractions for buffered and controlled upload-streaming
   --  requests.
   --
   --  This package supports empty bodies, replayable in-memory bodies, and
   --  fixed-length producer-backed bodies, and explicit unknown-length
   --  producer-backed bodies. HTTP/1.1 execution serializes unknown-length
   --  producer bodies with Transfer-Encoding: chunked. Request trailers are
   --  explicit: they are stored separately from ordinary request headers,
   --  declared with the HTTP/1.1 Trailer field, and serialized only after the
   --  terminating chunk for unknown-length chunked uploads. An explicit
   --  `Expect: 100-continue` request header is honored by HTTP/1.1 execution:
   --  the client sends headers, waits for a `100 Continue` interim response,
   --  then sends the body; if a final response is received instead, the body is
   --  not sent.

   type Body_Kind is
     (Empty_Body,
      Buffered_Body,
      Fixed_Length_Stream,
      Unknown_Length_Stream);
   --  Request body storage/framing kind.

   type Body_Producer is limited interface;
   --  Caller-owned streaming upload producer.
   --
   --  A producer is owned by one request execution at a time. Implementations
   --  are not task-safe unless they document stronger guarantees.

   type Body_Producer_Access is access all Body_Producer'Class;
   --  Access value naming a caller-owned producer. The library does not free
   --  this object.

   function Read_Some
     (Item   : in out Body_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status is abstract;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Count Subprogram parameter.
   --  @return Subprogram result.
   --  Fill Buffer with the next upload bytes.
   --
   --  Count is the number of bytes written starting at Buffer'First. Returning
   --  Ok with Count = 0 means ordinary end-of-input. Producer failures should
   --  return Body_Producer_Failed or another deterministic non-Ok status.

   function Reset
     (Item : in out Body_Producer) return Http_Client.Errors.Result_Status is abstract;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Reset the producer to its initial byte position for a replay.
   --
   --  Non-replayable producers should return Body_Not_Replayable.

   type Request_Body is private;
   --  Explicit request-body descriptor.

   function Empty return Request_Body;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return an empty request body.

   function From_String (Payload : String) return Request_Body;
   --  GNATdoc contract.
   --  @param Payload Subprogram parameter.
   --  @return Subprogram result.
   --  Return a replayable in-memory request body containing Payload. The String
   --  is byte-preserving: each Character position 0 .. 255 is one HTTP entity
   --  octet and no encoding, UTF-8 validation, line-ending normalization, or
   --  NUL stripping is performed.

   function From_Bytes
     (Payload : Ada.Streams.Stream_Element_Array) return Request_Body;
   --  GNATdoc contract.
   --  @param Payload Subprogram parameter.
   --  @return Subprogram result.
   --  Return a replayable in-memory request body containing Payload exactly.

   function From_Fixed_Length_Stream
     (Producer   : Body_Producer_Access;
      Length     : Natural;
      Replayable : Boolean := False) return Request_Body;
   --  GNATdoc contract.
   --  @param Producer Subprogram parameter.
   --  @param Length Subprogram parameter.
   --  @param Replayable Subprogram parameter.
   --  @return Subprogram result.
   --  Return a fixed-length streaming body.
   --
   --  Length is the exact byte count that must be produced. HTTP/1.1 execution
   --  synthesizes or validates Content-Length against this value. Replayable
   --  should be True only when Reset can restore identical bytes.

   function From_Unknown_Length_Stream
     (Producer   : Body_Producer_Access;
      Replayable : Boolean := False) return Request_Body;
   --  GNATdoc contract.
   --  @param Producer Subprogram parameter.
   --  @param Replayable Subprogram parameter.
   --  @return Subprogram result.
   --  Return an unknown-length streaming body without request trailers.
   --
   --  HTTP/1.1 execution sends this body with Transfer-Encoding: chunked,
   --  emits each produced byte sequence as one chunk, and terminates the
   --  upload with a zero-size chunk when the producer returns Ok and Count = 0.
   --  Producer failure aborts the request and the connection is not reusable.

   function From_Unknown_Length_Stream_With_Trailers
     (Producer   : Body_Producer_Access;
      Trailers   : Http_Client.Headers.Header_List;
      Replayable : Boolean := False) return Request_Body;
   --  GNATdoc contract.
   --  @param Producer Subprogram parameter.
   --  @param Trailers Trailer fields to send after the chunked body.
   --  @param Replayable Subprogram parameter.
   --  @return Subprogram result.
   --  Return an unknown-length streaming body with explicit request trailers.

   function With_Trailers
     (Item     : Request_Body;
      Trailers : Http_Client.Headers.Header_List) return Request_Body;
   --  GNATdoc contract.
   --  @param Item Request body descriptor to copy.
   --  @param Trailers Trailer fields to send after a chunked upload body.
   --  @return A copy of Item with explicit request trailers attached.
   --
   --  For HTTP/1.1, trailer fields are only valid for Unknown_Length_Stream
   --  bodies serialized with Transfer-Encoding: chunked; HTTP/1.1
   --  serialization rejects trailers on empty, buffered, and fixed-length
   --  bodies. For HTTP/2, Phase 10 permits trailers on empty, buffered,
   --  fixed-length, and unknown-length bodies by sending one trailing HEADERS
   --  block after body DATA. Trailer names and values must already be valid
   --  Header_List fields; framing, routing, authentication, connection-control,
   --  and pseudo-header trailers are rejected by the protocol serializer.

   function Has_Trailers (Item : Request_Body) return Boolean;
   --  GNATdoc contract.
   --  @param Item Request body descriptor.
   --  @return True when explicit request trailers are attached.

   function Trailers
     (Item : Request_Body) return Http_Client.Headers.Header_List;
   --  GNATdoc contract.
   --  @param Item Request body descriptor.
   --  @return A copy of the explicit request trailers.

   function Kind (Item : Request_Body) return Body_Kind;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the body kind.

   function Has_Body (Item : Request_Body) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the body can send at least one byte or is a stream whose
   --  length is not known to be zero.

   function Is_Replayable (Item : Request_Body) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the body can be sent again identically.

   function Has_Producer (Item : Request_Body) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when a stream body has a producer object attached.

   function Declared_Length (Item : Request_Body; Length : out Natural)
      return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Length Subprogram parameter.
   --  @return Subprogram result.
   --  Return True and set Length for buffered and fixed-length bodies.

   function Buffered_Payload (Item : Request_Body) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the in-memory payload for Buffered_Body as byte-preserving String,
   --  or the empty string for other body kinds.

   function Buffered_Bytes
     (Item : Request_Body) return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the in-memory payload for Buffered_Body as exact octets, or an
   --  empty array for other body kinds.

   function Read_Next
     (Item   : Request_Body;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Request body descriptor to read from.
   --  @param Buffer String buffer receiving byte-preserving data.
   --  @param Count Number of characters written to Buffer.
   --  @return Ok on successful read, End_Of_Stream when exhausted, or a deterministic failure status.

   function Read_Next
     (Item   : Request_Body;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Last Last stream element written, or Buffer'First - 1 for no data.
   --  @return Subprogram result.
   --  Read bytes from the body producer.

   function Reset_Body
     (Item : Request_Body) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Reset a replayable stream body before retry or redirect replay.

private
   use Ada.Strings.Unbounded;

   type Request_Body is record
      Body_Type        : Body_Kind := Empty_Body;
      Payload_Text     : Unbounded_String := Null_Unbounded_String;
      Stream_Producer    : Body_Producer_Access := null;
      Stream_Length      : Natural := 0;
      Replayable_Flag    : Boolean := True;
      Trailer_Fields     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Has_Trailer_Fields : Boolean := False;
   end record;
end Http_Client.Request_Bodies;
