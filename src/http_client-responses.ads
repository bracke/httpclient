with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Types;

package Http_Client.Responses is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/1.1 response model and strict in-memory parser.
   --
   --  This package parses complete raw HTTP response messages already read by
   --  a transport. It performs no socket I/O, TLS handling, redirects,
   --  cookies, decompression, chunked decoding, streaming, HTTP/2, HPACK, or
   --  content interpretation. Parsing is strict about CRLF line endings. It expects
   --  the body argument to be HTTP entity bytes, not raw transfer framing.
   --
   --  Supported response framing for the stable buffered parser is a single valid
   --  Content-Length header or no Content-Length. Duplicate Content-Length
   --  fields and any raw Transfer-Encoding field are rejected deterministically:
   --  callers that decode HTTP/1.1 transfer framing must pass entity body bytes
   --  without raw transfer-framing headers. If Content-Length is absent, simple
   --  in-memory parsing treats all bytes after the header terminator as the body
   --  except for response codes that must not carry a body.

   type HTTP_Version is
     (HTTP_1_0,
      HTTP_1_1);
   --  Response protocol versions accepted by the parser.

   type Parse_Context is record
      Request_Was_HEAD : Boolean := False;
   end record;
   --  Optional request context supplied to response parsing.
   --
   --  @field Request_Was_HEAD True when the response belongs to a HEAD
   --         request, meaning no response body is required or consumed.

   Default_Context : constant Parse_Context := (Request_Was_HEAD => False);
   --  Default parse context for responses not associated with a known method.

   type Response is private;
   --  Validated in-memory HTTP response data.
   --
   --  Response values are constructed by Default_Response or Parse_Response.
   --  Accessors return scalar values or copies, so callers cannot mutate
   --  internal parser state accidentally. Payload is currently represented as
   --  a String-backed unbounded string. It may contain arbitrary 8-bit
   --  Character values, but no character-set or content decoding is performed.

   function Default_Response return Response;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return a default HTTP/1.1 200 response with no reason, headers, or body.

   function Version_Image (Version : HTTP_Version) return String;
   --  Return the wire token for Version.
   --
   --  @param Version HTTP version enumeration value.
   --  @return "HTTP/1.0" or "HTTP/1.1".

   function Reason_Phrase (Item : Response) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored reason phrase.

   function Version (Item : Response) return HTTP_Version;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed HTTP protocol version.

   function Status_Code
     (Item : Response) return Http_Client.Types.Status_Code;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed three-digit HTTP status code.

   function Headers (Item : Response) return Http_Client.Headers.Header_List;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return a copy of the parsed response header collection.

   function Header
     (Item : Response;
      Name : String) return String;
   --  Return the first response header value for Name, or the empty string
   --  when absent. Header names are matched case-insensitively by the
   --  existing header collection semantics.

   function Has_Header
     (Item : Response;
      Name : String) return Boolean;
   --  Return True when the response contains a header named Name.

   function Content_Type (Item : Response) return String;
   --  Return the complete server-declared Content-Type header value, or the
   --  empty string when absent. This accessor does not inspect the body.

   function Has_Content_Type (Item : Response) return Boolean;
   --  Return True when the response contains a Content-Type header.

   function Media_Type (Item : Response) return String;
   --  Return the Content-Type media type before parameters, trimmed of
   --  surrounding HTTP optional whitespace, or the empty string when absent.

   function Charset (Item : Response) return String;
   --  Return the Content-Type charset parameter value when present and
   --  non-empty. Simple quoted values are unquoted. This accessor does not
   --  perform character-set conversion or MIME sniffing.

   function Has_Charset (Item : Response) return Boolean;
   --  Return True when Charset would return a non-empty value.

   function Trailers (Item : Response) return Http_Client.Headers.Header_List;
   --  GNATdoc contract.
   --  @param Item Response value.
   --  @return Copy of the response trailer field collection.
   --  HTTP/2 response trailers are stored separately from ordinary response
   --  headers. HTTP/1.x parsing returns an empty list because transfer
   --  trailers are consumed by the streaming/framing layer.

   function Response_Body (Item : Response) return String;
   --  GNATdoc contract.
   --  @param Item Response value.
   --  @return Response body converted through the string convenience path.

   function Response_Body_Bytes
     (Item : Response) return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored in-memory response body bytes.

   function From_Components
     (Version : HTTP_Version;
      Status  : Http_Client.Types.Status_Code;
      Reason  : String;
      Headers : Http_Client.Headers.Header_List;
      Body_Text : String) return Response;
   --  Build a response from already validated HTTP representation components.
   --
   --  This helper is for protocol adapters that have already decoded transport
   --  framing and enforced their caller-supplied body limits. It does not parse
   --  synthetic raw HTTP/1.x bytes or apply Parse_Response's defensive fixed
   --  in-memory body ceiling.

   function Copy_With_Headers
     (Item    : Response;
      Headers : Http_Client.Headers.Header_List) return Response;
   --  GNATdoc contract.
   --  @param Item Response value to copy.
   --  @param Headers Replacement response header fields.
   --  @return A copy of Item with Headers replacing the stored header list.
   --
   --  This helper is intentionally narrow. It exists for conservative HTTP
   --  cache revalidation metadata updates after a 304 Not Modified response;
   --  it does not reinterpret Content-Length, transform the body, or parse raw
   --  HTTP bytes. Callers must preserve HTTP representation invariants.

   function Copy_With_Trailers
     (Item     : Response;
      Trailers : Http_Client.Headers.Header_List) return Response;
   --  GNATdoc contract.
   --  @param Item Response value to copy.
   --  @param Trailers Replacement response trailer fields.
   --  @return A copy of Item with Trailers replacing the stored trailer list.

   function Parse_Header_Section
     (Input   : String;
      Result  : out Response;
      Context : Parse_Context := Default_Context)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Input Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Context Subprogram parameter.
   --  @return Subprogram result.
   --  Parse a strict HTTP/1.x response header section without requiring or
   --  storing the response body.
   --
   --  Input must contain the complete status line, response headers, and the
   --  terminating CRLF CRLF, with no body bytes required. The returned Response
   --  contains version, status code, reason phrase, and headers; Response_Body returns
   --  the empty string. This helper exists for streaming execution paths that
   --  expose metadata before the body is fully consumed. Header syntax and
   --  no-body status handling follow Parse_Response. Transfer-Encoding is
   --  preserved as ordinary metadata here because the streaming layer decides
   --  whether that framing is supported before it exposes entity body bytes.

   function Parse_Response
     (Input   : String;
      Result  : out Response;
      Context : Parse_Context := Default_Context)
      return Http_Client.Errors.Result_Status;
   --  Parse a complete strict HTTP/1.x response message.
   --
   --  The status line must use HTTP/1.1 or HTTP/1.0, one required space before
   --  the three-digit status code, and either no reason phrase or one required
   --  space before the reason phrase. Header lines must be `Name: Value`, use
   --  CRLF, and pass Http_Client.Headers validation. Leading spaces and tabs
   --  after the colon are stripped; trailing spaces and tabs in values are
   --  stripped deterministically. Obsolete folded header continuation lines are
   --  rejected.
   --
   --  Body_Data handling is in-memory only. A single Content-Length header requires
   --  exactly that many body bytes to be available. Extra bytes after a
   --  Content-Length body are rejected as Protocol_Error. Without
   --  Content-Length, all bytes after the header terminator are stored as the
   --  body unless the response is for HEAD or has a no-body status: 1xx,
   --  204, 205, or 304. Unexpected body bytes for these cases are rejected as
   --  Protocol_Error.
   --
   --  Complete responses returned by Http_Client.HTTP1.Reader have already had
   --  HTTP/1.1 chunked transfer coding decoded when present. Direct callers of
   --  Parse_Response must pass a complete entity body, not raw chunk frames, and
   --  must not include raw Transfer-Encoding response fields.
   --
   --  @param Input Raw response bytes represented as a String.
   --  @param Result Parsed response on Ok; default response on failure.
   --  @param Context Optional originating-request context.
   --  @return Ok, Protocol_Error, Invalid_Header, Unsupported_Feature, or
   --          Incomplete_Message for ordinary parse outcomes.

private
   use Ada.Strings.Unbounded;

   type Response is record
      Version_Value : HTTP_Version := HTTP_1_1;
      Status_Value  : Http_Client.Types.Status_Code := 200;
      Reason_Value  : Unbounded_String := Null_Unbounded_String;
      Header_List   : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Trailer_List  : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Payload_Value : Unbounded_String := Null_Unbounded_String;
   end record;
end Http_Client.Responses;
