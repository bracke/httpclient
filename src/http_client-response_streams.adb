with Ada.Calendar;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Http_Client.Cancellation;
with Http_Client.Cookies; use Http_Client.Cookies;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.HTTP2;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.Response_Streams.HTTP2_IO;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Execution;
with Http_Client.Proxies; use Http_Client.Proxies;
with Http_Client.Request_Bodies;
with Http_Client.Resources;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Transports.SOCKS;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Zlib_Decompression;

package body Http_Client.Response_Streams is
   package H2_Common renames Http_Client.HTTP2_Execution_Common;
   package H2_IO renames Http_Client.Response_Streams.HTTP2_IO;
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Diagnostics.Protocol_Version;
   use type Http_Client.Cancellation.Cancellation_Token_Access;
   use type Http_Client.HTTP1.Request_Target_Mode;
   use type Http_Client.HTTP2.Selected_Protocol;
   use type Http_Client.HTTP2.HTTP2_Mode;
   use type Http_Client.HTTP2.Frames.Frame_Type;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;
   use type Http_Client.Request_Bodies.Body_Kind;
   use type Http_Client.Diagnostics.Context_Access;
   use type Http_Client.Diagnostics.Event_Kind;
   use type Http_Client.Decompression.Unsupported_Encoding_Policy;
   use type Http_Client.Decompression.Deflate_Decoding_Mode;


   CR : constant Character := Character'Val (13);
   LF : constant Character := Character'Val (10);
   HT : constant Character := Character'Val (9);
   CRLFCRLF : constant String := CR & LF & CR & LF;


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

   function H2_Has_Flag (Flags : Natural; Mask : Natural) return Boolean
      renames H2_Common.Has_Flag;

   function H2_Serialize_Frame
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String
      renames H2_Common.Serialize_Frame;

   function H2_Window_Update
     (Stream    : Natural;
      Increment : Natural) return String
      renames H2_Common.Serialize_Window_Update;

   function Diagnostics_Active (Options : Streaming_Options) return Boolean is
   begin
      return Options.Diagnostics /= null
        and then Http_Client.Diagnostics.Is_Enabled (Options.Diagnostics.all);
   end Diagnostics_Active;

   function Emit_Diagnostic
     (Options : Streaming_Options;
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

   function Emit_Stream_Diagnostic
     (Stream : in out Streaming_Response;
      Event  : Http_Client.Diagnostics.Diagnostic_Event)
      return Http_Client.Errors.Result_Status
   is
      Delivered : Http_Client.Diagnostics.Diagnostic_Event := Event;
   begin
      if Stream.Diagnostics = null
        or else not Http_Client.Diagnostics.Is_Enabled (Stream.Diagnostics.all)
      then
         return Http_Client.Errors.Ok;
      end if;

      Delivered.Request_ID := Stream.Request_ID;
      Delivered.Connection_ID := Stream.Connection_ID;
      if Delivered.Protocol = Http_Client.Diagnostics.Protocol_Unknown then
         Delivered.Protocol := Stream.Diagnostic_Protocol;
      end if;
      if Delivered.Kind = Http_Client.Diagnostics.Request_Finish
        or else Delivered.Kind = Http_Client.Diagnostics.Streaming_Response_Closed
      then
         Delivered.Status_Code :=
           (if Stream.Had_Response
            then Natural (Http_Client.Responses.Status_Code (Stream.Meta))
            else 0);
         Delivered.Redirect_Count := Stream.Redirects_Followed;
         Delivered.Retry_Attempt := Stream.Retry_Attempts;
         Delivered.Elapsed_Milliseconds :=
           Http_Client.Diagnostics.Elapsed_Milliseconds
             (Stream.Diagnostics.all,
              Stream.Request_Start_Time,
              Http_Client.Diagnostics.Now (Stream.Diagnostics.all));
      end if;
      return Http_Client.Diagnostics.Emit (Stream.Diagnostics.all, Delivered);
   end Emit_Stream_Diagnostic;

   function Check_Cancelled
     (Token : Http_Client.Cancellation.Cancellation_Token_Access)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Token /= null and then Http_Client.Cancellation.Is_Cancelled (Token.all) then
         return Http_Client.Errors.Cancelled;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Check_Cancelled;

   function Configure_Decompression
     (Stream  : in out Streaming_Response;
      Options : Streaming_Options) return Http_Client.Errors.Result_Status;

   function Cancel_Stream
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status
   is
      Ignored : Http_Client.Errors.Result_Status;
      pragma Unreferenced (Ignored);
   begin
      Stream.Failed := True;
      Stream.Finished := False;
      Stream.Last_Result := Http_Client.Errors.Cancelled;
      if Stream.Opened then
         Ignored := Close (Stream);
      end if;
      return Http_Client.Errors.Cancelled;
   end Cancel_Stream;

   function Lower (Text : String) return String is
      Result : String := Text;
   begin
      for Index in Result'Range loop
         if Result (Index) in 'A' .. 'Z' then
            Result (Index) := Character'Val
              (Character'Pos (Result (Index)) - Character'Pos ('A') + Character'Pos ('a'));
         end if;
      end loop;
      return Result;
   end Lower;

   function Trim_OWS (Text : String) return String is
      First : Integer := Text'First;
      Last  : Integer := Text'Last;
   begin
      if Text'Length = 0 then
         return "";
      end if;
      while First <= Text'Last and then (Text (First) = ' ' or else Text (First) = HT) loop
         First := First + 1;
      end loop;
      while Last >= First and then (Text (Last) = ' ' or else Text (Last) = HT) loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return "";
      end if;
      return Text (First .. Last);
   end Trim_OWS;

   function Parse_Natural_Strict (Text : String; Value : out Natural) return Boolean
      renames H2_Common.Parse_Natural;

   subtype H2_Peer_Settings is H2_Common.Peer_Settings;

   function H2_Parse_Peer_Settings
     (Payload : String;
      Peer    : in out H2_Peer_Settings) return Http_Client.Errors.Result_Status
      renames H2_Common.Parse_Peer_Settings;

   function H2_Encoded_Header_List_Size
     (Headers : Http_Client.Headers.Header_List;
      Size    : out Natural) return Boolean
      renames H2_Common.Encoded_Header_List_Size;

   function H2_Response_Body_Is_Disallowed
     (Request_Method : Http_Client.Types.Method_Name;
      Code           : Http_Client.Types.Status_Code) return Boolean
      renames H2_Common.Response_Body_Is_Disallowed;

   function H2_Ensure_Content_Length_Header
     (Headers     : in out Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
      renames H2_Common.Ensure_Content_Length_Header;

   function H2_Request_Content_Length_Is_Valid
     (Headers     : Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
      renames H2_Common.Request_Content_Length_Is_Valid;

   function H2_Read_Frame
     (Stream : in out Streaming_Response;
      Frame  : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
      renames H2_IO.Read_Frame;

   function H2_Try_Read_Frame
     (Stream     : in out Streaming_Response;
      Timeout_MS : Http_Client.Transports.TCP.Timeout_Milliseconds;
      Frame      : out Http_Client.HTTP2.Frames.Frame;
      Got_Frame  : out Boolean) return Http_Client.Errors.Result_Status
      renames H2_IO.Try_Read_Frame;

   function H2_Handle_Settings_Frame
     (Stream                     : in out Streaming_Response;
      Frame                      : Http_Client.HTTP2.Frames.Frame;
      Peer                       : in out H2_Peer_Settings;
      Update_Read_Max_Frame_Size : Boolean := False)
      return Http_Client.Errors.Result_Status
      renames H2_IO.Handle_Settings_Frame;

   function H2_Handle_Ping_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
      renames H2_IO.Handle_Ping_Frame;

   function H2_Window_Update_Increment
     (Frame     : Http_Client.HTTP2.Frames.Frame;
      Increment : out Natural) return Http_Client.Errors.Result_Status
      renames H2_IO.Window_Update_Increment;

   function H2_Validate_Data_Frame
     (Stream : Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
      renames H2_IO.Validate_Data_Frame;

   function H2_Consume_Data_Payload
     (Stream         : in out Streaming_Response;
      Payload_Length : Natural) return Http_Client.Errors.Result_Status
      renames H2_IO.Consume_Data_Payload;

   function H2_Complete_Data_End_Stream
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status
      renames H2_IO.Complete_Data_End_Stream;

   function H2_Validate_Trailer_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
      renames H2_IO.Validate_Trailer_Frame;

   function H2_Terminal_Frame_Status
     (Stream           : Streaming_Response;
      Frame            : Http_Client.HTTP2.Frames.Frame;
      Data_Is_Protocol : Boolean := False) return Http_Client.Errors.Result_Status
      renames H2_IO.Terminal_Frame_Status;

   function H2_Handle_Response_Header_Block_Frame
     (Stream               : in out Streaming_Response;
      Frame                : Http_Client.HTTP2.Frames.Frame;
      Max_Header_List_Size : Natural;
      Header_Block         : in out Unbounded_String;
      End_Stream           : in out Boolean;
      Headers              : out Http_Client.Headers.Header_List;
      Complete             : out Boolean) return Http_Client.Errors.Result_Status
      renames H2_IO.Handle_Response_Header_Block_Frame;

   function H2_Configure_Response_Metadata
     (Stream  : in out Streaming_Response;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List;
      Options : Streaming_Options) return Http_Client.Errors.Result_Status
   is
      Code      : Http_Client.Types.Status_Code;
      Status    : Http_Client.Errors.Result_Status;
      Response_Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      CL        : Natural := 0;
   begin
      Status := Http_Client.HTTP2.Mapping.Validate_Response_Headers (Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Mapping.Parse_Status (Headers, Code);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Stream.H2_Bodyless := H2_Response_Body_Is_Disallowed
        (Http_Client.Requests.Method (Request), Code);

      if Http_Client.Headers.Count (Headers, "content-length") > 1 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      elsif Http_Client.Headers.Contains (Headers, "content-length") then
         if not Parse_Natural_Strict
           (Http_Client.Headers.Get (Headers, "content-length"), CL)
         then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         elsif CL > Options.Max_Body_Size then
            return Http_Client.Errors.Response_Too_Large;
         end if;
         Stream.H2_Content_Length_Set := True;
         Stream.H2_Content_Length := CL;
      else
         Stream.H2_Content_Length_Set := False;
         Stream.H2_Content_Length := 0;
      end if;

      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         declare
            Name  : constant String := Http_Client.Headers.Name_At (Headers, I);
            Value : constant String := Http_Client.Headers.Value_At (Headers, I);
         begin
            if Name'Length > 0 and then Name (Name'First) = ':' then
               null;
            else
               Status := Http_Client.Headers.Add (Response_Headers, Name, Value);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;
         end;
      end loop;

      Stream.Meta := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => Code,
         Reason    => "",
         Headers   => Response_Headers,
         Body_Text => "");
      Stream.Mode := Fixed_Length;
      Stream.Remaining := 0;
      Stream.Max_Body := Options.Max_Body_Size;
      Stream.Read_Quantum := Options.Read_Buffer_Size;
      Stream.Body_Read := 0;
      Stream.Had_Response := True;
      Stream.Opened := True;
      Stream.Failed := False;
      Stream.Protocol := Protocol_HTTP_2;
      Stream.Diagnostic_Protocol := Http_Client.Diagnostics.Protocol_HTTP_2;
      Stream.Transport := TLS_Transport;
      Http_Client.Resources.Increment
        (Http_Client.Resources.Streaming_Responses_Open);

      Status := Configure_Decompression (Stream, Options);
      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Status;
            return Status;
         end;
      end if;

      if Stream.H2_Bodyless or else (Stream.H2_Content_Length_Set and then CL = 0) then
         null;
      end if;

      Stream.Last_Result := Http_Client.Errors.Ok;
      return Http_Client.Errors.Ok;
   end H2_Configure_Response_Metadata;


   function H2_Write_Request_Body
     (Stream      : in out Streaming_Response;
      Request     : Http_Client.Requests.Request;
      B           : Http_Client.Request_Bodies.Request_Body;
      Options     : Streaming_Options;
      Peer        : H2_Peer_Settings;
      Trailers    : Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Kind            : constant Http_Client.Request_Bodies.Body_Kind :=
        Http_Client.Request_Bodies.Kind (B);
      Declared_Length : Natural := 0;
      Has_Length      : constant Boolean :=
        Http_Client.Request_Bodies.Declared_Length (B, Declared_Length);
      Has_Trailers    : constant Boolean :=
        Http_Client.Request_Bodies.Has_Trailers (B);
      Sent            : Natural := 0;
      Count           : Natural := 0;
      Status          : Http_Client.Errors.Result_Status;
      Working_Peer      : H2_Peer_Settings := Peer;
      Conn_Send_Window   : Natural := 65_535;
      Stream_Send_Window : Natural := Working_Peer.Initial_Window_Size;
      Poll_Interval_Bytes : constant Natural := 262_144;
      Poll_Timeout_MS     : constant Http_Client.Transports.TCP.Timeout_Milliseconds := 1;
      Bytes_Since_Poll    : Natural := 0;
      Early_Header_Block : Unbounded_String := Null_Unbounded_String;
      Early_End_Stream_With_Headers : Boolean := False;

      function Send_Trailers return Http_Client.Errors.Result_Status is
      begin
         return Http_Client.Transports.TLS.Write_All
           (Stream.TLS_Conn,
            H2_Serialize_Frame
              (Http_Client.HTTP2.Frames.HEADERS, 16#05#, 1, To_String (Trailers)));
      end Send_Trailers;

      function Send_End_Stream return Http_Client.Errors.Result_Status is
      begin
         if Has_Trailers then
            return Send_Trailers;
         else
            return Http_Client.Transports.TLS.Write_All
              (Stream.TLS_Conn,
               H2_Serialize_Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, ""));
         end if;
      end Send_End_Stream;

      function Queue_Early_Response_Data
        (Payload    : String;
         End_Stream : Boolean) return Http_Client.Errors.Result_Status
      is
      begin
         Status := H2_Consume_Data_Payload (Stream, Payload'Length);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if Payload'Length > 0 then
            Append (Stream.Lookahead, Payload);
         end if;

         if End_Stream then
            Status := H2_Complete_Data_End_Stream (Stream);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
         end if;

         return Http_Client.Errors.Ok;
      end Queue_Early_Response_Data;

      function Handle_Early_Response_Frame
        (F : Http_Client.HTTP2.Frames.Frame) return Http_Client.Errors.Result_Status
      is
         Resp_Headers : Http_Client.Headers.Header_List;
         Headers_Complete : Boolean := False;
      begin
         if F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
            if F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif Stream.H2_Headers_Done then
               Status := H2_Validate_Trailer_Frame (Stream, F);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Stream.Finished := True;
               return Http_Client.Errors.Ok;
            else
               Status := H2_Handle_Response_Header_Block_Frame
                 (Stream, F, Options.TLS.HTTP2.Max_Header_List_Size,
                  Early_Header_Block, Early_End_Stream_With_Headers,
                  Resp_Headers, Headers_Complete);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               elsif Headers_Complete then
                  Status := H2_Configure_Response_Metadata
                    (Stream, Request, Resp_Headers, Options);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Stream.H2_Headers_Done := True;
                  Stream.Finished := Early_End_Stream_With_Headers;
               end if;
               return Http_Client.Errors.Ok;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION then
            if Stream.H2_Headers_Done then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            Status := H2_Handle_Response_Header_Block_Frame
              (Stream, F, Options.TLS.HTTP2.Max_Header_List_Size,
               Early_Header_Block, Early_End_Stream_With_Headers,
               Resp_Headers, Headers_Complete);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Headers_Complete then
               Status := H2_Configure_Response_Metadata
                 (Stream, Request, Resp_Headers, Options);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Stream.H2_Headers_Done := True;
               Stream.Finished := Early_End_Stream_With_Headers;
            end if;
            return Http_Client.Errors.Ok;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.DATA then
            Status := H2_Validate_Data_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
            return Queue_Early_Response_Data
              (To_String (F.Payload), H2_Has_Flag (F.Header.Flags, 16#01#));
         else
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
      end Handle_Early_Response_Frame;

      function Wait_For_Send_Window return Http_Client.Errors.Result_Status is
         F      : Http_Client.HTTP2.Frames.Frame;
         Window_Increment  : Natural := 0;
      begin
         while (Conn_Send_Window = 0 or else Stream_Send_Window = 0)
           and then not Stream.H2_Headers_Done loop
            Status := H2_Read_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

            if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
               Status := H2_Handle_Settings_Frame (Stream, F, Working_Peer);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

            elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
               Status := H2_Handle_Ping_Frame (Stream, F);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

            elsif F.Header.Kind = Http_Client.HTTP2.Frames.WINDOW_UPDATE then
               Status := H2_Window_Update_Increment (F, Window_Increment);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               elsif F.Header.Stream = 0 then
                  if Conn_Send_Window > Natural'Last - Window_Increment then
                     return Http_Client.Errors.HTTP2_Flow_Control_Error;
                  end if;
                  Conn_Send_Window := Conn_Send_Window + Window_Increment;
               elsif F.Header.Stream = 1 then
                  if Stream_Send_Window > Natural'Last - Window_Increment then
                     return Http_Client.Errors.HTTP2_Flow_Control_Error;
                  end if;
                  Stream_Send_Window := Stream_Send_Window + Window_Increment;
               else
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;

            elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM
              or else F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY
            then
               Status := H2_Terminal_Frame_Status (Stream, F);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS
              or else F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION
              or else F.Header.Kind = Http_Client.HTTP2.Frames.DATA
            then
               Status := Handle_Early_Response_Frame (F);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               elsif Stream.H2_Headers_Done then
                  return Http_Client.Errors.Ok;
               end if;
            else
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
         end loop;

         return Http_Client.Errors.Ok;
      end Wait_For_Send_Window;


      function Poll_For_Early_Response return Http_Client.Errors.Result_Status is
         F          : Http_Client.HTTP2.Frames.Frame;
         Got_Frame  : Boolean := False;
         Increment  : Natural := 0;
      begin
         Status := H2_Try_Read_Frame (Stream, Poll_Timeout_MS, F, Got_Frame);
         if Status /= Http_Client.Errors.Ok or else not Got_Frame then
            return Status;
         end if;

         if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
            return H2_Handle_Settings_Frame (Stream, F, Working_Peer);

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
            return H2_Handle_Ping_Frame (Stream, F);

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.WINDOW_UPDATE then
            Status := H2_Window_Update_Increment (F, Increment);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif F.Header.Stream = 0 then
               if Conn_Send_Window > Natural'Last - Increment then
                  return Http_Client.Errors.HTTP2_Flow_Control_Error;
               end if;
               Conn_Send_Window := Conn_Send_Window + Increment;
            elsif F.Header.Stream = 1 then
               if Stream_Send_Window > Natural'Last - Increment then
                  return Http_Client.Errors.HTTP2_Flow_Control_Error;
               end if;
               Stream_Send_Window := Stream_Send_Window + Increment;
            else
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            return Http_Client.Errors.Ok;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS
           or else F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION
           or else F.Header.Kind = Http_Client.HTTP2.Frames.DATA
         then
            return Handle_Early_Response_Frame (F);

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM
           or else F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY
         then
            return H2_Terminal_Frame_Status (Stream, F);
         else
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
      end Poll_For_Early_Response;

      function Send_Data
        (Payload    : String;
         End_Stream : Boolean) return Http_Client.Errors.Result_Status
      is
      begin
         if Payload'Length > Conn_Send_Window
           or else Payload'Length > Stream_Send_Window
         then
            return Http_Client.Errors.HTTP2_Flow_Control_Error;
         end if;

         Status := Http_Client.Transports.TLS.Write_All
           (Stream.TLS_Conn,
            H2_Serialize_Frame
              (Http_Client.HTTP2.Frames.DATA,
               (if End_Stream then 16#01# else 0),
               1,
               Payload));
         if Status = Http_Client.Errors.Ok then
            Conn_Send_Window := Conn_Send_Window - Payload'Length;
            Stream_Send_Window := Stream_Send_Window - Payload'Length;
            Sent := Sent + Payload'Length;
            Bytes_Since_Poll := Bytes_Since_Poll + Payload'Length;
            if not End_Stream
              and then not Stream.H2_Headers_Done
              and then Bytes_Since_Poll >= Poll_Interval_Bytes
            then
               Bytes_Since_Poll := 0;
               Status := Poll_For_Early_Response;
            end if;
         end if;
         return Status;
      end Send_Data;

      function Send_Buffered (Payload : String) return Http_Client.Errors.Result_Status is
         Pos : Natural := 0;
      begin
         if Payload'Length = 0 then
            return Send_End_Stream;
         end if;

         while Pos < Payload'Length loop
            Status := Wait_For_Send_Window;
            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Stream.H2_Headers_Done then
               return Http_Client.Errors.Ok;
            end if;
            declare
               Quantum : constant Natural := Natural'Min
                 (Natural'Min (Working_Peer.Max_Frame_Size, Conn_Send_Window),
                  Natural'Min (Stream_Send_Window, Payload'Length - Pos));
               Last    : constant Boolean := Pos + Quantum = Payload'Length;
            begin
               if Quantum = 0 then
                  return Http_Client.Errors.Timeout;
               end if;
               Status := Send_Data
                 (Payload (Payload'First + Integer (Pos)
                   .. Payload'First + Integer (Pos + Quantum) - 1),
                  Last and then not Has_Trailers);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Pos := Pos + Quantum;
            end;
         end loop;

         if Has_Trailers then
            return Send_Trailers;
         else
            return Http_Client.Errors.Ok;
         end if;
      end Send_Buffered;
   begin
      case Kind is
         when Http_Client.Request_Bodies.Empty_Body =>
            return Send_End_Stream;

         when Http_Client.Request_Bodies.Buffered_Body =>
            return Send_Buffered (Http_Client.Request_Bodies.Buffered_Payload (B));

         when Http_Client.Request_Bodies.Fixed_Length_Stream |
              Http_Client.Request_Bodies.Unknown_Length_Stream =>
            if not Http_Client.Request_Bodies.Has_Producer (B) then
               return Http_Client.Errors.Body_Producer_Failed;
            elsif Kind = Http_Client.Request_Bodies.Fixed_Length_Stream
              and then Has_Length
              and then Declared_Length = 0
            then
               return Send_End_Stream;
            end if;

            loop
               if Has_Length and then Sent >= Declared_Length then
                  return Send_End_Stream;
               end if;

               Status := Wait_For_Send_Window;
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               elsif Stream.H2_Headers_Done then
                  return Http_Client.Errors.Ok;
               end if;

               declare
                  Quantum : Natural := Natural'Min
                    (Natural'Min (Working_Peer.Max_Frame_Size, Conn_Send_Window),
                     Stream_Send_Window);
               begin
                  if Has_Length then
                     Quantum := Natural'Min (Quantum, Declared_Length - Sent);
                  end if;
                  if Quantum = 0 then
                     return Http_Client.Errors.Timeout;
                  end if;

                  declare
                     Buffer : String (1 .. Positive'Max (1, Quantum));
                  begin
                     Status := Http_Client.Request_Bodies.Read_Next (B, Buffer, Count);
                     if Status /= Http_Client.Errors.Ok then
                        return Status;
                     end if;

                     if Count = 0 then
                        if Has_Length and then Sent /= Declared_Length then
                           return Http_Client.Errors.Body_Length_Mismatch;
                        else
                           return Send_End_Stream;
                        end if;
                     elsif Count > Quantum then
                        return Http_Client.Errors.Body_Length_Mismatch;
                     end if;

                     if Has_Length and then Sent + Count = Declared_Length then
                        declare
                           Extra_Buffer : String (1 .. 1);
                           Extra_Count  : Natural := 0;
                        begin
                           Status := Http_Client.Request_Bodies.Read_Next
                             (B, Extra_Buffer, Extra_Count);
                           if Status /= Http_Client.Errors.Ok then
                              return Status;
                           elsif Extra_Count /= 0 then
                              return Http_Client.Errors.Body_Length_Mismatch;
                           end if;
                        end;
                     end if;

                     Status := Send_Data
                       (Buffer (Buffer'First .. Buffer'First + Count - 1),
                        Has_Length
                          and then Sent + Count = Declared_Length
                          and then not Has_Trailers);
                     if Status /= Http_Client.Errors.Ok then
                        return Status;
                     end if;

                     if Has_Length and then Sent = Declared_Length then
                        if Has_Trailers then
                           return Send_Trailers;
                        else
                           return Http_Client.Errors.Ok;
                        end if;
                     end if;
                  end;
               end;
            end loop;
      end case;
   end H2_Write_Request_Body;


   function Open_HTTP2_Stream
     (Stream    : in out Streaming_Response;
      Request   : Http_Client.Requests.Request;
      Options   : Streaming_Options;
      Final_URI : Http_Client.URI.URI_Reference)
      return Http_Client.Errors.Result_Status
   is
      Status        : Http_Client.Errors.Result_Status;
      H2_Headers    : Http_Client.Headers.Header_List;
      Enc           : Http_Client.HTTP2.HPACK.Encoder :=
        Http_Client.HTTP2.HPACK.Create_Encoder;
      Request_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Has_Request_Trailers : constant Boolean :=
        Http_Client.Request_Bodies.Has_Trailers (Request_Body);
      Kind          : constant Http_Client.Request_Bodies.Body_Kind :=
        Http_Client.Request_Bodies.Kind (Request_Body);
      Declared_Length : Natural := 0;
      Has_Declared_Length : constant Boolean :=
        Http_Client.Request_Bodies.Declared_Length (Request_Body, Declared_Length);
      Request_Has_Body : constant Boolean :=
        Kind = Http_Client.Request_Bodies.Unknown_Length_Stream
        or else (Has_Declared_Length and then Declared_Length > 0);
      Block         : Unbounded_String := Null_Unbounded_String;
      Trailer_Block : Unbounded_String := Null_Unbounded_String;
      Parsed        : Unbounded_String := Null_Unbounded_String;
      Peer          : H2_Peer_Settings;
      Request_Header_List_Size : Natural := 0;
      F             : Http_Client.HTTP2.Frames.Frame;
      Header_Block  : Unbounded_String := Null_Unbounded_String;
      Resp_Headers  : Http_Client.Headers.Header_List;
      Headers_Complete : Boolean := False;
      End_Stream_With_Headers : Boolean := False;
   begin
      Status := Http_Client.HTTP2.Validate (Options.TLS.HTTP2);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Options.TLS.HTTP2.Mode = Http_Client.HTTP2.HTTP2_Disabled then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;

      if Kind in Http_Client.Request_Bodies.Fixed_Length_Stream |
                 Http_Client.Request_Bodies.Unknown_Length_Stream
        and then not Http_Client.Request_Bodies.Has_Producer (Request_Body)
      then
         return Http_Client.Errors.Body_Producer_Failed;
      end if;

      Status := Http_Client.HTTP2.Mapping.Build_Request_Headers (Request, H2_Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := H2_Ensure_Content_Length_Header (H2_Headers, Declared_Length);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := H2_Request_Content_Length_Is_Valid (H2_Headers, Declared_Length);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Has_Request_Trailers then
         if Http_Client.Headers.Contains (H2_Headers, "trailer") then
            return Http_Client.Errors.HTTP2_Header_Error;
         end if;
         Status := Http_Client.Headers.Validate_HTTP2_Trailers
           (Http_Client.Request_Bodies.Trailers (Request_Body), Response => False);
         if Status /= Http_Client.Errors.Ok then
            return Http_Client.Errors.HTTP2_Header_Error;
         end if;
      end if;

      Status := Http_Client.Transports.TLS.Write_All
        (Stream.TLS_Conn,
         Http_Client.HTTP2.Client_Connection_Preface &
         H2_Serialize_Frame
           (Http_Client.HTTP2.Frames.SETTINGS, 0, 0,
            Http_Client.HTTP2.Settings.Initial_Settings_Payload
              (Initial_Window_Size  => Options.TLS.HTTP2.Initial_Stream_Window_Size,
               Max_Header_List_Size => Options.TLS.HTTP2.Max_Header_List_Size,
               Max_Frame_Size       => Options.TLS.HTTP2.Max_Frame_Size)) &
         (if Options.TLS.HTTP2.Initial_Connection_Window_Size > 65_535 then
            H2_Window_Update
              (0, Options.TLS.HTTP2.Initial_Connection_Window_Size - 65_535)
          else ""));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Stream.H2_Peer_Max_Frame_Size := Options.TLS.HTTP2.Max_Frame_Size;
      Status := H2_Read_Frame (Stream, F);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif F.Header.Kind /= Http_Client.HTTP2.Frames.SETTINGS
        or else F.Header.Stream /= 0
        or else H2_Has_Flag (F.Header.Flags, 16#01#)
      then
         return Http_Client.Errors.HTTP2_Settings_Error;
      end if;

      Status := Http_Client.HTTP2.Settings.Parse (To_String (F.Payload), Parsed);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := H2_Parse_Peer_Settings (To_String (F.Payload), Peer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if not H2_Encoded_Header_List_Size (H2_Headers, Request_Header_List_Size)
        or else Request_Header_List_Size > Peer.Max_Header_List_Size
      then
         return Http_Client.Errors.Header_Too_Large;
      end if;

      Http_Client.HTTP2.HPACK.Set_Peer_Dynamic_Table_Size
        (Enc, Peer.Header_Table_Size);
      Status := Http_Client.HTTP2.HPACK.Encode_Header_Block (Enc, H2_Headers, Block);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif Length (Block) > Peer.Max_Frame_Size then
         return Http_Client.Errors.Header_Too_Large;
      end if;

      if Has_Request_Trailers then
         Status := Http_Client.HTTP2.HPACK.Encode_Header_Block
           (Enc, Http_Client.Request_Bodies.Trailers (Request_Body), Trailer_Block);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         elsif Length (Trailer_Block) > Peer.Max_Frame_Size then
            return Http_Client.Errors.Header_Too_Large;
         end if;
      end if;

      Status := Http_Client.Transports.TLS.Write_All
        (Stream.TLS_Conn,
         H2_Serialize_Frame (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, "") &
         H2_Serialize_Frame
           (Http_Client.HTTP2.Frames.HEADERS,
            (if not Request_Has_Body and then not Has_Request_Trailers then 16#05# else 16#04#),
            1,
            To_String (Block)));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Stream.H2_Stream := 1;
      Stream.H2_Decoder := Http_Client.HTTP2.HPACK.Create_Decoder
        (Max_Dynamic_Table_Size => 4_096,
         Max_Header_List_Size   => Options.TLS.HTTP2.Max_Header_List_Size);
      Stream.H2_Headers_Done := False;
      Stream.H2_Conn_Window := Options.TLS.HTTP2.Initial_Connection_Window_Size;
      Stream.H2_Stream_Window := Options.TLS.HTTP2.Initial_Stream_Window_Size;
      Stream.H2_Peer_Max_Frame_Size := Peer.Max_Frame_Size;

      if Request_Has_Body or else Has_Request_Trailers then
         Status := H2_Write_Request_Body
           (Stream   => Stream,
            Request  => Request,
            B        => Request_Body,
            Options  => Options,
            Peer     => Peer,
            Trailers => Trailer_Block);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         elsif Stream.H2_Headers_Done then
            if Http_Client.URI.Is_Empty (Final_URI) then
               Stream.URI_Value := Http_Client.Requests.URI (Request);
            else
               Stream.URI_Value := Final_URI;
            end if;
            return Http_Client.Errors.Ok;
         end if;
      end if;

      loop
         Status := H2_Read_Frame (Stream, F);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.HTTP2.Frames.Apply_Continuation_Rule
           (Stream.H2_Continuation, F.Header);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
            Status := H2_Handle_Settings_Frame
              (Stream, F, Peer, Update_Read_Max_Frame_Size => True);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
            Status := H2_Handle_Ping_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS
           or else F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION
         then
            Status := H2_Handle_Response_Header_Block_Frame
              (Stream, F, Options.TLS.HTTP2.Max_Header_List_Size,
               Header_Block, End_Stream_With_Headers,
               Resp_Headers, Headers_Complete);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Headers_Complete then
               Status := H2_Configure_Response_Metadata
                 (Stream, Request, Resp_Headers, Options);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Stream.H2_Headers_Done := True;
               Stream.Finished := End_Stream_With_Headers;
               if Http_Client.URI.Is_Empty (Final_URI) then
                  Stream.URI_Value := Http_Client.Requests.URI (Request);
               else
                  Stream.URI_Value := Final_URI;
               end if;
               return Http_Client.Errors.Ok;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM
           or else F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY
           or else F.Header.Kind = Http_Client.HTTP2.Frames.PUSH_PROMISE
           or else F.Header.Kind = Http_Client.HTTP2.Frames.DATA
         then
            Status := H2_Terminal_Frame_Status
              (Stream, F, Data_Is_Protocol => True);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
         else
            null;
         end if;
      end loop;
   end Open_HTTP2_Stream;



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
      Acc        : Natural := 0;
      Saw_Digit  : Boolean := False;
      In_Ext     : Boolean := False;
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
            elsif C = ';' then
               if not Saw_Digit then
                  return Http_Client.Errors.Protocol_Error;
               end if;
               In_Ext := True;
            elsif C = ' ' or else C = HT then
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
      --  The streaming HTTP/1.1 path supports only the ordinary chunked
      --  transfer coding. Comma-separated field syntax is parsed so malformed
      --  or unsupported values are rejected deterministically instead of being
      --  accidentally accepted by a raw string comparison. Additional transfer
      --  codings such as "gzip, chunked" are not silently ignored.
      V     : constant String := Value;
      First : Positive := V'First;
      Last  : Natural;
      Seen  : Boolean := False;
   begin
      if V'Length = 0 then
         return False;
      end if;

      loop
         Last := First;
         while Last <= V'Last and then V (Last) /= ',' loop
            Last := Last + 1;
         end loop;

         declare
            Part : constant String := Lower (Trim_OWS (V (First .. Last - 1)));
         begin
            if Seen or else Part /= "chunked" then
               return False;
            end if;
            Seen := True;
         end;

         exit when Last > V'Last;
         First := Last + 1;
         if First > V'Last then
            return False;
         end if;
      end loop;

      return Seen;
   end Transfer_Encoding_Is_Chunked;


   function Contains_Comma (Text : String) return Boolean is
   begin
      for C of Text loop
         if C = ',' then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Comma;

   procedure Free_Decoder (Stream : in out Streaming_Response) is
   begin
      Http_Client.Zlib_Decompression.Close (Stream.Decode_Context);
      Stream.Decode_Active := False;
      Stream.Decode_Finished := False;
      Stream.Decode_End_Seen := False;
      Stream.Decode_Auto := False;
      Stream.Decode_Selected := True;
      Stream.Decode_Format := Http_Client.Zlib_Decompression.Gzip;
      Stream.Decode_Auto_Prefix := Null_Unbounded_String;
      Stream.Decode_Buffer := Null_Unbounded_String;
      Stream.Decode_Read := 0;
      Stream.Decode_Max := 0;
   end Free_Decoder;

   function Configure_Decompression
     (Stream  : in out Streaming_Response;
      Options : Streaming_Options) return Http_Client.Errors.Result_Status
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Stream.Meta);
      Count   : constant Natural :=
        Http_Client.Headers.Count (Headers, "Content-Encoding");
      Token   : constant String :=
        (if Count = 0 then "" else Lower (Trim_OWS (Http_Client.Headers.Get (Headers, "Content-Encoding"))));
      Format  : Http_Client.Zlib_Decompression.Wrapper_Format :=
        Http_Client.Zlib_Decompression.Gzip;
      Auto    : Boolean := False;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Free_Decoder (Stream);

      if not Options.Enable_Decompression
        or else Stream.Mode = No_Body
        or else (Stream.Mode = Fixed_Length and then Stream.Remaining = 0)
      then
         return Http_Client.Errors.Ok;
      end if;

      if Count = 0 or else Token = "" or else Token = "identity" then
         return Http_Client.Errors.Ok;
      end if;

      if Count > 1 or else Contains_Comma (Token) then
         if Options.Decompression.Unsupported_Policy =
           Http_Client.Decompression.Leave_Encoded
         then
            return Http_Client.Errors.Ok;
         else
            return Http_Client.Errors.Unsupported_Content_Encoding;
         end if;
      end if;

      if Token = "gzip" then
         Format := Http_Client.Zlib_Decompression.Gzip;
      elsif Token = "deflate" then
         case Options.Decompression.Deflate_Mode is
            when Http_Client.Decompression.Zlib_Wrapped_Only =>
               Format := Http_Client.Zlib_Decompression.Zlib_Wrapped_Deflate;
            when Http_Client.Decompression.Raw_Only =>
               Format := Http_Client.Zlib_Decompression.Raw_Deflate;
            when Http_Client.Decompression.Auto_Zlib_Then_Raw =>
               Format := Http_Client.Zlib_Decompression.Zlib_Wrapped_Deflate;
               Auto := True;
         end case;
      elsif Options.Decompression.Unsupported_Policy =
        Http_Client.Decompression.Leave_Encoded
      then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Errors.Unsupported_Content_Encoding;
      end if;

      if not Auto then
         Status := Http_Client.Zlib_Decompression.Initialize
           (Item   => Stream.Decode_Context,
            Format => Format);
         if Status /= Http_Client.Errors.Ok then
            Free_Decoder (Stream);
            return Status;
         end if;
      end if;

      Stream.Decode_Active := True;
      Stream.Decode_Finished := False;
      Stream.Decode_End_Seen := False;
      Stream.Decode_Auto := Auto;
      Stream.Decode_Selected := not Auto;
      Stream.Decode_Format := Format;
      Stream.Decode_Auto_Prefix := Null_Unbounded_String;
      Stream.Decode_Buffer := Null_Unbounded_String;
      Stream.Decode_Read := 0;
      Stream.Decode_Max := Options.Decompression.Maximum_Decoded_Body_Size;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Free_Decoder (Stream);
         return Http_Client.Errors.Internal_Error;
   end Configure_Decompression;

   function Append_Decoded
     (Stream : in out Streaming_Response;
      Input  : String;
      Finish : Boolean) return Http_Client.Errors.Result_Status
   is
      Output   : Unbounded_String;
      End_Seen : Boolean := False;
      Status   : Http_Client.Errors.Result_Status;
   begin
      if not Stream.Decode_Active then
         return Http_Client.Errors.Ok;
      end if;

      if Stream.Decode_Read > Stream.Decode_Max then
         return Http_Client.Errors.Decoded_Body_Too_Large;
      end if;

      if Stream.Decode_Auto and then not Stream.Decode_Selected then
         declare
            Combined : constant String := To_String (Stream.Decode_Auto_Prefix) & Input;
         begin
            if Combined'Length < 2 and then not Finish then
               Stream.Decode_Auto_Prefix := To_Unbounded_String (Combined);
               return Http_Client.Errors.Ok;
            end if;

            Stream.Decode_Format :=
              (if Http_Client.Zlib_Decompression.Looks_Like_Zlib_Header (Combined) then
                  Http_Client.Zlib_Decompression.Zlib_Wrapped_Deflate
               else
                  Http_Client.Zlib_Decompression.Raw_Deflate);
            Status := Http_Client.Zlib_Decompression.Initialize
              (Item   => Stream.Decode_Context,
               Format => Stream.Decode_Format);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

            Stream.Decode_Selected := True;
            Stream.Decode_Auto_Prefix := Null_Unbounded_String;
            Status := Http_Client.Zlib_Decompression.Decode_Some
              (Item       => Stream.Decode_Context,
               Input      => Combined,
               Finish     => Finish,
               Max_Output => Stream.Decode_Max - Stream.Decode_Read,
               Output     => Output,
               Stream_End => End_Seen);
         end;
      else
         Status := Http_Client.Zlib_Decompression.Decode_Some
           (Item       => Stream.Decode_Context,
            Input      => Input,
            Finish     => Finish,
            Max_Output => Stream.Decode_Max - Stream.Decode_Read,
            Output     => Output,
            Stream_End => End_Seen);
      end if;

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      declare
         Text : constant String := To_String (Output);
      begin
         if Text'Length > 0 then
            Append (Stream.Decode_Buffer, Text);
            Stream.Decode_Read := Stream.Decode_Read + Text'Length;
         end if;
      end;

      if End_Seen then
         Stream.Decode_End_Seen := True;
      end if;

      if Finish and then not Stream.Decode_End_Seen then
         return Http_Client.Errors.Decompression_Failed;
      end if;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Append_Decoded;

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

   function Line_End_At (Input : String; From : Positive) return Natural is
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


   function Header_Line_Too_Long (Header_Text : String; Max_Line : Natural) return Boolean is
      Cursor   : Positive := Header_Text'First;
      Line_End : Natural;
   begin
      loop
         exit when Cursor > Header_Text'Last;
         Line_End := Line_End_At (Header_Text, Cursor);
         if Line_End = 0 or else Line_End = Natural'Last then
            return False;
         end if;
         if Natural (Line_End - Cursor) > Max_Line then
            return True;
         end if;
         exit when Line_End = Cursor;
         Cursor := Line_End + 2;
      end loop;
      return False;
   end Header_Line_Too_Long;

   function Body_Is_Disallowed
     (Status  : Http_Client.Types.Status_Code;
      Request : Http_Client.Requests.Request) return Boolean is
   begin
      return Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD
        or else (Status >= 100 and then Status <= 199)
        or else Status = 204
        or else Status = 205
        or else Status = 304;
   end Body_Is_Disallowed;

   function Analyze_Header
     (Header_Text : String;
      Request     : Http_Client.Requests.Request;
      Mode        : out Body_Mode;
      Length      : out Natural) return Http_Client.Errors.Result_Status
   is
      Cursor       : Positive := Header_Text'First;
      Line_End     : Natural;
      Parsed_Code  : Natural := 0;
      Status_Code  : Http_Client.Types.Status_Code := 200;
      Has_CL       : Boolean := False;
      CL           : Natural := 0;
      Has_TE       : Boolean := False;
      TE_Chunked   : Boolean := False;
   begin
      Mode := Close_Delimited;
      Length := 0;
      Line_End := Line_End_At (Header_Text, Cursor);
      if Line_End = 0 then
         return Http_Client.Errors.Incomplete_Message;
      elsif Line_End = Natural'Last then
         return Http_Client.Errors.Protocol_Error;
      elsif Line_End - Cursor < 11 then
         return Http_Client.Errors.Protocol_Error;
      end if;

      declare
         Line : constant String := Header_Text (Cursor .. Line_End - 1);
      begin
         if Line'Length < 12
           or else (Line (Line'First .. Line'First + 7) /= "HTTP/1.1"
                    and then Line (Line'First .. Line'First + 7) /= "HTTP/1.0")
           or else Line (Line'First + 8) /= ' '
         then
            return Http_Client.Errors.Protocol_Error;
         end if;
         if not Parse_Natural_Strict (Line (Line'First + 9 .. Line'First + 11), Parsed_Code)
           or else Parsed_Code < 100 or else Parsed_Code > 599
         then
            return Http_Client.Errors.Protocol_Error;
         end if;
         Status_Code := Http_Client.Types.Status_Code (Parsed_Code);
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
         end if;
         exit when Line_End = Cursor;
         if Header_Text (Cursor) = ' ' or else Header_Text (Cursor) = HT then
            return Http_Client.Errors.Unsupported_Feature;
         end if;
         declare
            Line : constant String := Header_Text (Cursor .. Line_End - 1);
            Colon : Natural := 0;
         begin
            for Index in Line'Range loop
               if Line (Index) = ':' then
                  Colon := Index;
                  exit;
               end if;
            end loop;
            if Colon = 0 then
               return Http_Client.Errors.Invalid_Header;
            end if;
            declare
               Name : constant String := Line (Line'First .. Colon - 1);
               Value : constant String := Trim_OWS (Line (Colon + 1 .. Line'Last));
               Lower_Name : constant String := Lower (Name);
               Parsed : Natural := 0;
            begin
               if not Http_Client.Headers.Is_Valid_Name (Name)
                 or else not Http_Client.Headers.Is_Valid_Value (Value)
               then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               if Lower_Name = "transfer-encoding" then
                  if Has_TE then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Has_TE := True;
                  TE_Chunked := Transfer_Encoding_Is_Chunked (Value);
                  if not TE_Chunked then
                     return Http_Client.Errors.Unsupported_Feature;
                  end if;
               elsif Lower_Name = "content-length" then
                  if Has_CL then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  if not Parse_Natural_Strict (Value, Parsed) then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Has_CL := True;
                  CL := Parsed;
               end if;
            end;
         end;
         Cursor := Line_End + 2;
      end loop;

      if Has_TE and then Has_CL then
         return Http_Client.Errors.Invalid_Header;
      elsif Body_Is_Disallowed (Status_Code, Request) then
         Mode := No_Body;
         Length := 0;
      elsif Has_TE then
         Mode := Chunked;
         Length := 0;
      elsif Has_CL then
         Mode := Fixed_Length;
         Length := CL;
      else
         Mode := Close_Delimited;
         Length := 0;
      end if;
      return Http_Client.Errors.Ok;
   end Analyze_Header;

   procedure Reset (Stream : in out Streaming_Response) is
   begin
      Free_Decoder (Stream);
      declare
         Ignored : Http_Client.Errors.Result_Status;
      begin
         if Stream.Opened then
            Ignored := Close (Stream);
         end if;
      end;
      Stream.Transport := No_Transport;
      Stream.Protocol := Protocol_HTTP_1_1;
      Stream.Diagnostic_Protocol := Http_Client.Diagnostics.Protocol_Unknown;
      Stream.Opened := False;
      Stream.Had_Response := False;
      Stream.Finished := True;
      Stream.Failed := False;
      Stream.Mode := No_Body;
      Stream.Remaining := 0;
      Stream.Chunk_Remaining := 0;
      Stream.Chunk_Phase := Reading_Chunk_Size;
      Stream.Body_Read := 0;
      Stream.Max_Body := 0;
      Stream.H2_Stream := 0;
      Stream.H2_Continuation := (others => <>);
      Stream.H2_Decoder := Http_Client.HTTP2.HPACK.Create_Decoder;
      Stream.H2_Headers_Done := False;
      Stream.H2_Bodyless := False;
      Stream.H2_Content_Length_Set := False;
      Stream.H2_Content_Length := 0;
      Stream.H2_Peer_Max_Frame_Size := 16_384;
      Stream.H2_Conn_Window := 65_535;
      Stream.H2_Stream_Window := 65_535;
      Stream.Max_Trailer_Size := 0;
      Stream.Max_Trailer_Line_Size := 0;
      Stream.Trailer_Read := 0;
      Stream.Read_Quantum := 4_096;
      Stream.Lookahead := Null_Unbounded_String;
      Stream.Meta := Http_Client.Responses.Default_Response;
      Stream.URI_Value := Http_Client.URI.Create_Unchecked ("");
      Stream.Last_Result := Http_Client.Errors.Ok;
      Stream.Diagnostics := null;
      Stream.Request_ID := 0;
      Stream.Connection_ID := 0;
      Stream.Request_Start_Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Stream.Cancellation := null;
   end Reset;

   function Read_Transport
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status is
      Cancel_Status : constant Http_Client.Errors.Result_Status :=
        Check_Cancelled (Stream.Cancellation);
   begin
      if Cancel_Status /= Http_Client.Errors.Ok then
         Count := 0;
         return Cancel_Stream (Stream);
      end if;

      case Stream.Transport is
         when Plain_Transport =>
            return Http_Client.Transports.TCP.Read_Some (Stream.TCP, Buffer, Count);
         when TLS_Transport =>
            return Http_Client.Transports.TLS.Read_Some (Stream.TLS_Conn, Buffer, Count);
         when No_Transport =>
            Count := 0;
            return Http_Client.Errors.Not_Connected;
      end case;
   end Read_Transport;

   function Write_Transport
     (Stream : in out Streaming_Response;
      Data   : String) return Http_Client.Errors.Result_Status is
      Cancel_Status : constant Http_Client.Errors.Result_Status :=
        Check_Cancelled (Stream.Cancellation);
   begin
      if Cancel_Status /= Http_Client.Errors.Ok then
         return Cancel_Stream (Stream);
      end if;

      case Stream.Transport is
         when Plain_Transport =>
            return Http_Client.Transports.TCP.Write_All (Stream.TCP, Data);
         when TLS_Transport =>
            return Http_Client.Transports.TLS.Write_All (Stream.TLS_Conn, Data);
         when No_Transport =>
            return Http_Client.Errors.Not_Connected;
      end case;
   end Write_Transport;

   function Prepared_Request
     (Request      : Http_Client.Requests.Request;
      Options      : Streaming_Options;
      Target_Mode  : Http_Client.HTTP1.Request_Target_Mode;
      Output       : out Unbounded_String;
      Wire_Request : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers  : Http_Client.Headers.Header_List := Http_Client.Requests.Headers (Request);
      Status   : Http_Client.Errors.Result_Status;
      Req_Body : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
   begin
      Output := Null_Unbounded_String;
      Wire_Request := Http_Client.Requests.Default_Request;

      if Options.Add_Connection_Close and then not Http_Client.Headers.Contains (Headers, "Connection") then
         Status := Http_Client.Headers.Set (Headers, "Connection", "close");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Options.Cookie_Jar /= null then
         declare
            Existing : constant Boolean := Http_Client.Headers.Contains (Headers, "Cookie");
            Jar_Header : constant String :=
              Http_Client.Cookies.Get_Cookie_Header (Options.Cookie_Jar.all, Http_Client.Requests.URI (Request));
         begin
            if Jar_Header'Length > 0 then
               if not Existing then
                  Status := Http_Client.Headers.Set (Headers, "Cookie", Jar_Header);
               elsif Options.Merge_Jar_Cookies then
                  Status := Http_Client.Headers.Set
                    (Headers, "Cookie", Http_Client.Headers.Get (Headers, "Cookie") & "; " & Jar_Header);
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
           (Headers, "Proxy-Authorization", Http_Client.Proxies.Proxy_Authorization (Options.Proxy));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      else
         Status := Http_Client.Headers.Remove (Headers, "Proxy-Authorization");
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      Status := Http_Client.Requests.Create
        (Method => Http_Client.Requests.Method (Request),
         URI => Http_Client.Requests.URI (Request),
         Item => Wire_Request,
         Headers => Headers,
         Payload => Http_Client.Requests.Payload (Request),
         Auto_Host => False);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Set_Body (Wire_Request, Req_Body);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Http_Client.Headers.Contains
           (Http_Client.Requests.Headers (Wire_Request), "Expect")
        and then Lower
          (Trim_OWS
             (Http_Client.Headers.Get
                (Http_Client.Requests.Headers (Wire_Request), "Expect"))) =
          "100-continue"
        and then Http_Client.Request_Bodies.Has_Body
          (Http_Client.Requests.Request_Body (Wire_Request))
      then
         --  With `Expect: 100-continue`, even buffered bodies must remain
         --  unsent until the interim response grants the upload.
         return Http_Client.HTTP1.Serialize_Headers
           (Wire_Request, Output, Target_Mode);
      elsif Http_Client.Request_Bodies.Kind (Req_Body) = Http_Client.Request_Bodies.Buffered_Body
        or else Http_Client.Request_Bodies.Kind (Req_Body) = Http_Client.Request_Bodies.Empty_Body
      then
         return Http_Client.HTTP1.Serialize_Request (Wire_Request, Output, Target_Mode);
      else
         return Http_Client.HTTP1.Serialize_Headers (Wire_Request, Output, Target_Mode);
      end if;
   end Prepared_Request;




   function Request_Expects_100_Continue
     (Request : Http_Client.Requests.Request) return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
   begin
      return Http_Client.Headers.Contains (Headers, "Expect")
        and then Lower (Trim_OWS (Http_Client.Headers.Get (Headers, "Expect"))) = "100-continue"
        and then Http_Client.Request_Bodies.Has_Body
          (Http_Client.Requests.Request_Body (Request));
   end Request_Expects_100_Continue;

   function Wait_For_100_Continue
     (Stream           : in out Streaming_Response;
      Request          : Http_Client.Requests.Request;
      Options          : Streaming_Options;
      Continue_Granted : out Boolean)
      return Http_Client.Errors.Result_Status
   is
      Acc        : Unbounded_String := Null_Unbounded_String;
      Buffer     : String (1 .. 1);
      Count      : Natural := 0;
      Status     : Http_Client.Errors.Result_Status;
      Header_End : Natural := 0;
      Mode       : Body_Mode := No_Body;
      Length     : Natural := 0;
   begin
      Continue_Granted := False;

      loop
         Status := Read_Transport (Stream, Buffer, Count);
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
         declare
            Text : constant String := To_String (Acc);
         begin
            Header_End := Header_End_Index (Text);
            if Header_End /= 0 then
               if Natural (Header_End - Text'First + 1) > Options.Max_Header_Size
                 or else Header_Line_Too_Long
                   (Text (Text'First .. Header_End), Options.Max_Header_Line_Size)
               then
                  return Http_Client.Errors.Header_Too_Large;
               end if;

               Status := Http_Client.Responses.Parse_Header_Section
                 (Text (Text'First .. Header_End),
                  Stream.Meta,
                  (Request_Was_HEAD =>
                     Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD));
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

               if Http_Client.Responses.Status_Code (Stream.Meta) = 100 then
                  Continue_Granted := True;
                  return Http_Client.Errors.Ok;
               elsif Http_Client.Responses.Status_Code (Stream.Meta) >= 100
                 and then Http_Client.Responses.Status_Code (Stream.Meta) <= 199
               then
                  Acc := Null_Unbounded_String;
               else
                  Status := Analyze_Header
                    (Text (Text'First .. Header_End), Request, Mode, Length);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  elsif Length > Options.Max_Body_Size then
                     return Http_Client.Errors.Response_Too_Large;
                  end if;

                  Stream.Mode := Mode;
                  Stream.Remaining := Length;
                  Stream.Max_Body := Options.Max_Body_Size;
                  Stream.Max_Trailer_Size := Options.Max_Header_Size;
                  Stream.Max_Trailer_Line_Size := Options.Max_Header_Line_Size;
                  Stream.Trailer_Read := 0;
                  Stream.Read_Quantum := Options.Read_Buffer_Size;
                  Stream.Body_Read := 0;
                  Status := Configure_Decompression (Stream, Options);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Stream.Had_Response := True;
                  if Stream.Mode = No_Body or else
                    (Stream.Mode = Fixed_Length and then Stream.Remaining = 0)
                  then
                     Stream.Finished := True;
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status :=
                          Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  end if;

                  Continue_Granted := False;
                  return Http_Client.Errors.Ok;
               end if;
            elsif Text'Length > Options.Max_Header_Size then
               return Http_Client.Errors.Header_Too_Large;
            end if;
         end;
      end loop;
   exception
      when others =>
         Continue_Granted := False;
         return Http_Client.Errors.Internal_Error;
   end Wait_For_100_Continue;


   function Write_Chunked_Upload
     (Stream  : in out Streaming_Response;
      Request : Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Req_Body : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Buffer   : String (1 .. 8192);
      Count    : Natural := 0;
      Status   : Http_Client.Errors.Result_Status;
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Sent     : Natural := 0;
   begin
      loop
         Status := Check_Cancelled (Stream.Cancellation);
         if Status /= Http_Client.Errors.Ok then
            return Cancel_Stream (Stream);
         end if;

         Status := Http_Client.Request_Bodies.Read_Next
           (Req_Body, Buffer, Count);

         if Status /= Http_Client.Errors.Ok then
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Stream_Diagnostic
                   (Stream,
                    (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                     Result  => Status,
                     Message => Http_Client.Diagnostics.To_Text
                       ("chunked upload producer failed"),
                     others  => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
            end;
            return Status;
         end if;

         Status := Check_Cancelled (Stream.Cancellation);
         if Status /= Http_Client.Errors.Ok then
            return Cancel_Stream (Stream);
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
               Status := Check_Cancelled (Stream.Cancellation);
               if Status /= Http_Client.Errors.Ok then
                  return Cancel_Stream (Stream);
               end if;
               Status := Write_Transport
                 (Stream, Ada.Strings.Unbounded.To_String (Trailer_Text));
            end;
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Stream_Diagnostic
                   (Stream,
                    (Kind               => Http_Client.Diagnostics.Upload_Producer_Event,
                     Request_Byte_Count => Sent,
                     Result             => Http_Client.Errors.Ok,
                     Message            => Http_Client.Diagnostics.To_Text
                       ("chunked upload producer completed"),
                     others             => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  return Emit_Status;
               end if;
            end;
            return Http_Client.Errors.Ok;
         end if;

         Status := Write_Transport (Stream, Hex_Image (Count) & CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Write_Transport
           (Stream, Buffer (Buffer'First .. Buffer'First + Count - 1));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Write_Transport (Stream, CRLF);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Sent := Sent + Count;
      end loop;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Chunked_Upload;

   function Write_Buffered_Upload
     (Stream  : in out Streaming_Response;
      Request : Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Payload : constant String :=
        Http_Client.Request_Bodies.Buffered_Payload
          (Http_Client.Requests.Request_Body (Request));
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         return Cancel_Stream (Stream);
      end if;

      if Payload'Length = 0 then
         return Http_Client.Errors.Ok;
      else
         return Write_Transport (Stream, Payload);
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Buffered_Upload;

   function Write_Upload
     (Stream  : in out Streaming_Response;
      Request : Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Req_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Remaining       : Natural := 0;
      Original_Length : Natural := 0;
      Buffer          : String (1 .. 8192);
      Count     : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         return Cancel_Stream (Stream);
      end if;

      case Http_Client.Request_Bodies.Kind (Req_Body) is
         when Http_Client.Request_Bodies.Empty_Body |
              Http_Client.Request_Bodies.Buffered_Body =>
            return Http_Client.Errors.Ok;
         when Http_Client.Request_Bodies.Unknown_Length_Stream =>
            return Write_Chunked_Upload (Stream, Request);
         when Http_Client.Request_Bodies.Fixed_Length_Stream =>
            if not Http_Client.Request_Bodies.Declared_Length (Req_Body, Remaining) then
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
            Original_Length := Remaining;
      end case;

      while Remaining > 0 loop
         Status := Check_Cancelled (Stream.Cancellation);
         if Status /= Http_Client.Errors.Ok then
            return Cancel_Stream (Stream);
         end if;

         declare
            Limit : constant Natural := Natural'Min (Remaining, Buffer'Length);
         begin
            Status := Http_Client.Request_Bodies.Read_Next
              (Req_Body,
               Buffer (Buffer'First .. Buffer'First + Limit - 1),
               Count);

            if Status /= Http_Client.Errors.Ok then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Stream_Diagnostic
                      (Stream,
                       (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                        Result  => Status,
                        Message => Http_Client.Diagnostics.To_Text ("streaming upload producer failed"),
                        others  => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     return Emit_Status;
                  end if;
               end;
               return Status;
            elsif Count = 0 or else Count > Limit or else Count > Remaining then
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Stream_Diagnostic
                      (Stream,
                       (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                        Result  => Http_Client.Errors.Body_Length_Mismatch,
                        Message => Http_Client.Diagnostics.To_Text ("streaming upload length mismatch"),
                        others  => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     return Emit_Status;
                  end if;
               end;
               return Http_Client.Errors.Body_Length_Mismatch;
            end if;
         end;

         Status := Check_Cancelled (Stream.Cancellation);
         if Status /= Http_Client.Errors.Ok then
            return Cancel_Stream (Stream);
         end if;

         Status := Write_Transport
           (Stream,
            Buffer (Buffer'First .. Buffer'First + Count - 1));

         if Status /= Http_Client.Errors.Ok then
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Stream_Diagnostic
                   (Stream,
                    (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                     Result  => Status,
                     Message => Http_Client.Diagnostics.To_Text ("streaming upload write failed"),
                     others  => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  declare
                     Ignored : constant Http_Client.Errors.Result_Status :=
                       Close (Stream);
                     pragma Unreferenced (Ignored);
                  begin
                     Stream.Failed := True;
                     Stream.Last_Result := Emit_Status;
                     return Emit_Status;
                  end;
               end if;
            end;
            return Status;
         end if;

         Remaining := Remaining - Count;
      end loop;

      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         return Cancel_Stream (Stream);
      end if;

      Status := Http_Client.Request_Bodies.Read_Next
        (Req_Body,
         Buffer (Buffer'First .. Buffer'First),
         Count);

      if Status /= Http_Client.Errors.Ok then
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                  Result  => Status,
                  Message => Http_Client.Diagnostics.To_Text ("streaming upload producer failed"),
                  others  => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         return Status;
      elsif Count /= 0 then
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind    => Http_Client.Diagnostics.Upload_Producer_Event,
                  Result  => Http_Client.Errors.Body_Length_Mismatch,
                  Message => Http_Client.Diagnostics.To_Text ("streaming upload length mismatch"),
                  others  => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         return Http_Client.Errors.Body_Length_Mismatch;
      else
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind               => Http_Client.Diagnostics.Upload_Producer_Event,
                  Request_Byte_Count => Original_Length,
                  Result             => Http_Client.Errors.Ok,
                  Message            => Http_Client.Diagnostics.To_Text ("streaming upload producer completed"),
                  others             => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         return Http_Client.Errors.Ok;
      end if;
   exception
      when others =>
         return Http_Client.Errors.Body_Producer_Failed;
   end Write_Upload;


   function Setup_Buffered_Protocol_Stream
     (Stream    : in out Streaming_Response;
      Request   : Http_Client.Requests.Request;
      Options   : Streaming_Options;
      Final_URI : Http_Client.URI.URI_Reference;
      Response  : Http_Client.Responses.Response;
      Protocol  : Http_Client.Diagnostics.Protocol_Version)
      return Http_Client.Errors.Result_Status
   is
      Payload : constant String := Http_Client.Responses.Response_Body (Response);
      Status  : Http_Client.Errors.Result_Status;
   begin
      Stream.Meta := Response;
      Stream.Mode := Fixed_Length;
      Stream.Remaining := Payload'Length;
      Stream.Max_Body := Options.Max_Body_Size;
      Stream.Read_Quantum := Options.Read_Buffer_Size;
      Stream.Body_Read := 0;
      Stream.Lookahead := To_Unbounded_String (Payload);
      Stream.Had_Response := True;
      Stream.Finished := Payload'Length = 0;
      Stream.Failed := False;
      Stream.Opened := True;
      Stream.Transport := No_Transport;
      Stream.Diagnostic_Protocol := Protocol;
      Http_Client.Resources.Increment
        (Http_Client.Resources.Streaming_Responses_Open);

      Status := Configure_Decompression (Stream, Options);
      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Status;
            return Status;
         end;
      end if;

      if Http_Client.URI.Is_Empty (Final_URI) then
         Stream.URI_Value := Http_Client.Requests.URI (Request);
      else
         Stream.URI_Value := Final_URI;
      end if;

      declare
         Emit_Status : Http_Client.Errors.Result_Status;
      begin
         Emit_Status := Emit_Stream_Diagnostic
           (Stream,
            (Kind        => Http_Client.Diagnostics.Streaming_Response_Opened,
             Status_Code => Natural (Http_Client.Responses.Status_Code (Stream.Meta)),
             Protocol    => Protocol,
             others      => <>));
         if Emit_Status /= Http_Client.Errors.Ok then
            Stream.Last_Result := Emit_Status;
            return Emit_Status;
         end if;
      end;

      if Stream.Finished then
         Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
      else
         Stream.Last_Result := Http_Client.Errors.Ok;
      end if;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Stream.Last_Result := Http_Client.Errors.Internal_Error;
         return Stream.Last_Result;
   end Setup_Buffered_Protocol_Stream;

   function Open
     (Request   : Http_Client.Requests.Request;
      Stream    : in out Streaming_Response;
      Options   : Streaming_Options := Default_Streaming_Options;
      Final_URI : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("");
      Redirect_Count : Natural := 0;
      Retry_Attempt_Count : Natural := 1)
      return Http_Client.Errors.Result_Status
   is
      Status      : Http_Client.Errors.Result_Status;
      Wire        : Unbounded_String;
      Wire_Request : Http_Client.Requests.Request;
      Acc         : Unbounded_String := Null_Unbounded_String;
      Buffer      : String (1 .. Options.Read_Buffer_Size);
      Count       : Natural := 0;
      Header_End  : Natural := 0;
      Body_First  : Natural := 0;
      Mode        : Body_Mode := No_Body;
      Length      : Natural := 0;
      Use_Proxy   : constant Boolean := Http_Client.Proxies.Is_Enabled (Options.Proxy);
      Target_Mode : Http_Client.HTTP1.Request_Target_Mode := Http_Client.HTTP1.Origin_Form;
      Open_Host   : Unbounded_String;
      Open_Port   : Http_Client.URI.TCP_Port;
      Effective_TLS : Http_Client.Transports.TLS.TLS_Options := Options.TLS;
      Buffered_Protocol_Response : Http_Client.Responses.Response;
   begin
      Reset (Stream);
      Stream.Redirects_Followed := Redirect_Count;
      Stream.Retry_Attempts := Retry_Attempt_Count;
      Stream.Cancellation := Options.Cancellation;

      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         Stream.Last_Result := Status;
         return Status;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         Stream.Last_Result := Http_Client.Errors.Invalid_Request;
         return Stream.Last_Result;
      elsif Options.Max_Header_Size = 0 or else Options.Max_Header_Line_Size = 0 then
         Stream.Last_Result := Http_Client.Errors.Invalid_Configuration;
         return Stream.Last_Result;
      end if;

      Stream.Diagnostics := Options.Diagnostics;
      if Diagnostics_Active (Options) then
         Stream.Request_Start_Time := Http_Client.Diagnostics.Now (Options.Diagnostics.all);
         Stream.Request_ID := Http_Client.Diagnostics.Next_Request_ID (Options.Diagnostics.all);
         Status := Emit_Diagnostic
           (Options,
            (Kind          => Http_Client.Diagnostics.Request_Start,
             Request_ID    => Stream.Request_ID,
             URI_Or_Origin => Http_Client.Diagnostics.To_Text
               (Http_Client.URI.Scheme (Http_Client.Requests.URI (Request)) & "://" &
                Http_Client.URI.Host (Http_Client.Requests.URI (Request))),
             Has_Method    => True,
             Method        => Http_Client.Requests.Method (Request),
             others        => <>));
         if Status /= Http_Client.Errors.Ok then
            Stream.Last_Result := Status;
            return Status;
         end if;
      end if;

      if Http_Client.TLS.Client_Certificates.Is_Configured
           (Effective_TLS.Client_Certificate)
        and then Http_Client.TLS.Client_Certificates.Validate
           (Effective_TLS.Client_Certificate) = Http_Client.Errors.Ok
        and then not Http_Client.TLS.Client_Certificates.Matches
           (Effective_TLS.Client_Certificate, Http_Client.Requests.URI (Request))
      then
         --  Direct streaming users get the same per-request mutual-TLS
         --  scoping behavior as the high-level client: credentials scoped to a
         --  different origin are not presented on this TLS handshake.
         Effective_TLS.Client_Certificate :=
           Http_Client.TLS.Client_Certificates.No_Client_Certificate;
      end if;

      case Options.Protocol_Policy is
         when Streaming_HTTP_1_1_Only =>
            Effective_TLS.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Disabled;
         when Streaming_Prefer_HTTP_2 =>
            Effective_TLS.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Allowed;
         when Streaming_Force_HTTP_2 =>
            if Http_Client.URI.Scheme (Http_Client.Requests.URI (Request)) /= "https" then
               Stream.Last_Result := Http_Client.Errors.HTTP2_Unsupported_Feature;
               return Stream.Last_Result;
            end if;
            Effective_TLS.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Required;
         when Streaming_Prefer_HTTP_3 =>
            --  HTTP/3 uses UDP/QUIC rather than this TCP/TLS connection. Try the
            --  explicit HTTP/3 boundary before any TCP request bytes are sent;
            --  fall back to HTTP/1.1 only when policy and backend status allow.
            declare
               H3_Options : Http_Client.HTTP3.HTTP3_Options := Options.HTTP3;
            begin
               H3_Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
               H3_Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
               Status := Http_Client.HTTP3.Execution.Execute_Buffered
                 (Request          => Request,
                  Options          => H3_Options,
                  Response         => Buffered_Protocol_Response,
                  Proxy_Configured => Use_Proxy and then
                     Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.HTTP_Proxy,
                  SOCKS_Configured => Use_Proxy and then
                     Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy,
                  Client_Certificate_Configured =>
                    Http_Client.TLS.Client_Certificates.Is_Configured
                      (Effective_TLS.Client_Certificate),
                  Max_Body_Size    => Options.Max_Body_Size,
                  Diagnostics      => Options.Diagnostics,
                  Request_ID       => Stream.Request_ID,
                  Connection_ID    => Stream.Connection_ID);
               if Status = Http_Client.Errors.Ok then
                  return Setup_Buffered_Protocol_Stream
                    (Stream, Request, Options, Final_URI, Buffered_Protocol_Response,
                     Http_Client.Diagnostics.Protocol_HTTP_3);
               elsif Http_Client.HTTP3.Fallback_Status (H3_Options, False) /= Http_Client.Errors.Ok then
                  Stream.Last_Result := Status;
                  return Status;
               end if;
            end;
            Effective_TLS.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Disabled;
         when Streaming_Force_HTTP_3 =>
            declare
               H3_Options : Http_Client.HTTP3.HTTP3_Options := Options.HTTP3;
            begin
               H3_Options.Mode := Http_Client.HTTP3.HTTP3_Required;
               H3_Options.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
               Status := Http_Client.HTTP3.Execution.Execute_Buffered
                 (Request          => Request,
                  Options          => H3_Options,
                  Response         => Buffered_Protocol_Response,
                  Proxy_Configured => Use_Proxy and then
                     Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.HTTP_Proxy,
                  SOCKS_Configured => Use_Proxy and then
                     Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy,
                  Client_Certificate_Configured =>
                    Http_Client.TLS.Client_Certificates.Is_Configured
                      (Effective_TLS.Client_Certificate),
                  Max_Body_Size    => Options.Max_Body_Size,
                  Diagnostics      => Options.Diagnostics,
                  Request_ID       => Stream.Request_ID,
                  Connection_ID    => Stream.Connection_ID);
               if Status = Http_Client.Errors.Ok then
                  return Setup_Buffered_Protocol_Stream
                    (Stream, Request, Options, Final_URI, Buffered_Protocol_Response,
                     Http_Client.Diagnostics.Protocol_HTTP_3);
               else
                  Stream.Last_Result := Status;
                  return Status;
               end if;
            end;
      end case;


      if Use_Proxy then
         if Http_Client.Proxies.Kind (Options.Proxy) /= Http_Client.Proxies.HTTP_Proxy
           and then Http_Client.Proxies.Kind (Options.Proxy) /= Http_Client.Proxies.SOCKS5_Proxy
         then
            Stream.Last_Result := Http_Client.Errors.Proxy_Unsupported;
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Stream_Diagnostic
                   (Stream,
                    (Kind   => Http_Client.Diagnostics.Request_Finish,
                     Result => Stream.Last_Result,
                     others => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  Stream.Failed := True;
                  Stream.Last_Result := Emit_Status;
                  return Emit_Status;
               end if;
            end;
            return Stream.Last_Result;
         end if;

         if Http_Client.URI.Scheme (Http_Client.Requests.URI (Request)) = "https"
           or else Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy
         then
            Target_Mode := Http_Client.HTTP1.Origin_Form;
         else
            Target_Mode := Http_Client.HTTP1.Absolute_Form;
         end if;

         Open_Host := To_Unbounded_String (Http_Client.Proxies.Host (Options.Proxy));
         Open_Port := Http_Client.Proxies.Port (Options.Proxy);
      else
         Open_Host := To_Unbounded_String (Http_Client.URI.Host (Http_Client.Requests.URI (Request)));
         Open_Port := Http_Client.URI.Effective_Port (Http_Client.Requests.URI (Request));
      end if;

      Status := Prepared_Request (Request, Options, Target_Mode, Wire, Wire_Request);
      if Status /= Http_Client.Errors.Ok then
         Stream.Last_Result := Status;
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind   => Http_Client.Diagnostics.Request_Finish,
                  Result => Status,
                  others => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         return Status;
      end if;

      if Diagnostics_Active (Options) then
         Stream.Connection_ID := Http_Client.Diagnostics.Next_Connection_ID (Options.Diagnostics.all);
         Status := Emit_Stream_Diagnostic
           (Stream,
            (Kind     => Http_Client.Diagnostics.DNS_Connect_Start,
             Protocol =>
               (if Http_Client.URI.Scheme (Http_Client.Requests.URI (Request)) = "https"
                then Http_Client.Diagnostics.Protocol_HTTP_1_1
                else Http_Client.Diagnostics.Protocol_HTTP_1_1),
             others   => <>));
         if Status /= Http_Client.Errors.Ok then
            Stream.Last_Result := Status;
            return Status;
         end if;
      end if;

      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         Stream.Last_Result := Status;
         return Status;
      end if;

      if Http_Client.URI.Scheme (Http_Client.Requests.URI (Request)) = "https" then
         if Use_Proxy then
            if Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.HTTP_Proxy then
               Status := Http_Client.Transports.TLS.Open_Through_HTTP_Proxy
                 (Item                => Stream.TLS_Conn,
                  Host                => Http_Client.URI.Host (Http_Client.Requests.URI (Request)),
                  Port                => Http_Client.URI.Effective_Port (Http_Client.Requests.URI (Request)),
                  Proxy_Host          => Http_Client.Proxies.Host (Options.Proxy),
                  Proxy_Port          => Http_Client.Proxies.Port (Options.Proxy),
                  Proxy_Authorization =>
                    (if Http_Client.Proxies.Has_Proxy_Authorization (Options.Proxy)
                     then Http_Client.Proxies.Proxy_Authorization (Options.Proxy)
                     else ""),
                  Options             => Effective_TLS);
            elsif Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy then
               Status := Http_Client.Transports.TLS.Open_Through_SOCKS_Proxy
                 (Item    => Stream.TLS_Conn,
                  Host    => Http_Client.URI.Host (Http_Client.Requests.URI (Request)),
                  Port    => Http_Client.URI.Effective_Port (Http_Client.Requests.URI (Request)),
                  Proxy   => Options.Proxy,
                  Options => Effective_TLS);
            else
               Status := Http_Client.Errors.Proxy_Unsupported;
            end if;
         else
            Status := Http_Client.Transports.TLS.Open
              (Stream.TLS_Conn,
               Http_Client.URI.Host (Http_Client.Requests.URI (Request)),
               Http_Client.URI.Effective_Port (Http_Client.Requests.URI (Request)),
               Effective_TLS);
         end if;
         Stream.Transport := TLS_Transport;
      else
         if Use_Proxy and then Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.SOCKS5_Proxy then
            Status := Http_Client.Transports.SOCKS.Open_Tunnel
              (Connection  => Stream.TCP,
               Proxy       => Options.Proxy,
               Target_Host => Http_Client.URI.Host (Http_Client.Requests.URI (Request)),
               Target_Port => Http_Client.URI.Effective_Port (Http_Client.Requests.URI (Request)),
               Timeouts    => Options.Timeouts);
         else
            Status := Http_Client.Transports.TCP.Open
              (Stream.TCP,
               To_String (Open_Host),
               Open_Port,
               Options.Timeouts);
         end if;
         Stream.Transport := Plain_Transport;
      end if;

      if Status /= Http_Client.Errors.Ok then
         if Use_Proxy
           and then Stream.Transport = Plain_Transport
           and then Http_Client.Proxies.Kind (Options.Proxy) = Http_Client.Proxies.HTTP_Proxy
           and then (Status = Http_Client.Errors.Connection_Failed
                     or else Status = Http_Client.Errors.DNS_Failed
                     or else Status = Http_Client.Errors.Timeout)
         then
            Stream.Last_Result := Http_Client.Errors.Proxy_Connection_Failed;
         else
            Stream.Last_Result := Status;
         end if;
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind   => Http_Client.Diagnostics.Request_Finish,
                  Result => Stream.Last_Result,
                  others => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
         return Stream.Last_Result;
      end if;

      if Stream.Transport = TLS_Transport
        and then Http_Client.Transports.TLS.Selected_ALPN (Stream.TLS_Conn) =
          Http_Client.HTTP2.Protocol_HTTP_2
      then
         if Options.Protocol_Policy = Streaming_HTTP_1_1_Only then
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               Stream.Last_Result := Http_Client.Errors.ALPN_Negotiation_Failed;
               return Stream.Last_Result;
            end;
         end if;

         declare
            H2_Options : Streaming_Options := Options;
         begin
            H2_Options.TLS := Effective_TLS;
            Status := Open_HTTP2_Stream
              (Stream    => Stream,
               Request   => Request,
               Options   => H2_Options,
               Final_URI => Final_URI);
         end;
         if Status /= Http_Client.Errors.Ok then
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               Stream.Last_Result := Status;
               return Status;
            end;
         end if;

         declare
            Emit_Status : Http_Client.Errors.Result_Status;
         begin
            Emit_Status := Emit_Stream_Diagnostic
              (Stream,
               (Kind                => Http_Client.Diagnostics.Response_Headers_Received,
                Status_Code         => Natural (Http_Client.Responses.Status_Code (Stream.Meta)),
                Response_Byte_Count => 0,
                Protocol            => Http_Client.Diagnostics.Protocol_HTTP_2,
                others              => <>));
            if Emit_Status /= Http_Client.Errors.Ok then
               Stream.Last_Result := Emit_Status;
               return Emit_Status;
            end if;

            Emit_Status := Emit_Stream_Diagnostic
              (Stream,
               (Kind        => Http_Client.Diagnostics.Streaming_Response_Opened,
                Status_Code => Natural (Http_Client.Responses.Status_Code (Stream.Meta)),
                Protocol    => Http_Client.Diagnostics.Protocol_HTTP_2,
                others      => <>));
            if Emit_Status /= Http_Client.Errors.Ok then
               Stream.Last_Result := Emit_Status;
               return Emit_Status;
            end if;
         end;

         return Http_Client.Errors.Ok;
      end if;

      declare
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_Stream_Diagnostic
             (Stream,
              (Kind     => Http_Client.Diagnostics.TCP_Connection_Opened,
               Protocol => Http_Client.Diagnostics.Protocol_HTTP_1_1,
               others   => <>));
      begin
         if Emit_Status /= Http_Client.Errors.Ok then
            Stream.Last_Result := Emit_Status;
            return Emit_Status;
         end if;
      end;

      Stream.Opened := True;
      Http_Client.Resources.Increment
        (Http_Client.Resources.Streaming_Responses_Open);
      Stream.Finished := False;

      Status := Write_Transport (Stream, To_String (Wire));
      if Status = Http_Client.Errors.Ok then
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind               => Http_Client.Diagnostics.Request_Headers_Sent,
                  Request_Byte_Count => Natural (Ada.Strings.Unbounded.Length (Wire)),
                  Protocol           => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                  others             => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               Status := Emit_Status;
            end if;
         end;
      end if;
      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Status;
            return Status;
         end;
      end if;

      if Request_Expects_100_Continue (Wire_Request) then
         declare
            Continue_Granted : Boolean := False;
         begin
            Status := Wait_For_100_Continue
              (Stream           => Stream,
               Request          => Wire_Request,
               Options          => Options,
               Continue_Granted => Continue_Granted);
            if Status /= Http_Client.Errors.Ok then
               declare
                  Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                  pragma Unreferenced (Ignored);
               begin
                  Stream.Last_Result := Status;
                  return Status;
               end;
            elsif not Continue_Granted then
               Stream.Last_Result := Http_Client.Errors.Ok;
               return Http_Client.Errors.Ok;
            end if;
         end;
      end if;

      if Request_Expects_100_Continue (Wire_Request)
        and then Http_Client.Request_Bodies.Kind
          (Http_Client.Requests.Request_Body (Wire_Request)) =
            Http_Client.Request_Bodies.Buffered_Body
      then
         Status := Write_Buffered_Upload (Stream, Wire_Request);
      else
         Status := Write_Upload (Stream, Wire_Request);
      end if;
      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Status;
            return Status;
         end;
      end if;

      loop
         Status := Read_Transport (Stream, Buffer, Count);
         if Status = Http_Client.Errors.Ok then
            if Count = 0 then
               Status := Http_Client.Errors.Read_Failed;
               exit;
            end if;
            Append (Acc, Buffer (1 .. Count));
            declare
               Text : constant String := To_String (Acc);
            begin
               Header_End := Header_End_Index (Text);
               if Header_End = 0 then
                  if Text'Length > Options.Max_Header_Size then
                     Status := Http_Client.Errors.Header_Too_Large;
                     exit;
                  end if;
               else
                  if Natural (Header_End - Text'First + 1) > Options.Max_Header_Size then
                     Status := Http_Client.Errors.Header_Too_Large;
                     exit;
                  end if;
                  declare
                     Header_Text : constant String := Text (Text'First .. Header_End);
                     Context     : constant Http_Client.Responses.Parse_Context :=
                       (Request_Was_HEAD => Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD);
                  begin
                     if Header_Line_Too_Long (Header_Text, Options.Max_Header_Line_Size) then
                        Status := Http_Client.Errors.Header_Too_Large;
                     else
                        Status := Http_Client.Responses.Parse_Header_Section (Header_Text, Stream.Meta, Context);
                        if Status = Http_Client.Errors.Ok then
                           Status := Analyze_Header (Header_Text, Request, Mode, Length);
                        end if;
                     end if;
                  end;
                  if Status /= Http_Client.Errors.Ok then
                     exit;
                  end if;
                  if Length > Options.Max_Body_Size then
                     Status := Http_Client.Errors.Response_Too_Large;
                     exit;
                  end if;
                  Body_First := Header_End + 1;
                  Stream.Mode := Mode;
                  Stream.Remaining := Length;
                  Stream.Max_Body := Options.Max_Body_Size;
                  Stream.Max_Trailer_Size := Options.Max_Header_Size;
                  Stream.Max_Trailer_Line_Size := Options.Max_Header_Line_Size;
                  Stream.Trailer_Read := 0;
                  Stream.Read_Quantum := Options.Read_Buffer_Size;
                  Stream.Body_Read := 0;
                  Status := Configure_Decompression (Stream, Options);
                  if Status /= Http_Client.Errors.Ok then
                     exit;
                  end if;
                  if Http_Client.URI.Is_Empty (Final_URI) then
                     Stream.URI_Value := Http_Client.Requests.URI (Request);
                  else
                     Stream.URI_Value := Final_URI;
                  end if;
                  if Body_First <= Text'Last then
                     Stream.Lookahead := To_Unbounded_String (Text (Body_First .. Text'Last));
                     if Stream.Mode = No_Body then
                        Status := Http_Client.Errors.Protocol_Error;
                        exit;
                     elsif Stream.Mode = Fixed_Length
                       and then Natural (Ada.Strings.Unbounded.Length (Stream.Lookahead)) > Stream.Remaining
                     then
                        Status := Http_Client.Errors.Protocol_Error;
                        exit;
                     elsif Stream.Mode = Close_Delimited
                       and then Natural (Ada.Strings.Unbounded.Length (Stream.Lookahead)) > Options.Max_Body_Size
                     then
                        Status := Http_Client.Errors.Response_Too_Large;
                        exit;
                     end if;
                  end if;
                  if Stream.Mode = No_Body or else (Stream.Mode = Fixed_Length and then Stream.Remaining = 0) then
                     Stream.Finished := True;
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  end if;
                  if Options.Cookie_Jar /= null then
                     declare
                        Cookie_Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
                     begin
                        Http_Client.Cookies.Store_From_Response
                          (Jar        => Options.Cookie_Jar.all,
                           Origin_URI => Http_Client.Requests.URI (Request),
                           Headers    => Http_Client.Responses.Headers (Stream.Meta),
                           Strict     => Options.Strict_Cookies,
                           Status     => Cookie_Status);
                        if Options.Strict_Cookies and then Cookie_Status /= Http_Client.Errors.Ok then
                           Status := Cookie_Status;
                           exit;
                        end if;
                     end;
                  end if;
                  declare
                     Emit_Status : Http_Client.Errors.Result_Status;
                  begin
                     Emit_Status := Emit_Stream_Diagnostic
                       (Stream,
                        (Kind                => Http_Client.Diagnostics.Response_Headers_Received,
                         Status_Code         => Natural (Http_Client.Responses.Status_Code (Stream.Meta)),
                         Response_Byte_Count => Natural (Header_End - Text'First + 1),
                         Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                         others              => <>));
                     if Emit_Status /= Http_Client.Errors.Ok then
                        declare
                           Ignored : constant Http_Client.Errors.Result_Status :=
                             Close (Stream);
                           pragma Unreferenced (Ignored);
                        begin
                           Stream.Last_Result := Emit_Status;
                           return Emit_Status;
                        end;
                     end if;

                     Emit_Status := Emit_Stream_Diagnostic
                       (Stream,
                        (Kind        => Http_Client.Diagnostics.Streaming_Response_Opened,
                         Status_Code => Natural (Http_Client.Responses.Status_Code (Stream.Meta)),
                         Protocol    => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                         others      => <>));
                     if Emit_Status /= Http_Client.Errors.Ok then
                        declare
                           Ignored : constant Http_Client.Errors.Result_Status :=
                             Close (Stream);
                           pragma Unreferenced (Ignored);
                        begin
                           Stream.Last_Result := Emit_Status;
                           return Emit_Status;
                        end;
                     end if;
                  end;

                  Stream.Had_Response := True;
                  Stream.Diagnostic_Protocol := Http_Client.Diagnostics.Protocol_HTTP_1_1;

                  if Stream.Finished then
                     declare
                        Emit_Status : Http_Client.Errors.Result_Status :=
                          Emit_Stream_Diagnostic
                            (Stream,
                             (Kind   => Http_Client.Diagnostics.Streaming_Response_Closed,
                              Result => Http_Client.Errors.Ok,
                              others => <>));
                     begin
                        if Emit_Status /= Http_Client.Errors.Ok then
                           Stream.Last_Result := Emit_Status;
                           return Emit_Status;
                        end if;

                        Emit_Status := Emit_Stream_Diagnostic
                          (Stream,
                           (Kind   => Http_Client.Diagnostics.Request_Finish,
                            Result => Http_Client.Errors.Ok,
                            others => <>));
                        if Emit_Status /= Http_Client.Errors.Ok then
                           Stream.Last_Result := Emit_Status;
                           return Emit_Status;
                        end if;
                     end;
                  end if;

                  Stream.Last_Result := Http_Client.Errors.Ok;
                  return Http_Client.Errors.Ok;
               end if;
            end;
         elsif Status = Http_Client.Errors.End_Of_Stream then
            Status := Http_Client.Errors.Incomplete_Message;
            exit;
         else
            exit;
         end if;
      end loop;

      declare
         Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
         pragma Unreferenced (Ignored);
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_Stream_Diagnostic
             (Stream,
              (Kind   => Http_Client.Diagnostics.Request_Finish,
               Result => Status,
               others => <>));
      begin
         Stream.Last_Result := Status;
         if Emit_Status /= Http_Client.Errors.Ok then
            return Emit_Status;
         end if;
         return Status;
      end;
   exception
      when others =>
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Http_Client.Errors.Internal_Error;
            return Http_Client.Errors.Internal_Error;
         end;
   end Open;

   overriding procedure Finalize (Item : in out Streaming_Response) is
      Ignored : constant Http_Client.Errors.Result_Status := Close (Item);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Finalize;

   function Metadata (Stream : Streaming_Response) return Http_Client.Responses.Response is
   begin
      return Stream.Meta;
   end Metadata;

   function Status_Code (Stream : Streaming_Response) return Http_Client.Types.Status_Code is
   begin
      return Http_Client.Responses.Status_Code (Stream.Meta);
   end Status_Code;

   function Reason_Phrase (Stream : Streaming_Response) return String is
   begin
      return Http_Client.Responses.Reason_Phrase (Stream.Meta);
   end Reason_Phrase;

   function Redirect_Count (Stream : Streaming_Response) return Natural is
   begin
      return Stream.Redirects_Followed;
   end Redirect_Count;

   function Retry_Attempt_Count (Stream : Streaming_Response) return Natural is
   begin
      return Stream.Retry_Attempts;
   end Retry_Attempt_Count;

   function Headers (Stream : Streaming_Response) return Http_Client.Headers.Header_List is
   begin
      return Http_Client.Responses.Headers (Stream.Meta);
   end Headers;

   function Effective_URI (Stream : Streaming_Response) return Http_Client.URI.URI_Reference is
   begin
      return Stream.URI_Value;
   end Effective_URI;

   function Is_Open (Stream : Streaming_Response) return Boolean is
   begin
      return Stream.Opened and then not Stream.Finished and then not Stream.Failed;
   end Is_Open;

   function End_Of_Body (Stream : Streaming_Response) return Boolean is
   begin
      return Stream.Finished;
   end End_Of_Body;

   function Last_Status (Stream : Streaming_Response) return Http_Client.Errors.Result_Status is
   begin
      return Stream.Last_Result;
   end Last_Status;


   function Fail_Chunked
     (Stream : in out Streaming_Response;
      Status : Http_Client.Errors.Result_Status;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
      pragma Unreferenced (Ignored);
   begin
      Last := 0;
      Stream.Failed := True;
      Stream.Last_Result := Status;
      return Status;
   end Fail_Chunked;

   function Ensure_Raw
     (Stream : in out Streaming_Response;
      Needed : Natural) return Http_Client.Errors.Result_Status
   is
      Buffer : String (1 .. Stream.Read_Quantum);
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      while Natural (Length (Stream.Lookahead)) < Needed loop
         Status := Read_Transport (Stream, Buffer, Count);
         if Status = Http_Client.Errors.Ok then
            if Count = 0 then
               return Http_Client.Errors.Read_Failed;
            end if;
            Append (Stream.Lookahead, Buffer (1 .. Count));
         elsif Status = Http_Client.Errors.End_Of_Stream then
            return Http_Client.Errors.Incomplete_Message;
         else
            return Status;
         end if;
      end loop;
      return Http_Client.Errors.Ok;
   end Ensure_Raw;

   function Ensure_Line
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status
   is
      Buffer : String (1 .. Stream.Read_Quantum);
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      loop
         declare
            LA : constant String := To_String (Stream.Lookahead);
         begin
            if LA'Length > 0 then
               declare
                  Line_End : constant Natural := Line_End_At (LA, LA'First);
                  Limit    : constant Natural :=
                    (if Stream.Chunk_Phase = Reading_Trailers then
                        Stream.Max_Trailer_Line_Size
                     else
                        Stream.Max_Trailer_Line_Size);
               begin
                  if Line_End = Natural'Last then
                     return Http_Client.Errors.Protocol_Error;
                  elsif Line_End /= 0 then
                     if Natural (Line_End - LA'First) > Limit then
                        return Http_Client.Errors.Header_Too_Large;
                     end if;
                     return Http_Client.Errors.Ok;
                  elsif LA'Length > Limit then
                     return Http_Client.Errors.Header_Too_Large;
                  end if;
               end;
            end if;
         end;

         Status := Read_Transport (Stream, Buffer, Count);
         if Status = Http_Client.Errors.Ok then
            if Count = 0 then
               return Http_Client.Errors.Read_Failed;
            end if;
            Append (Stream.Lookahead, Buffer (1 .. Count));
         elsif Status = Http_Client.Errors.End_Of_Stream then
            return Http_Client.Errors.Incomplete_Message;
         else
            return Status;
         end if;
      end loop;
   end Ensure_Line;

   procedure Consume_Raw
     (Stream : in out Streaming_Response;
      Count  : Natural)
   is
      LA : constant String := To_String (Stream.Lookahead);
   begin
      if Count >= LA'Length then
         Stream.Lookahead := Null_Unbounded_String;
      else
         Stream.Lookahead := To_Unbounded_String (LA (LA'First + Count .. LA'Last));
      end if;
   end Consume_Raw;

   function Read_Chunked
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      Last := 0;

      loop
         case Stream.Chunk_Phase is
            when Reading_Chunk_Size =>
               Status := Ensure_Line (Stream);
               if Status /= Http_Client.Errors.Ok then
                  return Fail_Chunked (Stream, Status, Last);
               end if;

               declare
                  LA       : constant String := To_String (Stream.Lookahead);
                  Line_End : constant Natural := Line_End_At (LA, LA'First);
                  Size     : Natural := 0;
               begin
                  Status := Parse_Chunk_Size_Line (LA (LA'First .. Line_End - 1), Size);
                  if Status /= Http_Client.Errors.Ok then
                     return Fail_Chunked (Stream, Status, Last);
                  end if;
                  Consume_Raw (Stream, Natural (Line_End - LA'First + 2));
                  Stream.Chunk_Remaining := Size;
                  if Size = 0 then
                     Stream.Chunk_Phase := Reading_Trailers;
                  else
                     Stream.Chunk_Phase := Reading_Chunk_Data;
                  end if;
               end;

            when Reading_Chunk_Data =>
               if Stream.Chunk_Remaining = 0 then
                  Stream.Chunk_Phase := Reading_Chunk_Data_CRLF;
               else
                  Status := Ensure_Raw (Stream, 1);
                  if Status /= Http_Client.Errors.Ok then
                     return Fail_Chunked (Stream, Status, Last);
                  end if;

                  declare
                     LA        : constant String := To_String (Stream.Lookahead);
                     Available : constant Natural := LA'Length;
                     Space     : constant Natural := Buffer'Length - Last;
                     Take      : constant Natural :=
                       Natural'Min (Natural'Min (Available, Stream.Chunk_Remaining), Space);
                  begin
                     if Take = 0 then
                        Stream.Last_Result := Http_Client.Errors.Ok;
                        return Http_Client.Errors.Ok;
                     end if;

                     if Take > Stream.Max_Body or else Stream.Body_Read > Stream.Max_Body - Take then
                        return Fail_Chunked (Stream, Http_Client.Errors.Response_Too_Large, Last);
                     end if;

                     Buffer (Buffer'First + Last .. Buffer'First + Last + Take - 1) :=
                       LA (LA'First .. LA'First + Take - 1);
                     Last := Last + Take;
                     Stream.Body_Read := Stream.Body_Read + Take;
                     Stream.Chunk_Remaining := Stream.Chunk_Remaining - Take;
                     Consume_Raw (Stream, Take);

                     declare
                        Emit_Status : constant Http_Client.Errors.Result_Status :=
                          Emit_Stream_Diagnostic
                            (Stream,
                             (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
                              Response_Byte_Count => Take,
                              Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                              others              => <>));
                     begin
                        if Emit_Status /= Http_Client.Errors.Ok then
                           return Fail_Chunked (Stream, Emit_Status, Last);
                        end if;
                     end;

                     if Last > 0 then
                        Stream.Last_Result := Http_Client.Errors.Ok;
                        return Http_Client.Errors.Ok;
                     end if;
                  end;
               end if;

            when Reading_Chunk_Data_CRLF =>
               Status := Ensure_Raw (Stream, 2);
               if Status /= Http_Client.Errors.Ok then
                  return Fail_Chunked (Stream, Status, Last);
               end if;
               declare
                  LA : constant String := To_String (Stream.Lookahead);
               begin
                  if LA (LA'First) /= CR or else LA (LA'First + 1) /= LF then
                     return Fail_Chunked (Stream, Http_Client.Errors.Protocol_Error, Last);
                  end if;
                  Consume_Raw (Stream, 2);
                  Stream.Chunk_Phase := Reading_Chunk_Size;
               end;

            when Reading_Trailers =>
               Status := Ensure_Line (Stream);
               if Status /= Http_Client.Errors.Ok then
                  return Fail_Chunked (Stream, Status, Last);
               end if;
               declare
                  LA       : constant String := To_String (Stream.Lookahead);
                  Line_End : constant Natural := Line_End_At (LA, LA'First);
               begin
                  if Line_End = LA'First then
                     Consume_Raw (Stream, 2);
                     Stream.Chunk_Phase := Chunk_Done;
                     Stream.Finished := True;
                     Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        return Http_Client.Errors.End_Of_Stream;
                     end;
                  else
                     declare
                        Line_Bytes : constant Natural := Natural (Line_End - LA'First + 2);
                     begin
                        if Line_Bytes > Stream.Max_Trailer_Line_Size
                          or else Line_Bytes > Stream.Max_Trailer_Size
                          or else Stream.Trailer_Read > Stream.Max_Trailer_Size - Line_Bytes
                        then
                           return Fail_Chunked (Stream, Http_Client.Errors.Header_Too_Large, Last);
                        end if;
                        Stream.Trailer_Read := Stream.Trailer_Read + Line_Bytes;
                     end;

                     declare
                        Line  : constant String := LA (LA'First .. Line_End - 1);
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
                           return Fail_Chunked (Stream, Http_Client.Errors.Invalid_Header, Last);
                        end if;
                     end;
                     Consume_Raw (Stream, Natural (Line_End - LA'First + 2));
                  end if;
               end;

            when Chunk_Done =>
               Stream.Finished := True;
               Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
               return Http_Client.Errors.End_Of_Stream;
         end case;
      end loop;
   exception
      when others =>
         return Fail_Chunked (Stream, Http_Client.Errors.Internal_Error, Last);
   end Read_Chunked;


   function Read_HTTP2_Entity_Some
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
      F      : Http_Client.HTTP2.Frames.Frame;
   begin
      Last := 0;

      if Buffer'Length = 0 then
         Stream.Last_Result := Http_Client.Errors.Invalid_Request;
         return Stream.Last_Result;
      end if;

      declare
         Pending : constant String := To_String (Stream.Lookahead);
      begin
         if Pending'Length > 0 then
            declare
               Take : constant Natural := Natural'Min (Buffer'Length, Pending'Length);
            begin
               Buffer (Buffer'First .. Buffer'First + Take - 1) :=
                 Pending (Pending'First .. Pending'First + Take - 1);
               Last := Take;
               if Take = Pending'Length then
                  Stream.Lookahead := Null_Unbounded_String;
               else
                  Stream.Lookahead :=
                    To_Unbounded_String (Pending (Pending'First + Take .. Pending'Last));
               end if;
               Stream.Last_Result := Http_Client.Errors.Ok;
               return Http_Client.Errors.Ok;
            end;
         end if;
      end;

      if Stream.Finished then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
            return Stream.Last_Result;
         end;
      end if;

      loop
         Status := H2_Read_Frame (Stream, F);
         if Status /= Http_Client.Errors.Ok then
            Stream.Failed := True;
            Stream.Last_Result := Status;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               return Status;
            end;
         end if;

         Status := Http_Client.HTTP2.Frames.Apply_Continuation_Rule
           (Stream.H2_Continuation, F.Header);
         if Status /= Http_Client.Errors.Ok then
            Stream.Failed := True;
            Stream.Last_Result := Status;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               return Status;
            end;
         end if;

         if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
            declare
               Peer : H2_Peer_Settings;
            begin
               Status := H2_Handle_Settings_Frame (Stream, F, Peer);
            end;
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               return Status;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
            Status := H2_Handle_Ping_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               return Status;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.DATA then
            Status := H2_Validate_Data_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               declare
                  Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                  pragma Unreferenced (Ignored);
               begin
                  return Status;
               end;
            end if;

            Status := H2_Consume_Data_Payload (Stream, Length (F.Payload));
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               return Status;
            end if;

            if H2_Has_Flag (F.Header.Flags, 16#01#) then
               Status := H2_Complete_Data_End_Stream (Stream);
               if Status /= Http_Client.Errors.Ok then
                  Stream.Failed := True;
                  Stream.Last_Result := Status;
                  return Stream.Last_Result;
               end if;
            end if;

            declare
               Payload : constant String := To_String (F.Payload);
            begin
               if Payload'Length = 0 then
                  if Stream.Finished then
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
                        return Stream.Last_Result;
                     end;
                  end if;
               else
                  declare
                     Take : constant Natural := Natural'Min (Buffer'Length, Payload'Length);
                  begin
                     Buffer (Buffer'First .. Buffer'First + Take - 1) :=
                       Payload (Payload'First .. Payload'First + Take - 1);
                     Last := Take;
                     if Take < Payload'Length then
                        Stream.Lookahead :=
                          To_Unbounded_String (Payload (Payload'First + Take .. Payload'Last));
                     end if;
                     Stream.Last_Result := Http_Client.Errors.Ok;
                     return Http_Client.Errors.Ok;
                  end;
               end if;
            end;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
            Status := H2_Validate_Trailer_Frame (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               return Status;
            end if;

            if Stream.H2_Content_Length_Set
              and then Stream.Body_Read /= Stream.H2_Content_Length
            then
               Stream.Failed := True;
               Stream.Last_Result := Http_Client.Errors.HTTP2_Protocol_Error;
               return Stream.Last_Result;
            end if;
            Stream.Finished := True;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
               return Stream.Last_Result;
            end;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.WINDOW_UPDATE then
            null;
         elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM
           or else F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY
           or else F.Header.Kind = Http_Client.HTTP2.Frames.PUSH_PROMISE
         then
            Status := H2_Terminal_Frame_Status (Stream, F);
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               return Stream.Last_Result;
            end if;
         else
            null;
         end if;
      end loop;
   exception
      when others =>
         Stream.Failed := True;
         Stream.Last_Result := Http_Client.Errors.Internal_Error;
         Last := 0;
         return Stream.Last_Result;
   end Read_HTTP2_Entity_Some;

   function Read_Entity_Some
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Want   : Natural;
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      Last := 0;
      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         Last := 0;
         return Cancel_Stream (Stream);
      end if;

      if Buffer'Length = 0 then
         Stream.Last_Result := Http_Client.Errors.Invalid_Request;
         return Stream.Last_Result;
      elsif Stream.Failed then
         return Stream.Last_Result;
      elsif Stream.Had_Response and then Stream.Finished then
         Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
         return Stream.Last_Result;
      elsif not Stream.Opened then
         Stream.Last_Result := Http_Client.Errors.Not_Connected;
         return Stream.Last_Result;
      end if;

      if Stream.Mode = Chunked then
         return Read_Chunked (Stream, Buffer, Last);
      end if;

      declare
         LA : constant String := To_String (Stream.Lookahead);
      begin
         if LA'Length > 0 then
            Want := Natural'Min (Buffer'Length, LA'Length);
            if Stream.Mode = Fixed_Length then
               Want := Natural'Min (Want, Stream.Remaining);
            end if;
            Buffer (Buffer'First .. Buffer'First + Want - 1) := LA (LA'First .. LA'First + Want - 1);
            Last := Want;
            if Want = LA'Length then
               Stream.Lookahead := Null_Unbounded_String;
            else
               Stream.Lookahead := To_Unbounded_String (LA (LA'First + Want .. LA'Last));
            end if;
            if Stream.Mode = Fixed_Length then
               Stream.Remaining := Stream.Remaining - Want;
               if Stream.Remaining = 0 then
                  Stream.Finished := True;
               end if;
            end if;
            Stream.Body_Read := Stream.Body_Read + Want;
            if Stream.Body_Read > Stream.Max_Body then
               Stream.Failed := True;
               Stream.Last_Result := Http_Client.Errors.Response_Too_Large;
               Status := Close (Stream);

               Last := 0;
               return Stream.Last_Result;
            end if;
            Stream.Last_Result := Http_Client.Errors.Ok;
            declare
               Emit_Status : constant Http_Client.Errors.Result_Status :=
                 Emit_Stream_Diagnostic
                   (Stream,
                    (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
                     Response_Byte_Count => Want,
                     Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                     others              => <>));
            begin
               if Emit_Status /= Http_Client.Errors.Ok then
                  declare
                     Ignored : constant Http_Client.Errors.Result_Status :=
                       Close (Stream);
                     pragma Unreferenced (Ignored);
                  begin
                     Stream.Failed := True;
                     Stream.Last_Result := Emit_Status;
                     Last := 0;
                     return Emit_Status;
                  end;
               end if;
            end;
            if Stream.Finished and then Stream.Opened then
               declare
                  Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            end if;
            return Http_Client.Errors.Ok;
         end if;
      end;

      if Stream.Mode = Fixed_Length then
         Want := Natural'Min (Buffer'Length, Stream.Remaining);
      else
         Want := Buffer'Length;
      end if;

      declare
         Temp : String (1 .. Want);
      begin
         Status := Read_Transport (Stream, Temp, Count);
         if Status = Http_Client.Errors.Ok then
            if Count = 0 then
               Status := Http_Client.Errors.Read_Failed;
            else
               if Count > Stream.Max_Body or else Stream.Body_Read > Stream.Max_Body - Count then
                  Stream.Failed := True;
                  Stream.Last_Result := Http_Client.Errors.Response_Too_Large;
                  declare
                     Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                     pragma Unreferenced (Ignored);
                  begin
                     Last := 0;
                     return Stream.Last_Result;
                  end;
               end if;
               Buffer (Buffer'First .. Buffer'First + Count - 1) := Temp (1 .. Count);
               Last := Count;
               Stream.Body_Read := Stream.Body_Read + Count;
               if Stream.Mode = Fixed_Length then
                  if Count > Stream.Remaining then
                     Stream.Failed := True;
                     Stream.Last_Result := Http_Client.Errors.Protocol_Error;
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        Last := 0;
                        return Stream.Last_Result;
                     end;
                  end if;
                  Stream.Remaining := Stream.Remaining - Count;
                  if Stream.Remaining = 0 then
                     Stream.Finished := True;
                  end if;
               end if;
               Stream.Last_Result := Http_Client.Errors.Ok;
               declare
                  Emit_Status : constant Http_Client.Errors.Result_Status :=
                    Emit_Stream_Diagnostic
                      (Stream,
                       (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
                        Response_Byte_Count => Count,
                        Protocol            => Http_Client.Diagnostics.Protocol_HTTP_1_1,
                        others              => <>));
               begin
                  if Emit_Status /= Http_Client.Errors.Ok then
                     declare
                        Ignored : constant Http_Client.Errors.Result_Status :=
                          Close (Stream);
                        pragma Unreferenced (Ignored);
                     begin
                        Stream.Failed := True;
                        Stream.Last_Result := Emit_Status;
                        Last := 0;
                        return Emit_Status;
                     end;
                  end if;
               end;
               if Stream.Finished and then Stream.Opened then
                  declare
                     Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               end if;
               return Http_Client.Errors.Ok;
            end if;
         end if;

         if Status = Http_Client.Errors.End_Of_Stream and then Stream.Mode = Close_Delimited then
            Stream.Finished := True;
            Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               return Http_Client.Errors.End_Of_Stream;
            end;
         elsif Status = Http_Client.Errors.End_Of_Stream and then Stream.Mode = Fixed_Length then
            Stream.Failed := True;
            Stream.Last_Result := Http_Client.Errors.Incomplete_Message;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               return Stream.Last_Result;
            end;
         else
            Stream.Failed := True;
            Stream.Last_Result := Status;
            declare
               Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
               pragma Unreferenced (Ignored);
            begin
               return Status;
            end;
         end if;
      end;
   exception
      when others =>
         Stream.Failed := True;
         Stream.Last_Result := Http_Client.Errors.Internal_Error;
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
            pragma Unreferenced (Ignored);
         begin
            Last := 0;
            return Stream.Last_Result;
         end;
   end Read_Entity_Some;


   function Read_Some
     (Stream : in out Streaming_Response;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Raw_Buffer : String (1 .. Stream.Read_Quantum);
      Raw_Last   : Natural := 0;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Last := 0;
      Status := Check_Cancelled (Stream.Cancellation);
      if Status /= Http_Client.Errors.Ok then
         return Cancel_Stream (Stream);
      end if;

      if not Stream.Decode_Active then
         if Stream.Protocol = Protocol_HTTP_2 then
            return Read_HTTP2_Entity_Some (Stream, Buffer, Last);
         else
            return Read_Entity_Some (Stream, Buffer, Last);
         end if;
      elsif Buffer'Length = 0 then
         Stream.Last_Result := Http_Client.Errors.Invalid_Request;
         return Stream.Last_Result;
      end if;

      loop
         Status := Check_Cancelled (Stream.Cancellation);
         if Status /= Http_Client.Errors.Ok then
            Last := 0;
            return Cancel_Stream (Stream);
         end if;

         declare
            Pending : constant String := To_String (Stream.Decode_Buffer);
         begin
            if Pending'Length > 0 then
               declare
                  Take : constant Natural := Natural'Min (Buffer'Length, Pending'Length);
               begin
                  Buffer (Buffer'First .. Buffer'First + Take - 1) :=
                    Pending (Pending'First .. Pending'First + Take - 1);
                  Last := Take;
                  if Take = Pending'Length then
                     Stream.Decode_Buffer := Null_Unbounded_String;
                  else
                     Stream.Decode_Buffer :=
                       To_Unbounded_String (Pending (Pending'First + Take .. Pending'Last));
                  end if;
                  Stream.Last_Result := Http_Client.Errors.Ok;
                  return Http_Client.Errors.Ok;
               end;
            end if;
         end;

         if Stream.Decode_Finished then
            Stream.Last_Result := Http_Client.Errors.End_Of_Stream;
            return Stream.Last_Result;
         end if;

         if Stream.Protocol = Protocol_HTTP_2 then
            Status := Read_HTTP2_Entity_Some (Stream, Raw_Buffer, Raw_Last);
         else
            Status := Read_Entity_Some (Stream, Raw_Buffer, Raw_Last);
         end if;
         if Status = Http_Client.Errors.Ok then
            if Raw_Last > 0 then
               Status := Append_Decoded
                 (Stream, Raw_Buffer (Raw_Buffer'First .. Raw_Buffer'First + Raw_Last - 1), False);
               if Status /= Http_Client.Errors.Ok then
                  Stream.Failed := True;
                  Stream.Last_Result := Status;
                  Free_Decoder (Stream);
                  declare
                     Ignored : constant Http_Client.Errors.Result_Status := Close (Stream);
                     pragma Unreferenced (Ignored);
                  begin
                     return Status;
                  end;
               end if;
            end if;
         elsif Status = Http_Client.Errors.End_Of_Stream then
            Status := Append_Decoded (Stream, "", True);
            Http_Client.Zlib_Decompression.Close (Stream.Decode_Context);
            Stream.Decode_Finished := True;
            if Status /= Http_Client.Errors.Ok then
               Stream.Failed := True;
               Stream.Last_Result := Status;
               Stream.Decode_Active := False;
               return Status;
            end if;
         else
            return Status;
         end if;
      end loop;
   exception
      when others =>
         Stream.Failed := True;
         Stream.Last_Result := Http_Client.Errors.Internal_Error;
         Last := 0;
         return Stream.Last_Result;
   end Read_Some;


   function Read_Some
     (Stream : in out Streaming_Response;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status
   is
      Text_Last : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      if Buffer'Length = 0 then
         Last := Buffer'First;
         Stream.Last_Result := Http_Client.Errors.Invalid_Request;
         return Stream.Last_Result;
      end if;

      declare
         Temp : String (1 .. Natural (Buffer'Length));
      begin
         Status := Read_Some (Stream, Temp, Text_Last);
         if Text_Last = 0 then
            Last := Buffer'First - 1;
         else
            for I in 0 .. Text_Last - 1 loop
               Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (I)) :=
                 Ada.Streams.Stream_Element
                   (Character'Pos (Temp (Temp'First + I)));
            end loop;
            Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Text_Last) - 1;
         end if;
         return Status;
      end;
   exception
      when others =>
         Stream.Failed := True;
         Stream.Last_Result := Http_Client.Errors.Internal_Error;
         if Buffer'Length = 0 then
            Last := Buffer'First;
         else
            Last := Buffer'First - 1;
         end if;
         return Stream.Last_Result;
   end Read_Some;

   function Close (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status is
      Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   begin
      if not (Stream.Decode_Active and then Stream.Finished and then not Stream.Decode_Finished) then
         Free_Decoder (Stream);
      end if;
      if not Stream.Opened then
         Stream.Transport := No_Transport;
         return Http_Client.Errors.Ok;
      end if;
      case Stream.Transport is
         when Plain_Transport =>
            Status := Http_Client.Transports.TCP.Close (Stream.TCP);
         when TLS_Transport =>
            Status := Http_Client.Transports.TLS.Close (Stream.TLS_Conn);
         when No_Transport =>
            Status := Http_Client.Errors.Ok;
      end case;
      Stream.Opened := False;
      Http_Client.Resources.Decrement
        (Http_Client.Resources.Streaming_Responses_Open);
      Stream.Transport := No_Transport;
      if Status /= Http_Client.Errors.Ok then
         Stream.Last_Result := Status;
      end if;

      if Stream.Had_Response then
         declare
            Emit_Status : Http_Client.Errors.Result_Status :=
              Emit_Stream_Diagnostic
                (Stream,
                 (Kind   => Http_Client.Diagnostics.Streaming_Response_Closed,
                  Result => Status,
                  others => <>));
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;

            Emit_Status := Emit_Stream_Diagnostic
              (Stream,
               (Kind   => Http_Client.Diagnostics.Request_Finish,
                Result => Status,
                others => <>));
            if Emit_Status /= Http_Client.Errors.Ok then
               return Emit_Status;
            end if;
         end;
      end if;

      return Status;
   end Close;

end Http_Client.Response_Streams;
