with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Http_Client.HTTP2.Settings
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;

   function B (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end B;

   function U8 (C : Character) return Natural is
   begin
      return Character'Pos (C);
   end U8;

   function U32_Fits_Natural (B0 : Character) return Boolean is
   begin
      --  The project stores SETTINGS values in Natural. On common GNAT
      --  targets Natural'Last is 2**31 - 1, so values with the high bit set
      --  cannot be represented safely and are rejected deterministically.
      return U8 (B0) <= 127;
   end U32_Fits_Natural;

   function U32_Value
     (B0 : Character;
      B1 : Character;
      B2 : Character;
      B3 : Character) return Natural
   is
   begin
      return U8 (B0) * 16#01_00_00_00# +
             U8 (B1) * 16#00_01_00_00# +
             U8 (B2) * 16#00_00_01_00# +
             U8 (B3);
   end U32_Value;

   function Identifier_Code
     (Identifier : Setting_Identifier;
      Raw_ID     : Natural := 0) return Natural
   is
   begin
      case Identifier is
         when SETTINGS_HEADER_TABLE_SIZE      => return 16#0001#;
         when SETTINGS_ENABLE_PUSH            => return 16#0002#;
         when SETTINGS_MAX_CONCURRENT_STREAMS => return 16#0003#;
         when SETTINGS_INITIAL_WINDOW_SIZE    => return 16#0004#;
         when SETTINGS_MAX_FRAME_SIZE         => return 16#0005#;
         when SETTINGS_MAX_HEADER_LIST_SIZE   => return 16#0006#;
         when SETTINGS_UNKNOWN                => return Raw_ID;
      end case;
   end Identifier_Code;

   function Identifier_From_Code (Code : Natural) return Setting_Identifier is
   begin
      case Code is
         when 16#0001# => return SETTINGS_HEADER_TABLE_SIZE;
         when 16#0002# => return SETTINGS_ENABLE_PUSH;
         when 16#0003# => return SETTINGS_MAX_CONCURRENT_STREAMS;
         when 16#0004# => return SETTINGS_INITIAL_WINDOW_SIZE;
         when 16#0005# => return SETTINGS_MAX_FRAME_SIZE;
         when 16#0006# => return SETTINGS_MAX_HEADER_LIST_SIZE;
         when others   => return SETTINGS_UNKNOWN;
      end case;
   end Identifier_From_Code;

   function Validate
     (Item : Setting) return Http_Client.Errors.Result_Status
   is
   begin
      case Item.Identifier is
         when SETTINGS_ENABLE_PUSH =>
            if Item.Value > 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         when SETTINGS_INITIAL_WINDOW_SIZE =>
            null;

         when SETTINGS_MAX_FRAME_SIZE =>
            if Item.Value < 16_384 or else Item.Value > 16#00FF_FFFF# then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         when others =>
            null;
      end case;

      return Http_Client.Errors.Ok;
   end Validate;

   function Serialize
     (Items  : Setting_List;
      Output : out Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      S      : Unbounded_String := Null_Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
      ID     : Natural;
      V      : Natural;
   begin
      for Item of Items loop
         Status := Validate (Item);
         if Status /= Http_Client.Errors.Ok then
            Output := Null_Unbounded_String;
            return Status;
         end if;

         ID := Identifier_Code (Item.Identifier, Item.Raw_ID);
         V := Item.Value;
         Append (S, String'
           (1 => B (ID / 16#00_00_01_00#),
            2 => B (ID),
            3 => B (V / 16#01_00_00_00#),
            4 => B (V / 16#00_01_00_00#),
            5 => B (V / 16#00_00_01_00#),
            6 => B (V)));
      end loop;

      Output := S;
      return Http_Client.Errors.Ok;
   end Serialize;

   function Parse
     (Payload : String;
      Output  : out Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      P      : Integer := Payload'First;
      ID     : Natural;
      V      : Natural;
      Item   : Setting;
      Status : Http_Client.Errors.Result_Status;
      Text   : Unbounded_String := Null_Unbounded_String;
   begin
      if Payload'Length mod 6 /= 0 then
         Output := Null_Unbounded_String;
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      while P <= Payload'Last loop
         ID := U8 (Payload (P)) * 16#100# + U8 (Payload (P + 1));
         if not U32_Fits_Natural (Payload (P + 2)) then
            Output := Null_Unbounded_String;
            return Http_Client.Errors.HTTP2_Unsupported_Feature;
         end if;
         V := U32_Value
           (Payload (P + 2), Payload (P + 3),
            Payload (P + 4), Payload (P + 5));
         Item := (Identifier => Identifier_From_Code (ID),
                  Raw_ID     => ID,
                  Value      => V);
         Status := Validate (Item);
         if Status /= Http_Client.Errors.Ok then
            Output := Null_Unbounded_String;
            return Status;
         end if;

         Append (Text, Natural'Image (ID));
         Append (Text, "=");
         Append (Text, Natural'Image (V));
         Append (Text, ";");
         P := P + 6;
      end loop;

      Output := Text;
      return Http_Client.Errors.Ok;
   end Parse;

   function Initial_Settings_Payload
     (Header_Table_Size     : Natural := 4_096;
      Enable_Push           : Boolean := False;
      Max_Concurrent_Streams : Natural := 1;
      Initial_Window_Size   : Natural := 65_535;
      Max_Frame_Size        : Natural := 16_384;
      Max_Header_List_Size  : Natural := 65_536) return String
      with SPARK_Mode => Off
   is
      Push_Value : constant Natural := (if Enable_Push then 1 else 0);
      Payload    : Unbounded_String;
      Status     : Http_Client.Errors.Result_Status;
      pragma Unreferenced (Status);
   begin
      Status := Serialize
        ((1 => (SETTINGS_HEADER_TABLE_SIZE, 16#0001#, Header_Table_Size),
          2 => (SETTINGS_ENABLE_PUSH, 16#0002#, Push_Value),
          3 => (SETTINGS_MAX_CONCURRENT_STREAMS, 16#0003#, Max_Concurrent_Streams),
          4 => (SETTINGS_INITIAL_WINDOW_SIZE, 16#0004#, Initial_Window_Size),
          5 => (SETTINGS_MAX_FRAME_SIZE, 16#0005#, Max_Frame_Size),
          6 => (SETTINGS_MAX_HEADER_LIST_SIZE, 16#0006#, Max_Header_List_Size)),
         Payload);
      return To_String (Payload);
   end Initial_Settings_Payload;
end Http_Client.HTTP2.Settings;
