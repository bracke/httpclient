with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Responses;

package Http_Client.Decompression is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit bounded in-memory response content decompression.
   --
   --  This package interprets HTTP Content-Encoding metadata after transports,
   --  HTTP/1.1 message framing, and response parsing have already completed.
   --  It performs no socket I/O, TLS handling, redirect handling, cookie
   --  handling, HTTP/2, HPACK, caching, or public streaming-body work.
   --
   --  Supported encodings are identity, gzip, zlib-wrapped deflate, and
   --  explicitly configured raw deflate. Brotli, zstd, and stacked encodings
   --  are intentionally out of scope for this release.


   type Deflate_Decoding_Mode is
     (Zlib_Wrapped_Only,
      Raw_Only,
      Auto_Zlib_Then_Raw);
   --  Policy for ambiguous HTTP Content-Encoding: deflate payloads.
   --
   --  Zlib_Wrapped_Only is the default and accepts only RFC-conservative
   --  zlib-wrapped deflate. Raw_Only accepts raw deflate without a zlib
   --  wrapper. Auto_Zlib_Then_Raw chooses zlib-wrapped deflate when the
   --  initial bytes have a valid zlib header and otherwise decodes as raw
   --  deflate. Decompression remains opt-in in streaming APIs, and decoded
   --  body bytes are binary data.

   type Unsupported_Encoding_Policy is
     (Reject_Unsupported,
      Leave_Encoded);
   --  Policy for unsupported or stacked Content-Encoding values.
   --
   --  Reject_Unsupported returns Unsupported_Content_Encoding. Leave_Encoded
   --  returns Ok with Decoded set to False and Body_Data equal to the encoded body.

   type Decompression_Options is record
      Maximum_Decoded_Body_Size : Natural := 4_194_304;
      Unsupported_Policy        : Unsupported_Encoding_Policy := Reject_Unsupported;
      Deflate_Mode              : Deflate_Decoding_Mode := Zlib_Wrapped_Only;
   end record;
   --  Options for bounded in-memory decompression.
   --
   --  @field Maximum_Decoded_Body_Size Maximum decoded bytes returned to the
   --         caller. Encoded-size limits remain owned by the response reader.
   --  @field Unsupported_Policy Whether unknown or stacked encodings fail or
   --         are returned still encoded.
   --  @field Deflate_Mode How Content-Encoding: deflate is interpreted. The
   --         default is standards-conservative zlib-wrapped deflate only.

   Default_Decompression_Options : constant Decompression_Options :=
     (Maximum_Decoded_Body_Size => 4_194_304,
      Unsupported_Policy        => Reject_Unsupported,
      Deflate_Mode              => Zlib_Wrapped_Only);
   --  Conservative default decoded-output limit.

   type Decoded_Response is private;
   --  Non-destructive decoded response view.
   --
   --  Original_Response preserves the parsed response and original headers.
   --  Decoded_Body returns decoded bytes when Decoded is True, otherwise the original
   --  encoded body. Content-Length and Content-Encoding therefore remain
   --  accurate metadata for the encoded wire representation.

   function Default_Decoded_Response return Decoded_Response;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return an empty non-decoded view over Default_Response.

   function Original_Response
     (Item : Decoded_Response) return Http_Client.Responses.Response;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the original parsed response with its original headers and body.

   function Decoded_Body (Item : Decoded_Response) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return decoded bytes when Decoded is True, otherwise original body bytes.

   function Encoded_Body (Item : Decoded_Response) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the original encoded response body bytes without interpretation.
   --
   --  This is a convenience accessor for Response_Body (Original_Response (Item)) and
   --  makes the encoded-versus-decoded distinction explicit for callers that
   --  need exact wire payload bytes after using a decoded view.

   function Decoded (Item : Decoded_Response) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when a non-identity supported encoding was successfully decoded.

   function Original_Content_Encoding (Item : Decoded_Response) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the original Content-Encoding token, or the empty string when absent.

   function Supported_Accept_Encoding return String;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return the exact Accept-Encoding value supported by this release.

   function Decode_Body
     (Encoded_Body : String;
      Encoding     : String;
      Decoded_Body : out Ada.Strings.Unbounded.Unbounded_String;
      Options      : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Encoded_Body Subprogram parameter.
   --  @param Encoding Subprogram parameter.
   --  @param Decoded_Body Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Decode Encoded_Body according to a single Content-Encoding token.
   --
   --  identity and an empty token copy the body unchanged. gzip validates the
   --  gzip wrapper and checksum through zlib. deflate is interpreted according
   --  to Options.Deflate_Mode; zlib-wrapped is the default, raw deflate is
   --  explicit, and auto mode selects zlib or raw from the initial bytes.
   --  Unknown or stacked encodings are handled according to
   --  Options.Unsupported_Policy.

   function Decode_Response
     (Response : Http_Client.Responses.Response;
      Result   : out Decoded_Response;
      Options  : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Response Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Build a non-destructive decoded view of Response.
   --
   --  Original response headers are preserved. Stacked encodings such as
   --  "gzip, deflate" and multiple Content-Encoding headers are rejected unless
   --  Options.Unsupported_Policy requests that encoded bytes be left unchanged.
   --  This low-level overload assumes the response belongs to a body-capable
   --  request method; use Decode_Response_With_Context when the originating
   --  request may have been HEAD.

   function Decode_Response_With_Context
     (Response         : Http_Client.Responses.Response;
      Request_Was_HEAD : Boolean;
      Result           : out Decoded_Response;
      Options          : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Response Subprogram parameter.
   --  @param Request_Was_HEAD Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Build a decoded view with originating-request body semantics.
   --
   --  When Request_Was_HEAD is True, Content-Encoding remains metadata only and
   --  no decompression is attempted even for a 200 response.

private
   use Ada.Strings.Unbounded;

   type Decoded_Response is record
      Original : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Payload  : Unbounded_String := Null_Unbounded_String;
      Was_Decoded : Boolean := False;
      Encoding : Unbounded_String := Null_Unbounded_String;
   end record;
end Http_Client.Decompression;
