with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.Requests;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Http_Client.URI;

procedure H2_Wire_Probe is
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP2.Selected_Protocol;
   use type Http_Client.HTTP2.Frames.Frame_Type;

   Max_Frame_Size : constant Natural := 16_384;

   function Hex_Digit (Value : Natural) return Character is
      Hex_Chars : constant String := "0123456789ABCDEF";
   begin
      return Hex_Chars (Value + 1);
   end Hex_Digit;

   function Hex_Byte (C : Character) return String is
      V      : constant Natural := Character'Pos (C);
      Result : String (1 .. 2);
   begin
      Result (1) := Hex_Digit (V / 16);
      Result (2) := Hex_Digit (V mod 16);
      return Result;
   end Hex_Byte;

   function Has_Flag (Flags : Natural; Flag : Natural) return Boolean is
   begin
      return (Flags / Flag) mod 2 = 1;
   end Has_Flag;

   function Frame_Name (Kind : Http_Client.HTTP2.Frames.Frame_Type) return String is
   begin
      case Kind is
         when Http_Client.HTTP2.Frames.DATA =>
            return "DATA";
         when Http_Client.HTTP2.Frames.HEADERS =>
            return "HEADERS";
         when Http_Client.HTTP2.Frames.PRIORITY =>
            return "PRIORITY";
         when Http_Client.HTTP2.Frames.RST_STREAM =>
            return "RST_STREAM";
         when Http_Client.HTTP2.Frames.SETTINGS =>
            return "SETTINGS";
         when Http_Client.HTTP2.Frames.PUSH_PROMISE =>
            return "PUSH_PROMISE";
         when Http_Client.HTTP2.Frames.PING =>
            return "PING";
         when Http_Client.HTTP2.Frames.GOAWAY =>
            return "GOAWAY";
         when Http_Client.HTTP2.Frames.WINDOW_UPDATE =>
            return "WINDOW_UPDATE";
         when Http_Client.HTTP2.Frames.CONTINUATION =>
            return "CONTINUATION";
         when Http_Client.HTTP2.Frames.UNKNOWN =>
            return "UNKNOWN";
      end case;
   end Frame_Name;

   procedure Dump_Hex (Prefix : String; Data : String) is
      Col : Natural := 0;
   begin
      Ada.Text_IO.Put_Line (Prefix & " bytes=" & Natural'Image (Data'Length));
      if Data'Length = 0 then
         return;
      end if;

      Ada.Text_IO.Put ("  ");
      for C of Data loop
         Ada.Text_IO.Put (Hex_Byte (C));
         Col := Col + 1;
         if Col mod 16 = 0 then
            Ada.Text_IO.New_Line;
            if Col < Data'Length then
               Ada.Text_IO.Put ("  ");
            end if;
         else
            Ada.Text_IO.Put (' ');
         end if;
      end loop;
      if Col mod 16 /= 0 then
         Ada.Text_IO.New_Line;
      end if;
   end Dump_Hex;

   procedure Dump_Frame (Direction : String; F : Http_Client.HTTP2.Frames.Frame) is
      Payload : constant String := To_String (F.Payload);
      Code    : Natural;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Ada.Text_IO.Put_Line
        (Direction & " frame kind=" & Frame_Name (F.Header.Kind) &
         " raw_type=" & Natural'Image (F.Header.Raw_Type) &
         " flags=0x" & Hex_Byte (Character'Val (F.Header.Flags)) &
         " stream=" & Natural'Image (F.Header.Stream) &
         " length=" & Natural'Image (F.Header.Length));
      Dump_Hex (Direction & " payload", Payload);

      if F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM then
         Code := Http_Client.HTTP2.Frames.RST_Stream_Error_Code (Payload);
         Status := Http_Client.HTTP2.Frames.RST_Stream_Status (Payload);
         Ada.Text_IO.Put_Line
           (Direction & " RST_STREAM error_code=" & Natural'Image (Code) &
            " mapped_status=" & Http_Client.Errors.Result_Status'Image (Status));
      end if;
   end Dump_Frame;

   function Read_Exact
     (Connection : in out Http_Client.Transports.TLS.Connection;
      Length     : Natural;
      Data       : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Buffer : String (1 .. 4_096);
      Count  : Natural;
      Need   : Natural := Length;
      Status : Http_Client.Errors.Result_Status;
   begin
      Data := Null_Unbounded_String;
      while Need > 0 loop
         Status := Http_Client.Transports.TLS.Read_Some
           (Connection, Buffer (1 .. Natural'Min (Buffer'Length, Need)), Count);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Count = 0 then
            return Http_Client.Errors.End_Of_Stream;
         end if;
         Append (Data, Buffer (1 .. Count));
         Need := Need - Count;
      end loop;
      return Http_Client.Errors.Ok;
   end Read_Exact;

   function Read_Frame
     (Connection : in out Http_Client.Transports.TLS.Connection;
      F          : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status
   is
      Header_Data  : Unbounded_String;
      Payload_Data : Unbounded_String;
      Header       : Http_Client.HTTP2.Frames.Frame_Header;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Status := Read_Exact (Connection, 9, Header_Data);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Dump_Hex ("<- frame-header", To_String (Header_Data));
      Status := Http_Client.HTTP2.Frames.Parse_Header (To_String (Header_Data), Header);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP2.Frames.Validate_Header (Header, Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Read_Exact (Connection, Header.Length, Payload_Data);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.HTTP2.Frames.Validate_Payload
        (Header, To_String (Payload_Data));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      F.Header := Header;
      F.Payload := Payload_Data;
      Dump_Frame ("<-", F);
      return Http_Client.Errors.Ok;
   end Read_Frame;

   function Serialize_Frame
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String
   is
      Header : constant Http_Client.HTTP2.Frames.Frame_Header :=
        (Length       => Payload'Length,
         Kind         => Kind,
         Raw_Type     => Http_Client.HTTP2.Frames.Type_Code (Kind),
         Flags        => Flags,
         Reserved_Bit => False,
         Stream       => Stream);
   begin
      return Http_Client.HTTP2.Frames.Serialize_Header (Header) & Payload;
   end Serialize_Frame;

   function B (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end B;

   function Serialize_Window_Update
     (Stream    : Natural;
      Increment : Natural) return String
   is
      Payload : String (1 .. 4);
   begin
      if Increment = 0 or else Increment > 16#7FFF_FFFF# then
         return "";
      end if;

      Payload (1) := B (Increment / 16#01_00_00_00#);
      Payload (2) := B (Increment / 16#00_01_00_00#);
      Payload (3) := B (Increment / 16#00_00_01_00#);
      Payload (4) := B (Increment);
      return Serialize_Frame
        (Http_Client.HTTP2.Frames.WINDOW_UPDATE, 0, Stream, Payload);
   end Serialize_Window_Update;

   procedure Send_Bytes
     (Connection : in out Http_Client.Transports.TLS.Connection;
      Label      : String;
      Data       : String;
      Status     : out Http_Client.Errors.Result_Status) is
   begin
      Dump_Hex ("-> " & Label, Data);
      Status := Http_Client.Transports.TLS.Write_All (Connection, Data);
      if Status /= Http_Client.Errors.Ok then
         Ada.Text_IO.Put_Line
           ("write status=" & Http_Client.Errors.Result_Status'Image (Status));
      end if;
   end Send_Bytes;

   procedure Print_Headers (Label : String; Headers : Http_Client.Headers.Header_List) is
   begin
      Ada.Text_IO.Put_Line (Label & " header_count=" & Natural'Image (Http_Client.Headers.Length (Headers)));
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         Ada.Text_IO.Put_Line
           ("  " & Http_Client.Headers.Name_At (Headers, I) & ": " &
            Http_Client.Headers.Value_At (Headers, I));
      end loop;
   end Print_Headers;

   URL_Text : Unbounded_String;
   URL      : Http_Client.URI.URI_Reference;
   Request  : Http_Client.Requests.Request;
   H2_Req   : Http_Client.Headers.Header_List;
   TLS_Opt  : Http_Client.Transports.TLS.TLS_Options :=
     Http_Client.Transports.TLS.Default_TLS_Options;
   Conn     : Http_Client.Transports.TLS.Connection;
   Enc      : Http_Client.HTTP2.HPACK.Encoder := Http_Client.HTTP2.HPACK.Create_Encoder;
   Dec      : Http_Client.HTTP2.HPACK.Decoder :=
     Http_Client.HTTP2.HPACK.Create_Decoder (Max_Header_List_Size => 65_536);
   Block    : Unbounded_String;
   Settings : constant String := Http_Client.HTTP2.Settings.Initial_Settings_Payload
     (Max_Header_List_Size => 65_536,
      Max_Frame_Size       => Max_Frame_Size);
   F        : Http_Client.HTTP2.Frames.Frame;
   Status   : Http_Client.Errors.Result_Status;
   Headers  : Http_Client.Headers.Header_List;
   Frames_Read : Natural := 0;
   Total_Data_Bytes : Natural := 0;
begin
   if Ada.Command_Line.Argument_Count < 1 then
      Ada.Text_IO.Put_Line ("usage: h2_wire_probe https://host/path [--insecure]");
      Ada.Text_IO.Put_Line ("prints TLS ALPN plus raw HTTP/2 bytes and parsed frame summaries");
      return;
   end if;

   URL_Text := To_Unbounded_String (Ada.Command_Line.Argument (1));
   Status := Http_Client.URI.Parse (To_String (URL_Text), URL);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("URI parse status=" & Http_Client.Errors.Result_Status'Image (Status));
      return;
   end if;
   if not Http_Client.URI.Requires_TLS (URL) then
      Ada.Text_IO.Put_Line ("only https:// URLs are supported by this TLS h2 probe");
      return;
   end if;

   TLS_Opt.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Required;
   TLS_Opt.Timeouts :=
     (Connect => Http_Client.Transports.TCP.Timeout_Milliseconds (5_000),
      Read    => Http_Client.Transports.TCP.Timeout_Milliseconds (5_000),
      Write   => Http_Client.Transports.TCP.Timeout_Milliseconds (5_000));
   if Ada.Command_Line.Argument_Count >= 2
     and then Ada.Command_Line.Argument (2) = "--insecure"
   then
      TLS_Opt.Disable_Certificate_Verification := True;
   end if;

   Status := Http_Client.Requests.Create
     (Http_Client.Types.GET, URL, Request, Payload => "");
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("request create status=" & Http_Client.Errors.Result_Status'Image (Status));
      return;
   end if;

   Status := Http_Client.HTTP2.Mapping.Build_Request_Headers (Request, H2_Req);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("h2 mapping status=" & Http_Client.Errors.Result_Status'Image (Status));
      return;
   end if;
   Print_Headers ("request", H2_Req);

   Status := Http_Client.HTTP2.HPACK.Encode_Header_Block (Enc, H2_Req, Block);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("hpack encode status=" & Http_Client.Errors.Result_Status'Image (Status));
      return;
   end if;
   Dump_Hex ("request HPACK block", To_String (Block));

   Ada.Text_IO.Put_Line
     ("opening TLS host=" & Http_Client.URI.Host (URL) &
      " port=" & Natural'Image (Http_Client.URI.Effective_Port (URL)) &
      " ALPN=h2 required");
   Status := Http_Client.Transports.TLS.Open
     (Conn, Http_Client.URI.Host (URL), Http_Client.URI.Effective_Port (URL), TLS_Opt);
   Ada.Text_IO.Put_Line ("tls open status=" & Http_Client.Errors.Result_Status'Image (Status));
   if Status /= Http_Client.Errors.Ok then
      return;
   end if;
   Ada.Text_IO.Put_Line
     ("selected ALPN=" & Http_Client.HTTP2.Selected_Protocol'Image
        (Http_Client.Transports.TLS.Selected_ALPN (Conn)));
   if Http_Client.Transports.TLS.Selected_ALPN (Conn) /= Http_Client.HTTP2.Protocol_HTTP_2 then
      Ada.Text_IO.Put_Line ("server did not negotiate h2");
      return;
   end if;

   Send_Bytes (Conn, "client preface", Http_Client.HTTP2.Client_Connection_Preface, Status);
   if Status /= Http_Client.Errors.Ok then
      return;
   end if;
   Send_Bytes
     (Conn, "SETTINGS", Serialize_Frame (Http_Client.HTTP2.Frames.SETTINGS, 0, 0, Settings), Status);
   if Status /= Http_Client.Errors.Ok then
      return;
   end if;

   Status := Read_Frame (Conn, F);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("read first frame status=" & Http_Client.Errors.Result_Status'Image (Status));
      return;
   end if;
   if F.Header.Kind /= Http_Client.HTTP2.Frames.SETTINGS or else F.Header.Stream /= 0 then
      Ada.Text_IO.Put_Line ("first frame was not connection SETTINGS; stopping");
      return;
   end if;

   Send_Bytes
     (Conn, "SETTINGS ack", Serialize_Frame (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, ""), Status);
   if Status /= Http_Client.Errors.Ok then
      return;
   end if;
   Send_Bytes
     (Conn,
      "HEADERS stream=1 END_HEADERS|END_STREAM",
      Serialize_Frame (Http_Client.HTTP2.Frames.HEADERS, 16#05#, 1, To_String (Block)),
      Status);
   if Status /= Http_Client.Errors.Ok then
      return;
   end if;

   loop
      exit when Frames_Read >= 20;
      Status := Read_Frame (Conn, F);
      if Status /= Http_Client.Errors.Ok then
         Ada.Text_IO.Put_Line ("read frame status=" & Http_Client.Errors.Result_Status'Image (Status));
         exit;
      end if;
      Frames_Read := Frames_Read + 1;

      if F.Header.Kind = Http_Client.HTTP2.Frames.HEADERS then
         Status := Http_Client.HTTP2.HPACK.Decode_Header_Block
           (Dec, To_String (F.Payload), Headers);
         Ada.Text_IO.Put_Line ("response hpack status=" & Http_Client.Errors.Result_Status'Image (Status));
         if Status = Http_Client.Errors.Ok then
            Print_Headers ("response", Headers);
         end if;
      elsif F.Header.Kind = Http_Client.HTTP2.Frames.DATA then
         Total_Data_Bytes := Total_Data_Bytes + Natural (F.Header.Length);
         if F.Header.Length > 0 then
            Send_Bytes
              (Conn,
               "WINDOW_UPDATE connection after DATA",
               Serialize_Window_Update (0, Natural (F.Header.Length)),
               Status);
            if Status /= Http_Client.Errors.Ok then
               exit;
            end if;
            if F.Header.Stream /= 0 then
               Send_Bytes
                 (Conn,
                  "WINDOW_UPDATE stream after DATA",
                  Serialize_Window_Update
                    (Natural (F.Header.Stream), Natural (F.Header.Length)),
                  Status);
               if Status /= Http_Client.Errors.Ok then
                  exit;
               end if;
            end if;
         end if;
      end if;

      exit when F.Header.Stream = 1 and then Has_Flag (F.Header.Flags, 16#01#);
      exit when F.Header.Kind = Http_Client.HTTP2.Frames.RST_STREAM;
      exit when F.Header.Kind = Http_Client.HTTP2.Frames.GOAWAY;
   end loop;

   Ada.Text_IO.Put_Line ("total DATA bytes=" & Natural'Image (Total_Data_Bytes));
   Status := Http_Client.Transports.TLS.Close (Conn);
   Ada.Text_IO.Put_Line ("close status=" & Http_Client.Errors.Result_Status'Image (Status));
end H2_Wire_Probe;
