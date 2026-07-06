with Ada.Strings.Unbounded;
with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Requests;

package Http_Client.Auth.Digest is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Conservative HTTP Digest authentication helpers.
   --
   --  This package parses Digest challenges and generates caller-controlled
   --  Authorization field values. It does not prompt for credentials, persist
   --  credentials, use OS stores, perform OAuth/OIDC/SAML/NTLM/Negotiate/
   --  Kerberos workflows, or automatically retry requests. Callers that build
   --  challenge-response execution must keep retry counts bounded and must
   --  resend a body only when the method and body producer are replayable.
   --
   --  qop=auth is supported. qop=auth-int is reported as unsupported because
   --  hashing the entity body exactly as sent must account for streaming,
   --  multipart, retries, and HTTP/2 DATA framing. MD5/MD5-sess support is
   --  provided only for legacy protocol compatibility and is disabled by the
   --  Allow_Legacy_MD5 parameter unless the caller explicitly permits it.

   use Ada.Strings.Unbounded;

   type Digest_Algorithm is
     (Algorithm_MD5,
      Algorithm_MD5_Sess,
      Algorithm_SHA_256,
      Algorithm_SHA_256_Sess);

   type Digest_QOP is
     (QOP_None,
      QOP_Auth,
      QOP_Auth_Int);

   type Challenge is record
      Valid          : Boolean := False;
      Realm          : Unbounded_String;
      Nonce          : Unbounded_String;
      Opaque         : Unbounded_String;
      Algorithm      : Digest_Algorithm := Algorithm_MD5;
      Has_Algorithm  : Boolean := False;
      Offers_Auth    : Boolean := False;
      Offers_Auth_Int : Boolean := False;
      Stale          : Boolean := False;
   end record;
   --  Parsed Digest challenge. Unknown extension parameters are ignored.

   function Parse_Challenge
     (Header_Value : String;
      Parsed       : out Challenge) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header_Value Subprogram parameter.
   --  @param Parsed Subprogram parameter.
   --  @return Subprogram result.
   --  Parse WWW-Authenticate/Proxy-Authenticate Digest challenge text.
   --
   --  Header_Value may be either the full "Digest ..." field value or only
   --  the Digest parameter list. Malformed quoted strings, duplicate critical
   --  parameters, CR/LF injection, overlong parameter values, unsupported
   --  algorithms, missing realm, and missing nonce are rejected deterministically.

   function Nonce_Count_Text (Value : Positive) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Return the eight-lowercase-hex nonce-count representation.

   function CNonce_From_Octets (Octets : String) return String;
   --  GNATdoc contract.
   --  @param Octets Subprogram parameter.
   --  @return Subprogram result.
   --  Return lowercase hexadecimal text for caller/test supplied octets.
   --
   --  This deterministic helper is intended for tests and for callers that
   --  already obtained cryptographically strong random bytes elsewhere. The
   --  result contains only header-safe ASCII hex characters.

   function Generate_CNonce
     (Value       : out Unbounded_String;
      Octet_Count : Positive := 16) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @param Octet_Count Subprogram parameter.
   --  @return Subprogram result.
   --  Generate a cryptographically random Digest cnonce as lowercase hex.
   --
   --  Production code uses OpenSSL-backed random bytes. If randomness fails,
   --  this function returns a deterministic failure status and emits no cnonce;
   --  callers must not silently fall back to predictable cnonce values.

   function Generate_Response
     (Parsed           : Challenge;
      Username         : String;
      Password         : String;
      Method           : String;
      URI              : String;
      Nonce_Count      : Positive;
      CNonce           : String;
      Header_Value     : out Unbounded_String;
      Allow_Legacy_MD5 : Boolean := False)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Parsed Subprogram parameter.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Method Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @param Nonce_Count Subprogram parameter.
   --  @param CNonce Subprogram parameter.
   --  @param Header_Value Subprogram parameter.
   --  @param Allow_Legacy_MD5 Subprogram parameter.
   --  @return Subprogram result.
   --  Generate an Authorization/Proxy-Authorization Digest field value.
   --
   --  URI must be the effective request target without fragment: origin-form
   --  path plus query for origin HTTP/1.1, the documented proxy target for
   --  proxy authentication, or the HTTP/2 :path value for HTTP/2. The response
   --  uses qop=auth when offered, rejects auth-int-only challenges, increments
   --  nonce count according to caller-provided state, rejects oversized generated
   --  field values, and never downgrades to legacy MD5 unless
   --  Allow_Legacy_MD5 is True.


   function Generate_Response_For_Request
     (Parsed           : Challenge;
      Request          : Http_Client.Requests.Request;
      Username         : String;
      Password         : String;
      Nonce_Count      : Positive;
      CNonce           : String;
      Header_Value     : out Unbounded_String;
      Allow_Legacy_MD5 : Boolean := False)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Parsed Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Username Subprogram parameter.
   --  @param Password Subprogram parameter.
   --  @param Nonce_Count Subprogram parameter.
   --  @param CNonce Subprogram parameter.
   --  @param Header_Value Subprogram parameter.
   --  @param Allow_Legacy_MD5 Subprogram parameter.
   --  @return Subprogram result.
   --  Generate a Digest field value using Request's method and origin-form
   --  request target. The URI fragment is never included because
   --  Http_Client.Requests.Request_Target delegates to the parsed URI target.

   function Set_Digest_Authorization
     (Request      : Http_Client.Requests.Request;
      Header_Value : String;
      Result       : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Header_Value Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Request with origin Authorization set to a generated Digest value.
   --
   --  Header_Value must be header-safe and begin with the Digest scheme. This
   --  helper does not retry, store credentials, or broaden redirect scope.

   function Set_Digest_Proxy_Authorization
     (Config       : Http_Client.Proxies.Proxy_Config;
      Header_Value : String;
      Result       : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @param Header_Value Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return Config with proxy-only Digest credentials attached.
   --
   --  The generated value is stored as proxy metadata and is not copied into
   --  origin requests or HTTP/2 origin header blocks.
end Http_Client.Auth.Digest;
