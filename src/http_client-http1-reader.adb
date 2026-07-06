with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Responses;
with Http_Client.Types;

package body Http_Client.HTTP1.Reader is
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Status_Code;

   CR : constant Character := Character'Val (13);
   LF : constant Character := Character'Val (10);
   HT : constant Character := Character'Val (9);
   CRLF : constant String := CR & LF;
   CRLFCRLF : constant String := CRLF & CRLF;

   function Lower (Text : String) return String is
      Result : String := Text;
   begin
      for Index in Result'Range loop
         if Result (Index) in 'A' .. 'Z' then
            Result (Index) :=
              Character'Val
                (Character'Pos (Result (Index))
                 - Character'Pos ('A')
                 + Character'Pos ('a'));
         end if;
      end loop;

      return Result;
   end Lower;

   function Trim_OWS (Text : String) return String is
      First : Natural := Text'First;
      Last  : Natural := Text'Last;
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
   end Trim_OWS;

   function Parse_Natural_Strict
     (Text  : String;
      Value : out Natural) return Boolean
   is
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
   end Parse_Natural_Strict;

   function Header_End_Index (Text : String) return Natural is
   begin
      if Text'Length < CRLFCRLF'Length then
         return 0;
      end if;

      for Index in Text'First .. Text'Last - CRLFCRLF'Length + 1 loop
         if Text (Index .. Index + CRLFCRLF'Length - 1) = CRLFCRLF then
            return Index + CRLFCRLF'Length - 1;
         end if;
      end loop;

      return 0;
   end Header_End_Index;

   function Contains_Bare_LF_Before_Header_End (Text : String) return Boolean is
      Header_End : constant Natural := Header_End_Index (Text);
      Last       : constant Natural :=
        (if Header_End = 0 then Text'Last else Header_End);
   begin
      if Text'Length = 0 then
         return False;
      end if;

      for Index in Text'First .. Last loop
         if Text (Index) = LF
           and then (Index = Text'First or else Text (Index - 1) /= CR)
         then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Bare_LF_Before_Header_End;

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
            elsif Input (Index + 1) = LF then
               return Index;
            else
               return Natural'Last;
            end if;
         elsif Input (Index) = LF then
            return Natural'Last;
         end if;
      end loop;

      return 0;
   end Line_End_At;

   function Is_HEX (C : Character) return Boolean is
   begin
      return C in '0' .. '9' or else C in 'a' .. 'f' or else C in 'A' .. 'F';
   end Is_HEX;

   function HEX_Value (C : Character) return Natural is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         return 10 + Character'Pos (C) - Character'Pos ('a');
      else
         return 10 + Character'Pos (C) - Character'Pos ('A');
      end if;
   end HEX_Value;

   function Parse_Chunk_Size_Line
     (Line  : String;
      Value : out Natural) return Http_Client.Errors.Result_Status
   is
      Acc       : Natural := 0;
      Saw_Digit : Boolean := False;
      In_Ext    : Boolean := False;
   begin
      Value := 0;
      if Line'Length = 0 then
         return Http_Client.Errors.Protocol_Error;
      end if;
      for C of Line loop
         if not In_Ext then
            if Is_HEX (C) then
               Saw_Digit := True;
               declare
                  Digit : constant Natural := HEX_Value (C);
               begin
                  if Acc > (Natural'Last - Digit) / 16 then
                     return Http_Client.Errors.Response_Too_Large;
                  end if;
                  Acc := Acc * 16 + Digit;
               end;
            elsif C = ';' or else C = ' ' or else C = HT then
               if not Saw_Digit then
                  return Http_Client.Errors.Protocol_Error;
               end if;
               In_Ext := True;
            else
               return Http_Client.Errors.Protocol_Error;
            end if;
         else
            if C = CR or else C = LF then
               return Http_Client.Errors.Protocol_Error;
            end if;
         end if;
      end loop;
      if not Saw_Digit then
         return Http_Client.Errors.Protocol_Error;
      end if;
      Value := Acc;
      return Http_Client.Errors.Ok;
   end Parse_Chunk_Size_Line;

   function Transfer_Encoding_Is_Chunked (Value : String) return Boolean is
      V : constant String := Lower (Trim_OWS (Value));
   begin
      return V = "chunked";
   end Transfer_Encoding_Is_Chunked;

   function Decode_Chunked_Body
     (Input     : String;
      Decoded   : out Unbounded_String;
      Complete  : out Boolean;
      Max_Body  : Natural) return Http_Client.Errors.Result_Status
   is
      Cursor : Natural := Input'First;
      Size   : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      Decoded := Null_Unbounded_String;
      Complete := False;
      if Input'Length = 0 then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      loop
         if Cursor > Input'Last then
            return Http_Client.Errors.Incomplete_Message;
         end if;

         declare
            Line_End : constant Natural := Line_End_At (Input, Positive (Cursor));
         begin
            if Line_End = 0 then
               return Http_Client.Errors.Incomplete_Message;
            elsif Line_End = Natural'Last then
               return Http_Client.Errors.Protocol_Error;
            end if;

            Status := Parse_Chunk_Size_Line (Input (Cursor .. Line_End - 1), Size);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
            Cursor := Line_End + 2;
         end;

         if Size = 0 then
            loop
               if Cursor > Input'Last then
                  return Http_Client.Errors.Incomplete_Message;
               end if;
               declare
                  Trailer_End : constant Natural := Line_End_At (Input, Positive (Cursor));
               begin
                  if Trailer_End = 0 then
                     return Http_Client.Errors.Incomplete_Message;
                  elsif Trailer_End = Natural'Last then
                     return Http_Client.Errors.Protocol_Error;
                  elsif Trailer_End = Cursor then
                     Complete := True;
                     return Http_Client.Errors.Ok;
                  else
                     declare
                        Line  : constant String := Input (Cursor .. Trailer_End - 1);
                        Colon : Natural := 0;
                     begin
                        for Index in Line'Range loop
                           if Line (Index) = ':' then
                              Colon := Index;
                              exit;
                           end if;
                        end loop;
                        if Colon = 0
                          or else not Http_Client.Headers.Is_Valid_Name (Line (Line'First .. Colon - 1))
                          or else not Http_Client.Headers.Is_Valid_Value (Trim_OWS (Line (Colon + 1 .. Line'Last)))
                        then
                           return Http_Client.Errors.Invalid_Header;
                        end if;
                     end;
                     Cursor := Trailer_End + 2;
                  end if;
               end;
            end loop;
         end if;

         if Size > Max_Body or else Natural (Length (Decoded)) > Max_Body - Size then
            return Http_Client.Errors.Response_Too_Large;
         end if;

         if Cursor > Input'Last or else Natural (Input'Last - Cursor + 1) < Size + 2 then
            return Http_Client.Errors.Incomplete_Message;
         end if;

         if Input (Cursor + Size) /= CR or else Input (Cursor + Size + 1) /= LF then
            return Http_Client.Errors.Protocol_Error;
         end if;

         if Size > 0 then
            Append (Decoded, Input (Cursor .. Cursor + Size - 1));
         end if;
         Cursor := Cursor + Size + 2;
      end loop;
   end Decode_Chunked_Body;

   function Natural_Image_No_Space (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image_No_Space;

   function Decoded_Response_Text
     (Header_Text : String;
      Decoded     : Unbounded_String) return Unbounded_String
   is
      Result   : Unbounded_String := Null_Unbounded_String;
      Cursor   : Positive := Header_Text'First;
      End_Line : Natural;
   begin
      End_Line := Line_End_At (Header_Text, Cursor);
      if End_Line = 0 or else End_Line = Natural'Last then
         return To_Unbounded_String (Header_Text) & Decoded;
      end if;

      Append (Result, Header_Text (Cursor .. End_Line - 1));
      Append (Result, CRLF);
      Cursor := End_Line + 2;

      loop
         exit when Cursor > Header_Text'Last;

         End_Line := Line_End_At (Header_Text, Cursor);
         exit when End_Line = 0 or else End_Line = Natural'Last;
         exit when End_Line = Cursor;

         declare
            Line        : constant String := Header_Text (Cursor .. End_Line - 1);
            Colon_Index : Natural := 0;
         begin
            for Index in Line'Range loop
               if Line (Index) = ':' then
                  Colon_Index := Index;
                  exit;
               end if;
            end loop;

            if Colon_Index = 0 then
               Append (Result, Line);
               Append (Result, CRLF);
            else
               declare
                  Name : constant String :=
                    Lower (Line (Line'First .. Colon_Index - 1));
               begin
                  if Name /= "transfer-encoding"
                    and then Name /= "content-length"
                  then
                     Append (Result, Line);
                     Append (Result, CRLF);
                  end if;
               end;
            end if;
         end;

         Cursor := End_Line + 2;
      end loop;

      Append (Result, "Content-Length: ");
      Append (Result, Natural_Image_No_Space (Natural (Length (Decoded))));
      Append (Result, CRLF);
      Append (Result, CRLF);
      Append (Result, Decoded);

      return Result;
   end Decoded_Response_Text;

   function Body_Is_Disallowed
     (Status  : Http_Client.Types.Status_Code;
      Context : Http_Client.Responses.Parse_Context) return Boolean is
   begin
      return Context.Request_Was_HEAD
        or else (Status >= 100 and then Status <= 199)
        or else Status = 204
        or else Status = 205
        or else Status = 304;
   end Body_Is_Disallowed;

   type Framing_Info is record
      Status_Code        : Http_Client.Types.Status_Code := 200;
      Has_Content_Length : Boolean := False;
      Content_Length     : Natural := 0;
      Has_Transfer_Enc   : Boolean := False;
      Transfer_Chunked   : Boolean := False;
   end record;

   function Analyze_Header
     (Header_Text : String;
      Context     : Http_Client.Responses.Parse_Context;
      Options     : Reader_Options;
      Info        : out Framing_Info) return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced (Context);
      Cursor       : Positive := Header_Text'First;
      Line_End     : Natural;
      Parsed_Code  : Natural := 0;
      Header_Count : Natural := 0;
   begin
      Info := (others => <>);

      Line_End := Line_End_At (Header_Text, Cursor);
      if Line_End = 0 then
         return Http_Client.Errors.Incomplete_Message;
      elsif Line_End = Natural'Last then
         return Http_Client.Errors.Protocol_Error;
      elsif Natural (Line_End - Cursor) > Options.Max_Header_Line_Size then
         return Http_Client.Errors.Header_Too_Large;
      end if;

      declare
         Line : constant String := Header_Text (Cursor .. Line_End - 1);
      begin
         if Line'Length < 12 then
            return Http_Client.Errors.Protocol_Error;
         end if;

         if Line (Line'First .. Line'First + 7) /= "HTTP/1.1"
           and then Line (Line'First .. Line'First + 7) /= "HTTP/1.0"
         then
            return Http_Client.Errors.Protocol_Error;
         end if;

         if Line (Line'First + 8) /= ' ' then
            return Http_Client.Errors.Protocol_Error;
         end if;

         if not Parse_Natural_Strict
                  (Line (Line'First + 9 .. Line'First + 11), Parsed_Code)
         then
            return Http_Client.Errors.Protocol_Error;
         end if;

         if Parsed_Code < 100 or else Parsed_Code > 599 then
            return Http_Client.Errors.Protocol_Error;
         end if;

         Info.Status_Code := Http_Client.Types.Status_Code (Parsed_Code);
      end;

      Cursor := Line_End + 2;

      loop
         if Cursor > Header_Text'Last then
            return Http_Client.Errors.Incomplete_Message;
         end if;

         Line_End := Line_End_At (Header_Text, Cursor);
         if Line_End = 0 then
            return Http_Client.Errors.Incomplete_Message;
         elsif Line_End = Natural'Last then
            return Http_Client.Errors.Protocol_Error;
         elsif Natural (Line_End - Cursor) > Options.Max_Header_Line_Size then
            return Http_Client.Errors.Header_Too_Large;
         end if;

         exit when Line_End = Cursor;

         Header_Count := Header_Count + 1;
         if Header_Count > 1_000 then
            return Http_Client.Errors.Header_Too_Large;
         end if;

         if Header_Text (Cursor) = ' ' or else Header_Text (Cursor) = HT then
            return Http_Client.Errors.Unsupported_Feature;
         end if;

         declare
            Line        : constant String := Header_Text (Cursor .. Line_End - 1);
            Colon_Index : Natural := 0;
         begin
            for Index in Line'Range loop
               if Line (Index) = ':' then
                  Colon_Index := Index;
                  exit;
               end if;
            end loop;

            if Colon_Index = 0 then
               return Http_Client.Errors.Invalid_Header;
            end if;

            declare
               Name  : constant String := Line (Line'First .. Colon_Index - 1);
               Value : constant String := Trim_OWS (Line (Colon_Index + 1 .. Line'Last));
               Lower_Name : constant String := Lower (Name);
               Parsed_CL : Natural := 0;
            begin
               if not Http_Client.Headers.Is_Valid_Name (Name)
                 or else not Http_Client.Headers.Is_Valid_Value (Value)
               then
                  return Http_Client.Errors.Invalid_Header;
               end if;

               if Lower_Name = "transfer-encoding" then
                  if Info.Has_Transfer_Enc then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Info.Has_Transfer_Enc := True;
                  Info.Transfer_Chunked := Transfer_Encoding_Is_Chunked (Value);
                  if not Info.Transfer_Chunked then
                     return Http_Client.Errors.Unsupported_Feature;
                  end if;
               elsif Lower_Name = "content-length" then
                  if Info.Has_Content_Length then
                     return Http_Client.Errors.Invalid_Header;
                  end if;

                  if not Parse_Natural_Strict (Value, Parsed_CL) then
                     return Http_Client.Errors.Invalid_Header;
                  end if;

                  Info.Has_Content_Length := True;
                  Info.Content_Length := Parsed_CL;
               end if;
            end;
         end;

         Cursor := Line_End + 2;
      end loop;

      if Info.Has_Transfer_Enc and then Info.Has_Content_Length then
         return Http_Client.Errors.Invalid_Header;
      end if;

      return Http_Client.Errors.Ok;
   end Analyze_Header;

   function Read_Response
     (Connection : in out Connection_Type;
      Context    : Http_Client.Responses.Parse_Context;
      Raw        : out Ada.Strings.Unbounded.Unbounded_String;
      Response   : out Http_Client.Responses.Response;
      Options    : Reader_Options := Default_Reader_Options)
      return Http_Client.Errors.Result_Status
   is
      Accumulator : Unbounded_String := Null_Unbounded_String;
      Complete    : Unbounded_String := Null_Unbounded_String;
      Buffer      : String (1 .. Options.Read_Buffer_Size);
      Count       : Natural := 0;
      Status      : Http_Client.Errors.Result_Status;
      Header_End  : Natural := 0;
      Body_Start  : Natural := 0;
      Info        : Framing_Info;

      function Parse_Complete return Http_Client.Errors.Result_Status is
      begin
         Raw := Complete;
         return Http_Client.Responses.Parse_Response
           (Input   => To_String (Complete),
            Result  => Response,
            Context => Context);
      end Parse_Complete;

      function Finalize_From_Buffer
        (Use_Length : Natural) return Http_Client.Errors.Result_Status
      is
      begin
         if Use_Length > Options.Max_Response_Size then
            return Http_Client.Errors.Response_Too_Large;
         end if;

         declare
            Text : constant String := To_String (Accumulator);
         begin
            if Use_Length = 0 or else Use_Length > Text'Length then
               return Http_Client.Errors.Internal_Error;
            end if;

            Complete := To_Unbounded_String
              (Text (Text'First .. Text'First + Use_Length - 1));
            return Parse_Complete;
         end;
      end Finalize_From_Buffer;
   begin
      Raw := Null_Unbounded_String;
      Response := Http_Client.Responses.Default_Response;

      loop
         Status := Read_Some (Connection, Buffer, Count);

         if Status = Http_Client.Errors.Ok then
            if Count = 0 then
               return Http_Client.Errors.Read_Failed;
            end if;

            Append (Accumulator, Buffer (1 .. Count));

            declare
               Text : constant String := To_String (Accumulator);
            begin
               if Contains_Bare_LF_Before_Header_End (Text) then
                  return Http_Client.Errors.Protocol_Error;
               end if;

               Header_End := Header_End_Index (Text);

               if Header_End = 0 then
                  if Text'Length > Options.Max_Header_Size then
                     return Http_Client.Errors.Header_Too_Large;
                  elsif Text'Length > Options.Max_Response_Size then
                     return Http_Client.Errors.Response_Too_Large;
                  end if;
               else
                  if Natural (Header_End - Text'First + 1) > Options.Max_Header_Size then
                     return Http_Client.Errors.Header_Too_Large;
                  end if;

                  declare
                     Header_Text : constant String := Text (Text'First .. Header_End);
                  begin
                     Status := Analyze_Header (Header_Text, Context, Options, Info);
                  end;

                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;

                  Body_Start := Header_End + 1;

                  if Body_Is_Disallowed (Info.Status_Code, Context) then
                     return Finalize_From_Buffer
                       (Natural (Header_End - Text'First + 1));
                  elsif Info.Has_Transfer_Enc then
                     declare
                        Decoded  : Unbounded_String;
                        Complete_Chunked : Boolean := False;
                     begin
                        Status := Decode_Chunked_Body
                          ((if Body_Start <= Text'Last then Text (Body_Start .. Text'Last) else ""),
                           Decoded,
                           Complete_Chunked,
                           Options.Max_Body_Size);
                        if Status = Http_Client.Errors.Ok and then Complete_Chunked then
                           if Natural (Header_End - Text'First + 1) > Options.Max_Response_Size
                             or else Natural (Length (Decoded)) >
                               Options.Max_Response_Size - Natural (Header_End - Text'First + 1)
                           then
                              return Http_Client.Errors.Response_Too_Large;
                           end if;
                           Complete :=
                             Decoded_Response_Text
                               (Text (Text'First .. Header_End), Decoded);
                           return Parse_Complete;
                        elsif Status /= Http_Client.Errors.Incomplete_Message then
                           return Status;
                        end if;
                     end;
                  elsif Info.Has_Content_Length then
                     if Info.Content_Length > Options.Max_Body_Size then
                        return Http_Client.Errors.Response_Too_Large;
                     end if;

                     declare
                        Header_Bytes : constant Natural :=
                          Natural (Header_End - Text'First + 1);
                        Total_Needed : Natural := 0;
                     begin
                        if Info.Content_Length > Options.Max_Response_Size
                          or else Header_Bytes > Options.Max_Response_Size - Info.Content_Length
                        then
                           return Http_Client.Errors.Response_Too_Large;
                        end if;

                        Total_Needed := Header_Bytes + Info.Content_Length;

                        if Text'Length >= Total_Needed then
                           return Finalize_From_Buffer (Total_Needed);
                        end if;
                     end;
                  else
                     declare
                        Body_Bytes : constant Natural :=
                          (if Body_Start > Text'Last then 0 else Text'Last - Body_Start + 1);
                     begin
                        if Text'Length > Options.Max_Response_Size
                          or else Body_Bytes > Options.Max_Body_Size
                        then
                           return Http_Client.Errors.Response_Too_Large;
                        end if;
                     end;
                  end if;
               end if;
            end;
         elsif Status = Http_Client.Errors.End_Of_Stream then
            declare
               Text : constant String := To_String (Accumulator);
            begin
               if Header_End_Index (Text) = 0 then
                  return Http_Client.Errors.Incomplete_Message;
               end if;

               Header_End := Header_End_Index (Text);

               if Natural (Header_End - Text'First + 1) > Options.Max_Header_Size then
                  return Http_Client.Errors.Header_Too_Large;
               end if;

               Status := Analyze_Header
                 (Text (Text'First .. Header_End), Context, Options, Info);

               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

               Body_Start := Header_End + 1;

               if Body_Is_Disallowed (Info.Status_Code, Context) then
                  return Finalize_From_Buffer
                    (Natural (Header_End - Text'First + 1));
               elsif Info.Has_Transfer_Enc then
                  declare
                     Decoded  : Unbounded_String;
                     Complete_Chunked : Boolean := False;
                  begin
                     Status := Decode_Chunked_Body
                       ((if Body_Start <= Text'Last then Text (Body_Start .. Text'Last) else ""),
                        Decoded,
                        Complete_Chunked,
                        Options.Max_Body_Size);
                     if Status = Http_Client.Errors.Ok and then Complete_Chunked then
                        if Natural (Header_End - Text'First + 1) > Options.Max_Response_Size
                          or else Natural (Length (Decoded)) >
                            Options.Max_Response_Size - Natural (Header_End - Text'First + 1)
                        then
                           return Http_Client.Errors.Response_Too_Large;
                        end if;
                        Complete :=
                          Decoded_Response_Text
                            (Text (Text'First .. Header_End), Decoded);
                        return Parse_Complete;
                     elsif Status = Http_Client.Errors.Incomplete_Message then
                        return Http_Client.Errors.Incomplete_Message;
                     else
                        return Status;
                     end if;
                  end;
               elsif Info.Has_Content_Length then
                  if Info.Content_Length > Options.Max_Body_Size then
                     return Http_Client.Errors.Response_Too_Large;
                  end if;

                  declare
                     Header_Bytes : constant Natural :=
                       Natural (Header_End - Text'First + 1);
                     Total_Needed : Natural := 0;
                  begin
                     if Info.Content_Length > Options.Max_Response_Size
                       or else Header_Bytes > Options.Max_Response_Size - Info.Content_Length
                     then
                        return Http_Client.Errors.Response_Too_Large;
                     end if;

                     Total_Needed := Header_Bytes + Info.Content_Length;

                     if Text'Length < Total_Needed then
                        return Http_Client.Errors.Incomplete_Message;
                     else
                        return Finalize_From_Buffer (Total_Needed);
                     end if;
                  end;
               else
                  declare
                     Body_Bytes : constant Natural :=
                       (if Body_Start > Text'Last then 0 else Text'Last - Body_Start + 1);
                  begin
                     if Text'Length > Options.Max_Response_Size
                       or else Body_Bytes > Options.Max_Body_Size
                     then
                        return Http_Client.Errors.Response_Too_Large;
                     end if;
                  end;

                  Complete := Accumulator;
                  return Parse_Complete;
               end if;
            end;
         else
            return Status;
         end if;
      end loop;
   exception
      when Constraint_Error =>
         Raw := Null_Unbounded_String;
         Response := Http_Client.Responses.Default_Response;
         return Http_Client.Errors.Internal_Error;
   end Read_Response;

end Http_Client.HTTP1.Reader;
