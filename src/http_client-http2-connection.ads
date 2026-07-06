with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Streams;
with Http_Client.Headers;

package Http_Client.HTTP2.Connection is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Bounded HTTP/2 multiplexed connection state for bounded HTTP/2 multiplexing.
   --
   --  This package owns the deterministic in-memory state used to schedule and
   --  demultiplex multiple client-initiated streams on one h2 connection. It
   --  does not own sockets, TLS handles, redirects, cookies, decompression,
   --  caching, proxy routing, or retry policy. One HPACK encoder and one HPACK
   --  decoder are held per connection, matching HTTP/2 connection semantics.
   --
   --  Public HTTP/2 response streaming and upload streaming are
   --  modeled through bounded DATA queues and send-window accounting. The
   --  public streaming API yields body bytes only; frame details remain in the
   --  frame and connection layers. Server push remains disabled; received
   --  PUSH_PROMISE frames are rejected deterministically.
   --
   --  The type is not task-safe. Callers that share a connection across Ada
   --  tasks must serialize access externally or through a later protected
   --  wrapper.

   Max_Tracked_Streams : constant Natural := 32;

   type Connection_State is private;

   function Create
     (Options : Http_Client.HTTP2.HTTP2_Options) return Connection_State;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Create a new bounded multiplexed connection state. The connection starts
   --  active, advertises SETTINGS_ENABLE_PUSH = 0 through the caller's frame
   --  layer, and allocates odd client stream IDs beginning at 1. Operations
   --  that open or drive streams return HTTP2_Multiplexing_Unsupported unless
   --  Options.Enable_Multiplexing is True and Options.Mode permits HTTP/2.

   function Effective_Max_Concurrent_Streams
     (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return min(local configured limit, peer SETTINGS_MAX_CONCURRENT_STREAMS).

   function Active_Stream_Count
     (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of open or half-closed streams currently occupying a
   --  concurrent-stream slot.

   function Can_Open_Stream
     (Connection : Connection_State) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when multiplexing is enabled, the connection is not retired
   --  by GOAWAY/error/stream-ID exhaustion, and a new stream would not exceed
   --  the effective limit.

   function Public_Streaming_Enabled (Connection : Connection_State) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when public HTTP/2 response streaming is explicitly
   --  enabled on this connection state.

   function Upload_Streaming_Enabled (Connection : Connection_State) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when HTTP/2 request-body DATA streaming is explicitly
   --  enabled on this connection state.

   function Peer_Max_Data_Frame_Size (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return the peer SETTINGS_MAX_FRAME_SIZE currently used to cap outbound
   --  HTTP/2 upload DATA frame payloads.

   function Allow_Unknown_Length_HTTP2_Bodies
     (Connection : Connection_State) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when unknown-length request producers may be delimited by
   --  DATA END_STREAM on this connection.

   function Begin_Public_Response_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Reserve one configured public HTTP/2 streamed-response slot for Stream.
   --  Final response HEADERS must already have been accepted, and no header
   --  block may be pending. The reservation is idempotent for the same live
   --  stream and enforces Max_Active_Streamed_Responses before a Body_Stream
   --  is exposed.

   function End_Public_Response_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Release only the public streamed-response slot for Stream after the
   --  remote response side reached END_STREAM while the underlying HTTP/2
   --  stream may still be half-closed-remote. This does not release the
   --  stream tracking slot or change stream state.

   function Begin_Upload_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Reserve one configured HTTP/2 upload slot for Stream before producer
   --  bytes are pulled. The request side must still be open for DATA unless
   --  the peer has half-closed first; a locally half-closed stream cannot be
   --  reopened for upload. This prevents exceeding Max_Active_Upload_Streams.

   function End_Upload_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Release a prior upload-stream reservation. This does not change HTTP/2
   --  stream state; it only releases the local upload activity slot.

   function Open_Stream
     (Connection : in out Connection_State;
      Stream     : out Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Allocate the next odd client stream ID and move it to open. Stream IDs
   --  are never reused; exhaustion retires the connection and returns
   --  HTTP2_Connection_Goaway.

   function End_Local_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Apply END_STREAM on the request side after HEADERS or DATA have been
   --  sent.

   function Send_Data
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      Length     : Natural;
      End_Stream : Boolean := False) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Length Subprogram parameter.
   --  @param End_Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Consume connection and stream send windows for outbound DATA without
   --  serializing frames. Length must fit the peer SETTINGS_MAX_FRAME_SIZE and
   --  both flow-control windows.

   function Send_Trailers
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      Trailers   : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Trailers HTTP/2 request trailer fields.
   --  @return Subprogram result.
   --  Validate and account request trailers as one trailing HEADERS block with
   --  END_STREAM. No DATA window is consumed and no HTTP/1.1 chunk framing or
   --  Trailer declaration is used.

   function Receive_Frame
     (Connection : in out Connection_State;
      Frame      : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Frame Subprogram parameter.
   --  @return Subprogram result.
   --  Demultiplex one already parsed frame. Connection-level SETTINGS, PING,
   --  GOAWAY, and WINDOW_UPDATE are handled on the connection. Stream-level
   --  HEADERS, CONTINUATION, DATA, RST_STREAM, and WINDOW_UPDATE are routed to
   --  the addressed stream while enforcing stream-state and header-block
   --  sequencing rules.

   function Apply_Settings_Payload
     (Connection : in out Connection_State;
      Payload    : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @return Subprogram result.
   --  Apply a non-ACK SETTINGS payload while streams may be active. Changes to
   --  SETTINGS_INITIAL_WINDOW_SIZE adjust all tracked stream windows; invalid
   --  settings retire the connection.

   function Retired (Connection : Connection_State) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return True after GOAWAY, stream-ID exhaustion, or connection-level
   --  protocol/flow-control/HPACK failure. A graceful GOAWAY retires the
   --  connection for new streams while already accepted streams at or below the
   --  peer last-stream-id may still complete.

   function Goaway_Last_Stream
     (Connection : Connection_State) return Http_Client.HTTP2.Frames.Stream_ID;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return the last stream ID reported by GOAWAY, or 16#7FFF_FFFF# before
   --  GOAWAY is received.

   function Stream_After_Goaway_Last
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return True after GOAWAY when Stream is greater than the peer's
   --  last-stream-id. Such a request may not have been processed by the peer
   --  and can be considered by the retry layer only if retry method and
   --  replayability rules permit it. Before GOAWAY this returns False.

   function Stream_State_Of
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.HTTP2.Streams.Stream_State;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return a tracked stream state, or Idle when the stream is unknown.

   function Stream_Status_Of
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return the most recent deterministic status for a stream.

   function Response_Body_Of
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return String;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return buffered DATA bytes accumulated for Stream. This is a decoded
   --  HTTP/2 body-byte queue, never raw frame bytes; padded DATA pad-length and
   --  padding octets are consumed internally and are not exposed.

   function Buffered_Response_Bytes
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return queued DATA bytes not yet credited as consumed by the public
   --  streaming reader. This is the unread queue length, not the total body
   --  length already received for Content-Length validation.

   function Total_Buffered_Response_Bytes
     (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.
   --  Return aggregate queued DATA bytes across all active streams. The
   --  aggregate excludes HEADERS, trailers, padding already credited, and all
   --  other frame metadata.

   function Response_Trailers_Received
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Boolean;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return True after a response trailing HEADERS block closed Stream.

   function Response_Trailer_Block_Bytes
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Bounded encoded trailer HEADERS fragment bytes seen for Stream.

   function Set_Response_Content_Length
     (Connection      : in out Connection_State;
      Stream          : Http_Client.HTTP2.Frames.Stream_ID;
      Expected_Length : Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Expected_Length Subprogram parameter.
   --  @return Subprogram result.
   --  Record the decoded response Content-Length for Stream after HPACK and
   --  response-header mapping have accepted the final response headers. DATA
   --  receipt then rejects bodies larger than the value and requires exact
   --  equality when END_STREAM closes the response.

   function Mark_Bodyless_Response
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Mark a stream as having a bodyless response, such as HEAD, 204, or 304,
   --  after response-header mapping has determined that DATA is forbidden.
   --  Any DATA frame for such a stream, even an empty END_STREAM DATA frame, is
   --  rejected deterministically as a protocol error. If unread DATA was already
   --  queued on that stream, the terminal stream failure credits it before the
   --  stream is reset so receive-window capacity is not leaked.

   function Credit_Response_Data
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      Length     : Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Length Subprogram parameter.
   --  @return Subprogram result.
   --  Credit accepted, queued HTTP/2 response DATA bytes back to both the
   --  connection-level and stream-level receive windows without removing them
   --  from the unread body queue. Production transports call this after
   --  serializing WINDOW_UPDATE for the same Length. This prevents large
   --  buffered responses from stalling at the initial receive window while
   --  preserving the bounded body queue. Bytes credited here are tracked so
   --  later body-stream consumption does not credit them a second time.

   function Consume_Response_Bytes
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      Length     : Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Length Subprogram parameter.
   --  @return Subprogram result.
   --  Mark buffered response bytes as consumed by the caller. Bytes that were
   --  not already credited by Credit_Response_Data credit both the stream-level
   --  and connection-level receive windows by Length, modeling the
   --  WINDOW_UPDATE amount that the frame layer should send. Bytes already
   --  credited during frame receipt are only removed from the unread queue.
   --  Overflow beyond the maximum HTTP/2 window is rejected deterministically.
   --  WINDOW_UPDATE increments are represented by positive uncredited lengths
   --  and therefore must never be zero at the frame layer.

   function Cancel_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Cancel a live stream because the public response stream was closed early
   --  or an upload no longer has an accepted peer stream. A production transport
   --  should serialize RST_STREAM(CANCEL) when practical. This in-memory state
   --  marks only the addressed stream reset, discards any unread queued DATA
   --  while crediting receive windows, and leaves the connection reusable if no
   --  connection-level error occurred.

   function Release_Stream
     (Connection : in out Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Release bookkeeping for a closed stream after all buffered body bytes have
   --  been consumed, or for a reset stream after its failure has been observed.
   --  Stream IDs are still never reused; this only frees one of
   --  the bounded tracking slots for later streams on the same connection.

   function Connection_Send_Window
     (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.

   function Connection_Receive_Window
     (Connection : Connection_State) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @return Subprogram result.

   function Stream_Send_Window
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.

   function Stream_Receive_Window
     (Connection : Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID) return Natural;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.

private
   use Ada.Strings.Unbounded;

   type Stream_Record is record
      In_Use             : Boolean := False;
      Stream             : Http_Client.HTTP2.Frames.Stream_ID := 0;
      State              : Http_Client.HTTP2.Streams.Stream_State :=
        Http_Client.HTTP2.Streams.Idle;
      Status             : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Seen_Final_Headers : Boolean := False;
      Seen_Response_Trailers : Boolean := False;
      Header_Block_Pending : Boolean := False;
      Header_Block_Is_Trailers : Boolean := False;
      Header_Block_Bytes   : Natural := 0;
      Header_Block_Data    : Unbounded_String := Null_Unbounded_String;
      --  Accumulated HPACK header-block fragment bytes for the current
      --  HEADERS/CONTINUATION sequence. Kept per stream so interleaved DATA
      --  on other streams never contaminates trailer metadata.
      Response_Trailer_Bytes : Natural := 0;
      Expected_Content_Length_Set : Boolean := False;
      Expected_Content_Length     : Natural := 0;
      Bodyless_Response           : Boolean := False;
      Public_Response_Stream_Open : Boolean := False;
      Upload_Stream_Open          : Boolean := False;
      Body_Data               : Unbounded_String := Null_Unbounded_String;
      --  Queued, unread decoded DATA bytes only. Consumed bytes are removed so
      --  Max_Per_Stream_Buffered_Bytes is a true backpressure queue bound.
      Consumed_Body_Bytes : Natural := 0;
      --  Retained for compatibility with older tests; queue compaction
      --  keeps this at zero after each consume.
      Window_Credited_Queued_Bytes : Natural := 0;
      --  Number of currently queued body bytes for which WINDOW_UPDATE has
      --  already been serialized by the transport. Consume_Response_Bytes
      --  removes these bytes without double-crediting receive windows.
      Total_Body_Bytes    : Natural := 0;
      --  Total decoded response DATA bytes observed for Content-Length and
      --  Max_Body_Size validation.
      Send_Window        : Natural := 65_535;
      Receive_Window     : Natural := 65_535;
   end record;

   type Stream_Table is array (Positive range 1 .. Max_Tracked_Streams) of Stream_Record;

   type Connection_State is record
      Options             : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Next_Client_Stream  : Http_Client.HTTP2.Frames.Stream_ID := 1;
      Peer_Max_Concurrent : Natural := 1;
      Peer_Max_Frame_Size : Natural := 16_384;
      Peer_Header_Table_Size : Natural := 4_096;
      Peer_Header_List_Size  : Natural := 65_536;
      Initial_Stream_Window  : Natural := 65_535;
      Send_Window         : Natural := 65_535;
      Receive_Window      : Natural := 65_535;
      Is_Retired          : Boolean := False;
      Protocol_Failed     : Boolean := False;
      --  True only for connection-level protocol/flow-control/transport
      --  failures that make subsequent frame processing unsafe. A graceful
      --  GOAWAY retires the connection for new streams without setting this
      --  flag, so already accepted streams at or below Last_Goaway_Stream may
      --  still complete deterministically.
      Last_Goaway_Stream  : Http_Client.HTTP2.Frames.Stream_ID := 16#7FFF_FFFF#;
      Continuation        : Http_Client.HTTP2.Frames.Continuation_State;
      Encoder             : Http_Client.HTTP2.HPACK.Encoder :=
        Http_Client.HTTP2.HPACK.Create_Encoder;
      Decoder             : Http_Client.HTTP2.HPACK.Decoder :=
        Http_Client.HTTP2.HPACK.Create_Decoder;
      Streams             : Stream_Table;
   end record;
end Http_Client.HTTP2.Connection;
