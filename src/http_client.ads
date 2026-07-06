package Http_Client
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   pragma Pure;

   --  Root namespace for the Http_Client library.
   --
   --  This package is the stable entry point for the 1.0 API surface. The
   --  library provides explicit Ada APIs for URI parsing, request and header
   --  modeling, HTTP/1.1 serialization/execution, HTTPS/TLS via OpenSSL,
   --  bounded response parsing/framing, opt-in redirects, cookies,
   --  decompression, HTTP and SOCKS proxy configuration, optional explicit
   --  PAC/WPAD proxy-discovery helpers, bounded retries,
   --  Basic/Bearer/Digest authentication helpers, high-level client
   --  configuration, response streaming, fixed-length upload streaming,
   --  multipart/form-data bodies, in-memory and persistent caches, encrypted
   --  persistent cache storage, structured diagnostics, HTTP/2 including HPACK
   --  foundations, multiplexing, streaming/upload support, client-certificate
   --  TLS authentication, bounded async/task integration, security/fuzz
   --  hardening, and explicit Alt-Svc plus HTTPS/SVCB protocol discovery when
   --  enabled by caller policy.
   --
   --  HTTP/3 and QUIC packages are present as explicitly experimental
   --  protocol and backend boundaries. QUIC-backed HTTP/3 execution is used
   --  only when HTTP/3 is explicitly enabled and a configured backend reports
   --  support; unsupported builds remain disabled rather than falling back
   --  after unsafe transmission.
   --
   --  Security-sensitive and browser-like behavior remains opt-in and explicit:
   --  TLS verification is enabled by default; redirects, retries, cookies,
   --  decompression, caches, persistent caches, encrypted caches, proxies,
   --  SOCKS, PAC/WPAD discovery helpers, async execution, and HTTP/3 candidates
   --  are disabled until configured. The library does not implement browser
   --  profiles, service workers, preload behavior, automatic login flows,
   --  OAuth/OIDC/SAML, NTLM/Negotiate/Kerberos, OS credential stores,
   --  password managers, automatic browser/system proxy discovery, SOCKS UDP/BIND, MASQUE,
   --  CONNECT-UDP, service workers, preload behavior, Tor control behavior,
   --  hidden Alt-Svc/HTTPS-SVCB learning, or hidden global networking policy.

   Version : constant String := "1.0.0";
end Http_Client;
