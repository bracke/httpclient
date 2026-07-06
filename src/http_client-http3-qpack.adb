with Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;
with Http_Client.Errors;

package body Http_Client.HTTP3.QPACK is
   use type Http_Client.Errors.Result_Status;
   use type Interfaces.Unsigned_64;

   function Ch (V : Natural) return Character is
   begin
      return Character'Val (V mod 256);
   end Ch;

   function Encode_Integer
     (Value        : QPACK_Integer;
      Prefix_Bits  : Positive;
      Prefix_Mask  : Natural) return String is
      Max_Prefix : constant Interfaces.Unsigned_64 := 2 ** Prefix_Bits - 1;
      V          : Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Value);
      Outp       : Unbounded_String := Null_Unbounded_String;
   begin
      if Prefix_Bits > 8 or else Prefix_Mask > 255 then
         return "";
      end if;

      if V < Max_Prefix then
         Append (Outp, Ch (Prefix_Mask + Natural (V)));
      else
         Append (Outp, Ch (Prefix_Mask + Natural (Max_Prefix)));
         V := V - Max_Prefix;
         while V >= 128 loop
            Append (Outp, Ch (Natural (V mod 128) + 128));
            V := V / 128;
         end loop;
         Append (Outp, Ch (Natural (V)));
      end if;
      return To_String (Outp);
   end Encode_Integer;

   function Decode_Integer
     (Data        : String;
      Prefix_Bits : Positive;
      Value       : out QPACK_Integer;
      Consumed    : out Natural) return Http_Client.Errors.Result_Status is
      Max_Prefix : constant Interfaces.Unsigned_64 := 2 ** Prefix_Bits - 1;
      First      : Interfaces.Unsigned_64;
      M          : Interfaces.Unsigned_64 := 0;
      I          : Natural;
      B          : Interfaces.Unsigned_64;
   begin
      Value := 0;
      Consumed := 0;
      if Data'Length = 0 or else Prefix_Bits > 8 then
         return Http_Client.Errors.Incomplete_Message;
      end if;
      First := Interfaces.Unsigned_64 (Character'Pos (Data (Data'First))) mod (2 ** Prefix_Bits);
      if First < Max_Prefix then
         Value := QPACK_Integer (First);
         Consumed := 1;
         return Http_Client.Errors.Ok;
      end if;

      Value := QPACK_Integer (Max_Prefix);
      I := Data'First + 1;
      while I <= Data'Last loop
         B := Interfaces.Unsigned_64 (Character'Pos (Data (I)));
         if M >= 63 then
            return Http_Client.Errors.HTTP3_QPACK_Error;
         end if;
         Value := QPACK_Integer (Interfaces.Unsigned_64 (Value) + ((B mod 128) * (2 ** Natural (M))));
         Consumed := I - Data'First + 1;
         if B < 128 then
            return Http_Client.Errors.Ok;
         end if;
         M := M + 7;
         I := I + 1;
      end loop;
      return Http_Client.Errors.Incomplete_Message;
   exception
      when Constraint_Error =>
         return Http_Client.Errors.HTTP3_QPACK_Error;
   end Decode_Integer;

   function Encode_String_Literal (Value : String) return String is
   begin
      return Encode_Integer (QPACK_Integer (Value'Length), 7, 0) & Value;
   end Encode_String_Literal;

   function Decode_String_Literal
     (Data      : String;
      Value     : out Ada.Strings.Unbounded.Unbounded_String;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status is
      Len : QPACK_Integer;
      Used : Natural;
      Status : Http_Client.Errors.Result_Status;
      First : Natural;
   begin
      Value := Null_Unbounded_String;
      Consumed := 0;
      if Data'Length = 0 then
         return Http_Client.Errors.Incomplete_Message;
      elsif Character'Pos (Data (Data'First)) >= 128 then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      end if;
      Status := Decode_Integer (Data, 7, Len, Used);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Len > Interfaces.Unsigned_64 (Natural'Last) then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      elsif Data'Length < Used + Natural (Len) then
         return Http_Client.Errors.Incomplete_Message;
      end if;
      First := Data'First + Used;
      if Len > 0 then
         Value := To_Unbounded_String (Data (First .. First + Natural (Len) - 1));
      end if;
      Consumed := Used + Natural (Len);
      return Http_Client.Errors.Ok;
   end Decode_String_Literal;

   function Encode_Header_Block_Prefix return String is
   begin
      return Character'Val (0) & Character'Val (0);
   end Encode_Header_Block_Prefix;

   function Decode_Header_Block_Prefix
     (Data      : String;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status is
      Required_Insert_Count : QPACK_Integer;
      Base                  : QPACK_Integer;
      Used1                 : Natural;
      Used2                 : Natural;
      Status                : Http_Client.Errors.Result_Status;
   begin
      Consumed := 0;
      Status := Decode_Integer (Data, 8, Required_Insert_Count, Used1);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Required_Insert_Count /= 0 then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      end if;

      if Data'Length < Used1 + 1 then
         return Http_Client.Errors.Incomplete_Message;
      elsif Character'Pos (Data (Data'First + Used1)) >= 128 then
         --  A set sign bit would require dynamic-table base handling, which
         --  is deliberately out of scope for the experimental QPACK subset.
         return Http_Client.Errors.HTTP3_QPACK_Error;
      end if;

      Status := Decode_Integer (Data (Data'First + Used1 .. Data'Last), 7, Base, Used2);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Base /= 0 then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      end if;

      Consumed := Used1 + Used2;
      return Http_Client.Errors.Ok;
   end Decode_Header_Block_Prefix;

   function Validate_Header_Name (Name : String) return Http_Client.Errors.Result_Status is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      if Name'Length = 0 or else Name /= Lower then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      elsif Name = "connection" or else Name = "keep-alive"
        or else Name = "proxy-connection" or else Name = "transfer-encoding"
        or else Name = "upgrade"
      then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Validate_Header_Name;

   function Encode_Literal_Field_Line
     (Name      : String;
      Value     : String;
      Sensitive : Boolean;
      Output    : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status is
      Status : constant Http_Client.Errors.Result_Status := Validate_Header_Name (Name);
   begin
      Output := Null_Unbounded_String;
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      --  001N.... literal field line with literal name. Sensitive headers
      --  are encoded with the QPACK never-indexed bit set. Huffman remains
      --  disabled in this experimental HTTP/3 subset.
      Output := To_Unbounded_String
        (Character'Val (if Sensitive then 16#30# else 16#20#)
         & Encode_String_Literal (Name)
         & Encode_String_Literal (Value));
      return Http_Client.Errors.Ok;
   end Encode_Literal_Field_Line;

   function Decode_Literal_Field_Line
     (Data      : String;
      Field     : out Header_Field;
      Consumed  : out Natural) return Http_Client.Errors.Result_Status is
      Name, Val : Unbounded_String;
      Used_Name, Used_Val : Natural;
      Status : Http_Client.Errors.Result_Status;
      Pos : Natural;
   begin
      Field := (Name => Null_Unbounded_String, Value => Null_Unbounded_String, Sensitive => False);
      Consumed := 0;
      if Data'Length = 0 then
         return Http_Client.Errors.Incomplete_Message;
      elsif (Character'Pos (Data (Data'First)) / 32) /= 1 then
         return Http_Client.Errors.HTTP3_QPACK_Error;
      elsif ((Character'Pos (Data (Data'First)) / 8) mod 2) /= 0 then
         --  Huffman-coded literal names are out of scope in experimental HTTP/3 foundation.
         return Http_Client.Errors.HTTP3_QPACK_Error;
      end if;
      Pos := Data'First + 1;
      Status := Decode_String_Literal (Data (Pos .. Data'Last), Name, Used_Name);
      if Status /= Http_Client.Errors.Ok then return Status; end if;
      Pos := Pos + Used_Name;
      if Pos > Data'Last then return Http_Client.Errors.Incomplete_Message; end if;
      Status := Decode_String_Literal (Data (Pos .. Data'Last), Val, Used_Val);
      if Status /= Http_Client.Errors.Ok then return Status; end if;
      Status := Validate_Header_Name (To_String (Name));
      if Status /= Http_Client.Errors.Ok then return Status; end if;
      Field :=
        (Name      => Name,
         Value     => Val,
         Sensitive => ((Character'Pos (Data (Data'First)) / 16) mod 2) /= 0);
      Consumed := 1 + Used_Name + Used_Val;
      return Http_Client.Errors.Ok;
   end Decode_Literal_Field_Line;
end Http_Client.HTTP3.QPACK;
