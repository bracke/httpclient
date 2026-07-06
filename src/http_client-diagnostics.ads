with Ada.Calendar;
with Ada.Strings.Bounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Types;

package Http_Client.Diagnostics is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Opt-in structured diagnostics and observability support.
   --
   --  Diagnostics are disabled unless a caller explicitly creates a context and
   --  attaches it through client execution options. The library does not write
   --  to standard output, standard error, files, system logs, or global hooks by
   --  default. Events are advisory and must not replace Result_Status values for
   --  application control flow.
   --
   --  The event model is intentionally bounded. Text fields use fixed maximum
   --  lengths and fields that do not apply to an event keep deterministic
   --  default values. Header values, cookies, credentials, and bodies are
   --  redacted by default.

   package Text_256 is new Ada.Strings.Bounded.Generic_Bounded_Length (256);
   subtype Bounded_Text is Text_256.Bounded_String;

   type Diagnostic_ID is new Natural;
   --  Per-context request, connection, or stream correlation identifier.

   type Protocol_Version is
     (Protocol_Unknown,
      Protocol_HTTP_1_1,
      Protocol_HTTP_2,
      Protocol_HTTP_3);
   --  Protocol label used only for diagnostics and metrics correlation.

   type Cache_Result is
     (Cache_Not_Applicable,
      Cache_Hit,
      Cache_Miss,
      Cache_Stale,
      Cache_Revalidated,
      Cache_Bypassed,
      Cache_Rejected);
   --  Bounded cache-observability classification.

   type Event_Kind is
     (Request_Start,
      Async_Request_Submitted,
      Async_Request_Queued,
      Async_Request_Dequeued,
      Async_Request_Started,
      Async_Request_Completed,
      Async_Request_Failed,
      Async_Cancel_Requested,
      Async_Cancelled_Before_Start,
      Async_Cancel_Observed,
      Async_Queue_Full,
      Async_Worker_Started,
      Async_Worker_Stopped,
      Async_Pool_Shutdown,
      Async_Result_Consumed,
      DNS_Connect_Start,
      TCP_Connection_Opened,
      TLS_Handshake_Start,
      TLS_Handshake_Finished,
      Certificate_Verification_Result,
      Proxy_CONNECT_Start,
      Proxy_CONNECT_Finished,
      SOCKS_Proxy_Selected,
      SOCKS_Tunnel_Start,
      SOCKS_Greeting_Sent,
      SOCKS_Method_Selected,
      SOCKS_Authentication_Finished,
      SOCKS_CONNECT_Sent,
      SOCKS_Reply_Received,
      SOCKS_Tunnel_Finished,
      Request_Headers_Sent,
      Request_Body_Progress,
      Response_Headers_Received,
      Response_Body_Progress,
      Redirect_Decision,
      Retry_Decision,
      Cache_Lookup_Result,
      Cache_Revalidation,
      Encrypted_Cache_Store_Open,
      Encrypted_Cache_Hit,
      Encrypted_Cache_Miss,
      Encrypted_Cache_Encryption,
      Encrypted_Cache_Decryption,
      Encrypted_Cache_Authentication_Failure,
      Encrypted_Cache_Corrupt_Entry,
      Encrypted_Cache_Eviction,
      Encrypted_Cache_Clear,
      Encrypted_Cache_Write_Failure,
      Decompression_Result,
      Cookie_Storage_Decision,
      Connection_Pool_Checkout,
      Connection_Pool_Checkin,
      HTTP2_Preface_Sent,
      HTTP2_Settings_Exchanged,
      HTTP2_Stream_Opened,
      HTTP2_Frame_Diagnostic,
      HTTP2_Stream_Closed,
      HTTP3_Enabled,
      HTTP3_Candidate_Selected,
      QUIC_Connection_Start,
      QUIC_Connection_Failed,
      HTTP3_Unsupported_Fallback,
      HTTP3_Settings_Exchanged,
      HTTP3_Stream_Opened,
      HTTP3_Frame_Diagnostic,
      HTTP3_QPACK_Decode_Failure,
      HTTP3_GOAWAY_Received,
      HTTP3_Execution_Unsupported,
      Alt_Svc_Header_Seen,
      Alt_Svc_Accepted,
      Alt_Svc_Rejected,
      Alt_Svc_Cache_Hit,
      Alt_Svc_Expired,
      HTTPS_SVCB_Lookup_Start,
      HTTPS_SVCB_Result_Accepted,
      HTTPS_SVCB_Result_Rejected,
      Discovery_Selected_HTTP3,
      Discovery_Skipped_Due_To_Proxy,
      Discovery_Fallback_Decision,
      Discovery_Cache_Cleared,
      Request_Finish,
      Streaming_Response_Opened,
      Streaming_Response_Closed,
      Upload_Producer_Event,
      Multipart_Event,
      Error_Event);
   --  Stable lifecycle event kind. Verbose protocol and body-preview events are
   --  emitted only when the caller enables the corresponding policy fields.
   --  SOCKS events are structural only and must not include SOCKS usernames,
   --  passwords, raw credential bytes, origin authorization fields, cookies,
   --  request bodies, or TLS client-certificate material. Encrypted-cache and async lifecycle
   --  events are structural only and must not include raw keys, passwords,
   --  decrypted URLs, headers, bodies, cookies, or credentials.

   type Callback_Failure_Policy is
     (Ignore_Callback_Failures,
      Abort_On_Callback_Failure);
   --  Determines whether observer exceptions or non-Ok callback statuses abort
   --  the HTTP operation. The default isolates diagnostics from the protocol.

   type Redaction_Policy is record
      Allow_Header_Values       : Boolean := False;
      Unsafe_Disable_Redaction  : Boolean := False;
      Allow_Body_Previews       : Boolean := False;
      Max_Body_Preview_Bytes    : Natural := 0;
      Redact_Cookie_Names       : Boolean := True;
      Extra_Redacted_Headers    : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
   end record;
   --  Conservative redaction and preview policy.
   --
   --  @field Allow_Header_Values Allows non-redacted header values to appear in
   --         diagnostic events. The default reports names and structure only.
   --  @field Unsafe_Disable_Redaction Explicitly disables the built-in and
   --         caller-supplied redaction list. This is unsafe and should not be
   --         enabled in production logs.
   --  @field Allow_Body_Previews Allows bounded body preview diagnostics. The
   --         default is False; diagnostics must not consume, buffer, or duplicate
   --         bodies just for logging.
   --  @field Max_Body_Preview_Bytes Maximum body-preview bytes when previews are
   --         explicitly allowed.
   --  @field Redact_Cookie_Names Redacts cookie names as well as values in
   --         cookie-specific diagnostic messages.
   --  @field Extra_Redacted_Headers Caller extension to the default sensitive
   --         header-name list.

   Default_Redaction_Policy : constant Redaction_Policy :=
     (Allow_Header_Values      => False,
      Unsafe_Disable_Redaction => False,
      Allow_Body_Previews      => False,
      Max_Body_Preview_Bytes   => 0,
      Redact_Cookie_Names      => True,
      Extra_Redacted_Headers   => Http_Client.Headers.Empty);

   type Diagnostic_Event is record
      Kind                 : Event_Kind := Request_Start;
      Request_ID           : Diagnostic_ID := 0;
      Connection_ID        : Diagnostic_ID := 0;
      Stream_ID            : Natural := 0;
      URI_Or_Origin        : Bounded_Text := Text_256.Null_Bounded_String;
      Has_Method           : Boolean := False;
      Method               : Http_Client.Types.Method_Name := Http_Client.Types.GET;
      Status_Code          : Natural := 0;
      Result               : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Request_Byte_Count   : Natural := 0;
      Response_Byte_Count  : Natural := 0;
      Elapsed_Milliseconds : Natural := 0;
      Redirect_Count       : Natural := 0;
      Retry_Attempt        : Natural := 0;
      Cache                : Cache_Result := Cache_Not_Applicable;
      Protocol             : Protocol_Version := Protocol_Unknown;
      Header_Name          : Bounded_Text := Text_256.Null_Bounded_String;
      Header_Value         : Bounded_Text := Text_256.Null_Bounded_String;
      Header_Redacted      : Boolean := False;
      Message              : Bounded_Text := Text_256.Null_Bounded_String;
   end record;
   --  Bounded structured event. Empty/default fields mean not applicable.

   type Metrics_Snapshot is record
      Requests_Started      : Natural := 0;
      Requests_Completed    : Natural := 0;
      Bytes_Sent            : Natural := 0;
      Bytes_Received        : Natural := 0;
      Cache_Hits            : Natural := 0;
      Cache_Misses          : Natural := 0;
      Retries_Attempted     : Natural := 0;
      Redirects_Followed    : Natural := 0;
      Connections_Opened    : Natural := 0;
      Pooled_Reuses         : Natural := 0;
      HTTP2_Streams_Opened  : Natural := 0;
      HTTP2_Resets          : Natural := 0;
      TLS_Failures          : Natural := 0;
      HTTP3_Events          : Natural := 0;
      Upload_Producer_Events : Natural := 0;
      Multipart_Events      : Natural := 0;
      Callback_Failures     : Natural := 0;
   end record;
   --  Per-context bounded aggregate counters. Counters are not global.
   --  Upload and multipart counters count structural events only; they do not
   --  imply that any request body, multipart field value, filename, or file
   --  content was captured.

   type Timing_Snapshot is record
      Request_Finish_Count             : Natural := 0;
      Request_Total_Milliseconds       : Natural := 0;
      TLS_Handshake_Count              : Natural := 0;
      TLS_Handshake_Total_Milliseconds : Natural := 0;
   end record;
   --  Per-context aggregate lifecycle timings derived from diagnostic events.
   --  Totals are saturating Natural counters; callers can divide by the matching
   --  count to derive averages without diagnostics retaining per-request state.

   type Event_Callback is access procedure
     (Event  : Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status);
   --  Synchronous non-owning event callback. Callbacks should return promptly and
   --  must not re-enter the same mutable client in ways that create deadlocks or
   --  reentrancy hazards.

   type Clock_Function is access function return Ada.Calendar.Time;
   --  Optional test clock for timing-related diagnostics.

   type Diagnostics_Context is tagged private;
   type Context_Access is access all Diagnostics_Context;
   --  Mutable opt-in diagnostics context. Sharing one context between tasks
   --  requires external synchronization.

   function To_Text (Value : String) return Bounded_Text;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Convert Value to bounded diagnostic text, truncating deterministically.

   function Text (Value : Bounded_Text) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored bounded text as a String.

   procedure Initialize
     (Context         : in out Diagnostics_Context;
      Enabled         : Boolean := True;
      Observer        : Event_Callback := null;
      Redaction       : Redaction_Policy := Default_Redaction_Policy;
      Failure_Policy  : Callback_Failure_Policy := Ignore_Callback_Failures;
      Clock           : Clock_Function := null;
      Metrics_Enabled : Boolean := True);
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Enabled Subprogram parameter.
   --  @param Observer Subprogram parameter.
   --  @param Redaction Subprogram parameter.
   --  @param Failure_Policy Subprogram parameter.
   --  @param Clock Subprogram parameter.
   --  @param Metrics_Enabled Subprogram parameter.
   --  Initialize a diagnostics context. Disabled contexts produce no events.

   procedure Set_Observer
     (Context  : in out Diagnostics_Context;
      Observer : Event_Callback);
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Observer Subprogram parameter.
   --  Replace the synchronous observer callback.

   procedure Set_Redaction_Policy
     (Context   : in out Diagnostics_Context;
      Redaction : Redaction_Policy);
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Redaction Subprogram parameter.
   --  Replace the redaction policy used for subsequent events.

   procedure Set_Callback_Failure_Policy
     (Context : in out Diagnostics_Context;
      Policy  : Callback_Failure_Policy);
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Policy Subprogram parameter.
   --  Configure deterministic callback failure handling.

   function Add_Redacted_Header
     (Policy : in out Redaction_Policy;
      Name   : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Policy Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Add Name to a caller-owned redaction policy extension list.

   function Is_Enabled (Context : Diagnostics_Context) return Boolean;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when this context emits events.

   function Is_Redacted_Header
     (Policy : Redaction_Policy;
      Name   : String) return Boolean;
   --  GNATdoc contract.
   --  @param Policy Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Name is sensitive under Policy.

   function Safe_Header_Value
     (Policy : Redaction_Policy;
      Name   : String;
      Value  : String) return String;
   --  GNATdoc contract.
   --  @param Policy Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Return either a redacted marker, an empty structural value, or Value
   --  according to Policy. Authorization, Proxy-Authorization, Cookie,
   --  Set-Cookie, and related credential-bearing headers are redacted by
   --  default.

   function Safe_Body_Preview
     (Policy : Redaction_Policy;
      Body_Data   : String) return String;
   --  GNATdoc contract.
   --  @param Policy Subprogram parameter.
   --  @param Body_Data Subprogram parameter.
   --  @return Subprogram result.
   --  Return an empty string unless body previews are explicitly enabled. When
   --  enabled, the returned preview is capped by Max_Body_Preview_Bytes and
   --  never causes transports, upload producers, multipart bodies, or streaming
   --  responses to be buffered by diagnostics.

   function Next_Request_ID
     (Context : in out Diagnostics_Context) return Diagnostic_ID;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Allocate a monotonically increasing per-context request id.

   function Next_Connection_ID
     (Context : in out Diagnostics_Context) return Diagnostic_ID;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Allocate a monotonically increasing per-context connection id.

   function Now (Context : Diagnostics_Context) return Ada.Calendar.Time;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Return the injected clock value, or Ada.Calendar.Clock.

   function Elapsed_Milliseconds
     (Context : Diagnostics_Context;
      Start   : Ada.Calendar.Time;
      Stop    : Ada.Calendar.Time) return Natural;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Start Subprogram parameter.
   --  @param Stop Subprogram parameter.
   --  @return Subprogram result.
   --  Convert a duration to non-negative whole milliseconds.

   function Emit
     (Context : in out Diagnostics_Context;
      Event   : Diagnostic_Event) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @param Event Subprogram parameter.
   --  @return Subprogram result.
   --  Redact, count, and synchronously deliver Event when diagnostics are
   --  enabled. Observer exceptions are caught and converted according to the
   --  configured callback failure policy.

   function Snapshot (Context : Diagnostics_Context) return Metrics_Snapshot;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Return deterministic aggregate counters.

   function Timing (Context : Diagnostics_Context) return Timing_Snapshot;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Return aggregate lifecycle timings derived from emitted events.

   function Average_Request_Milliseconds
     (Snapshot : Timing_Snapshot) return Natural;
   --  GNATdoc contract.
   --  @param Snapshot Subprogram parameter.
   --  @return Subprogram result.
   --  Return the whole-millisecond average for completed request timings, or 0
   --  when no completed request timing has been observed.

   function Average_TLS_Handshake_Milliseconds
     (Snapshot : Timing_Snapshot) return Natural;
   --  GNATdoc contract.
   --  @param Snapshot Subprogram parameter.
   --  @return Subprogram result.
   --  Return the whole-millisecond average for TLS handshake timings, or 0 when
   --  no TLS handshake timing has been observed.

   procedure Reset_Metrics (Context : in out Diagnostics_Context);
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  Reset aggregate counters without changing ids, observer, or redaction.

   function Last_Callback_Status
     (Context : Diagnostics_Context) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Return the last callback failure status captured by Emit, or Ok.

private
   type Diagnostics_Context is tagged record
      Enabled_Value      : Boolean := False;
      Observer_Value     : Event_Callback := null;
      Redaction_Value    : Redaction_Policy := Default_Redaction_Policy;
      Failure_Value      : Callback_Failure_Policy := Ignore_Callback_Failures;
      Clock_Value        : Clock_Function := null;
      Metrics_On         : Boolean := True;
      Metrics_Value      : Metrics_Snapshot := (others => 0);
      Timing_Value       : Timing_Snapshot := (others => 0);
      Next_Request_Value : Diagnostic_ID := 1;
      Next_Conn_Value    : Diagnostic_ID := 1;
      Last_Callback      : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   end record;
end Http_Client.Diagnostics;
