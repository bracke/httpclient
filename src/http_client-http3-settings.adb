with Interfaces;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Http_Client.HTTP3.Frames;
with Http_Client.Errors;

package body Http_Client.HTTP3.Settings
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;
   use type Interfaces.Unsigned_64;

   function Validate (Settings : Settings_Record)
      return Http_Client.Errors.Result_Status is
   begin
      if Settings.QPACK_Max_Table_Capacity > 0
        or else Settings.QPACK_Blocked_Streams > 0
        or else Settings.Max_Field_Section_Size = 0
        or else Settings.Enable_Connect_Protocol
        or else Settings.H3_Datagram
      then
         return Http_Client.Errors.HTTP3_Settings_Error;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Validate;

   function Serialize_Payload
     (Settings : Settings_Record;
      Output   : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      Status : constant Http_Client.Errors.Result_Status := Validate (Settings);
   begin
      Output := Null_Unbounded_String;
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (SETTINGS_QPACK_MAX_TABLE_CAPACITY)));
      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (Settings.QPACK_Max_Table_Capacity)));
      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (SETTINGS_QPACK_BLOCKED_STREAMS)));
      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (Settings.QPACK_Blocked_Streams)));
      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (SETTINGS_MAX_FIELD_SECTION_SIZE)));
      Append (Output, Http_Client.HTTP3.Frames.Encode_Varint
        (Http_Client.HTTP3.Frames.Varint_Value (Settings.Max_Field_Section_Size)));
      return Http_Client.Errors.Ok;
   end Serialize_Payload;

   function Parse_Payload
     (Payload  : String;
      Settings : out Settings_Record)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
      Pos : Natural := Payload'First;
      ID  : Http_Client.HTTP3.Frames.Varint_Value;
      Val : Http_Client.HTTP3.Frames.Varint_Value;
      Used : Natural;
      Seen_QCap, Seen_QBlk, Seen_Max, Seen_Conn, Seen_Dgram : Boolean := False;
      Status : Http_Client.Errors.Result_Status;
   begin
      Settings := Default_Settings;
      while Pos <= Payload'Last loop
         Status := Http_Client.HTTP3.Frames.Decode_Varint (Payload (Pos .. Payload'Last), ID, Used);
         if Status /= Http_Client.Errors.Ok then return Http_Client.Errors.HTTP3_Settings_Error; end if;
         Pos := Pos + Used;
         if Pos > Payload'Last then return Http_Client.Errors.HTTP3_Settings_Error; end if;
         Status := Http_Client.HTTP3.Frames.Decode_Varint (Payload (Pos .. Payload'Last), Val, Used);
         if Status /= Http_Client.Errors.Ok then return Http_Client.Errors.HTTP3_Settings_Error; end if;
         Pos := Pos + Used;

         if Setting_ID (ID) = SETTINGS_QPACK_MAX_TABLE_CAPACITY then
            if Seen_QCap then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Seen_QCap := True;
            if Val > Interfaces.Unsigned_64 (Natural'Last) then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Settings.QPACK_Max_Table_Capacity := Natural (Val);
         elsif Setting_ID (ID) = SETTINGS_QPACK_BLOCKED_STREAMS then
            if Seen_QBlk then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Seen_QBlk := True;
            if Val > Interfaces.Unsigned_64 (Natural'Last) then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Settings.QPACK_Blocked_Streams := Natural (Val);
         elsif Setting_ID (ID) = SETTINGS_MAX_FIELD_SECTION_SIZE then
            if Seen_Max then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Seen_Max := True;
            if Val = 0
              or else Val > Interfaces.Unsigned_64 (Natural'Last)
            then
               return Http_Client.Errors.HTTP3_Settings_Error;
            end if;
            Settings.Max_Field_Section_Size := Natural (Val);
         elsif Setting_ID (ID) = SETTINGS_ENABLE_CONNECT_PROTOCOL then
            if Seen_Conn or else Val > 1 then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Seen_Conn := True;
            Settings.Enable_Connect_Protocol := Val = 1;
         elsif Setting_ID (ID) = SETTINGS_H3_DATAGRAM then
            if Seen_Dgram or else Val > 1 then return Http_Client.Errors.HTTP3_Settings_Error; end if;
            Seen_Dgram := True;
            Settings.H3_Datagram := Val = 1;
         else
            null;
         end if;
      end loop;
      return Validate (Settings);
   exception
      when Constraint_Error =>
         return Http_Client.Errors.HTTP3_Settings_Error;
   end Parse_Payload;
end Http_Client.HTTP3.Settings;
