with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Requests;

package Http_Client.Auth is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit HTTP authentication header helpers.
   --
   --  This package supports deterministic construction of HTTP Basic
   --  Authorization and Proxy-Authorization field values from credentials the
   --  caller already possesses. Advanced helpers add selected advanced helpers in
   --  child packages: Http_Client.Auth.Bearer for opaque Bearer tokens and
   --  Http_Client.Auth.Digest for conservative Digest challenge/response
   --  construction. These helpers do not implement automatic credential
   --  prompting, credential stores, token refresh, browser login flows, NTLM,
   --  Negotiate/SPNEGO, Kerberos, OAuth token acquisition, OpenID Connect,
   --  SAML, or TLS client-certificate workflows; mutual TLS is configured
   --  separately through Http_Client.TLS.Client_Certificates.
   --
   --  Credentials are processed only in caller-visible values and ordinary
   --  in-memory records. The library does not protect these strings from
   --  process memory inspection.

   function Is_Valid_Basic_Credentials
     (Username : String;
      Password : String) return Boolean;
   --  Return True when Username and Password are acceptable for Basic auth.
   --
   --  Username must be non-empty, must not contain ':', and both fields must
   --  reject CR, LF, NUL, DEL, C1 controls, and all other control characters. Password may
   --  be empty and may contain ':' because Basic separates at the first colon.
   --
   --  @param Username Caller-supplied Basic username.
   --  @param Password Caller-supplied Basic password.
   --  @return True only when the credentials are safe to encode into a header.

   function Base64_Encode (Input : String) return String;
   --  Return RFC-compatible Base64 for Input octets.
   --
   --  The encoder emits ASCII only, uses '=' padding as required, and never
   --  inserts whitespace or line breaks. Input characters are treated as octets
   --  using Character'Pos.
   --
   --  @param Input Octets represented as an Ada String.
   --  @return Base64 text with deterministic padding and no line folding.

   function Basic_Authorization
     (Username : String;
      Password : String;
      Value    : out String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  Construct an origin-server Authorization field value.
   --
   --  On success Value is exactly "Basic " followed by Base64 of
   --  username:password. Value must be large enough for the result; callers who
   --  prefer allocation-free exact sizing can use Basic_Authorization_Value.
   --
   --  @return Ok on success, Invalid_Credentials for rejected credentials, or
   --          Invalid_Header when Value is too short for the generated header.

   function Basic_Authorization_Value
     (Username : String;
      Password : String) return String
   with
      Pre => Is_Valid_Basic_Credentials (Username, Password);
   --  GNATdoc contract.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @return Subprogram result.
   --  Return a Basic origin-server Authorization field value.
   --
   --  This convenience function has a precondition and is intended for tests
   --  and callers that already validated credentials or can rely on assertions.

   function Basic_Proxy_Authorization_Value
     (Username : String;
      Password : String) return String
   with
      Pre => Is_Valid_Basic_Credentials (Username, Password);
   --  GNATdoc contract.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @return Subprogram result.
   --  Return a Basic proxy-only Proxy-Authorization field value.
   --
   --  The field value syntax is the same as Basic_Authorization_Value, but the
   --  name documents that it is for proxy use only. Client execution sends
   --  proxy authorization only to configured proxies, not to origin servers.

   function Set_Basic_Authorization
     (Request  : Http_Client.Requests.Request;
      Username : String;
      Password : String;
      Result   : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Request with Authorization set to Basic credentials.
   --
   --  This is a thin wrapper around validated request/header operations. It
   --  replaces any existing Authorization field deterministically and does not
   --  mutate the input request, perform I/O, retry on 401, or store secrets
   --  globally.

   function Clear_Authorization
     (Request : Http_Client.Requests.Request;
      Result  : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Request with origin Authorization removed.
   --
   --  Proxy-Authorization is intentionally separate and is not installed by
   --  this helper.

   function Set_Basic_Proxy_Authorization
     (Config   : Http_Client.Proxies.Proxy_Config;
      Username : String;
      Password : String;
      Result   : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Config with proxy-only Basic credentials attached.
   --
   --  The generated value is stored as proxy metadata. It is not copied into
   --  ordinary origin request headers and is not used for origin Authorization.
end Http_Client.Auth;
