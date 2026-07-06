with Ada.Strings.Unbounded;
with Interfaces;

with Http_Client.Errors;

package Http_Client.HTTP3.QPACK is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  Conservative QPACK package boundary for experimental HTTP/3.
   --
   --  This package is not HPACK. It supports no-dynamic-table header block
   --  prefixes and literal field lines without name references. Huffman-coded
   --  strings and dynamic table references are rejected deterministically.

   subtype QPACK_Integer is Interfaces.Unsigned_64 range 0 .. 16#3FFF_FFFF_FFFF_FFFF#;

   type Header_Field is record
      Name      : Ada.Strings.Unbounded.Unbounded_String;
      Value     : Ada.Strings.Unbounded.Unbounded_String;
      Sensitive : Boolean := False;
   end record;

   function Encode_Integer
     (Value        : QPACK_Integer;
      Prefix_Bits  : Positive;
      Prefix_Mask  : Natural) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @param Prefix_Bits Subprogram parameter.
   --  @param Prefix_Mask Subprogram parameter.
   --  @return Subprogram result.
   --  Encode an integer with a caller-provided already-shifted prefix mask.

   function Decode_Integer
     (Data        : String;
      Prefix_Bits : Positive;
      Value       : out QPACK_Integer;
      Consumed    : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Prefix_Bits Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @param Consumed Subprogram parameter.
   --  @return Subprogram result.

   function Encode_String_Literal (Value : String) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   function Decode_String_Literal
     (Data      : String;
      Value     : out Ada.Strings.Unbounded.Unbounded_String;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @param Consumed Subprogram parameter.
   --  @return Subprogram result.

   function Encode_Header_Block_Prefix return String;
   --  GNATdoc contract.
   --  @return Subprogram result.
   function Decode_Header_Block_Prefix
     (Data      : String;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Consumed Subprogram parameter.
   --  @return Subprogram result.
   --  Accept only the experimental HTTP/3 no-dynamic-table prefix: required insert
   --  count = 0 and base = 0. Nonzero values require dynamic-table state and
   --  are rejected deterministically.

   function Validate_Header_Name (Name : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.

   function Encode_Literal_Field_Line
     (Name      : String;
      Value     : String;
      Sensitive : Boolean;
      Output    : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Name Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @param Sensitive Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.

   function Decode_Literal_Field_Line
     (Data      : String;
      Field     : out Header_Field;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Field Subprogram parameter.
   --  @param Consumed Subprogram parameter.
   --  @return Subprogram result.

end Http_Client.HTTP3.QPACK;
