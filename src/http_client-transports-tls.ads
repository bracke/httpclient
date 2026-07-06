with Ada.Finalization;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.HTTP2;
with Http_Client.Proxies;
with Http_Client.Transports.TCP;
with Http_Client.TLS.Client_Certificates;
with Http_Client.URI;

private with System;

package Http_Client.Transports.TLS is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  OpenSSL-backed TLS transport for HTTPS.
   --
   --  This package owns one TLS connection per Connection object. It hides all
   --  OpenSSL handles behind a private Ada type, initializes OpenSSL, creates
   --  the TLS context, requests a TLS 1.2-or-newer protocol floor where the
   --  OpenSSL API supports it, performs the TLS handshake,
   --  verifies the certificate chain and server identity by default, writes
   --  caller-supplied bytes exactly, returns decrypted bytes exactly, and
   --  closes deterministically. It does not parse HTTP, follow redirects,
   --  manage cookies, decompress payloads, execute HTTP/2, tunnel through
   --  proxies, retry requests, stream application bodies, or pool connections.

   type TLS_Options is record
      Timeouts : Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
      Disable_Certificate_Verification : Boolean := False;
      CA_File : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      CA_Directory : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Send_SNI : Boolean := True;
      HTTP2 : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Client_Certificate : Http_Client.TLS.Client_Certificates.Client_Certificate :=
        Http_Client.TLS.Client_Certificates.No_Client_Certificate;
   end record;
   --  TLS connection options.
   --
   --  @field Timeouts Timeout intent mirrored from the plain TCP transport.
   --         The OpenSSL bridge applies configured read/write timeouts to the
   --         underlying TLS socket where the platform exposes socket-level
   --         timeouts. Zero keeps normal blocking behavior.
   --  @field Disable_Certificate_Verification Unsafe development/test-only
   --         option. The default is False, so certificate-chain and host-name
   --         verification are enabled.
   --  @field CA_File Optional PEM CA bundle path. When provided, failure to
   --         load it returns CA_Store_Failed instead of silently falling back to
   --         system trust. Embedded NUL characters are rejected before calling
   --         C. When empty with no CA_Directory, OpenSSL default trust
   --         locations are used.
   --  @field CA_Directory Optional hashed CA directory path. When provided,
   --         failure to load it returns CA_Store_Failed. Embedded NUL characters
   --         are rejected before calling C. When empty with no CA_File, OpenSSL
   --         default trust locations are used.
   --  @field Send_SNI Send Server Name Indication for suitable DNS names.
   --         IPv4 literals omit SNI.
   --  @field HTTP2 Conservative ALPN/HTTP/2 policy. Defaults disable h2 so
   --         default HTTPS behavior is unchanged.
   --  @field Client_Certificate Optional explicit mutual-TLS client
   --         certificate credential. Disabled by default. A configured client
   --         certificate is loaded before the handshake and checked against
   --         its private key before any HTTP bytes are sent. It does not
   --         disable server certificate verification, hostname verification,
   --         SNI, ALPN, or TLS version policy. This package supports caller-
   --         supplied PEM certificate/private-key files only. A PEM certificate
   --         file may include intermediate chain certificates accepted by
   --         OpenSSL; no OS keychain, hardware token, automatic discovery,
   --         PKCS#12, or renegotiation-
   --         based client authentication is implemented.

   Default_TLS_Options : constant TLS_Options :=
     (Timeouts => Http_Client.Transports.TCP.Default_Timeouts,
      Disable_Certificate_Verification => False,
      CA_File => Ada.Strings.Unbounded.Null_Unbounded_String,
      CA_Directory => Ada.Strings.Unbounded.Null_Unbounded_String,
      Send_SNI => True,
      HTTP2 => Http_Client.HTTP2.Default_HTTP2_Options,
      Client_Certificate =>
        Http_Client.TLS.Client_Certificates.No_Client_Certificate);
   --  Default HTTPS settings: verification enabled, OpenSSL default trust
   --  paths, SNI enabled for DNS names, HTTP/2 disabled for ALPN, no client
   --  certificate configured, and blocking timeout behavior unless callers
   --  configure explicit read/write timeout values.


   function Validate_Options
     (Options : TLS_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate a TLS_Options record without opening a network connection.
   --
   --  Returns Ok for internally consistent options, CA_Store_Failed when
   --  CA_File or CA_Directory contains an embedded NUL, and Invalid_Request
   --  when Disable_Certificate_Verification is True while explicit CA
   --  locations are also supplied. Explicit CA locations are meaningful only
   --  for the default verifying mode; rejecting the mixed configuration avoids
   --  silently ignoring caller-supplied trust settings. Client-certificate
   --  configuration is also checked for explicit paths, NUL-free strings, and
   --  scope validity. PEM syntax, unsupported key formats, encrypted-key
   --  passphrase validity, and certificate/private-key consistency are checked
   --  by OpenSSL during Open before any HTTP request bytes are sent.
   --  Missing or wrong encrypted-key passphrases are reported with the
   --  dedicated client-key passphrase statuses when OpenSSL exposes a
   --  recognizable reason.

   type Connection is new Ada.Finalization.Limited_Controlled with private;
   --  Owned TLS connection.
   --
   --  A Connection closes its OpenSSL connection and context during
   --  finalization if still open. Calling Close on an already closed value is
   --  safe.

   overriding procedure Finalize (Item : in out Connection);
   --  GNATdoc contract.
   --  @param Item TLS connection being finalized.
   --  Close any still-open TLS connection owned by Item.

   function Open
     (Item    : in out Connection;
      Host    : String;
      Port    : Http_Client.URI.TCP_Port;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Open a direct TLS connection to Host:Port and perform the handshake.
   --
   --  Host must be a conservative DNS name or IPv4 literal. Embedded NUL,
   --  spaces, invalid labels, oversized labels, oversized host names, and an
   --  empty host are rejected before calling C. The C bridge also defensively
   --  rejects oversized host strings and target-address formatting overflow.
   --  Open first closes any
   --  connection already owned by Item, so failed opens never leave a stale
   --  TLS session attached to the same object. A configured client certificate
   --  must match this HTTPS origin or Open returns
   --  TLS_Client_Certificate_Scope_Mismatch before opening a socket or starting
   --  a TLS handshake.
   --  Certificate verification and hostname/IP-address verification are
   --  enabled by default. SNI is sent for DNS-style host names when Send_SNI is
   --  True. After a successful handshake, the selected ALPN protocol is
   --  checked against Options.HTTP2; incompatible selections close the
   --  connection and return ALPN_Negotiation_Failed. OpenSSL initialization
   --  or protocol-floor setup failure returns Internal_Error before the
   --  connection is marked open. Use Open_Through_HTTP_Proxy for HTTPS over an
   --  explicit HTTP CONNECT proxy.


   function Open_Through_HTTP_Proxy
     (Item                : in out Connection;
      Host                : String;
      Port                : Http_Client.URI.TCP_Port;
      Proxy_Host          : String;
      Proxy_Port          : Http_Client.URI.TCP_Port;
      Proxy_Authorization : String := "";
      Options             : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Host Origin TLS host name. Used for CONNECT, SNI, and
   --         hostname/IP-address verification.
   --  @param Port Origin TLS port. Used in the CONNECT authority.
   --  @param Proxy_Host HTTP proxy host.
   --  @param Proxy_Port HTTP proxy port.
   --  @param Proxy_Authorization Optional Proxy-Authorization field value sent
   --         only on the CONNECT request to the proxy. Pass the empty string
   --         when no proxy credentials are configured.
   --  @param Options TLS options for the origin TLS server.
   --  @return Ok on a verified TLS connection through the proxy tunnel,
   --          Proxy_Connection_Failed when the proxy TCP connection cannot be
   --          opened, Proxy_Authentication_Required for a 407 CONNECT response,
   --          Proxy_Tunnel_Failed for other non-2xx or malformed CONNECT
   --          responses, or the same deterministic TLS statuses as Open for
   --          origin TLS handshake and verification failures.
   --
   --  This operation sends an HTTP/1.1 CONNECT request to Proxy_Host:Proxy_Port
   --  and starts TLS only after the proxy returns a 2xx response. It never sends
   --  origin request headers, cookies, Authorization, request bodies, or client
   --  certificates to the proxy. A configured mutual-TLS client certificate is
   --  loaded only into the origin TLS handshake after CONNECT succeeds. Closing
   --  an already-open Item before starting is deterministic; failed CONNECT or
   --  TLS handshakes leave Item closed.

   function Open_Through_SOCKS_Proxy
     (Item    : in out Connection;
      Host    : String;
      Port    : Http_Client.URI.TCP_Port;
      Proxy   : Http_Client.Proxies.Proxy_Config;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Host Origin TLS host name. Used for the SOCKS CONNECT target,
   --         SNI, and hostname/IP-address verification.
   --  @param Port Origin TLS port.
   --  @param Proxy SOCKS5 proxy configuration. HTTP proxy values are rejected
   --         with Invalid_SOCKS_Proxy.
   --  @param Options TLS options for the origin TLS server.
   --  @return Ok on a verified TLS connection through the SOCKS5 tunnel,
   --          Proxy_Connection_Failed when the proxy TCP connection cannot be
   --          opened, SOCKS_* for deterministic SOCKS negotiation failures,
   --          or the same deterministic TLS statuses as Open for origin TLS
   --          handshake and verification failures.
   --
   --  This operation connects to the configured SOCKS5 proxy, performs the
   --  SOCKS CONNECT negotiation first, and starts TLS only after the tunnel is
   --  established. SOCKS username/password credentials are used only in the
   --  SOCKS negotiation. Origin request headers, cookies, Authorization,
   --  request bodies, and mutual-TLS client certificates are sent only inside
   --  the TLS tunnel after SOCKS succeeds. SOCKS UDP ASSOCIATE, BIND, SOCKS4,
   --  and SOCKS4a are unsupported. Request trailers, when used, are serialized
   --  only after the HTTP request is inside the established TLS tunnel.

   function Open_URI
     (Item    : in out Connection;
      URI     : Http_Client.URI.URI_Reference;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Open a TLS connection for a parsed https URI.
   --
   --  http URIs return Unsupported_Feature; this transport never downgrades or
   --  sends HTTPS requests over cleartext. Invalid or unsupported URI inputs
   --  close any connection already owned by Item before returning.

   function Is_Open (Item : Connection) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item currently owns an open TLS connection.

   function Write_All
     (Item : in out Connection;
      Data : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Data Subprogram parameter.
   --  @return Subprogram result.
   --  Encrypt and write every byte in Data exactly as supplied.
   --
   --  Large Ada strings are split into bounded bridge calls. The C bridge loops
   --  for partial TLS writes and blocking OpenSSL retry conditions. If a
   --  delayed TLS alert shows that the peer rejected the configured client
   --  certificate, the operation returns TLS_Client_Certificate_Rejected
   --  instead of an undifferentiated write failure where OpenSSL exposes that
   --  alert reason.

   function Read_Some
     (Item   : in out Connection;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;

   function Read_Some_With_Timeout
     (Item       : in out Connection;
      Buffer     : out String;
      Count      : out Natural;
      Timeout_MS : Http_Client.Transports.TCP.Timeout_Milliseconds)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Count Subprogram parameter.
   --  @return Subprogram result.
   --  Read up to Buffer'Length decrypted bytes from the TLS stream.
   --
   --  This operation does not parse HTTP or decode transfer/content encodings.
   --  If a delayed TLS alert shows that the peer rejected the configured
   --  client certificate, the operation returns
   --  TLS_Client_Certificate_Rejected instead of an undifferentiated read
   --  failure where OpenSSL exposes that alert reason.

   --  Read_Some_With_Timeout performs one read using Timeout_MS as a temporary
   --  read timeout for this call. Timeout_MS = 0 preserves the connection's
   --  configured blocking behavior. The connection's original timeout setting
   --  is restored before the function returns.

   function Close
     (Item : in out Connection) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Shutdown and free the OpenSSL connection if open. Closing an already
   --  closed connection returns Ok.

   function Verification_Enabled_By_Default return Boolean;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return True. Provided for deterministic tests of the default TLS policy.

   function Selected_ALPN (Item : Connection) return Http_Client.HTTP2.Selected_Protocol;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized ALPN protocol selected by the completed TLS
   --  handshake. A closed connection, a server that selected no ALPN, or a
   --  bridge that cannot expose ALPN returns Protocol_None.

   function TLS_Version (Item : Connection) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the negotiated TLS protocol version reported by the backend after
   --  a completed handshake, such as "TLSv1.3" or "TLSv1.2". A closed
   --  connection or backend without metadata support returns the empty string.

   function Cipher_Name (Item : Connection) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the negotiated TLS cipher-suite name reported by the backend after
   --  a completed handshake. A closed connection or backend without metadata
   --  support returns the empty string.

private
   type Connection is new Ada.Finalization.Limited_Controlled with record
      Handle : System.Address := System.Null_Address;
      Opened : Boolean := False;
   end record;

end Http_Client.Transports.TLS;
