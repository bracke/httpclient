with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Http_Client.HTTP2.Frames;

package body Http_Client.HTTP2_Execution_Common is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Request_Bodies.Body_Kind;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;

   function Has_Flag (Flags : Natural; Mask : Natural) return Boolean is
   begin
      return (Flags / Mask) mod 2 = 1;
   end Has_Flag;

   function U8 (C : Character) return Natural is
   begin
      return Character'Pos (C);
   end U8;

   function B (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end B;

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

   function Parse_Natural (Text : String; Value : out Natural) return Boolean is
      Acc : Natural := 0;
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;
      for C of Text loop
         if C not in '0' .. '9' then
            return False;
         end if;
         declare
            Digit : constant Natural := Character'Pos (C) - Character'Pos ('0');
         begin
            if Acc > (Natural'Last - Digit) / 10 then
               return False;
            end if;
            Acc := Acc * 10 + Digit;
         end;
      end loop;
      Value := Acc;
      return True;
   end Parse_Natural;

   function Response_Body_Is_Disallowed
     (Request_Method : Http_Client.Types.Method_Name;
      Code           : Http_Client.Types.Status_Code) return Boolean is
   begin
      return Request_Method = Http_Client.Types.HEAD
        or else (Code >= 100 and then Code <= 199)
        or else Code = 204
        or else Code = 205
        or else Code = 304;
   end Response_Body_Is_Disallowed;

   function Natural_Image_No_Leading_Blank (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image_No_Leading_Blank;

   function Serialize_Frame
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String
   is
      H : constant Http_Client.HTTP2.Frames.Frame_Header :=
        (Length       => Http_Client.HTTP2.Frames.Frame_Length (Payload'Length),
         Kind         => Kind,
         Raw_Type     => Http_Client.HTTP2.Frames.Type_Code (Kind),
         Flags        => Http_Client.HTTP2.Frames.Byte_Value (Flags),
         Reserved_Bit => False,
         Stream       => Http_Client.HTTP2.Frames.Stream_ID (Stream));
   begin
      return Http_Client.HTTP2.Frames.Serialize_Header (H) & Payload;
   end Serialize_Frame;

   function Serialize_Window_Update
     (Stream    : Natural;
      Increment : Natural) return String
   is
   begin
      if Increment = 0 or else Increment > 16#7FFF_FFFF# then
         return "";
      end if;

      return Serialize_Frame
        (Http_Client.HTTP2.Frames.WINDOW_UPDATE,
         0,
         Stream,
         String'
           (1 => B (Increment / 16#01_00_00_00#),
            2 => B (Increment / 16#00_01_00_00#),
            3 => B (Increment / 16#00_00_01_00#),
            4 => B (Increment)));
   end Serialize_Window_Update;

   function Serialize_Data_Frames
     (Payload            : String;
      Max_Frame_Size     : Natural;
      End_Stream_On_Last : Boolean := True) return String
   is
      Outp  : Unbounded_String := Null_Unbounded_String;
      First : Integer := Payload'First;
      Last  : Integer;
   begin
      if Payload'Length = 0 then
         return "";
      end if;

      while First <= Payload'Last loop
         Last := Integer'Min
           (Payload'Last, First + Integer (Max_Frame_Size) - 1);
         Append
           (Outp,
            Serialize_Frame
              (Http_Client.HTTP2.Frames.DATA,
               (if Last = Payload'Last and then End_Stream_On_Last then 16#01# else 0),
               1,
               Payload (First .. Last)));
         First := Last + 1;
      end loop;

      return To_String (Outp);
   end Serialize_Data_Frames;

   function Parse_Peer_Settings
     (Payload : String;
      Peer    : in out Peer_Settings) return Http_Client.Errors.Result_Status
   is
      P  : Integer := Payload'First;
      ID : Natural;
      V  : Natural;
   begin
      if Payload'Length mod 6 /= 0 then
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      while P <= Payload'Last loop
         ID := U8 (Payload (P)) * 16#100# + U8 (Payload (P + 1));
         if not U32_Fits_Natural (Payload (P + 2)) then
            return Http_Client.Errors.HTTP2_Unsupported_Feature;
         end if;
         V := U32_Value
           (Payload (P + 2), Payload (P + 3), Payload (P + 4), Payload (P + 5));

         case ID is
            when 16#0001# =>
               Peer.Header_Table_Size := V;
            when 16#0002# =>
               if V > 1 then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
            when 16#0004# =>
               Peer.Initial_Window_Size := V;
            when 16#0005# =>
               if V < 16_384 or else V > 16#00FF_FFFF# then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
               Peer.Max_Frame_Size := V;
            when 16#0006# =>
               Peer.Max_Header_List_Size := V;
            when others =>
               null;
         end case;

         P := P + 6;
      end loop;

      return Http_Client.Errors.Ok;
   end Parse_Peer_Settings;

   function Encoded_Header_List_Size
     (Headers : Http_Client.Headers.Header_List;
      Size    : out Natural) return Boolean
   is
      Total : Natural := 0;
      Field : Natural;
   begin
      Size := 0;
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         declare
            Name  : constant String := Http_Client.Headers.Name_At (Headers, I);
            Value : constant String := Http_Client.Headers.Value_At (Headers, I);
         begin
            Field := Name'Length + Value'Length + 32;
         end;

         if Field > Natural'Last - Total then
            return False;
         end if;
         Total := Total + Field;
      end loop;

      Size := Total;
      return True;
   end Encoded_Header_List_Size;

   function Ensure_Content_Length_Header
     (Headers     : in out Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
   is
   begin
      if Body_Length > 0
        and then not Http_Client.Headers.Contains (Headers, "content-length")
      then
         return Http_Client.Headers.Set
           (Headers, "content-length", Natural_Image_No_Leading_Blank (Body_Length));
      end if;

      return Http_Client.Errors.Ok;
   end Ensure_Content_Length_Header;

   function Request_Content_Length_Is_Valid
     (Headers     : Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
   is
      Declared : Natural := 0;
   begin
      if Http_Client.Headers.Count (Headers, "content-length") > 1 then
         return Http_Client.Errors.Body_Length_Mismatch;
      end if;

      if Http_Client.Headers.Contains (Headers, "content-length") then
         if not Parse_Natural
           (Http_Client.Headers.Get (Headers, "content-length"), Declared)
         then
            return Http_Client.Errors.Body_Length_Mismatch;
         elsif Declared /= Body_Length then
            return Http_Client.Errors.Body_Length_Mismatch;
         end if;
      end if;

      return Http_Client.Errors.Ok;
   end Request_Content_Length_Is_Valid;

   function Collect_Request_Body
     (Req_Body  : Http_Client.Request_Bodies.Request_Body;
      Max_Bytes : Natural;
      Output    : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Kind      : constant Http_Client.Request_Bodies.Body_Kind :=
        Http_Client.Request_Bodies.Kind (Req_Body);
      Declared  : Natural := 0;
      Has_Len   : constant Boolean :=
        Http_Client.Request_Bodies.Declared_Length (Req_Body, Declared);
      Total     : Natural := 0;
      Buffer    : String (1 .. 8_192);
      Count     : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      Output := Null_Unbounded_String;

      case Kind is
         when Http_Client.Request_Bodies.Empty_Body =>
            return Http_Client.Errors.Ok;

         when Http_Client.Request_Bodies.Buffered_Body =>
            declare
               Payload : constant String :=
                 Http_Client.Request_Bodies.Buffered_Payload (Req_Body);
            begin
               if Payload'Length > Max_Bytes then
                  return Http_Client.Errors.HTTP2_Flow_Control_Error;
               end if;
               Output := To_Unbounded_String (Payload);
               return Http_Client.Errors.Ok;
            end;

         when Http_Client.Request_Bodies.Fixed_Length_Stream |
              Http_Client.Request_Bodies.Unknown_Length_Stream =>
            if not Http_Client.Request_Bodies.Has_Producer (Req_Body) then
               return Http_Client.Errors.Invalid_Request;
            elsif Has_Len and then Declared > Max_Bytes then
               return Http_Client.Errors.HTTP2_Flow_Control_Error;
            end if;

            loop
               Status := Http_Client.Request_Bodies.Read_Next
                 (Req_Body, Buffer, Count);
               if Status /= Http_Client.Errors.Ok then
                  Output := Null_Unbounded_String;
                  return Status;
               end if;

               exit when Count = 0;

               if Count > Max_Bytes - Total then
                  Output := Null_Unbounded_String;
                  return Http_Client.Errors.HTTP2_Flow_Control_Error;
               end if;

               Append (Output, Buffer (1 .. Count));
               Total := Total + Count;
            end loop;

            if Has_Len and then Total /= Declared then
               Output := Null_Unbounded_String;
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;

            return Http_Client.Errors.Ok;
      end case;
   end Collect_Request_Body;
end Http_Client.HTTP2_Execution_Common;
