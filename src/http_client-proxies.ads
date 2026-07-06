with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.URI;

package Http_Client.Proxies is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit HTTP and SOCKS proxy configuration.
   --
   --  Proxy support is opt-in. This package does not inspect environment
   --  variables, operating-system settings, PAC files, WPAD, credential stores,
   --  or browser configuration. HTTP proxies and SOCKS5 proxies are distinct
   --  routing modes. SOCKS support is TCP CONNECT tunneling only; it does not
   --  implement UDP ASSOCIATE, BIND, Tor control behavior, anonymity guarantees,
   --  browser profile integration, or automatic proxy discovery.

   type Proxy_Kind is (No_Proxy, HTTP_Proxy, SOCKS5_Proxy);
   --  Supported proxy kinds. No_Proxy preserves direct execution behavior.

   type SOCKS5_Authentication_Method is
     (SOCKS5_No_Authentication,
      SOCKS5_Username_Password);
   --  SOCKS5 authentication offered by the client. GSSAPI is unsupported.

   type SOCKS5_DNS_Mode is
     (SOCKS5_Remote_DNS,
      SOCKS5_Local_DNS);
   --  SOCKS5 target-address policy.
   --
   --  Remote_DNS sends the origin host name in the SOCKS5 CONNECT request and
   --  is the default because it avoids local resolver use. Local_DNS is exposed
   --  as policy, but the transport may reject it when it cannot encode the
   --  resolved address portably for the current host family.

   type Proxy_Config is private;
   --  Validated proxy configuration.
   --
   --  HTTP_Proxy values contain a parsed http:// proxy endpoint. The optional
   --  Proxy-Authorization value is sent only to HTTP proxies and is never used
   --  for SOCKS. SOCKS5_Proxy values contain the proxy endpoint, DNS policy,
   --  and optional SOCKS username/password credentials. SOCKS credentials are
   --  used only in the SOCKS negotiation and are not serialized as HTTP
   --  headers, cache metadata, cookies, HPACK entries, diagnostics secrets, or
   --  request bodies. They are ordinary in-process Ada strings; this package
   --  does not claim hardened secret storage.

   No_Proxy_Config : constant Proxy_Config;
   --  Explicit no-proxy configuration.

   function Parse
     (Text : String;
      Item : out Proxy_Config) return Http_Client.Errors.Result_Status;
   --  Parse a conservative proxy URI.
   --
   --  Accepted forms are http://host[:port], socks5://host[:port], and
   --  socks5h://host[:port]. socks5h selects remote DNS. socks5 selects the
   --  documented default, also remote DNS. Query, fragment, userinfo, PAC,
   --  HTTPS proxy endpoints, SOCKS4, SOCKS4a, and opaque schemes are rejected.
   --
   --  @param Text Proxy URI text.
   --  @param Item Validated proxy configuration on success.
   --  @return Ok on success, Invalid_Proxy or Invalid_SOCKS_Proxy for malformed
   --          proxy URIs, or Proxy_Unsupported for syntactically recognized
   --          unsupported proxy schemes.

   function HTTP
     (Host : String;
      Port : Http_Client.URI.TCP_Port := 80)
      return Proxy_Config;
   --  GNATdoc contract.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @return Subprogram result.
   --  Construct an HTTP proxy endpoint from an already known host and port.

   function SOCKS5
     (Host      : String;
      Port      : Http_Client.URI.TCP_Port := 1080;
      DNS_Mode  : SOCKS5_DNS_Mode := SOCKS5_Remote_DNS)
      return Proxy_Config;
   --  GNATdoc contract.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @param DNS_Mode Subprogram parameter.
   --  @return Subprogram result.
   --  Construct a no-authentication SOCKS5 proxy endpoint.
   --
   --  The proxy host is validated with the same conservative host syntax used
   --  for HTTP proxy construction. Invalid host syntax returns No_Proxy_Config;
   --  callers that need detailed status diagnostics should prefer Parse.

   function With_Proxy_Authorization
     (Config : Proxy_Config;
      Value  : String;
      Item   : out Proxy_Config) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return Config with an explicit HTTP Proxy-Authorization field attached.
   --
   --  This is valid only for HTTP_Proxy values. Applying HTTP proxy
   --  authorization to SOCKS5 proxies returns Invalid_Proxy so credentials are
   --  not silently moved between protocol layers.

   function With_SOCKS5_Username_Password
     (Config   : Proxy_Config;
      Username : String;
      Password : String;
      Item     : out Proxy_Config) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return Config with SOCKS5 username/password authentication enabled.
   --
   --  Each credential must be 1 .. 255 octets and must not contain ASCII
   --  control characters. Credentials are used only during SOCKS5 negotiation.

   function Kind (Item : Proxy_Config) return Proxy_Kind;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Is_Enabled (Item : Proxy_Config) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Host (Item : Proxy_Config) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Port (Item : Proxy_Config) return Http_Client.URI.TCP_Port;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.

   function Has_Proxy_Authorization (Item : Proxy_Config) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Proxy_Authorization (Item : Proxy_Config) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.

   function SOCKS5_Authentication
     (Item : Proxy_Config) return SOCKS5_Authentication_Method;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function SOCKS5_DNS_Resolution
     (Item : Proxy_Config) return SOCKS5_DNS_Mode;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function SOCKS5_Username (Item : Proxy_Config) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function SOCKS5_Password (Item : Proxy_Config) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.

private
   use Ada.Strings.Unbounded;

   type Proxy_Config is record
      Mode        : Proxy_Kind := No_Proxy;
      Proxy_Host  : Unbounded_String := Null_Unbounded_String;
      Proxy_Port  : Http_Client.URI.TCP_Port := 1;
      Has_Auth    : Boolean := False;
      Auth_Value  : Unbounded_String := Null_Unbounded_String;
      SOCKS_Auth  : SOCKS5_Authentication_Method := SOCKS5_No_Authentication;
      SOCKS_DNS   : SOCKS5_DNS_Mode := SOCKS5_Remote_DNS;
      SOCKS_User  : Unbounded_String := Null_Unbounded_String;
      SOCKS_Pass  : Unbounded_String := Null_Unbounded_String;
   end record;

   No_Proxy_Config : constant Proxy_Config :=
     (Mode       => No_Proxy,
      Proxy_Host => Null_Unbounded_String,
      Proxy_Port => 1,
      Has_Auth   => False,
      Auth_Value => Null_Unbounded_String,
      SOCKS_Auth => SOCKS5_No_Authentication,
      SOCKS_DNS  => SOCKS5_Remote_DNS,
      SOCKS_User => Null_Unbounded_String,
      SOCKS_Pass => Null_Unbounded_String);
end Http_Client.Proxies;
