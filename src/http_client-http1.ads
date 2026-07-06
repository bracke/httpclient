with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Requests;

package Http_Client.HTTP1 is

   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/1.1 wire-format serialization.
   --
   --  This package converts validated in-memory requests into deterministic
   --  HTTP/1.1 request text. It performs no socket I/O, DNS
   --  lookup, TLS setup, connection management, response parsing, redirects,
   --  cookies, compression, HTTP/2, HPACK, streaming, authentication, or
   --  request execution.

   type Request_Target_Mode is (Origin_Form, Absolute_Form);
   --  Request-target serialization mode.
   --
   --  Origin_Form is the ordinary direct-server and CONNECT-tunnel form, such
   --  as /path?query. Absolute_Form is for plain HTTP requests sent through an
   --  HTTP proxy, such as http://example.com/path?query.

   function Serialize_Headers
     (Request : Http_Client.Requests.Request;
      Output  : out Ada.Strings.Unbounded.Unbounded_String;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @param Target_Mode Subprogram parameter.
   --  @return Subprogram result.
   --  Serialize only the request line and header section, including the final
   --  CRLF-CRLF delimiter.
   --
   --  For fixed-length streaming bodies, Content-Length is synthesized or
   --  validated against the declared stream length. For unknown-length
   --  streaming bodies, Transfer-Encoding: chunked is synthesized unless an
   --  explicit validated Transfer-Encoding: chunked header already exists.
   --  Content-Length and Transfer-Encoding together are rejected. Explicit
   --  request trailers are valid only for unknown-length chunked uploads; when
   --  present, a Trailer declaration is synthesized unless the request already
   --  supplied a covering Trailer header. The body and trailer field lines are
   --  not appended.

   function Serialize_Request
     (Request : Http_Client.Requests.Request;
      Output  : out Ada.Strings.Unbounded.Unbounded_String;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return Http_Client.Errors.Result_Status;
   --  Serialize Request as an HTTP/1.1 request message.
   --
   --  The request line uses the stored method token, the selected request
   --  target form, and literal HTTP/1.1. Header order is deterministic: existing
   --  request headers are emitted in insertion order, a synthesized Host
   --  header is appended when absent, and a synthesized Content-Length is
   --  appended when an in-memory payload is present and no explicit matching
   --  Content-Length exists. Header lines and the header terminator use CRLF.
   --
   --  @param Request Validated request created by Http_Client.Requests.Create.
   --  @param Output Serialized request text on success; empty on failure.
   --  @param Target_Mode Origin_Form for direct/tunneled requests or
   --         Absolute_Form for plain HTTP over an HTTP proxy.
   --  @return Ok on success; Invalid_Request for invalid request state;
   --          Invalid_Header for invalid or inconsistent headers;
   --          Protocol_Error for inconsistent Content-Length.

   function Serialize_Request
     (Request : Http_Client.Requests.Request;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return String
   with
      Pre => Http_Client.Requests.Is_Valid (Request);
   --  Convenience wrapper returning serialized text directly.
   --
   --  This wrapper is intended for callers that have already validated the
   --  request and do not need status inspection. Use the status-returning
   --  overload for ordinary error handling.
   --
   --  @param Request Validated request created by Http_Client.Requests.Create.
   --  @param Target_Mode Origin_Form for direct/tunneled requests or
   --         Absolute_Form for plain HTTP over an HTTP proxy.
   --  @return Serialized HTTP/1.1 request text.

end Http_Client.HTTP1;
