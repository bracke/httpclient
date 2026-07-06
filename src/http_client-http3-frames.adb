with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Http_Client.Errors;

package body Http_Client.HTTP3.Frames
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;
   use type Interfaces.Unsigned_64;

   function B (C : Character) return Interfaces.Unsigned_64 is
   begin
      return Interfaces.Unsigned_64 (Character'Pos (C));
   end B;

   function Ch (V : Interfaces.Unsigned_64) return Character is
   begin
      return Character'Val (Natural (V and 16#FF#));
   end Ch;

   function Type_Code (Kind : Frame_Type; Raw_Type : Varint_Value := 0)
      return Varint_Value is
   begin
      case Kind is
         when DATA         => return 16#00#;
         when HEADERS      => return 16#01#;
         when CANCEL_PUSH  => return 16#03#;
         when SETTINGS     => return 16#04#;
         when PUSH_PROMISE => return 16#05#;
         when GOAWAY       => return 16#07#;
         when MAX_PUSH_ID  => return 16#0D#;
         when UNKNOWN      => return Raw_Type;
      end case;
   end Type_Code;

   function Kind_From_Code (Code : Varint_Value) return Frame_Type is
   begin
      case Code is
         when 16#00# => return DATA;
         when 16#01# => return HEADERS;
         when 16#03# => return CANCEL_PUSH;
         when 16#04# => return SETTINGS;
         when 16#05# => return PUSH_PROMISE;
         when 16#07# => return GOAWAY;
         when 16#0D# => return MAX_PUSH_ID;
         when others => return UNKNOWN;
      end case;
   end Kind_From_Code;

   function Encoded_Length (Value : Varint_Value) return Positive is
   begin
      if Value <= 16#3F# then
         return 1;
      elsif Value <= 16#3FFF# then
         return 2;
      elsif Value <= 16#3FFF_FFFF# then
         return 4;
      else
         return 8;
      end if;
   end Encoded_Length;

   function Encode_Varint (Value : Varint_Value) return String is
      V : constant Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
   begin
      if Value <= 16#3F# then
         return String'(1 => Ch (V));
      elsif Value <= 16#3FFF# then
         return String'
           (1 => Ch (16#40# or ((V / 256) and 16#3F#)),
            2 => Ch (V));
      elsif Value <= 16#3FFF_FFFF# then
         return String'
           (1 => Ch (16#80# or ((V / 16#01_00_00_00#) and 16#3F#)),
            2 => Ch (V / 16#01_00_00#),
            3 => Ch (V / 16#01_00#),
            4 => Ch (V));
      else
         return String'
           (1 => Ch (16#C0# or ((V / 16#01_00_00_00_00_00_00#) and 16#3F#)),
            2 => Ch (V / 16#01_00_00_00_00_00#),
            3 => Ch (V / 16#01_00_00_00_00#),
            4 => Ch (V / 16#01_00_00_00#),
            5 => Ch (V / 16#01_00_00#),
            6 => Ch (V / 16#01_00#),
            7 => Ch (V / 16#01#),
            8 => Ch (V));
      end if;
   end Encode_Varint;

   function Decode_Varint
     (Data      : String;
      Value     : out Varint_Value;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      First : Interfaces.Unsigned_64;
      Len   : Positive;
      V     : Interfaces.Unsigned_64;
   begin
      Value := 0;
      Consumed := 0;
      if Data'Length = 0 then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      First := B (Data (Data'First));
      case Natural (First / 64) is
         when 0 => Len := 1;
         when 1 => Len := 2;
         when 2 => Len := 4;
         when others => Len := 8;
      end case;

      if Data'Length < Len then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      V := First and 16#3F#;
      for I in 2 .. Len loop
         V := V * 256 + B (Data (Data'First + I - 1));
      end loop;

      --  QUIC variable-length integers encode the selected width in the top
      --  two bits. The protocol does not require the shortest possible width
      --  on the wire, so decoding must accept otherwise well-formed wider
      --  encodings even though this package serializes shortest encodings.
      Value := Varint_Value (V);
      Consumed := Len;
      return Http_Client.Errors.Ok;
   end Decode_Varint;

   function Serialize_Frame
     (Header  : Frame_Header;
      Payload : String;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      Code : constant Varint_Value := Type_Code (Header.Kind, Header.Raw_Type);
   begin
      if Header.Length /= Payload'Length then
         return Http_Client.Errors.HTTP3_Frame_Error;
      elsif Header.Kind = UNKNOWN and then Kind_From_Code (Header.Raw_Type) /= UNKNOWN then
         return Http_Client.Errors.HTTP3_Frame_Error;
      end if;

      Output := To_Unbounded_String
        (Encode_Varint (Code) & Encode_Varint (Varint_Value (Payload'Length)) & Payload);
      return Http_Client.Errors.Ok;
   end Serialize_Frame;

   function Parse_Frame
     (D : String;
      Max_Frame_Size : Natural;
      Item           : out Frame) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      Code      : Varint_Value;
      Len_Value : Varint_Value;
      Used1     : Natural;
      Used2     : Natural;
      Status    : Http_Client.Errors.Result_Status;
      Payload_First : Natural;
   begin
      Item.Header := (Kind => DATA, Raw_Type => 0, Length => 0);
      Item.Payload := Null_Unbounded_String;

      Status := Decode_Varint (D, Code, Used1);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Decode_Varint (D (D'First + Used1 .. D'Last), Len_Value, Used2);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Len_Value > Interfaces.Unsigned_64 (Natural'Last)
        or else Natural (Len_Value) > Max_Frame_Size
      then
         return Http_Client.Errors.Response_Too_Large;
      end if;

      Payload_First := D'First + Used1 + Used2;
      if D'Length < Used1 + Used2 + Natural (Len_Value) then
         return Http_Client.Errors.Incomplete_Message;
      elsif D'Length > Used1 + Used2 + Natural (Len_Value) then
         return Http_Client.Errors.HTTP3_Frame_Error;
      end if;

      Item.Header :=
        (Kind => Kind_From_Code (Code), Raw_Type => Code, Length => Natural (Len_Value));
      if Natural (Len_Value) > 0 then
         Item.Payload := To_Unbounded_String
           (D (Payload_First .. Payload_First + Natural (Len_Value) - 1));
      end if;
      return Http_Client.Errors.Ok;
   end Parse_Frame;

   function Skip_Unknown_Frame
     (Header         : Frame_Header;
      Max_Frame_Size : Natural) return Http_Client.Errors.Result_Status is
   begin
      if Header.Kind /= UNKNOWN then
         return Http_Client.Errors.HTTP3_Frame_Error;
      elsif Header.Length > Max_Frame_Size then
         return Http_Client.Errors.Response_Too_Large;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Skip_Unknown_Frame;

   function Parse_Goaway_Payload
     (Payload   : String;
      Stream_ID : out Varint_Value) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      Used   : Natural;
      Status : Http_Client.Errors.Result_Status;
   begin
      Stream_ID := 0;
      Status := Decode_Varint (Payload, Stream_ID, Used);
      if Status /= Http_Client.Errors.Ok then
         return Http_Client.Errors.HTTP3_Goaway;
      elsif Used /= Payload'Length then
         return Http_Client.Errors.HTTP3_Goaway;
      elsif (Interfaces.Unsigned_64 (Stream_ID) mod 4) /= 0 then
         return Http_Client.Errors.HTTP3_Goaway;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Parse_Goaway_Payload;

end Http_Client.HTTP3.Frames;
