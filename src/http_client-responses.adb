with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Types;

package body Http_Client.Responses is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use Http_Client.Errors;

   CR : constant Character := Character'Val (13);
   LF : constant Character := Character'Val (10);
   HT : constant Character := Character'Val (9);

   Max_Status_Line_Length   : constant Natural := 8_192;
   Max_Header_Line_Length   : constant Natural := 8_192;
   Max_Header_Count         : constant Natural := 100;
   Max_Header_Section_Size  : constant Natural := 65_536;
   Max_In_Memory_Body_Size  : constant Natural := 16 * 1_024 * 1_024;

   function Default_Response return Response is
   begin
      return
        (Version_Value => HTTP_1_1,
         Status_Value  => 200,
         Reason_Value  => Null_Unbounded_String,
         Header_List   => Http_Client.Headers.Empty,
         Trailer_List  => Http_Client.Headers.Empty,
         Payload_Value => Null_Unbounded_String);
   end Default_Response;

   function Version_Image (Version : HTTP_Version) return String is
   begin
      case Version is
         when HTTP_1_0 =>
            return "HTTP/1.0";
         when HTTP_1_1 =>
            return "HTTP/1.1";
      end case;
   end Version_Image;

   function Reason_Phrase (Item : Response) return String is
   begin
      return To_String (Item.Reason_Value);
   end Reason_Phrase;


   function Version (Item : Response) return HTTP_Version is
   begin
      return Item.Version_Value;
   end Version;

   function Status_Code
     (Item : Response) return Http_Client.Types.Status_Code is
   begin
      return Item.Status_Value;
   end Status_Code;

   function Headers (Item : Response) return Http_Client.Headers.Header_List is
   begin
      return Item.Header_List;
   end Headers;

   function Trailers (Item : Response) return Http_Client.Headers.Header_List is
   begin
      return Item.Trailer_List;
   end Trailers;

   function Response_Body (Item : Response) return String is
   begin
      return To_String (Item.Payload_Value);
   end Response_Body;

   function Response_Body_Bytes
     (Item : Response) return Ada.Streams.Stream_Element_Array
   is
      Text : constant String := Response_Body (Item);
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for I in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (I - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (I)));
      end loop;
      return Data;
   end Response_Body_Bytes;

   function From_Components
     (Version : HTTP_Version;
      Status  : Http_Client.Types.Status_Code;
      Reason  : String;
      Headers : Http_Client.Headers.Header_List;
      Body_Text : String) return Response
   is
   begin
      return
        (Version_Value => Version,
         Status_Value  => Status,
         Reason_Value  => To_Unbounded_String (Reason),
         Header_List   => Headers,
         Trailer_List  => Http_Client.Headers.Empty,
         Payload_Value => To_Unbounded_String (Body_Text));
   end From_Components;

   function Copy_With_Headers
     (Item    : Response;
      Headers : Http_Client.Headers.Header_List) return Response
   is
      Result : Response := Item;
   begin
      Result.Header_List := Headers;
      return Result;
   end Copy_With_Headers;

   function Copy_With_Trailers
     (Item     : Response;
      Trailers : Http_Client.Headers.Header_List) return Response
   is
      Result : Response := Item;
   begin
      Result.Trailer_List := Trailers;
      return Result;
   end Copy_With_Trailers;

   function Lower (Text : String) return String is
      Result : String := Text;
   begin
      for Index in Result'Range loop
         if Result (Index) in 'A' .. 'Z' then
            Result (Index) := Character'Val
              (Character'Pos (Result (Index)) +
               Character'Pos ('a') - Character'Pos ('A'));
         end if;
      end loop;

      return Result;
   end Lower;

   function Has_Control (Text : String) return Boolean is
   begin
      for C of Text loop
         if Character'Pos (C) < 32
           or else Character'Pos (C) = 127
           or else (Character'Pos (C) >= 128
                    and then Character'Pos (C) <= 159)
         then
            return True;
         end if;
      end loop;

      return False;
   end Has_Control;

   function Parse_Decimal_Natural
     (Text  : String;
      Value : out Natural) return Boolean
   is
      Accumulator : Natural := 0;
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
            Digit : constant Natural :=
              Character'Pos (C) - Character'Pos ('0');
         begin
            if Accumulator > (Natural'Last - Digit) / 10 then
               return False;
            end if;

            Accumulator := Accumulator * 10 + Digit;
         end;
      end loop;

      Value := Accumulator;
      return True;
   end Parse_Decimal_Natural;

   function Trim_Optional_Whitespace (Text : String) return String is
      First : Integer := Text'First;
      Last  : Integer := Text'Last;
   begin
      if Text'Length = 0 then
         return "";
      end if;

      while First <= Text'Last
        and then (Text (First) = ' ' or else Text (First) = HT)
      loop
         First := First + 1;
      end loop;

      while Last >= First
        and then (Text (Last) = ' ' or else Text (Last) = HT)
      loop
         Last := Last - 1;
      end loop;

      if First > Last then
         return "";
      end if;

      return Text (First .. Last);
   end Trim_Optional_Whitespace;

   function Header
     (Item : Response;
      Name : String) return String is
   begin
      return Http_Client.Headers.Get (Item.Header_List, Name);
   end Header;

   function Has_Header
     (Item : Response;
      Name : String) return Boolean is
   begin
      return Http_Client.Headers.Contains (Item.Header_List, Name);
   end Has_Header;

   function Content_Type (Item : Response) return String is
   begin
      return Header (Item, "Content-Type");
   end Content_Type;

   function Has_Content_Type (Item : Response) return Boolean is
   begin
      return Has_Header (Item, "Content-Type");
   end Has_Content_Type;

   function Semicolon_Position (Text : String) return Natural is
   begin
      for Index in Text'Range loop
         if Text (Index) = ';' then
            return Index;
         end if;
      end loop;

      return 0;
   end Semicolon_Position;

   function Media_Type (Item : Response) return String is
      Value : constant String := Content_Type (Item);
      Semi  : constant Natural := Semicolon_Position (Value);
   begin
      if Value'Length = 0 then
         return "";
      elsif Semi = 0 then
         return Trim_Optional_Whitespace (Value);
      elsif Semi = Value'First then
         return "";
      else
         return Trim_Optional_Whitespace (Value (Value'First .. Semi - 1));
      end if;
   end Media_Type;

   function Charset (Item : Response) return String is
      Value : constant String := Content_Type (Item);
      Start : Integer;
   begin
      if Value'Length = 0 then
         return "";
      end if;

      declare
         Semi : constant Natural := Semicolon_Position (Value);
      begin
         if Semi = 0 or else Semi = Value'Last then
            return "";
         end if;

         Start := Semi + 1;
      end;

      while Start <= Value'Last loop
         declare
            Stop : Integer := Value'Last + 1;
         begin
            for Index in Start .. Value'Last loop
               if Value (Index) = ';' then
                  Stop := Index;
                  exit;
               end if;
            end loop;

            declare
               Part : constant String :=
                 Trim_Optional_Whitespace (Value (Start .. Stop - 1));
               Equal : Natural := 0;
            begin
               for Index in Part'Range loop
                  if Part (Index) = '=' then
                     Equal := Index;
                     exit;
                  end if;
               end loop;

               if Equal /= 0 then
                  declare
                     Name : constant String :=
                       Lower (Trim_Optional_Whitespace
                         (Part (Part'First .. Equal - 1)));
                     Raw_Value : constant String :=
                       Trim_Optional_Whitespace
                         (Part (Equal + 1 .. Part'Last));
                  begin
                     if Name = "charset" then
                        if Raw_Value'Length >= 2
                          and then Raw_Value (Raw_Value'First) = '"'
                          and then Raw_Value (Raw_Value'Last) = '"'
                        then
                           declare
                              Inner : constant String :=
                                Raw_Value
                                  (Raw_Value'First + 1 .. Raw_Value'Last - 1);
                           begin
                              return Trim_Optional_Whitespace (Inner);
                           end;
                        else
                           return Raw_Value;
                        end if;
                     end if;
                  end;
               elsif Lower (Part) = "charset" then
                  return "";
               end if;
            end;

            Start := Stop + 1;
         end;
      end loop;

      return "";
   end Charset;

   function Has_Charset (Item : Response) return Boolean is
   begin
      return Charset (Item)'Length > 0;
   end Has_Charset;

   function Line_End_At
     (Input : String;
      From  : Positive) return Natural
   is
   begin
      if From > Input'Last then
         return 0;
      end if;

      for Index in From .. Input'Last loop
         if Input (Index) = CR then
            if Index = Input'Last then
               return 0;
            end if;

            if Input (Index + 1) = LF then
               return Index;
            end if;

            return Natural'Last;
         elsif Input (Index) = LF then
            return Natural'Last;
         end if;
      end loop;

      return 0;
   end Line_End_At;

   function Parse_Status_Line
     (Line    : String;
      Version : out HTTP_Version;
      Code    : out Http_Client.Types.Status_Code;
      Reason  : out Unbounded_String) return Result_Status
   is
      Parsed_Code : Natural := 0;
   begin
      Version := HTTP_1_1;
      Code := 200;
      Reason := Null_Unbounded_String;

      if Line'Length > Max_Status_Line_Length then
         return Protocol_Error;
      end if;

      if Has_Control (Line) then
         return Protocol_Error;
      end if;

      if Line'Length < 12 then
         return Protocol_Error;
      end if;

      declare
         Token : constant String := Line (Line'First .. Line'First + 7);
      begin
         if Token = "HTTP/1.1" then
            Version := HTTP_1_1;
         elsif Token = "HTTP/1.0" then
            Version := HTTP_1_0;
         else
            return Protocol_Error;
         end if;
      end;

      if Line (Line'First + 8) /= ' ' then
         return Protocol_Error;
      end if;

      declare
         Code_Text : constant String :=
           Line (Line'First + 9 .. Line'First + 11);
      begin
         if not Parse_Decimal_Natural (Code_Text, Parsed_Code) then
            return Protocol_Error;
         end if;
      end;

      if Parsed_Code < 100 or else Parsed_Code > 599 then
         return Protocol_Error;
      end if;

      Code := Http_Client.Types.Status_Code (Parsed_Code);

      if Line'Length = 12 then
         return Ok;
      end if;

      if Line (Line'First + 12) /= ' ' then
         return Protocol_Error;
      end if;

      if Line'Length > 13 then
         Reason := To_Unbounded_String (Line (Line'First + 13 .. Line'Last));
      else
         Reason := Null_Unbounded_String;
      end if;

      return Ok;
   end Parse_Status_Line;

   function Body_Is_Disallowed
     (Status  : Http_Client.Types.Status_Code;
      Context : Parse_Context) return Boolean is
   begin
      return Context.Request_Was_HEAD
        or else (Status >= 100 and then Status <= 199)
        or else Status = 204
        or else Status = 205
        or else Status = 304;
   end Body_Is_Disallowed;

   function Parse_Header_Section
     (Input   : String;
      Result  : out Response;
      Context : Parse_Context := Default_Context)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced (Context);
      Cursor             : Positive := Input'First;
      Line_End           : Natural;
      Header_Count       : Natural := 0;
      Header_Bytes       : Natural := 0;
      Parsed_Version     : HTTP_Version := HTTP_1_1;
      Parsed_Status      : Http_Client.Types.Status_Code := 200;
      Parsed_Reason      : Unbounded_String := Null_Unbounded_String;
      Parsed_Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Status             : Result_Status;
   begin
      Result := Default_Response;

      if Input'Length = 0 then
         return Incomplete_Message;
      end if;

      Line_End := Line_End_At (Input, Cursor);
      if Line_End = 0 then
         return Incomplete_Message;
      elsif Line_End = Natural'Last then
         return Protocol_Error;
      end if;

      Status := Parse_Status_Line
        (Input (Cursor .. Line_End - 1),
         Parsed_Version,
         Parsed_Status,
         Parsed_Reason);

      if Status /= Ok then
         return Status;
      end if;

      Cursor := Line_End + 2;
      Header_Bytes := Cursor - Input'First;

      loop
         if Cursor > Input'Last then
            return Incomplete_Message;
         end if;

         Line_End := Line_End_At (Input, Cursor);
         if Line_End = 0 then
            return Incomplete_Message;
         elsif Line_End = Natural'Last then
            return Protocol_Error;
         end if;

         if Natural (Line_End - Cursor) > Max_Header_Line_Length then
            return Protocol_Error;
         end if;

         Header_Bytes := Header_Bytes + Natural (Line_End - Cursor) + 2;
         if Header_Bytes > Max_Header_Section_Size then
            return Protocol_Error;
         end if;

         exit when Line_End = Cursor;

         Header_Count := Header_Count + 1;
         if Header_Count > Max_Header_Count then
            return Protocol_Error;
         end if;

         if Input (Cursor) = ' ' or else Input (Cursor) = HT then
            return Unsupported_Feature;
         end if;

         declare
            Line        : constant String := Input (Cursor .. Line_End - 1);
            Colon_Index : Natural := 0;
         begin
            for Index in Line'Range loop
               if Line (Index) = ':' then
                  Colon_Index := Index;
                  exit;
               end if;
            end loop;

            if Colon_Index = 0 then
               return Invalid_Header;
            end if;

            declare
               Name  : constant String := Line (Line'First .. Colon_Index - 1);
               Value : constant String :=
                 Trim_Optional_Whitespace
                   (Line (Colon_Index + 1 .. Line'Last));
            begin
               if Name'Length = 0 then
                  return Invalid_Header;
               end if;

               if not Http_Client.Headers.Is_Valid_Name (Name) then
                  return Invalid_Header;
               end if;

               if not Http_Client.Headers.Is_Valid_Value (Value) then
                  return Invalid_Header;
               end if;

               Status := Http_Client.Headers.Add (Parsed_Headers, Name, Value);
               if Status /= Ok then
                  return Status;
               end if;
            end;
         end;

         Cursor := Line_End + 2;
      end loop;

      if Line_End + 1 /= Input'Last then
         return Protocol_Error;
      end if;

      Result :=
        (Version_Value => Parsed_Version,
         Status_Value  => Parsed_Status,
         Reason_Value  => Parsed_Reason,
         Header_List   => Parsed_Headers,
         Trailer_List  => Http_Client.Headers.Empty,
         Payload_Value => Null_Unbounded_String);
      return Ok;
   end Parse_Header_Section;

   function Parse_Response
     (Input   : String;
      Result  : out Response;
      Context : Parse_Context := Default_Context)
      return Http_Client.Errors.Result_Status
   is
      Cursor             : Positive := Input'First;
      Line_End           : Natural;
      Header_Count       : Natural := 0;
      Header_Bytes       : Natural := 0;
      Parsed_Version     : HTTP_Version := HTTP_1_1;
      Parsed_Status      : Http_Client.Types.Status_Code := 200;
      Parsed_Reason      : Unbounded_String := Null_Unbounded_String;
      Parsed_Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Content_Length     : Natural := 0;
      Has_Content_Length : Boolean := False;
      Has_Transfer_Encoding : Boolean := False;
      Status             : Result_Status;
   begin
      Result := Default_Response;

      if Input'Length = 0 then
         return Incomplete_Message;
      end if;

      Line_End := Line_End_At (Input, Cursor);
      if Line_End = 0 then
         return Incomplete_Message;
      elsif Line_End = Natural'Last then
         return Protocol_Error;
      end if;

      Status := Parse_Status_Line
        (Input (Cursor .. Line_End - 1),
         Parsed_Version,
         Parsed_Status,
         Parsed_Reason);

      if Status /= Ok then
         return Status;
      end if;

      Cursor := Line_End + 2;
      Header_Bytes := Cursor - Input'First;

      loop
         if Cursor > Input'Last then
            return Incomplete_Message;
         end if;

         Line_End := Line_End_At (Input, Cursor);
         if Line_End = 0 then
            return Incomplete_Message;
         elsif Line_End = Natural'Last then
            return Protocol_Error;
         end if;

         if Natural (Line_End - Cursor) > Max_Header_Line_Length then
            return Protocol_Error;
         end if;

         Header_Bytes := Header_Bytes + Natural (Line_End - Cursor) + 2;
         if Header_Bytes > Max_Header_Section_Size then
            return Protocol_Error;
         end if;

         exit when Line_End = Cursor;

         Header_Count := Header_Count + 1;
         if Header_Count > Max_Header_Count then
            return Protocol_Error;
         end if;

         if Input (Cursor) = ' ' or else Input (Cursor) = HT then
            return Unsupported_Feature;
         end if;

         declare
            Line        : constant String := Input (Cursor .. Line_End - 1);
            Colon_Index : Natural := 0;
         begin
            for Index in Line'Range loop
               if Line (Index) = ':' then
                  Colon_Index := Index;
                  exit;
               end if;
            end loop;

            if Colon_Index = 0 then
               return Invalid_Header;
            end if;

            declare
               Name  : constant String := Line (Line'First .. Colon_Index - 1);
               Value : constant String :=
                 Trim_Optional_Whitespace
                   (Line (Colon_Index + 1 .. Line'Last));
            begin
               if Name'Length = 0 then
                  return Invalid_Header;
               end if;

               if not Http_Client.Headers.Is_Valid_Name (Name) then
                  return Invalid_Header;
               end if;

               if not Http_Client.Headers.Is_Valid_Value (Value) then
                  return Invalid_Header;
               end if;

               declare
                  Lower_Name : constant String := Lower (Name);
               begin
                  if Lower_Name = "transfer-encoding" then
                     if Has_Transfer_Encoding then
                        return Invalid_Header;
                     end if;

                     Has_Transfer_Encoding := True;
                  elsif Lower_Name = "content-length" then
                     if Has_Content_Length then
                        return Invalid_Header;
                     end if;

                     if not Parse_Decimal_Natural (Value, Content_Length) then
                        return Invalid_Header;
                     end if;

                     Has_Content_Length := True;
                  end if;
               end;

               Status := Http_Client.Headers.Add (Parsed_Headers, Name, Value);
               if Status /= Ok then
                  return Status;
               end if;
            end;
         end;

         Cursor := Line_End + 2;
      end loop;

      Cursor := Line_End + 2;

      if Has_Transfer_Encoding then
         --  Parse_Response accepts HTTP entity bytes, not raw HTTP/1.1
         --  transfer framing.  Complete responses read through HTTP1.Reader
         --  have already had chunk framing decoded before this parser sees
         --  the message.  Reject raw Transfer-Encoding here so callers cannot
         --  accidentally mix framing metadata with entity body bytes.
         return Unsupported_Feature;
      end if;

      declare
         Remaining : constant Natural :=
           (if Cursor > Input'Last then 0 else Input'Last - Cursor + 1);
      begin
         if Body_Is_Disallowed (Parsed_Status, Context) then
            if Remaining /= 0 then
               return Protocol_Error;
            end if;

            Result :=
              (Version_Value => Parsed_Version,
               Status_Value  => Parsed_Status,
               Reason_Value  => Parsed_Reason,
               Header_List   => Parsed_Headers,
               Trailer_List  => Http_Client.Headers.Empty,
               Payload_Value => Null_Unbounded_String);
            return Ok;
         end if;

         if Has_Content_Length then
            if Content_Length > Max_In_Memory_Body_Size then
               return Protocol_Error;
            end if;

            if Remaining < Content_Length then
               return Incomplete_Message;
            elsif Remaining > Content_Length then
               return Protocol_Error;
            end if;

            if Content_Length = 0 then
               Result :=
                 (Version_Value => Parsed_Version,
                  Status_Value  => Parsed_Status,
                  Reason_Value  => Parsed_Reason,
                  Header_List   => Parsed_Headers,
                  Trailer_List  => Http_Client.Headers.Empty,
                  Payload_Value => Null_Unbounded_String);
            else
               Result :=
                 (Version_Value => Parsed_Version,
                  Status_Value  => Parsed_Status,
                  Reason_Value  => Parsed_Reason,
                  Header_List   => Parsed_Headers,
                  Trailer_List  => Http_Client.Headers.Empty,
                  Payload_Value => To_Unbounded_String
                    (Input (Cursor .. Cursor + Content_Length - 1)));
            end if;
         else
            if Remaining > Max_In_Memory_Body_Size then
               return Protocol_Error;
            end if;

            if Remaining = 0 then
               Result :=
                 (Version_Value => Parsed_Version,
                  Status_Value  => Parsed_Status,
                  Reason_Value  => Parsed_Reason,
                  Header_List   => Parsed_Headers,
                  Trailer_List  => Http_Client.Headers.Empty,
                  Payload_Value => Null_Unbounded_String);
            else
               Result :=
                 (Version_Value => Parsed_Version,
                  Status_Value  => Parsed_Status,
                  Reason_Value  => Parsed_Reason,
                  Header_List   => Parsed_Headers,
                  Trailer_List  => Http_Client.Headers.Empty,
                  Payload_Value => To_Unbounded_String (Input (Cursor .. Input'Last)));
            end if;
         end if;
      end;

      return Ok;
   end Parse_Response;

end Http_Client.Responses;
