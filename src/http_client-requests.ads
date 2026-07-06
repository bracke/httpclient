with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Types;
with Http_Client.URI;

package Http_Client.Requests is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  In-memory HTTP request construction.
   --
   --  This package models outbound requests after URI parsing and before wire
   --  serialization. It performs no network I/O, DNS lookup, TLS setup,
   --  redirects, cookies, compression, HTTP/2, HPACK, streaming, response
   --  parsing, authentication, or request execution.

   type Request is private;
   --  Validated in-memory outbound request.

   function Method_Image
     (Method : Http_Client.Types.Method_Name) return String;
   --  Return the uppercase HTTP method token for Method.
   --
   --  @param Method Method enumeration value.
   --  @return HTTP method token such as "GET" or "POST".

   function Create
     (Method    : Http_Client.Types.Method_Name;
      URI       : Http_Client.URI.URI_Reference;
      Item      : out Request;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Payload   : String := "";
      Auto_Host : Boolean := True) return Http_Client.Errors.Result_Status;
   --  Construct a request from a parsed HTTP or HTTPS URI.
   --
   --  If Auto_Host is True and Headers does not already contain Host, the
   --  correct Host header value is inserted from the URI. Existing caller Host
   --  fields are preserved. Payload is stored verbatim as a replayable buffered body. Streaming
   --  bodies are attached explicitly through Set_Body.
   --
   --  @param Method HTTP method.
   --  @param URI Parsed URI value produced by Http_Client.URI.Parse.
   --  @param Item Constructed request when the return status is Ok.
   --  @param Headers Initial validated header collection.
   --  @param Payload Optional string payload.
   --  @param Auto_Host Whether to insert Host automatically when absent.
   --  @return Ok on success, Invalid_URI for an unparsed URI, Invalid_Header
   --          if automatic Host insertion unexpectedly fails.

   function Default_Request return Request;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return an inert default GET request.
   --
   --  The default value exists for compatibility and tests. It is not a valid
   --  complete outbound request until Create is used with a parsed URI.

   function Is_Valid (Item : Request) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item was successfully constructed by Create.

   function Method (Item : Request) return Http_Client.Types.Method_Name;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the request method.

   function URI (Item : Request) return Http_Client.URI.URI_Reference;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed URI associated with the request.

   function Headers (Item : Request) return Http_Client.Headers.Header_List;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return a copy of the request header collection.

   function Payload (Item : Request) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored string payload for buffered bodies, or the empty
   --  string for empty/streaming bodies.

   function Request_Body (Item : Request) return Http_Client.Request_Bodies.Request_Body;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the explicit request-body descriptor.

   function Has_Payload (Item : Request) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the stored payload has non-zero length.

   function Request_Target (Item : Request) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the HTTP/1.1 origin-form request target from the parsed URI.
   --
   --  The result is path plus optional query and never includes the fragment.

   function Host_Header_Value (Item : Request) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the Host header value computed from the parsed URI.

   function Set_Payload
     (Item    : in out Request;
      Payload : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @return Subprogram result.
   --  Replace the request body with a replayable in-memory payload.
   --
   --  This package deliberately does not infer Transfer-Encoding. HTTP/1.1
   --  serialization and Content-Length handling are owned by Http_Client.HTTP1.

   function Set_Body
     (Item : in out Request;
      New_Body : Http_Client.Request_Bodies.Request_Body)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param New_Body Subprogram parameter.
   --  @return Subprogram result.
   --  Replace the request body with an explicit empty, buffered, or streaming
   --  descriptor. A streamed body is owned by one execution at a time.

   function Is_Body_Replayable (Item : Request) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the current body can be resent identically.

   function Reset_Body (Item : Request) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Reset the current body before a retry or redirect replay.

   procedure Set_Target
     (Item   : in out Request;
      Target : String);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Target Subprogram parameter.
   --  Compatibility helper that stores unchecked target text.
   --
   --  New request construction should use Create with Http_Client.URI.Parse.

   function Target_Text (Item : Request) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return compatibility target text for unchecked default requests, or the
   --  computed request target for validated requests.

private
   use Ada.Strings.Unbounded;

   type Request is record
      Valid       : Boolean := False;
      Method_Name : Http_Client.Types.Method_Name := Http_Client.Types.GET;
      Request_URI : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Header_List : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Payload_Text : Unbounded_String := Null_Unbounded_String;
      Body_Value   : Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Request_Bodies.Empty;
      Legacy_Target : Unbounded_String := Null_Unbounded_String;
   end record;
end Http_Client.Requests;
