with Ada.Strings.Unbounded;
with Interfaces;

with Http_Client.Errors;

package Http_Client.HTTP3.Frames
  with SPARK_Mode => On
is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  Strict bounded HTTP/3 frame and QUIC variable-length integer modeling.
   --
   --  Serialization uses shortest QUIC varint encodings. Parsing follows
   --  QUIC varint width bits, accepts protocol-valid non-shortest encodings,
   --  and rejects truncated varints, oversized frame payloads, and incomplete
   --  frame payloads before allocating unbounded memory.

   subtype Byte_Value is Natural range 0 .. 255;
   subtype Varint_Value is Interfaces.Unsigned_64 range 0 .. 16#3FFF_FFFF_FFFF_FFFF#;

   type Frame_Type is
     (DATA,
      HEADERS,
      CANCEL_PUSH,
      SETTINGS,
      PUSH_PROMISE,
      GOAWAY,
      MAX_PUSH_ID,
      UNKNOWN);

   type Frame_Header is record
      Kind       : Frame_Type := DATA;
      Raw_Type   : Varint_Value := 0;
      Length     : Natural := 0;
   end record;

   type Frame is record
      Header  : Frame_Header;
      Payload : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   function Type_Code (Kind : Frame_Type; Raw_Type : Varint_Value := 0)
      return Varint_Value;
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @param Raw_Type Subprogram parameter.
   --  @return Subprogram result.
   function Kind_From_Code (Code : Varint_Value) return Frame_Type;
   --  GNATdoc contract.
   --  @param Code Subprogram parameter.
   --  @return Subprogram result.

   function Encoded_Length (Value : Varint_Value) return Positive;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   function Encode_Varint (Value : Varint_Value) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   function Decode_Varint
     (Data      : String;
      Value     : out Varint_Value;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Value Subprogram parameter.
   --  @param Consumed Subprogram parameter.
   --  @return Subprogram result.

   function Serialize_Frame
     (Header  : Frame_Header;
      Payload : String;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.

   function Parse_Frame
     (D : String;
      Max_Frame_Size : Natural;
      Item           : out Frame) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param D Encoded frame bytes to parse.
   --  @param Max_Frame_Size Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.

   function Skip_Unknown_Frame
     (Header         : Frame_Header;
      Max_Frame_Size : Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @param Max_Frame_Size Subprogram parameter.
   --  @return Subprogram result.

   function Parse_Goaway_Payload
     (Payload   : String;
      Stream_ID : out Varint_Value) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Payload Subprogram parameter.
   --  @param Stream_ID Subprogram parameter.
   --  @return Subprogram result.
   --  Parse a GOAWAY payload containing exactly one QUIC varint. Server
   --  GOAWAY values for this client model must identify a client-initiated
   --  bidirectional stream, whose low two bits are zero.

end Http_Client.HTTP3.Frames;
