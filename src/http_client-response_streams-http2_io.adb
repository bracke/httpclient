with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Http_Client.Headers;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Settings;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.Transports.TLS;

package body Http_Client.Response_Streams.HTTP2_IO is
   package H2_Common renames Http_Client.HTTP2_Execution_Common;

   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP2.Frames.Frame_Type;

   function Read_Exact
     (Stream : in out Streaming_Response;
      Buffer : out String) return Http_Client.Errors.Result_Status
   is
      Offset : Natural := 0;
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
      Chunk  : String (1 .. Buffer'Length);
   begin
      while Offset < Buffer'Length loop
         Status := Http_Client.Transports.TLS.Read_Some
           (Stream.TLS_Conn, Chunk (1 .. Buffer'Length - Offset), Count);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         elsif Count = 0 then
            return Http_Client.Errors.Incomplete_Message;
         end if;

         Buffer (Buffer'First + Integer (Offset) ..
                 Buffer'First + Integer (Offset + Count) - 1) := Chunk (1 .. Count);
         Offset := Offset + Count;
      end loop;
      return Http_Client.Errors.Ok;
   end Read_Exact;

   function Read_Frame
     (Stream : in out Streaming_Response;
      Frame  : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Header_Bytes : String (1 .. 9);
      Header       : Http_Client.HTTP2.Frames.Frame_Header;
      Payload      : Unbounded_String := Null_Unbounded_String;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Status := Read_Exact (Stream, Header_Bytes);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Frames.Parse_Header (Header_Bytes, Header);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Frames.Validate_Header
        (Header, Stream.H2_Peer_Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Header.Length > 0 then
         declare
            Bytes : String (1 .. Integer (Header.Length));
         begin
            Status := Read_Exact (Stream, Bytes);
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
   end Read_Frame;

   function Try_Read_Frame
     (Stream     : in out Streaming_Response;
      Timeout_MS : Http_Client.Transports.TCP.Timeout_Milliseconds;
      Frame      : out Http_Client.HTTP2.Frames.Frame;
      Got_Frame  : out Boolean) return Http_Client.Errors.Result_Status
   is
      Header_Bytes : String (1 .. 9);
      Header       : Http_Client.HTTP2.Frames.Frame_Header;
      Payload      : Unbounded_String := Null_Unbounded_String;
      Status       : Http_Client.Errors.Result_Status;
      Count        : Natural := 0;
      Offset       : Natural := 0;
   begin
      Got_Frame := False;
      Frame := (Header => <>, Payload => Null_Unbounded_String);

      while Offset < Header_Bytes'Length loop
         declare
            Chunk : String (1 .. Header_Bytes'Length - Offset);
         begin
            if Offset = 0 then
               Status := Http_Client.Transports.TLS.Read_Some_With_Timeout
                 (Stream.TLS_Conn, Chunk, Count, Timeout_MS);
               if Status = Http_Client.Errors.Timeout then
                  return Http_Client.Errors.Ok;
               end if;
            else
               Status := Http_Client.Transports.TLS.Read_Some
                 (Stream.TLS_Conn, Chunk, Count);
            end if;

            if Status /= Http_Client.Errors.Ok then
               return Status;
            elsif Count = 0 then
               return Http_Client.Errors.Incomplete_Message;
            end if;

            Header_Bytes
              (Header_Bytes'First + Integer (Offset) ..
               Header_Bytes'First + Integer (Offset + Count) - 1) :=
                 Chunk (Chunk'First .. Chunk'First + Count - 1);
            Offset := Offset + Count;
         end;
      end loop;

      Status := Http_Client.HTTP2.Frames.Parse_Header (Header_Bytes, Header);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Frames.Validate_Header
        (Header, Stream.H2_Peer_Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Header.Length > 0 then
         declare
            Bytes : String (1 .. Integer (Header.Length));
         begin
            Status := Read_Exact (Stream, Bytes);
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
      Got_Frame := True;
      return Http_Client.Errors.Ok;
   end Try_Read_Frame;


   function Write_Settings_Ack
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Transports.TLS.Write_All
        (Stream.TLS_Conn,
         H2_Common.Serialize_Frame
           (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, ""));
   end Write_Settings_Ack;

   function Write_Ping_Ack
     (Stream  : in out Streaming_Response;
      Payload : String) return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Transports.TLS.Write_All
        (Stream.TLS_Conn,
         H2_Common.Serialize_Frame
           (Http_Client.HTTP2.Frames.PING, 16#01#, 0, Payload));
   end Write_Ping_Ack;

   function Write_Data_Window_Update
     (Stream    : in out Streaming_Response;
      Stream_ID : Natural;
      Increment : Natural) return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Transports.TLS.Write_All
        (Stream.TLS_Conn,
         H2_Common.Serialize_Window_Update (0, Increment) &
         H2_Common.Serialize_Window_Update (Stream_ID, Increment));
   end Write_Data_Window_Update;

   function Handle_Settings_Frame
     (Stream                     : in out Streaming_Response;
      Frame                      : Http_Client.HTTP2.Frames.Frame;
      Peer                       : in out H2_Common.Peer_Settings;
      Update_Read_Max_Frame_Size : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
      Parsed : Unbounded_String := Null_Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
   begin
      if H2_Common.Has_Flag (Frame.Header.Flags, 16#01#) then
         return Http_Client.Errors.Ok;
      end if;

      Status := Http_Client.HTTP2.Settings.Parse (To_String (Frame.Payload), Parsed);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := H2_Common.Parse_Peer_Settings (To_String (Frame.Payload), Peer);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Update_Read_Max_Frame_Size then
         Stream.H2_Peer_Max_Frame_Size := Peer.Max_Frame_Size;
      end if;

      return Write_Settings_Ack (Stream);
   end Handle_Settings_Frame;

   function Handle_Ping_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
   begin
      if H2_Common.Has_Flag (Frame.Header.Flags, 16#01#) then
         return Http_Client.Errors.Ok;
      end if;

      return Write_Ping_Ack (Stream, To_String (Frame.Payload));
   end Handle_Ping_Frame;

   function Window_Update_Increment
     (Frame     : Http_Client.HTTP2.Frames.Frame;
      Increment : out Natural) return Http_Client.Errors.Result_Status
   is
      Payload : constant String := To_String (Frame.Payload);
   begin
      Increment := 0;
      if Payload'Length /= 4 then
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      Increment := H2_Common.U32_Value
        (Payload (Payload'First), Payload (Payload'First + 1),
         Payload (Payload'First + 2), Payload (Payload'First + 3));
      if Increment = 0 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      return Http_Client.Errors.Ok;
   end Window_Update_Increment;

   function Validate_Data_Frame
     (Stream : Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Payload_Length : constant Natural := Length (Frame.Payload);
   begin
      if Frame.Header.Stream /= Stream.H2_Stream or else not Stream.H2_Headers_Done then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      elsif Stream.H2_Bodyless and then Payload_Length /= 0 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      elsif Payload_Length > Stream.H2_Conn_Window
        or else Payload_Length > Stream.H2_Stream_Window
      then
         return Http_Client.Errors.HTTP2_Flow_Control_Error;
      elsif Payload_Length > Stream.Max_Body - Stream.Body_Read then
         return Http_Client.Errors.Response_Too_Large;
      elsif Stream.H2_Content_Length_Set
        and then Payload_Length > Stream.H2_Content_Length - Stream.Body_Read
      then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      return Http_Client.Errors.Ok;
   end Validate_Data_Frame;

   function Consume_Data_Payload
     (Stream         : in out Streaming_Response;
      Payload_Length : Natural) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      Stream.H2_Conn_Window := Stream.H2_Conn_Window - Payload_Length;
      Stream.H2_Stream_Window := Stream.H2_Stream_Window - Payload_Length;
      Stream.Body_Read := Stream.Body_Read + Payload_Length;

      if Payload_Length > 0 then
         Status := Write_Data_Window_Update
           (Stream, Natural (Stream.H2_Stream), Payload_Length);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         Stream.H2_Conn_Window := Stream.H2_Conn_Window + Payload_Length;
         Stream.H2_Stream_Window := Stream.H2_Stream_Window + Payload_Length;
      end if;

      return Http_Client.Errors.Ok;
   end Consume_Data_Payload;

   function Complete_Data_End_Stream
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status
   is
   begin
      if Stream.H2_Content_Length_Set
        and then Stream.Body_Read /= Stream.H2_Content_Length
      then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      Stream.Finished := True;
      return Http_Client.Errors.Ok;
   end Complete_Data_End_Stream;

   function Validate_Trailer_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Trailer_Headers : Http_Client.Headers.Header_List;
      Status          : Http_Client.Errors.Result_Status;
   begin
      if Frame.Header.Stream /= Stream.H2_Stream
        or else not H2_Common.Has_Flag (Frame.Header.Flags, 16#01#)
        or else not H2_Common.Has_Flag (Frame.Header.Flags, 16#04#)
      then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
        (Stream.H2_Decoder, To_String (Frame.Payload), Trailer_Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Validate_HTTP2_Trailers
        (Trailer_Headers, Response => True);
      if Status /= Http_Client.Errors.Ok then
         return Http_Client.Errors.HTTP2_Header_Error;
      end if;

      return Http_Client.Errors.Ok;
   end Validate_Trailer_Frame;

   function Terminal_Frame_Status
     (Stream           : Streaming_Response;
      Frame            : Http_Client.HTTP2.Frames.Frame;
      Data_Is_Protocol : Boolean := False) return Http_Client.Errors.Result_Status
   is
   begin
      if Frame.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM then
         if Frame.Header.Stream = Stream.H2_Stream then
            return Http_Client.HTTP2.Frames.RST_Stream_Status (To_String (Frame.Payload));
         else
            return Http_Client.Errors.Ok;
         end if;
      elsif Frame.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY
        or else Frame.Header.Kind = Http_Client.HTTP2.Frames.PUSH_PROMISE
        or else (Data_Is_Protocol and then Frame.Header.Kind = Http_Client.HTTP2.Frames.DATA)
      then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Terminal_Frame_Status;

   function Handle_Response_Header_Block_Frame
     (Stream               : in out Streaming_Response;
      Frame                : Http_Client.HTTP2.Frames.Frame;
      Max_Header_List_Size : Natural;
      Header_Block         : in out Unbounded_String;
      End_Stream           : in out Boolean;
      Headers              : out Http_Client.Headers.Header_List;
      Complete             : out Boolean) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      Headers := Http_Client.Headers.Empty;
      Complete := False;

      if Frame.Header.Stream /= Stream.H2_Stream then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      if Frame.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
         Header_Block := Frame.Payload;
         End_Stream := H2_Common.Has_Flag (Frame.Header.Flags, 16#01#);
      elsif Frame.Header.Kind = Http_Client.HTTP2.Frames.CONTINUATION then
         Append (Header_Block, To_String (Frame.Payload));
         if Length (Header_Block) > Max_Header_List_Size then
            return Http_Client.Errors.Header_Too_Large;
         end if;
      else
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      if H2_Common.Has_Flag (Frame.Header.Flags, 16#04#) then
         Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
           (Stream.H2_Decoder, To_String (Header_Block), Headers);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         Complete := True;
      end if;

      return Http_Client.Errors.Ok;
   end Handle_Response_Header_Block_Frame;

end Http_Client.Response_Streams.HTTP2_IO;
