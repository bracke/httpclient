with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Types;

package Http_Client.HTTP3.Mapping is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  HTTP request/response metadata mapping rules for HTTP/3.
   --
   --  This package performs no QPACK compression and no QUIC I/O. It builds
   --  and validates the header lists that a future QPACK encoder may consume.
   --  Pseudo-headers are represented in ordinary Header_List values so tests
   --  can inspect deterministic ordering.

   function Build_Request_Headers
     (Request : Http_Client.Requests.Request;
      Output  : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Build HTTP/3 request headers in pseudo-header order:
   --  :method, :scheme, :authority, :path, followed by lowercase ordinary
   --  fields. Host maps to :authority and is not emitted as a normal field.
   --  Connection-specific fields are rejected before bytes are sent.

   function Validate_Request_Headers
     (Headers : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Headers Subprogram parameter.
   --  @return Subprogram result.
   --  Validate already-built HTTP/3 request headers.

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
   --  Validate HTTP/3 response header ordering and forbidden fields.
end Http_Client.HTTP3.Mapping;
