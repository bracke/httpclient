with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Transports.TCP;
with Http_Client.URI;

package Http_Client.Transports.SOCKS is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  SOCKS tunnel establishment above the raw TCP transport.
   --
   --  This package opens a TCP connection to a caller-configured SOCKS5 proxy,
   --  performs a strict bounded CONNECT negotiation, and leaves the supplied
   --  TCP connection positioned as a raw byte tunnel to the origin. Higher
   --  layers remain responsible for HTTP/1.1 serialization, TLS handshakes,
   --  HTTP/2, redirects, retries, cookies, caching, upload/streaming, pooling,
   --  and diagnostics. SOCKS UDP ASSOCIATE and BIND are unsupported.

   function Open_Tunnel
     (Connection  : in out Http_Client.Transports.TCP.Connection;
      Proxy       : Http_Client.Proxies.Proxy_Config;
      Target_Host   : String;
      Target_Port   : Http_Client.URI.TCP_Port;
      Timeouts      : Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
      Diagnostics   : Http_Client.Diagnostics.Context_Access := null;
      Request_ID    : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID : Http_Client.Diagnostics.Diagnostic_ID := 0)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Proxy Subprogram parameter.
   --  @param Target_Host Subprogram parameter.
   --  @param Target_Port Subprogram parameter.
   --  @param Timeouts Subprogram parameter.
   --  Open a SOCKS5 CONNECT tunnel to Target_Host:Target_Port.
   --
   --  @param Diagnostics Optional diagnostics context. When supplied, structural
   --         SOCKS negotiation events are emitted without usernames, passwords,
   --         target hostnames, request headers, cookies, bodies, or TLS material.
   --  @param Request_ID Existing request diagnostic correlation id.
   --  @param Connection_ID Existing connection diagnostic correlation id.
   --  @return Ok on success; Invalid_SOCKS_Proxy for invalid proxy mode;
   --          Proxy_Connection_Failed for failures connecting to the proxy;
   --          SOCKS_* statuses for deterministic negotiation failures.

end Http_Client.Transports.SOCKS;
