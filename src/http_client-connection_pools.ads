with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Transports.TLS;
with Http_Client.URI;

package Http_Client.Connection_Pools is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Bounded HTTP/1.1 persistent-connection pool metadata and lifecycle
   --  policy.
   --
   --  This package models explicit persistent connection reuse. The pool key is
   --  intentionally conservative: direct connections are keyed by scheme,
   --  origin host, effective origin port, TLS verification-relevant options,
   --  mutual-TLS client-certificate identity, and proxy configuration. Plain HTTP proxy connections are keyed by both
   --  proxy and origin. HTTPS CONNECT tunnels, when transport support is added,
   --  are likewise keyed by the target origin plus the proxy endpoint. A key is
   --  never broadened merely because a TLS certificate covers multiple names.
   --  A mutual-TLS connection authenticated with one client certificate is not
   --  compatible with no-certificate requests or a different credential.
   --
   --  This package owns pool policy, limits, checkout/checkin state, idle
   --  expiration, shutdown, and compatibility tests. The public type
   --  intentionally stores opaque lifecycle metadata rather than exposing raw
   --  TCP/OpenSSL handles. Transport-attached client code must keep the actual
   --  handle beside the returned token and close that handle whenever Check_In
   --  is not permitted. This package does not parse HTTP, read or write
   --  sockets, implement HTTP/2, multiplex, pipeline, cache, spawn tasks, or
   --  expose raw TCP/OpenSSL handles.

   type Pooling_Options is record
      Enabled                         : Boolean := False;
      Max_Total_Idle_Connections      : Natural := 8;
      Max_Idle_Connections_Per_Key    : Natural := 2;
      Max_Connection_Age_Seconds      : Natural := 300;
      Max_Idle_Time_Seconds           : Natural := 60;
      Max_Requests_Per_Connection     : Natural := 100;
   end record;
   --  Explicit bounded connection-pooling options.
   --
   --  @field Enabled Enables use of a high-level-client-owned HTTP/1.1
   --         persistent connection pool. Low-level one-shot execution remains
   --         one-request-per-connection.
   --  @field Max_Total_Idle_Connections Maximum number of idle entries kept by
   --         one pool. Enabled pooling requires this value to be nonzero.
   --  @field Max_Idle_Connections_Per_Key Maximum number of idle entries kept
   --         for one compatibility key. Enabled pooling requires this value to be nonzero.
   --  @field Max_Connection_Age_Seconds Maximum age before a connection is no
   --         longer reusable. Zero disables age-based reuse.
   --  @field Max_Idle_Time_Seconds Maximum idle duration before a connection is
   --         no longer reusable. Zero disables idle-time reuse.
   --  @field Max_Requests_Per_Connection Maximum sequential request/response
   --         exchanges allowed on one connection. Zero means one exchange only.

   Default_Pooling_Options : constant Pooling_Options :=
     (Enabled                         => False,
      Max_Total_Idle_Connections      => 8,
      Max_Idle_Connections_Per_Key    => 2,
      Max_Connection_Age_Seconds      => 300,
      Max_Idle_Time_Seconds           => 60,
      Max_Requests_Per_Connection     => 100);
   --  Conservative defaults. Pooling remains disabled until configured.

   type Pooled_Protocol is
     (Pool_HTTP_1_1,
      Pool_HTTP_2,
      Pool_HTTP_3);
   --  Protocol identity carried by compatibility keys.
   --
   --  Current transport-attached reuse is HTTP/1.1 only. The HTTP/2 and
   --  HTTP/3 values reserve the key boundary needed by future multiplexed
   --  connection pools so they cannot accidentally share HTTP/1.1 entries for
   --  the same origin, TLS, and proxy route.

   type Pool_Key is private;
   --  Compatibility key for safe protocol-specific connection reuse.

   function Key_For
     (URI      : Http_Client.URI.URI_Reference;
      Proxy    : Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.No_Proxy_Config;
      TLS      : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Protocol : Pooled_Protocol := Pool_HTTP_1_1)
      return Pool_Key;
   --  GNATdoc contract.
   --  @param URI Subprogram parameter.
   --  @param Proxy Subprogram parameter.
   --  @param TLS Subprogram parameter.
   --  @return Subprogram result.
   --  Build a conservative key for a request URI, proxy configuration, TLS
   --  options, and protocol identity. The URI must already be parsed. Invalid
   --  inputs produce an invalid key that is never compatible with valid keys.

   function Is_Valid (Key : Pool_Key) return Boolean;
   --  GNATdoc contract.
   --  @param Key Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Key was built from a parsed http or https URI.

   function Same_Key (Left, Right : Pool_Key) return Boolean;
   --  GNATdoc contract.
   --  @param Left Subprogram parameter.
   --  @param Right Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only when every reuse-relevant key component is equal.

   function Image (Key : Pool_Key) return String;
   --  GNATdoc contract.
   --  @param Key Subprogram parameter.
   --  @return Subprogram result.
   --  Return a deterministic diagnostic image of Key without exposing secrets.
   --  Proxy-Authorization values are represented only by their presence.

   function Validate
     (Options : Pooling_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate pooling limits. Disabled options are always accepted. Enabled
   --  pooling requires at least one idle slot globally and per key, and the
   --  per-key idle limit must not exceed the global idle limit.

   function Transport_Attached_Reuse_Available return Boolean;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return True only when this build contains a client execution path that
   --  stores real TCP/TLS handles in a pool and reuses them for later requests.
   --  The high-level buffered HTTP/1.1 Client path provides that
   --  transport-attached reuse while this package continues to expose only
   --  policy and lifecycle metadata.

   function Request_Permits_Persistent_Reuse
     (Request : Http_Client.Requests.Request) return Boolean;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Request itself does not forbid persistent connection
   --  reuse. Caller-supplied Connection: close, Connection: upgrade, and
   --  Upgrade headers are rejected conservatively.

   function Response_Permits_Reuse
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response) return Boolean;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only when the completed buffered response leaves the
   --  HTTP/1.1 connection cleanly reusable for the next request.
   --
   --  The predicate rejects caller or server `Connection: close`, HTTP/1.0
   --  responses, connection-close-delimited bodies, unsupported transfer
   --  codings, and any response that lacks explicit reusable framing unless
   --  the originating request/status combination proves that no body is
   --  present. It is intentionally conservative and is suitable for deciding
   --  whether a fully consumed buffered response may be checked back into a
   --  pool. Streaming responses must additionally prove that end-of-body was
   --  reached before using this predicate.

   type Pool_Token is private;
   --  Checked-out connection identity used by the pool lifecycle. The token is
   --  metadata only; it is not a socket or TLS handle.

   function Is_Valid (Token : Pool_Token) return Boolean;
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Token represents a checked-out pool entry.

   type Connection_Pool is limited private;
   --  Bounded, synchronous, non-task-safe pool state.
   --
   --  Callers sharing one pool between Ada tasks must serialize access. The
   --  implementation never holds a pool state operation across blocking
   --  network I/O because transports remain outside this package.

   procedure Initialize
     (Item    : in out Connection_Pool;
      Options : Pooling_Options := Default_Pooling_Options);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  Reset Item to an open, empty pool using Options.

   function Configure
     (Item    : in out Connection_Pool;
      Options : Pooling_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Replace pool options after validation and close all idle entries.

   procedure Close_All (Item : in out Connection_Pool);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  Close/discard all idle entries while leaving the pool open for future
   --  checkouts.

   procedure Shutdown (Item : in out Connection_Pool);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  Close/discard all idle entries and reject future checkouts/checkins.

   function Is_Closed (Item : Connection_Pool) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True after Shutdown.

   function Idle_Count (Item : Connection_Pool) return Natural;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of currently retained idle entries.

   function Idle_Count
     (Item : Connection_Pool;
      Key  : Pool_Key) return Natural;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Key Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of idle entries compatible with Key.

   function Check_Out
     (Item   : in out Connection_Pool;
      Key    : Pool_Key;
      Token  : out Pool_Token;
      Reused : out Boolean) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Key Subprogram parameter.
   --  @param Token Subprogram parameter.
   --  @param Reused Subprogram parameter.
   --  @return Subprogram result.
   --  Try to acquire an idle entry for Key.
   --
   --  If an idle entry exists, Token is valid and Reused is True. If no idle
   --  entry exists, Token is invalid, Reused is False, and Ok is returned so
   --  the caller may open a fresh transport connection. Pool_Closed and
   --  Invalid_Request are returned for a closed pool or invalid key.

   function Begin_Fresh
     (Item  : in out Connection_Pool;
      Key   : Pool_Key;
      Token : out Pool_Token) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Key Subprogram parameter.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.
   --  Register a newly opened transport connection as checked out.
   --
   --  This is the companion to Check_Out for the no-idle-entry path: after the
   --  caller opens a fresh TCP/TLS connection, Begin_Fresh creates the token
   --  that must later be passed to Check_In after the response body is fully
   --  consumed or safely completed. Disabled pooling returns Ok with an invalid
   --  token so one-shot callers can close the fresh connection normally.

   function Check_In
     (Item     : in out Connection_Pool;
      Token    : Pool_Token;
      Reusable : Boolean := True) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Token Subprogram parameter.
   --  @param Reusable Subprogram parameter.
   --  @return Subprogram result.
   --  Return a previously checked-out entry to idle state when Reusable is
   --  True and limits still permit reuse. Non-reusable, expired, over-limit,
   --  or max-request entries are deterministically discarded and return Ok.

   function Register_Fresh_Idle
     (Item     : in out Connection_Pool;
      Key      : Pool_Key;
      Reusable : Boolean := True) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Key Subprogram parameter.
   --  @param Reusable Subprogram parameter.
   --  @return Subprogram result.
   --  Register a freshly completed connection as idle. This helper is useful
   --  for deterministic tests and for buffered execution paths that have just
   --  consumed the complete response body.

   function Stream_Completion_Permits_Check_In
     (Reached_End_Of_Body       : Boolean;
      Closed_Early              : Boolean;
      Failed                    : Boolean;
      Connection_Close_Delimited : Boolean;
      Framing_Permits_Reuse     : Boolean) return Boolean;
   --  GNATdoc contract.
   --  @param Reached_End_Of_Body Subprogram parameter.
   --  @param Closed_Early Subprogram parameter.
   --  @param Failed Subprogram parameter.
   --  @param Connection_Close_Delimited Subprogram parameter.
   --  @param Framing_Permits_Reuse Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only for a streaming response completion state that may
   --  check the owned connection back into the pool. Early close, mid-body
   --  failure, close-delimited framing, and a response/request framing verdict
   --  that does not permit reuse all force discard.

private
   use Ada.Strings.Unbounded;

   type Pool_Key is record
      Valid              : Boolean := False;
      Protocol           : Pooled_Protocol := Pool_HTTP_1_1;
      Scheme             : Unbounded_String := Null_Unbounded_String;
      Host               : Unbounded_String := Null_Unbounded_String;
      Host_Class         : Http_Client.URI.Host_Kind := Http_Client.URI.DNS_Name;
      Port               : Http_Client.URI.TCP_Port := 1;
      Proxy_Mode         : Http_Client.Proxies.Proxy_Kind := Http_Client.Proxies.No_Proxy;
      Proxy_Host         : Unbounded_String := Null_Unbounded_String;
      Proxy_Port         : Http_Client.URI.TCP_Port := 1;
      Proxy_Has_Auth     : Boolean := False;
      SOCKS5_Auth        : Http_Client.Proxies.SOCKS5_Authentication_Method :=
        Http_Client.Proxies.SOCKS5_No_Authentication;
      SOCKS5_DNS         : Http_Client.Proxies.SOCKS5_DNS_Mode :=
        Http_Client.Proxies.SOCKS5_Remote_DNS;
      SOCKS5_User_Key    : Unbounded_String := Null_Unbounded_String;
      SOCKS5_Pass_Present : Boolean := False;
      SOCKS5_Pass_Fingerprint : Natural := 0;
      --  Private SOCKS credential discriminator for pool isolation. The raw
      --  password is never stored in the key; only presence and a bounded
      --  non-secret fingerprint are retained so different credentials do not
      --  accidentally share one tunnel. It is intentionally omitted from Image.
      TLS_Verify         : Boolean := True;
      TLS_CA_File        : Unbounded_String := Null_Unbounded_String;
      TLS_CA_Directory   : Unbounded_String := Null_Unbounded_String;
      TLS_Send_SNI       : Boolean := True;
      TLS_Client_Cert_ID : Natural := 0;
      TLS_Client_Cert_Material_Key : Unbounded_String := Null_Unbounded_String;
      --  Private exact material discriminator for mutual-TLS pool isolation.
      --  It is intentionally omitted from Image so diagnostics disclose only
      --  presence/absence, not certificate or private-key paths.
   end record;

   type Pool_Token is record
      Valid         : Boolean := False;
      Key           : Pool_Key;
      Created_At    : Ada.Calendar.Time := Ada.Calendar.Clock;
      Last_Used_At  : Ada.Calendar.Time := Ada.Calendar.Clock;
      Request_Count : Natural := 0;
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Pool_Token);

   type Connection_Pool is limited record
      Options : Pooling_Options := Default_Pooling_Options;
      Closed  : Boolean := False;
      Entries : Entry_Vectors.Vector;
   end record;
end Http_Client.Connection_Pools;
