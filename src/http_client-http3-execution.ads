with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.Requests;
with Http_Client.Responses;

package Http_Client.HTTP3.Execution is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  QUIC-backed HTTP/3 buffered execution boundary.
   --
   --  HTTP/3 execution is explicit and disabled by default. This package owns
   --  the protocol handoff from an already-validated request to the QUIC/HTTP/3
   --  stack. It never sends HTTP/3 frames over TCP/TLS and never bypasses
   --  configured HTTP or SOCKS proxies. When no production QUIC backend is
   --  configured, calls fail deterministically before request bytes are sent.
   --
   --  The initial supported public shape is buffered request/response
   --  execution. Alt-Svc and HTTPS/SVCB selection may supply an explicit
   --  alternative UDP endpoint, but this package still enforces proxy rejection,
   --  original-origin TLS authority requirements, disabled 0-RTT, and the
   --  configured QUIC backend boundary. Live QUIC-backed public response streaming, upload
   --  streaming, server push, MASQUE, CONNECT-UDP, and HTTP/3 through HTTP/SOCKS
   --  proxies remain outside this package's implemented scope. The public
   --  Response_Streams package can expose this bounded HTTP/3 execution result
   --  through the common pull API when an explicit HTTP/3 streaming policy is
   --  selected and the QUIC backend accepts the request.

   type Buffered_Backend_Callback is access function
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status;
   --  Caller-supplied production HTTP/3 backend. The callback receives an
   --  already validated HTTPS request, HTTP/3-mapped request fields, selected
   --  UDP endpoint, and bounded response-body limit. It owns QUIC/TLS 1.3
   --  handshake, HTTP/3 SETTINGS/QPACK/stream I/O, response validation, and
   --  status mapping. Null preserves the built-in unsupported boundary.
   function Execute_Buffered
     (Request                       : Http_Client.Requests.Request;
      Options                       : Http_Client.HTTP3.HTTP3_Options;
      Response                      : out Http_Client.Responses.Response;
      Proxy_Configured              : Boolean := False;
      SOCKS_Configured              : Boolean := False;
      Client_Certificate_Configured : Boolean := False;
      Alternative_Host              : String := "";
      Alternative_Port              : Natural := 0;
      Requires_Origin_TLS_Authority : Boolean := True;
      Max_Body_Size                 : Natural := 16_777_216;
      Diagnostics                   : Http_Client.Diagnostics.Context_Access := null;
      Request_ID                    : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID                 : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Backend                       : Buffered_Backend_Callback := null)
      return Http_Client.Errors.Result_Status;
   --  Execute one bounded HTTP/3 request over a QUIC backend.
   --
   --  @param Request Valid HTTPS request. Non-HTTPS requests are rejected.
   --  @param Options Explicit HTTP/3 and QUIC options.
   --  @param Response Buffered response on Ok; default response on failure.
   --  @param Proxy_Configured True when an HTTP proxy is configured.
   --  @param SOCKS_Configured True when a SOCKS proxy is configured.
   --  @param Client_Certificate_Configured True when this origin would use a
   --         client certificate and the configured QUIC backend cannot support
   --         it safely.
   --  @param Alternative_Host Optional Alt-Svc or HTTPS/SVCB endpoint host.
   --         When supplied, TLS authority verification still belongs to the
   --         original request origin. This parameter does not permit proxy
   --         bypass or cross-origin credential scoping.
   --  @param Alternative_Port Optional Alt-Svc or HTTPS/SVCB endpoint port. A
   --         zero value uses the origin effective port.
   --  @param Requires_Origin_TLS_Authority Must remain True for discovered
   --         alternatives in this phase; False is rejected conservatively.
   --  @param Max_Body_Size Maximum buffered response body bytes.
   --  @param Diagnostics Optional caller-owned diagnostics context.
   --  @param Request_ID Optional diagnostics correlation identifier.
   --  @param Connection_ID Optional diagnostics correlation identifier.
   --  @param Backend Optional production HTTP/3 backend callback.
   --  Streaming upload producers are rejected before UDP/QUIC network I/O;
   --  empty and buffered in-memory bodies are the only accepted body modes at
   --  this boundary.
   --  @return Ok for completed HTTP/3 execution; otherwise a deterministic
   --          HTTP3_*, QUIC_*, TLS_*, validation, or configuration status before
   --          unsafe fallback can occur.

end Http_Client.HTTP3.Execution;
