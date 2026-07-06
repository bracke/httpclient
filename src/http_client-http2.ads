with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.HTTP2
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/2 protocol package.
   --
   --  This package defines conservative public HTTP/2 configuration and ALPN
   --  selection boundaries. It does not replace the existing HTTP/1.1
   --  execution path. The package includes conservative single-stream buffered
   --  HTTP/2 execution core when TLS ALPN selects h2. It also includes
   --  explicitly enabled, bounded HTTP/2 multiplexing. Streaming/upload support
   --  extends the existing public response streaming and request-body producer
   --  abstractions to HTTP/2 DATA frames when enabled, while leaving
   --  production-grade HTTP/3 execution, available QUIC backends,
   --  server-push caches, async task pools, browser cache/profile integration,
   --  service workers, credential
   --  stores, and browser-like networking out of scope.

   Client_Connection_Preface : constant String :=
     "PRI * HTTP/2.0" & Character'Val (13) & Character'Val (10) &
     Character'Val (13) & Character'Val (10) &
     "SM" & Character'Val (13) & Character'Val (10) &
     Character'Val (13) & Character'Val (10);
   --  Exact client connection preface required before the first client
   --  SETTINGS frame on a TLS connection whose ALPN result selected h2.

   type HTTP2_Mode is
     (HTTP2_Disabled,
      HTTP2_Allowed,
      HTTP2_Required);
   --  Caller-visible protocol selection policy.
   --
   --  HTTP2_Disabled advertises and uses HTTP/1.1 only. HTTP2_Allowed permits
   --  ALPN to select h2 but permits fallback to HTTP/1.1 before bytes are sent.
   --  HTTP2_Required rejects connections that do not negotiate h2.

   type Selected_Protocol is
     (Protocol_None,
      Protocol_HTTP_1_1,
      Protocol_HTTP_2,
      Protocol_Unsupported);
   --  Normalized ALPN result.

   type HTTP2_Options is record
      Mode                   : HTTP2_Mode := HTTP2_Disabled;
      Max_Frame_Size         : Natural := 16_384;
      Max_Header_List_Size   : Natural := 65_536;
      Max_Body_Size          : Natural := 16_777_216;
      Enable_Server_Push     : Boolean := False;
      Enable_Multiplexing     : Boolean := False;
      Enable_Public_Streaming : Boolean := False;
      Enable_Upload_Streaming : Boolean := False;
      Max_Per_Stream_Buffered_Bytes : Natural := 16_777_216;
      Max_Total_Queued_Body_Bytes : Natural := 67_108_864;
      Max_Active_Streamed_Responses : Natural := 1;
      Max_Active_Upload_Streams     : Natural := 1;
      Flow_Control_Update_Threshold : Natural := 16_384;
      Upload_Flow_Control_Timeout_MS : Natural := 30_000;
      Allow_Unknown_Length_HTTP2_Bodies : Boolean := False;
      Enable_Streaming_Decompression : Boolean := False;
      Local_Max_Concurrent_Streams : Natural := 1;
      Initial_Stream_Window_Size   : Natural := 1_048_576;
      Initial_Connection_Window_Size : Natural := 1_048_576;
   end record;
   --  Conservative HTTP/2 protocol options.
   --
   --  @field Mode Whether HTTP/2 is disabled, allowed by ALPN, or required.
   --  @field Max_Frame_Size Inbound frame payload limit. The default is the
   --         HTTP/2 initial maximum frame size and the accepted range is
   --         16_384 .. 16_777_215.
   --  @field Max_Header_List_Size Bounded decoded header-list limit for HPACK
   --         and request/response mapping.
   --  @field Max_Body_Size Maximum HTTP/2 DATA bytes accumulated into the
   --         buffered response object before deterministic rejection.
   --  @field Enable_Server_Push Reserved for future work. This release rejects
   --         enabled push because no push cache or promised-request store is
   --         implemented.
   --  @field Enable_Multiplexing Enable the bounded multiplexed
   --         connection model. This requires Mode to be HTTP2_Allowed or
   --         HTTP2_Required. When False, callers keep the conservative single-stream path.
   --  @field Enable_Public_Streaming Enable public response streaming
   --         over HTTP/2 DATA frames. The public API yields body bytes only;
   --         frame boundaries, WINDOW_UPDATE, RST_STREAM, GOAWAY, SETTINGS,
   --         PING, padding, and continuation handling remain protocol internals.
   --  @field Enable_Upload_Streaming Enable request-body producers over
   --         HTTP/2 DATA frames. DATA emission is bounded by the peer maximum
   --         frame size and current stream and connection send windows.
   --  @field Max_Per_Stream_Buffered_Bytes Bounded unread DATA-byte queue per
   --         public HTTP/2 response stream before deterministic rejection.
   --         Consumed bytes are removed from the queue; total decoded response
   --         body bytes remain bounded separately by Max_Body_Size. This is not
   --         a persistent-cache tee; streamed responses are not cached by default.
   --  @field Max_Total_Queued_Body_Bytes Bounded aggregate unread DATA-byte
   --         queue across all active streams on one HTTP/2 connection. This
   --         prevents one slow caller per stream from causing unbounded memory
   --         growth when DATA frames are interleaved across multiplexed streams.
   --  @field Max_Active_Streamed_Responses Caller-side cap for live public HTTP/2
   --         streaming responses on one connection.
   --  @field Max_Active_Upload_Streams Caller-side cap for live HTTP/2 upload
   --         producer streams on one connection.
   --  @field Flow_Control_Update_Threshold Deterministic receive-window credit
   --         threshold. In-memory tests may credit immediately; production frame
   --         layers must never send zero or overflowing WINDOW_UPDATE increments.
   --  @field Upload_Flow_Control_Timeout_MS Timeout intent used when an upload
   --         producer cannot progress because HTTP/2 send windows are exhausted.
   --  @field Allow_Unknown_Length_HTTP2_Bodies Permit explicitly configured
   --         unknown-length HTTP/2 uploads delimited by DATA END_STREAM. When
   --         False, unknown-length producers are rejected before unsafe send.
   --  @field Enable_Streaming_Decompression Reserved for a future streaming
   --         decompressor. streaming responses remain raw by default.
   --  @field Local_Max_Concurrent_Streams Caller-side cap for active streams
   --         per HTTP/2 connection. The effective cap is the minimum of this
   --         value and SETTINGS_MAX_CONCURRENT_STREAMS received from the peer.
   --  @field Initial_Stream_Window_Size Initial per-stream receive/send window
   --         tracked by the bounded multiplexed connection model.
   --  @field Initial_Connection_Window_Size Initial connection-level window
   --         tracked by the bounded multiplexed connection model.

   Default_HTTP2_Options : constant HTTP2_Options :=
     (Mode                    => HTTP2_Disabled,
      Max_Frame_Size          => 16_384,
      Max_Header_List_Size    => 65_536,
      Max_Body_Size           => 16_777_216,
      Enable_Server_Push      => False,
      Enable_Multiplexing     => False,
      Enable_Public_Streaming => False,
      Enable_Upload_Streaming => False,
      Max_Per_Stream_Buffered_Bytes => 16_777_216,
      Max_Total_Queued_Body_Bytes => 67_108_864,
      Max_Active_Streamed_Responses => 1,
      Max_Active_Upload_Streams => 1,
      Flow_Control_Update_Threshold => 16_384,
      Upload_Flow_Control_Timeout_MS => 30_000,
      Allow_Unknown_Length_HTTP2_Bodies => False,
      Enable_Streaming_Decompression => False,
      Local_Max_Concurrent_Streams => 1,
      Initial_Stream_Window_Size => 1_048_576,
      Initial_Connection_Window_Size => 1_048_576);
   --  Defaults preserve exact pre-HTTP/2 HTTP/1.1, buffered
   --  HTTP/2, caching, upload, diagnostics, and multiplexing behavior.

   function Validate
     (Options : HTTP2_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate HTTP/2 options without network I/O.

   function ALPN_Advertisement
     (Options : HTTP2_Options) return String;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return the ordered ALPN protocol list represented as comma-separated
   --  protocol names for deterministic tests and TLS bridge configuration.
   --  Disabled mode returns "http/1.1". Allowed mode returns "h2,http/1.1".
   --  Required mode returns "h2".

   function Normalize_ALPN_Selected
     (Protocol : String) return Selected_Protocol;
   --  GNATdoc contract.
   --  @param Protocol Subprogram parameter.
   --  @return Subprogram result.
   --  Normalize a selected ALPN protocol string.

   function Selected_Status
     (Options  : HTTP2_Options;
      Selected : Selected_Protocol) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @param Selected Subprogram parameter.
   --  @return Subprogram result.
   --  Return Ok when Selected is compatible with Options.
   --  HTTP2_Required rejects no ALPN, HTTP/1.1, and unsupported protocols.
   --  HTTP2_Disabled rejects h2 so callers do not silently switch protocols.

   function Execution_Status_For_Selected
     (Options  : HTTP2_Options;
      Selected : Selected_Protocol) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @param Selected Subprogram parameter.
   --  @return Subprogram result.
   --  Return Ok when the selected protocol can be executed by the configured
   --  path. h2 is executable for the conservative single-stream buffered scope,
   --  explicitly enabled bounded multiplexing, and streaming/upload
   --  helpers when their options are valid. Server push, HTTP/3, and QUIC
   --  remain unsupported unless a later package implements them deliberately.
end Http_Client.HTTP2;
