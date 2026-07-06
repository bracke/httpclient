with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Types;

package Http_Client.HTTP2.Mapping is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/1 request/response metadata mapping rules for HTTP/2.
   --
   --  This package performs no HPACK compression and no socket I/O. It builds
   --  and validates the header lists that later HPACK and frame layers may
   --  encode. Pseudo-headers are represented in ordinary Header_List values so
   --  tests can inspect deterministic ordering.

   function Build_Request_Headers
     (Request : Http_Client.Requests.Request;
      Output  : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Build HTTP/2 request headers in pseudo-header order:
   --  :method, :scheme, :authority, :path, followed by lowercase ordinary
   --  fields. Host maps to :authority and is not emitted as a normal field.
   --  Connection-specific fields are rejected before bytes are sent.

   function Validate_Request_Headers
     (Headers : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Headers Subprogram parameter.
   --  @return Subprogram result.
   --  Validate already-built HTTP/2 request headers.

   function Parse_Status
     (Headers : Http_Client.Headers.Header_List;
      Status  : out Http_Client.Types.Status_Code)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Headers Subprogram parameter.
   --  @param Status Subprogram parameter.
   --  @return Subprogram result.
   --  Parse exactly one :status response pseudo-header.

   function Validate_Response_Headers
     (Headers : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Headers Subprogram parameter.
   --  @return Subprogram result.
   --  Validate HTTP/2 response header ordering and forbidden fields.
end Http_Client.HTTP2.Mapping;
