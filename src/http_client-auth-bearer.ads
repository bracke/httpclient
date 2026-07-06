with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Requests;

package Http_Client.Auth.Bearer is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit Bearer-token authentication helpers.
   --
   --  Tokens are opaque caller-supplied credentials. This package validates
   --  only header-safety: it does not parse OAuth tokens, refresh tokens,
   --  contact token endpoints, persist tokens, read environment variables,
   --  use credential stores, or implement OpenID Connect/browser flows.
   --  Authorization values produced here are ordinary request headers and
   --  remain subject to redirect stripping, diagnostics redaction, cache
   --  bypass rules, and HTTP/2 HPACK never-index handling elsewhere.

   function Is_Valid_Token (Token : String) return Boolean;
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Token can be placed after the Bearer scheme.
   --
   --  Empty tokens, overlong tokens, and CR, LF, NUL, DEL, C1 controls,
   --  and all other control characters are rejected to prevent header injection
   --  and accidental oversized authentication fields.

   function Authorization_Value (Token : String) return String
   with
      Pre => Is_Valid_Token (Token);
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.
   --  Return "Bearer " & Token for origin Authorization.

   function Proxy_Authorization_Value (Token : String) return String
   with
      Pre => Is_Valid_Token (Token);
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.
   --  Return "Bearer " & Token for explicit proxy authentication only.

   function Bearer_Authorization
     (Token : String;
      Value : out String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Construct a Bearer field value into Value without allocation by caller.

   function Set_Bearer_Authorization
     (Request : Http_Client.Requests.Request;
      Token   : String;
      Result  : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Token Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Request with origin Authorization set to Bearer credentials.

   function Clear_Authorization
     (Request : Http_Client.Requests.Request;
      Result  : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Request with origin Authorization removed.

   function Set_Bearer_Proxy_Authorization
     (Config : Http_Client.Proxies.Proxy_Config;
      Token  : String;
      Result : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Token Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Config with proxy-only Bearer credentials attached.
end Http_Client.Auth.Bearer;
