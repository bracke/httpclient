with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.URI;

package Http_Client.Proxies.SOCKS is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Byte-exact SOCKS5 protocol helpers.
   --
   --  This package builds and parses SOCKS5 CONNECT negotiation messages using
   --  explicit octet operations. It implements CONNECT only. UDP ASSOCIATE,
   --  BIND, SOCKS4/SOCKS4a, GSSAPI, PAC/WPAD, and browser-like proxy behavior
   --  are intentionally outside this package.

   function Greeting
     (Config : Http_Client.Proxies.Proxy_Config;
      Output : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Build the SOCKS5 method greeting for Config.

   function Expected_Method
     (Config : Http_Client.Proxies.Proxy_Config) return Character;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Return the method octet expected for the configured SOCKS5 auth mode.

   function Parse_Method_Selection
     (Reply  : String;
      Config : Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Reply Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Parse a two-octet SOCKS5 method-selection reply.

   function Username_Password_Request
     (Config : Http_Client.Proxies.Proxy_Config;
      Output : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Build RFC 1929 username/password subnegotiation bytes.

   function Parse_Username_Password_Reply
     (Reply : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Reply Subprogram parameter.
   --  @return Subprogram result.
   --  Parse the two-octet RFC 1929 subnegotiation reply.

   function Connect_Request
     (Target_Host : String;
      Target_Port : Http_Client.URI.TCP_Port;
      DNS_Mode    : Http_Client.Proxies.SOCKS5_DNS_Mode;
      Output      : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Target_Host Subprogram parameter.
   --  @param Target_Port Subprogram parameter.
   --  @param DNS_Mode Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Build a SOCKS5 CONNECT request for a domain name or IPv4 literal.
   --  IPv6 targets are rejected in this release rather than encoded ambiguously.

   function Parse_Connect_Reply
     (Reply : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Reply Subprogram parameter.
   --  @return Subprogram result.
   --  Parse a complete SOCKS5 CONNECT reply and map reply codes to stable
   --  project statuses.

end Http_Client.Proxies.SOCKS;
