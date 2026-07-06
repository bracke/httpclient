with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Http_Client.Headers;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.Request_Bodies;
with Http_Client.Types; use Http_Client.Types;
with Http_Client.Transports.TLS;

package body Http_Client.HTTP2.Single_Stream is
   package H2_Common renames Http_Client.HTTP2_Execution_Common;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP2.HTTP2_Mode;
   use type Http_Client.HTTP2.Frames.Frame_Type;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Has_Flag (Flags : Natural; Mask : Natural) return Boolean
      renames H2_Common.Has_Flag;

   function Serialize_Frame_Bytes
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String
      renames H2_Common.Serialize_Frame;

   function Response_Frame_Payload_Is_Supported
     (Frame : Http_Client.HTTP2.Frames.Frame) return Boolean
   is
   begin
      if Frame.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
         return not Has_Flag (Frame.Header.Flags, 16#08#)
           and then not Has_Flag (Frame.Header.Flags, 16#20#);
      elsif Frame.Header.Kind = Http_Client.HTTP2.Frames.DATA then
         return not Has_Flag (Frame.Header.Flags, 16#08#);
      else
         return True;
      end if;
   end Response_Frame_Payload_Is_Supported;

   function Next_Frame
     (Data           : String;
      Position       : in out Positive;
      Max_Frame_Size : Natural;
      Frame          : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Header : Http_Client.HTTP2.Frames.Frame_Header;
      Status : Http_Client.Errors.Result_Status;
      Last   : Natural;
   begin
      if Position > Data'Last then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      if Position + 8 > Data'Last then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      Status := Http_Client.HTTP2.Frames.Parse_Header
        (Data (Position .. Position + 8), Header);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Frames.Validate_Header (Header, Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Last := Position + 8 + Header.Length;
      if Last > Data'Last then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      Frame.Header := Header;
      if Header.Length = 0 then
         Frame.Payload := Null_Unbounded_String;
      else
         Frame.Payload := To_Unbounded_String (Data (Position + 9 .. Last));
      end if;

      Status := Http_Client.HTTP2.Frames.Validate_Payload
        (Header, To_String (Frame.Payload));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Position := Last + 1;
      return Http_Client.Errors.Ok;
   end Next_Frame;

   function Decimal_Image (Code : Http_Client.Types.Status_Code) return String is
      N : constant Natural := Natural (Code);
   begin
      return String'
        (1 => Character'Val (Character'Pos ('0') + (N / 100) mod 10),
         2 => Character'Val (Character'Pos ('0') + (N / 10) mod 10),
         3 => Character'Val (Character'Pos ('0') + N mod 10));
   end Decimal_Image;

   function Parse_Natural (Text : String; Value : out Natural) return Boolean
      renames H2_Common.Parse_Natural;

   function Response_Body_Is_Disallowed
     (Request_Method : Http_Client.Types.Method_Name;
      Code           : Http_Client.Types.Status_Code) return Boolean
      renames H2_Common.Response_Body_Is_Disallowed;

   function Ensure_Content_Length_Header
     (Headers     : in out Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
      renames H2_Common.Ensure_Content_Length_Header;

   function Request_Content_Length_Is_Valid
     (Headers     : Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status
      renames H2_Common.Request_Content_Length_Is_Valid;

   function Collect_Request_Body
     (Req_Body  : Http_Client.Request_Bodies.Request_Body;
      Max_Bytes : Natural;
      Output    : out Unbounded_String)
      return Http_Client.Errors.Result_Status
      renames H2_Common.Collect_Request_Body;

   subtype Peer_Settings is H2_Common.Peer_Settings;

   function Serialize_Window_Update
     (Stream    : Natural;
      Increment : Natural) return String
      renames H2_Common.Serialize_Window_Update;

   function Parse_Peer_Settings
     (Payload : String;
      Peer    : in out Peer_Settings) return Http_Client.Errors.Result_Status
      renames H2_Common.Parse_Peer_Settings;

   function Encoded_Header_List_Size
     (Headers : Http_Client.Headers.Header_List;
      Size    : out Natural) return Boolean
      renames H2_Common.Encoded_Header_List_Size;

   function Serialize_Data_Frames
     (Payload            : String;
      Max_Frame_Size     : Natural;
      End_Stream_On_Last : Boolean := True) return String
      renames H2_Common.Serialize_Data_Frames;

   function Build_Response
     (Request_Method : Http_Client.Types.Method_Name;
      Headers        : Http_Client.Headers.Header_List;
      Body_Data      : String;
      Trailers       : Http_Client.Headers.Header_List;
      Response       : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      Code      : Http_Client.Types.Status_Code;
      Status    : Http_Client.Errors.Result_Status;
      Response_Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      CL        : Natural := 0;
      Has_CL    : Boolean;
      Bodyless  : Boolean := False;
   begin
      Response := Http_Client.Responses.Default_Response;
      Status := Http_Client.HTTP2.Mapping.Validate_Response_Headers (Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Mapping.Parse_Status (Headers, Code);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Bodyless := Response_Body_Is_Disallowed (Request_Method, Code);

      if Bodyless and then Body_Data'Length /= 0 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      Has_CL := Http_Client.Headers.Contains (Headers, "content-length");
      if Http_Client.Headers.Count (Headers, "content-length") > 1 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;
      if Has_CL then
         if not Parse_Natural (Http_Client.Headers.Get (Headers, "content-length"), CL) then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
         if (not Bodyless) and then CL /= Body_Data'Length then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
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

      Response := Http_Client.Responses.Copy_With_Trailers
        (Http_Client.Responses.From_Components
           (Version => Http_Client.Responses.HTTP_1_1,
            Status  => Code,
            Reason  => "",
            Headers => Response_Headers,
            Body_Text => Body_Data),
         Trailers);
      return Http_Client.Errors.Ok;
   end Build_Response;

   function Read_Exact_TLS
     (Connection : in out Http_Client.Transports.TLS.Connection;
      Buffer     : out String) return Http_Client.Errors.Result_Status
   is
      Offset : Natural := 0;
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
      Chunk  : String (1 .. Buffer'Length);
   begin
      while Offset < Buffer'Length loop
         Status := Http_Client.Transports.TLS.Read_Some
           (Connection, Chunk (1 .. Buffer'Length - Offset), Count);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Count = 0 then
            return Http_Client.Errors.Incomplete_Message;
         end if;
         Buffer (Buffer'First + Integer (Offset) ..
                 Buffer'First + Integer (Offset + Count) - 1) := Chunk (1 .. Count);
         Offset := Offset + Count;
      end loop;
      return Http_Client.Errors.Ok;
   end Read_Exact_TLS;

   function Read_Frame_TLS
     (Connection     : in out Http_Client.Transports.TLS.Connection;
      Max_Frame_Size : Natural;
      Frame          : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Header_Bytes : String (1 .. 9);
      Payload      : Unbounded_String := Null_Unbounded_String;
      Header       : Http_Client.HTTP2.Frames.Frame_Header;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Status := Read_Exact_TLS (Connection, Header_Bytes);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Frames.Parse_Header (Header_Bytes, Header);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Frames.Validate_Header (Header, Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Header.Length > 0 then
         declare
            Bytes : String (1 .. Integer (Header.Length));
         begin
            Status := Read_Exact_TLS (Connection, Bytes);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
            Payload := To_Unbounded_String (Bytes);
         end;
      end if;

      Status := Http_Client.HTTP2.Frames.Validate_Payload (Header, To_String (Payload));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Frame.Header := Header;
      Frame.Payload := Payload;
      return Http_Client.Errors.Ok;
   end Read_Frame_TLS;

   function Execute_TLS
     (Connection : in out Http_Client.Transports.TLS.Connection;
      Request    : Http_Client.Requests.Request;
      Options    : Http_Client.HTTP2.HTTP2_Options;
      Response   : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      Status        : Http_Client.Errors.Result_Status;
      H2_Headers    : Http_Client.Headers.Header_List;
      Enc           : Http_Client.HTTP2.HPACK.Encoder := Http_Client.HTTP2.HPACK.Create_Encoder;
      Dec           : Http_Client.HTTP2.HPACK.Decoder :=
        Http_Client.HTTP2.HPACK.Create_Decoder
          (Max_Dynamic_Table_Size => 4_096,
           Max_Header_List_Size   => Options.Max_Header_List_Size);
      Block         : Unbounded_String;
      Trailer_Block : Unbounded_String;
      Request_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Has_Request_Trailers : constant Boolean :=
        Http_Client.Request_Bodies.Has_Trailers (Request_Body);
      F             : Http_Client.HTTP2.Frames.Frame;
      Parsed        : Unbounded_String;
      Peer          : Peer_Settings;
      Header_Block  : Unbounded_String := Null_Unbounded_String;
      Resp_Headers  : Http_Client.Headers.Header_List;
      Body_Data          : Unbounded_String := Null_Unbounded_String;
      Resp_Trailers      : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Headers_Decoded          : Boolean := False;
      End_Stream_With_Headers  : Boolean := False;
      Continuation             : Http_Client.HTTP2.Frames.Continuation_State;
      Done                     : Boolean := False;
      Body_Buffer              : Unbounded_String := Null_Unbounded_String;
      Request_Header_List_Size : Natural := 0;
      Conn_Recv_Window         : Natural := Options.Initial_Connection_Window_Size;
      Stream_Recv_Window       : Natural := Options.Initial_Stream_Window_Size;
   begin
      Response := Http_Client.Responses.Default_Response;

      Status := Http_Client.HTTP2.Validate (Options);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Options.Mode = Http_Client.HTTP2.HTTP2_Disabled then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;
      Status := Collect_Request_Body
        (Request_Body, Options.Initial_Stream_Window_Size, Body_Buffer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Mapping.Build_Request_Headers (Request, H2_Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Ensure_Content_Length_Header (H2_Headers, Length (Body_Buffer));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Request_Content_Length_Is_Valid (H2_Headers, Length (Body_Buffer));
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
        (Connection,
         Http_Client.HTTP2.Client_Connection_Preface &
         Serialize_Frame_Bytes
           (Http_Client.HTTP2.Frames.SETTINGS, 0, 0,
            Http_Client.HTTP2.Settings.Initial_Settings_Payload
              (Initial_Window_Size  => Options.Initial_Stream_Window_Size,
               Max_Header_List_Size => Options.Max_Header_List_Size,
               Max_Frame_Size       => Options.Max_Frame_Size)) &
         (if Options.Initial_Connection_Window_Size > 65_535 then
            Serialize_Window_Update
              (0, Options.Initial_Connection_Window_Size - 65_535)
          else ""));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Read_Frame_TLS (Connection, Options.Max_Frame_Size, F);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if F.Header.Kind /= Http_Client.HTTP2.Frames.SETTINGS
        or else F.Header.Stream /= 0
        or else Has_Flag (F.Header.Flags, 16#01#)
      then
         return Http_Client.Errors.HTTP2_Settings_Error;
      end if;
      Status := Http_Client.HTTP2.Settings.Parse (To_String (F.Payload), Parsed);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Parse_Peer_Settings (To_String (F.Payload), Peer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if not Encoded_Header_List_Size (H2_Headers, Request_Header_List_Size)
        or else Request_Header_List_Size > Peer.Max_Header_List_Size
      then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      Http_Client.HTTP2.HPACK.Set_Peer_Dynamic_Table_Size
        (Enc, Peer.Header_Table_Size);
      Status := Http_Client.HTTP2.HPACK.Encode_Header_Block (Enc, H2_Headers, Block);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Length (Block) > Peer.Max_Frame_Size then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      if Has_Request_Trailers then
         Status := Http_Client.HTTP2.HPACK.Encode_Header_Block
           (Enc, Http_Client.Request_Bodies.Trailers (Request_Body), Trailer_Block);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Length (Trailer_Block) > Peer.Max_Frame_Size then
            return Http_Client.Errors.Header_Too_Large;
         end if;
      end if;
      if Length (Body_Buffer) > Peer.Initial_Window_Size then
         return Http_Client.Errors.HTTP2_Flow_Control_Error;
      end if;

      Status := Http_Client.Transports.TLS.Write_All
        (Connection,
         Serialize_Frame_Bytes (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, "") &
         Serialize_Frame_Bytes
           (Http_Client.HTTP2.Frames.HEADERS,
            (if Length (Body_Buffer) = 0 and then not Has_Request_Trailers then 16#05# else 16#04#),
            1,
            To_String (Block)) &
         Serialize_Data_Frames
           (To_String (Body_Buffer), Peer.Max_Frame_Size, not Has_Request_Trailers) &
         (if Has_Request_Trailers then
            Serialize_Frame_Bytes
              (Http_Client.HTTP2.Frames.HEADERS, 16#05#, 1, To_String (Trailer_Block))
          else ""));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      while not Done loop
         Status := Read_Frame_TLS (Connection, Options.Max_Frame_Size, F);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.HTTP2.Frames.Apply_Continuation_Rule
           (Continuation, F.Header);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if not Response_Frame_Payload_Is_Supported (F) then
            return Http_Client.Errors.HTTP2_Unsupported_Feature;
         end if;

         if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
            if Has_Flag (F.Header.Flags, 16#01#) then
               null;
            else
               Status := Http_Client.HTTP2.Settings.Parse (To_String (F.Payload), Parsed);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Parse_Peer_Settings (To_String (F.Payload), Peer);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Http_Client.HTTP2.HPACK.Set_Peer_Dynamic_Table_Size
                 (Enc, Peer.Header_Table_Size);
               Status := Http_Client.Transports.TLS.Write_All
                 (Connection, Serialize_Frame_Bytes
                    (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, ""));
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
            if not Has_Flag (F.Header.Flags, 16#01#) then
               Status := Http_Client.Transports.TLS.Write_All
                 (Connection,
                  Serialize_Frame_Bytes
                    (Http_Client.HTTP2.Frames.PING,
                     16#01#,
                     0,
                     To_String (F.Payload)));
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
            if F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif Headers_Decoded then
               declare
                  Trailer_Headers : Http_Client.Headers.Header_List;
               begin
                  if not Has_Flag (F.Header.Flags, 16#01#) then
                     return Http_Client.Errors.HTTP2_Stream_State_Error;
                  end if;
                  if not Has_Flag (F.Header.Flags, 16#04#) then
                     return Http_Client.Errors.HTTP2_Unsupported_Feature;
                  end if;
                  Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                    (Dec, To_String (F.Payload), Trailer_Headers);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Status := Http_Client.Headers.Validate_HTTP2_Trailers
                    (Trailer_Headers, Response => True);
                  if Status /= Http_Client.Errors.Ok then
                     return Http_Client.Errors.HTTP2_Header_Error;
                  end if;
                  Resp_Trailers := Trailer_Headers;
                  Done := True;
               end;
            else
               Header_Block := F.Payload;
               End_Stream_With_Headers := Has_Flag (F.Header.Flags, 16#01#);
               if Has_Flag (F.Header.Flags, 16#04#) then
                  Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                    (Dec, To_String (Header_Block), Resp_Headers);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Headers_Decoded := True;
                  if End_Stream_With_Headers then
                     Done := True;
                  end if;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION then
            if Headers_Decoded or else F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            Append (Header_Block, To_String (F.Payload));
            if Length (Header_Block) > Options.Max_Header_List_Size then
               return Http_Client.Errors.Header_Too_Large;
            end if;
            if Has_Flag (F.Header.Flags, 16#04#) then
               Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                 (Dec, To_String (Header_Block), Resp_Headers);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Headers_Decoded := True;
               if End_Stream_With_Headers then
                  Done := True;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.DATA then
            if not Headers_Decoded or else F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            if Length (F.Payload) > Conn_Recv_Window
              or else Length (F.Payload) > Stream_Recv_Window
            then
               return Http_Client.Errors.HTTP2_Flow_Control_Error;
            end if;
            Conn_Recv_Window := Conn_Recv_Window - Length (F.Payload);
            Stream_Recv_Window := Stream_Recv_Window - Length (F.Payload);
            if Length (F.Payload) > Options.Max_Body_Size
              or else Length (Body_Data) > Options.Max_Body_Size - Length (F.Payload)
            then
               return Http_Client.Errors.Response_Too_Large;
            end if;
            Append (Body_Data, To_String (F.Payload));
            if Length (F.Payload) > 0 then
               Status := Http_Client.Transports.TLS.Write_All
                 (Connection,
                  Serialize_Window_Update (0, Length (F.Payload)) &
                  Serialize_Window_Update (1, Length (F.Payload)));
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Conn_Recv_Window := Conn_Recv_Window + Length (F.Payload);
               Stream_Recv_Window := Stream_Recv_Window + Length (F.Payload);
            end if;
            if Has_Flag (F.Header.Flags, 16#01#) then
               Done := True;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.WINDOW_UPDATE then
            if F.Header.Stream /= 0 and then F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM then
            if F.Header.Stream = 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif F.Header.Stream /= 1 then
               null;
            else
               return Http_Client.HTTP2.Frames.RST_Stream_Status
                 (To_String (F.Payload));
            end if;
         elsif F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PUSH_PROMISE then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         else
            null;
         end if;
      end loop;

      return Build_Response
        (Http_Client.Requests.Method (Request), Resp_Headers, To_String (Body_Data),
         Resp_Trailers, Response);
   end Execute_TLS;

   function Execute_Scripted
     (Request      : Http_Client.Requests.Request;
      Server_Bytes : String;
      Options      : Http_Client.HTTP2.HTTP2_Options;
      Client_Bytes : out Ada.Strings.Unbounded.Unbounded_String;
      Response     : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      Status        : Http_Client.Errors.Result_Status;
      H2_Headers    : Http_Client.Headers.Header_List;
      Enc           : Http_Client.HTTP2.HPACK.Encoder := Http_Client.HTTP2.HPACK.Create_Encoder;
      Dec           : Http_Client.HTTP2.HPACK.Decoder :=
        Http_Client.HTTP2.HPACK.Create_Decoder
          (Max_Dynamic_Table_Size => 4_096,
           Max_Header_List_Size   => Options.Max_Header_List_Size);
      Block         : Unbounded_String;
      Trailer_Block : Unbounded_String;
      Request_Body  : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Has_Request_Trailers : constant Boolean :=
        Http_Client.Request_Bodies.Has_Trailers (Request_Body);
      Outp          : Unbounded_String := Null_Unbounded_String;
      Pos           : Positive := Server_Bytes'First;
      F             : Http_Client.HTTP2.Frames.Frame;
      Parsed        : Unbounded_String;
      Peer          : Peer_Settings;
      Header_Block  : Unbounded_String := Null_Unbounded_String;
      Resp_Headers  : Http_Client.Headers.Header_List;
      Body_Data          : Unbounded_String := Null_Unbounded_String;
      Resp_Trailers      : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Headers_Decoded          : Boolean := False;
      End_Stream_With_Headers  : Boolean := False;
      Continuation             : Http_Client.HTTP2.Frames.Continuation_State;
      Done                     : Boolean := False;
      Body_Buffer              : Unbounded_String := Null_Unbounded_String;
      Request_Header_List_Size : Natural := 0;
      Conn_Recv_Window         : Natural := Options.Initial_Connection_Window_Size;
      Stream_Recv_Window       : Natural := Options.Initial_Stream_Window_Size;
   begin
      Client_Bytes := Null_Unbounded_String;
      Response := Http_Client.Responses.Default_Response;

      Status := Http_Client.HTTP2.Validate (Options);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Options.Mode = Http_Client.HTTP2.HTTP2_Disabled then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;
      Status := Collect_Request_Body
        (Request_Body, Options.Initial_Stream_Window_Size, Body_Buffer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Mapping.Build_Request_Headers (Request, H2_Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Ensure_Content_Length_Header (H2_Headers, Length (Body_Buffer));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Request_Content_Length_Is_Valid (H2_Headers, Length (Body_Buffer));
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

      Append (Outp, Http_Client.HTTP2.Client_Connection_Preface);
      Append
        (Outp,
         Serialize_Frame_Bytes
           (Http_Client.HTTP2.Frames.SETTINGS, 0, 0,
            Http_Client.HTTP2.Settings.Initial_Settings_Payload
              (Initial_Window_Size  => Options.Initial_Stream_Window_Size,
               Max_Header_List_Size => Options.Max_Header_List_Size,
               Max_Frame_Size       => Options.Max_Frame_Size)) &
         (if Options.Initial_Connection_Window_Size > 65_535 then
            Serialize_Window_Update
              (0, Options.Initial_Connection_Window_Size - 65_535)
          else ""));

      Status := Next_Frame (Server_Bytes, Pos, Options.Max_Frame_Size, F);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if F.Header.Kind /= Http_Client.HTTP2.Frames.SETTINGS
        or else F.Header.Stream /= 0
        or else Has_Flag (F.Header.Flags, 16#01#)
      then
         return Http_Client.Errors.HTTP2_Settings_Error;
      end if;
      Status := Http_Client.HTTP2.Settings.Parse (To_String (F.Payload), Parsed);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Parse_Peer_Settings (To_String (F.Payload), Peer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if not Encoded_Header_List_Size (H2_Headers, Request_Header_List_Size)
        or else Request_Header_List_Size > Peer.Max_Header_List_Size
      then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      Http_Client.HTTP2.HPACK.Set_Peer_Dynamic_Table_Size
        (Enc, Peer.Header_Table_Size);
      Status := Http_Client.HTTP2.HPACK.Encode_Header_Block (Enc, H2_Headers, Block);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Length (Block) > Peer.Max_Frame_Size then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      if Has_Request_Trailers then
         Status := Http_Client.HTTP2.HPACK.Encode_Header_Block
           (Enc, Http_Client.Request_Bodies.Trailers (Request_Body), Trailer_Block);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Length (Trailer_Block) > Peer.Max_Frame_Size then
            return Http_Client.Errors.Header_Too_Large;
         end if;
      end if;
      if Length (Body_Buffer) > Peer.Initial_Window_Size then
         return Http_Client.Errors.HTTP2_Flow_Control_Error;
      end if;
      Append (Outp, Serialize_Frame_Bytes (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, ""));

      Append (Outp, Serialize_Frame_Bytes
        (Http_Client.HTTP2.Frames.HEADERS,
         (if Length (Body_Buffer) = 0 and then not Has_Request_Trailers then 16#05# else 16#04#),
         1,
         To_String (Block)));
      if Length (Body_Buffer) > 0 then
         Append
           (Outp,
            Serialize_Data_Frames
              (To_String (Body_Buffer), Peer.Max_Frame_Size, not Has_Request_Trailers));
      end if;
      if Has_Request_Trailers then
         Append
           (Outp,
            Serialize_Frame_Bytes
              (Http_Client.HTTP2.Frames.HEADERS, 16#05#, 1, To_String (Trailer_Block)));
      end if;

      while not Done loop
         Status := Next_Frame (Server_Bytes, Pos, Options.Max_Frame_Size, F);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Status := Http_Client.HTTP2.Frames.Apply_Continuation_Rule
           (Continuation, F.Header);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         if not Response_Frame_Payload_Is_Supported (F) then
            return Http_Client.Errors.HTTP2_Unsupported_Feature;
         end if;

         if F.Header.Kind = Http_Client.HTTP2.Frames.SETTINGS then
            if Has_Flag (F.Header.Flags, 16#01#) then
               null;
            else
               Status := Http_Client.HTTP2.Settings.Parse (To_String (F.Payload), Parsed);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Parse_Peer_Settings (To_String (F.Payload), Peer);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Http_Client.HTTP2.HPACK.Set_Peer_Dynamic_Table_Size
                 (Enc, Peer.Header_Table_Size);
               Append (Outp, Serialize_Frame_Bytes
                 (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, ""));
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PING then
            if not Has_Flag (F.Header.Flags, 16#01#) then
               Append
                 (Outp,
                  Serialize_Frame_Bytes
                    (Http_Client.HTTP2.Frames.PING,
                     16#01#,
                     0,
                     To_String (F.Payload)));
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
            if F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif Headers_Decoded then
               declare
                  Trailer_Headers : Http_Client.Headers.Header_List;
               begin
                  if not Has_Flag (F.Header.Flags, 16#01#) then
                     return Http_Client.Errors.HTTP2_Stream_State_Error;
                  end if;
                  if not Has_Flag (F.Header.Flags, 16#04#) then
                     return Http_Client.Errors.HTTP2_Unsupported_Feature;
                  end if;
                  Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                    (Dec, To_String (F.Payload), Trailer_Headers);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Status := Http_Client.Headers.Validate_HTTP2_Trailers
                    (Trailer_Headers, Response => True);
                  if Status /= Http_Client.Errors.Ok then
                     return Http_Client.Errors.HTTP2_Header_Error;
                  end if;
                  Resp_Trailers := Trailer_Headers;
                  Done := True;
               end;
            else
               Header_Block := F.Payload;
               End_Stream_With_Headers := Has_Flag (F.Header.Flags, 16#01#);
               if Has_Flag (F.Header.Flags, 16#04#) then
                  Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                    (Dec, To_String (Header_Block), Resp_Headers);
                  if Status /= Http_Client.Errors.Ok then
                     return Status;
                  end if;
                  Headers_Decoded := True;
                  if End_Stream_With_Headers then
                     Done := True;
                  end if;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION then
            if Headers_Decoded or else F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            Append (Header_Block, To_String (F.Payload));
            if Length (Header_Block) > Options.Max_Header_List_Size then
               return Http_Client.Errors.Header_Too_Large;
            end if;
            if Has_Flag (F.Header.Flags, 16#04#) then
               Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
                 (Dec, To_String (Header_Block), Resp_Headers);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Headers_Decoded := True;
               if End_Stream_With_Headers then
                  Done := True;
               end if;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.DATA then
            if not Headers_Decoded or else F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
            if Length (F.Payload) > Conn_Recv_Window
              or else Length (F.Payload) > Stream_Recv_Window
            then
               return Http_Client.Errors.HTTP2_Flow_Control_Error;
            end if;
            Conn_Recv_Window := Conn_Recv_Window - Length (F.Payload);
            Stream_Recv_Window := Stream_Recv_Window - Length (F.Payload);
            if Length (F.Payload) > Options.Max_Body_Size
              or else Length (Body_Data) > Options.Max_Body_Size - Length (F.Payload)
            then
               return Http_Client.Errors.Response_Too_Large;
            end if;
            Append (Body_Data, To_String (F.Payload));
            if Length (F.Payload) > 0 then
               Append
                 (Outp,
                  Serialize_Window_Update (0, Length (F.Payload)) &
                  Serialize_Window_Update (1, Length (F.Payload)));
               Conn_Recv_Window := Conn_Recv_Window + Length (F.Payload);
               Stream_Recv_Window := Stream_Recv_Window + Length (F.Payload);
            end if;
            if Has_Flag (F.Header.Flags, 16#01#) then
               Done := True;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.WINDOW_UPDATE then
            if F.Header.Stream /= 0 and then F.Header.Stream /= 1 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM then
            if F.Header.Stream = 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif F.Header.Stream /= 1 then
               null;
            else
               return Http_Client.HTTP2.Frames.RST_Stream_Status
                 (To_String (F.Payload));
            end if;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY then
            return Http_Client.Errors.HTTP2_Protocol_Error;

         elsif F.Header.Kind = Http_Client.HTTP2.Frames.PUSH_PROMISE then
            return Http_Client.Errors.HTTP2_Protocol_Error;

         else
            null;
         end if;
      end loop;

      Client_Bytes := Outp;
      return Build_Response
        (Http_Client.Requests.Method (Request), Resp_Headers, To_String (Body_Data),
         Resp_Trailers, Response);
   end Execute_Scripted;
end Http_Client.HTTP2.Single_Stream;
