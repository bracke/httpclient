with Http_Client.Cache;
with Http_Client.Cancellation;
with Http_Client.Cache.Persistent;
with Http_Client.Connection_Pools;
with Http_Client.Cookies;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.Proxies;
with Http_Client.Proxy_Discovery;
with Http_Client.Protocol_Discovery;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Execution;
with Http_Client.Requests;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Ada.Calendar;
private with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Http_Client.URI;

package Http_Client.Clients
  with SPARK_Mode => Off
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  High-level synchronous client configuration and execution.
   --
   --  This package coordinates protocol-neutral requests with the stable
   --  HTTP/1.1, HTTPS/TLS, proxy, SOCKS, redirect, retry, cookie,
   --  decompression, cache, persistent-cache, diagnostics, streaming, upload,
   --  multipart, HTTP/2, client-certificate, and pooling-policy boundaries.
   --  It is deliberately explicit: redirects, retries, cookies, decompression,
   --  caches, persistent stores, diagnostics, proxies, SOCKS, pooling, and
   --  HTTP/3 candidates are disabled until configured.
   --
   --  Ordinary buffered Execute/Get/Post/Put/Delete calls return complete
   --  protocol-neutral responses. Execute_Stream returns a caller-owned stream
   --  with explicit close/read-to-end lifetime. Upload bodies must be
   --  fixed-length and replayable where retries or redirects require replay.
   --  Multipart/form-data bodies are built by Http_Client.Multipart before they
   --  reach this package.
   --
   --  This package does not implement browser behavior: no automatic environment proxy
   --  discovery, automatic PAC/WPAD, browser profile/cache import, hidden global cookie
   --  jar, automatic PAC/WPAD discovery, automatic credential prompting,
   --  OAuth/OIDC/SAML, NTLM/Negotiate/Kerberos, automatic token refresh,
   --  HTML form automation,
   --  broad MIME inference, service workers, preload behavior, browser-managed
   --  upload policy, hidden global diagnostics, hidden global pooling, or
   --  implicit async scheduler. Pooling configuration validates policy,
   --  suppresses synthetic Connection: close for reusable paths, and enables
   --  bounded high-level buffered HTTP/1.1 TCP/TLS handle reuse.

   type Client is tagged private;
   --  Explicit high-level client handle.
   --
   --  A default-initialized Client object is intentionally not usable for
   --  high-level Execute/Get/Post/Put/Delete until Initialize or Configure
   --  succeeds. Create returns an initialized client with conservative
   --  defaults. The handle stores reusable configuration. When configured pooling is
   --  enabled, the high-level buffered client validates explicit HTTP/1.1
   --  persistent connection reuse policy, avoids synthetic Connection: close,
   --  and may retain clean TCP/TLS handles for a later compatible exchange;
   --  low-level one-shot APIs remain one-shot.
   --  Cookie state exists only through an explicitly configured caller-supplied
   --  jar. Low-level one-shot requests keep one-request-per-connection
   --  semantics. High-level pooling configuration validates policy, suppresses
   --  synthesized Connection: close, and retains only clean compatible buffered
   --  HTTP/1.1 TCP/TLS handles. Mutable clients and mutable cookie/header
   --  collections are not synchronized; callers sharing them between tasks must
   --  serialize access.

   type Protocol_Selection_Policy is
     (Protocol_From_Configuration,
      Force_HTTP_1_1,
      Prefer_HTTP_2,
      Force_HTTP_2,
      Prefer_HTTP_3,
      Force_HTTP_3);
   --  Protocol selection policy for high-level execution.
   --
   --  Protocol_From_Configuration preserves the configured HTTP/2, HTTP/3,
   --  and discovery options. Force_HTTP_1_1 disables HTTP/2 ALPN, HTTP/3
   --  candidate execution, and Alt-Svc/HTTPS-SVCB upgrade selection for this
   --  request path. Prefer_HTTP_2 enables h2 ALPN while allowing HTTP/1.1
   --  fallback before request bytes are sent. Force_HTTP_2 requires TLS ALPN
   --  h2, rejects plain HTTP because h2c is not implemented, and rejects a
   --  TLS connection that negotiates HTTP/1.1.
   --  Prefer_HTTP_3 enables the experimental HTTP/3 candidate path with
   --  before-send fallback, subject to configured QUIC/proxy capability.
   --  Force_HTTP_3 requires the experimental HTTP/3 candidate path and disables
   --  fallback. Git smart HTTP callers that need the high-level buffered path can select
   --  protocol behavior here; pull-based streaming protocol selection lives in
   --  Http_Client.Response_Streams.Streaming_Options.Protocol_Policy.

   type Execution_Options is record
      Max_Response_Size    : Natural := 16_777_216;
      Max_Header_Size      : Natural := 65_536;
      Max_Header_Line_Size : Natural := 8_192;
      Max_Body_Size        : Natural := 16_777_216;
      Read_Buffer_Size     : Positive := 4_096;
      Timeouts            : Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
      Cancellation        : Http_Client.Cancellation.Cancellation_Token_Access := null;
      TLS                 : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Add_Connection_Close : Boolean := True;
      Cookie_Jar           : Http_Client.Cookies.Cookie_Jar_Access := null;
      Strict_Cookies       : Boolean := False;
      Merge_Jar_Cookies    : Boolean := False;
      Advertise_Accept_Encoding : Boolean := False;
      Proxy               : Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.No_Proxy_Config;
      Diagnostics         : Http_Client.Diagnostics.Context_Access := null;
      Protocol_Policy     : Protocol_Selection_Policy := Prefer_HTTP_2;
   end record;
   --  Options for one-shot in-memory execution.
   --
   --  @field Max_Response_Size Maximum total response bytes kept in memory.
   --  @field Max_Header_Size Maximum status-line plus header-section bytes,
   --         including the terminating CRLF CRLF.
   --  @field Max_Header_Line_Size Maximum bytes in one status or header line,
   --         excluding the terminating CRLF.
   --  @field Max_Body_Size Maximum response body bytes kept in memory.
   --  @field Read_Buffer_Size Maximum bytes requested from the transport per
   --         low-level read.
   --  @field Timeouts Timeout intent for high-level one-shot execution. For
   --         http:// it is passed to the plain TCP transport. For https:// it
   --         is used as the TLS timeout default when TLS.Timeouts is left at
   --         its all-zero default. Explicit TLS.Timeouts still take precedence.
   --         The underlying transport may not enforce each timeout precisely
   --         on all platforms. Zero disables that timeout.
   --  @field Cancellation Optional cooperative cancellation token. Null preserves
   --         existing behavior. A cancelled token makes execution return Cancelled
   --         at documented checkpoints and discard the affected connection.
   --  @field TLS TLS verification, SNI, ALPN, CA-location, optional
   --         explicit client-certificate credential, and TLS timeout-intent
   --         options for https:// execution. Verification is enabled by
   --         default. Configuring a client certificate does not create HTTP
   --         Authorization headers and does not disable server verification.
   --         High-level execution recomputes client-certificate applicability
   --         for the current request URI or redirect hop; a valid credential
   --         scoped to another origin is not sent on this TLS connection.
   --         TLS.Timeouts is authoritative for https:// execution when any
   --         TLS timeout field is nonzero; otherwise high-level Timeouts are
   --         used as the TLS default for this request.
   --  @field Add_Connection_Close When True, execution serializes a temporary
   --         request copy with `Connection: close` if the caller did not supply
   --         a Connection header. The original request object is not mutated.
   --  @field Cookie_Jar Optional in-memory jar. Null preserves stateless behavior: no cookies are stored or replayed.
   --  @field Strict_Cookies When False, malformed Set-Cookie fields are ignored
   --         after the response is returned. When True, the first cookie error is
   --         reported after the response has been read and parsed.
   --  @field Merge_Jar_Cookies When False, an explicit caller Cookie header wins
   --         and no jar-generated Cookie field is added. When True, jar cookies
   --         are appended to the explicit Cookie value in one generated field.
   --  @field Advertise_Accept_Encoding When True and the request has no
   --         Accept-Encoding header, execution serializes a temporary request
   --         copy with only the encodings this library can decode. This does
   --         not by itself mutate the returned raw Response body; use
   --         Execute_Decoded to request a decoded view.
   --  @field Proxy Explicit proxy configuration. No_Proxy_Config preserves
   --         direct execution. HTTP proxy configuration routes plain HTTP
   --         requests through the proxy using absolute-form request targets.
   --         SOCKS5 proxy configuration opens a CONNECT tunnel first and then
   --         serializes plain HTTP requests in origin-form through that tunnel.
   --         SOCKS credentials are used only during SOCKS negotiation and are
   --         never emitted as HTTP Proxy-Authorization headers. An explicit
   --         HTTP proxy authorization value attached to this config is added
   --         only to proxy-directed HTTP requests: absolute-form plain HTTP
   --         requests and HTTPS CONNECT tunnel establishment. It is not sent
   --         inside the origin TLS stream, to direct origins, or to SOCKS
   --         origin-form requests. Caller-supplied Proxy-Authorization headers
   --         are stripped from origin-form wire requests prepared by this
   --         client so proxy credentials do not leak to origin servers. SOCKS
   --         diagnostics report structural negotiation progress and result
   --         codes without copying SOCKS credentials or detailed target host
   --         names into handshake events. DNS,
   --         connect, and timeout failures while opening the proxy connection
   --         are reported as Proxy_Connection_Failed where possible. HTTPS over
   --         an explicit HTTP proxy uses CONNECT first, then performs ordinary
   --         origin TLS verification, SNI, ALPN, and optional scoped mTLS
   --         inside the tunnel. HTTPS over an explicit SOCKS5 proxy opens the
   --         SOCKS tunnel first, then performs ordinary origin TLS verification,
   --         SNI, ALPN, and optional scoped mTLS inside that tunnel. SOCKS
   --         username/password credentials are never serialized as HTTP headers,
   --         and origin headers, cookies, request bodies, and client certificates
   --         are sent only after the SOCKS negotiation and origin TLS handshake
   --         have succeeded.
   --  @field Protocol_Policy Protocol selection guard. Use Force_HTTP_1_1 to
   --         disable HTTP/2 ALPN, HTTP/3 candidate execution, and protocol
   --         discovery upgrades for this execution path. Use Prefer_HTTP_2 or
   --         Force_HTTP_2 for buffered HTTPS Git calls that may or must use h2;
   --         Force_HTTP_2 rejects plain HTTP because h2c is not implemented. Use
   --         Prefer_HTTP_3 or Force_HTTP_3 only for buffered HTTPS calls when a
   --         QUIC backend is configured and no proxy/client-certificate
   --         limitation applies. Protocol_From_Configuration preserves the
   --         configured HTTP2, HTTP3, and Discovery settings.
   --  @field Diagnostics Optional caller-owned diagnostics context. Null keeps
   --         execution completely silent and preserves previous behavior. When
   --         non-null, lifecycle events and bounded metrics are emitted through
   --         Http_Client.Diagnostics using its redaction and callback-failure
   --         policy.

   Default_Execution_Options : constant Execution_Options :=
     (Max_Response_Size    => 16_777_216,
      Max_Header_Size      => 65_536,
      Max_Header_Line_Size => 8_192,
      Max_Body_Size        => 16_777_216,
      Read_Buffer_Size     => 4_096,
      Timeouts             => Http_Client.Transports.TCP.Default_Timeouts,
      Cancellation         => null,
      TLS                  => Http_Client.Transports.TLS.Default_TLS_Options,
      Add_Connection_Close => True,
      Cookie_Jar           => null,
      Strict_Cookies       => False,
      Merge_Jar_Cookies    => False,
      Advertise_Accept_Encoding => False,
      Proxy               => Http_Client.Proxies.No_Proxy_Config,
      Diagnostics          => null,
      Protocol_Policy      => Prefer_HTTP_2);

   Strict_Execution_Options : constant Execution_Options :=
     (Max_Response_Size    => 16_777_216,
      Max_Header_Size      => 65_536,
      Max_Header_Line_Size => 8_192,
      Max_Body_Size        => 16_777_216,
      Read_Buffer_Size     => 4_096,
      Timeouts             => Http_Client.Transports.TCP.Default_Timeouts,
      Cancellation         => null,
      TLS                  => Http_Client.Transports.TLS.Default_TLS_Options,
      Add_Connection_Close => True,
      Cookie_Jar           => null,
      Strict_Cookies       => False,
      Merge_Jar_Cookies    => False,
      Advertise_Accept_Encoding => False,
      Proxy               => Http_Client.Proxies.No_Proxy_Config,
      Diagnostics          => null,
      Protocol_Policy      => Protocol_From_Configuration);
   --  Safe default options for local and loopback use.

   type Redirect_Method_Policy is
     (Rewrite_Post_To_Get_For_301_302,
      Preserve_Method_For_301_302);
   --  Policy for 301 and 302 method handling.
   --
   --  Rewrite_Post_To_Get_For_301_302 follows common HTTP client behavior for
   --  POST by changing the redirected request to GET and dropping the payload.
   --  Other methods are preserved. Preserve_Method_For_301_302 keeps the
   --  original method and payload, subject to body replay restrictions.

   type Redirect_Options is record
      Follow_Redirects               : Boolean := False;
      Max_Redirects                  : Natural := 5;
      Method_Policy_301_302          : Redirect_Method_Policy :=
        Rewrite_Post_To_Get_For_301_302;
      Allow_Body_Replay              : Boolean := False;
      Allow_HTTPS_To_HTTP_Redirects  : Boolean := False;
      Strip_Credentials_Cross_Origin : Boolean := True;
   end record;
   --  Options for controlled redirect handling.
   --
   --  @field Follow_Redirects False by default so existing execution returns
   --         3xx responses unchanged. Execute_Following_Redirects ignores this
   --         field and follows using the remaining policy fields.
   --  @field Max_Redirects Maximum number of redirect hops before returning
   --         Too_Many_Redirects. The default is 5.
   --  @field Method_Policy_301_302 Method policy for 301 and 302. The default
   --         rewrites POST to GET and drops its body; other methods are
   --         preserved unless body replay is disallowed.
   --  @field Allow_Body_Replay Whether redirected non-empty request payloads may
   --         be resent when policy preserves the method. This is False by
   --         default to avoid surprising replay of unsafe in-memory bodies.
   --  @field Allow_HTTPS_To_HTTP_Redirects Whether https:// to http://
   --         downgrade redirects are allowed. This is False by default.
   --  @field Strip_Credentials_Cross_Origin Remove caller-supplied
   --         Authorization, Cookie, Proxy-Authorization, Git-Protocol, and
   --         related credential/session headers when scheme, host, or effective
   --         port changes. Proxy credentials remain scoped to the configured
   --         proxy route and are never converted into origin credentials.

   Default_Redirect_Options : constant Redirect_Options :=
     (Follow_Redirects               => True,
      Max_Redirects                  => 10,
      Method_Policy_301_302          => Rewrite_Post_To_Get_For_301_302,
      Allow_Body_Replay              => False,
      Allow_HTTPS_To_HTTP_Redirects  => False,
      Strip_Credentials_Cross_Origin => True);

   Strict_Redirect_Options : constant Redirect_Options :=
     (Follow_Redirects               => False,
      Max_Redirects                  => 5,
      Method_Policy_301_302          => Rewrite_Post_To_Get_For_301_302,
      Allow_Body_Replay              => False,
      Allow_HTTPS_To_HTTP_Redirects  => False,
      Strip_Credentials_Cross_Origin => True);

   type Redirect_Result is record
      Final_Response : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Final_URI      : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirect_Count : Natural := 0;
      Final_Request_Was_HEAD : Boolean := False;
   end record;
   --  Result returned by redirect-aware execution.
   --
   --  @field Final_Response Last parsed response received. On Ok this is the
   --         final non-followed response. On Too_Many_Redirects it is the last
   --         redirect response received before the limit stopped execution.
   --  @field Final_URI URI used for Final_Response.
   --  @field Redirect_Count Number of redirect hops successfully followed.
   --  @field Final_Request_Was_HEAD True when the final response belongs to a
   --         HEAD request and therefore must not be decompressed as a body.

   subtype Retry_Result is Http_Client.Retry.Retry_Result;
   --  Retry-aware execution result metadata.

   type Decoded_Redirect_Result is record
      Final_Response : Http_Client.Decompression.Decoded_Response :=
        Http_Client.Decompression.Default_Decoded_Response;
      Final_URI      : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirect_Count : Natural := 0;
   end record;
   --  Result returned by explicit redirect-following plus final-body decoding.
   --
   --  Only the final response body is decoded. Intermediate redirect responses
   --  remain transport/parser inputs for Location and Set-Cookie handling and
   --  are not exposed through this result type. The decoded view preserves the
   --  final response's original headers and encoded body metadata.
   --
   --  @field Final_Response Non-destructive decoded view of the final response.
   --  @field Final_URI URI used for the final response.
   --  @field Redirect_Count Number of redirect hops successfully followed.

   function Create return Client;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Create an initialized high-level client with conservative 1.0 defaults.

   function Supports_Network_IO (Item : Client) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True because the client supports minimal HTTP and HTTPS execution.

   function Is_Initialized (Item : Client) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item currently holds a validated high-level
   --  configuration and may be used with the high-level Execute/Get/Post/Put/
   --  Delete operations. A failed Initialize call marks the client
   --  uninitialized. A failed Configure call preserves the previous state.

   function Execute
     (Item     : Client;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Options  : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status;
   --  Execute one blocking, non-retry, non-pooled HTTP or HTTPS request.
   --
   --  Request must be a validated request created by Http_Client.Requests.Create
   --  and must target an http:// or https:// URI. The request is serialized by
   --  Http_Client.HTTP1, sent through Http_Client.Transports.TCP for http:// or
   --  Http_Client.Transports.TLS for https://, read into a bounded in-memory
   --  buffer, parsed by Http_Client.Responses, and the connection is explicitly
   --  closed on every ordinary path. When the request explicitly contains
   --  Expect: 100-continue, headers are sent first; the body is sent only
   --  after a 100 Continue response. Early final fixed-length and chunked
   --  responses are returned without sending the request body.
   --
   --  Redirect responses are returned unchanged. This one-shot API never
   --  follows Location, never rewrites methods, never forwards credentials to
   --  another origin, and never performs extra network hops. It also remains
   --  cookie-stateless unless Options.Cookie_Jar is non-null. Use
   --  Execute_Following_Redirects or Execute_With_Redirects for explicit bounded
   --  redirect following.
   --
   --  @param Item Stateless client handle.
   --  @param Request Validated request to execute.
   --  @param Response Parsed response on Ok; default response on failure.
   --  @param Options Execution limits and timeout intent.
   --  @return Ok on success; otherwise a coarse project status such as
   --          Invalid_Request, Unsupported_Feature, Connection_Failed,
   --          DNS_Failed, TLS_Failed, TLS_Handshake_Failed,
   --          Certificate_Verification_Failed, Hostname_Verification_Failed,
   --          CA_Store_Failed, Write_Failed, Read_Failed, Timeout,
   --          Incomplete_Message, Response_Too_Large, Header_Too_Large,
   --          Protocol_Error, Invalid_Header, or Internal_Error.


   function Execute_With_Cache
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Response  : out Http_Client.Responses.Response;
      Cache     : in out Http_Client.Cache.Cache_Store;
      Metadata  : out Http_Client.Cache.Cache_Metadata;
      Options   : Execution_Options := Default_Execution_Options;
      Policy    : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Cache Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Policy Subprogram parameter.
   --  @return Subprogram result.
   --  Execute one blocking buffered request through an explicit in-memory HTTP
   --  cache. Fresh cache hits avoid network I/O. Cache misses and stale
   --  revalidations use the ordinary one-shot execution path and preserve TLS,
   --  proxy, cookie, upload, and pooling-independent behavior from previous
   --  phases. Streaming responses, request bodies, multipart uploads,
   --  Authorization, Cookie, Set-Cookie, Content-Encoding, non-GET methods,
   --  and no-store directives are bypassed by the conservative cache policy.

   function Execute_With_Persistent_Cache
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Response  : out Http_Client.Responses.Response;
      Cache     : in out Http_Client.Cache.Persistent.Persistent_Store;
      Metadata  : out Http_Client.Cache.Cache_Metadata;
      Options   : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Cache Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Execute one blocking buffered request through an explicitly opened
   --  persistent cache store. The persistent backend owns durability while
   --  preserving the cacheability, Vary, freshness, sensitive-response,
   --  and conditional revalidation semantics. Streaming responses and request
   --  bodies are not persistently cached by this convenience path.

   function Execute_Stream
     (Request : Http_Client.Requests.Request;
      Stream  : in out Http_Client.Response_Streams.Streaming_Response;
      Options : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Convenience wrapper around streaming execution using a temporary client
   --  handle and explicit one-shot options. The caller owns Stream and must
   --  close it or read to End_Of_Body.

   function Execute_Once
     (Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Options  : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Convenience wrapper around Execute using a temporary client handle.

   function Execute_Decoded
     (Item          : Client;
      Request       : Http_Client.Requests.Request;
      Result        : out Http_Client.Decompression.Decoded_Response;
      Execution     : Execution_Options := Default_Execution_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Decompression Subprogram parameter.
   --  @return Subprogram result.
   --  Execute one request and return a non-destructive decoded response view.
   --
   --  The underlying request remains a one-shot execution. If the caller did
   --  not provide Accept-Encoding, this function advertises only the encodings
   --  supported by Http_Client.Decompression. A caller-supplied
   --  Accept-Encoding header is respected and is not overwritten or duplicated.
   --  The parsed original response and
   --  original headers remain available through Result. Content-Length and
   --  Content-Encoding continue to describe the encoded wire body. Unsupported,
   --  malformed, truncated, or over-limit compressed content is reported with a
   --  deterministic status. Streaming responses are exposed only through explicit Execute_Stream APIs.

   function Execute_Decoded_Once
     (Request       : Http_Client.Requests.Request;
      Result        : out Http_Client.Decompression.Decoded_Response;
      Execution     : Execution_Options := Default_Execution_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Decompression Subprogram parameter.
   --  @return Subprogram result.
   --  Convenience wrapper around Execute_Decoded using a temporary client handle.

   function Execute_Following_Redirects
     (Item             : Client;
      Request          : Http_Client.Requests.Request;
      Result           : out Redirect_Result;
      Execution        : Execution_Options := Default_Execution_Options;
      Redirects        : Redirect_Options := Default_Redirect_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Redirects Subprogram parameter.
   --  @return Subprogram result.
   --  Execute a request and follow a bounded sequence of redirects explicitly.
   --
   --  Status codes 301, 302, 303, 307, and 308 are recognized. Status 300 is
   --  returned unchanged, 304 is never followed, and other 3xx statuses are
   --  returned unchanged. Location may be absolute http/https or a common
   --  relative reference resolved against the current request URI: absolute
   --  path, relative path with dot-segment removal, query-only, fragment-only,
   --  and scheme-relative. URI fragments are never sent in request targets.
   --
   --  For 303, the redirected method becomes GET and the request body is dropped,
   --  except HEAD remains HEAD. For 307 and 308, method and body are preserved
   --  only when Allow_Body_Replay is True and the body is replayable, or when the
   --  body is empty. For 301 and 302, Method_Policy_301_302 controls whether
   --  POST is rewritten to GET or methods are preserved. Host, Content-Length,
   --  and Transfer-Encoding
   --  are removed from each redirected request so serialization recomputes
   --  authority and body framing. Hop-by-hop headers such as Connection,
   --  Keep-Alive, TE, Trailer, and Upgrade are also removed.
   --  Credential-bearing headers are stripped on cross-origin redirects by default.
   --  HTTPS-to-HTTP downgrades are blocked by
   --  default.
   --
   --  Every hop reuses the one-shot execution path and therefore honors the same
   --  timeout intent, response-size limits, and explicit Cookie_Jar option.
   --  Intermediate Set-Cookie fields may populate a supplied jar before the
   --  next hop, and jar-generated Cookie headers are selected per target URI.
   --  No production HTTP/2 execution, authentication workflows, caching, persistent
   --  cookie storage, browser-grade cookie behavior, circuit breaker, or
   --  connection pooling is introduced. Retries remain available only through
   --  explicit retry-aware APIs.

   function Execute_Decoded_Following_Redirects
     (Item          : Client;
      Request       : Http_Client.Requests.Request;
      Result        : out Decoded_Redirect_Result;
      Execution     : Execution_Options := Default_Execution_Options;
      Redirects     : Redirect_Options := Default_Redirect_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Redirects Subprogram parameter.
   --  @param Decompression Subprogram parameter.
   --  @return Subprogram result.
   --  Execute a request, follow redirects explicitly, and decode only the final
   --  response body into a non-destructive decoded view.
   --
   --  Accept-Encoding advertisement is enabled for the temporary serialized
   --  request copies when the caller did not supply Accept-Encoding. Cookie jar
   --  behavior, redirect limits, credential stripping, and method rewriting are
   --  otherwise identical to Execute_Following_Redirects. Intermediate redirect
   --  bodies are not decompressed.

   function Execute_With_Redirects
     (Item             : Client;
      Request          : Http_Client.Requests.Request;
      Result           : out Redirect_Result;
      Execution        : Execution_Options := Default_Execution_Options;
      Redirects        : Redirect_Options := Default_Redirect_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Redirects Subprogram parameter.
   --  @return Subprogram result.
   --  Execute once when Redirects.Follow_Redirects is False, or delegate to
   --  Execute_Following_Redirects when it is True.


   function Execute_With_Retry
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Result    : out Retry_Result;
      Execution : Execution_Options := Default_Execution_Options;
      Retries   : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Retries Subprogram parameter.
   --  @return Subprogram result.
   --  Execute a request with explicit bounded retry policy.
   --
   --  Plain Execute and Execute_Once never retry implicitly. This function makes
   --  retries opt-in through Retries.Enable_Retries and Retries.Maximum_Attempts.
   --  One attempt is a complete one-shot execution using the supplied execution
   --  options. Retryable complete HTTP responses are returned as the final
   --  response if the attempt limit is exhausted, rather than being hidden
   --  behind a generic error.
   --
   --  By default only idempotent methods are eligible for retry: GET, HEAD,
   --  OPTIONS, PUT, and DELETE. POST and PATCH require the explicit
   --  Allow_Non_Idempotent_Retry option, which can duplicate application-level
   --  side effects. Current request bodies are in-memory strings and therefore
   --  replayable; future non-replayable body types must be rejected before
   --  retrying.
   --
   --  Certificate verification failure, hostname verification failure, CA-store
   --  failure, invalid URI/request/header, unsupported feature, invalid proxy
   --  configuration, proxy authentication required, decompression failure, and
   --  protocol errors are not classified as retryable by the default policy.
   --  Retry delays are calculated deterministically and invoked only through the
   --  optional delay hook; this package does not perform implicit wall-clock
   --  sleeps.

   function Execute_Once_With_Retry
     (Request   : Http_Client.Requests.Request;
      Result    : out Retry_Result;
      Execution : Execution_Options := Default_Execution_Options;
      Retries   : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Retries Subprogram parameter.
   --  @return Subprogram result.
   --  Convenience wrapper around Execute_With_Retry using a temporary client.

   function Execute_With_Redirects_And_Retry
     (Item           : Client;
      Request        : Http_Client.Requests.Request;
      Result         : out Redirect_Result;
      Retry_Metadata : out Retry_Result;
      Execution      : Execution_Options := Default_Execution_Options;
      Redirects      : Redirect_Options := Default_Redirect_Options;
      Retries        : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Retry_Metadata Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Redirects Subprogram parameter.
   --  @param Retries Subprogram parameter.
   --  @return Subprogram result.
   --  Execute with explicit bounded retry policy around the redirect policy.
   --
   --  Redirect/retry chains preserve the caller's Protocol_Policy and Proxy
   --  configuration for every attempt. Forced protocol policies remain forced;
   --  a forced HTTP/2 or HTTP/3 request is not retried or redirected by silently
   --  falling back to another protocol. Cancellation stops the chain instead of
   --  being treated as a transient retryable failure.
   --
   --  One retry attempt is one complete Execute_With_Redirects call. When
   --  Redirects.Follow_Redirects is True, an attempt may consume up to
   --  Redirects.Max_Redirects hops; retries always restart from the original
   --  request. The retry and redirect bounds are independent, so loops cannot
   --  multiply without both limits applying.
   --
   --  A supplied Cookie_Jar follows the existing redirect/cookie semantics for
   --  every attempt. This means complete intermediate redirect responses may
   --  store cookies exactly as Execute_Following_Redirects already documents.
   --  The retry layer does not add a separate retry cookie staging area. Proxy routing
   --  is recomputed on each attempt from the same explicit proxy configuration;
   --  no connection state is reused.

   function Execute_Once_With_Redirects_And_Retry
     (Request        : Http_Client.Requests.Request;
      Result         : out Redirect_Result;
      Retry_Metadata : out Retry_Result;
      Execution      : Execution_Options := Default_Execution_Options;
      Redirects      : Redirect_Options := Default_Redirect_Options;
      Retries        : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Retry_Metadata Subprogram parameter.
   --  @param Execution Subprogram parameter.
   --  @param Redirects Subprogram parameter.
   --  @param Retries Subprogram parameter.
   --  @return Subprogram result.
   --  Convenience wrapper around Execute_With_Redirects_And_Retry.



   type Client_Configuration is record
      Execution            : Execution_Options := Default_Execution_Options;
      Redirects            : Redirect_Options := Default_Redirect_Options;
      Retries              : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Enable_Decompression : Boolean := True;
      Decompression        : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
      Default_Headers      : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Pooling              : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Cache                : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      HTTP3                : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      HTTP3_Backend        : Http_Client.HTTP3.Execution.Buffered_Backend_Callback := null;
      Cache_Store          : Http_Client.Cache.Cache_Store_Access := null;
      Persistent_Cache_Store :
        Http_Client.Cache.Persistent.Persistent_Store_Access := null;
      Discovery            : Http_Client.Protocol_Discovery.Discovery_Options :=
        Http_Client.Protocol_Discovery.Default_Discovery_Options;
      Proxy_Discovery      : Http_Client.Proxy_Discovery.Discovery_Options :=
        Http_Client.Proxy_Discovery.Default_Discovery_Options;
      Proxy_PAC_Script     : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;
   --  Reusable high-level client configuration.
   --
   --  @field Execution One-shot transport, TLS, cookie, proxy, size-limit,
   --         framing, and opt-in diagnostics options. Defaults preserve direct
   --         stateless execution, disabled proxy use, disabled cookies, disabled
   --         decompression advertisement, disabled retries, silent diagnostics,
   --         and verified TLS.
   --  @field Redirects Optional bounded redirect policy. Redirects are disabled
   --         by default and HTTPS-to-HTTP downgrades remain blocked by default.
   --  @field Retries Optional bounded retry policy. Retries are disabled by
   --         default and non-idempotent methods are not retried by default.
   --  @field Enable_Decompression Enables the explicit decoded final
   --         response view and Accept-Encoding advertisement through the
   --         serialized temporary request copy when the caller did not supply an
   --         Accept-Encoding header.
   --  @field Decompression Bounded decoded-body options used only when
   --         Enable_Decompression is True.
   --  @field Default_Headers Caller-configured default request headers. They
   --         are applied to high-level Client Execute/Get/Post/Put/Delete
   --         operations only when the request does not already contain that
   --         field. Request-specific headers win. Caller-configured
   --         Accept-Encoding is also treated as explicit input, so decompression
   --         advertisement will not overwrite or duplicate it.
   --         Sensitive framing, routing, credential, cookie, and hop-by-hop
   --         headers are rejected as defaults, including non-standard
   --         Proxy-Connection.
   --  @field Pooling Explicit HTTP/1.1 persistent connection reuse policy
   --         options. Disabled by default. When enabled in this client layer,
   --         the configuration is validated, synthesized Connection: close is
   --         suppressed, and clean compatible buffered HTTP/1.1 TCP/TLS
   --         handles may be retained behind the client.
   --         The policy never enables pipelining, multiplexing, HTTP/2 stream scheduling,
   --         async execution, or task pools.
   --  @field HTTP3 Explicit HTTP/3 candidate, QUIC boundary, and fallback
   --         policy. Disabled by default; the experimental HTTP/3 boundary validates the options and
   --         reports unsupported execution deterministically rather than
   --         silently using HTTP/3 or faking QUIC over TCP/TLS. When required,
   --         HTTP/3 applies only to HTTPS/QUIC-capable origins; plain HTTP
   --         requests fail deterministically instead of falling through to
   --         HTTP/1.1.
   --  @field HTTP3_Backend Optional caller-supplied production HTTP/3 backend
   --         callback. Null preserves deterministic unsupported behavior.
   --  @field Cache Explicit bounded in-memory HTTP cache policy. Disabled by
   --         default. When enabled, Cache_Store must be non-null and only the
   --         conservative buffered GET cache path is used; redirects, retries,
   --         decompression, streaming, uploads, multipart, Authorization,
   --         Cookie, Set-Cookie, and encoded representations retain their
   --         documented bypass behavior.
   --  @field Cache_Store Caller-owned mutable in-memory cache. It is not
   --         synchronized; callers sharing it between tasks must serialize
   --         access externally. Diagnostics are configured through the nested
   --         Execution.Diagnostics context and remain opt-in.
   --  @field Persistent_Cache_Store Caller-owned explicitly opened persistent
   --         cache store. When supplied without Cache_Store, the high-level
   --         buffered Execute path may use it directly for cacheable GETs under
   --         the same restrictions as Execute_With_Persistent_Cache.
   --  @field Discovery Explicit Alt-Svc and HTTPS/SVCB protocol discovery
   --         policy. Disabled by default. Discovery never bypasses configured
   --         HTTP or SOCKS proxies, never weakens TLS authority validation,
   --         never updates the HTTP response cache, and never starts hidden
   --         background DNS refresh tasks. Forced low-level protocol APIs remain
   --         unaffected.
   --  @field Proxy_Discovery Explicit PAC/WPAD proxy-discovery policy. Disabled
   --         by default. When Enabled is True and Proxy_PAC_Script is non-empty,
   --         high-level Execute evaluates the bounded PAC subset for the current
   --         request URI before network execution. Explicit proxies win unless
   --         the proxy-discovery precedence field deliberately says otherwise.
   --  @field Proxy_PAC_Script Optional caller-supplied PAC script text. The
   --         client never loads browser/system PAC locations automatically and
   --         never fetches PAC URLs from this field.

   Default_Client_Configuration : constant Client_Configuration :=
     (Execution            => Default_Execution_Options,
      Redirects            => Default_Redirect_Options,
      Retries              => Http_Client.Retry.Default_Retry_Options,
      Enable_Decompression => True,
      Decompression        => Http_Client.Decompression.Default_Decompression_Options,
      Default_Headers      => Http_Client.Headers.Empty,
      Pooling              => Http_Client.Connection_Pools.Default_Pooling_Options,
      Cache                => Http_Client.Cache.Default_Cache_Config,
      HTTP3                => Http_Client.HTTP3.Default_HTTP3_Options,
      HTTP3_Backend        => null,
      Cache_Store          => null,
      Persistent_Cache_Store => null,
      Discovery            => Http_Client.Protocol_Discovery.Default_Discovery_Options,
      Proxy_Discovery      => Http_Client.Proxy_Discovery.Default_Discovery_Options,
      Proxy_PAC_Script     => Ada.Strings.Unbounded.Null_Unbounded_String);

   Strict_Client_Configuration : constant Client_Configuration :=
     (Execution            => Strict_Execution_Options,
      Redirects            => Strict_Redirect_Options,
      Retries              => Http_Client.Retry.Default_Retry_Options,
      Enable_Decompression => False,
      Decompression        => Http_Client.Decompression.Default_Decompression_Options,
      Default_Headers      => Http_Client.Headers.Empty,
      Pooling              => Http_Client.Connection_Pools.Default_Pooling_Options,
      Cache                => Http_Client.Cache.Default_Cache_Config,
      HTTP3                => Http_Client.HTTP3.Default_HTTP3_Options,
      HTTP3_Backend        => null,
      Cache_Store          => null,
      Persistent_Cache_Store => null,
      Discovery            => Http_Client.Protocol_Discovery.Default_Discovery_Options,
      Proxy_Discovery      => Http_Client.Proxy_Discovery.Default_Discovery_Options,
      Proxy_PAC_Script     => Ada.Strings.Unbounded.Null_Unbounded_String);


   type Download_File_Mode is
     (Create_New,
      Overwrite,
      Replace_Atomically);
   --  File write policy for download-to-file convenience APIs.
   --
   --  Create_New fails when the target already exists. Overwrite writes
   --  directly to the target path. Replace_Atomically writes to a sibling
   --  temporary file and installs it only after the response body has been
   --  fully written and the stream has completed successfully.

   type File_Durability_Mode is
     (File_Durability_Default,
      File_Durability_Flush_Temp_File,
      File_Durability_Sync_Data_And_Directory);
   --  Durability policy for reusable file-write helpers. Default closes the
   --  temporary file before rename. Flush_Temp_File also flushes the text
   --  stream before close. Sync_Data_And_Directory additionally fsyncs the
   --  completed temporary/source file before rename and best-effort fsyncs
   --  the parent directory after rename where the platform supports it.

   function Available_Sibling_Path
     (Base   : String;
      Suffix : String) return String;
   --  Return an unused sibling path derived from Base and Suffix, or empty
   --  when no candidate can be found. The result is advisory; callers still
   --  need to handle races when creating or renaming files.

   function Delete_Ordinary_File_If_Present
     (Path : String) return Http_Client.Errors.Result_Status;
   --  Delete Path when it exists and is an ordinary file. Missing paths are Ok;
   --  directories and delete failures return Write_Failed.

   function Ensure_Parent_Directory
     (Path : String) return Http_Client.Errors.Result_Status;
   --  Create the parent directory for Path when needed.

   function Install_File_Atomically
     (Source_Path        : String;
      Target_Path        : String;
      Backup_Suffix      : String := ".http_client_old";
      Create_Parent_Dirs : Boolean := True;
      Durability         : File_Durability_Mode := File_Durability_Default)
      return Http_Client.Errors.Result_Status;
   --  Install Source_Path at Target_Path using a sibling backup and rollback on
   --  rename failure. Existing targets must be ordinary files. Durable mode
   --  fsyncs Source_Path before rename and best-effort fsyncs the target parent
   --  directory after the install is complete.

   function Write_Text_File_Atomically
     (Path          : String;
      Content       : String;
      Temp_Suffix   : String := ".http_client_tmp";
      Backup_Suffix : String := ".http_client_old";
      Durability    : File_Durability_Mode := File_Durability_Default)
      return Http_Client.Errors.Result_Status;
   --  Write Content to a sibling temporary file, close it, then atomically
   --  install it at Path. Temporary files are removed on failure where possible.

   Default_Max_Download_Size : constant Natural := 1024 * 1024 * 1024;
   --  Default total-size cap for download-to-file convenience APIs. This is
   --  intentionally separate from, and much larger than, buffered response
   --  limits because file downloads stream directly to disk. Set
   --  Download_Options.Max_Download_Size to 0 for an unlimited download.


   type Download_Progress_Callback is access function
     (Bytes_Written : Natural;
      Total_Bytes   : Natural) return Http_Client.Errors.Result_Status;
   --  Optional download progress callback. Bytes_Written is the final-file
   --  byte count written so far, including existing bytes for resumed
   --  downloads. Total_Bytes is the expected final size when known, or zero
   --  when unknown. Return Ok to continue or any other status to abort.

   type Download_Options is record
      Follow_Redirects      : Boolean := True;
      Max_Redirects         : Natural := 10;
      Max_Download_Size     : Natural := Default_Max_Download_Size;
      Require_Success_Status : Boolean := False;
      File_Mode             : Download_File_Mode := Replace_Atomically;
      Durability            : File_Durability_Mode := File_Durability_Default;
      Create_Parent_Dirs    : Boolean := False;
      Preserve_Partial_File : Boolean := False;
      Enable_Resume         : Boolean := False;
      Resume_If_Range       : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Expected_Size         : Natural := 0;
      Verify_SHA256         : Boolean := False;
      Expected_SHA256_Hex   : String (1 .. 64) := (others => '0');
      Progress_Callback     : Download_Progress_Callback := null;
      Progress_Interval_Bytes : Natural := 0;
      Cancellation         : Http_Client.Cancellation.Cancellation_Token_Access := null;
      Buffer_Size           : Positive := 64 * 1024;
   end record;
   --  Options for streaming a response directly to a local file.
   --
   --  @field Follow_Redirects Whether the download convenience API follows
   --         safe redirects using the same redirect rules as client execution.
   --  @field Max_Redirects Maximum redirect hops when Follow_Redirects is True.
   --  @field Max_Download_Size Maximum bytes written by the download API. The
   --         default is Default_Max_Download_Size, a high file-download cap
   --         independent of the buffered Max_Body_Size used by in-memory
   --         Execute/Get calls. Zero means no explicit download-size cap.
   --  @field File_Mode Target file creation/replacement policy.
   --  @field Durability Local filesystem durability policy. With atomic
   --         replacement, durable mode fsyncs the completed temporary file
   --         before install and best-effort fsyncs the parent directory after
   --         rename. With direct writes, durable mode fsyncs the final file.
   --  @field Create_Parent_Dirs Whether missing parent directories are created.
   --  @field Preserve_Partial_File Whether a failed download leaves the partial
   --         target or temporary file in place for inspection.
   --  @field Enable_Resume Whether GET downloads with File_Mode = Overwrite
   --         and an existing non-empty target file may request the remaining
   --         range and append to that file. The server must return a valid 206
   --         Content-Range starting at the existing file size; a 200 response
   --         falls back to a full overwrite.
   --  @field Resume_If_Range Optional If-Range validator, usually a strong
   --         ETag or Last-Modified HTTP-date, sent only for resume attempts.
   --  @field Expected_Size Expected final file size. Zero disables this
   --         integrity check. For resumed downloads this is the final size,
   --         including existing bytes.
   --  @field Verify_SHA256 Whether to verify the completed file against
   --         Expected_SHA256_Hex before accepting or installing it.
   --  @field Expected_SHA256_Hex Lowercase or uppercase hexadecimal SHA-256
   --         digest expected when Verify_SHA256 is True.
   --  @field Progress_Callback Optional callback invoked after bytes are
   --         written. Return Ok to continue, or another status to abort.
   --  @field Progress_Interval_Bytes Minimum byte delta between progress
   --         callbacks. Zero reports after every write. A final progress
   --         callback is still emitted when needed, including successful
   --         zero-byte downloads.
   --  @field Cancellation Optional cooperative cancellation token checked
   --         before creating the target and while reading response bytes.
   --  @field Buffer_Size Fixed transfer buffer used while copying stream bytes
   --         to the file; memory use is not proportional to response size.

   Default_Download_Options : constant Download_Options :=
     (Follow_Redirects      => True,
      Max_Redirects         => 10,
      Max_Download_Size     => Default_Max_Download_Size,
      Require_Success_Status => False,
      File_Mode             => Replace_Atomically,
      Durability            => File_Durability_Default,
      Create_Parent_Dirs    => False,
      Preserve_Partial_File => False,
      Enable_Resume         => False,
      Resume_If_Range       => Ada.Strings.Unbounded.Null_Unbounded_String,
      Expected_Size         => 0,
      Verify_SHA256         => False,
      Expected_SHA256_Hex   => (others => '0'),
      Progress_Callback     => null,
      Progress_Interval_Bytes => 0,
      Cancellation         => null,
      Buffer_Size           => 64 * 1024);

   type Resume_Fallback_Action is
     (Keep_Download_Result,
      Retry_Without_Resume);
   --  Action callers should take after a resumable download attempt.

   function Resume_Validator
     (ETag          : String;
      Last_Modified : String;
      ETag_Is_Weak  : Boolean;
      Resume_Safe   : Boolean := True)
      return Ada.Strings.Unbounded.Unbounded_String;
   --  Return the best If-Range validator for a resumable download. Strong
   --  ETag is preferred, then Last-Modified. Empty is returned when resume is
   --  not safe or no suitable validator is available.

   procedure Configure_Resumable_Download
     (Options             : in out Download_Options;
      Resume_Mode         : Boolean;
      Can_Resume          : Boolean;
      Resume_If_Range     : Ada.Strings.Unbounded.Unbounded_String;
      Partial_Size        : Natural;
      Remaining_Max_Bytes : Natural);
   --  Apply common resumable-download policy to Options. Resume_Mode selects
   --  overwrite plus partial preservation; non-resume mode selects atomic
   --  replacement. Remaining_Max_Bytes is a new-transfer budget; when resuming
   --  it is converted to the final-size cap expected by Download_To_File.

   procedure Configure_Full_Retry_After_Resume_Failure
     (Options             : in out Download_Options;
      Remaining_Max_Bytes : Natural);
   --  Reset Options for a full non-resumed retry after a stale partial/range
   --  failure.

   type Download_Result is record
      Status        : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Internal_Error;
      Response      : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Final_URI     : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      HTTP_Status_Code    : Natural := 0;
      Expected_Final_Size : Natural := 0;
      Redirect_Count      : Natural := 0;
      Retry_Attempt_Count : Natural := 0;
      Resumed             : Boolean := False;
      Resume_Offset       : Natural := 0;
      Bytes_Written       : Natural := 0;
      Final_Size          : Natural := 0;
   end record;
   --  Result for download-to-file convenience APIs. Response contains headers,
   --  status code, and other metadata for the final response; its body is empty
   --  because the body is streamed to the target file. HTTP_Status_Code is the
   --  final response status code, or zero when no HTTP response was received.
   --  Expected_Final_Size is the final file size implied by Content-Length plus
   --  any resume offset, by resumed Content-Range, or by Expected_Size when
   --  configured, or zero when unknown.
   --  Resumed is True only when a range request was accepted with a valid 206
   --  response; Resume_Offset is the existing byte count used for that resume.
   --  Bytes_Written reports bytes written by this call. Final_Size reports the
   --  final file size, including existing bytes for successful or partially
   --  written resumed downloads.

function Resume_Fallback_For
     (Status      : Http_Client.Errors.Result_Status;
      Result      : Download_Result;
      Resume_Mode : Boolean) return Resume_Fallback_Action;
   --  Return Retry_Without_Resume for retryable resume-specific outcomes such
   --  as 416 after a failed resumable attempt.

   type Client_Result is record
      Status              : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Internal_Error;
      Response            : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Decoded_Response    : Http_Client.Decompression.Decoded_Response :=
        Http_Client.Decompression.Default_Decoded_Response;
      Final_URI           : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirect_Count      : Natural := 0;
      Retry_Attempt_Count : Natural := 0;
      Retry_Exhausted     : Boolean := False;
      Used_Decoded_View   : Boolean := False;
      Cache_Metadata      : Http_Client.Cache.Cache_Metadata :=
        (Source             => Http_Client.Cache.Cache_Bypassed,
         Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
         Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
         Age_Seconds        => 0,
         Revalidation_Count => 0,
         Entry_Count        => 0,
         Stored_Body_Bytes  => 0);
   end record;
   --  High-level client execution result.
   --
   --  Complete HTTP responses are exposed even when the status code is an HTTP
   --  error. Status reports operation-level errors such as invalid
   --  configuration, connection failure, TLS failure, redirect failure, retry
   --  exhaustion, parse failure, or decompression failure, or cache revalidation failure. Response contains
   --  the parsed final HTTP response when one was received. Decoded_Response is
   --  meaningful only when Used_Decoded_View is True. Final_URI and
   --  Redirect_Count describe the redirect outcome. Retry_Attempt_Count and
   --  Retry_Exhausted are populated from retry-aware execution. Cache_Metadata
   --  is populated by cache-aware high-level execution and remains Cache_Bypassed otherwise.
   --  Retry_Attempt_Count remains 0 for failures that happen before any
   --  execution attempt, such as an uninitialized client or invalid URL, so
   --  high-level callers do not lose the bounded retry metadata exposed by
   --  the lower retry API.

   function Validate
     (Configuration : Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Configuration Subprogram parameter.
   --  @return Subprogram result.
   --  Validate a high-level configuration without performing network I/O.
   --
   --  Invalid limits, header/body sublimits larger than their enclosing
   --  response/header limits, contradictory TLS options, zero redirect limits
   --  when redirect following is enabled, zero decoded-body limits when
   --  decompression is enabled, and forbidden default headers are rejected
   --  deterministically. Validation also inspects the public Default_Headers
   --  field directly, so callers cannot bypass broad-header restrictions by
   --  editing the record instead of using Set_Default_Header.

   function Initialize
     (Item          : in out Client;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Configuration Subprogram parameter.
   --  @return Subprogram result.
   --  Initialize Item with Configuration after validation.
   --
   --  Multiple Client values may exist concurrently with different
   --  configurations. Low-level execution remains one complete TCP/TLS request
   --  lifecycle per request; configured high-level pooling validates the explicit
   --  pool policy and compatibility limits.

   function Configure
     (Item          : in out Client;
      Configuration : Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Configuration Subprogram parameter.
   --  @return Subprogram result.
   --  Replace Item's reusable high-level configuration after validation.
   --  A failed Configure call leaves Item's previous configuration and
   --  initialization state unchanged.

   function Configuration (Item : Client) return Client_Configuration;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return a copy of Item's current high-level configuration.
   --
   --  For a client that was left uninitialized by a failed Initialize call,
   --  this returns the last stored configuration value; it does not imply that
   --  Execute will accept the client. Failed Initialize does not install an
   --  invalid configuration. Failed Configure calls preserve the previous
   --  configuration and previous initialization state.

   function Accept_Alt_Svc_Header
     (Item                         : in out Client;
      Origin                       : Http_Client.URI.URI_Reference;
      Header                       : String;
      Received_At                  : Ada.Calendar.Time;
      From_Verified_HTTPS_Response : Boolean := False)
      return Http_Client.Errors.Result_Status
   with Pre => Http_Client.URI.Is_Parsed (Origin);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Origin Subprogram parameter.
   --  @param Header Subprogram parameter.
   --  @param Received_At Subprogram parameter.
   --  @param From_Verified_HTTPS_Response Subprogram parameter.
   --  @return Subprogram result.
   --  Explicitly feed a network Alt-Svc response header into Item's bounded
   --  discovery cache using Item's configured discovery policy. This operation
   --  is a no-op when Alt-Svc discovery or HTTP/3 discovery is disabled. It
   --  accepts metadata only for successfully verified HTTPS responses and does
   --  not touch HTTP response caches or persistent cache storage.

   procedure Clear_Discovery_Cache (Item : in out Client);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  Clear Item's bounded in-memory Alt-Svc discovery cache. This operation
   --  does not touch in-memory, persistent, or encrypted HTTP response caches.
   --  It is deterministic and creates no background work.

   function Set_Default_Header
     (Configuration : in out Client_Configuration;
      Name          : String;
      Value         : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Configuration Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Add or replace a non-sensitive default header in Configuration.
   --  Request-specific headers override defaults during high-level execution.
   --  This operation rejects Authorization, Proxy-Authorization, Cookie, Host,
   --  Content-Length, Transfer-Encoding, Connection, Proxy-Connection, and
   --  related hop-by-hop fields as broad defaults.

   function Remove_Default_Header
     (Configuration : in out Client_Configuration;
      Name          : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Configuration Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Remove a default header from Configuration.

   function Execute
     (Item    : Client;
      Request : Http_Client.Requests.Request;
      Result  : out Client_Result) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Execute Request through Item's reusable configuration.
   --
   --  This operation composes existing lower-level execution, redirect,
   --  cookie, decompression, proxy, retry, TLS, and authentication-helper
   --  behavior. Origin Authorization remains request-specific: this API will
   --  send an Authorization header already present on Request, but client
   --  configuration deliberately has no broad origin-credential default.
   --  When Pooling.Enabled is True the client validates the pooling
   --  policy, does not synthesize Connection: close, and may reuse a clean
   --  HTTP/1.1 TCP/TLS handle retained behind Item. Reuse is transport-only:
   --  requests, headers, cookies, Authorization, Proxy-Authorization, and Git
   --  headers are rebuilt for each exchange. Connection: close, close-delimited framing, early
   --  stream close, failed streams, stale connections, incompatible
   --  proxy/TLS/origin keys, and pool limits all prevent reuse by policy.
   --  Proxy credentials are taken only from the configured proxy metadata and
   --  are emitted only on proxy-facing requests. It does not introduce automatic
   --  challenge negotiation, pipelining, hidden global
   --  diagnostics, hidden global defaults, or implicit async scheduling.


   function Execute_Stream
     (Item    : Client;
      Request : Http_Client.Requests.Request;
      Stream  : in out Http_Client.Response_Streams.Streaming_Response)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Execute Request through Item and return a streaming response body.
   --
   --  Default headers, TLS defaults, proxy configuration, cookie jar handling,
   --  and size limits are taken from the client configuration. Buffered
   --  Execute/Get/Post/Put/Delete remain unchanged and never return a live
   --  connection. When configured redirect following is enabled, intermediate
   --  redirect streams are closed and only the final response stream is
   --  returned. When Enable_Decompression is configured, streaming reads return
   --  decoded entity bytes using bounded Response_Streams decompression; when
   --  disabled, callers receive raw content-encoded response body bytes.
   --  Retry-enabled streaming retries only failures that
   --  occur before response headers are returned; once a stream is returned,
   --  mid-body failures are reported to the caller and are never retried.
   --  The pooling policy defines how a later transport-attached stream
   --  may own a checked-out connection until end-of-body or Close. A stream read
   --  fully may return the connection to the pool; an early close, malformed
   --  body, timeout, read failure, or connection-close-delimited response
   --  discards it. This release keeps streaming transport handles outside the
   --  real reuse pool; only buffered HTTP/1.1 execution returns clean handles.

   function Get
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Build and execute a GET request for URL.
   --
   --  The client must be initialized before convenience request construction is
   --  attempted. An uninitialized client returns Client_Not_Initialized and
   --  leaves Result with neutral metadata, without parsing URL or opening a
   --  connection.

      function Get
     (URL           : String;
      Result        : out Client_Result;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  Perform a complete GET request using a temporary client initialized
   --  with Configuration.
   --
   --  This is the convenience form for simple downloads. It applies the same
   --  redirect, decompression, retry, proxy, pooling, cache, and protocol
   --  discovery policy as a Client initialized with Configuration, then stores
   --  the final response in Result.
   --
   --  With Default_Client_Configuration, safe redirects and response
   --  decompression are enabled. Use Strict_Client_Configuration when exact
   --  no-redirect/no-transform behavior is required.
   --
   --  Result.Response contains the final HTTP response after any followed
   --  redirects. Result.Redirect_Count records the number of redirects that
   --  were followed. Use Response_Text to retrieve the ordinary caller-facing
   --  body text, decoded when a decoded response view is available.
   --
   --  Returns Ok on success. On failure, returns the deterministic status
   --  describing initialization, connection, redirect, decompression, retry, or
   --  response-processing failure.

   function Head
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status;
   --  Build and execute a HEAD request for URL.
   --
   --  The response contains status and headers, but no response body is read or
   --  returned. Uninitialized-client handling is identical to Get.

   function Head
     (URL           : String;
      Result        : out Client_Result;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  Perform a complete HEAD request using a temporary client initialized
   --  with Configuration.

   function Execute_To_File
     (Item    : in out Client;
      Request : Http_Client.Requests.Request;
      Path    : String;
      Result  : out Download_Result;
      Options : Download_Options := Default_Download_Options)
      return Http_Client.Errors.Result_Status;
   --  Execute Request and stream the final response body directly to Path.
   --
   --  The implementation uses Execute_Stream/Response_Streams and never stores
   --  the complete response body in memory. Buffered Max_Body_Size does not
   --  cap this API; Options.Max_Download_Size is the separate file-download
   --  byte limit and defaults to Default_Max_Download_Size. Redirect handling
   --  is controlled by Options and preserves the
   --  same downgrade and method-rewrite safety rules as the client.

   function Download_To_File
     (Item    : in out Client;
      URL     : String;
      Path    : String;
      Result  : out Download_Result;
      Options : Download_Options := Default_Download_Options)
      return Http_Client.Errors.Result_Status;
   --  Build a GET request for URL and stream the response body directly to Path.

   function Download_To_File
     (URL           : String;
      Path          : String;
      Result        : out Download_Result;
      Options       : Download_Options := Default_Download_Options;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status;
   --  Convenience form using a temporary client initialized with Configuration.

   function Delete
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Build and execute a DELETE request for URL.
   --
   --  Uninitialized-client handling is identical to Get.

   function Put
     (Item         : Client;
      URL          : String;
      Payload      : String;
      Result       : out Client_Result;
      Content_Type : String := "") return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Content_Type Subprogram parameter.
   --  @return Subprogram result.
   --  Build and execute a PUT request with an in-memory payload.
   --
   --  Uninitialized-client handling is identical to Get.

   function Post
     (Item         : Client;
      URL          : String;
      Payload      : String;
      Result       : out Client_Result;
      Content_Type : String := "") return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Content_Type Subprogram parameter.
   --  @return Subprogram result.
   --  Build and execute a POST request with an in-memory payload.
   --
   --  Uninitialized-client handling is identical to Get.

   function Response_Text (Result : Client_Result) return String;
   --  Return the ordinary caller-facing response body text.
   --
   --  If Result contains a decoded response view, this returns the decoded body.
   --  Otherwise, it returns the final response body exactly as stored in
   --  Result.Response.

   function Final_URL (Result : Client_Result) return String;
   --  Return the final URL as printable text after any followed redirects.

private
   type Pooled_Connection_Kind is (Pooled_TCP, Pooled_TLS);

   type TCP_Connection_Access is access Http_Client.Transports.TCP.Connection;
   type TLS_Connection_Access is access Http_Client.Transports.TLS.Connection;

   type Pooled_Connection is record
      Key   : Http_Client.Connection_Pools.Pool_Key;
      Token : Http_Client.Connection_Pools.Pool_Token;
      Kind  : Pooled_Connection_Kind := Pooled_TCP;
      TCP   : TCP_Connection_Access := null;
      TLS   : TLS_Connection_Access := null;
      Created_At    : Ada.Calendar.Time := Ada.Calendar.Clock;
      Last_Used_At  : Ada.Calendar.Time := Ada.Calendar.Clock;
      Request_Count : Natural := 0;
   end record;

   package Pooled_Connection_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Pooled_Connection);

   type Client_State is record
      Pool    : Http_Client.Connection_Pools.Connection_Pool;
      Entries : Pooled_Connection_Vectors.Vector;
   end record;

   type Client_State_Access is access Client_State;

   type Client is tagged record
      Initialized : Boolean := False;
      Config      : Client_Configuration := Default_Client_Configuration;
      Discovery_Cache : Http_Client.Protocol_Discovery.Discovery_Cache;
      State      : Client_State_Access := null;
   end record;

end Http_Client.Clients;
