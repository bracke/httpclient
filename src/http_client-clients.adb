with Ada.Calendar;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

with Interfaces.C;
with Interfaces.C.Strings;

with Http_Client.Cache;
with Http_Client.Cancellation;
with Http_Client.Cache.Persistent;
with Http_Client.Connection_Pools;
with Http_Client.Cookies;
with Http_Client.Crypto;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Execution;
with Http_Client.HTTP1;
with Http_Client.HTTP1.Reader;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Single_Stream;
with Http_Client.Proxies;
with Http_Client.Proxy_Discovery;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.Transports.SOCKS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Clients is
   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;

   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type C.int;
   use type C_Strings.chars_ptr;
   use Http_Client.Diagnostics;
   use Http_Client.Protocol_Discovery;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Cancellation.Cancellation_Token_Access;
   use type Http_Client.Cookies.Cookie_Jar_Access;
   use type Http_Client.Cache.Cache_Store_Access;
   use type Http_Client.Cache.Persistent.Persistent_Store_Access;
   use type Http_Client.Proxy_Discovery.Proxy_Precedence;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.URI.TCP_Port;
   use type Http_Client.HTTP1.Request_Target_Mode;
   use type Http_Client.HTTP2.Selected_Protocol;
   use type Http_Client.HTTP2.HTTP2_Mode;
   use type Http_Client.HTTP3.HTTP3_Mode;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Retry.Delay_Hook_Access;
   use type Http_Client.Request_Bodies.Body_Kind;
   use type Http_Client.Diagnostics.Context_Access;
   use type Http_Client.Transports.TCP.Timeout_Milliseconds;
   use type Ada.Directories.File_Size;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;


   function Hex_Image (Value : Natural) return String is
      Hex_Digits : constant String := "0123456789abcdef";
      Temp   : String (1 .. Natural'Size);
      Last   : Natural := Temp'Last;
      N      : Natural := Value;
   begin
      if Value = 0 then
         return "0";
      end if;

      while N > 0 loop
         Temp (Last) := Hex_Digits ((N mod 16) + 1);
         Last := Last - 1;
         N := N / 16;
      end loop;

      return Temp (Last + 1 .. Temp'Last);
   end Hex_Image;


   function Resume_Validator
     (ETag          : String;
      Last_Modified : String;
      ETag_Is_Weak  : Boolean;
      Resume_Safe   : Boolean := True)
      return Ada.Strings.Unbounded.Unbounded_String is
   begin
      if not Resume_Safe then
         return Null_Unbounded_String;
      elsif ETag /= "" and then not ETag_Is_Weak then
         return To_Unbounded_String (ETag);
      elsif Last_Modified /= "" then
         return To_Unbounded_String (Last_Modified);
      else
         return Null_Unbounded_String;
      end if;
   end Resume_Validator;

   procedure Configure_Resumable_Download
     (Options             : in out Download_Options;
      Resume_Mode         : Boolean;
      Can_Resume          : Boolean;
      Resume_If_Range     : Ada.Strings.Unbounded.Unbounded_String;
      Partial_Size        : Natural;
      Remaining_Max_Bytes : Natural)
   is
   begin
      Options.Create_Parent_Dirs := True;
      Options.File_Mode := (if Resume_Mode then Overwrite else Replace_Atomically);
      Options.Preserve_Partial_File := Resume_Mode;
      Options.Enable_Resume := Can_Resume;
      Options.Resume_If_Range := Resume_If_Range;

      if Resume_Mode and then Remaining_Max_Bytes > 0 then
         if Partial_Size > Natural'Last - Remaining_Max_Bytes then
            Options.Max_Download_Size := Natural'Last;
         else
            Options.Max_Download_Size := Partial_Size + Remaining_Max_Bytes;
         end if;
      else
         Options.Max_Download_Size := Remaining_Max_Bytes;
      end if;
   end Configure_Resumable_Download;

   function Resume_Fallback_For
     (Status      : Http_Client.Errors.Result_Status;
      Result      : Download_Result;
      Resume_Mode : Boolean) return Resume_Fallback_Action is
   begin
      if Status /= Http_Client.Errors.Ok
        and then Resume_Mode
        and then Result.HTTP_Status_Code = 416
      then
         return Retry_Without_Resume;
      else
         return Keep_Download_Result;
      end if;
   end Resume_Fallback_For;

   procedure Configure_Full_Retry_After_Resume_Failure
     (Options             : in out Download_Options;
      Remaining_Max_Bytes : Natural)
   is
   begin
      Options.Enable_Resume := False;
      Options.Resume_If_Range := Null_Unbounded_String;
      Options.Max_Download_Size := Remaining_Max_Bytes;
   end Configure_Full_Retry_After_Resume_Failure;

   function Request_Uses_Client_Certificate
     (Request : Http_Client.Requests.Request;
      Options : Execution_Options) return Boolean
   is
   begin
      return Http_Client.Requests.Is_Valid (Request)
        and then Http_Client.TLS.Client_Certificates.Is_Configured
          (Options.TLS.Client_Certificate)
        and then Http_Client.TLS.Client_Certificates.Matches
          (Options.TLS.Client_Certificate,
           Http_Client.Requests.URI (Request));
   exception
      when others =>
         return False;
   end Request_Uses_Client_Certificate;


   procedure Apply_Protocol_Policy
     (Configuration : in out Client_Configuration)
   is
   begin
      case Configuration.Execution.Protocol_Policy is
         when Protocol_From_Configuration =>
            null;

         when Force_HTTP_1_1 =>
            Configuration.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Disabled;
            Configuration.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Disabled;
            Configuration.Discovery.Allow_HTTP3_Discovery := False;

         when Prefer_HTTP_2 =>
            Configuration.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Allowed;
            Configuration.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Disabled;
            Configuration.Discovery.Allow_HTTP3_Discovery := False;

         when Force_HTTP_2 =>
            Configuration.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Required;
            Configuration.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Disabled;
            Configuration.Discovery.Allow_HTTP3_Discovery := False;

         when Prefer_HTTP_3 =>
            Configuration.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Allowed;
            Configuration.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
            Configuration.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Disabled;

         when Force_HTTP_3 =>
            Configuration.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Required;
            Configuration.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
            Configuration.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Disabled;
      end case;
   end Apply_Protocol_Policy;

   function Effective_TLS_Options_For_Request
     (Request : Http_Client.Requests.Request;
      Options : Execution_Options)
      return Http_Client.Transports.TLS.TLS_Options
   is
      Result : Http_Client.Transports.TLS.TLS_Options := Options.TLS;
   begin
      case Options.Protocol_Policy is
         when Force_HTTP_1_1 =>
            Result.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Disabled;
         when Prefer_HTTP_2 =>
            Result.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Allowed;
         when Force_HTTP_2 =>
            Result.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Required;
         when Protocol_From_Configuration | Prefer_HTTP_3 | Force_HTTP_3 =>
            null;
      end case;

      if Result.Timeouts.Connect = 0
        and then Result.Timeouts.Read = 0
        and then Result.Timeouts.Write = 0
        and then
          (Options.Timeouts.Connect /= 0
           or else Options.Timeouts.Read /= 0
           or else Options.Timeouts.Write /= 0)
      then
         --  High-level callers historically configured the top-level timeout
         --  record for one-shot requests.  HTTPS/TLS has its own timeout
         --  record, but leaving it at the default must not make HTTP/2 frame
         --  reads block indefinitely when the caller supplied bounded request
         --  timeouts.  Treat the top-level timeouts as the TLS default only
         --  when TLS-specific timeouts were not configured.
         Result.Timeouts := Options.Timeouts;
      end if;

      if Result.HTTP2.Mode /= Http_Client.HTTP2.HTTP2_Disabled
        and then Result.HTTP2.Max_Body_Size < Options.Max_Body_Size
      then
         Result.HTTP2.Max_Body_Size := Options.Max_Body_Size;
      end if;

      if Http_Client.Requests.Is_Valid (Request)
        and then Http_Client.TLS.Client_Certificates.Is_Configured
          (Result.Client_Certificate)
        and then Http_Client.TLS.Client_Certificates.Validate
          (Result.Client_Certificate) = Http_Client.Errors.Ok
        and then not Http_Client.TLS.Client_Certificates.Matches
          (Result.Client_Certificate,
           Http_Client.Requests.URI (Request))
      then
         --  Redirects and ordinary high-level requests recompute the mutual-TLS
         --  credential for the current origin. A credential scoped to another
         --  origin is not sent and must not force this hop onto a credentialed
         --  TLS connection. Invalid client-certificate configurations are left
         --  intact so TLS validation can still fail deterministically.
         Result.Client_Certificate :=
           Http_Client.TLS.Client_Certificates.No_Client_Certificate;
      end if;

      return Result;
   exception
      when others =>
         return Options.TLS;
   end Effective_TLS_Options_For_Request;

   function Diagnostics_Active
     (Options : Execution_Options) return Boolean
   is
   begin
      return Options.Diagnostics /= null
        and then Http_Client.Diagnostics.Is_Enabled (Options.Diagnostics.all);
   end Diagnostics_Active;

   function Emit_Diagnostic
     (Options : Execution_Options;
      Event   : Http_Client.Diagnostics.Diagnostic_Event)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Diagnostics_Active (Options) then
         return Http_Client.Diagnostics.Emit (Options.Diagnostics.all, Event);
      else
         return Http_Client.Errors.Ok;
      end if;
   end Emit_Diagnostic;

   function Retry_Message
     (Reason          : String;
      Body_Replayable : Boolean) return Http_Client.Diagnostics.Bounded_Text
   is
   begin
      return Http_Client.Diagnostics.To_Text
        (Reason &
         (if Body_Replayable
          then "; body replayable"
          else "; body not replayable"));
   end Retry_Message;

   function Emit_Retry_Diagnostic
     (Execution       : Execution_Options;
      Attempt         : Positive;
      Status          : Http_Client.Errors.Result_Status;
      Status_Code     : Natural;
      Planned_Delay   : Http_Client.Retry.Delay_Milliseconds;
      Reason          : String;
      Body_Replayable : Boolean) return Http_Client.Errors.Result_Status
   is
   begin
      return Emit_Diagnostic
        (Execution,
         (Kind                 => Http_Client.Diagnostics.Retry_Decision,
          Retry_Attempt        => Attempt,
          Result               => Status,
          Status_Code          => Status_Code,
          Elapsed_Milliseconds => Planned_Delay,
          Message              => Retry_Message (Reason, Body_Replayable),
          others               => <>));
   end Emit_Retry_Diagnostic;

   function New_Request_ID
     (Options : Execution_Options) return Http_Client.Diagnostics.Diagnostic_ID
   is
   begin
      if Diagnostics_Active (Options) then
         return Http_Client.Diagnostics.Next_Request_ID (Options.Diagnostics.all);
      else
         return 0;
      end if;
   end New_Request_ID;

   function New_Connection_ID
     (Options : Execution_Options) return Http_Client.Diagnostics.Diagnostic_ID
   is
   begin
      if Diagnostics_Active (Options) then
         return Http_Client.Diagnostics.Next_Connection_ID (Options.Diagnostics.all);
      else
         return 0;
      end if;
   end New_Connection_ID;

   function Header_Section_Byte_Count (Raw : Unbounded_String) return Natural is
      Text : constant String := To_String (Raw);
      CR   : constant Character := Character'Val (13);
      LF   : constant Character := Character'Val (10);
   begin
      if Text'Length < 4 then
         return Text'Length;
      end if;

      for Index in Text'First .. Text'Last - 3 loop
         if Text (Index) = CR
           and then Text (Index + 1) = LF
           and then Text (Index + 2) = CR
           and then Text (Index + 3) = LF
         then
            return Natural (Index - Text'First + 4);
         end if;
      end loop;

      return Text'Length;
   end Header_Section_Byte_Count;



   function Parse_Content_Length
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
   end Parse_Content_Length;

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   function Natural_Sum
     (Left  : Natural;
      Right : Natural;
      Sum   : out Natural) return Boolean
   is
   begin
      if Left > Natural'Last - Right then
         Sum := Natural'Last;
         return False;
      end if;

      Sum := Left + Right;
      return True;
   end Natural_Sum;

   procedure Existing_File_Size
     (Path      : String;
      Value     : out Natural;
      Too_Large : out Boolean)
   is
      File_Size : Ada.Directories.File_Size;
   begin
      Value := 0;
      Too_Large := False;

      if Path'Length = 0 or else not Ada.Directories.Exists (Path) then
         return;
      end if;

      File_Size := Ada.Directories.Size (Path);
      if File_Size > Ada.Directories.File_Size (Natural'Last) then
         Too_Large := True;
         return;
      end if;

      Value := Natural (File_Size);
   exception
      when others =>
         Value := 0;
         Too_Large := False;
   end Existing_File_Size;

   function Parse_Content_Range
     (Value      : String;
      Start      : out Natural;
      Last_Byte  : out Natural;
      Total_Size : out Natural) return Boolean
   is
      Trimmed : constant String := Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
      Prefix  : constant String := "bytes ";
      First   : Natural;
      Dash    : Natural := 0;
      Slash   : Natural := 0;
   begin
      Start := 0;
      Last_Byte := 0;
      Total_Size := 0;

      if Trimmed'Length <= Prefix'Length
        or else Trimmed (Trimmed'First .. Trimmed'First + Prefix'Length - 1) /= Prefix
      then
         return False;
      end if;

      First := Trimmed'First + Prefix'Length;
      for Index in First .. Trimmed'Last loop
         if Trimmed (Index) = '-' then
            Dash := Index;
         elsif Trimmed (Index) = '/' then
            Slash := Index;
            exit;
         elsif Trimmed (Index) not in '0' .. '9' then
            return False;
         end if;
      end loop;

      if Dash = 0
        or else Slash = 0
        or else Dash = First
        or else Slash <= Dash + 1
        or else Slash = Trimmed'Last
      then
         return False;
      end if;

      if not Parse_Content_Length (Trimmed (First .. Dash - 1), Start)
        or else not Parse_Content_Length (Trimmed (Dash + 1 .. Slash - 1), Last_Byte)
        or else Last_Byte < Start
      then
         return False;
      end if;

      if Trimmed (Slash + 1 .. Trimmed'Last) /= "*" then
         if not Parse_Content_Length (Trimmed (Slash + 1 .. Trimmed'Last), Total_Size)
           or else Total_Size <= Last_Byte
         then
            return False;
         end if;
      end if;

      return True;
   end Parse_Content_Range;

   function Parse_Unsatisfied_Content_Range
     (Value      : String;
      Total_Size : out Natural) return Boolean
   is
      Trimmed : constant String := Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
      Prefix  : constant String := "bytes */";
   begin
      Total_Size := 0;

      if Trimmed'Length <= Prefix'Length
        or else Trimmed (Trimmed'First .. Trimmed'First + Prefix'Length - 1) /= Prefix
      then
         return False;
      end if;

      return Parse_Content_Length
        (Trimmed (Trimmed'First + Prefix'Length .. Trimmed'Last), Total_Size);
   end Parse_Unsatisfied_Content_Range;



   function Request_Expects_100_Continue
     (Request : Http_Client.Requests.Request) return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
   begin
      return Http_Client.Headers.Contains (Headers, "Expect")
        and then Ada.Characters.Handling.To_Lower
          (Http_Client.Headers.Get (Headers, "Expect")) = "100-continue"
        and then Http_Client.Request_Bodies.Has_Body
          (Http_Client.Requests.Request_Body (Request));
   end Request_Expects_100_Continue;

   generic
      type Connection_Type is limited private;
      with function Read_Some
        (Item   : in out Connection_Type;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status;
   function Wait_For_100_Continue
     (Connection       : in out Connection_Type;
      Context          : Http_Client.Responses.Parse_Context;
      Options          : Execution_Options;
      Final_Response   : out Http_Client.Responses.Response;
      Continue_Granted : out Boolean)
      return Http_Client.Errors.Result_Status;

   function Wait_For_100_Continue
     (Connection       : in out Connection_Type;
      Context          : Http_Client.Responses.Parse_Context;
      Options          : Execution_Options;
      Final_Response   : out Http_Client.Responses.Response;
      Continue_Granted : out Boolean)
      return Http_Client.Errors.Result_Status
   is
      Acc        : Unbounded_String := Null_Unbounded_String;
      Buffer     : String (1 .. 1);
      Count      : Natural := 0;
      Status     : Http_Client.Errors.Result_Status;
      Header_Len : Natural := 0;

      function Body_Is_Disallowed return Boolean is
         Code : constant Http_Client.Types.Status_Code :=
           Http_Client.Responses.Status_Code (Final_Response);
      begin
         return Context.Request_Was_HEAD
           or else (Code >= 100 and then Code <= 199)
           or else Code = 204
           or else Code = 205
           or else Code = 304;
      end Body_Is_Disallowed;

      function Read_Final_Body
        (Header_Text : String) return Http_Client.Errors.Result_Status
      is
         Headers       : constant Http_Client.Headers.Header_List :=
           Http_Client.Responses.Headers (Final_Response);
         Content_Length : Natural := 0;
         Response_Body : Unbounded_String := Null_Unbounded_String;
         Body_Buffer   : String (1 .. Options.Read_Buffer_Size);
         Body_Count    : Natural := 0;
         Remaining     : Natural := 0;
         Body_Status   : Http_Client.Errors.Result_Status;
         CR            : constant Character := Character'Val (13);
         LF            : constant Character := Character'Val (10);
         HT            : constant Character := Character'Val (9);

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

         function Decode_Chunked_Body
           (Input     : String;
            Decoded   : out Unbounded_String;
            Complete  : out Boolean) return Http_Client.Errors.Result_Status
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
                  Line_End : constant Natural :=
                    Line_End_At (Input, Positive (Cursor));
               begin
                  if Line_End = 0 then
                     return Http_Client.Errors.Incomplete_Message;
                  elsif Line_End = Natural'Last then
                     return Http_Client.Errors.Protocol_Error;
                  end if;

                  Status := Parse_Chunk_Size_Line
                    (Input (Cursor .. Line_End - 1), Size);
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
                        Trailer_End : constant Natural :=
                          Line_End_At (Input, Positive (Cursor));
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
                              Line  : constant String :=
                                Input (Cursor .. Trailer_End - 1);
                              Colon : Natural := 0;
                           begin
                              for Index in Line'Range loop
                                 if Line (Index) = ':' then
                                    Colon := Index;
                                    exit;
                                 end if;
                              end loop;

                              if Colon = 0
                                or else not Http_Client.Headers.Is_Valid_Name
                                  (Line (Line'First .. Colon - 1))
                                or else not Http_Client.Headers.Is_Valid_Value
                                  (Trim_OWS (Line (Colon + 1 .. Line'Last)))
                              then
                                 return Http_Client.Errors.Invalid_Header;
                              end if;
                           end;
                           Cursor := Trailer_End + 2;
                        end if;
                     end;
                  end loop;
               end if;

               if Size > Options.Max_Body_Size
                 or else Natural (Length (Decoded)) > Options.Max_Body_Size - Size
               then
                  return Http_Client.Errors.Response_Too_Large;
               end if;

               if Cursor > Input'Last
                 or else Natural (Input'Last - Cursor + 1) < Size + 2
               then
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
      begin
         if Options.Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         if Body_Is_Disallowed then
            return Http_Client.Errors.Ok;
         end if;

         if Http_Client.Headers.Contains (Headers, "Transfer-Encoding") then
            if Http_Client.Headers.Contains (Headers, "Content-Length") then
               return Http_Client.Errors.Invalid_Header;
            elsif Lower (Trim_OWS (Http_Client.Headers.Get (Headers, "Transfer-Encoding")))
              /= "chunked"
            then
               return Http_Client.Errors.Unsupported_Feature;
            end if;

            declare
               Raw_Chunks : Unbounded_String := Null_Unbounded_String;
               Decoded    : Unbounded_String := Null_Unbounded_String;
               Complete   : Boolean := False;
            begin
               loop
                  if Options.Cancellation /= null
                    and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
                  then
                     return Http_Client.Errors.Cancelled;
                  end if;

                  Body_Status := Decode_Chunked_Body
                    (To_String (Raw_Chunks), Decoded, Complete);

                  if Body_Status = Http_Client.Errors.Ok and then Complete then
                     if Header_Text'Length > Options.Max_Response_Size
                       or else Natural (Length (Decoded)) > Options.Max_Body_Size
                       or else Natural (Length (Decoded)) >
                         Options.Max_Response_Size - Header_Text'Length
                     then
                        return Http_Client.Errors.Response_Too_Large;
                     end if;

                     declare
                        Decoded_Header : Unbounded_String := Null_Unbounded_String;
                        Cursor         : Natural := Header_Text'First;
                        Line_End       : Natural := 0;
                     begin
                        Line_End := Line_End_At (Header_Text, Positive (Cursor));
                        if Line_End = 0 or else Line_End = Natural'Last then
                           return Http_Client.Errors.Protocol_Error;
                        end if;

                        Append
                          (Decoded_Header,
                           Header_Text (Cursor .. Line_End + 1));
                        Cursor := Line_End + 2;

                        while Cursor <= Header_Text'Last - 1 loop
                           Line_End := Line_End_At (Header_Text, Positive (Cursor));
                           if Line_End = 0 or else Line_End = Natural'Last then
                              return Http_Client.Errors.Protocol_Error;
                           elsif Line_End = Cursor then
                              exit;
                           end if;

                           declare
                              Line  : constant String :=
                                Header_Text (Cursor .. Line_End - 1);
                              Colon : Natural := 0;
                           begin
                              for Index in Line'Range loop
                                 if Line (Index) = ':' then
                                    Colon := Index;
                                    exit;
                                 end if;
                              end loop;

                              if Colon = 0
                                or else Lower
                                  (Line (Line'First .. Colon - 1)) /=
                                  "transfer-encoding"
                              then
                                 Append
                                   (Decoded_Header,
                                    Header_Text (Cursor .. Line_End + 1));
                              end if;
                           end;

                           Cursor := Line_End + 2;
                        end loop;

                        declare
                           Length_Image : constant String :=
                             Natural'Image (Natural (Length (Decoded)));
                        begin
                           Append
                             (Decoded_Header,
                              "Content-Length: " &
                              Length_Image (2 .. Length_Image'Last) &
                              Character'Val (13) & Character'Val (10) &
                              Character'Val (13) & Character'Val (10));
                        end;

                        return Http_Client.Responses.Parse_Response
                          (To_String (Decoded_Header) & To_String (Decoded),
                           Final_Response,
                           Context);
                     end;
                  elsif Body_Status /= Http_Client.Errors.Incomplete_Message then
                     return Body_Status;
                  end if;

                  Body_Status := Read_Some (Connection, Body_Buffer, Body_Count);
                  if Body_Status /= Http_Client.Errors.Ok then
                     if Body_Status = Http_Client.Errors.End_Of_Stream then
                        return Http_Client.Errors.Incomplete_Message;
                     else
                        return Body_Status;
                     end if;
                  elsif Body_Count = 0 then
                     return Http_Client.Errors.Read_Failed;
                  end if;

                  Append
                    (Raw_Chunks,
                     Body_Buffer
                       (Body_Buffer'First .. Body_Buffer'First + Body_Count - 1));

                  if Natural (Length (Raw_Chunks)) > Options.Max_Response_Size
                  then
                     return Http_Client.Errors.Response_Too_Large;
                  end if;
               end loop;
            end;
         end if;

         if not Http_Client.Headers.Contains (Headers, "Content-Length") then
            return Http_Client.Errors.Ok;
         end if;

         if not Parse_Content_Length
                  (Http_Client.Headers.Get (Headers, "Content-Length"), Content_Length)
         then
            return Http_Client.Errors.Invalid_Header;
         elsif Content_Length > Options.Max_Body_Size
           or else Content_Length > Options.Max_Response_Size
           or else Header_Text'Length > Options.Max_Response_Size - Content_Length
         then
            return Http_Client.Errors.Response_Too_Large;
         end if;

         Remaining := Content_Length;
         while Remaining > 0 loop
            if Options.Cancellation /= null
              and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
            then
               return Http_Client.Errors.Cancelled;
            end if;

            declare
               Need : constant Natural := Natural'Min (Remaining, Body_Buffer'Length);
            begin
               Body_Status := Read_Some
                 (Connection,
                  Body_Buffer (Body_Buffer'First .. Body_Buffer'First + Need - 1),
                  Body_Count);
            end;

            if Body_Status /= Http_Client.Errors.Ok then
               if Body_Status = Http_Client.Errors.End_Of_Stream then
                  return Http_Client.Errors.Incomplete_Message;
               else
                  return Body_Status;
               end if;
            elsif Body_Count = 0 then
               return Http_Client.Errors.Read_Failed;
            elsif Body_Count > Remaining then
               return Http_Client.Errors.Protocol_Error;
            end if;

            Append
              (Response_Body,
               Body_Buffer
                 (Body_Buffer'First .. Body_Buffer'First + Body_Count - 1));
            Remaining := Remaining - Body_Count;
         end loop;

         return Http_Client.Responses.Parse_Response
           (Header_Text & To_String (Response_Body), Final_Response, Context);
      end Read_Final_Body;
   begin
      Final_Response := Http_Client.Responses.Default_Response;
      Continue_Granted := False;

      loop
         if Options.Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         Status := Read_Some (Connection, Buffer, Count);
         if Status /= Http_Client.Errors.Ok then
            if Status = Http_Client.Errors.End_Of_Stream then
               return Http_Client.Errors.Incomplete_Message;
            else
               return Status;
            end if;
         elsif Count = 0 then
            return Http_Client.Errors.Read_Failed;
         end if;

         Append (Acc, Buffer (1 .. Count));
         Header_Len := Header_Section_Byte_Count (Acc);

         declare
            Text : constant String := To_String (Acc);
         begin
            if Header_Len = Text'Length
              and then Header_Len >= 4
              and then Text (Text'Last - 3 .. Text'Last) =
                Character'Val (13) & Character'Val (10) &
                Character'Val (13) & Character'Val (10)
            then
               Status := Http_Client.Responses.Parse_Header_Section
                 (Text, Final_Response, Context);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

               if Http_Client.Responses.Status_Code (Final_Response) = 100 then
                  Continue_Granted := True;
                  return Http_Client.Errors.Ok;
               elsif Http_Client.Responses.Status_Code (Final_Response) >= 100
                 and then Http_Client.Responses.Status_Code (Final_Response) <= 199
               then
                  --  Ignore other informational responses and continue waiting
                  --  for either 100 Continue or the final response.
                  Acc := Null_Unbounded_String;
               else
                  Continue_Granted := False;
                  return Read_Final_Body (Text);
               end if;
            elsif Text'Length > Options.Max_Header_Size then
               return Http_Client.Errors.Header_Too_Large;
            end if;
         end;
      end loop;
   exception
      when others =>
         Final_Response := Http_Client.Responses.Default_Response;
         Continue_Granted := False;
         return Http_Client.Errors.Internal_Error;
   end Wait_For_100_Continue;


   function Create return Client is
      Result : Client;
   begin
      Result.Initialized := True;
      Result.Config := Default_Client_Configuration;
      Result.State := new Client_State;
      Http_Client.Connection_Pools.Initialize
        (Result.State.Pool, Default_Client_Configuration.Pooling);
      Http_Client.Protocol_Discovery.Initialize
        (Result.Discovery_Cache, Default_Client_Configuration.Discovery);
      return Result;
   end Create;

   function Supports_Network_IO (Item : Client) return Boolean is
      pragma Unreferenced (Item);
   begin
      return True;
   end Supports_Network_IO;

   function Is_Initialized (Item : Client) return Boolean is
   begin
      return Item.Initialized;
   end Is_Initialized;


   function Port_Image (Port : Http_Client.URI.TCP_Port) return String is
      Image : constant String := Natural'Image (Natural (Port));
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Port_Image;

   function Status_Is_Followed_Redirect
     (Code : Http_Client.Types.Status_Code) return Boolean
   is
   begin
      return Code = 301 or else Code = 302 or else Code = 303
        or else Code = 307 or else Code = 308;
   end Status_Is_Followed_Redirect;

   function Same_Origin
     (Left  : Http_Client.URI.URI_Reference;
      Right : Http_Client.URI.URI_Reference) return Boolean
   is
   begin
      return Http_Client.URI.Scheme (Left) = Http_Client.URI.Scheme (Right)
        and then Http_Client.URI.Host (Left) = Http_Client.URI.Host (Right)
        and then Http_Client.URI.Effective_Port (Left) =
          Http_Client.URI.Effective_Port (Right);
   end Same_Origin;

   function Text_Before_Fragment (Text : String) return String is
   begin
      for I in Text'Range loop
         if Text (I) = '#' then
            if I = Text'First then
               return "";
            else
               return Text (Text'First .. I - 1);
            end if;
         end if;
      end loop;

      return Text;
   end Text_Before_Fragment;

   function Absolute_Prefix (Base : Http_Client.URI.URI_Reference) return String is
      Prefix : constant String :=
        Http_Client.URI.Scheme (Base) & "://" & Http_Client.URI.Authority_Host (Base);
   begin
      if Http_Client.URI.Has_Explicit_Port (Base)
        and then not
          ((Http_Client.URI.Scheme (Base) = "http"
            and then Http_Client.URI.Effective_Port (Base) = 80)
           or else
           (Http_Client.URI.Scheme (Base) = "https"
            and then Http_Client.URI.Effective_Port (Base) = 443))
      then
         return Prefix & ":" & Port_Image (Http_Client.URI.Effective_Port (Base));
      else
         return Prefix;
      end if;
   end Absolute_Prefix;

   function Directory_Path (Path : String) return String is
   begin
      for I in reverse Path'Range loop
         if Path (I) = '/' then
            return Path (Path'First .. I);
         end if;
      end loop;

      return "/";
   end Directory_Path;


   function Path_Before_Query (Text : String) return String is
   begin
      for I in Text'Range loop
         if Text (I) = '?' then
            if I = Text'First then
               return "";
            else
               return Text (Text'First .. I - 1);
            end if;
         end if;
      end loop;

      return Text;
   end Path_Before_Query;

   function Query_Suffix (Text : String) return String is
   begin
      for I in Text'Range loop
         if Text (I) = '?' then
            return Text (I .. Text'Last);
         end if;
      end loop;

      return "";
   end Query_Suffix;

   function Normalize_Redirect_Path (Path : String) return String is
      Segment_Count : Positive := 1;
   begin
      for C of Path loop
         if C = '/' then
            Segment_Count := Segment_Count + 1;
         end if;
      end loop;

      declare
         Segments : array (Positive range 1 .. Segment_Count) of Unbounded_String;
         Top      : Natural := 0;
         I        : Natural := Path'First;
         Result   : Unbounded_String := To_Unbounded_String ("/");
      begin
         while I <= Path'Last loop
            while I <= Path'Last and then Path (I) = '/' loop
               I := I + 1;
            end loop;

            exit when I > Path'Last;

            declare
               Start : constant Natural := I;
            begin
               while I <= Path'Last and then Path (I) /= '/' loop
                  I := I + 1;
               end loop;

               declare
                  Segment : constant String := Path (Start .. I - 1);
               begin
                  if Segment = "." then
                     null;
                  elsif Segment = ".." then
                     if Top > 0 then
                        Top := Top - 1;
                     end if;
                  else
                     Top := Top + 1;
                     Segments (Top) := To_Unbounded_String (Segment);
                  end if;
               end;
            end;
         end loop;

         for J in 1 .. Top loop
            if J > 1 then
               Append (Result, "/");
            end if;

            Append (Result, To_String (Segments (J)));
         end loop;

         return To_String (Result);
      end;
   end Normalize_Redirect_Path;

   function Normalize_Path_Query (Text : String) return String is
      Path : constant String := Path_Before_Query (Text);
   begin
      return Normalize_Redirect_Path (Path) & Query_Suffix (Text);
   end Normalize_Path_Query;

   function Resolve_Location
     (Base     : Http_Client.URI.URI_Reference;
      Location : String;
      Target   : out Http_Client.URI.URI_Reference)
      return Http_Client.Errors.Result_Status
   is
      Clean       : constant String := Text_Before_Fragment (Location);
      Lower_Clean : constant String := Ada.Characters.Handling.To_Lower (Clean);
      Text        : Unbounded_String := Null_Unbounded_String;
   begin
      Target := Http_Client.URI.Create_Unchecked ("");

      if Location'Length = 0 then
         return Http_Client.Errors.Invalid_Redirect;
      end if;

      if Clean'Length = 0 then
         Text := To_Unbounded_String (Http_Client.URI.Image (Base));
      elsif Clean'Length >= 7
        and then Lower_Clean (Lower_Clean'First .. Lower_Clean'First + 6) = "http://"
      then
         Text := To_Unbounded_String (Clean);
      elsif Clean'Length >= 8
        and then Lower_Clean (Lower_Clean'First .. Lower_Clean'First + 7) = "https://"
      then
         Text := To_Unbounded_String (Clean);
      elsif Clean'Length >= 2
        and then Clean (Clean'First) = '/'
        and then Clean (Clean'First + 1) = '/'
      then
         Text :=
           To_Unbounded_String
             (Http_Client.URI.Scheme (Base) & ":" & Clean);
      elsif Clean (Clean'First) = '/' then
         Text :=
           To_Unbounded_String
             (Absolute_Prefix (Base) & Normalize_Path_Query (Clean));
      elsif Clean (Clean'First) = '?' then
         Text :=
           To_Unbounded_String
             (Absolute_Prefix (Base) & Http_Client.URI.Path (Base) & Clean);
      else
         Text :=
           To_Unbounded_String
             (Absolute_Prefix (Base) &
              Normalize_Path_Query
                (Directory_Path (Http_Client.URI.Path (Base)) & Clean));
      end if;

      declare
         Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.URI.Parse (To_String (Text), Target);
      begin
         if Status = Http_Client.Errors.Ok then
            return Http_Client.Errors.Ok;
         else
            return Http_Client.Errors.Invalid_Redirect;
         end if;
      end;
   exception
      when others =>
         Target := Http_Client.URI.Create_Unchecked ("");
         return Http_Client.Errors.Invalid_Redirect;
   end Resolve_Location;

   function Redirected_Method
     (Original_Method : Http_Client.Types.Method_Name;
      Status_Code     : Http_Client.Types.Status_Code;
      Policy          : Redirect_Method_Policy)
      return Http_Client.Types.Method_Name
   is
   begin
      if Status_Code = 303 then
         if Original_Method = Http_Client.Types.HEAD then
            return Http_Client.Types.HEAD;
         else
            return Http_Client.Types.GET;
         end if;
      elsif (Status_Code = 301 or else Status_Code = 302)
        and then Policy = Rewrite_Post_To_Get_For_301_302
        and then Original_Method = Http_Client.Types.POST
      then
         return Http_Client.Types.GET;
      else
         return Original_Method;
      end if;
   end Redirected_Method;

   function Build_Redirected_Request
     (Current_Request : Http_Client.Requests.Request;
      Current_URI     : Http_Client.URI.URI_Reference;
      Target_URI      : Http_Client.URI.URI_Reference;
      Status_Code     : Http_Client.Types.Status_Code;
      Redirects       : Redirect_Options;
      Next_Request    : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers    : Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Current_Request);
      Old_Method : constant Http_Client.Types.Method_Name :=
        Http_Client.Requests.Method (Current_Request);
      New_Method : constant Http_Client.Types.Method_Name :=
        Redirected_Method
          (Old_Method,
           Status_Code,
           Redirects.Method_Policy_301_302);
      Old_Body   : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Current_Request);
      New_Body   : Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Request_Bodies.Empty;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Next_Request := Http_Client.Requests.Default_Request;

      Status := Http_Client.Headers.Remove (Headers, "Host");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Content-Length");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Transfer-Encoding");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Connection");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Keep-Alive");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "TE");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Trailer");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Upgrade");
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Redirects.Strip_Credentials_Cross_Origin
        and then not Same_Origin (Current_URI, Target_URI)
      then
         Status := Http_Client.Headers.Remove (Headers, "Authorization");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Proxy-Authorization");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Cookie");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Cookie2");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Git-Protocol");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Status_Code = 303
        or else New_Method /= Old_Method
      then
         Status := Http_Client.Headers.Remove (Headers, "Content-Type");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Content-Encoding");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Content-Language");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Content-Location");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Content-MD5");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Digest");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Headers.Remove (Headers, "Expect");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         New_Body := Http_Client.Request_Bodies.Empty;
      else
         if Http_Client.Request_Bodies.Has_Body (Old_Body) then
            if not Redirects.Allow_Body_Replay
              or else not Http_Client.Request_Bodies.Is_Replayable (Old_Body)
            then
               return Http_Client.Errors.Redirect_Body_Replay_Disallowed;
            end if;

            Status := Http_Client.Request_Bodies.Reset_Body (Old_Body);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
         end if;

         New_Body := Old_Body;
      end if;

      Status := Http_Client.Requests.Create
        (Method    => New_Method,
         URI       => Target_URI,
         Item      => Next_Request,
         Headers   => Headers,
         Payload   => Http_Client.Request_Bodies.Buffered_Payload (New_Body),
         Auto_Host => True);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Requests.Set_Body (Next_Request, New_Body);
   exception
      when others =>
         Next_Request := Http_Client.Requests.Default_Request;
         return Http_Client.Errors.Internal_Error;
   end Build_Redirected_Request;

   function Parse_Context_For
     (Request : Http_Client.Requests.Request)
      return Http_Client.Responses.Parse_Context
   is
   begin
      return
        (Request_Was_HEAD =>
           Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD);
   end Parse_Context_For;

   function Reader_Options_For
     (Options : Execution_Options) return Http_Client.HTTP1.Reader.Reader_Options
   is
   begin
      return
        (Max_Response_Size    => Options.Max_Response_Size,
         Max_Header_Size      => Options.Max_Header_Size,
         Max_Header_Line_Size => Options.Max_Header_Line_Size,
         Max_Body_Size        => Options.Max_Body_Size,
         Read_Buffer_Size     => Options.Read_Buffer_Size);
   end Reader_Options_For;

   function Streaming_Protocol_Policy_For
     (Options : Execution_Options)
      return Http_Client.Response_Streams.Streaming_Protocol_Policy
   is
   begin
      case Options.Protocol_Policy is
         when Force_HTTP_1_1 =>
            return Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;

         when Prefer_HTTP_2 =>
            return Http_Client.Response_Streams.Streaming_Prefer_HTTP_2;

         when Force_HTTP_2 =>
            return Http_Client.Response_Streams.Streaming_Force_HTTP_2;

         when Prefer_HTTP_3 =>
            return Http_Client.Response_Streams.Streaming_Prefer_HTTP_3;

         when Force_HTTP_3 =>
            return Http_Client.Response_Streams.Streaming_Force_HTTP_3;

         when Protocol_From_Configuration =>
            if Options.TLS.HTTP2.Mode = Http_Client.HTTP2.HTTP2_Required then
               return Http_Client.Response_Streams.Streaming_Force_HTTP_2;
            elsif Options.TLS.HTTP2.Mode = Http_Client.HTTP2.HTTP2_Allowed then
               return Http_Client.Response_Streams.Streaming_Prefer_HTTP_2;
            else
               return Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;
            end if;
      end case;
   end Streaming_Protocol_Policy_For;

   function Streaming_Options_For
     (Options : Execution_Options)
      return Http_Client.Response_Streams.Streaming_Options
   is
   begin
      return
        (Max_Header_Size      => Options.Max_Header_Size,
         Max_Header_Line_Size => Options.Max_Header_Line_Size,
         Max_Body_Size        => Options.Max_Body_Size,
         Read_Buffer_Size     => Options.Read_Buffer_Size,
         Timeouts             => Options.Timeouts,
         Cancellation         => Options.Cancellation,
         TLS                  => Options.TLS,
         Add_Connection_Close => Options.Add_Connection_Close,
         Cookie_Jar           => Options.Cookie_Jar,
         Strict_Cookies       => Options.Strict_Cookies,
         Merge_Jar_Cookies    => Options.Merge_Jar_Cookies,
         Enable_Decompression => False,
         Decompression        => Http_Client.Decompression.Default_Decompression_Options,
         HTTP3                => Http_Client.HTTP3.Default_HTTP3_Options,
         Proxy                => Options.Proxy,
         Diagnostics          => Options.Diagnostics,
         Protocol_Policy      => Streaming_Protocol_Policy_For (Options));
   end Streaming_Options_For;

   function Serialized_Request
     (Request : Http_Client.Requests.Request;
      Options : Execution_Options;
      Output  : out Unbounded_String;
      Wire_Request : out Http_Client.Requests.Request;
      Target_Mode : Http_Client.HTTP1.Request_Target_Mode :=
        Http_Client.HTTP1.Origin_Form) return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Status  : Http_Client.Errors.Result_Status;
   begin
      Output := Null_Unbounded_String;
      Wire_Request := Http_Client.Requests.Default_Request;

      if Options.Add_Connection_Close
        and then not Http_Client.Headers.Contains (Headers, "Connection")
      then
         Status :=
           Http_Client.Headers.Set
             (Headers,
              "Connection",
              "close");

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Options.Advertise_Accept_Encoding
        and then not Http_Client.Headers.Contains (Headers, "Accept-Encoding")
      then
         Status :=
           Http_Client.Headers.Set
             (Headers,
              "Accept-Encoding",
              Http_Client.Decompression.Supported_Accept_Encoding);

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Options.Cookie_Jar /= null then
         declare
            Existing_Cookie : constant Boolean :=
              Http_Client.Headers.Contains (Headers, "Cookie");
            Jar_Header      : constant String :=
              Http_Client.Cookies.Get_Cookie_Header
                (Options.Cookie_Jar.all,
                 Http_Client.Requests.URI (Request));
         begin
            if Jar_Header'Length > 0 then
               if not Existing_Cookie then
                  Status := Http_Client.Headers.Set
                    (Headers, "Cookie", Jar_Header);
               elsif Options.Merge_Jar_Cookies then
                  Status := Http_Client.Headers.Set
                    (Headers,
                     "Cookie",
                     Http_Client.Headers.Get (Headers, "Cookie") & "; " & Jar_Header);
               else
                  Status := Http_Client.Errors.Ok;
               end if;

               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;
         end;
      end if;

      if Target_Mode = Http_Client.HTTP1.Absolute_Form
        and then Http_Client.Proxies.Is_Enabled (Options.Proxy)
        and then Http_Client.Proxies.Has_Proxy_Authorization (Options.Proxy)
      then
         Status := Http_Client.Headers.Set
           (Headers,
            "Proxy-Authorization",
            Http_Client.Proxies.Proxy_Authorization (Options.Proxy));

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      else
         Status := Http_Client.Headers.Remove (Headers, "Proxy-Authorization");

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      Status :=
        Http_Client.Requests.Create
          (Method    => Http_Client.Requests.Method (Request),
           URI       => Http_Client.Requests.URI (Request),
           Item      => Wire_Request,
           Headers   => Headers,
           Payload   => Http_Client.Requests.Payload (Request),
           Auto_Host => False);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Set_Body
        (Wire_Request,
         Http_Client.Requests.Request_Body (Request));

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Request_Expects_100_Continue (Wire_Request) then
         --  `Expect: 100-continue` requires the body to be withheld until an
         --  interim `100 Continue` response is received. Even replayable
         --  buffered bodies therefore use the header-only serializer here; the
         --  upload writer sends the buffered bytes after the interim response.
         return Http_Client.HTTP1.Serialize_Headers
           (Wire_Request, Output, Target_Mode);
      elsif Http_Client.Request_Bodies.Kind
           (Http_Client.Requests.Request_Body (Wire_Request)) =
         Http_Client.Request_Bodies.Buffered_Body
        or else Http_Client.Request_Bodies.Kind
           (Http_Client.Requests.Request_Body (Wire_Request)) =
         Http_Client.Request_Bodies.Empty_Body
      then
         return Http_Client.HTTP1.Serialize_Request
           (Wire_Request, Output, Target_Mode);
      else
         return Http_Client.HTTP1.Serialize_Headers
           (Wire_Request, Output, Target_Mode);
      end if;
   end Serialized_Request;


   function Write_Chunked_Upload_TCP
     (Connection   : in out Http_Client.Transports.TCP.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Req_Body : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Buffer   : String (1 .. 8192);
      Count    : Natural := 0;
      Status   : Http_Client.Errors.Result_Status;
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
   begin
      loop
         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         Status := Http_Client.Request_Bodies.Read_Next
           (Req_Body, Buffer, Count);

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         if Count > Buffer'Length then
            return Http_Client.Errors.Body_Producer_Failed;
         elsif Count = 0 then
            declare
               Trailer_Fields : constant Http_Client.Headers.Header_List :=
                 Http_Client.Request_Bodies.Trailers (Req_Body);
               Trailer_Text   : Ada.Strings.Unbounded.Unbounded_String :=
                 Ada.Strings.Unbounded.To_Unbounded_String ("0" & CRLF);
            begin
               for Index in 1 .. Http_Client.Headers.Length (Trailer_Fields) loop
                  Ada.Strings.Unbounded.Append
                    (Trailer_Text, Http_Client.Headers.Name_At (Trailer_Fields, Index));
                  Ada.Strings.Unbounded.Append (Trailer_Text, ": ");
                  Ada.Strings.Unbounded.Append
                    (Trailer_Text, Http_Client.Headers.Value_At (Trailer_Fields, Index));
                  Ada.Strings.Unbounded.Append (Trailer_Text, CRLF);
               end loop;
               Ada.Strings.Unbounded.Append (Trailer_Text, CRLF);
               if Cancellation /= null
                 and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
               then
                  return Http_Client.Errors.Cancelled;
               end if;
               return Http_Client.Transports.TCP.Write_All
                 (Connection, Ada.Strings.Unbounded.To_String (Trailer_Text));
            end;
         end if;

         Status := Http_Client.Transports.TCP.Write_All
           (Connection, Hex_Image (Count) & CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Transports.TCP.Write_All
           (Connection, Buffer (Buffer'First .. Buffer'First + Count - 1));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Transports.TCP.Write_All (Connection, CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end loop;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Chunked_Upload_TCP;

   function Write_Chunked_Upload_TLS
     (Connection   : in out Http_Client.Transports.TLS.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Req_Body : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Buffer   : String (1 .. 8192);
      Count    : Natural := 0;
      Status   : Http_Client.Errors.Result_Status;
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
   begin
      loop
         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         Status := Http_Client.Request_Bodies.Read_Next
           (Req_Body, Buffer, Count);

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         if Count > Buffer'Length then
            return Http_Client.Errors.Body_Producer_Failed;
         elsif Count = 0 then
            declare
               Trailer_Fields : constant Http_Client.Headers.Header_List :=
                 Http_Client.Request_Bodies.Trailers (Req_Body);
               Trailer_Text   : Ada.Strings.Unbounded.Unbounded_String :=
                 Ada.Strings.Unbounded.To_Unbounded_String ("0" & CRLF);
            begin
               for Index in 1 .. Http_Client.Headers.Length (Trailer_Fields) loop
                  Ada.Strings.Unbounded.Append
                    (Trailer_Text, Http_Client.Headers.Name_At (Trailer_Fields, Index));
                  Ada.Strings.Unbounded.Append (Trailer_Text, ": ");
                  Ada.Strings.Unbounded.Append
                    (Trailer_Text, Http_Client.Headers.Value_At (Trailer_Fields, Index));
                  Ada.Strings.Unbounded.Append (Trailer_Text, CRLF);
               end loop;
               Ada.Strings.Unbounded.Append (Trailer_Text, CRLF);
               if Cancellation /= null
                 and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
               then
                  return Http_Client.Errors.Cancelled;
               end if;
               return Http_Client.Transports.TLS.Write_All
                 (Connection, Ada.Strings.Unbounded.To_String (Trailer_Text));
            end;
         end if;

         Status := Http_Client.Transports.TLS.Write_All
           (Connection, Hex_Image (Count) & CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Transports.TLS.Write_All
           (Connection, Buffer (Buffer'First .. Buffer'First + Count - 1));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.Transports.TLS.Write_All (Connection, CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end loop;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Chunked_Upload_TLS;

   function Write_Buffered_Upload_TCP
     (Connection   : in out Http_Client.Transports.TCP.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Payload : constant String :=
        Http_Client.Request_Bodies.Buffered_Payload
          (Http_Client.Requests.Request_Body (Request));
   begin
      if Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      end if;

      if Payload'Length = 0 then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Transports.TCP.Write_All (Connection, Payload);
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Buffered_Upload_TCP;

   function Write_Buffered_Upload_TLS
     (Connection   : in out Http_Client.Transports.TLS.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Payload : constant String :=
        Http_Client.Request_Bodies.Buffered_Payload
          (Http_Client.Requests.Request_Body (Request));
   begin
      if Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      end if;

      if Payload'Length = 0 then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Transports.TLS.Write_All (Connection, Payload);
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Buffered_Upload_TLS;

   function Write_Upload_TCP
     (Connection   : in out Http_Client.Transports.TCP.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Req_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Remaining : Natural := 0;
      Buffer    : String (1 .. 8192);
      Count     : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      if Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      end if;

      case Http_Client.Request_Bodies.Kind (Req_Body) is
         when Http_Client.Request_Bodies.Empty_Body |
              Http_Client.Request_Bodies.Buffered_Body =>
            return Http_Client.Errors.Ok;
         when Http_Client.Request_Bodies.Unknown_Length_Stream =>
            return Write_Chunked_Upload_TCP (Connection, Request, Cancellation);
         when Http_Client.Request_Bodies.Fixed_Length_Stream =>
            if not Http_Client.Request_Bodies.Declared_Length (Req_Body, Remaining) then
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
      end case;

      while Remaining > 0 loop
         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         declare
            Limit : constant Natural := Natural'Min (Remaining, Buffer'Length);
         begin
            Status := Http_Client.Request_Bodies.Read_Next
              (Req_Body,
               Buffer (Buffer'First .. Buffer'First + Limit - 1),
               Count);

            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Count = 0 or else Count > Limit or else Count > Remaining then
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
         end;

         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         Status := Http_Client.Transports.TCP.Write_All
           (Connection,
            Buffer (Buffer'First .. Buffer'First + Count - 1));

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Remaining := Remaining - Count;
      end loop;

      Status := Http_Client.Request_Bodies.Read_Next
        (Req_Body,
         Buffer (Buffer'First .. Buffer'First),
         Count);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      elsif Count /= 0 then
         return Http_Client.Errors.Body_Length_Mismatch;
      else
         return Http_Client.Errors.Ok;
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Upload_TCP;

   function Write_Upload_TLS
     (Connection   : in out Http_Client.Transports.TLS.Connection;
      Request      : Http_Client.Requests.Request;
      Cancellation : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
      Req_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Remaining : Natural := 0;
      Buffer    : String (1 .. 8192);
      Count     : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      if Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      end if;

      case Http_Client.Request_Bodies.Kind (Req_Body) is
         when Http_Client.Request_Bodies.Empty_Body |
              Http_Client.Request_Bodies.Buffered_Body =>
            return Http_Client.Errors.Ok;
         when Http_Client.Request_Bodies.Unknown_Length_Stream =>
            return Write_Chunked_Upload_TLS (Connection, Request, Cancellation);
         when Http_Client.Request_Bodies.Fixed_Length_Stream =>
            if not Http_Client.Request_Bodies.Declared_Length (Req_Body, Remaining) then
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
      end case;

      while Remaining > 0 loop
         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         declare
            Limit : constant Natural := Natural'Min (Remaining, Buffer'Length);
         begin
            Status := Http_Client.Request_Bodies.Read_Next
              (Req_Body,
               Buffer (Buffer'First .. Buffer'First + Limit - 1),
               Count);

            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Count = 0 or else Count > Limit or else Count > Remaining then
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
         end;

         if Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         end if;

         Status := Http_Client.Transports.TLS.Write_All
           (Connection,
            Buffer (Buffer'First .. Buffer'First + Count - 1));

         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Remaining := Remaining - Count;
      end loop;

      Status := Http_Client.Request_Bodies.Read_Next
        (Req_Body,
         Buffer (Buffer'First .. Buffer'First),
         Count);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Cancellation.all)
      then
         return Http_Client.Errors.Cancelled;
      elsif Count /= 0 then
         return Http_Client.Errors.Body_Length_Mismatch;
      else
         return Http_Client.Errors.Ok;
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Upload_TLS;

   procedure Close_Ignoring_Status
     (Connection : in out Http_Client.Transports.TCP.Connection)
   is
      Ignored : constant Http_Client.Errors.Result_Status :=
        Http_Client.Transports.TCP.Close (Connection);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Close_Ignoring_Status;

   procedure Close_Ignoring_Status
     (Connection : in out Http_Client.Transports.TLS.Connection)
   is
      Ignored : constant Http_Client.Errors.Result_Status :=
        Http_Client.Transports.TLS.Close (Connection);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Close_Ignoring_Status;

   procedure Free_TCP is new Ada.Unchecked_Deallocation
     (Http_Client.Transports.TCP.Connection, TCP_Connection_Access);

   procedure Free_TLS is new Ada.Unchecked_Deallocation
     (Http_Client.Transports.TLS.Connection, TLS_Connection_Access);

   procedure Close_And_Free (Slot : in out Pooled_Connection) is
   begin
      if Slot.TCP /= null then
         Close_Ignoring_Status (Slot.TCP.all);
         Free_TCP (Slot.TCP);
      end if;

      if Slot.TLS /= null then
         Close_Ignoring_Status (Slot.TLS.all);
         Free_TLS (Slot.TLS);
      end if;
   end Close_And_Free;

   procedure Clear_Real_Pool (State : Client_State_Access) is
   begin
      if State = null then
         return;
      end if;

      while not State.Entries.Is_Empty loop
         declare
            Slot : Pooled_Connection := State.Entries (State.Entries.First_Index);
         begin
            State.Entries.Delete_First;
            Close_And_Free (Slot);
         end;
      end loop;

      Http_Client.Connection_Pools.Close_All (State.Pool);
   end Clear_Real_Pool;

   function Seconds_Elapsed
     (Earlier : Ada.Calendar.Time;
      Later   : Ada.Calendar.Time) return Natural
   is
      Elapsed : constant Duration := Later - Earlier;
   begin
      if Elapsed <= 0.0 then
         return 0;
      elsif Elapsed >= Duration (Natural'Last) then
         return Natural'Last;
      else
         return Natural (Elapsed);
      end if;
   end Seconds_Elapsed;

   function Entry_Expired
     (Slot    : Pooled_Connection;
      Options : Http_Client.Connection_Pools.Pooling_Options;
      Now     : Ada.Calendar.Time) return Boolean is
   begin
      if Options.Max_Connection_Age_Seconds > 0
        and then Seconds_Elapsed (Slot.Created_At, Now) >=
          Options.Max_Connection_Age_Seconds
      then
         return True;
      end if;

      if Options.Max_Idle_Time_Seconds > 0
        and then Seconds_Elapsed (Slot.Last_Used_At, Now) >=
          Options.Max_Idle_Time_Seconds
      then
         return True;
      end if;

      if Options.Max_Requests_Per_Connection = 0
        or else Slot.Request_Count >= Options.Max_Requests_Per_Connection
      then
         return True;
      end if;

      return False;
   end Entry_Expired;

   procedure Prune_Real_Pool
     (State   : Client_State_Access;
      Options : Http_Client.Connection_Pools.Pooling_Options)
   is
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      I   : Positive;
   begin
      if State = null or else State.Entries.Is_Empty then
         return;
      end if;

      I := State.Entries.First_Index;
      while I <= State.Entries.Last_Index loop
         if Entry_Expired (State.Entries (I), Options, Now) then
            declare
               Victim : Pooled_Connection := State.Entries (I);
            begin
               State.Entries.Delete (I);
               Close_And_Free (Victim);
            end;
            exit when State.Entries.Is_Empty;
         else
            I := I + 1;
         end if;
      end loop;
   end Prune_Real_Pool;

   function Real_Pool_Count_For
     (State : Client_State_Access;
      Key   : Http_Client.Connection_Pools.Pool_Key) return Natural
   is
      Count : Natural := 0;
   begin
      if State = null or else State.Entries.Is_Empty then
         return 0;
      end if;

      for Slot of State.Entries loop
         if Http_Client.Connection_Pools.Same_Key (Slot.Key, Key) then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Real_Pool_Count_For;

   procedure Enforce_Real_Pool_Limits
     (State   : Client_State_Access;
      Key     : Http_Client.Connection_Pools.Pool_Key;
      Options : Http_Client.Connection_Pools.Pooling_Options)
   is
      I : Positive;
   begin
      if State = null then
         return;
      end if;

      while Natural (State.Entries.Length) > Options.Max_Total_Idle_Connections loop
         declare
            Victim : Pooled_Connection := State.Entries (State.Entries.First_Index);
         begin
            State.Entries.Delete_First;
            Close_And_Free (Victim);
         end;
      end loop;

      if State.Entries.Is_Empty then
         return;
      end if;

      I := State.Entries.First_Index;
      while I <= State.Entries.Last_Index
        and then Real_Pool_Count_For (State, Key) > Options.Max_Idle_Connections_Per_Key
      loop
         if Http_Client.Connection_Pools.Same_Key (State.Entries (I).Key, Key) then
            declare
               Victim : Pooled_Connection := State.Entries (I);
            begin
               State.Entries.Delete (I);
               Close_And_Free (Victim);
            end;
            exit when State.Entries.Is_Empty;
         else
            I := I + 1;
         end if;
      end loop;
   end Enforce_Real_Pool_Limits;

   function Acquire_TCP
     (Item          : Client;
      Key           : Http_Client.Connection_Pools.Pool_Key;
      Options       : Http_Client.Connection_Pools.Pooling_Options;
      Result        : out TCP_Connection_Access;
      Request_Count : out Natural) return Boolean
   is
      I   : Positive;
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      Result := null;
      Request_Count := 0;
      if Item.State = null or else not Options.Enabled then
         return False;
      end if;

      Prune_Real_Pool (Item.State, Options);
      if Item.State.Entries.Is_Empty then
         return False;
      end if;

      I := Item.State.Entries.First_Index;
      while I <= Item.State.Entries.Last_Index loop
         if Item.State.Entries (I).Kind = Pooled_TCP
           and then Http_Client.Connection_Pools.Same_Key (Item.State.Entries (I).Key, Key)
         then
            declare
               Slot : Pooled_Connection := Item.State.Entries (I);
            begin
               Item.State.Entries.Delete (I);
               Result := Slot.TCP;
               Slot.TCP := null;
               Request_Count := Slot.Request_Count + 1;
               Slot.Last_Used_At := Now;
               return Result /= null;
            end;
         end if;
         I := I + 1;
      end loop;
      return False;
   end Acquire_TCP;

   function Acquire_TLS
     (Item          : Client;
      Key           : Http_Client.Connection_Pools.Pool_Key;
      Options       : Http_Client.Connection_Pools.Pooling_Options;
      Result        : out TLS_Connection_Access;
      Request_Count : out Natural) return Boolean
   is
      I   : Positive;
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      Result := null;
      Request_Count := 0;
      if Item.State = null or else not Options.Enabled then
         return False;
      end if;

      Prune_Real_Pool (Item.State, Options);
      if Item.State.Entries.Is_Empty then
         return False;
      end if;

      I := Item.State.Entries.First_Index;
      while I <= Item.State.Entries.Last_Index loop
         if Item.State.Entries (I).Kind = Pooled_TLS
           and then Http_Client.Connection_Pools.Same_Key (Item.State.Entries (I).Key, Key)
         then
            declare
               Slot : Pooled_Connection := Item.State.Entries (I);
            begin
               Item.State.Entries.Delete (I);
               Result := Slot.TLS;
               Slot.TLS := null;
               Request_Count := Slot.Request_Count + 1;
               Slot.Last_Used_At := Now;
               return Result /= null;
            end;
         end if;
         I := I + 1;
      end loop;
      return False;
   end Acquire_TLS;

   procedure Release_TCP
     (Item     : Client;
      Key      : Http_Client.Connection_Pools.Pool_Key;
      Options  : Http_Client.Connection_Pools.Pooling_Options;
      Conn     : in out TCP_Connection_Access;
      Reusable : Boolean;
      Count    : Natural := 1) is
   begin
      if Conn = null then
         return;
      end if;

      if Item.State = null or else not Options.Enabled or else not Reusable then
         Close_Ignoring_Status (Conn.all);
         Free_TCP (Conn);
         return;
      end if;

      declare
         Now   : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Slot : Pooled_Connection :=
           (Key           => Key,
            Token         => <>,
            Kind          => Pooled_TCP,
            TCP           => Conn,
            TLS           => null,
            Created_At    => Now,
            Last_Used_At  => Now,
            Request_Count => Count);
      begin
         Conn := null;
         if Entry_Expired (Slot, Options, Now) then
            Close_And_Free (Slot);
            return;
         end if;
         Item.State.Entries.Append (Slot);
         Enforce_Real_Pool_Limits (Item.State, Key, Options);
      end;
   end Release_TCP;

   procedure Release_TLS
     (Item     : Client;
      Key      : Http_Client.Connection_Pools.Pool_Key;
      Options  : Http_Client.Connection_Pools.Pooling_Options;
      Conn     : in out TLS_Connection_Access;
      Reusable : Boolean;
      Count    : Natural := 1) is
   begin
      if Conn = null then
         return;
      end if;

      if Item.State = null or else not Options.Enabled or else not Reusable then
         Close_Ignoring_Status (Conn.all);
         Free_TLS (Conn);
         return;
      end if;

      declare
         Now   : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Slot : Pooled_Connection :=
           (Key           => Key,
            Token         => <>,
            Kind          => Pooled_TLS,
            TCP           => null,
            TLS           => Conn,
            Created_At    => Now,
            Last_Used_At  => Now,
            Request_Count => Count);
      begin
         Conn := null;
         if Entry_Expired (Slot, Options, Now) then
            Close_And_Free (Slot);
            return;
         end if;
         Item.State.Entries.Append (Slot);
         Enforce_Real_Pool_Limits (Item.State, Key, Options);
      end;
   end Release_TLS;

   function Execute
     (Item     : Client;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Options  : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status
   is
      URI          : Http_Client.URI.URI_Reference;
      Request_Text : Unbounded_String;
      Wire_Request : Http_Client.Requests.Request;
      Raw_Response : Unbounded_String := Null_Unbounded_String;
      Status       : Http_Client.Errors.Result_Status;
      Request_ID   : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID: Http_Client.Diagnostics.Diagnostic_ID := 0;
      Request_Start_Time : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);

      function Read_TCP_Response is new Http_Client.HTTP1.Reader.Read_Response
        (Connection_Type => Http_Client.Transports.TCP.Connection,
         Read_Some       => Http_Client.Transports.TCP.Read_Some);

      function Read_TLS_Response is new Http_Client.HTTP1.Reader.Read_Response
        (Connection_Type => Http_Client.Transports.TLS.Connection,
         Read_Some       => Http_Client.Transports.TLS.Read_Some);

      function Wait_For_100_TCP is new Wait_For_100_Continue
        (Connection_Type => Http_Client.Transports.TCP.Connection,
         Read_Some       => Http_Client.Transports.TCP.Read_Some);

      function Wait_For_100_TLS is new Wait_For_100_Continue
        (Connection_Type => Http_Client.Transports.TLS.Connection,
         Read_Some       => Http_Client.Transports.TLS.Read_Some);

      function Emit_Request_Finish
        (Final_Status : Http_Client.Errors.Result_Status)
         return Http_Client.Errors.Result_Status
      is
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_Diagnostic
             (Options,
              (Kind                 => Http_Client.Diagnostics.Request_Finish,
               Request_ID           => Request_ID,
               Connection_ID        => Connection_ID,
               Result               => Final_Status,
               Status_Code          =>
                 (if Final_Status = Http_Client.Errors.Ok
                  then Natural (Http_Client.Responses.Status_Code (Response))
                  else 0),
               Elapsed_Milliseconds =>
                 (if Diagnostics_Active (Options)
                  then Http_Client.Diagnostics.Elapsed_Milliseconds
                    (Options.Diagnostics.all,
                     Request_Start_Time,
                     Http_Client.Diagnostics.Now (Options.Diagnostics.all))
                  else 0),
               others               => <>));
      begin
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         else
            return Final_Status;
         end if;
      end Emit_Request_Finish;

      function Check_Cancelled return Http_Client.Errors.Result_Status is
      begin
         if Options.Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
         then
            return Http_Client.Errors.Cancelled;
         else
            return Http_Client.Errors.Ok;
         end if;
      end Check_Cancelled;

      function Execute_TCP return Http_Client.Errors.Result_Status is
         Connection : TCP_Connection_Access := null;
         Pool_Key   : constant Http_Client.Connection_Pools.Pool_Key :=
           Http_Client.Connection_Pools.Key_For (URI, Options.Proxy, Options.TLS);
         Reused_Connection : Boolean := False;
         Pool_Request_Count : Natural := 1;
      begin
         Reused_Connection := Acquire_TCP
           (Item, Pool_Key, Item.Config.Pooling, Connection, Pool_Request_Count);
         if not Reused_Connection then
            Connection := new Http_Client.Transports.TCP.Connection;
            Pool_Request_Count := 1;
         end if;

         Connection_ID := New_Connection_ID (Options);
         if Reused_Connection then
            Status := Emit_Diagnostic
              (Options,
               (Kind          => Http_Client.Diagnostics.Connection_Pool_Checkout,
                Request_ID    => Request_ID,
                Connection_ID => Connection_ID,
                Result        => Http_Client.Errors.Ok,
                Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                Message       => Http_Client.Diagnostics.To_Text ("pool-hit"),
                others        => <>));
            if Status /= Http_Client.Errors.Ok then
               Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Status;
            end if;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind          => Http_Client.Diagnostics.DNS_Connect_Start,
             Request_ID    => Request_ID,
             Connection_ID => Connection_ID,
             URI_Or_Origin => Http_Client.Diagnostics.To_Text
               ((if Http_Client.Proxies.Is_Enabled (Options.Proxy)
                 then Http_Client.Proxies.Host (Options.Proxy)
                 else Http_Client.URI.Host (URI))),
             Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
             others        => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;
         if Reused_Connection then
            null;
         elsif Http_Client.Proxies.Is_Enabled (Options.Proxy) then
            if Http_Client.Proxies.Kind (Options.Proxy) =
              Http_Client.Proxies.HTTP_Proxy
            then
               Status :=
                 Http_Client.Transports.TCP.Open
                   (Item     => Connection.all,
                    Host     => Http_Client.Proxies.Host (Options.Proxy),
                    Port     => Http_Client.Proxies.Port (Options.Proxy),
                    Timeouts => Options.Timeouts);

               if Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  --  The TCP transport reports DNS, connect, and timeout failures
                  --  in transport-native terms. When the connection target is an
                  --  explicitly configured proxy, normalize those open-time
                  --  failures to the proxy-specific status so callers can
                  --  distinguish proxy reachability problems from origin-server
                  --  reachability problems.
                  if Status = Http_Client.Errors.Connection_Failed
                    or else Status = Http_Client.Errors.DNS_Failed
                    or else Status = Http_Client.Errors.Timeout
                  then
                     return Http_Client.Errors.Proxy_Connection_Failed;
                  else
                     return Status;
                  end if;
               end if;
            elsif Http_Client.Proxies.Kind (Options.Proxy) =
              Http_Client.Proxies.SOCKS5_Proxy
            then
               Status := Emit_Diagnostic
                 (Options,
                  (Kind          => Http_Client.Diagnostics.SOCKS_Proxy_Selected,
                   Request_ID    => Request_ID,
                   Connection_ID => Connection_ID,
                   URI_Or_Origin => Http_Client.Diagnostics.To_Text
                     (Http_Client.Proxies.Host (Options.Proxy)),
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others        => <>));
               if Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               end if;

               Status := Emit_Diagnostic
                 (Options,
                  (Kind          => Http_Client.Diagnostics.SOCKS_Tunnel_Start,
                   Request_ID    => Request_ID,
                   Connection_ID => Connection_ID,
                   URI_Or_Origin => Http_Client.Diagnostics.To_Text
                     ("<socks-target-redacted>"),
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   Message       => Http_Client.Diagnostics.To_Text
                     ("target-type=origin"),
                   others        => <>));
               if Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               end if;

               Status :=
                 Http_Client.Transports.SOCKS.Open_Tunnel
                   (Connection  => Connection.all,
                    Proxy         => Options.Proxy,
                    Target_Host   => Http_Client.URI.Host (URI),
                    Target_Port   => Http_Client.URI.Effective_Port (URI),
                    Timeouts      => Options.Timeouts,
                    Diagnostics   => Options.Diagnostics,
                    Request_ID    => Request_ID,
                    Connection_ID => Connection_ID);

               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind          => Http_Client.Diagnostics.SOCKS_Tunnel_Finished,
                        Request_ID    => Request_ID,
                        Connection_ID => Connection_ID,
                        Result        => Status,
                        Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                        others        => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                     return Emit_Status;
                  end if;
               end;

               if Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               end if;
            else
               Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Http_Client.Errors.Proxy_Unsupported;
            end if;
         else
            Status :=
              Http_Client.Transports.TCP.Open_URI
                (Item     => Connection.all,
                 URI      => URI,
                 Timeouts => Options.Timeouts);

            if Status /= Http_Client.Errors.Ok then
               Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Status;
            end if;
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind          => Http_Client.Diagnostics.TCP_Connection_Opened,
             Request_ID    => Request_ID,
             Connection_ID => Connection_ID,
             Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
             Result        => Http_Client.Errors.Ok,
             others        => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status :=
           Http_Client.Transports.TCP.Write_All
             (Connection.all,
              To_String (Request_Text));

         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind               => Http_Client.Diagnostics.Request_Headers_Sent,
             Request_ID         => Request_ID,
             Connection_ID      => Connection_ID,
             Request_Byte_Count => To_String (Request_Text)'Length,
             Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
             others             => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Request_Expects_100_Continue (Wire_Request) then
            declare
               Continue_Granted : Boolean := False;
            begin
               Status := Wait_For_100_TCP
                 (Connection       => Connection.all,
                  Context          => Parse_Context_For (Wire_Request),
                  Options          => Options,
                  Final_Response   => Response,
                  Continue_Granted => Continue_Granted);
               if Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               elsif not Continue_Granted then
                  --  The server sent a final response instead of 100 Continue.
                  --  Do not send the request body. Wait_For_100_TCP has already
                  --  parsed the final response body for buffered execution.
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Request_Finish (Http_Client.Errors.Ok);
               end if;
            end;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Request_Expects_100_Continue (Wire_Request)
           and then Http_Client.Request_Bodies.Kind
             (Http_Client.Requests.Request_Body (Wire_Request)) =
               Http_Client.Request_Bodies.Buffered_Body
         then
            Status := Write_Buffered_Upload_TCP (Connection.all, Wire_Request, Options.Cancellation);
         else
            Status := Write_Upload_TCP (Connection.all, Wire_Request, Options.Cancellation);
         end if;

         declare
            Len         : Natural := 0;
            Has_Length  : constant Boolean :=
              Http_Client.Request_Bodies.Declared_Length
                (Http_Client.Requests.Request_Body (Wire_Request), Len);
            Emit_Status : Http_Client.Errors.Result_Status;
         begin
            if Status /= Http_Client.Errors.Ok then
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind          => Http_Client.Diagnostics.Upload_Producer_Event,
                   Request_ID    => Request_ID,
                   Connection_ID => Connection_ID,
                   Result        => Status,
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   Message       => Http_Client.Diagnostics.To_Text ("upload producer failed"),
                   others        => <>));
               Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
               return Status;
            end if;

            if Has_Length and then Len > 0 then
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind               => Http_Client.Diagnostics.Upload_Producer_Event,
                   Request_ID         => Request_ID,
                   Connection_ID      => Connection_ID,
                   Request_Byte_Count => Len,
                   Result             => Http_Client.Errors.Ok,
                   Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   Message            => Http_Client.Diagnostics.To_Text ("upload producer completed"),
                   others             => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;

               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind               => Http_Client.Diagnostics.Request_Body_Progress,
                   Request_ID         => Request_ID,
                   Connection_ID      => Connection_ID,
                   Request_Byte_Count => Len,
                   Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others             => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;
            end if;
         end;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status :=
           Read_TCP_Response
             (Connection => Connection.all,
              Context    => Parse_Context_For (Request),
              Raw        => Raw_Response,
              Response   => Response,
              Options    => Reader_Options_For (Options));

         if Status = Http_Client.Errors.Ok then
            declare
               Emit_Status : Http_Client.Errors.Result_Status;
            begin
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind                => Http_Client.Diagnostics.Response_Headers_Received,
                   Request_ID          => Request_ID,
                   Connection_ID       => Connection_ID,
                   Status_Code         => Natural (Http_Client.Responses.Status_Code (Response)),
                   Response_Byte_Count => Header_Section_Byte_Count (Raw_Response),
                   Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others              => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;

               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
                   Request_ID          => Request_ID,
                   Connection_ID       => Connection_ID,
                   Response_Byte_Count => Http_Client.Responses.Response_Body (Response)'Length,
                   Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others              => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;
            end;
         end if;

         declare
            May_Reuse : constant Boolean :=
              Status = Http_Client.Errors.Ok
              and then Http_Client.Connection_Pools.Response_Permits_Reuse
                (Wire_Request, Response);
         begin
            if May_Reuse then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind          => Http_Client.Diagnostics.Connection_Pool_Checkin,
                        Request_ID    => Request_ID,
                        Connection_ID => Connection_ID,
                        Result        => Http_Client.Errors.Ok,
                        Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                        Message       => Http_Client.Diagnostics.To_Text ("pool-checkin"),
                        others        => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     Release_TCP
                       (Item, Pool_Key, Item.Config.Pooling, Connection,
                        Reusable => False);
                     return Emit_Status;
                  end if;
               end;
            end if;

            Release_TCP
              (Item,
               Pool_Key,
               Item.Config.Pooling,
               Connection,
               Reusable => May_Reuse,
               Count    => Pool_Request_Count);
            return Status;
         end;
      exception
         when others =>
            Release_TCP (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Http_Client.Errors.Internal_Error;
      end Execute_TCP;

      function Execute_TLS return Http_Client.Errors.Result_Status
      is
         Connection    : TLS_Connection_Access := null;
         Effective_TLS : Http_Client.Transports.TLS.TLS_Options :=
           Effective_TLS_Options_For_Request (Request, Options);
         Pool_Key      : Http_Client.Connection_Pools.Pool_Key;
         Reused_Connection : Boolean := False;
         Pool_Request_Count : Natural := 1;
         TLS_Start_Time : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      begin
         Pool_Key := Http_Client.Connection_Pools.Key_For
           (URI, Options.Proxy, Effective_TLS);

         Reused_Connection := Acquire_TLS
           (Item, Pool_Key, Item.Config.Pooling, Connection, Pool_Request_Count);
         if not Reused_Connection then
            Pool_Request_Count := 1;
            Connection := new Http_Client.Transports.TLS.Connection;
         end if;

         Connection_ID := New_Connection_ID (Options);
         if Reused_Connection then
            Status := Emit_Diagnostic
              (Options,
               (Kind          => Http_Client.Diagnostics.Connection_Pool_Checkout,
                Request_ID    => Request_ID,
                Connection_ID => Connection_ID,
                Result        => Http_Client.Errors.Ok,
                Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                Message       => Http_Client.Diagnostics.To_Text ("pool-hit"),
                others        => <>));
            if Status /= Http_Client.Errors.Ok then
               Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Status;
            end if;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Diagnostics_Active (Options) then
            TLS_Start_Time := Http_Client.Diagnostics.Now (Options.Diagnostics.all);
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind          => Http_Client.Diagnostics.TLS_Handshake_Start,
             Request_ID    => Request_ID,
             Connection_ID => Connection_ID,
             URI_Or_Origin => Http_Client.Diagnostics.To_Text (Http_Client.URI.Host (URI)),
             Protocol      => Http_Client.Diagnostics.Protocol_Unknown,
             others        => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Reused_Connection then
            Status := Http_Client.Errors.Ok;
         elsif Http_Client.Proxies.Is_Enabled (Options.Proxy) then
            if Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.HTTP_Proxy then
               Status :=
                 Http_Client.Transports.TLS.Open_Through_HTTP_Proxy
                   (Item                => Connection.all,
                    Host                => Http_Client.URI.Host (URI),
                    Port                => Http_Client.URI.Effective_Port (URI),
                    Proxy_Host          => Http_Client.Proxies.Host (Options.Proxy),
                    Proxy_Port          => Http_Client.Proxies.Port (Options.Proxy),
                    Proxy_Authorization =>
                      (if Http_Client.Proxies.Has_Proxy_Authorization (Options.Proxy)
                       then Http_Client.Proxies.Proxy_Authorization (Options.Proxy)
                       else ""),
                    Options             => Effective_TLS);
            elsif Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy then
               Status :=
                 Http_Client.Transports.TLS.Open_Through_SOCKS_Proxy
                   (Item    => Connection.all,
                    Host    => Http_Client.URI.Host (URI),
                    Port    => Http_Client.URI.Effective_Port (URI),
                    Proxy   => Options.Proxy,
                    Options => Effective_TLS);
            else
               Status := Http_Client.Errors.Proxy_Unsupported;
            end if;
         else
            Status :=
              Http_Client.Transports.TLS.Open_URI
                (Item    => Connection.all,
                 URI     => URI,
                 Options => Effective_TLS);
         end if;

         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Diagnostic
                   (Options,
                    (Kind                 => Http_Client.Diagnostics.TLS_Handshake_Finished,
                     Request_ID           => Request_ID,
                     Connection_ID        => Connection_ID,
                     Result               => Status,
                     Elapsed_Milliseconds =>
                       (if Diagnostics_Active (Options)
                        then Http_Client.Diagnostics.Elapsed_Milliseconds
                          (Options.Diagnostics.all,
                           TLS_Start_Time,
                           Http_Client.Diagnostics.Now (Options.Diagnostics.all))
                        else 0),
                     others               => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
            end;
            return Status;
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind                 => Http_Client.Diagnostics.TLS_Handshake_Finished,
             Request_ID           => Request_ID,
             Connection_ID        => Connection_ID,
             Result               => Http_Client.Errors.Ok,
             Elapsed_Milliseconds =>
               (if Diagnostics_Active (Options)
                then Http_Client.Diagnostics.Elapsed_Milliseconds
                  (Options.Diagnostics.all,
                   TLS_Start_Time,
                   Http_Client.Diagnostics.Now (Options.Diagnostics.all))
                else 0),
             others               => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         declare
            Selected : constant Http_Client.HTTP2.Selected_Protocol :=
              Http_Client.Transports.TLS.Selected_ALPN (Connection.all);
         begin
            Status :=
              Http_Client.HTTP2.Execution_Status_For_Selected
                (Options  => Effective_TLS.HTTP2,
                 Selected => Selected);

            if Status /= Http_Client.Errors.Ok then
               Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Status;
            end if;

            if Selected = Http_Client.HTTP2.Protocol_HTTP_2 then
               Status := Emit_Diagnostic
                 (Options,
                  (Kind          => Http_Client.Diagnostics.HTTP2_Stream_Opened,
                   Request_ID    => Request_ID,
                   Connection_ID => Connection_ID,
                   Stream_ID     => 1,
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_2,
                   others        => <>));
               if Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               end if;

               Status := Http_Client.HTTP2.Single_Stream.Execute_TLS
                 (Connection => Connection.all,
                  Request    => Wire_Request,
                  Options    => Effective_TLS.HTTP2,
                  Response   => Response);

               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind          => Http_Client.Diagnostics.HTTP2_Stream_Closed,
                        Request_ID    => Request_ID,
                        Connection_ID => Connection_ID,
                        Stream_ID     => 1,
                        Result        => Status,
                        Protocol      => Http_Client.Diagnostics.Protocol_HTTP_2,
                        others        => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                     return Emit_Status;
                  end if;
               end;
               Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               return Status;
            end if;
         end;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status :=
           Http_Client.Transports.TLS.Write_All
             (Connection.all,
              To_String (Request_Text));

         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Emit_Diagnostic
           (Options,
            (Kind               => Http_Client.Diagnostics.Request_Headers_Sent,
             Request_ID         => Request_ID,
             Connection_ID      => Connection_ID,
             Request_Byte_Count => To_String (Request_Text)'Length,
             Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
             others             => <>));
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Request_Expects_100_Continue (Wire_Request) then
            declare
               Continue_Granted : Boolean := False;
            begin
               Status := Wait_For_100_TLS
                 (Connection       => Connection.all,
                  Context          => Parse_Context_For (Wire_Request),
                  Options          => Options,
                  Final_Response   => Response,
                  Continue_Granted => Continue_Granted);
               if Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Status;
               elsif not Continue_Granted then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Request_Finish (Http_Client.Errors.Ok);
               end if;
            end;
         end if;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         if Request_Expects_100_Continue (Wire_Request)
           and then Http_Client.Request_Bodies.Kind
             (Http_Client.Requests.Request_Body (Wire_Request)) =
               Http_Client.Request_Bodies.Buffered_Body
         then
            Status := Write_Buffered_Upload_TLS (Connection.all, Wire_Request, Options.Cancellation);
         else
            Status := Write_Upload_TLS (Connection.all, Wire_Request, Options.Cancellation);
         end if;

         declare
            Len         : Natural := 0;
            Has_Length  : constant Boolean :=
              Http_Client.Request_Bodies.Declared_Length
                (Http_Client.Requests.Request_Body (Wire_Request), Len);
            Emit_Status : Http_Client.Errors.Result_Status;
         begin
            if Status /= Http_Client.Errors.Ok then
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind          => Http_Client.Diagnostics.Upload_Producer_Event,
                   Request_ID    => Request_ID,
                   Connection_ID => Connection_ID,
                   Result        => Status,
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   Message       => Http_Client.Diagnostics.To_Text ("upload producer failed"),
                   others        => <>));
               Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
               return Status;
            end if;

            if Has_Length and then Len > 0 then
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind               => Http_Client.Diagnostics.Upload_Producer_Event,
                   Request_ID         => Request_ID,
                   Connection_ID      => Connection_ID,
                   Request_Byte_Count => Len,
                   Result             => Http_Client.Errors.Ok,
                   Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   Message            => Http_Client.Diagnostics.To_Text ("upload producer completed"),
                   others             => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;

               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind               => Http_Client.Diagnostics.Request_Body_Progress,
                   Request_ID         => Request_ID,
                   Connection_ID      => Connection_ID,
                   Request_Byte_Count => Len,
                   Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others             => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;
            end if;
         end;

         Status := Check_Cancelled;
         if Status /= Http_Client.Errors.Ok then
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Status;
         end if;

         Status :=
           Read_TLS_Response
             (Connection => Connection.all,
              Context    => Parse_Context_For (Request),
              Raw        => Raw_Response,
              Response   => Response,
              Options    => Reader_Options_For (Options));

         if Status = Http_Client.Errors.Ok then
            declare
               Emit_Status : Http_Client.Errors.Result_Status;
            begin
               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind                => Http_Client.Diagnostics.Response_Headers_Received,
                   Request_ID          => Request_ID,
                   Connection_ID       => Connection_ID,
                   Status_Code         => Natural (Http_Client.Responses.Status_Code (Response)),
                   Response_Byte_Count => Header_Section_Byte_Count (Raw_Response),
                   Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others              => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;

               Emit_Status := Emit_Diagnostic
                 (Options,
                  (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
                   Request_ID          => Request_ID,
                   Connection_ID       => Connection_ID,
                   Response_Byte_Count => Http_Client.Responses.Response_Body (Response)'Length,
                   Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                   others              => <>));
               if Emit_Status /= Http_Client.Errors.Ok then
                  Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
                  return Emit_Status;
               end if;
            end;
         end if;

         declare
            May_Reuse : constant Boolean :=
              Status = Http_Client.Errors.Ok
              and then Http_Client.Connection_Pools.Response_Permits_Reuse
                (Wire_Request, Response);
         begin
            if May_Reuse then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind          => Http_Client.Diagnostics.Connection_Pool_Checkin,
                        Request_ID    => Request_ID,
                        Connection_ID => Connection_ID,
                        Result        => Http_Client.Errors.Ok,
                        Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                        Message       => Http_Client.Diagnostics.To_Text ("pool-checkin"),
                        others        => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     Release_TLS
                       (Item, Pool_Key, Item.Config.Pooling, Connection,
                        Reusable => False);
                     return Emit_Status;
                  end if;
               end;
            end if;

            Release_TLS
              (Item,
               Pool_Key,
               Item.Config.Pooling,
               Connection,
               Reusable => May_Reuse,
               Count    => Pool_Request_Count);
            return Status;
         end;
      exception
         when others =>
            Release_TLS (Item, Pool_Key, Item.Config.Pooling, Connection, Reusable => False);
            return Http_Client.Errors.Internal_Error;
      end Execute_TLS;
   begin
      Response := Http_Client.Responses.Default_Response;

      Status := Check_Cancelled;
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      URI := Http_Client.Requests.URI (Request);

      if not Http_Client.URI.Is_Parsed (URI) then
         return Http_Client.Errors.Invalid_URI;
      end if;

      if Options.Protocol_Policy = Force_HTTP_2
        and then not Http_Client.URI.Requires_TLS (URI)
      then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;

      if Options.Protocol_Policy = Force_HTTP_3 then
         if not Http_Client.URI.Requires_TLS (URI) then
            return Http_Client.Errors.HTTP3_Unsupported;
         elsif Http_Client.Proxies.Is_Enabled (Options.Proxy) then
            return Http_Client.Errors.HTTP3_Proxy_Unsupported;
         else
            return Http_Client.Errors.QUIC_Unsupported;
         end if;
      end if;

      Request_ID := New_Request_ID (Options);
      if Diagnostics_Active (Options) then
         Request_Start_Time := Http_Client.Diagnostics.Now (Options.Diagnostics.all);
      end if;
      Status := Emit_Diagnostic
        (Options,
         (Kind          => Http_Client.Diagnostics.Request_Start,
          Request_ID    => Request_ID,
          URI_Or_Origin => Http_Client.Diagnostics.To_Text
            (Http_Client.URI.Scheme (URI) & "://" & Http_Client.URI.Authority_Host (URI)),
          Has_Method    => True,
          Method        => Http_Client.Requests.Method (Request),
          others        => <>));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Check_Cancelled;
      if Status /= Http_Client.Errors.Ok then
         return Emit_Request_Finish (Status);
      end if;

      Status := Serialized_Request
        (Request     => Request,
         Options     => Options,
         Output      => Request_Text,
         Wire_Request => Wire_Request,
         Target_Mode =>
           (if Http_Client.Proxies.Is_Enabled (Options.Proxy)
              and then Http_Client.Proxies.Kind (Options.Proxy) =
                Http_Client.Proxies.HTTP_Proxy
              and then not Http_Client.URI.Requires_TLS
                (Http_Client.Requests.URI (Request))
            then Http_Client.HTTP1.Absolute_Form
            else Http_Client.HTTP1.Origin_Form));

      if Status /= Http_Client.Errors.Ok then
         return Emit_Request_Finish (Status);
      end if;

      Status := Check_Cancelled;
      if Status /= Http_Client.Errors.Ok then
         return Emit_Request_Finish (Status);
      end if;

      if Http_Client.URI.Requires_TLS (URI) then
         if Http_Client.Proxies.Is_Enabled (Options.Proxy)
           and then Http_Client.Proxies.Kind (Options.Proxy) not in
             Http_Client.Proxies.HTTP_Proxy | Http_Client.Proxies.SOCKS5_Proxy
         then
            return Emit_Request_Finish (Http_Client.Errors.Proxy_Unsupported);
         end if;

         Status := Execute_TLS;
      else
         Status := Execute_TCP;
      end if;

      if Status = Http_Client.Errors.Ok and then Options.Cookie_Jar /= null then
         declare
            Cookie_Status : Http_Client.Errors.Result_Status;
         begin
            Http_Client.Cookies.Store_From_Response
              (Jar        => Options.Cookie_Jar.all,
               Origin_URI => URI,
               Headers    => Http_Client.Responses.Headers (Response),
               Strict     => Options.Strict_Cookies,
               Status     => Cookie_Status);

            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Diagnostic
                   (Options,
                    (Kind       => Http_Client.Diagnostics.Cookie_Storage_Decision,
                     Request_ID => Request_ID,
                     Result     => Cookie_Status,
                     Message    => Http_Client.Diagnostics.To_Text
                       ((if Cookie_Status = Http_Client.Errors.Ok
                         then "set-cookie processed"
                         else "set-cookie rejected")),
                     others     => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
            end;

            if Options.Strict_Cookies and then Cookie_Status /= Http_Client.Errors.Ok then
               return Emit_Request_Finish (Cookie_Status);
            end if;
         end;
      end if;

      return Emit_Request_Finish (Status);
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         if Request_ID /= 0 then
            return Emit_Request_Finish (Http_Client.Errors.Internal_Error);
         else
            return Http_Client.Errors.Internal_Error;
         end if;
   end Execute;


   function Request_Has_Cache_Token
     (Request : Http_Client.Requests.Request;
      Token   : String) return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Value   : constant String :=
        Ada.Characters.Handling.To_Lower
          (Http_Client.Headers.Get (Headers, "Cache-Control"));
      Wanted  : constant String := Ada.Characters.Handling.To_Lower (Token);
      Start   : Positive := Value'First;
      Stop    : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      while Start <= Value'Last loop
         Stop := Start;
         while Stop <= Value'Last and then Value (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part  : constant String :=
              Ada.Strings.Fixed.Trim (Value (Start .. Stop - 1), Ada.Strings.Both);
            Delim : Natural := Part'First;
         begin
            while Delim <= Part'Last
              and then Part (Delim) /= ';'
              and then Part (Delim) /= '='
            loop
               Delim := Delim + 1;
            end loop;

            if Ada.Strings.Fixed.Trim
                 ((if Delim > Part'First
                   then Part (Part'First .. Delim - 1)
                   else Part),
                  Ada.Strings.Both) = Wanted
            then
               return True;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return False;
   end Request_Has_Cache_Token;

   function Request_Cache_Natural_Directive
     (Request : Http_Client.Requests.Request;
      Name    : String;
      Value   : out Natural) return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Text    : constant String :=
        Ada.Characters.Handling.To_Lower
          (Http_Client.Headers.Get (Headers, "Cache-Control"));
      Wanted  : constant String := Ada.Characters.Handling.To_Lower (Name);
      Start   : Positive := Text'First;
      Stop    : Natural;
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;

      while Start <= Text'Last loop
         Stop := Start;
         while Stop <= Text'Last and then Text (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part : constant String :=
              Ada.Strings.Fixed.Trim (Text (Start .. Stop - 1), Ada.Strings.Both);
            Eq : Natural := Part'First;
         begin
            while Eq <= Part'Last and then Part (Eq) /= '=' loop
               Eq := Eq + 1;
            end loop;

            if Eq <= Part'Last
              and then Ada.Strings.Fixed.Trim
                (Part (Part'First .. Eq - 1), Ada.Strings.Both) = Wanted
            then
               declare
                  Raw0 : constant String :=
                    Ada.Strings.Fixed.Trim (Part (Eq + 1 .. Part'Last), Ada.Strings.Both);
                  Raw  : constant String :=
                    (if Raw0'Length >= 2 and then Raw0 (Raw0'First) = '"'
                       and then Raw0 (Raw0'Last) = '"'
                     then Raw0 (Raw0'First + 1 .. Raw0'Last - 1)
                     else Raw0);
               begin
                  if Raw'Length = 0 then
                     return False;
                  end if;

                  for C of Raw loop
                     if C not in '0' .. '9' then
                        return False;
                     end if;
                  end loop;

                  Value := Natural'Value (Raw);
                  return True;
               exception
                  when others =>
                     return False;
               end;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return False;
   end Request_Cache_Natural_Directive;

   function Request_Forces_Cache_Revalidation
     (Request : Http_Client.Requests.Request) return Boolean
   is
      Max_Age : Natural := 0;
   begin
      return Request_Has_Cache_Token (Request, "no-cache")
        or else
          (Request_Cache_Natural_Directive (Request, "max-age", Max_Age)
           and then Max_Age = 0);
   end Request_Forces_Cache_Revalidation;

   function Execute_With_Cache
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Response  : out Http_Client.Responses.Response;
      Cache     : in out Http_Client.Cache.Cache_Store;
      Metadata  : out Http_Client.Cache.Cache_Metadata;
      Options   : Execution_Options := Default_Execution_Options;
      Policy    : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config)
      return Http_Client.Errors.Result_Status
   is
      Lookup_Status      : Http_Client.Errors.Result_Status;
      Network_Status     : Http_Client.Errors.Result_Status;
      Cached             : Http_Client.Responses.Response;
      Network            : Http_Client.Responses.Response;
      Conditional        : Http_Client.Requests.Request;
      Only_If_Cached     : Boolean;
      Force_Revalidation : Boolean;
      Using_Client_Cert  : constant Boolean :=
        Request_Uses_Client_Certificate (Request, Options);
   begin
      Response := Http_Client.Responses.Default_Response;
      Metadata :=
        (Source             => Http_Client.Cache.Cache_Bypassed,
         Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
         Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
         Age_Seconds        => 0,
         Revalidation_Count => 0,
         Entry_Count        => Http_Client.Cache.Length (Cache),
         Stored_Body_Bytes  => Http_Client.Cache.Stored_Body_Bytes (Cache));

      if not Policy.Enabled then
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Diagnostic
                (Options,
                 (Kind    => Http_Client.Diagnostics.Cache_Lookup_Result,
                  Cache   => Http_Client.Diagnostics.Cache_Bypassed,
                  Message => Http_Client.Diagnostics.To_Text ("cache disabled"),
                  others  => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      Http_Client.Cache.Configure (Cache, Policy);

      if Using_Client_Cert and then not Policy.Allow_Authenticated_Store then
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      if Request_Has_Cache_Token (Request, "no-store") then
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      Only_If_Cached := Request_Has_Cache_Token (Request, "only-if-cached");
      Force_Revalidation := Request_Forces_Cache_Revalidation (Request);

      Lookup_Status := Http_Client.Cache.Lookup
        (Cache    => Cache,
         Request  => Request,
         Response => Cached,
         Metadata => Metadata);

      declare
         Cache_Event : Http_Client.Diagnostics.Cache_Result :=
           Http_Client.Diagnostics.Cache_Miss;
         Emit_Status : Http_Client.Errors.Result_Status;
      begin
         if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
            Cache_Event := Http_Client.Diagnostics.Cache_Hit;
         elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
           or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
         then
            Cache_Event := Http_Client.Diagnostics.Cache_Stale;
         elsif Lookup_Status = Http_Client.Errors.Cache_Miss then
            Cache_Event := Http_Client.Diagnostics.Cache_Miss;
         else
            Cache_Event := Http_Client.Diagnostics.Cache_Bypassed;
         end if;

         Emit_Status := Emit_Diagnostic
           (Options,
            (Kind   => Http_Client.Diagnostics.Cache_Lookup_Result,
             Cache  => Cache_Event,
             Result => Lookup_Status,
             others => <>));
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         end if;
      end;

      if Lookup_Status = Http_Client.Errors.Ok
        and then not Force_Revalidation
      then
         Response := Cached;
         return Http_Client.Errors.Ok;
      elsif Only_If_Cached and then Lookup_Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Cache_Miss;
      elsif Only_If_Cached and then Force_Revalidation then
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Cache_Miss;
      elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
        or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
      then
         declare
            Conditional_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.Cache.Prepare_Conditional_Request
                (Original => Request,
                 Cached   => Cached,
                 Result   => Conditional);
         begin
            if Conditional_Status = Http_Client.Errors.Ok then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind    => Http_Client.Diagnostics.Cache_Revalidation,
                        Cache   => Http_Client.Diagnostics.Cache_Stale,
                        Message => Http_Client.Diagnostics.To_Text ("conditional revalidation"),
                        others  => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     return Emit_Status;
                  end if;
               end;

               Network_Status := Execute (Item, Conditional, Network, Options);

               if Network_Status /= Http_Client.Errors.Ok then
                  Response := Http_Client.Responses.Default_Response;
                  Metadata.Source := Http_Client.Cache.Cache_Bypassed;
                  return Http_Client.Errors.Cache_Revalidation_Failed;
               end if;

               if Http_Client.Responses.Status_Code (Network) = 304 then
                  declare
                     Update_Status : constant Http_Client.Errors.Result_Status :=
                       Http_Client.Cache.Update_From_304
                         (Cache    => Cache,
                          Request  => Request,
                          Response => Network,
                          Metadata => Metadata);
                  begin
                     if Update_Status = Http_Client.Errors.Ok then
                        declare
                           Refreshed_Metadata : Http_Client.Cache.Cache_Metadata;
                           Refreshed_Response : Http_Client.Responses.Response;
                           Refreshed_Status   : constant Http_Client.Errors.Result_Status :=
                             Http_Client.Cache.Lookup
                               (Cache    => Cache,
                                Request  => Request,
                                Response => Refreshed_Response,
                                Metadata => Refreshed_Metadata);
                        begin
                           if Refreshed_Status = Http_Client.Errors.Ok
                             or else Refreshed_Status = Http_Client.Errors.Cache_Entry_Stale
                           then
                              Response := Refreshed_Response;
                           else
                              Response := Cached;
                           end if;
                        end;

                        Metadata.Source := Http_Client.Cache.From_Revalidated_Cache;
                        return Http_Client.Errors.Ok;
                     else
                        return Update_Status;
                     end if;
                  end;
               else
                  Response := Network;
                  declare
                     Store_Status : constant Http_Client.Errors.Result_Status :=
                       (if Http_Client.Cache.May_Store_With_Client_Certificate
                             (Using_Client_Cert, Request, Network, Policy)
                        then Http_Client.Cache.Store (Cache, Request, Network)
                        else Http_Client.Errors.Ok);
                  begin
                     if Store_Status /= Http_Client.Errors.Ok then
                        Http_Client.Cache.Invalidate (Cache, Request);
                     end if;
                  end;
                  Metadata.Source := Http_Client.Cache.From_Network;
                  Metadata.Entry_Count := Http_Client.Cache.Length (Cache);
                  Metadata.Stored_Body_Bytes := Http_Client.Cache.Stored_Body_Bytes (Cache);
                  return Network_Status;
               end if;
            end if;
         end;
      end if;

      Network_Status := Execute (Item, Request, Response, Options);
      if Network_Status = Http_Client.Errors.Ok then
         declare
            Store_Status : constant Http_Client.Errors.Result_Status :=
              (if Http_Client.Cache.May_Store_With_Client_Certificate
                    (Using_Client_Cert, Request, Response, Policy)
               then Http_Client.Cache.Store (Cache, Request, Response)
               else Http_Client.Errors.Ok);
         begin
            if Store_Status /= Http_Client.Errors.Ok then
               Http_Client.Cache.Invalidate (Cache, Request);
            end if;
         end;
      end if;
      Metadata.Source := Http_Client.Cache.From_Network;
      Metadata.Entry_Count := Http_Client.Cache.Length (Cache);
      Metadata.Stored_Body_Bytes := Http_Client.Cache.Stored_Body_Bytes (Cache);
      return Network_Status;
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Internal_Error;
   end Execute_With_Cache;


   function Execute_With_Persistent_Cache
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Response  : out Http_Client.Responses.Response;
      Cache     : in out Http_Client.Cache.Persistent.Persistent_Store;
      Metadata  : out Http_Client.Cache.Cache_Metadata;
      Options   : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status
   is
      Lookup_Status      : Http_Client.Errors.Result_Status;
      Network_Status     : Http_Client.Errors.Result_Status;
      Cached             : Http_Client.Responses.Response;
      Network            : Http_Client.Responses.Response;
      Conditional        : Http_Client.Requests.Request;
      Only_If_Cached     : Boolean;
      Force_Revalidation : Boolean;
      Using_Client_Cert  : constant Boolean :=
        Request_Uses_Client_Certificate (Request, Options);
   begin
      Response := Http_Client.Responses.Default_Response;
      Metadata :=
        (Source             => Http_Client.Cache.Cache_Bypassed,
         Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
         Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
         Age_Seconds        => 0,
         Revalidation_Count => 0,
         Entry_Count        => Http_Client.Cache.Persistent.Entry_Count (Cache),
         Stored_Body_Bytes  => Http_Client.Cache.Persistent.Stored_Bytes (Cache));

      if not Http_Client.Cache.Persistent.Is_Open (Cache) then
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      if Using_Client_Cert then
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      if Request_Has_Cache_Token (Request, "no-store") then
         Network_Status := Execute (Item, Request, Response, Options);
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Network_Status;
      end if;

      Only_If_Cached := Request_Has_Cache_Token (Request, "only-if-cached");
      Force_Revalidation := Request_Forces_Cache_Revalidation (Request);

      Lookup_Status := Http_Client.Cache.Persistent.Lookup
        (Store    => Cache,
         Request  => Request,
         Response => Cached,
         Metadata => Metadata);

      declare
         Cache_Event : Http_Client.Diagnostics.Cache_Result :=
           Http_Client.Diagnostics.Cache_Miss;
         Emit_Status : Http_Client.Errors.Result_Status;
      begin
         if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
            Cache_Event := Http_Client.Diagnostics.Cache_Hit;
         elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
           or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
         then
            Cache_Event := Http_Client.Diagnostics.Cache_Stale;
         elsif Lookup_Status = Http_Client.Errors.Cache_Miss then
            Cache_Event := Http_Client.Diagnostics.Cache_Miss;
         else
            Cache_Event := Http_Client.Diagnostics.Cache_Bypassed;
         end if;

         Emit_Status := Emit_Diagnostic
           (Options,
            (Kind   => Http_Client.Diagnostics.Cache_Lookup_Result,
             Cache  => Cache_Event,
             Result => Lookup_Status,
             others => <>));
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         end if;

         if Http_Client.Cache.Persistent.Encrypts_At_Rest (Cache) then
            declare
               Encrypted_Kind : Http_Client.Diagnostics.Event_Kind :=
                 Http_Client.Diagnostics.Encrypted_Cache_Miss;
               Encrypted_Status : Http_Client.Errors.Result_Status;
            begin
               if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
                  Encrypted_Kind := Http_Client.Diagnostics.Encrypted_Cache_Hit;
               elsif Lookup_Status = Http_Client.Errors.Cache_Authentication_Failed
                 or else Lookup_Status = Http_Client.Errors.Cache_Decryption_Failed
               then
                  Encrypted_Kind := Http_Client.Diagnostics.Encrypted_Cache_Authentication_Failure;
               elsif Lookup_Status = Http_Client.Errors.Cache_Corrupt_Entry
                 or else Lookup_Status = Http_Client.Errors.Cache_Encrypted_Format_Unsupported
               then
                  Encrypted_Kind := Http_Client.Diagnostics.Encrypted_Cache_Corrupt_Entry;
               else
                  Encrypted_Kind := Http_Client.Diagnostics.Encrypted_Cache_Miss;
               end if;

               Encrypted_Status := Emit_Diagnostic
                 (Options,
                  (Kind    => Encrypted_Kind,
                   Cache   => Cache_Event,
                   Result  => Lookup_Status,
                   Message => Http_Client.Diagnostics.To_Text ("encrypted persistent cache lookup"),
                   others  => <>));
               if Encrypted_Status /= Http_Client.Errors.Ok then
                  return Encrypted_Status;
               end if;
            end;
         end if;
      end;

      if Lookup_Status = Http_Client.Errors.Ok
        and then not Force_Revalidation
      then
         Response := Cached;
         return Http_Client.Errors.Ok;
      elsif Only_If_Cached and then Lookup_Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Cache_Miss;
      elsif Only_If_Cached and then Force_Revalidation then
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Cache_Miss;
      elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
        or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
      then
         declare
            Conditional_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.Cache.Prepare_Conditional_Request
                (Original => Request,
                 Cached   => Cached,
                 Result   => Conditional);
         begin
            if Conditional_Status = Http_Client.Errors.Ok then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Diagnostic
                      (Options,
                       (Kind    => Http_Client.Diagnostics.Cache_Revalidation,
                        Cache   => Http_Client.Diagnostics.Cache_Stale,
                        Message => Http_Client.Diagnostics.To_Text ("persistent conditional revalidation"),
                        others  => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     return Emit_Status;
                  end if;
               end;

               Network_Status := Execute (Item, Conditional, Network, Options);

               if Network_Status /= Http_Client.Errors.Ok then
                  Response := Http_Client.Responses.Default_Response;
                  Metadata.Source := Http_Client.Cache.Cache_Bypassed;
                  return Http_Client.Errors.Cache_Revalidation_Failed;
               end if;

               if Http_Client.Responses.Status_Code (Network) = 304 then
                  declare
                     Update_Status : constant Http_Client.Errors.Result_Status :=
                       Http_Client.Cache.Persistent.Update_From_304
                         (Store    => Cache,
                          Request  => Request,
                          Response => Network,
                          Metadata => Metadata);
                  begin
                     if Update_Status = Http_Client.Errors.Ok then
                        declare
                           Refreshed_Metadata : Http_Client.Cache.Cache_Metadata;
                           Refreshed_Response : Http_Client.Responses.Response;
                           Refreshed_Status   : constant Http_Client.Errors.Result_Status :=
                             Http_Client.Cache.Persistent.Lookup
                               (Store    => Cache,
                                Request  => Request,
                                Response => Refreshed_Response,
                                Metadata => Refreshed_Metadata);
                        begin
                           if Refreshed_Status = Http_Client.Errors.Ok
                             or else Refreshed_Status = Http_Client.Errors.Cache_Entry_Stale
                           then
                              Response := Refreshed_Response;
                           else
                              Response := Cached;
                           end if;
                        end;

                        Metadata.Source := Http_Client.Cache.From_Revalidated_Cache;
                        return Http_Client.Errors.Ok;
                     else
                        return Update_Status;
                     end if;
                  end;
               else
                  Response := Network;
                  declare
                     Store_Status : constant Http_Client.Errors.Result_Status :=
                       Http_Client.Cache.Persistent.Store (Cache, Request, Network);
                  begin
                     if Store_Status /= Http_Client.Errors.Ok then
                        Http_Client.Cache.Persistent.Invalidate (Cache, Request);
                     end if;
                  end;
                  Metadata.Source := Http_Client.Cache.From_Network;
                  Metadata.Entry_Count := Http_Client.Cache.Persistent.Entry_Count (Cache);
                  Metadata.Stored_Body_Bytes := Http_Client.Cache.Persistent.Stored_Bytes (Cache);
                  return Network_Status;
               end if;
            end if;
         end;
      end if;

      Network_Status := Execute (Item, Request, Response, Options);
      if Network_Status = Http_Client.Errors.Ok then
         declare
            Store_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.Cache.Persistent.Store (Cache, Request, Response);
         begin
            if Store_Status /= Http_Client.Errors.Ok then
               Http_Client.Cache.Persistent.Invalidate (Cache, Request);
            end if;
         end;
      end if;
      Metadata.Source := Http_Client.Cache.From_Network;
      Metadata.Entry_Count := Http_Client.Cache.Persistent.Entry_Count (Cache);
      Metadata.Stored_Body_Bytes := Http_Client.Cache.Persistent.Stored_Bytes (Cache);
      return Network_Status;
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         Metadata.Source := Http_Client.Cache.Cache_Bypassed;
         return Http_Client.Errors.Internal_Error;
   end Execute_With_Persistent_Cache;


   function Execute_With_Retry
     (Item      : Client;
      Request   : Http_Client.Requests.Request;
      Result    : out Retry_Result;
      Execution : Execution_Options := Default_Execution_Options;
      Retries   : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status
   is
      Response        : Http_Client.Responses.Response;
      Status          : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Attempt         : Positive := 1;
      Attempts_Limit  : constant Positive :=
        (if Retries.Enable_Retries then Retries.Maximum_Attempts else 1);
      Method_Allows   : Boolean := False;
      Retry_Response  : Boolean := False;
      Retry_Failure   : Boolean := False;
      Planned_Delay   : Http_Client.Retry.Delay_Milliseconds := 0;

      function Delay_From_Response
        (Current_Attempt : Positive;
         Current_Response : Http_Client.Responses.Response)
         return Http_Client.Retry.Delay_Milliseconds
      is
         Headers : constant Http_Client.Headers.Header_List :=
           Http_Client.Responses.Headers (Current_Response);
         Parsed  : Http_Client.Retry.Delay_Milliseconds := 0;
      begin
         if Http_Client.Headers.Contains (Headers, "Retry-After")
           and then Http_Client.Retry.Retry_After_Delay
             (Value   => Http_Client.Headers.Get (Headers, "Retry-After"),
              Options => Retries,
              Pause   => Parsed)
         then
            return Parsed;
         else
            return Http_Client.Retry.Delay_For_Attempt
              (Attempt => Current_Attempt,
               Options => Retries);
         end if;
      end Delay_From_Response;

      function Invoke_Delay
        (Pause : Http_Client.Retry.Delay_Milliseconds)
         return Http_Client.Errors.Result_Status
      is
      begin
         if Retries.Delay_Hook /= null then
            Retries.Delay_Hook.all (Pause);
         end if;

         return Http_Client.Errors.Ok;
      exception
         when others =>
            return Http_Client.Errors.Internal_Error;
      end Invoke_Delay;
   begin
      Result :=
        (Final_Response    => Http_Client.Responses.Default_Response,
         Final_Status      => Http_Client.Errors.Internal_Error,
         Attempts          => 1,
         Retries_Exhausted => False,
         Last_Failure      => Http_Client.Errors.Ok);

      if Execution.Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Execution.Cancellation.all)
      then
         Result.Final_Status := Http_Client.Errors.Cancelled;
         Result.Last_Failure := Http_Client.Errors.Cancelled;
         return Http_Client.Errors.Cancelled;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         Result.Final_Status := Http_Client.Errors.Invalid_Request;
         Result.Last_Failure := Http_Client.Errors.Invalid_Request;
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Retries.Enable_Retries
        and then Attempts_Limit > 1
        and then not Http_Client.Retry.Is_Request_Body_Replayable (Request)
      then
         Result.Final_Status := Http_Client.Errors.Retry_Body_Not_Replayable;
         Result.Last_Failure := Http_Client.Errors.Retry_Body_Not_Replayable;
         return Http_Client.Errors.Retry_Body_Not_Replayable;
      end if;

      Method_Allows :=
        Http_Client.Retry.Is_Retryable_Method
          (Method  => Http_Client.Requests.Method (Request),
           Options => Retries);

      loop
         Response := Http_Client.Responses.Default_Response;
         Status := Execute
           (Item     => Item,
            Request  => Request,
            Response => Response,
            Options  => Execution);

         Result.Final_Response := Response;
         Result.Final_Status := Status;
         Result.Attempts := Attempt;

         if Status = Http_Client.Errors.Cancelled then
            Result.Last_Failure := Http_Client.Errors.Cancelled;
            return Http_Client.Errors.Cancelled;
         end if;

         if Status = Http_Client.Errors.Ok then
            Result.Last_Failure := Http_Client.Errors.Ok;
            Retry_Response :=
              Retries.Enable_Retries
              and then Method_Allows
              and then Http_Client.Retry.Is_Retryable_Response
                (Response => Response,
                 Options  => Retries);

            if not Retry_Response then
               return Http_Client.Errors.Ok;
            end if;

            if Attempt >= Attempts_Limit then
               Result.Retries_Exhausted := True;
               return Http_Client.Errors.Ok;
            end if;

            Planned_Delay := Delay_From_Response (Attempt, Response);
         else
            Result.Last_Failure := Status;
            Retry_Failure :=
              Retries.Enable_Retries
              and then Method_Allows
              and then Http_Client.Retry.Is_Retryable_Failure
                (Status  => Status,
                 Options => Retries);

            if not Retry_Failure then
               return Status;
            end if;

            if Attempt >= Attempts_Limit then
               Result.Retries_Exhausted := True;
               return Status;
            end if;

            Planned_Delay := Http_Client.Retry.Delay_For_Attempt
              (Attempt => Attempt,
               Options => Retries);
         end if;

         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Retry_Diagnostic
                (Execution       => Execution,
                 Attempt         => Attempt,
                 Status          => Status,
                 Status_Code     =>
                   (if Status = Http_Client.Errors.Ok
                    then Natural (Http_Client.Responses.Status_Code (Response))
                    else 0),
                 Planned_Delay   => Planned_Delay,
                 Reason          =>
                   (if Status = Http_Client.Errors.Ok
                    then "retrying response status"
                    else "retrying transient failure"),
                 Body_Replayable =>
                   Http_Client.Retry.Is_Request_Body_Replayable (Request));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               Result.Final_Status := Emit_Status;
               Result.Last_Failure := Emit_Status;
               return Emit_Status;
            end if;
         end;

         if Execution.Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Execution.Cancellation.all)
         then
            Result.Final_Status := Http_Client.Errors.Cancelled;
            Result.Last_Failure := Http_Client.Errors.Cancelled;
            return Http_Client.Errors.Cancelled;
         end if;

         declare
            Delay_Status : constant Http_Client.Errors.Result_Status :=
              Invoke_Delay (Planned_Delay);
         begin
            if Delay_Status /= Http_Client.Errors.Ok then
               Result.Final_Status := Delay_Status;
               Result.Last_Failure := Delay_Status;
               return Delay_Status;
            end if;
         end;

         if Execution.Cancellation /= null
           and then Http_Client.Cancellation.Is_Cancelled (Execution.Cancellation.all)
         then
            Result.Final_Status := Http_Client.Errors.Cancelled;
            Result.Last_Failure := Http_Client.Errors.Cancelled;
            return Http_Client.Errors.Cancelled;
         end if;

         declare
            Reset_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.Requests.Reset_Body (Request);
         begin
            if Reset_Status /= Http_Client.Errors.Ok then
               Result.Final_Status := Reset_Status;
               Result.Last_Failure := Reset_Status;
               return Reset_Status;
            end if;
         end;

         Attempt := Attempt + 1;
      end loop;
   exception
      when others =>
         Result :=
           (Final_Response    => Http_Client.Responses.Default_Response,
            Final_Status      => Http_Client.Errors.Internal_Error,
            Attempts          => 1,
            Retries_Exhausted => False,
            Last_Failure      => Http_Client.Errors.Internal_Error);
         return Http_Client.Errors.Internal_Error;
   end Execute_With_Retry;

   function Execute_Once_With_Retry
     (Request   : Http_Client.Requests.Request;
      Result    : out Retry_Result;
      Execution : Execution_Options := Default_Execution_Options;
      Retries   : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status
   is
      Local_Client : constant Client := Create;
   begin
      return Execute_With_Retry
        (Item      => Local_Client,
         Request   => Request,
         Result    => Result,
         Execution => Execution,
         Retries   => Retries);
   end Execute_Once_With_Retry;


   function Execute_Decoded
     (Item          : Client;
      Request       : Http_Client.Requests.Request;
      Result        : out Http_Client.Decompression.Decoded_Response;
      Execution     : Execution_Options := Default_Execution_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status
   is
      Raw_Response : Http_Client.Responses.Response;
      Options      : Execution_Options := Execution;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Options.Advertise_Accept_Encoding := True;

      Status := Execute
        (Item     => Item,
         Request  => Request,
         Response => Raw_Response,
         Options  => Options);

      if Status /= Http_Client.Errors.Ok then
         Result := Http_Client.Decompression.Default_Decoded_Response;
         return Status;
      end if;

      declare
         Decode_Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.Decompression.Decode_Response_With_Context
             (Response         => Raw_Response,
              Request_Was_HEAD =>
                Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD,
              Result           => Result,
              Options          => Decompression);
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_Diagnostic
             (Execution,
              (Kind                => Http_Client.Diagnostics.Decompression_Result,
               Result              => Decode_Status,
               Response_Byte_Count => Http_Client.Decompression.Decoded_Body (Result)'Length,
               others              => <>));
      begin
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         else
            return Decode_Status;
         end if;
      end;
   exception
      when others =>
         Result := Http_Client.Decompression.Default_Decoded_Response;
         return Http_Client.Errors.Internal_Error;
   end Execute_Decoded;

   function Execute_Stream
      (Request : Http_Client.Requests.Request;
       Stream  : in out Http_Client.Response_Streams.Streaming_Response;
       Options : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status
   is
      Effective_Options : Execution_Options := Options;
   begin
      Effective_Options.TLS :=
        Effective_TLS_Options_For_Request (Request, Options);

      return Http_Client.Response_Streams.Open
        (Request => Request,
         Stream  => Stream,
         Options => Streaming_Options_For (Effective_Options));
   end Execute_Stream;

   function Execute_Once
     (Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Options  : Execution_Options := Default_Execution_Options)
      return Http_Client.Errors.Result_Status
   is
      Local_Client : constant Client := Create;
   begin
      return Execute
        (Item     => Local_Client,
         Request  => Request,
         Response => Response,
         Options  => Options);
   end Execute_Once;


   function Execute_Decoded_Once
     (Request       : Http_Client.Requests.Request;
      Result        : out Http_Client.Decompression.Decoded_Response;
      Execution     : Execution_Options := Default_Execution_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status
   is
      Local_Client : constant Client := Create;
   begin
      return Execute_Decoded
        (Item          => Local_Client,
         Request       => Request,
         Result        => Result,
         Execution     => Execution,
         Decompression => Decompression);
   end Execute_Decoded_Once;


   function Execute_Following_Redirects
     (Item             : Client;
      Request          : Http_Client.Requests.Request;
      Result           : out Redirect_Result;
      Execution        : Execution_Options := Default_Execution_Options;
      Redirects        : Redirect_Options := Default_Redirect_Options)
      return Http_Client.Errors.Result_Status
   is
      Current_Request : Http_Client.Requests.Request := Request;
      Current_URI     : Http_Client.URI.URI_Reference;
      Current_Response: Http_Client.Responses.Response;
      Status          : Http_Client.Errors.Result_Status;
      Count           : Natural := 0;
   begin
      Result :=
        (Final_Response         => Http_Client.Responses.Default_Response,
         Final_URI              => Http_Client.URI.Create_Unchecked (""),
         Redirect_Count         => 0,
         Final_Request_Was_HEAD => False);

      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      Current_URI := Http_Client.Requests.URI (Current_Request);

      loop
         Status := Execute (Item, Current_Request, Current_Response, Execution);

         if Status /= Http_Client.Errors.Ok then
            Result.Final_Response := Current_Response;
            Result.Final_URI := Current_URI;
            Result.Redirect_Count := Count;
            Result.Final_Request_Was_HEAD :=
              Http_Client.Requests.Method (Current_Request) = Http_Client.Types.HEAD;
            return Status;
         end if;

         Result.Final_Response := Current_Response;
         Result.Final_URI := Current_URI;
         Result.Redirect_Count := Count;
         Result.Final_Request_Was_HEAD :=
           Http_Client.Requests.Method (Current_Request) = Http_Client.Types.HEAD;

         exit when not Status_Is_Followed_Redirect
           (Http_Client.Responses.Status_Code (Current_Response));

         declare
            Headers  : constant Http_Client.Headers.Header_List :=
              Http_Client.Responses.Headers (Current_Response);
            Location : constant String :=
              Http_Client.Headers.Get (Headers, "Location");
            Target   : Http_Client.URI.URI_Reference;
            Next     : Http_Client.Requests.Request;
         begin
            if not Http_Client.Headers.Contains (Headers, "Location") then
               return Http_Client.Errors.Invalid_Redirect;
            end if;

            if Count >= Redirects.Max_Redirects then
               return Http_Client.Errors.Too_Many_Redirects;
            end if;

            Status := Resolve_Location (Current_URI, Location, Target);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

            if Http_Client.URI.Requires_TLS (Current_URI)
              and then not Http_Client.URI.Requires_TLS (Target)
              and then not Redirects.Allow_HTTPS_To_HTTP_Redirects
            then
               return Http_Client.Errors.Redirect_Downgrade_Blocked;
            end if;

            Status := Build_Redirected_Request
              (Current_Request => Current_Request,
               Current_URI     => Current_URI,
               Target_URI      => Target,
               Status_Code     => Http_Client.Responses.Status_Code (Current_Response),
               Redirects       => Redirects,
               Next_Request    => Next);

            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Diagnostic
                   (Execution,
                    (Kind           => Http_Client.Diagnostics.Redirect_Decision,
                     Redirect_Count => Count + 1,
                     Status_Code    => Natural (Http_Client.Responses.Status_Code (Current_Response)),
                     URI_Or_Origin  => Http_Client.Diagnostics.To_Text
                       (Http_Client.URI.Scheme (Target) & "://" & Http_Client.URI.Authority_Host (Target)),
                     Header_Name    => Http_Client.Diagnostics.To_Text ("Location"),
                     Header_Value   => Http_Client.Diagnostics.To_Text (Location),
                     Header_Redacted => False,
                     Message        => Http_Client.Diagnostics.To_Text
                       (Http_Client.URI.Image (Target) & Character'Val (10) & Location),
                     others         => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
            end;

            Count := Count + 1;
            Current_Request := Next;
            Current_URI := Target;
         end;
      end loop;

      Result.Redirect_Count := Count;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Result :=
           (Final_Response         => Http_Client.Responses.Default_Response,
            Final_URI              => Http_Client.URI.Create_Unchecked (""),
            Redirect_Count         => 0,
            Final_Request_Was_HEAD => False);
         return Http_Client.Errors.Internal_Error;
   end Execute_Following_Redirects;

   function Execute_Decoded_Following_Redirects
     (Item          : Client;
      Request       : Http_Client.Requests.Request;
      Result        : out Decoded_Redirect_Result;
      Execution     : Execution_Options := Default_Execution_Options;
      Redirects     : Redirect_Options := Default_Redirect_Options;
      Decompression : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options)
      return Http_Client.Errors.Result_Status
   is
      Raw_Result : Redirect_Result;
      Options    : Execution_Options := Execution;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Result :=
        (Final_Response => Http_Client.Decompression.Default_Decoded_Response,
         Final_URI      => Http_Client.URI.Create_Unchecked (""),
         Redirect_Count => 0);

      Options.Advertise_Accept_Encoding := True;

      Status := Execute_Following_Redirects
        (Item      => Item,
         Request   => Request,
         Result    => Raw_Result,
         Execution => Options,
         Redirects => Redirects);

      Result.Final_URI := Raw_Result.Final_URI;
      Result.Redirect_Count := Raw_Result.Redirect_Count;

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      declare
         Decode_Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.Decompression.Decode_Response_With_Context
             (Response         => Raw_Result.Final_Response,
              Request_Was_HEAD => Raw_Result.Final_Request_Was_HEAD,
              Result           => Result.Final_Response,
              Options          => Decompression);
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_Diagnostic
             (Execution,
              (Kind                => Http_Client.Diagnostics.Decompression_Result,
               Result              => Decode_Status,
               Response_Byte_Count => Http_Client.Decompression.Decoded_Body (Result.Final_Response)'Length,
               others              => <>));
      begin
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         else
            return Decode_Status;
         end if;
      end;
   exception
      when others =>
         Result :=
           (Final_Response => Http_Client.Decompression.Default_Decoded_Response,
            Final_URI      => Http_Client.URI.Create_Unchecked (""),
            Redirect_Count => 0);
         return Http_Client.Errors.Internal_Error;
   end Execute_Decoded_Following_Redirects;

   function Execute_With_Redirects
     (Item             : Client;
      Request          : Http_Client.Requests.Request;
      Result           : out Redirect_Result;
      Execution        : Execution_Options := Default_Execution_Options;
      Redirects        : Redirect_Options := Default_Redirect_Options)
      return Http_Client.Errors.Result_Status
   is
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      if Redirects.Follow_Redirects then
         return Execute_Following_Redirects
           (Item      => Item,
            Request   => Request,
            Result    => Result,
            Execution => Execution,
            Redirects => Redirects);
      end if;

      Status := Execute (Item, Request, Response, Execution);
      Result.Final_Response := Response;
      Result.Final_URI := Http_Client.Requests.URI (Request);
      Result.Redirect_Count := 0;
      Result.Final_Request_Was_HEAD :=
        Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD;
      return Status;
   exception
      when others =>
         Result :=
           (Final_Response         => Http_Client.Responses.Default_Response,
            Final_URI              => Http_Client.URI.Create_Unchecked (""),
            Redirect_Count         => 0,
            Final_Request_Was_HEAD => False);
         return Http_Client.Errors.Internal_Error;
   end Execute_With_Redirects;

   function Execute_With_Redirects_And_Retry
     (Item           : Client;
      Request        : Http_Client.Requests.Request;
      Result         : out Redirect_Result;
      Retry_Metadata : out Retry_Result;
      Execution      : Execution_Options := Default_Execution_Options;
      Redirects      : Redirect_Options := Default_Redirect_Options;
      Retries        : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status
   is
      Status         : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Attempt        : Positive := 1;
      Attempts_Limit : constant Positive :=
        (if Retries.Enable_Retries then Retries.Maximum_Attempts else 1);
      Method_Allows  : Boolean := False;
      Should_Retry   : Boolean := False;
      Planned_Delay  : Http_Client.Retry.Delay_Milliseconds := 0;

      function Delay_From_Response
        (Current_Attempt  : Positive;
         Current_Response : Http_Client.Responses.Response)
         return Http_Client.Retry.Delay_Milliseconds
      is
         Headers : constant Http_Client.Headers.Header_List :=
           Http_Client.Responses.Headers (Current_Response);
         Parsed  : Http_Client.Retry.Delay_Milliseconds := 0;
      begin
         if Http_Client.Headers.Contains (Headers, "Retry-After")
           and then Http_Client.Retry.Retry_After_Delay
             (Value   => Http_Client.Headers.Get (Headers, "Retry-After"),
              Options => Retries,
              Pause   => Parsed)
         then
            return Parsed;
         else
            return Http_Client.Retry.Delay_For_Attempt
              (Attempt => Current_Attempt,
               Options => Retries);
         end if;
      end Delay_From_Response;

      function Invoke_Delay
        (Pause : Http_Client.Retry.Delay_Milliseconds)
         return Http_Client.Errors.Result_Status
      is
      begin
         if Retries.Delay_Hook /= null then
            Retries.Delay_Hook.all (Pause);
         end if;

         return Http_Client.Errors.Ok;
      exception
         when others =>
            return Http_Client.Errors.Internal_Error;
      end Invoke_Delay;
   begin
      Result :=
        (Final_Response         => Http_Client.Responses.Default_Response,
         Final_URI              => Http_Client.URI.Create_Unchecked (""),
         Redirect_Count         => 0,
         Final_Request_Was_HEAD => False);
      Retry_Metadata :=
        (Final_Response    => Http_Client.Responses.Default_Response,
         Final_Status      => Http_Client.Errors.Internal_Error,
         Attempts          => 1,
         Retries_Exhausted => False,
         Last_Failure      => Http_Client.Errors.Ok);

      if not Http_Client.Requests.Is_Valid (Request) then
         Retry_Metadata.Final_Status := Http_Client.Errors.Invalid_Request;
         Retry_Metadata.Last_Failure := Http_Client.Errors.Invalid_Request;
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Retries.Enable_Retries
        and then Attempts_Limit > 1
        and then not Http_Client.Retry.Is_Request_Body_Replayable (Request)
      then
         Retry_Metadata.Final_Status := Http_Client.Errors.Retry_Body_Not_Replayable;
         Retry_Metadata.Last_Failure := Http_Client.Errors.Retry_Body_Not_Replayable;
         return Http_Client.Errors.Retry_Body_Not_Replayable;
      end if;

      Method_Allows :=
        Http_Client.Retry.Is_Retryable_Method
          (Method  => Http_Client.Requests.Method (Request),
           Options => Retries);

      loop
         Status := Execute_With_Redirects
           (Item      => Item,
            Request   => Request,
            Result    => Result,
            Execution => Execution,
            Redirects => Redirects);

         Retry_Metadata.Final_Response := Result.Final_Response;
         Retry_Metadata.Final_Status := Status;
         Retry_Metadata.Attempts := Attempt;

         if Status = Http_Client.Errors.Ok then
            Retry_Metadata.Last_Failure := Http_Client.Errors.Ok;
            Should_Retry :=
              Retries.Enable_Retries
              and then Method_Allows
              and then Http_Client.Retry.Is_Retryable_Response
                (Response => Result.Final_Response,
                 Options  => Retries);

            if not Should_Retry then
               return Http_Client.Errors.Ok;
            end if;

            if Attempt >= Attempts_Limit then
               Retry_Metadata.Retries_Exhausted := True;
               return Http_Client.Errors.Ok;
            end if;

            Planned_Delay := Delay_From_Response (Attempt, Result.Final_Response);
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Retry_Diagnostic
                   (Execution       => Execution,
                    Attempt         => Attempt,
                    Status          => Status,
                    Status_Code     =>
                      Natural
                        (Http_Client.Responses.Status_Code (Result.Final_Response)),
                    Planned_Delay   => Planned_Delay,
                    Reason          => "retrying redirected response status",
                    Body_Replayable =>
                      Http_Client.Retry.Is_Request_Body_Replayable (Request));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  Retry_Metadata.Final_Status := Emit_Status;
                  Retry_Metadata.Last_Failure := Emit_Status;
                  return Emit_Status;
               end if;
            end;

            declare
               Delay_Status : constant Http_Client.Errors.Result_Status :=
                 Invoke_Delay (Planned_Delay);
            begin
               if Delay_Status /= Http_Client.Errors.Ok then
                  Retry_Metadata.Final_Status := Delay_Status;
                  Retry_Metadata.Last_Failure := Delay_Status;
                  return Delay_Status;
               end if;
            end;
         else
            Retry_Metadata.Last_Failure := Status;
            Should_Retry :=
              Retries.Enable_Retries
              and then Method_Allows
              and then Http_Client.Retry.Is_Retryable_Failure
                (Status  => Status,
                 Options => Retries);

            if not Should_Retry then
               return Status;
            end if;

            if Attempt >= Attempts_Limit then
               Retry_Metadata.Retries_Exhausted := True;
               return Status;
            end if;

            Planned_Delay :=
              Http_Client.Retry.Delay_For_Attempt
                (Attempt => Attempt,
                 Options => Retries);
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Retry_Diagnostic
                   (Execution       => Execution,
                    Attempt         => Attempt,
                    Status          => Status,
                    Status_Code     => 0,
                    Planned_Delay   => Planned_Delay,
                    Reason          => "retrying redirected transient failure",
                    Body_Replayable =>
                      Http_Client.Retry.Is_Request_Body_Replayable (Request));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  Retry_Metadata.Final_Status := Emit_Status;
                  Retry_Metadata.Last_Failure := Emit_Status;
                  return Emit_Status;
               end if;
            end;

            declare
               Delay_Status : constant Http_Client.Errors.Result_Status :=
                 Invoke_Delay (Planned_Delay);
            begin
               if Delay_Status /= Http_Client.Errors.Ok then
                  Retry_Metadata.Final_Status := Delay_Status;
                  Retry_Metadata.Last_Failure := Delay_Status;
                  return Delay_Status;
               end if;
            end;
         end if;

         declare
            Reset_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.Requests.Reset_Body (Request);
         begin
            if Reset_Status /= Http_Client.Errors.Ok then
               Retry_Metadata.Final_Status := Reset_Status;
               Retry_Metadata.Last_Failure := Reset_Status;
               return Reset_Status;
            end if;
         end;

         Attempt := Attempt + 1;
      end loop;
   exception
      when others =>
         Result :=
           (Final_Response         => Http_Client.Responses.Default_Response,
            Final_URI              => Http_Client.URI.Create_Unchecked (""),
            Redirect_Count         => 0,
            Final_Request_Was_HEAD => False);
         Retry_Metadata :=
           (Final_Response    => Http_Client.Responses.Default_Response,
            Final_Status      => Http_Client.Errors.Internal_Error,
            Attempts          => 1,
            Retries_Exhausted => False,
            Last_Failure      => Http_Client.Errors.Internal_Error);
         return Http_Client.Errors.Internal_Error;
   end Execute_With_Redirects_And_Retry;

   function Execute_Once_With_Redirects_And_Retry
     (Request        : Http_Client.Requests.Request;
      Result         : out Redirect_Result;
      Retry_Metadata : out Retry_Result;
      Execution      : Execution_Options := Default_Execution_Options;
      Redirects      : Redirect_Options := Default_Redirect_Options;
      Retries        : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options)
      return Http_Client.Errors.Result_Status
   is
      Local_Client : constant Client := Create;
   begin
      return Execute_With_Redirects_And_Retry
        (Item           => Local_Client,
         Request        => Request,
         Result         => Result,
         Retry_Metadata => Retry_Metadata,
         Execution      => Execution,
         Redirects      => Redirects,
         Retries        => Retries);
   end Execute_Once_With_Redirects_And_Retry;


   function Is_Forbidden_Default_Header (Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Name);
   begin
      return Lower = "authorization"
        or else Lower = "proxy-authorization"
        or else Lower = "cookie"
        or else Lower = "cookie2"
        or else Lower = "host"
        or else Lower = "content-length"
        or else Lower = "transfer-encoding"
        or else Lower = "connection"
        or else Lower = "proxy-connection"
        or else Lower = "keep-alive"
        or else Lower = "te"
        or else Lower = "trailer"
        or else Lower = "upgrade";
   end Is_Forbidden_Default_Header;

   function Validate
     (Configuration : Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      TLS_Status     : Http_Client.Errors.Result_Status;
      Pooling_Status : Http_Client.Errors.Result_Status;
      Cache_Status   : Http_Client.Errors.Result_Status;
      HTTP3_Status   : Http_Client.Errors.Result_Status;
      Discovery_Status : Http_Client.Errors.Result_Status;
      Proxy_Discovery_Status : Http_Client.Errors.Result_Status;
   begin
      if Configuration.Execution.Max_Response_Size = 0
        or else Configuration.Execution.Max_Header_Size = 0
        or else Configuration.Execution.Max_Header_Line_Size = 0
        or else Configuration.Execution.Max_Body_Size = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Execution.Max_Header_Size >
        Configuration.Execution.Max_Response_Size
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Execution.Max_Header_Line_Size >
        Configuration.Execution.Max_Header_Size
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Execution.Max_Body_Size >
        Configuration.Execution.Max_Response_Size
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      TLS_Status :=
        Http_Client.Transports.TLS.Validate_Options
          (Configuration.Execution.TLS);

      if TLS_Status /= Http_Client.Errors.Ok then
         return TLS_Status;
      end if;

      Pooling_Status :=
        Http_Client.Connection_Pools.Validate (Configuration.Pooling);

      if Pooling_Status /= Http_Client.Errors.Ok then
         return Pooling_Status;
      end if;

      Cache_Status := Http_Client.Cache.Validate (Configuration.Cache);

      if Cache_Status /= Http_Client.Errors.Ok then
         return Cache_Status;
      end if;

      HTTP3_Status := Http_Client.HTTP3.Validate (Configuration.HTTP3);

      if HTTP3_Status /= Http_Client.Errors.Ok then
         return HTTP3_Status;
      end if;

      Discovery_Status :=
        Http_Client.Protocol_Discovery.Validate (Configuration.Discovery);

      if Discovery_Status /= Http_Client.Errors.Ok then
         return Discovery_Status;
      end if;

      Proxy_Discovery_Status :=
        Http_Client.Proxy_Discovery.Validate (Configuration.Proxy_Discovery);

      if Proxy_Discovery_Status /= Http_Client.Errors.Ok then
         return Proxy_Discovery_Status;
      end if;

      if Configuration.Proxy_Discovery.Enabled
        and then Length (Configuration.Proxy_PAC_Script) >
          Configuration.Proxy_Discovery.Limits.Max_Script_Size
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Cache.Enabled
        and then Configuration.Cache_Store = null
        and then Configuration.Persistent_Cache_Store = null
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Cache_Store /= null
        and then Configuration.Persistent_Cache_Store /= null
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Cache.Enabled
        and then Configuration.Persistent_Cache_Store /= null
        and then not Http_Client.Cache.Persistent.Is_Open
          (Configuration.Persistent_Cache_Store.all)
      then
         return Http_Client.Errors.Cache_Open_Failed;
      end if;

      if Configuration.Redirects.Follow_Redirects
        and then Configuration.Redirects.Max_Redirects = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Configuration.Enable_Decompression
        and then Configuration.Decompression.Maximum_Decoded_Body_Size = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      for Index in 1 .. Http_Client.Headers.Length (Configuration.Default_Headers) loop
         if Is_Forbidden_Default_Header
           (Http_Client.Headers.Name_At (Configuration.Default_Headers, Index))
         then
            return Http_Client.Errors.Invalid_Configuration;
         end if;
      end loop;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Invalid_Configuration;
   end Validate;

   function Initialize
     (Item          : in out Client;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      Status : constant Http_Client.Errors.Result_Status := Validate (Configuration);
   begin
      if Status /= Http_Client.Errors.Ok then
         Item.Initialized := False;
         return Status;
      end if;

      if Item.State = null then
         Item.State := new Client_State;
      else
         Clear_Real_Pool (Item.State);
      end if;

      Item.Initialized := True;
      Item.Config := Configuration;
      Http_Client.Connection_Pools.Initialize (Item.State.Pool, Configuration.Pooling);
      Http_Client.Protocol_Discovery.Initialize
        (Item.Discovery_Cache, Configuration.Discovery);
      return Http_Client.Errors.Ok;
   end Initialize;

   function Configure
     (Item          : in out Client;
      Configuration : Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      Status : constant Http_Client.Errors.Result_Status := Validate (Configuration);
   begin
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Item.State = null then
         Item.State := new Client_State;
      else
         Clear_Real_Pool (Item.State);
      end if;

      Item.Initialized := True;
      Item.Config := Configuration;
      Http_Client.Connection_Pools.Initialize (Item.State.Pool, Configuration.Pooling);
      Http_Client.Protocol_Discovery.Initialize
        (Item.Discovery_Cache, Configuration.Discovery);
      return Http_Client.Errors.Ok;
   end Configure;

   function Configuration (Item : Client) return Client_Configuration is
   begin
      return Item.Config;
   end Configuration;

   function Accept_Alt_Svc_Header
     (Item                         : in out Client;
      Origin                       : Http_Client.URI.URI_Reference;
      Header                       : String;
      Received_At                  : Ada.Calendar.Time;
      From_Verified_HTTPS_Response : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
   begin
      if not Item.Initialized then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      return Http_Client.Protocol_Discovery.Accept_Alt_Svc
        (Cache                        => Item.Discovery_Cache,
         Origin                       => Origin,
         Header                       => Header,
         Received_At                  => Received_At,
         Options                      => Item.Config.Discovery,
         From_Verified_HTTPS_Response => From_Verified_HTTPS_Response);
   end Accept_Alt_Svc_Header;

   procedure Clear_Discovery_Cache (Item : in out Client) is
   begin
      Http_Client.Protocol_Discovery.Clear (Item.Discovery_Cache);
   end Clear_Discovery_Cache;


   function Set_Default_Header
     (Configuration : in out Client_Configuration;
      Name          : String;
      Value         : String) return Http_Client.Errors.Result_Status
   is
   begin
      if Is_Forbidden_Default_Header (Name) then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      return Http_Client.Headers.Set
        (Configuration.Default_Headers,
         Name,
         Value);
   end Set_Default_Header;

   function Remove_Default_Header
     (Configuration : in out Client_Configuration;
      Name          : String) return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Headers.Remove (Configuration.Default_Headers, Name);
   end Remove_Default_Header;

   function Apply_Default_Headers
     (Request       : Http_Client.Requests.Request;
      Configuration : Client_Configuration;
      Result        : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Status  : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   begin
      Result := Http_Client.Requests.Default_Request;

      for Index in 1 .. Http_Client.Headers.Length (Configuration.Default_Headers) loop
         declare
            Name  : constant String :=
              Http_Client.Headers.Name_At (Configuration.Default_Headers, Index);
            Value : constant String :=
              Http_Client.Headers.Value_At (Configuration.Default_Headers, Index);
         begin
            if Is_Forbidden_Default_Header (Name) then
               return Http_Client.Errors.Invalid_Configuration;
            end if;

            if not Http_Client.Headers.Contains (Headers, Name) then
               Status := Http_Client.Headers.Add (Headers, Name, Value);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;
         end;
      end loop;

      if Configuration.Execution.Advertise_Accept_Encoding
        and then not Http_Client.Headers.Contains (Headers, "Accept-Encoding")
      then
         Status :=
           Http_Client.Headers.Set
             (Headers,
              "Accept-Encoding",
              Http_Client.Decompression.Supported_Accept_Encoding);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      Status := Http_Client.Requests.Create
        (Method    => Http_Client.Requests.Method (Request),
         URI       => Http_Client.Requests.URI (Request),
         Item      => Result,
         Headers   => Headers,
         Payload   => Http_Client.Requests.Payload (Request),
         Auto_Host => False);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Requests.Set_Body
        (Result,
         Http_Client.Requests.Request_Body (Request));
   exception
      when others =>
         Result := Http_Client.Requests.Default_Request;
         return Http_Client.Errors.Internal_Error;
   end Apply_Default_Headers;

   procedure Reset_Client_Result (Result : out Client_Result) is
   begin
      Result :=
        (Status              => Http_Client.Errors.Internal_Error,
         Response            => Http_Client.Responses.Default_Response,
         Decoded_Response    => Http_Client.Decompression.Default_Decoded_Response,
         Final_URI           => Http_Client.URI.Create_Unchecked (""),
         Redirect_Count      => 0,
         Retry_Attempt_Count => 0,
         Retry_Exhausted     => False,
         Used_Decoded_View   => False,
         Cache_Metadata      =>
           (Source             => Http_Client.Cache.Cache_Bypassed,
            Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
            Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
            Age_Seconds        => 0,
            Revalidation_Count => 0,
            Entry_Count        => 0,
            Stored_Body_Bytes  => 0));
   end Reset_Client_Result;

   function Execute
     (Item    : Client;
      Request : Http_Client.Requests.Request;
      Result  : out Client_Result) return Http_Client.Errors.Result_Status
   is
      Effective_Request : Http_Client.Requests.Request;
      Effective_Config  : Client_Configuration := Item.Config;
      Status            : Http_Client.Errors.Result_Status;
      Redirect_Result_Value : Redirect_Result;
      Retry_Result_Value    : Retry_Result;
      Request_Was_HEAD      : Boolean := False;
   begin
      Reset_Client_Result (Result);

      if not Item.Initialized then
         Result.Status := Http_Client.Errors.Client_Not_Initialized;
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Apply_Protocol_Policy (Effective_Config);

      Status := Validate (Effective_Config);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         Result.Status := Http_Client.Errors.Invalid_Request;
         return Http_Client.Errors.Invalid_Request;
      end if;

      Status := Apply_Default_Headers
        (Request       => Request,
         Configuration => Effective_Config,
         Result        => Effective_Request);

      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      Request_Was_HEAD :=
        Http_Client.Requests.Method (Effective_Request) = Http_Client.Types.HEAD;

      if Effective_Config.Enable_Decompression then
         Effective_Config.Execution.Advertise_Accept_Encoding := True;
      end if;

      if Effective_Config.Pooling.Enabled then
         --  HTTP/1.1 persistence is the default. Enabling pooling policy on the
         --  high-level configuration must not synthesize Connection: close
         --  unless the caller explicitly supplied it on the request. Clean
         --  compatible buffered HTTP/1.1 TCP/TLS handles may then be retained
         --  by this client after the exchange.
         Effective_Config.Execution.Add_Connection_Close := False;
      end if;

      if Effective_Config.Proxy_Discovery.Enabled
        and then Length (Effective_Config.Proxy_PAC_Script) > 0
        and then
          (not Http_Client.Proxies.Is_Enabled (Effective_Config.Execution.Proxy)
           or else Effective_Config.Proxy_Discovery.Precedence =
             Http_Client.Proxy_Discovery.Discovery_Wins_When_Enabled)
      then
         declare
            PAC_Status : Http_Client.Errors.Result_Status;
            PAC_Config : Http_Client.Proxies.Proxy_Config;
         begin
            PAC_Status := Http_Client.Proxy_Discovery.Resolve_PAC_Script
              (Script  => To_String (Effective_Config.Proxy_PAC_Script),
               Target  => Http_Client.Requests.URI (Effective_Request),
               Options => Effective_Config.Proxy_Discovery,
               Config  => PAC_Config);

            if PAC_Status /= Http_Client.Errors.Ok then
               Result.Status := PAC_Status;
               return PAC_Status;
            end if;

            Effective_Config.Execution.Proxy := PAC_Config;
         end;
      end if;

      if Effective_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Required
        and then Effective_Config.Execution.Protocol_Policy in
          Protocol_From_Configuration | Prefer_HTTP_3 | Force_HTTP_3
        and then not Http_Client.URI.Requires_TLS
          (Http_Client.Requests.URI (Effective_Request))
      then
         declare
            HTTP3_Request_ID : constant Http_Client.Diagnostics.Diagnostic_ID :=
              New_Request_ID (Effective_Config.Execution);
            HTTP3_Connection_ID : constant Http_Client.Diagnostics.Diagnostic_ID :=
              New_Connection_ID (Effective_Config.Execution);
         begin
            Status := Emit_Diagnostic
              (Effective_Config.Execution,
               (Kind          => Http_Client.Diagnostics.HTTP3_Execution_Unsupported,
                Request_ID    => HTTP3_Request_ID,
                Connection_ID => HTTP3_Connection_ID,
                URI_Or_Origin => Http_Client.Diagnostics.To_Text
                  (Http_Client.URI.Host
                     (Http_Client.Requests.URI (Effective_Request))),
                Result        => Http_Client.Errors.HTTP3_Unsupported,
                Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                Message       => Http_Client.Diagnostics.To_Text
                  ("HTTP/3 required for non-HTTPS URI"),
                others        => <>));
            if Status /= Http_Client.Errors.Ok then
               Result.Status := Status;
               return Status;
            end if;
         end;

         Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
         Result.Redirect_Count := 0;
         Result.Status := Http_Client.Errors.HTTP3_Unsupported;
         return Http_Client.Errors.HTTP3_Unsupported;
      end if;

      if Effective_Config.Cache.Enabled and then Effective_Config.Cache_Store /= null
        and then not Effective_Config.Retries.Enable_Retries
        and then not Effective_Config.Redirects.Follow_Redirects
        and then not Effective_Config.Enable_Decompression
      then
         if Effective_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled
           or else Effective_Config.Execution.Protocol_Policy in Force_HTTP_1_1 | Prefer_HTTP_2 | Force_HTTP_2
         then
            Status := Execute_With_Cache
              (Item     => Item,
               Request  => Effective_Request,
               Response => Result.Response,
               Cache    => Effective_Config.Cache_Store.all,
               Metadata => Result.Cache_Metadata,
               Options  => Effective_Config.Execution,
               Policy   => Effective_Config.Cache);

            Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
            Result.Redirect_Count := 0;
            Result.Status := Status;
            return Result.Status;
         else
            --  HTTP/3 candidate routing must not enter the legacy cache wrapper
            --  because that wrapper performs HTTP/1.1/HTTP/2 network misses and
            --  revalidations internally. Fresh cache hits, however, remain pure
            --  HTTP semantics and must avoid QUIC network creation entirely.
            declare
               Cached             : Http_Client.Responses.Response;
               Lookup_Metadata    : Http_Client.Cache.Cache_Metadata;
               Lookup_Status      : Http_Client.Errors.Result_Status;
               Force_Revalidation : constant Boolean :=
                 Request_Forces_Cache_Revalidation (Effective_Request);
               Only_If_Cached     : constant Boolean :=
                 Request_Has_Cache_Token (Effective_Request, "only-if-cached");
               Cache_Event        : Http_Client.Diagnostics.Cache_Result :=
                 Http_Client.Diagnostics.Cache_Miss;
            begin
               Http_Client.Cache.Configure
                 (Effective_Config.Cache_Store.all, Effective_Config.Cache);

               Lookup_Status := Http_Client.Cache.Lookup
                 (Cache    => Effective_Config.Cache_Store.all,
                  Request  => Effective_Request,
                  Response => Cached,
                  Metadata => Lookup_Metadata);

               if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
                  Cache_Event := Http_Client.Diagnostics.Cache_Hit;
               elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
                 or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
               then
                  Cache_Event := Http_Client.Diagnostics.Cache_Stale;
               elsif Lookup_Status = Http_Client.Errors.Cache_Miss then
                  Cache_Event := Http_Client.Diagnostics.Cache_Miss;
               else
                  Cache_Event := Http_Client.Diagnostics.Cache_Bypassed;
               end if;

               Status := Emit_Diagnostic
                 (Effective_Config.Execution,
                  (Kind     => Http_Client.Diagnostics.Cache_Lookup_Result,
                   Cache    => Cache_Event,
                   Result   => Lookup_Status,
                   Protocol => Http_Client.Diagnostics.Protocol_HTTP_3,
                   Message  => Http_Client.Diagnostics.To_Text
                     ("HTTP/3 fresh-cache lookup only"),
                   others   => <>));
               if Status /= Http_Client.Errors.Ok then
                  Result.Status := Status;
                  return Status;
               end if;

               if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
                  Result.Response := Cached;
                  Result.Cache_Metadata := Lookup_Metadata;
                  Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
                  Result.Redirect_Count := 0;
                  Result.Status := Http_Client.Errors.Ok;
                  return Http_Client.Errors.Ok;
               elsif Only_If_Cached then
                  Result.Cache_Metadata := Lookup_Metadata;
                  Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
                  Result.Redirect_Count := 0;
                  Result.Status := Http_Client.Errors.Cache_Miss;
                  return Http_Client.Errors.Cache_Miss;
               end if;
            end;
         end if;
      elsif Effective_Config.Cache.Enabled
        and then Effective_Config.Persistent_Cache_Store /= null
        and then not Effective_Config.Retries.Enable_Retries
        and then not Effective_Config.Redirects.Follow_Redirects
        and then not Effective_Config.Enable_Decompression
      then
         if Effective_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled
           or else Effective_Config.Execution.Protocol_Policy in Force_HTTP_1_1 | Prefer_HTTP_2 | Force_HTTP_2
         then
            Status := Execute_With_Persistent_Cache
              (Item     => Item,
               Request  => Effective_Request,
               Response => Result.Response,
               Cache    => Effective_Config.Persistent_Cache_Store.all,
               Metadata => Result.Cache_Metadata,
               Options  => Effective_Config.Execution);

            Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
            Result.Redirect_Count := 0;
            Result.Status := Status;
            return Result.Status;
         else
            --  Persistent/encrypted cache hits are likewise safe before QUIC,
            --  but misses and stale revalidations must be handled by a future
            --  backend-aware HTTP/3 cache path rather than the TCP wrapper.
            declare
               Cached             : Http_Client.Responses.Response;
               Lookup_Metadata    : Http_Client.Cache.Cache_Metadata;
               Lookup_Status      : Http_Client.Errors.Result_Status;
               Force_Revalidation : constant Boolean :=
                 Request_Forces_Cache_Revalidation (Effective_Request);
               Only_If_Cached     : constant Boolean :=
                 Request_Has_Cache_Token (Effective_Request, "only-if-cached");
               Cache_Event        : Http_Client.Diagnostics.Cache_Result :=
                 Http_Client.Diagnostics.Cache_Miss;
            begin
               Lookup_Status := Http_Client.Cache.Persistent.Lookup
                 (Store    => Effective_Config.Persistent_Cache_Store.all,
                  Request  => Effective_Request,
                  Response => Cached,
                  Metadata => Lookup_Metadata);

               if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
                  Cache_Event := Http_Client.Diagnostics.Cache_Hit;
               elsif Lookup_Status = Http_Client.Errors.Cache_Entry_Stale
                 or else (Lookup_Status = Http_Client.Errors.Ok and then Force_Revalidation)
               then
                  Cache_Event := Http_Client.Diagnostics.Cache_Stale;
               elsif Lookup_Status = Http_Client.Errors.Cache_Miss then
                  Cache_Event := Http_Client.Diagnostics.Cache_Miss;
               else
                  Cache_Event := Http_Client.Diagnostics.Cache_Bypassed;
               end if;

               Status := Emit_Diagnostic
                 (Effective_Config.Execution,
                  (Kind     => Http_Client.Diagnostics.Cache_Lookup_Result,
                   Cache    => Cache_Event,
                   Result   => Lookup_Status,
                   Protocol => Http_Client.Diagnostics.Protocol_HTTP_3,
                   Message  => Http_Client.Diagnostics.To_Text
                     ("HTTP/3 persistent-cache lookup only"),
                   others   => <>));
               if Status /= Http_Client.Errors.Ok then
                  Result.Status := Status;
                  return Status;
               end if;

               if Lookup_Status = Http_Client.Errors.Ok and then not Force_Revalidation then
                  Result.Response := Cached;
                  Result.Cache_Metadata := Lookup_Metadata;
                  Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
                  Result.Redirect_Count := 0;
                  Result.Status := Http_Client.Errors.Ok;
                  return Http_Client.Errors.Ok;
               elsif Only_If_Cached then
                  Result.Cache_Metadata := Lookup_Metadata;
                  Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
                  Result.Redirect_Count := 0;
                  Result.Status := Http_Client.Errors.Cache_Miss;
                  return Http_Client.Errors.Cache_Miss;
               end if;
            end;
         end if;
      end if;

      if Http_Client.URI.Requires_TLS (Http_Client.Requests.URI (Effective_Request))
        and then Effective_Config.Execution.Protocol_Policy in
          Protocol_From_Configuration | Prefer_HTTP_3 | Force_HTTP_3
        and then Effective_Config.HTTP3.Mode /= Http_Client.HTTP3.HTTP3_Disabled
      then
         declare
            Proxy_Configured : constant Boolean :=
              Http_Client.Proxies.Is_Enabled (Effective_Config.Execution.Proxy)
              and then Http_Client.Proxies.Kind (Effective_Config.Execution.Proxy) =
                Http_Client.Proxies.HTTP_Proxy;
            SOCKS_Configured : constant Boolean :=
              Http_Client.Proxies.Is_Enabled (Effective_Config.Execution.Proxy)
              and then Http_Client.Proxies.Kind (Effective_Config.Execution.Proxy) =
                Http_Client.Proxies.SOCKS5_Proxy;
            HTTP3_Status : Http_Client.Errors.Result_Status;
            Fallback_Status : Http_Client.Errors.Result_Status;
            Discovery_Status : Http_Client.Errors.Result_Status;
            Discovery_Cache  : Http_Client.Protocol_Discovery.Discovery_Cache := Item.Discovery_Cache;
            Discovery_Selection : Http_Client.Protocol_Discovery.Discovery_Selection :=
              (Source => Http_Client.Protocol_Discovery.Discovery_None,
               Protocol => Http_Client.HTTP3.Protocol_None,
               Alternative_Host => Null_Unbounded_String,
               Alternative_Port => 0,
               Uses_Origin_Host => False,
               Requires_Origin_TLS_Authority => True);
            HTTP3_Request_ID : constant Http_Client.Diagnostics.Diagnostic_ID :=
              New_Request_ID (Effective_Config.Execution);
            HTTP3_Connection_ID : constant Http_Client.Diagnostics.Diagnostic_ID :=
              New_Connection_ID (Effective_Config.Execution);
         begin
            if Effective_Config.Discovery.Allow_HTTP3_Discovery then
               if Proxy_Configured or else SOCKS_Configured then
                  Status := Emit_Diagnostic
                    (Effective_Config.Execution,
                     (Kind          => Http_Client.Diagnostics.Discovery_Skipped_Due_To_Proxy,
                      Request_ID    => HTTP3_Request_ID,
                      Connection_ID => HTTP3_Connection_ID,
                      URI_Or_Origin => Http_Client.Diagnostics.To_Text
                        (Http_Client.URI.Host
                           (Http_Client.Requests.URI (Effective_Request))),
                      Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                      Message       => Http_Client.Diagnostics.To_Text
                        ("protocol discovery skipped because a proxy is configured"),
                      others        => <>));
                  if Status /= Http_Client.Errors.Ok then
                     Result.Status := Status;
                     return Status;
                  end if;
               else
                  Discovery_Status := Http_Client.Protocol_Discovery.Selection
                    (Cache     => Discovery_Cache,
                     Origin    => Http_Client.Requests.URI (Effective_Request),
                     Options   => Effective_Config.Discovery,
                     HTTP3     => Effective_Config.HTTP3,
                     Proxy     => Effective_Config.Execution.Proxy,
                     Now       => Ada.Calendar.Clock,
                     Selection => Discovery_Selection);
                  if Discovery_Status /= Http_Client.Errors.Ok then
                     Status := Emit_Diagnostic
                       (Effective_Config.Execution,
                        (Kind          => Http_Client.Diagnostics.HTTPS_SVCB_Result_Rejected,
                         Request_ID    => HTTP3_Request_ID,
                         Connection_ID => HTTP3_Connection_ID,
                         Result        => Discovery_Status,
                         Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                         others        => <>));
                     if Status /= Http_Client.Errors.Ok then
                        Result.Status := Status;
                        return Status;
                     end if;
                     if Effective_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Required then
                        Result.Status := Discovery_Status;
                        return Discovery_Status;
                     end if;
                  elsif Discovery_Selection.Source /=
                    Http_Client.Protocol_Discovery.Discovery_None
                  then
                     Status := Emit_Diagnostic
                       (Effective_Config.Execution,
                        (Kind          => Http_Client.Diagnostics.Discovery_Selected_HTTP3,
                         Request_ID    => HTTP3_Request_ID,
                         Connection_ID => HTTP3_Connection_ID,
                         URI_Or_Origin => Http_Client.Diagnostics.To_Text
                           (Http_Client.URI.Host
                              (Http_Client.Requests.URI (Effective_Request))),
                         Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                         Message       => Http_Client.Diagnostics.To_Text
                           ("protocol discovery selected HTTP/3; TLS authority remains the origin"),
                         others        => <>));
                     if Status /= Http_Client.Errors.Ok then
                        Result.Status := Status;
                        return Status;
                     end if;
                  end if;
               end if;
            end if;

            Status := Emit_Diagnostic
              (Effective_Config.Execution,
               (Kind          => Http_Client.Diagnostics.HTTP3_Candidate_Selected,
                Request_ID    => HTTP3_Request_ID,
                Connection_ID => HTTP3_Connection_ID,
                URI_Or_Origin => Http_Client.Diagnostics.To_Text
                  (Http_Client.URI.Host (Http_Client.Requests.URI (Effective_Request))),
                Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                others        => <>));
            if Status /= Http_Client.Errors.Ok then
               Result.Status := Status;
               return Status;
            end if;

            HTTP3_Status := Http_Client.HTTP3.Execution.Execute_Buffered
              (Request                       => Effective_Request,
               Options                       => Effective_Config.HTTP3,
               Response                      => Result.Response,
               Proxy_Configured              => Proxy_Configured,
               SOCKS_Configured              => SOCKS_Configured,
               Client_Certificate_Configured =>
                 Request_Uses_Client_Certificate
                   (Effective_Request, Effective_Config.Execution),
               Alternative_Host              =>
                 To_String (Discovery_Selection.Alternative_Host),
               Alternative_Port              =>
                 Discovery_Selection.Alternative_Port,
               Requires_Origin_TLS_Authority =>
                 Discovery_Selection.Requires_Origin_TLS_Authority,
               Max_Body_Size                 =>
                 Effective_Config.Execution.Max_Body_Size,
               Diagnostics                   =>
                 Effective_Config.Execution.Diagnostics,
               Request_ID                    => HTTP3_Request_ID,
               Connection_ID                 => HTTP3_Connection_ID,
               Backend                       => Effective_Config.HTTP3_Backend);

            if HTTP3_Status = Http_Client.Errors.Ok then
               Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
               Result.Redirect_Count := 0;
               Result.Status := Http_Client.Errors.Ok;
               return Http_Client.Errors.Ok;
            end if;

            Fallback_Status := Http_Client.HTTP3.Fallback_Status
              (Effective_Config.HTTP3, Request_Bytes_Already_Sent => False);

            if Effective_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Required
              or else Fallback_Status /= Http_Client.Errors.Ok
            then
               Status := Emit_Diagnostic
                 (Effective_Config.Execution,
                  (Kind          => Http_Client.Diagnostics.HTTP3_Execution_Unsupported,
                   Request_ID    => HTTP3_Request_ID,
                   Connection_ID => HTTP3_Connection_ID,
                   Result        => HTTP3_Status,
                   Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                   others        => <>));
               if Status /= Http_Client.Errors.Ok then
                  Result.Status := Status;
                  return Status;
               end if;
               Result.Status := HTTP3_Status;
               return HTTP3_Status;
            end if;

            Status := Emit_Diagnostic
              (Effective_Config.Execution,
               (Kind          => Http_Client.Diagnostics.HTTP3_Unsupported_Fallback,
                Request_ID    => HTTP3_Request_ID,
                Connection_ID => HTTP3_Connection_ID,
                Result        => HTTP3_Status,
                Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
                others        => <>));
            if Status /= Http_Client.Errors.Ok then
               Result.Status := Status;
               return Status;
            end if;
         end;
      end if;

      if Effective_Config.Retries.Enable_Retries then
         if Effective_Config.Redirects.Follow_Redirects then
            Status := Execute_With_Redirects_And_Retry
              (Item           => Item,
               Request        => Effective_Request,
               Result         => Redirect_Result_Value,
               Retry_Metadata => Retry_Result_Value,
               Execution      => Effective_Config.Execution,
               Redirects      => Effective_Config.Redirects,
               Retries        => Effective_Config.Retries);

            Result.Response := Redirect_Result_Value.Final_Response;
            Result.Final_URI := Redirect_Result_Value.Final_URI;
            Result.Redirect_Count := Redirect_Result_Value.Redirect_Count;
            Result.Retry_Attempt_Count := Retry_Result_Value.Attempts;
            Result.Retry_Exhausted := Retry_Result_Value.Retries_Exhausted;
            Request_Was_HEAD := Redirect_Result_Value.Final_Request_Was_HEAD;
         else
            Status := Execute_With_Retry
              (Item      => Item,
               Request   => Effective_Request,
               Result    => Retry_Result_Value,
               Execution => Effective_Config.Execution,
               Retries   => Effective_Config.Retries);

            Result.Response := Retry_Result_Value.Final_Response;
            Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
            Result.Redirect_Count := 0;
            Result.Retry_Attempt_Count := Retry_Result_Value.Attempts;
            Result.Retry_Exhausted := Retry_Result_Value.Retries_Exhausted;
         end if;
      else
         if Effective_Config.Redirects.Follow_Redirects then
            Status := Execute_With_Redirects
              (Item      => Item,
               Request   => Effective_Request,
               Result    => Redirect_Result_Value,
               Execution => Effective_Config.Execution,
               Redirects => Effective_Config.Redirects);

            Result.Response := Redirect_Result_Value.Final_Response;
            Result.Final_URI := Redirect_Result_Value.Final_URI;
            Result.Redirect_Count := Redirect_Result_Value.Redirect_Count;
            Request_Was_HEAD := Redirect_Result_Value.Final_Request_Was_HEAD;
         else
            Status := Execute
              (Item     => Item,
               Request  => Effective_Request,
               Response => Result.Response,
               Options  => Effective_Config.Execution);

            Result.Final_URI := Http_Client.Requests.URI (Effective_Request);
            Result.Redirect_Count := 0;
         end if;
      end if;

      Result.Status := Status;

      if Status = Http_Client.Errors.Ok and then Effective_Config.Enable_Decompression then
         Status := Http_Client.Decompression.Decode_Response_With_Context
           (Response         => Result.Response,
            Request_Was_HEAD => Request_Was_HEAD,
            Result           => Result.Decoded_Response,
            Options          => Effective_Config.Decompression);

         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Diagnostic
                (Effective_Config.Execution,
                 (Kind                => Http_Client.Diagnostics.Decompression_Result,
                  Result              => Status,
                  Response_Byte_Count => Http_Client.Decompression.Decoded_Body (Result.Decoded_Response)'Length,
                  others              => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               Result.Status := Emit_Status;
               return Emit_Status;
            end if;
         end;

         Result.Status := Status;
         Result.Used_Decoded_View := Status = Http_Client.Errors.Ok;
      end if;

      return Result.Status;
   exception
      when others =>
         Reset_Client_Result (Result);
         Result.Status := Http_Client.Errors.Internal_Error;
         return Http_Client.Errors.Internal_Error;
   end Execute;


   function Reject_Uninitialized_Client
     (Item   : Client;
      Result : out Client_Result) return Boolean
   is
   begin
      if Item.Initialized then
         return False;
      end if;

      Reset_Client_Result (Result);
      Result.Status := Http_Client.Errors.Client_Not_Initialized;
      return True;
   end Reject_Uninitialized_Client;

   function Build_Simple_Request
     (Method       : Http_Client.Types.Method_Name;
      URL          : String;
      Payload      : String;
      Content_Type : String;
      Request      : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      URI     : Http_Client.URI.URI_Reference;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Request := Http_Client.Requests.Default_Request;

      Status := Http_Client.URI.Parse (URL, URI);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Content_Type'Length > 0 then
         Status := Http_Client.Headers.Set (Headers, "Content-Type", Content_Type);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      return Http_Client.Requests.Create
        (Method    => Method,
         URI       => URI,
         Item      => Request,
         Headers   => Headers,
         Payload   => Payload,
         Auto_Host => True);
   exception
      when others =>
         Request := Http_Client.Requests.Default_Request;
         return Http_Client.Errors.Internal_Error;
   end Build_Simple_Request;

   function Execute_Stream
     (Item    : Client;
      Request : Http_Client.Requests.Request;
      Stream  : in out Http_Client.Response_Streams.Streaming_Response)
      return Http_Client.Errors.Result_Status
   is
      Effective_Request : Http_Client.Requests.Request;
      Effective_Config  : Client_Configuration := Item.Config;
      Status            : Http_Client.Errors.Result_Status;
   begin
      if not Item.Initialized then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Validate (Effective_Config);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Effective_Config.Enable_Decompression then
         Effective_Config.Execution.Advertise_Accept_Encoding := True;
      end if;

      if Effective_Config.Pooling.Enabled then
         Effective_Config.Execution.Add_Connection_Close := False;
      end if;

      Status := Apply_Default_Headers
        (Request       => Request,
         Configuration => Effective_Config,
         Result        => Effective_Request);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Effective_Config.Proxy_Discovery.Enabled
        and then Length (Effective_Config.Proxy_PAC_Script) > 0
        and then
          (not Http_Client.Proxies.Is_Enabled (Effective_Config.Execution.Proxy)
           or else Effective_Config.Proxy_Discovery.Precedence =
             Http_Client.Proxy_Discovery.Discovery_Wins_When_Enabled)
      then
         declare
            PAC_Status : Http_Client.Errors.Result_Status;
            PAC_Config : Http_Client.Proxies.Proxy_Config;
         begin
            PAC_Status := Http_Client.Proxy_Discovery.Resolve_PAC_Script
              (Script  => To_String (Effective_Config.Proxy_PAC_Script),
               Target  => Http_Client.Requests.URI (Effective_Request),
               Options => Effective_Config.Proxy_Discovery,
               Config  => PAC_Config);

            if PAC_Status /= Http_Client.Errors.Ok then
               return PAC_Status;
            end if;

            Effective_Config.Execution.Proxy := PAC_Config;
         end;
      end if;

      Effective_Config.Execution.TLS :=
        Effective_TLS_Options_For_Request (Effective_Request, Effective_Config.Execution);

      declare
         function Open_With_Pre_Header_Retry
           (Request_To_Open : Http_Client.Requests.Request;
            Final_URI       : Http_Client.URI.URI_Reference;
            Redirect_Count  : Natural := 0)
            return Http_Client.Errors.Result_Status
         is
            Attempt        : Positive := 1;
            Attempts_Limit : constant Positive :=
              (if Effective_Config.Retries.Enable_Retries
               then Effective_Config.Retries.Maximum_Attempts
               else 1);
            Method_Allows  : constant Boolean :=
              Http_Client.Retry.Is_Retryable_Method
                (Method  => Http_Client.Requests.Method (Request_To_Open),
                 Options => Effective_Config.Retries);
            Open_Status    : Http_Client.Errors.Result_Status;
            Planned_Delay  : Http_Client.Retry.Delay_Milliseconds := 0;
         begin
            if Effective_Config.Retries.Enable_Retries
              and then Attempts_Limit > 1
              and then not Http_Client.Retry.Is_Request_Body_Replayable (Request_To_Open)
            then
               return Http_Client.Errors.Retry_Body_Not_Replayable;
            end if;

            loop
               declare
                  Stream_Options : Http_Client.Response_Streams.Streaming_Options :=
                    Streaming_Options_For (Effective_Config.Execution);
               begin
                  Stream_Options.Enable_Decompression :=
                    Effective_Config.Enable_Decompression;
                  Stream_Options.Decompression := Effective_Config.Decompression;

                  Open_Status := Http_Client.Response_Streams.Open
                    (Request   => Request_To_Open,
                     Stream    => Stream,
                     Options   => Stream_Options,
                     Final_URI => Final_URI,
                     Redirect_Count => Redirect_Count,
                     Retry_Attempt_Count => Attempt);
               end;

               if Open_Status = Http_Client.Errors.Ok then
                  return Http_Client.Errors.Ok;
               end if;

               exit when not Effective_Config.Retries.Enable_Retries;
               exit when not Method_Allows;
               exit when Attempt >= Attempts_Limit;
               exit when not Http_Client.Retry.Is_Retryable_Failure
                 (Status  => Open_Status,
                  Options => Effective_Config.Retries);

               Planned_Delay := Http_Client.Retry.Delay_For_Attempt
                 (Attempt => Attempt,
                  Options => Effective_Config.Retries);

               begin
                  if Effective_Config.Retries.Delay_Hook /= null then
                     Effective_Config.Retries.Delay_Hook.all (Planned_Delay);
                  end if;
               exception
                  when others =>
                     return Http_Client.Errors.Internal_Error;
               end;

               declare
                  Reset_Status : constant Http_Client.Errors.Result_Status :=
                    Http_Client.Requests.Reset_Body (Request_To_Open);
               begin
                  if Reset_Status /= Http_Client.Errors.Ok then
                     return Reset_Status;
                  end if;
               end;

               Attempt := Attempt + 1;
            end loop;

            return Open_Status;
         end Open_With_Pre_Header_Retry;
      begin

      if Effective_Config.Redirects.Follow_Redirects then
         declare
            Current_Request : Http_Client.Requests.Request := Effective_Request;
            Current_URI     : Http_Client.URI.URI_Reference :=
              Http_Client.Requests.URI (Effective_Request);
            Count           : Natural := 0;
         begin
            loop
               Status := Open_With_Pre_Header_Retry
                 (Request_To_Open => Current_Request,
                  Final_URI       => Current_URI,
                  Redirect_Count  => Count);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

               exit when not Status_Is_Followed_Redirect
                 (Http_Client.Response_Streams.Status_Code (Stream));

               declare
                  Headers  : constant Http_Client.Headers.Header_List :=
                    Http_Client.Response_Streams.Headers (Stream);
                  Location : constant String :=
                    Http_Client.Headers.Get (Headers, "Location");
                  Target   : Http_Client.URI.URI_Reference;
                  Next     : Http_Client.Requests.Request;
                  Ignored  : Http_Client.Errors.Result_Status;
               begin
                  Ignored := Http_Client.Response_Streams.Close (Stream);
                  pragma Unreferenced (Ignored);

                  if not Http_Client.Headers.Contains (Headers, "Location") then
                     return Http_Client.Errors.Invalid_Redirect;
                  end if;

                  if Count >= Effective_Config.Redirects.Max_Redirects then
                     return Http_Client.Errors.Too_Many_Redirects;
                  end if;

                  Status := Resolve_Location (Current_URI, Location, Target);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;

                  if Http_Client.URI.Requires_TLS (Current_URI)
                    and then not Http_Client.URI.Requires_TLS (Target)
                    and then not Effective_Config.Redirects.Allow_HTTPS_To_HTTP_Redirects
                  then
                     return Http_Client.Errors.Redirect_Downgrade_Blocked;
                  end if;

                  Status := Build_Redirected_Request
                    (Current_Request => Current_Request,
                     Current_URI     => Current_URI,
                     Target_URI      => Target,
                     Status_Code     => Http_Client.Response_Streams.Status_Code (Stream),
                     Redirects       => Effective_Config.Redirects,
                     Next_Request    => Next);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;

                  declare
                     Emit_Status : constant Http_Client.Errors.Result_Status :=
                       Emit_Diagnostic
                         (Effective_Config.Execution,
                          (Kind           => Http_Client.Diagnostics.Redirect_Decision,
                           Redirect_Count => Count + 1,
                           Status_Code    => Natural (Http_Client.Response_Streams.Status_Code (Stream)),
                           URI_Or_Origin  => Http_Client.Diagnostics.To_Text
                             (Http_Client.URI.Scheme (Target) & "://" & Http_Client.URI.Authority_Host (Target)),
                           Header_Name    => Http_Client.Diagnostics.To_Text ("Location"),
                           Header_Value   => Http_Client.Diagnostics.To_Text (Location),
                           Header_Redacted => False,
                           Message        => Http_Client.Diagnostics.To_Text
                       (Http_Client.URI.Image (Target) & Character'Val (10) & Location),
                           others         => <>));
                  begin
                     if Emit_Status /= Http_Client.Errors.Ok then
                        return Emit_Status;
                     end if;
                  end;

                  Count := Count + 1;
                  Current_Request := Next;
                  Current_URI := Target;
               end;
            end loop;

            return Http_Client.Errors.Ok;
         end;
      end if;

      return Open_With_Pre_Header_Retry
        (Request_To_Open => Effective_Request,
         Final_URI       => Http_Client.URI.Create_Unchecked (""));
      end;
   end Execute_Stream;

   function Get
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Reject_Uninitialized_Client (Item, Result) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.GET,
         URL          => URL,
         Payload      => "",
         Content_Type => "",
         Request      => Request);

      if Status /= Http_Client.Errors.Ok then
         Reset_Client_Result (Result);
         Result.Status := Status;
         return Status;
      end if;

      return Execute (Item, Request, Result);
   end Get;

   function Get
     (URL           : String;
      Result        : out Client_Result;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      Item   : Client;
      Status : Http_Client.Errors.Result_Status;
   begin
      Reset_Client_Result (Result);

      Status := Initialize (Item, Configuration);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      return Get
        (Item   => Item,
         URL    => URL,
         Result => Result);
   end Get;

   function Head
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Reject_Uninitialized_Client (Item, Result) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.HEAD,
         URL          => URL,
         Payload      => "",
         Content_Type => "",
         Request      => Request);

      if Status /= Http_Client.Errors.Ok then
         Reset_Client_Result (Result);
         Result.Status := Status;
         return Status;
      end if;

      return Execute (Item, Request, Result);
   end Head;

   function Head
     (URL           : String;
      Result        : out Client_Result;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      Item   : Client;
      Status : Http_Client.Errors.Result_Status;
   begin
      Reset_Client_Result (Result);

      Status := Initialize (Item, Configuration);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      return Head
        (Item   => Item,
         URL    => URL,
         Result => Result);
   end Head;


   function Content_Length_Value
     (Headers : Http_Client.Headers.Header_List;
      Value   : out Natural) return Http_Client.Errors.Result_Status
   is
      Raw     : constant String := Http_Client.Headers.Get (Headers, "Content-Length");
      Trimmed : constant String := Ada.Strings.Fixed.Trim (Raw, Ada.Strings.Both);
   begin
      Value := 0;

      if not Http_Client.Headers.Contains (Headers, "Content-Length") then
         return Http_Client.Errors.Ok;
      elsif Trimmed'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;

      if Parse_Content_Length (Trimmed, Value) then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Errors.Invalid_Header;
      end if;
   exception
      when others =>
         Value := 0;
         return Http_Client.Errors.Invalid_Header;
   end Content_Length_Value;

   function Available_Sibling_Path
     (Base   : String;
      Suffix : String) return String
   is
      Candidate : Unbounded_String;
   begin
      for Index in Natural range 0 .. 999 loop
         if Index = 0 then
            Candidate := To_Unbounded_String (Base & Suffix);
         else
            Candidate :=
              To_Unbounded_String
                (Base & Suffix & "."
                 & Ada.Strings.Fixed.Trim
                     (Natural'Image (Index), Ada.Strings.Both));
         end if;

         if not Ada.Directories.Exists (To_String (Candidate)) then
            return To_String (Candidate);
         end if;
      end loop;

      return "";
   exception
      when others =>
         return "";
   end Available_Sibling_Path;

   function Delete_Ordinary_File_If_Present
     (Path : String) return Http_Client.Errors.Result_Status
   is
   begin
      if Path'Length = 0 or else not Ada.Directories.Exists (Path) then
         return Http_Client.Errors.Ok;
      end if;

      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         return Http_Client.Errors.Write_Failed;
      end if;

      Ada.Directories.Delete_File (Path);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Write_Failed;
   end Delete_Ordinary_File_If_Present;

   function Ensure_Parent_Directory
     (Path : String) return Http_Client.Errors.Result_Status
   is
      Parent : constant String := Ada.Directories.Containing_Directory (Path);
   begin
      if Path'Length = 0 then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Parent'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      if Ada.Directories.Exists (Parent) then
         if Ada.Directories.Kind (Parent) = Ada.Directories.Directory then
            return Http_Client.Errors.Ok;
         else
            return Http_Client.Errors.Write_Failed;
         end if;
      end if;

      Ada.Directories.Create_Path (Parent);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Write_Failed;
   end Ensure_Parent_Directory;

   function C_Open (Path : C_Strings.chars_ptr; Flags : C.int) return C.int
     with Import, Convention => C, External_Name => "open";

   function C_Fsync (FD : C.int) return C.int
     with Import, Convention => C, External_Name => "fsync";

   function C_Close (FD : C.int) return C.int
     with Import, Convention => C, External_Name => "close";

   O_RDONLY   : constant C.int := 0;
   O_DIRECTORY : constant C.int := 16#10000#;

   function Fsync_Open_Path (Path : String; Flags : C.int) return Boolean is
      use type C.int;
      use type C_Strings.chars_ptr;
      C_Path : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      FD     : C.int := -1;
      Result : C.int := -1;
      Closed : C.int := -1;
   begin
      if Path'Length = 0 then
         return False;
      end if;

      C_Path := C_Strings.New_String (Path);
      FD := C_Open (C_Path, Flags);
      C_Strings.Free (C_Path);
      if FD < 0 then
         return False;
      end if;

      Result := C_Fsync (FD);
      Closed := C_Close (FD);
      return Result = 0 and then Closed = 0;
   exception
      when others =>
         if C_Path /= C_Strings.Null_Ptr then
            C_Strings.Free (C_Path);
         end if;
         if FD >= 0 then
            Closed := C_Close (FD);
         end if;
         return False;
   end Fsync_Open_Path;

   function Fsync_File (Path : String) return Boolean is
   begin
      return Fsync_Open_Path (Path, O_RDONLY);
   end Fsync_File;

   procedure Fsync_Parent_Directory_Best_Effort (Path : String) is
      Parent : constant String := Ada.Directories.Containing_Directory (Path);
      Synced : Boolean;
   begin
      if Parent'Length = 0 or else not Ada.Directories.Exists (Parent) then
         return;
      end if;

      Synced := Fsync_Open_Path (Parent, O_RDONLY + O_DIRECTORY);
      if not Synced then
         Synced := Fsync_Open_Path (Parent, O_RDONLY);
      end if;
   exception
      when others =>
         null;
   end Fsync_Parent_Directory_Best_Effort;


   function Install_File_Atomically
     (Source_Path        : String;
      Target_Path        : String;
      Backup_Suffix      : String := ".http_client_old";
      Create_Parent_Dirs : Boolean := True;
      Durability         : File_Durability_Mode := File_Durability_Default)
      return Http_Client.Errors.Result_Status
   is
      Backup_Path : constant String := Available_Sibling_Path (Target_Path, Backup_Suffix);
      Had_Target  : constant Boolean := Ada.Directories.Exists (Target_Path);
      Status      : Http_Client.Errors.Result_Status;
   begin
      if Source_Path'Length = 0 or else Target_Path'Length = 0 then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Create_Parent_Dirs then
         Status := Ensure_Parent_Directory (Target_Path);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Backup_Path'Length = 0 then
         return Http_Client.Errors.Write_Failed;
      elsif not Ada.Directories.Exists (Source_Path)
        or else Ada.Directories.Kind (Source_Path) /= Ada.Directories.Ordinary_File
      then
         return Http_Client.Errors.Write_Failed;
      elsif Had_Target
        and then Ada.Directories.Kind (Target_Path) /= Ada.Directories.Ordinary_File
      then
         return Http_Client.Errors.Write_Failed;
      end if;

      Status := Delete_Ordinary_File_If_Present (Backup_Path);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Durability = File_Durability_Sync_Data_And_Directory
        and then not Fsync_File (Source_Path)
      then
         return Http_Client.Errors.Write_Failed;
      end if;

      if Had_Target then
         begin
            Ada.Directories.Rename
              (Old_Name => Target_Path,
               New_Name => Backup_Path);
         exception
            when others =>
               return Http_Client.Errors.Write_Failed;
         end;
      end if;

      begin
         Ada.Directories.Rename (Old_Name => Source_Path, New_Name => Target_Path);
      exception
         when others =>
            if Had_Target and then Ada.Directories.Exists (Backup_Path) then
               begin
                  Ada.Directories.Rename
                    (Old_Name => Backup_Path,
                     New_Name => Target_Path);
               exception
                  when others =>
                     null;
               end;
            end if;

            return Http_Client.Errors.Write_Failed;
      end;

      if Had_Target then
         Status := Delete_Ordinary_File_If_Present (Backup_Path);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Durability = File_Durability_Sync_Data_And_Directory then
         Fsync_Parent_Directory_Best_Effort (Target_Path);
      end if;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Write_Failed;
   end Install_File_Atomically;

   function Write_Text_File_Atomically
     (Path          : String;
      Content       : String;
      Temp_Suffix   : String := ".http_client_tmp";
      Backup_Suffix : String := ".http_client_old";
      Durability    : File_Durability_Mode := File_Durability_Default)
      return Http_Client.Errors.Result_Status
   is
      Output_File : Ada.Text_IO.File_Type;
      Temp_Path   : constant String := Available_Sibling_Path (Path, Temp_Suffix);
      Status      : Http_Client.Errors.Result_Status;
   begin
      if Path'Length = 0 or else Temp_Path'Length = 0 then
         return Http_Client.Errors.Write_Failed;
      end if;

      Status := Ensure_Parent_Directory (Path);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Delete_Ordinary_File_If_Present (Temp_Path);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Ada.Text_IO.Create (Output_File, Ada.Text_IO.Out_File, Temp_Path);
      Ada.Text_IO.Put (Output_File, Content);
      if Durability /= File_Durability_Default then
         Ada.Text_IO.Flush (Output_File);
      end if;
      Ada.Text_IO.Close (Output_File);

      Status := Install_File_Atomically
        (Source_Path        => Temp_Path,
         Target_Path        => Path,
         Backup_Suffix      => Backup_Suffix,
         Create_Parent_Dirs => False,
         Durability         => Durability);
      if Status /= Http_Client.Errors.Ok then
         declare
            Cleanup_Status : constant Http_Client.Errors.Result_Status :=
              Delete_Ordinary_File_If_Present (Temp_Path);
         begin
            null;
         end;
      end if;

      return Status;
   exception
      when others =>
         begin
            if Ada.Text_IO.Is_Open (Output_File) then
               Ada.Text_IO.Close (Output_File);
            end if;
         exception
            when others =>
               null;
         end;

         declare
            Cleanup_Status : constant Http_Client.Errors.Result_Status :=
              Delete_Ordinary_File_If_Present (Temp_Path);
         begin
            null;
         end;

         return Http_Client.Errors.Write_Failed;
   end Write_Text_File_Atomically;

   function Preflight_Download_Target
     (Path    : String;
      Options : Download_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if Path'Length = 0 then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if Options.File_Mode = Create_New
        and then Ada.Directories.Exists (Path)
      then
         return Http_Client.Errors.Write_Failed;
      end if;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Write_Failed;
   end Preflight_Download_Target;

   procedure Prepare_Download_Target
     (Path       : String;
      Options    : Download_Options;
      Actual     : out Ada.Strings.Unbounded.Unbounded_String;
      Final_Path : out Ada.Strings.Unbounded.Unbounded_String;
      Status     : out Http_Client.Errors.Result_Status)
   is
   begin
      Actual := Null_Unbounded_String;
      Final_Path := To_Unbounded_String (Path);
      Status := Http_Client.Errors.Ok;

      if Path'Length = 0 then
         Status := Http_Client.Errors.Invalid_Request;
         return;
      end if;

      if Options.Create_Parent_Dirs then
         declare
            Parent : constant String := Ada.Directories.Containing_Directory (Path);
         begin
            if Parent'Length > 0 and then not Ada.Directories.Exists (Parent) then
               Ada.Directories.Create_Path (Parent);
            end if;
         end;
      end if;

      case Options.File_Mode is
         when Create_New =>
            if Ada.Directories.Exists (Path) then
               Status := Http_Client.Errors.Write_Failed;
            else
               Actual := To_Unbounded_String (Path);
            end if;
         when Overwrite =>
            Actual := To_Unbounded_String (Path);
         when Replace_Atomically =>
            declare
               Temp : constant String :=
                 Available_Sibling_Path (Path, ".http_client_download_tmp");
            begin
               if Temp'Length = 0 then
                  Status := Http_Client.Errors.Write_Failed;
               else
                  Actual := To_Unbounded_String (Temp);
               end if;
            end;
      end case;
   exception
      when others =>
         Status := Http_Client.Errors.Write_Failed;
   end Prepare_Download_Target;

   procedure Cleanup_Download_Target
     (Actual_Path : String;
      Options     : Download_Options)
   is
   begin
      if not Options.Preserve_Partial_File
        and then Actual_Path'Length > 0
        and then Ada.Directories.Exists (Actual_Path)
      then
         Ada.Directories.Delete_File (Actual_Path);
      end if;
   exception
      when others =>
         null;
   end Cleanup_Download_Target;


   function Is_SHA256_Hex (Text : String) return Boolean is
   begin
      if Text'Length /= 64 then
         return False;
      end if;

      for Ch of Text loop
         if not ((Ch >= '0' and then Ch <= '9')
                 or else (Ch >= 'a' and then Ch <= 'f')
                 or else (Ch >= 'A' and then Ch <= 'F'))
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_SHA256_Hex;


   function Report_Download_Progress
     (Options       : Download_Options;
      Bytes_Written : Natural;
      Total_Bytes   : Natural) return Http_Client.Errors.Result_Status
   is
   begin
      if Options.Progress_Callback = null then
         return Http_Client.Errors.Ok;
      end if;

      return Options.Progress_Callback.all
        (Bytes_Written => Bytes_Written,
         Total_Bytes   => Total_Bytes);
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Report_Download_Progress;

   function Verify_Download_Integrity
     (Path       : String;
      Final_Size : Natural;
      Options    : Download_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if Options.Expected_Size > 0 and then Final_Size /= Options.Expected_Size then
         return Http_Client.Errors.Integrity_Check_Failed;
      end if;

      if Options.Verify_SHA256 then
         if not Is_SHA256_Hex (Options.Expected_SHA256_Hex) then
            return Http_Client.Errors.Invalid_Configuration;
         end if;

         declare
            Expected : constant String :=
              Ada.Characters.Handling.To_Lower (Options.Expected_SHA256_Hex);
            Actual   : constant String :=
              Http_Client.Crypto.Digest_File_SHA256_Hex (Path);
         begin
            if Actual'Length /= 64 then
               return Http_Client.Errors.Read_Failed;
            end if;

            if Actual /= Expected then
               return Http_Client.Errors.Integrity_Check_Failed;
            end if;
         end;
      end if;

      return Http_Client.Errors.Ok;
   end Verify_Download_Integrity;

   function Install_Download_Target
     (Actual_Path : String;
      Final_Path  : String;
      Options     : Download_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if Options.File_Mode /= Replace_Atomically then
         return Http_Client.Errors.Ok;
      end if;

      return Install_File_Atomically
        (Source_Path        => Actual_Path,
         Target_Path        => Final_Path,
         Backup_Suffix      => ".http_client_download_old",
         Create_Parent_Dirs => False,
         Durability         => Options.Durability);
   end Install_Download_Target;

   function Execute_To_File
     (Item    : in out Client;
      Request : Http_Client.Requests.Request;
      Path    : String;
      Result  : out Download_Result;
      Options : Download_Options := Default_Download_Options)
      return Http_Client.Errors.Result_Status
   is
      Working_Client    : Client := Item;
      Effective_Request : Http_Client.Requests.Request := Request;
      Stream            : Http_Client.Response_Streams.Streaming_Response;
      Status            : Http_Client.Errors.Result_Status;
      Close_Status      : Http_Client.Errors.Result_Status;
      File              : Ada.Streams.Stream_IO.File_Type;
      Buffer         : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Options.Buffer_Size));
      Last           : Ada.Streams.Stream_Element_Offset;
      Count          : Natural;
      Written        : Natural := 0;
      Actual_Path    : Ada.Strings.Unbounded.Unbounded_String;
      Final_Path     : Ada.Strings.Unbounded.Unbounded_String;
      Prepared       : Boolean := False;
      Opened_Stream   : Boolean := False;
      Opened_File    : Boolean := False;
      Resume_Offset  : Natural := 0;
      Resume_Attempted : Boolean := False;
      Resume_Offset_Too_Large : Boolean := False;
      Resume_Active  : Boolean := False;
      Content_Range_Last_Byte  : Natural := 0;
      Content_Range_Final_Size : Natural := 0;
      Content_Length_Body_Size : Natural := 0;
      Total_Size     : Natural := 0;
      Last_Progress_Bytes : Natural := 0;
      Progress_Reported   : Boolean := False;
      Effective_Download_Limit : constant Natural :=
        (if Options.Max_Download_Size = 0
         then Natural'Last
         else Options.Max_Download_Size);
   begin
      Result :=
        (Status        => Http_Client.Errors.Internal_Error,
         Response      => Http_Client.Responses.Default_Response,
         Final_URI     => Http_Client.URI.Create_Unchecked (""),
         HTTP_Status_Code    => 0,
         Expected_Final_Size => 0,
         Redirect_Count      => 0,
         Retry_Attempt_Count => 0,
         Resumed             => False,
         Resume_Offset       => 0,
         Bytes_Written       => 0,
         Final_Size          => 0);

      if not Http_Client.Requests.Is_Valid (Request) then
         Result.Status := Http_Client.Errors.Invalid_Request;
         return Result.Status;
      end if;

      if not Working_Client.Initialized then
         Result.Status := Http_Client.Errors.Client_Not_Initialized;
         return Result.Status;
      end if;

      if Options.Cancellation /= null
        and then Http_Client.Cancellation.Is_Cancelled (Options.Cancellation.all)
      then
         Result.Status := Http_Client.Errors.Cancelled;
         return Result.Status;
      end if;

      Status := Preflight_Download_Target (Path, Options);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      if Options.Expected_Size > 0
        and then Options.Max_Download_Size > 0
        and then Options.Expected_Size > Options.Max_Download_Size
      then
         Result.Status := Http_Client.Errors.Response_Too_Large;
         Result.Expected_Final_Size := Options.Expected_Size;
         return Result.Status;
      end if;

      if Options.Verify_SHA256 and then not Is_SHA256_Hex (Options.Expected_SHA256_Hex) then
         Result.Status := Http_Client.Errors.Invalid_Configuration;
         return Result.Status;
      end if;

      Working_Client.Config.Redirects.Follow_Redirects := Options.Follow_Redirects;
      Working_Client.Config.Redirects.Max_Redirects := Options.Max_Redirects;

      --  Execute_Stream still validates and enforces its own streaming body
      --  bound. For file downloads that bound must be the separate download
      --  limit, not the in-memory buffered Max_Body_Size.
      Working_Client.Config.Execution.Max_Body_Size := Effective_Download_Limit;
      if Options.Cancellation /= null then
         Working_Client.Config.Execution.Cancellation := Options.Cancellation;
      end if;
      if Working_Client.Config.Execution.Max_Response_Size < Effective_Download_Limit then
         Working_Client.Config.Execution.Max_Response_Size := Effective_Download_Limit;
      end if;

      if Options.Enable_Resume
        and then Options.File_Mode = Overwrite
        and then Http_Client.Requests.Method (Request) = Http_Client.Types.GET
        and then not Http_Client.Requests.Has_Payload (Request)
      then
         declare
            Headers : Http_Client.Headers.Header_List :=
              Http_Client.Requests.Headers (Request);
         begin
            if not Http_Client.Headers.Contains (Headers, "Range") then
               Existing_File_Size
                 (Path      => Path,
                  Value     => Resume_Offset,
                  Too_Large => Resume_Offset_Too_Large);

               if Resume_Offset_Too_Large then
                  Result.Final_URI := Http_Client.Requests.URI (Request);
                  Result.Resumed := True;
                  Result.Resume_Offset := Natural'Last;
                  Result.Expected_Final_Size := Options.Expected_Size;
                  Result.Bytes_Written := 0;
                  Result.Final_Size := Natural'Last;
                  Result.Status := Http_Client.Errors.Response_Too_Large;
                  return Result.Status;
               end if;

               if Resume_Offset > 0 then
                  if Options.Max_Download_Size > 0
                    and then Resume_Offset > Options.Max_Download_Size
                  then
                     Result.Final_URI := Http_Client.Requests.URI (Request);
                     Result.Resumed := True;
                     Result.Resume_Offset := Resume_Offset;
                     Result.Expected_Final_Size := Options.Expected_Size;
                     Result.Bytes_Written := 0;
                     Result.Final_Size := Resume_Offset;
                     Result.Status := Http_Client.Errors.Response_Too_Large;
                     return Result.Status;
                  end if;

                  if Options.Expected_Size > 0
                    and then Resume_Offset > Options.Expected_Size
                  then
                     Result.Final_URI := Http_Client.Requests.URI (Request);
                     Result.Resumed := True;
                     Result.Resume_Offset := Resume_Offset;
                     Result.Expected_Final_Size := Options.Expected_Size;
                     Result.Bytes_Written := 0;
                     Result.Final_Size := Resume_Offset;
                     Result.Status := Http_Client.Errors.Integrity_Check_Failed;
                     return Result.Status;
                  end if;

                  if Options.Expected_Size > 0
                    and then Resume_Offset = Options.Expected_Size
                  then
                     Result.Final_URI := Http_Client.Requests.URI (Request);
                     Result.Resumed := True;
                     Result.Resume_Offset := Resume_Offset;
                     Result.Expected_Final_Size := Options.Expected_Size;
                     Result.Bytes_Written := 0;
                     Result.Final_Size := Resume_Offset;

                     if Options.Max_Download_Size > 0
                       and then Resume_Offset > Options.Max_Download_Size
                     then
                        Result.Status := Http_Client.Errors.Response_Too_Large;
                        return Result.Status;
                     end if;

                     Status := Verify_Download_Integrity
                       (Path       => Path,
                        Final_Size => Resume_Offset,
                        Options    => Options);
                     if Status /= Http_Client.Errors.Ok then
                        Result.Status := Status;
                        return Result.Status;
                     end if;

                     Status := Report_Download_Progress
                       (Options       => Options,
                        Bytes_Written => Resume_Offset,
                        Total_Bytes   => Options.Expected_Size);
                     if Status /= Http_Client.Errors.Ok then
                        Result.Status := Status;
                        return Result.Status;
                     end if;

                     Result.Status := Http_Client.Errors.Ok;
                     return Http_Client.Errors.Ok;
                  end if;

                  Status :=
                    Http_Client.Headers.Set
                      (Headers,
                       "Range",
                       "bytes=" & Decimal_Image (Resume_Offset) & "-");
                  if Status /= Http_Client.Errors.Ok then
                     Result.Status := Status;
                     return Status;
                  end if;

                  if Length (Options.Resume_If_Range) > 0 then
                     Status :=
                       Http_Client.Headers.Set
                         (Headers,
                          "If-Range",
                          To_String (Options.Resume_If_Range));
                     if Status /= Http_Client.Errors.Ok then
                        Result.Status := Status;
                        return Status;
                     end if;
                  end if;

                  Status :=
                    Http_Client.Requests.Create
                      (Method    => Http_Client.Types.GET,
                       URI       => Http_Client.Requests.URI (Request),
                       Item      => Effective_Request,
                       Headers   => Headers,
                       Payload   => "",
                       Auto_Host => False);
                  if Status /= Http_Client.Errors.Ok then
                     Result.Status := Status;
                     return Status;
                  end if;

                  Resume_Attempted := True;
               end if;
            end if;
         end;
      end if;

      Status := Execute_Stream
        (Item    => Working_Client,
         Request => Effective_Request,
         Stream  => Stream);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;
      Opened_Stream := True;

      Result.Response := Http_Client.Response_Streams.Metadata (Stream);
      Result.Final_URI := Http_Client.Response_Streams.Effective_URI (Stream);
      Result.HTTP_Status_Code :=
        Natural (Http_Client.Response_Streams.Status_Code (Stream));
      Result.Redirect_Count :=
        Http_Client.Response_Streams.Redirect_Count (Stream);
      Result.Retry_Attempt_Count :=
        Http_Client.Response_Streams.Retry_Attempt_Count (Stream);

      if Resume_Attempted then
         declare
            Code : constant Http_Client.Types.Status_Code :=
              Http_Client.Response_Streams.Status_Code (Stream);
         begin
            if Code = 206 then
               declare
                  Start : Natural;
                  Raw   : constant String :=
                    Http_Client.Headers.Get
                      (Http_Client.Response_Streams.Headers (Stream),
                       "Content-Range");
               begin
                  if not Parse_Content_Range
                    (Raw, Start, Content_Range_Last_Byte, Content_Range_Final_Size)
                    or else Start /= Resume_Offset
                  then
                     Close_Status := Http_Client.Response_Streams.Close (Stream);
                     if Close_Status /= Http_Client.Errors.Ok then
                        null;
                     end if;
                     Result.Status := Http_Client.Errors.Protocol_Error;
                     Result.Final_Size := Resume_Offset;
                     return Result.Status;
                  end if;

                  Resume_Active := True;
                  Result.Resumed := True;
                  Result.Resume_Offset := Resume_Offset;
               end;
            elsif Code = 200 then
               Resume_Offset := 0;
            elsif Code = 416 then
               declare
                  Existing_Final_Size : Natural := 0;
                  Ignored_Length      : Natural := 0;
                  Raw                 : constant String :=
                    Http_Client.Headers.Get
                      (Http_Client.Response_Streams.Headers (Stream),
                       "Content-Range");
               begin
                  Status := Content_Length_Value
                    (Http_Client.Response_Streams.Headers (Stream), Ignored_Length);
                  if Status /= Http_Client.Errors.Ok then
                     Close_Status := Http_Client.Response_Streams.Close (Stream);
                     if Close_Status /= Http_Client.Errors.Ok then
                        null;
                     end if;
                     Result.Status := Status;
                     Result.Final_Size := Resume_Offset;
                     return Result.Status;
                  end if;

                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     Result.Status := Close_Status;
                     Result.Final_Size := Resume_Offset;
                     return Result.Status;
                  end if;

                  if not Parse_Unsatisfied_Content_Range
                    (Raw, Existing_Final_Size)
                    or else Existing_Final_Size /= Resume_Offset
                  then
                     Result.Status := Http_Client.Errors.Protocol_Error;
                     Result.Final_Size := Resume_Offset;
                     return Result.Status;
                  end if;

                  Result.Resumed := True;
                  Result.Resume_Offset := Resume_Offset;
                  Result.Expected_Final_Size := Existing_Final_Size;
                  Result.Bytes_Written := 0;
                  Result.Final_Size := Resume_Offset;

                  if Options.Max_Download_Size > 0
                    and then Resume_Offset > Options.Max_Download_Size
                  then
                     Result.Status := Http_Client.Errors.Response_Too_Large;
                     return Result.Status;
                  end if;

                  Status := Verify_Download_Integrity
                    (Path       => Path,
                     Final_Size => Resume_Offset,
                     Options    => Options);
                  if Status /= Http_Client.Errors.Ok then
                     Result.Status := Status;
                     return Result.Status;
                  end if;

                  Status := Report_Download_Progress
                    (Options       => Options,
                     Bytes_Written => Resume_Offset,
                     Total_Bytes   => Existing_Final_Size);
                  if Status /= Http_Client.Errors.Ok then
                     Result.Status := Status;
                     return Result.Status;
                  end if;

                  Result.Status := Http_Client.Errors.Ok;
                  return Http_Client.Errors.Ok;
               end;
            else
               Close_Status := Http_Client.Response_Streams.Close (Stream);
               if Close_Status /= Http_Client.Errors.Ok then
                  null;
               end if;
               Result.Status := Http_Client.Errors.Protocol_Error;
               Result.Final_Size := Resume_Offset;
               return Result.Status;
            end if;
         end;
      end if;

      declare
         Length : Natural := 0;
      begin
         Status := Content_Length_Value
           (Http_Client.Response_Streams.Headers (Stream), Length);
         if Status /= Http_Client.Errors.Ok then
            Close_Status := Http_Client.Response_Streams.Close (Stream);
            if Close_Status /= Http_Client.Errors.Ok then
               null;
            end if;
            Result.Status := Status;
            Result.Final_Size := Resume_Offset;
            return Result.Status;
         end if;

         if Length > 0 then
            declare
               Combined_Size : Natural := 0;
            begin
               if not Natural_Sum (Resume_Offset, Length, Combined_Size) then
                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     null;
                  end if;
                  Result.Status := Http_Client.Errors.Response_Too_Large;
                  Result.Final_Size := Resume_Offset;
                  return Result.Status;
               end if;

               if Resume_Active and then Content_Range_Final_Size > 0 then
                  Total_Size := Content_Range_Final_Size;
               else
                  Total_Size := Combined_Size;
               end if;
            end;
         elsif Resume_Active and then Content_Range_Final_Size > 0 then
            Total_Size := Content_Range_Final_Size;
         elsif Options.Expected_Size > 0 then
            Total_Size := Options.Expected_Size;
         end if;

         Result.Expected_Final_Size := Total_Size;
         if not Working_Client.Config.Enable_Decompression then
            Content_Length_Body_Size := Length;
         end if;

         if Resume_Active and then Length > 0 then
            declare
               Expected_End : Natural := 0;
            begin
               if not Natural_Sum (Resume_Offset, Length, Expected_End) then
                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     null;
                  end if;
                  Result.Status := Http_Client.Errors.Response_Too_Large;
                  Result.Final_Size := Resume_Offset;
                  return Result.Status;
               elsif Content_Range_Last_Byte = Natural'Last
                 or else Content_Range_Last_Byte + 1 /= Expected_End
               then
                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     null;
                  end if;
                  Result.Status := Http_Client.Errors.Protocol_Error;
                  Result.Final_Size := Resume_Offset;
                  return Result.Status;
               end if;
            end;
         end if;

         if Options.Require_Success_Status
           and then
             (Http_Client.Response_Streams.Status_Code (Stream) < 200
              or else Http_Client.Response_Streams.Status_Code (Stream) > 299)
         then
            Close_Status := Http_Client.Response_Streams.Close (Stream);
            if Close_Status /= Http_Client.Errors.Ok then
               null;
            end if;
            Result.Status := Http_Client.Errors.Protocol_Error;
            return Result.Status;
         end if;

         if Options.Expected_Size > 0
           and then Total_Size > 0
           and then Total_Size /= Options.Expected_Size
         then
            Close_Status := Http_Client.Response_Streams.Close (Stream);
            if Close_Status /= Http_Client.Errors.Ok then
               null;
            end if;
            Result.Status := Http_Client.Errors.Integrity_Check_Failed;
            Result.Final_Size := Resume_Offset;
            return Result.Status;
         end if;

         if Options.Max_Download_Size > 0
           and then
             (Resume_Offset >= Options.Max_Download_Size
              or else (Length > 0
                       and then Length > Options.Max_Download_Size - Resume_Offset)
              or else (Length = 0
                       and then Total_Size > 0
                       and then Total_Size > Options.Max_Download_Size))
         then
            Close_Status := Http_Client.Response_Streams.Close (Stream);
            if Close_Status /= Http_Client.Errors.Ok then
               null;
            end if;
            Result.Status := Http_Client.Errors.Response_Too_Large;
            Result.Final_Size := Resume_Offset;
            return Result.Status;
         end if;
      end;

      Prepare_Download_Target
        (Path       => Path,
         Options    => Options,
         Actual     => Actual_Path,
         Final_Path => Final_Path,
         Status     => Status);
      if Status /= Http_Client.Errors.Ok then
         Close_Status := Http_Client.Response_Streams.Close (Stream);
         if Close_Status /= Http_Client.Errors.Ok then
            null;
         end if;
         Result.Status := Status;
         return Status;
      end if;
      Prepared := True;

      if Resume_Active then
         Ada.Streams.Stream_IO.Open
           (File => File,
            Mode => Ada.Streams.Stream_IO.Append_File,
            Name => To_String (Actual_Path));
      else
         Ada.Streams.Stream_IO.Create
           (File => File,
            Mode => Ada.Streams.Stream_IO.Out_File,
            Name => To_String (Actual_Path));
      end if;
      Opened_File := True;
      Last_Progress_Bytes := Resume_Offset;

      loop
         Status := Http_Client.Response_Streams.Read_Some
           (Stream => Stream,
            Buffer => Buffer,
            Last   => Last);

         exit when Status = Http_Client.Errors.End_Of_Stream;

         if Status /= Http_Client.Errors.Ok then
            if Opened_File then
               Ada.Streams.Stream_IO.Close (File);
               Opened_File := False;
            end if;
            Close_Status := Http_Client.Response_Streams.Close (Stream);
            if Close_Status /= Http_Client.Errors.Ok then
               null;
            end if;
            Cleanup_Download_Target (To_String (Actual_Path), Options);
            Result.Status := Status;
            Result.Bytes_Written := Written;
            Result.Final_Size := Resume_Offset + Written;
            return Status;
         end if;

         if Last >= Buffer'First then
            Count := Natural (Last - Buffer'First + 1);
            declare
               Current_Size : Natural := 0;
               New_Size     : Natural := 0;
            begin
               if not Natural_Sum (Resume_Offset, Written, Current_Size)
                 or else not Natural_Sum (Current_Size, Count, New_Size)
                 or else
                   (Options.Max_Download_Size > 0
                    and then
                      (Current_Size >= Options.Max_Download_Size
                       or else Count > Options.Max_Download_Size - Current_Size))
               then
                  Ada.Streams.Stream_IO.Close (File);
                  Opened_File := False;
                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     null;
                  end if;
                  Cleanup_Download_Target (To_String (Actual_Path), Options);
                  Result.Status := Http_Client.Errors.Response_Too_Large;
                  Result.Bytes_Written := Written;
                  Result.Final_Size := Current_Size;
                  return Result.Status;
               end if;
            end;

            Ada.Streams.Stream_IO.Write (File, Buffer (Buffer'First .. Last));
            Written := Written + Count;

            if Options.Progress_Callback /= null
              and then
                (Options.Progress_Interval_Bytes = 0
                 or else Resume_Offset + Written - Last_Progress_Bytes
                         >= Options.Progress_Interval_Bytes)
            then
               Status :=
                 Report_Download_Progress
                   (Options       => Options,
                    Bytes_Written => Resume_Offset + Written,
                    Total_Bytes   => Total_Size);
               if Status /= Http_Client.Errors.Ok then
                  Ada.Streams.Stream_IO.Close (File);
                  Opened_File := False;
                  Close_Status := Http_Client.Response_Streams.Close (Stream);
                  if Close_Status /= Http_Client.Errors.Ok then
                     null;
                  end if;
                  Cleanup_Download_Target (To_String (Actual_Path), Options);
                  Result.Status := Status;
                  Result.Bytes_Written := Written;
                  Result.Final_Size := Resume_Offset + Written;
                  return Status;
               end if;

               Last_Progress_Bytes := Resume_Offset + Written;
               Progress_Reported := True;
            end if;
         end if;
      end loop;

      Ada.Streams.Stream_IO.Close (File);
      Opened_File := False;
      Close_Status := Http_Client.Response_Streams.Close (Stream);
      Opened_Stream := False;
      if Close_Status /= Http_Client.Errors.Ok then
         Cleanup_Download_Target (To_String (Actual_Path), Options);
         Result.Status := Close_Status;
         Result.Bytes_Written := Written;
         Result.Final_Size := Resume_Offset + Written;
         return Close_Status;
      end if;

      if Resume_Active then
         declare
            Expected_End : Natural := 0;
            Actual_End   : Natural := 0;
         begin
            if not Natural_Sum (Content_Range_Last_Byte, 1, Expected_End)
              or else not Natural_Sum (Resume_Offset, Written, Actual_End)
            then
               Cleanup_Download_Target (To_String (Actual_Path), Options);
               Result.Status := Http_Client.Errors.Response_Too_Large;
               Result.Bytes_Written := Written;
               Result.Final_Size := Natural'Last;
               return Result.Status;
            elsif Expected_End /= Actual_End then
               Cleanup_Download_Target (To_String (Actual_Path), Options);
               Result.Status := Http_Client.Errors.Protocol_Error;
               Result.Bytes_Written := Written;
               Result.Final_Size := Actual_End;
               return Result.Status;
            end if;
         end;
      end if;

      if not Resume_Active
        and then Content_Length_Body_Size > 0
        and then Written /= Content_Length_Body_Size
      then
         Cleanup_Download_Target (To_String (Actual_Path), Options);
         Result.Status :=
           (if Written < Content_Length_Body_Size
            then Http_Client.Errors.Incomplete_Message
            else Http_Client.Errors.Protocol_Error);
         Result.Bytes_Written := Written;
         Result.Final_Size := Resume_Offset + Written;
         return Result.Status;
      end if;

      if Options.Progress_Callback /= null
        and then
          ((not Progress_Reported)
           or else Last_Progress_Bytes < Resume_Offset + Written)
      then
         Status :=
           Report_Download_Progress
             (Options       => Options,
              Bytes_Written => Resume_Offset + Written,
              Total_Bytes   => Total_Size);
         if Status /= Http_Client.Errors.Ok then
            Cleanup_Download_Target (To_String (Actual_Path), Options);
            Result.Status := Status;
            Result.Bytes_Written := Written;
            Result.Final_Size := Resume_Offset + Written;
            return Status;
         end if;
      end if;

      Status := Verify_Download_Integrity
        (Path       => To_String (Actual_Path),
         Final_Size => Resume_Offset + Written,
         Options    => Options);
      if Status /= Http_Client.Errors.Ok then
         Cleanup_Download_Target (To_String (Actual_Path), Options);
         Result.Status := Status;
         Result.Bytes_Written := Written;
         Result.Final_Size := Resume_Offset + Written;
         return Status;
      end if;

      if Options.Durability = File_Durability_Sync_Data_And_Directory
        and then Options.File_Mode /= Replace_Atomically
      then
         if not Fsync_File (To_String (Actual_Path)) then
            Cleanup_Download_Target (To_String (Actual_Path), Options);
            Result.Status := Http_Client.Errors.Write_Failed;
            Result.Bytes_Written := Written;
            Result.Final_Size := Resume_Offset + Written;
            return Result.Status;
         end if;
         Fsync_Parent_Directory_Best_Effort (To_String (Final_Path));
      end if;

      Status := Install_Download_Target
        (Actual_Path => To_String (Actual_Path),
         Final_Path  => To_String (Final_Path),
         Options     => Options);
      if Status /= Http_Client.Errors.Ok then
         Cleanup_Download_Target (To_String (Actual_Path), Options);
         Result.Status := Status;
         Result.Bytes_Written := Written;
         Result.Final_Size := Resume_Offset + Written;
         return Status;
      end if;

      Result.Status := Http_Client.Errors.Ok;
      Result.Bytes_Written := Written;
      Result.Final_Size := Resume_Offset + Written;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         if Opened_File then
            begin
               Ada.Streams.Stream_IO.Close (File);
            exception
               when others =>
                  null;
            end;
         end if;
         if Opened_Stream then
            begin
               Close_Status := Http_Client.Response_Streams.Close (Stream);
            exception
               when others =>
                  null;
            end;
         end if;
         if Prepared then
            Cleanup_Download_Target (To_String (Actual_Path), Options);
         end if;
         Result.Status := Http_Client.Errors.Write_Failed;
         Result.Bytes_Written := Written;
         Result.Final_Size := Resume_Offset + Written;
         return Result.Status;
   end Execute_To_File;

   function Download_To_File
     (Item    : in out Client;
      URL     : String;
      Path    : String;
      Result  : out Download_Result;
      Options : Download_Options := Default_Download_Options)
      return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Result :=
        (Status        => Http_Client.Errors.Internal_Error,
         Response      => Http_Client.Responses.Default_Response,
         Final_URI     => Http_Client.URI.Create_Unchecked (""),
         HTTP_Status_Code    => 0,
         Expected_Final_Size => 0,
         Redirect_Count      => 0,
         Retry_Attempt_Count => 0,
         Resumed             => False,
         Resume_Offset       => 0,
         Bytes_Written       => 0,
         Final_Size          => 0);

      if not Item.Initialized then
         Result.Status := Http_Client.Errors.Client_Not_Initialized;
         return Result.Status;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.GET,
         URL          => URL,
         Payload      => "",
         Content_Type => "",
         Request      => Request);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      return Execute_To_File
        (Item    => Item,
         Request => Request,
         Path    => Path,
         Result  => Result,
         Options => Options);
   end Download_To_File;

   function Download_To_File
     (URL           : String;
      Path          : String;
      Result        : out Download_Result;
      Options       : Download_Options := Default_Download_Options;
      Configuration : Client_Configuration := Default_Client_Configuration)
      return Http_Client.Errors.Result_Status
   is
      Item   : Client;
      Status : Http_Client.Errors.Result_Status;
   begin
      Result :=
        (Status        => Http_Client.Errors.Internal_Error,
         Response      => Http_Client.Responses.Default_Response,
         Final_URI     => Http_Client.URI.Create_Unchecked (""),
         HTTP_Status_Code    => 0,
         Expected_Final_Size => 0,
         Redirect_Count      => 0,
         Retry_Attempt_Count => 0,
         Resumed             => False,
         Resume_Offset       => 0,
         Bytes_Written       => 0,
         Final_Size          => 0);

      Status := Initialize (Item, Configuration);
      if Status /= Http_Client.Errors.Ok then
         Result.Status := Status;
         return Status;
      end if;

      return Download_To_File
        (Item    => Item,
         URL     => URL,
         Path    => Path,
         Result  => Result,
         Options => Options);
   end Download_To_File;

   function Delete
     (Item   : Client;
      URL    : String;
      Result : out Client_Result) return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Reject_Uninitialized_Client (Item, Result) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.DELETE,
         URL          => URL,
         Payload      => "",
         Content_Type => "",
         Request      => Request);

      if Status /= Http_Client.Errors.Ok then
         Reset_Client_Result (Result);
         Result.Status := Status;
         return Status;
      end if;

      return Execute (Item, Request, Result);
   end Delete;

   function Put
     (Item         : Client;
      URL          : String;
      Payload      : String;
      Result       : out Client_Result;
      Content_Type : String := "") return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Reject_Uninitialized_Client (Item, Result) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.PUT,
         URL          => URL,
         Payload      => Payload,
         Content_Type => Content_Type,
         Request      => Request);

      if Status /= Http_Client.Errors.Ok then
         Reset_Client_Result (Result);
         Result.Status := Status;
         return Status;
      end if;

      return Execute (Item, Request, Result);
   end Put;

   function Post
     (Item         : Client;
      URL          : String;
      Payload      : String;
      Result       : out Client_Result;
      Content_Type : String := "") return Http_Client.Errors.Result_Status
   is
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Reject_Uninitialized_Client (Item, Result) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Status := Build_Simple_Request
        (Method       => Http_Client.Types.POST,
         URL          => URL,
         Payload      => Payload,
         Content_Type => Content_Type,
         Request      => Request);

      if Status /= Http_Client.Errors.Ok then
         Reset_Client_Result (Result);
         Result.Status := Status;
         return Status;
      end if;

      return Execute (Item, Request, Result);
   end Post;

   function Response_Text (Result : Client_Result) return String is
   begin
      if Result.Used_Decoded_View then
         return Http_Client.Decompression.Decoded_Body
           (Result.Decoded_Response);
      else
         return Http_Client.Responses.Response_Body
           (Result.Response);
      end if;
   end Response_Text;

   function Final_URL (Result : Client_Result) return String is
   begin
      return Http_Client.URI.Image (Result.Final_URI);
   end Final_URL;

end Http_Client.Clients;
