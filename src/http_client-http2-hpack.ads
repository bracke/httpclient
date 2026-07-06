with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;

package Http_Client.HTTP2.HPACK is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Bounded HPACK encoder/decoder for the conservative bounded HTTP/2 paths.
   --
   --  The decoder supports the HPACK static table, bounded dynamic table,
   --  indexed header fields, literal fields with incremental indexing,
   --  literal fields without indexing, literal fields never indexed, and
   --  dynamic table size updates. Raw and HPACK static-Huffman string
   --  literals are decoded. Malformed Huffman payloads fail deterministically
   --  with HPACK_Huffman_Error. The encoder still emits raw non-Huffman
   --  string literals only.
   --
   --  Dynamic-table storage is bounded by Max_Dynamic_Table_Size and by the
   --  latest peer size update. Header-list growth is bounded by
   --  Max_Header_List_Size using the HPACK header-list accounting model
   --  (name length + value length + 32 octets per field). Sensitive request
   --  fields should be encoded with
   --  Encode_Header_Block, which never indexes authorization, cookie, or
   --  proxy-authorization fields.

   type Decoder is private;
   --  Stateful HPACK decoder containing the bounded dynamic table.

   type Encoder is private;
   --  Conservative HPACK encoder. It tracks the peer table-size limit but may
   --  choose literal-without-indexing for all fields.

   function Create_Decoder
     (Max_Dynamic_Table_Size : Natural := 4_096;
      Max_Header_List_Size   : Natural := 65_536) return Decoder;
   --  GNATdoc contract.
   --  @param Max_Dynamic_Table_Size Subprogram parameter.
   --  @param Max_Header_List_Size Subprogram parameter.
   --  @return Subprogram result.
   --  Create a decoder with explicit dynamic-table and header-list bounds.

   function Create_Encoder
     (Peer_Dynamic_Table_Size : Natural := 4_096) return Encoder;
   --  GNATdoc contract.
   --  @param Peer_Dynamic_Table_Size Subprogram parameter.
   --  @return Subprogram result.
   --  Create an encoder using the peer SETTINGS_HEADER_TABLE_SIZE value.

   procedure Set_Peer_Dynamic_Table_Size
     (Item : in out Encoder;
      Size : Natural);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Size Subprogram parameter.
   --  Record the peer-advertised encoder dynamic-table size limit.

   function Encode_Integer
     (Value       : Natural;
      Prefix_Bits : Positive;
      High_Bits   : Natural := 0) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @param Prefix_Bits Subprogram parameter.
   --  @param High_Bits Subprogram parameter.
   --  @return Subprogram result.
   --  Encode Value using the HPACK variable-length integer format.

   function Decode_Integer
     (Data        : String;
      Position    : in out Positive;
      Prefix_Bits : Positive;
      Value       : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Position Subprogram parameter.
   --  @param Prefix_Bits Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Decode an HPACK integer and advance Position past the encoded bytes.
   --  Malformed, truncated, overflowing, or non-minimal continuation encodings
   --  are rejected.

   function Encode_Header_Block
     (Item    : in out Encoder;
      Headers : Http_Client.Headers.Header_List;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Headers Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Encode a complete header block. The encoder emits literal
   --  non-Huffman fields without indexing, and uses never-indexed literals for
   --  authorization, cookie, and proxy-authorization.

   function Decode_Header_Block
     (Item    : in out Decoder;
      Block   : String;
      Headers : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Block Subprogram parameter.
   --  @param Headers Subprogram parameter.
   --  @return Subprogram result.
   --  Decode a complete HPACK header block into ordered HTTP/2 headers.

   function Encode_Literal_Without_Indexing
     (Headers : Http_Client.Headers.Header_List;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Headers Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Compatibility wrapper around Encode_Header_Block.

   function Decode_Literal_Without_Indexing
     (Block                 : String;
      Max_Header_List_Size  : Natural;
      Headers               : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Block Subprogram parameter.
   --  @param Max_Header_List_Size Subprogram parameter.
   --  @param Headers Subprogram parameter.
   --  @return Subprogram result.
   --  Compatibility wrapper around Decode_Header_Block using an empty decoder.

private
   use Ada.Strings.Unbounded;

   type Header_Field is record
      Name  : Unbounded_String;
      Value : Unbounded_String;
      Size  : Natural := 0;
   end record;

   Max_Dynamic_Entries : constant Natural := 128;

   type Dynamic_Table is array (Positive range 1 .. Max_Dynamic_Entries) of Header_Field;

   type Decoder is record
      Table                  : Dynamic_Table;
      Count                  : Natural := 0;
      Current_Size           : Natural := 0;
      Max_Dynamic_Table_Size : Natural := 4_096;
      Effective_Table_Size   : Natural := 4_096;
      Max_Header_List_Size   : Natural := 65_536;
      Saw_Field              : Boolean := False;
   end record;

   type Encoder is record
      Peer_Dynamic_Table_Size : Natural := 4_096;
   end record;
end Http_Client.HTTP2.HPACK;
