with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.Headers is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Validated HTTP header field collection.
   --
   --  Header names are validated using the HTTP token character set and are
   --  matched case-insensitively. The original spelling supplied by the caller
   --  is preserved in storage and deterministic iteration order is insertion
   --  order. Header values are stored as raw strings, but carriage return,
   --  line feed, NUL, horizontal tab, DEL, C1 controls, and all other control
   --  characters are rejected. Obsolete line folding is not supported.

   type Header_List is private;
   --  Ordered collection of HTTP header fields.

   function Empty return Header_List;
   --  GNATdoc contract.
   --  @return Subprogram result.
   --  Return an empty header collection.

   function Is_Valid_Name (Name : String) return Boolean;
   --  Return True when Name is a non-empty HTTP token.
   --
   --  @param Name Candidate header field name.
   --  @return True only for a non-empty token composed of letters, digits, and
   --          allowed token punctuation.

   function Is_Valid_Value (Value : String) return Boolean;
   --  Return True when Value contains no rejected control characters.
   --
   --  @param Value Candidate header field value.
   --  @return True when Value is safe to store as a raw field value.


   function Is_HTTP2_Pseudo_Name (Name : String) return Boolean;
   --  Return True when Name is an HTTP/2 pseudo-header field name.
   --
   --  @param Name Candidate HTTP/2 field name.
   --  @return True only for names beginning with ':' followed by lowercase
   --          HTTP token characters. Pseudo-headers are never valid trailers.

   function Is_Forbidden_HTTP2_Trailer_Name
     (Name : String;
      Response : Boolean := False) return Boolean;
   --  Return True when Name is forbidden in HTTP/2 trailers.
   --
   --  @param Name Candidate trailer field name.
   --  @param Response True for response trailers, False for request trailers.
   --  @return True for pseudo-headers, connection/framing fields, and
   --          conservative credential/session fields rejected by Phase 10.

   function Validate_HTTP2_Trailers
     (List     : Header_List;
      Response : Boolean := False) return Http_Client.Errors.Result_Status;
   --  Validate a complete HTTP/2 trailer field list.
   --
   --  @param List Trailer fields to validate.
   --  @param Response True for response trailers, False for request trailers.
   --  @return Ok when every field is valid for HTTP/2 trailing HEADERS,
   --          otherwise Invalid_Header.

   function Add
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status;
   --  Append a header field without replacing existing fields of the same name.
   --
   --  @param List Header collection to modify.
   --  @param Name Header field name.
   --  @param Value Header field value.
   --  @return Ok when appended, otherwise Invalid_Header.


   function Add_HTTP2_Pseudo
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Append an HTTP/2 pseudo-header such as :method or :status.
   --
   --  This deliberately does not change Is_Valid_Name for ordinary HTTP/1.x
   --  header fields; colon-bearing pseudo-headers are only valid through the
   --  HTTP/2 mapping layer and still require a non-empty token after ':'.

   function Set
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status;
   --  Replace all fields with the same case-insensitive name with one field.
   --
   --  The new field is appended at the position of the first replaced field;
   --  if no previous field exists, it is appended to the end.
   --
   --  @param List Header collection to modify.
   --  @param Name Header field name.
   --  @param Value Header field value.
   --  @return Ok when stored, otherwise Invalid_Header.

   procedure Append
     (List  : in out Header_List;
      Name  : String;
      Value : String)
   with
      Pre => Is_Valid_Name (Name) and then Is_Valid_Value (Value);
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  Compatibility wrapper for Add.
   --
   --  New code should prefer Add so validation failures are returned as a
   --  status value.

   function Contains
     (List : Header_List;
      Name : String) return Boolean;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when a header with Name exists, using case-insensitive match.

   function Get
     (List : Header_List;
      Name : String) return String;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Return the first value for Name, or the empty string when absent.
   --
   --  Use Contains when absence must be distinguished from an empty value.

   function Count
     (List : Header_List;
      Name : String) return Natural;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of fields matching Name case-insensitively.

   function Remove
     (List : in out Header_List;
      Name : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Name Subprogram parameter.
   --  Remove all fields matching Name case-insensitively.
   --
   --  @return Ok for a valid field name whether or not a field was present;
   --          Invalid_Header for an invalid field name.

   function Length (List : Header_List) return Natural;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @return Subprogram result.
   --  Return the total number of stored header fields.

   procedure Clear (List : in out Header_List);
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  Remove all stored header fields.

   function Name_At
     (List  : Header_List;
      Index : Positive) return String
   with
      Pre => Index <= Length (List);
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Index Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored spelling of the field name at insertion-order Index.

   function Value_At
     (List  : Header_List;
      Index : Positive) return String
   with
      Pre => Index <= Length (List);
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Index Subprogram parameter.
   --  @return Subprogram result.
   --  Return the field value at insertion-order Index.

private
   use Ada.Strings.Unbounded;

   type Header_Field is record
      Name  : Unbounded_String;
      Key   : Unbounded_String;
      Value : Unbounded_String;
   end record;

   package Header_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Header_Field);

   type Header_List is record
      Items : Header_Vectors.Vector;
   end record;
end Http_Client.Headers;
