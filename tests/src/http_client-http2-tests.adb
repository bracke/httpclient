with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Body_Streams;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.HTTP2.Uploads;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.HTTP2.Single_Stream;
with Http_Client.HTTP2.Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Frames;
with Http_Client.HTTP3.QPACK;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.HTTP2.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP2.Frames.Frame_Type;
   use type Http_Client.HTTP2.Streams.Stream_State;

   Diagnostic_Callback_Count : Natural := 0;
   Diagnostic_Fail_Next      : Boolean := False;

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status) is
      pragma Unreferenced (Event);
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;

      if Diagnostic_Fail_Next then
         Diagnostic_Fail_Next := False;
         Status := Http_Client.Errors.Internal_Error;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Capture_Diagnostic;

   function Diagnostic_Test_Time return Ada.Calendar.Time is
   begin
      return Ada.Calendar.Time_Of (2026, 5, 13, 12.0);
   end Diagnostic_Test_Time;

   procedure Assert_Parse_Ok
     (Text    : String;
      Item    : out Http_Client.URI.URI_Reference;
      Message : String);

   procedure Assert_Parse_Status
     (Text     : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_Header_Status
     (Actual : Http_Client.Errors.Result_Status; Message : String) is
   begin
      Assert (Actual = Http_Client.Errors.Ok, Message);
   end Assert_Header_Status;

   function Hex_Nibble (C : Character) return Natural is
   begin
      case C is
         when '0' .. '9' =>
            return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' =>
            return 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' =>
            return 10 + Character'Pos (C) - Character'Pos ('A');
         when others =>
            return 0;
      end case;
   end Hex_Nibble;

   function Hex_Bytes (Hex : String) return String is
      Result : String (1 .. Hex'Length / 2);
      Out_I  : Positive := Result'First;
      In_I   : Positive := Hex'First;
   begin
      while In_I < Hex'Last loop
         Result (Out_I) := Character'Val
           (Hex_Nibble (Hex (In_I)) * 16 + Hex_Nibble (Hex (In_I + 1)));
         Out_I := Out_I + 1;
         In_I := In_I + 2;
      end loop;
      return Result;
   end Hex_Bytes;

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   procedure Assert_Serialize_Status
     (Request  : Http_Client.Requests.Request;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String;
      Output   : out Ada.Strings.Unbounded.Unbounded_String)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.HTTP1.Serialize_Request (Request, Output);
   begin
      Assert
        (Status = Expected,
         Message & " should return expected serialization status");
   end Assert_Serialize_Status;

   procedure Assert_Serialize_Ok
     (Request  : Http_Client.Requests.Request;
      Expected : String;
      Message  : String)
   is

      Output : Unbounded_String;
   begin
      Assert_Serialize_Status
        (Request  => Request,
         Expected => Http_Client.Errors.Ok,
         Message  => Message,
         Output   => Output);

      Assert
        (To_String (Output) = Expected,
         Message & " exact serialized output mismatch");
   end Assert_Serialize_Ok;

   procedure Assert_Parse_Ok
     (Text    : String;
      Item    : out Http_Client.URI.URI_Reference;
      Message : String)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.URI.Parse (Text, Item);
   begin
      Assert
        (Status = Http_Client.Errors.Ok,
         Message & " should parse successfully");

      Assert
        (Http_Client.URI.Is_Parsed (Item),
         Message & " should produce a parsed URI value");
   end Assert_Parse_Ok;

   procedure Assert_Parse_Status
     (Text     : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Item   : Http_Client.URI.URI_Reference;
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.URI.Parse (Text, Item);
   begin
      Assert
        (Status = Expected,
         Message & " should return expected URI parse status");
   end Assert_Parse_Status;

   procedure Build_Cache_Request
     (URL           : String;
      Request       : out Http_Client.Requests.Request;
      Extra_Headers : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty)
   is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse (URL, URI);
      Assert (Status = Http_Client.Errors.Ok, "cache test URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method  => Http_Client.Types.GET,
           URI     => URI,
           Item    => Request,
           Headers => Extra_Headers);
      Assert
        (Status = Http_Client.Errors.Ok, "cache test request should build");
   end Build_Cache_Request;

   procedure Build_Cache_Response
     (Raw : String; Response : out Http_Client.Responses.Response)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.Responses.Parse_Response (Raw, Response);
   begin
      Assert
        (Status = Http_Client.Errors.Ok,
         "cache test response should parse: "
         & Http_Client.Errors.Result_Status'Image (Status));
   end Build_Cache_Response;

   procedure Remove_Test_Directory (Path : String) is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Start_Search (Search, Path, "*");
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
               Ada.Directories.Delete_File (Ada.Directories.Full_Name (Ent));
            end if;
         end loop;
         Ada.Directories.End_Search (Search);
         Ada.Directories.Delete_Directory (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_Test_Directory;

   function Count_Test_Files (Path : String; Pattern : String) return Natural
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Count  : Natural := 0;
   begin
      if not Ada.Directories.Exists (Path) then
         return 0;
      end if;

      Ada.Directories.Start_Search (Search, Path, Pattern);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
            Count := Count + 1;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return Count;
   exception
      when others =>
         return 0;
   end Count_Test_Files;

   function First_Test_File (Path : String; Pattern : String) return String is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;

      Ada.Directories.Start_Search (Search, Path, Pattern);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
            declare
               Name : constant String := Ada.Directories.Simple_Name (Ent);
            begin
               Ada.Directories.End_Search (Search);
               return Name;
            end;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return "";
   exception
      when others =>
         return "";
   end First_Test_File;

   function Test_Raw_Key return String is
   begin
      return "0123456789abcdef0123456789abcdef";
   end Test_Raw_Key;

   function File_Contains_Text (Path : String; Marker : String) return Boolean
   is
      F    : Ada.Streams.Stream_IO.File_Type;
      Size : Ada.Streams.Stream_IO.Count;
   begin
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (F);
      if Size = 0 then
         Ada.Streams.Stream_IO.Close (F);
         return Marker'Length = 0;
      end if;
      declare
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         Text : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Streams.Stream_IO.Read (F, Data, Last);
         Ada.Streams.Stream_IO.Close (F);
         for I in Data'First .. Last loop
            Ada.Strings.Unbounded.Append
              (Text, Character'Val (Natural (Data (I))));
         end loop;
         return
           Ada.Strings.Fixed.Index
             (Ada.Strings.Unbounded.To_String (Text), Marker)
           /= 0;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         return False;
   end File_Contains_Text;

   function Any_Cache_File_Contains
     (Path : String; Marker : String) return Boolean
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      Ada.Directories.Start_Search (Search, Path, "*");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File
           and then
             File_Contains_Text (Ada.Directories.Full_Name (Ent), Marker)
         then
            Ada.Directories.End_Search (Search);
            return True;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return False;
   exception
      when others =>
         return False;
   end Any_Cache_File_Contains;

   function Phase38_Scripted_Resolver
     (Origin_Host : String) return Http_Client.DNS_SVCB.Resolver_Result
   is
      pragma Unreferenced (Origin_Host);
      R      : Http_Client.DNS_SVCB.SVCB_Record;
      Result : Http_Client.DNS_SVCB.Resolver_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example alpn=h3 port=9443 ttl=30", R);
      Result.Status := Status;
      if Status = Http_Client.Errors.Ok then
         Status := Http_Client.DNS_SVCB.Append (Result.Records, R);
         Result.Status := Status;
      end if;
      return Result;
   end Phase38_Scripted_Resolver;

   procedure Test_HTTP2_ALPN_And_Config
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options  : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      TLS_Opts : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      TLS_Conn : Http_Client.Transports.TLS.Connection;
   begin
      Assert
        (Options.Mode = Http_Client.HTTP2.HTTP2_Disabled,
         "HTTP/2 should be disabled by default to preserve HTTP/1.1 behavior");
      Assert
        (Http_Client.HTTP2.ALPN_Advertisement (Options) = "http/1.1",
         "disabled HTTP/2 should advertise only http/1.1");
      Assert
        (Http_Client.HTTP2.Normalize_ALPN_Selected ("h2")
         = Http_Client.HTTP2.Protocol_HTTP_2,
         "h2 ALPN selection should normalize to HTTP/2");
      Assert
        (Http_Client.HTTP2.Selected_Status
           (Options, Http_Client.HTTP2.Protocol_HTTP_2)
         = Http_Client.Errors.ALPN_Negotiation_Failed,
         "forced HTTP/1.1 configuration must reject h2 selection");

      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Assert
        (Http_Client.HTTP2.ALPN_Advertisement (Options) = "h2,http/1.1",
         "allowed HTTP/2 should advertise h2 before http/1.1");
      Assert
        (Http_Client.HTTP2.Execution_Status_For_Selected
           (Options, Http_Client.HTTP2.Protocol_HTTP_2)
         = Http_Client.Errors.Ok,
         "HTTP/2 should accept h2 for single-stream, multiplexed, or explicitly enabled streaming/upload execution");
      Assert
        (Http_Client.HTTP2.Execution_Status_For_Selected
           (Options, Http_Client.HTTP2.Protocol_HTTP_1_1)
         = Http_Client.Errors.Ok,
         "HTTP/1.1 fallback remains valid when HTTP/2 is merely allowed");

      Options.Mode := Http_Client.HTTP2.HTTP2_Required;
      Assert
        (Http_Client.HTTP2.Selected_Status
           (Options, Http_Client.HTTP2.Protocol_HTTP_1_1)
         = Http_Client.Errors.ALPN_Negotiation_Failed,
         "required HTTP/2 must reject http/1.1 ALPN selection");

      Assert
        (Http_Client.Transports.TLS.Selected_ALPN (TLS_Conn)
         = Http_Client.HTTP2.Protocol_None,
         "closed TLS connections should report no selected ALPN");

      TLS_Opts.HTTP2.Max_Frame_Size := 16_383;
      Assert
        (Http_Client.Transports.TLS.Validate_Options (TLS_Opts)
         = Http_Client.Errors.Invalid_Configuration,
         "TLS option validation should include nested HTTP/2 limits");

      Options := Http_Client.HTTP2.Default_HTTP2_Options;
      Options.Enable_Multiplexing := True;
      Assert
        (Http_Client.HTTP2.Validate (Options)
         = Http_Client.Errors.HTTP2_Multiplexing_Unsupported,
         "multiplexing must not be enabled while HTTP/2 mode is disabled");

      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Local_Max_Concurrent_Streams := 2;
      Assert
        (Http_Client.HTTP2.Validate (Options) = Http_Client.Errors.Ok,
         "bounded HTTP/2 multiplexing should remain supported");

      Options.Enable_Public_Streaming := True;
      Options.Enable_Upload_Streaming := True;
      Assert
        (Http_Client.HTTP2.Validate (Options) = Http_Client.Errors.Ok,
         "HTTP/2 should support explicitly enabled streaming and upload over multiplexed h2");

      Options := Http_Client.HTTP2.Default_HTTP2_Options;
      Options.Max_Body_Size := 0;
      Assert
        (Http_Client.HTTP2.Validate (Options)
         = Http_Client.Errors.Invalid_Configuration,
         "HTTP/2 response body limit should be explicitly bounded");
   end Test_HTTP2_ALPN_And_Config;

   procedure Test_HTTP2_Preface_And_Settings
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Payload : constant String :=
        Http_Client.HTTP2.Settings.Initial_Settings_Payload;
      Parsed  : Ada.Strings.Unbounded.Unbounded_String;
      Encoded : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert
        (Http_Client.HTTP2.Client_Connection_Preface
         = "PRI * HTTP/2.0"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10)
           & "SM"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10),
         "client preface bytes should be exact");
      Assert
        (Payload'Length = 36,
         "initial SETTINGS payload should contain six entries");
      Assert
        (Character'Pos (Payload (Payload'First + 6)) = 0
         and then Character'Pos (Payload (Payload'First + 7)) = 2,
         "second initial setting should be SETTINGS_ENABLE_PUSH");
      Assert
        (Character'Pos (Payload (Payload'First + 11)) = 0,
         "initial SETTINGS should disable server push");
      Assert
        (Http_Client.HTTP2.Settings.Parse (Payload, Parsed)
         = Http_Client.Errors.Ok,
         "initial SETTINGS payload should parse and validate");
      Assert
        (Http_Client.HTTP2.Settings.Parse
           (Character'Val (0) & Character'Val (2) & Character'Val (0), Parsed)
         = Http_Client.Errors.HTTP2_Frame_Error,
         "SETTINGS payloads must be multiples of six octets");
      Assert
        (Http_Client.HTTP2.Settings.Serialize
           ((1 =>
               (Http_Client.HTTP2.Settings.SETTINGS_INITIAL_WINDOW_SIZE,
                16#0004#,
                16#7FFF_FFFF#)),
            Encoded)
         = Http_Client.Errors.Ok,
         "maximum SETTINGS_INITIAL_WINDOW_SIZE should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Encoded)
         = Character'Val (0)
           & Character'Val (4)
           & Character'Val (127)
           & Character'Val (255)
           & Character'Val (255)
           & Character'Val (255),
         "SETTINGS serialization should use audited big-endian 32-bit bytes");
      Assert
        (Http_Client.HTTP2.Settings.Parse
           (Ada.Strings.Unbounded.To_String (Encoded), Parsed)
         = Http_Client.Errors.Ok,
         "maximum representable SETTINGS_INITIAL_WINDOW_SIZE should parse");
      Assert
        (Http_Client.HTTP2.Settings.Parse
           (Character'Val (0)
            & Character'Val (4)
            & Character'Val (128)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0),
            Parsed)
         = Http_Client.Errors.HTTP2_Unsupported_Feature,
         "unrepresentable 32-bit SETTINGS values should be deterministic");
   end Test_HTTP2_Preface_And_Settings;

   procedure Test_HTTP2_Frame_Header_And_Frame_Validation
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Header  : Http_Client.HTTP2.Frames.Frame_Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.SETTINGS,
         Raw_Type     => 4,
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Parsed  : Http_Client.HTTP2.Frames.Frame_Header;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      Bytes   : Unbounded_String;
      State   : Http_Client.HTTP2.Frames.Continuation_State;
      Payload : constant String := "abcd";
   begin
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Header (Header)
         = Character'Val (0)
           & Character'Val (0)
           & Character'Val (0)
           & Character'Val (4)
           & Character'Val (0)
           & Character'Val (0)
           & Character'Val (0)
           & Character'Val (0)
           & Character'Val (0),
         "SETTINGS frame header serialization should be byte-exact");
      Assert
        (Http_Client.HTTP2.Frames.Parse_Header
           (Http_Client.HTTP2.Frames.Serialize_Header (Header), Parsed)
         = Http_Client.Errors.Ok,
         "serialized frame header should parse");
      Assert
        (Parsed.Kind = Http_Client.HTTP2.Frames.SETTINGS
         and then Parsed.Stream = 0
         and then Parsed.Length = 0,
         "parsed frame header should preserve type, stream, and length");

      Header.Kind := Http_Client.HTTP2.Frames.PING;
      Header.Raw_Type := 6;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame (Header, "12345678", Bytes)
         = Http_Client.Errors.Ok,
         "valid PING frame should serialize");
      Assert
        (Length (Bytes) = 17,
         "serialized PING frame should contain 9 header and 8 payload octets");

      Assert
        (Http_Client.HTTP2.Frames.Parse_Frame
           (To_String (Bytes), 16_384, Frame)
         = Http_Client.Errors.Ok,
         "serialized PING frame should parse");
      Assert
        (Frame.Header.Kind = Http_Client.HTTP2.Frames.PING
         and then To_String (Frame.Payload) = "12345678",
         "parsed PING frame should preserve payload");
      Assert
        (Http_Client.HTTP2.Frames.Parse_Frame
           (To_String (Bytes) & "x", 16_384, Frame)
         = Http_Client.Errors.HTTP2_Frame_Error,
         "Parse_Frame should reject trailing bytes distinctly from incomplete input");

      Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Header.Raw_Type := 0;
      Header.Stream := 0;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame (Header, Payload, Bytes)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "DATA frames on stream zero must be rejected");

      Header.Kind := Http_Client.HTTP2.Frames.WINDOW_UPDATE;
      Header.Raw_Type := 8;
      Header.Stream := 0;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame
           (Header,
            Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (1),
            Bytes)
         = Http_Client.Errors.Ok,
         "connection-level WINDOW_UPDATE on stream zero must be valid");
      Header.Stream := 1;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame
           (Header,
            Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0),
            Bytes)
         = Http_Client.Errors.HTTP2_Flow_Control_Error,
         "WINDOW_UPDATE increment zero must be rejected");

      Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Header.Raw_Type := 1;
      Header.Flags := 16#20#;
      Header.Stream := 1;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame (Header, "abc", Bytes)
         = Http_Client.Errors.HTTP2_Frame_Error,
         "HEADERS with PRIORITY must contain a five-octet priority field");

      Header.Flags := 16#08#;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame
           (Header, Character'Val (2) & "x", Bytes)
         = Http_Client.Errors.HTTP2_Frame_Error,
         "HEADERS padding must not exceed the remaining payload");

      Header.Kind := Http_Client.HTTP2.Frames.PUSH_PROMISE;
      Header.Raw_Type := 5;
      Header.Flags := 0;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame
           (Header,
            Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0),
            Bytes)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "PUSH_PROMISE promised stream id zero must be rejected");

      Header.Kind := Http_Client.HTTP2.Frames.GOAWAY;
      Header.Raw_Type := 7;
      Header.Flags := 0;
      Header.Stream := 0;
      Assert
        (Http_Client.HTTP2.Frames.Serialize_Frame
           (Header,
            Character'Val (128)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0),
            Bytes)
         = Http_Client.Errors.HTTP2_Frame_Error,
         "GOAWAY last-stream-id reserved bit must be rejected");

      Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Header.Raw_Type := 1;
      Header.Flags := 0;
      Header.Stream := 3;
      Assert
        (Http_Client.HTTP2.Frames.Apply_Continuation_Rule (State, Header)
         = Http_Client.Errors.Ok,
         "HEADERS without END_HEADERS should start a continuation sequence");

      Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Header.Raw_Type := 0;
      Assert
        (Http_Client.HTTP2.Frames.Apply_Continuation_Rule (State, Header)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "non-CONTINUATION frame during a header block must be rejected");

      Header.Kind := Http_Client.HTTP2.Frames.CONTINUATION;
      Header.Raw_Type := 9;
      Header.Flags := 16#04#;
      Assert
        (Http_Client.HTTP2.Frames.Apply_Continuation_Rule (State, Header)
         = Http_Client.Errors.Ok,
         "matching CONTINUATION with END_HEADERS should complete the sequence");
   end Test_HTTP2_Frame_Header_And_Frame_Validation;

   procedure Test_HTTP2_Request_Response_Mapping_And_HPACK
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Req     : Http_Client.Requests.Request;
      In_H    : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      H2_H    : Http_Client.Headers.Header_List;
      Resp_H  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Types.Status_Code;
      Block   : Ada.Strings.Unbounded.Unbounded_String;
      Decoded : Http_Client.Headers.Header_List;
   begin
      Assert_Header_Status
        (Http_Client.Headers.Add (In_H, "accept", "text/plain"),
         "lowercase request header should be accepted before HTTP/2 mapping");
      Assert_Parse_Ok
        ("https://example.com:8443/a/b?x=1#frag",
         URI,
         "HTTP/2 request URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Req,
            Headers => In_H)
         = Http_Client.Errors.Ok,
         "request for HTTP/2 mapping should construct");
      Assert
        (Http_Client.HTTP2.Mapping.Build_Request_Headers (Req, H2_H)
         = Http_Client.Errors.Ok,
         "valid request should map to HTTP/2 headers");
      Assert
        (Http_Client.Headers.Name_At (H2_H, 1) = ":method"
         and then Http_Client.Headers.Value_At (H2_H, 1) = "GET",
         "HTTP/2 request mapping should start with :method");
      Assert
        (Http_Client.Headers.Get (H2_H, ":authority") = "example.com:8443",
         "Host authority should map to :authority");
      Assert
        (Http_Client.Headers.Get (H2_H, ":path") = "/a/b?x=1",
         "HTTP/2 :path should preserve query and omit fragment");
      Assert
        (not Http_Client.Headers.Contains (H2_H, "host"),
         "ordinary Host header must not be emitted in HTTP/2 request headers");

      declare
         Expect_H : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
         Expect_R : Http_Client.Requests.Request;
         Expect_H2 : Http_Client.Headers.Header_List;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add (Expect_H, "Expect", "100-continue"),
            "Expect: 100-continue should be constructible before HTTP/2 mapping");
         Assert
           (Http_Client.Requests.Create
              (Method  => Http_Client.Types.POST,
               URI     => URI,
               Item    => Expect_R,
               Headers => Expect_H,
               Payload => "body")
            = Http_Client.Errors.Ok,
            "request with HTTP/1.1 expect handshake should construct");
         Assert
           (Http_Client.HTTP2.Mapping.Build_Request_Headers (Expect_R, Expect_H2)
            = Http_Client.Errors.Ok,
            "HTTP/2 request mapping should normalize HTTP/1.1 expect handshake");
         Assert
           (not Http_Client.Headers.Contains (Expect_H2, "expect"),
            "HTTP/2 request mapping must not forward Expect: 100-continue");
      end;

      Assert
        (Http_Client.Headers.Add_HTTP2_Pseudo (Resp_H, ":status", "200")
         = Http_Client.Errors.Ok,
         "response :status pseudo-header should be constructible for mapping tests");
      Assert_Header_Status
        (Http_Client.Headers.Add (Resp_H, "content-type", "text/plain"),
         "lowercase response field should be accepted");
      Assert
        (Http_Client.HTTP2.Mapping.Validate_Response_Headers (Resp_H)
         = Http_Client.Errors.Ok,
         "valid HTTP/2 response headers should validate");
      Assert
        (Http_Client.HTTP2.Mapping.Parse_Status (Resp_H, Status)
         = Http_Client.Errors.Ok
         and then Status = 200,
         ":status should map to numeric response status");

      Assert
        (Http_Client.HTTP2.HPACK.Encode_Literal_Without_Indexing
           (Resp_H, Block)
         = Http_Client.Errors.Ok,
         "minimal HPACK encoder should encode literal non-Huffman fields");
      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Ada.Strings.Unbounded.To_String (Block), 1024, Decoded)
         = Http_Client.Errors.Ok,
         "minimal HPACK decoder should decode the encoder subset");
      Assert
        (Http_Client.Headers.Get (Decoded, ":status") = "200",
         "minimal HPACK round trip should preserve pseudo-header values");
      declare
         D : Http_Client.HTTP2.HPACK.Decoder :=
           Http_Client.HTTP2.HPACK.Create_Decoder;
      begin
         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block
              (D,
               Hex_Bytes ("828684418cf1e3c2e5f23a6ba0ab90f4ff"),
               Decoded)
            = Http_Client.Errors.Ok,
            "RFC 7541 C.4.1 Huffman request example should decode");
         Assert
           (Http_Client.Headers.Get (Decoded, ":method") = "GET"
            and then Http_Client.Headers.Get (Decoded, ":scheme") = "http"
            and then Http_Client.Headers.Get (Decoded, ":path") = "/"
            and then Http_Client.Headers.Get (Decoded, ":authority") = "www.example.com",
            "RFC 7541 Huffman request example should preserve pseudo-headers");
      end;

      declare
         D : Http_Client.HTTP2.HPACK.Decoder :=
           Http_Client.HTTP2.HPACK.Create_Decoder;
      begin
         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block
              (D,
               Hex_Bytes ("885f87497ca589d34d1f768349509f"),
               Decoded)
            = Http_Client.Errors.Ok,
            "realistic Huffman response headers should decode");
         Assert
           (Http_Client.Headers.Get (Decoded, ":status") = "200"
            and then Http_Client.Headers.Get (Decoded, "content-type") = "text/html"
            and then Http_Client.Headers.Get (Decoded, "server") = "test",
            "Huffman response header values should reach HTTP/2 header mapping");
      end;

      declare
         D : Http_Client.HTTP2.HPACK.Decoder :=
           Http_Client.HTTP2.HPACK.Create_Decoder;
      begin
         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block
              (D,
               Hex_Bytes
                 ("488264025885aec3771a4b"
                  & "6196d07abe941054d444a8200595040b8166e082a62d1bff"
                  & "6e919d29ad171863c78f0b97c8e9ae82ae43d3"),
               Decoded)
            = Http_Client.Errors.Ok,
            "RFC 7541 C.6.1 Huffman response example should decode");
         Assert
           (Http_Client.Headers.Get (Decoded, ":status") = "302"
            and then Http_Client.Headers.Get (Decoded, "cache-control") = "private"
            and then Http_Client.Headers.Get (Decoded, "date")
              = "Mon, 21 Oct 2013 20:13:21 GMT"
            and then Http_Client.Headers.Get (Decoded, "location")
              = "https://www.example.com",
            "RFC 7541 C.6.1 should preserve Huffman response fields");

         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block
              (D,
               Hex_Bytes ("4883640effc1c0bf"),
               Decoded)
            = Http_Client.Errors.Ok,
            "RFC 7541 C.6.2 response example should decode dynamic indexes");
         Assert
           (Http_Client.Headers.Get (Decoded, ":status") = "307"
            and then Http_Client.Headers.Get (Decoded, "cache-control") = "private"
            and then Http_Client.Headers.Get (Decoded, "date")
              = "Mon, 21 Oct 2013 20:13:21 GMT"
            and then Http_Client.Headers.Get (Decoded, "location")
              = "https://www.example.com",
            "RFC 7541 C.6.2 should reuse decoded dynamic-table values");

         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block
              (D,
               Hex_Bytes
                 ("88c1"
                  & "6196d07abe941054d444a8200595040b8166e084a62d1bff"
                  & "c0bf"),
               Decoded)
            = Http_Client.Errors.Ok,
            "RFC 7541 C.6.3 response example should decode mixed indexed fields");
         Assert
           (Http_Client.Headers.Get (Decoded, ":status") = "200"
            and then Http_Client.Headers.Get (Decoded, "cache-control") = "private"
            and then Http_Client.Headers.Get (Decoded, "date")
              = "Mon, 21 Oct 2013 20:13:22 GMT"
            and then Http_Client.Headers.Get (Decoded, "location")
              = "https://www.example.com"
            and then Http_Client.Headers.Count (Decoded, ":status") = 2,
            "RFC 7541 C.6.3 should preserve decoded literals and indexed fields");
      end;

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (16#8C#)
            & Hex_Bytes ("f1e3c2e5f23a6ba0ab90f4ff")
            & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.Ok
         and then Http_Client.Headers.Get (Decoded, "www.example.com") = "",
         "minimal Huffman-marked string should decode rather than reject the H flag");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (16#81#)
            & Character'Val (16#00#)
            & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.HPACK_Huffman_Error,
         "HPACK Huffman strings should reject invalid zero padding");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (16#81#)
            & Character'Val (16#FF#)
            & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.HPACK_Huffman_Error,
         "HPACK Huffman strings should reject padding longer than seven bits");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (16#84#)
            & Character'Val (16#FF#)
            & Character'Val (16#FF#)
            & Character'Val (16#FF#)
            & Character'Val (16#FF#)
            & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.HPACK_Huffman_Error,
         "HPACK Huffman decoder should reject EOS as a decoded symbol");

      declare
         P : Positive := 1;
         V : Natural := 0;
      begin
         Assert
           (Http_Client.HTTP2.HPACK.Decode_Integer
              (Character'Val (16#1F#)
               & Character'Val (16#80#)
               & Character'Val (0),
               P,
               5,
               V)
            = Http_Client.Errors.HPACK_Decode_Failed,
            "HPACK integer decoder should reject overlong continuation encodings");
      end;
      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (5)
            & "x"
            & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.HPACK_Decode_Failed,
         "HPACK raw string length beyond available bytes should fail deterministically");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (16#FF#)
            & Character'Val (6)
            & Character'Val (16#FF#),
            1024,
            Decoded)
         = Http_Client.Errors.HPACK_Decode_Failed,
         "HPACK Huffman string length beyond available bytes should fail deterministically");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0) & Character'Val (1) & "A" & Character'Val (0),
            1024,
            Decoded)
         = Http_Client.Errors.Invalid_Header,
         "HPACK decoded HTTP/2 field names must be lowercase");
      Assert
        (Http_Client.Headers.Add_HTTP2_Pseudo (Resp_H, ":Status", "204")
         = Http_Client.Errors.Invalid_Header,
         "direct HTTP/2 pseudo-header insertion must also reject uppercase names");

      Assert
        (Http_Client.HTTP2.HPACK.Decode_Literal_Without_Indexing
           (Character'Val (0)
            & Character'Val (1)
            & "x"
            & Character'Val (1)
            & "y",
            33,
            Decoded)
         = Http_Client.Errors.Header_Too_Large,
         "HPACK header-list accounting should include 32 octets of per-field overhead");

      declare
         Req     : Http_Client.Requests.Request :=
           Http_Client.Requests.Default_Request;
         URI     : Http_Client.URI.URI_Reference;
         H2_Req  : Http_Client.Headers.Header_List;
         Enc     : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Encoded : Ada.Strings.Unbounded.Unbounded_String;
         Bytes   : String (1 .. 4);
      begin
         Assert
           (Http_Client.URI.Parse ("https://www.example.com/", URI)
            = Http_Client.Errors.Ok,
            "URI for static HPACK request-encoding test should parse");
         Assert
           (Http_Client.Requests.Create
              (Method => Http_Client.Types.GET, URI => URI, Item => Req)
            = Http_Client.Errors.Ok,
            "request for static HPACK request-encoding test should build");
         Assert
           (Http_Client.HTTP2.Mapping.Build_Request_Headers (Req, H2_Req)
            = Http_Client.Errors.Ok,
            "HTTP/2 request headers should build for static HPACK encoding test");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Enc, H2_Req, Encoded) = Http_Client.Errors.Ok,
            "HPACK encoder should encode normal HTTP/2 request fields");
         Bytes := Ada.Strings.Unbounded.To_String (Encoded)
           (Ada.Strings.Unbounded.To_String (Encoded)'First ..
            Ada.Strings.Unbounded.To_String (Encoded)'First + 3);
         Assert
           (Character'Pos (Bytes (1)) = 16#82#
            and then Character'Pos (Bytes (2)) = 16#87#
            and then Character'Pos (Bytes (3)) = 16#84#
            and then Character'Pos (Bytes (4)) = 16#01#,
            "HTTP/2 request HPACK should use RFC-style static indexed pseudo-header order before authority literal");
      end;

      declare
         D         : Http_Client.HTTP2.HPACK.Decoder :=
           Http_Client.HTTP2.HPACK.Create_Decoder;
         Dyn_Block : constant String :=
           Character'Val (16#40#)
           & Character'Val (1)
           & "x"
           & Character'Val (16#8C#)
           & Hex_Bytes ("f1e3c2e5f23a6ba0ab90f4ff")
           & Character'Val (16#BE#);
      begin
         Assert
           (Http_Client.HTTP2.HPACK.Decode_Header_Block (D, Dyn_Block, Decoded)
            = Http_Client.Errors.Ok,
            "HPACK decoder should support incremental indexing and dynamic indexes");
         Assert
           (Http_Client.Headers.Count (Decoded, "x") = 2
            and then Http_Client.Headers.Get (Decoded, "x") = "www.example.com",
            "HPACK dynamic-table indexed field should store decoded Huffman text");
      end;

      declare
         Enc       : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Sensitive : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Encoded   : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add (Sensitive, "authorization", "Basic abc"),
            "authorization header should be constructible for HPACK sensitivity test");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Enc, Sensitive, Encoded)
            = Http_Client.Errors.Ok,
            "HPACK encoder should encode sensitive fields without failure");
         Assert
           ((Character'Pos
              (Ada.Strings.Unbounded.To_String (Encoded)
                 (Ada.Strings.Unbounded.To_String (Encoded)'First)) / 16) = 1,
            "sensitive HPACK fields must use never-indexed literal representation");
      end;
   end Test_HTTP2_Request_Response_Mapping_And_HPACK;

   procedure Test_HTTP2_Single_Stream_Scripted_Execution
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI          : Http_Client.URI.URI_Reference;
      Req          : Http_Client.Requests.Request;
      Options      : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Resp_H       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Enc          : Http_Client.HTTP2.HPACK.Encoder :=
        Http_Client.HTTP2.HPACK.Create_Encoder;
      Header_Block : Ada.Strings.Unbounded.Unbounded_String;
      Server       : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Client       : Ada.Strings.Unbounded.Unbounded_String;
      Response     : Http_Client.Responses.Response;
      Payload_16K  : constant String (1 .. 16_384) := [others => 'x'];

      function Frame
        (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
         Flags   : Natural;
         Stream  : Natural;
         Payload : String) return String
      is
         H : constant Http_Client.HTTP2.Frames.Frame_Header :=
           (Length       =>
              Http_Client.HTTP2.Frames.Frame_Length (Payload'Length),
            Kind         => Kind,
            Raw_Type     => Http_Client.HTTP2.Frames.Type_Code (Kind),
            Flags        => Http_Client.HTTP2.Frames.Byte_Value (Flags),
            Reserved_Bit => False,
            Stream       => Http_Client.HTTP2.Frames.Stream_ID (Stream));
      begin
         return Http_Client.HTTP2.Frames.Serialize_Header (H) & Payload;
      end Frame;

      type Scripted_Producer is new Http_Client.Request_Bodies.Body_Producer
      with record
         Position : Natural := 0;
      end record;

      overriding
      function Read_Some
        (Item : in out Scripted_Producer; Buffer : out String; Count : out Natural)
         return Http_Client.Errors.Result_Status;

      overriding
      function Reset
        (Item : in out Scripted_Producer) return Http_Client.Errors.Result_Status;

      overriding
      function Read_Some
        (Item : in out Scripted_Producer; Buffer : out String; Count : out Natural)
         return Http_Client.Errors.Result_Status
      is
         Payload   : constant String := "abcdef";
         Remaining : Natural := Payload'Length - Item.Position;
         Chunk     : Natural := Natural'Min (Remaining, Buffer'Length);
      begin
         if Chunk = 0 then
            Count := 0;
            return Http_Client.Errors.Ok;
         end if;

         Buffer (Buffer'First .. Buffer'First + Chunk - 1) :=
           Payload
             (Payload'First + Integer (Item.Position)
              .. Payload'First + Integer (Item.Position + Chunk) - 1);
         Item.Position := Item.Position + Chunk;
         Count := Chunk;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Scripted_Producer) return Http_Client.Errors.Result_Status
      is
      begin
         Item.Position := 0;
         return Http_Client.Errors.Ok;
      end Reset;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Assert_Parse_Ok
        ("https://example.com/",
         URI,
         "scripted HTTP/2 execution URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Req)
         = Http_Client.Errors.Ok,
         "scripted HTTP/2 execution request should construct");

      Assert_Header_Status
        (Http_Client.Headers.Add_HTTP2_Pseudo (Resp_H, ":status", "200"),
         "scripted response should include :status");
      Assert_Header_Status
        (Http_Client.Headers.Add (Resp_H, "content-length", "5"),
         "scripted response should include content-length");
      Assert
        (Http_Client.HTTP2.HPACK.Encode_Header_Block
           (Enc, Resp_H, Header_Block)
         = Http_Client.Errors.Ok,
         "scripted response headers should HPACK-encode");

      Ada.Strings.Unbounded.Append
        (Server,
         Frame
           (Http_Client.HTTP2.Frames.SETTINGS,
            0,
            0,
            Http_Client.HTTP2.Settings.Initial_Settings_Payload));
      Ada.Strings.Unbounded.Append
        (Server,
         Frame
           (Http_Client.HTTP2.Frames.HEADERS,
            16#04#,
            1,
            Ada.Strings.Unbounded.To_String (Header_Block)));
      Ada.Strings.Unbounded.Append
        (Server, Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "hello"));

      Assert
        (Http_Client.HTTP2.Single_Stream.Execute_Scripted
           (Req,
            Ada.Strings.Unbounded.To_String (Server),
            Options,
            Client,
            Response)
         = Http_Client.Errors.Ok,
         "scripted single-stream HTTP/2 response should execute successfully");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200
         and then Http_Client.Responses.Response_Body (Response) = "hello",
         "scripted single-stream HTTP/2 response should map status and body");
      Assert
        (Ada.Strings.Unbounded.To_String (Client)
           (1 .. Http_Client.HTTP2.Client_Connection_Preface'Length)
         = Http_Client.HTTP2.Client_Connection_Preface,
         "scripted HTTP/2 client bytes should start with the connection preface");

      declare
         Small_Options : Http_Client.HTTP2.HTTP2_Options := Options;
      begin
         Small_Options.Max_Body_Size := 4;
         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Server),
               Small_Options,
               Client,
               Response)
            = Http_Client.Errors.Response_Too_Large,
            "HTTP/2 DATA accumulation should honor Max_Body_Size, not the header-list limit");
      end;
      declare
         Post_URI    : Http_Client.URI.URI_Reference;
         Post_Req    : Http_Client.Requests.Request;
         Producer    : aliased Scripted_Producer;
         Req_Body    : Http_Client.Request_Bodies.Request_Body;
         Post_Client : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert_Parse_Ok
           ("https://example.com/git-upload-pack",
            Post_URI,
            "scripted HTTP/2 POST URI should parse");
         Assert
           (Http_Client.Requests.Create
              (Method => Http_Client.Types.POST, URI => Post_URI, Item => Post_Req)
            = Http_Client.Errors.Ok,
            "scripted HTTP/2 POST request should construct");
         Req_Body := Http_Client.Request_Bodies.From_Fixed_Length_Stream
           (Producer'Unchecked_Access, 6, Replayable => True);
         Assert
           (Http_Client.Requests.Set_Body (Post_Req, Req_Body) = Http_Client.Errors.Ok,
            "scripted HTTP/2 POST request should accept a producer body");

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Post_Req,
               Ada.Strings.Unbounded.To_String (Server),
               Options,
               Post_Client,
               Response)
            = Http_Client.Errors.Ok,
            "single-stream HTTP/2 should execute fixed-length producer requests");
         Assert
           (Ada.Strings.Fixed.Index
              (Ada.Strings.Unbounded.To_String (Post_Client), "abcdef") > 0,
            "single-stream HTTP/2 should serialize producer request bodies as DATA before END_STREAM");
         Assert
           (Producer.Position = 6,
            "single-stream HTTP/2 should consume the fixed-length request producer exactly once");
      end;

      declare
         Huffman_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Huffman_Block  : constant String :=
           Hex_Bytes ("885c81175f87497ca589d34d1f768349509f");
      begin
         Ada.Strings.Unbounded.Append
           (Huffman_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Huffman_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Huffman_Block));
         Ada.Strings.Unbounded.Append
           (Huffman_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "ok"));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Huffman_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Ok,
            "scripted HTTP/2 response with Huffman HPACK headers should execute successfully");
         Assert
           (Http_Client.Responses.Status_Code (Response) = 200
            and then Http_Client.Responses.Response_Body (Response) = "ok"
            and then Http_Client.Headers.Get
              (Http_Client.Responses.Headers (Response),
               "content-type") = "text/html"
            and then Http_Client.Headers.Get
              (Http_Client.Responses.Headers (Response),
               "server") = "test",
            "scripted HTTP/2 response path should map decoded Huffman headers");
      end;

      declare
         Refused_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Refused_Code   : constant String :=
           String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (7));
      begin
         Ada.Strings.Unbounded.Append
           (Refused_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Refused_Server,
            Frame (Http_Client.HTTP2.Frames.RST_STREAM, 0, 1, Refused_Code));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Refused_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.HTTP2_Stream_Refused,
            "RST_STREAM REFUSED_STREAM should produce retry-safe HTTP2_Stream_Refused");
      end;

      declare
         Ignored_Reset_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Reset_Code           : constant String :=
           String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (8));
      begin
         Ada.Strings.Unbounded.Append
           (Ignored_Reset_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Ignored_Reset_Server,
            Frame (Http_Client.HTTP2.Frames.RST_STREAM, 0, 3, Reset_Code));
         Ada.Strings.Unbounded.Append
           (Ignored_Reset_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Ada.Strings.Unbounded.To_String (Header_Block)));
         Ada.Strings.Unbounded.Append
           (Ignored_Reset_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "hello"));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Ignored_Reset_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Ok,
            "single-stream HTTP/2 should ignore RST_STREAM for unrelated stream IDs");
         Assert
           (Http_Client.Responses.Status_Code (Response) = 200
            and then Http_Client.Responses.Response_Body (Response) = "hello",
            "unrelated RST_STREAM should not mask the active stream response");
      end;

      declare
         Settings_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Settings_H      : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Settings_Enc    : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Settings_Block  : Ada.Strings.Unbounded.Unbounded_String;
         Ack_Frame       : constant String :=
           Frame (Http_Client.HTTP2.Frames.SETTINGS, 16#01#, 0, "");
         Client_Text     : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add_HTTP2_Pseudo
              (Settings_H, ":status", "204"),
            "post-handshake SETTINGS response should include :status");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Settings_Enc, Settings_H, Settings_Block)
            = Http_Client.Errors.Ok,
            "post-handshake SETTINGS response headers should encode");
         Ada.Strings.Unbounded.Append
           (Settings_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Settings_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload
                 (Max_Frame_Size => 32_768)));
         Ada.Strings.Unbounded.Append
           (Settings_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#05#,
               1,
               Ada.Strings.Unbounded.To_String (Settings_Block)));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Settings_Server),
               Options,
               Client_Text,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 execution should acknowledge and apply post-handshake SETTINGS before continuing");
         declare
            Text : constant String :=
              Ada.Strings.Unbounded.To_String (Client_Text);
         begin
            Assert
              (Text'Length >= Ack_Frame'Length
               and then
                 Text (Text'Last - Ack_Frame'Length + 1 .. Text'Last)
                 = Ack_Frame,
               "scripted HTTP/2 client output should end with a SETTINGS ACK for post-handshake SETTINGS");
         end;
      end;

      declare
         Ping_Server  : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Ping_Payload : constant String := "12345678";
         Ping_Ack     : constant String :=
           Frame (Http_Client.HTTP2.Frames.PING, 16#01#, 0, Ping_Payload);
         Ping_Client  : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Strings.Unbounded.Append
           (Ping_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Ping_Server,
            Frame (Http_Client.HTTP2.Frames.PING, 0, 0, Ping_Payload));
         Ada.Strings.Unbounded.Append
           (Ping_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Ada.Strings.Unbounded.To_String (Header_Block)));
         Ada.Strings.Unbounded.Append
           (Ping_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "hello"));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Ping_Server),
               Options,
               Ping_Client,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 execution should acknowledge inbound PING frames while waiting for response headers");
         declare
            Text : constant String :=
              Ada.Strings.Unbounded.To_String (Ping_Client);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Text, Ping_Ack) > 0,
               "scripted HTTP/2 client output should include a PING ACK carrying the same payload");
         end;
      end;

      declare
         Window_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Window_Client : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Strings.Unbounded.Append
           (Window_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Window_Server,
            Frame
              (Http_Client.HTTP2.Frames.WINDOW_UPDATE,
               0,
               0,
               Character'Val (0)
               & Character'Val (0)
               & Character'Val (0)
               & Character'Val (1)));
         Ada.Strings.Unbounded.Append
           (Window_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Ada.Strings.Unbounded.To_String (Header_Block)));
         Ada.Strings.Unbounded.Append
           (Window_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "hello"));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Window_Server),
               Options,
               Window_Client,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 execution should consume valid connection-level WINDOW_UPDATE frames");
      end;

      declare
         Head_Req    : Http_Client.Requests.Request;
         Head_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Head_H      : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Head_Enc    : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Head_Block  : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert
           (Http_Client.Requests.Create
              (Method => Http_Client.Types.HEAD, URI => URI, Item => Head_Req)
            = Http_Client.Errors.Ok,
            "HEAD request should construct for HTTP/2 bodyless response test");
         Assert_Header_Status
           (Http_Client.Headers.Add_HTTP2_Pseudo (Head_H, ":status", "200"),
            "HEAD response should include :status");
         Assert_Header_Status
           (Http_Client.Headers.Add (Head_H, "content-length", "5"),
            "HEAD response may advertise the selected representation length");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Head_Enc, Head_H, Head_Block)
            = Http_Client.Errors.Ok,
            "HEAD response headers should encode");
         Ada.Strings.Unbounded.Append
           (Head_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Head_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#05#,
               1,
               Ada.Strings.Unbounded.To_String (Head_Block)));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Head_Req,
               Ada.Strings.Unbounded.To_String (Head_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 HEAD responses should allow content-length without DATA bytes");
      end;

      declare
         Bad_Req_H : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Bad_Req   : Http_Client.Requests.Request;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add (Bad_Req_H, "content-length", "8"),
            "mismatched request content-length header should be constructible");
         Assert
           (Http_Client.Requests.Create
              (Method  => Http_Client.Types.POST,
               URI     => URI,
               Item    => Bad_Req,
               Headers => Bad_Req_H,
               Payload => "abc")
            = Http_Client.Errors.Ok,
            "request with mismatched content-length should construct before HTTP/2 validation");
         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Bad_Req,
               Ada.Strings.Unbounded.To_String (Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Body_Length_Mismatch,
            "HTTP/2 request DATA content-length must match the buffered body length");
      end;

      declare
         Header_Limit_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
      begin
         Ada.Strings.Unbounded.Append
           (Header_Limit_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload
                 (Max_Header_List_Size => 1)));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Header_Limit_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Header_Too_Large,
            "HTTP/2 request header generation should honor peer SETTINGS_MAX_HEADER_LIST_SIZE");
      end;

      declare
         Bad_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
      begin
         Ada.Strings.Unbounded.Append
           (Bad_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Bad_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               0,
               1,
               Ada.Strings.Unbounded.To_String (Header_Block)));
         Ada.Strings.Unbounded.Append
           (Bad_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 16#01#, 1, "hello"));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Bad_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.HTTP2_Protocol_Error,
            "DATA must be rejected while a response header block is awaiting CONTINUATION");
      end;

      declare
         Trailer_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Trailer_H      : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Trailer_Enc    : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Trailer_Block  : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add (Trailer_H, "x-trailer", "done"),
            "HTTP/2 trailer field should be encodable as an ordinary field");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Trailer_Enc, Trailer_H, Trailer_Block)
            = Http_Client.Errors.Ok,
            "HTTP/2 trailer header block should encode");
         Ada.Strings.Unbounded.Append
           (Trailer_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Trailer_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Ada.Strings.Unbounded.To_String (Header_Block)));
         Ada.Strings.Unbounded.Append
           (Trailer_Server,
            Frame (Http_Client.HTTP2.Frames.DATA, 0, 1, "hello"));
         Ada.Strings.Unbounded.Append
           (Trailer_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#05#,
               1,
               Ada.Strings.Unbounded.To_String (Trailer_Block)));

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Trailer_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 response trailers should be accepted as trailing HEADERS");
         Assert
           (Http_Client.Responses.Response_Body (Response) = "hello",
            "HTTP/2 response trailers should not be exposed as body bytes");
         Assert
           (Http_Client.Headers.Get
              (Http_Client.Responses.Trailers (Response), "x-trailer") = "done",
            "HTTP/2 buffered response trailers should be exposed separately");
      end;

      declare
         Flow_Server : Ada.Strings.Unbounded.Unbounded_String :=
           Ada.Strings.Unbounded.Null_Unbounded_String;
         Flow_H      : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
         Flow_Enc    : Http_Client.HTTP2.HPACK.Encoder :=
           Http_Client.HTTP2.HPACK.Create_Encoder;
         Flow_Block  : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Assert_Header_Status
           (Http_Client.Headers.Add_HTTP2_Pseudo (Flow_H, ":status", "200"),
            "flow-control response should include :status");
         Assert_Header_Status
           (Http_Client.Headers.Add (Flow_H, "content-length", "65536"),
            "flow-control response should declare its large body length");
         Assert
           (Http_Client.HTTP2.HPACK.Encode_Header_Block
              (Flow_Enc, Flow_H, Flow_Block)
            = Http_Client.Errors.Ok,
            "flow-control response headers should encode");
         Ada.Strings.Unbounded.Append
           (Flow_Server,
            Frame
              (Http_Client.HTTP2.Frames.SETTINGS,
               0,
               0,
               Http_Client.HTTP2.Settings.Initial_Settings_Payload));
         Ada.Strings.Unbounded.Append
           (Flow_Server,
            Frame
              (Http_Client.HTTP2.Frames.HEADERS,
               16#04#,
               1,
               Ada.Strings.Unbounded.To_String (Flow_Block)));
         for I in 1 .. 4 loop
            Ada.Strings.Unbounded.Append
              (Flow_Server,
               Frame
                 (Http_Client.HTTP2.Frames.DATA,
                  (if I = 4 then 16#01# else 0),
                  1,
                  Payload_16K));
         end loop;

         Assert
           (Http_Client.HTTP2.Single_Stream.Execute_Scripted
              (Req,
               Ada.Strings.Unbounded.To_String (Flow_Server),
               Options,
               Client,
               Response)
            = Http_Client.Errors.Ok,
            "HTTP/2 single-stream execution should accept large DATA "
            & "sequences when WINDOW_UPDATE is emitted while DATA is consumed");
         declare
            Initial_Connection_Credit : constant String :=
              Frame
                (Http_Client.HTTP2.Frames.WINDOW_UPDATE,
                 0,
                 0,
                 String'
                   (1 => Character'Val (0),
                    2 => Character'Val (15),
                    3 => Character'Val (0),
                    4 => Character'Val (1)));
            Client_Text : constant String :=
              Ada.Strings.Unbounded.To_String (Client);
         begin
            Assert
              (Ada.Strings.Fixed.Index
                 (Client_Text, Initial_Connection_Credit) > 0,
               "HTTP/2 single-stream execution should send initial "
               & "connection WINDOW_UPDATE credit before reading DATA");
         end;
         Assert
           (Http_Client.Responses.Response_Body (Response)'Length = 65_536,
            "HTTP/2 single-stream execution should preserve the complete "
            & "large response body");
      end;
   end Test_HTTP2_Single_Stream_Scripted_Execution;

   procedure Test_HTTP2_Stream_State
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      State : Http_Client.HTTP2.Streams.Stream_State :=
        Http_Client.HTTP2.Streams.Idle;
   begin
      Assert
        (Http_Client.HTTP2.Streams.Is_Client_Initiated_Stream_ID (1),
         "client stream IDs should be nonzero odd values");
      Assert
        (not Http_Client.HTTP2.Streams.Is_Client_Initiated_Stream_ID (2),
         "server-initiated even stream IDs should not be client request streams");
      Assert
        (Http_Client.HTTP2.Streams.Apply
           (State, Http_Client.HTTP2.Streams.Receive_Headers)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "client stream should reject response HEADERS before request HEADERS open it");
      Assert
        (State = Http_Client.HTTP2.Streams.Idle,
         "invalid idle receive must leave the stream state unchanged");
      Assert
        (Http_Client.HTTP2.Streams.Apply
           (State, Http_Client.HTTP2.Streams.Send_Headers_End_Stream)
         = Http_Client.Errors.Ok,
         "sending HEADERS with END_STREAM should half-close local side");
      Assert
        (State = Http_Client.HTTP2.Streams.Half_Closed_Local,
         "stream should become half-closed-local after END_STREAM request");
      Assert
        (Http_Client.HTTP2.Streams.Apply
           (State, Http_Client.HTTP2.Streams.Receive_Headers)
         = Http_Client.Errors.Ok,
         "response headers are legal after request side is half closed");
      Assert
        (Http_Client.HTTP2.Streams.Apply
           (State, Http_Client.HTTP2.Streams.Receive_Data_End_Stream)
         = Http_Client.Errors.Ok,
         "response DATA with END_STREAM should close the stream");
      Assert
        (State = Http_Client.HTTP2.Streams.Closed,
         "stream should be closed after remote END_STREAM");
      Assert
        (Http_Client.HTTP2.Streams.Apply
           (State, Http_Client.HTTP2.Streams.Receive_Data)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "closed streams should reject further DATA");
   end Test_HTTP2_Stream_State;

   procedure Test_HTTP2_Multiplexed_Requires_Explicit_Enablement
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (not Http_Client.HTTP2.Connection.Can_Open_Stream (Conn),
         "default HTTP/2 options should not permit multiplexed stream opens");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.HTTP2_Multiplexing_Unsupported,
         "multiplexed connection state should require explicit Enable_Multiplexing");

      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "explicitly enabled multiplexing should allow a client stream to open");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#04#,
         Reserved_Bit => False,
         Stream       => 2);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "server-initiated stream IDs should be rejected while push is disabled and unsupported");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "unsupported server-initiated stream frames should retire the connection deterministically");
   end Test_HTTP2_Multiplexed_Requires_Explicit_Enablement;

   procedure Test_HTTP2_Multiplexed_Stream_Limits_And_Goaway
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      S4      : Http_Client.HTTP2.Frames.Stream_ID;
      S5      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Effective_Max_Concurrent_Streams (Conn)
         = 2,
         "local and peer stream limits should produce effective limit two");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok
         and then S1 = 1,
         "first client-initiated stream should use stream ID 1");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok
         and then S2 = 3,
         "second client-initiated stream should use stream ID 3");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S3)
         = Http_Client.Errors.HTTP2_Stream_Limit_Reached,
         "third active stream should be rejected by the effective concurrent limit");

      Frame.Header :=
        (Length       => 8,
         Kind         => Http_Client.HTTP2.Frames.GOAWAY,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.GOAWAY),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (3),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0),
              8 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "GOAWAY should retire the connection deterministically");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "connection should be marked retired after GOAWAY");
      Assert
        (Http_Client.HTTP2.Connection.Goaway_Last_Stream (Conn) = 3,
         "GOAWAY last-stream-id should be exposed for retry classification");
   end Test_HTTP2_Multiplexed_Stream_Limits_And_Goaway;

   procedure Test_HTTP2_Multiplexed_Goaway_Classifies_Active_Streams
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 3;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream 1 should open before GOAWAY classification");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream 3 should open before GOAWAY classification");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "stream 5 should open before GOAWAY classification");

      Frame.Header :=
        (Length       => 8,
         Kind         => Http_Client.HTTP2.Frames.GOAWAY,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.GOAWAY),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (3),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0),
              8 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "GOAWAY should retire the connection for active-stream classification");
      Assert
        (not Http_Client.HTTP2.Connection.Stream_After_Goaway_Last (Conn, S1),
         "stream 1 is at or below GOAWAY last-stream-id and may have been processed");
      Assert
        (not Http_Client.HTTP2.Connection.Stream_After_Goaway_Last (Conn, S2),
         "stream 3 is at GOAWAY last-stream-id and may have been processed");
      Assert
        (Http_Client.HTTP2.Connection.Stream_After_Goaway_Last (Conn, S3),
         "stream 5 is above GOAWAY last-stream-id and may be eligible for bounded retry");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Status_Of (Conn, S1)
         = Http_Client.Errors.Ok,
         "GOAWAY should not rewrite status for streams at or below last-stream-id");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Status_Of (Conn, S3)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "GOAWAY should mark active streams above last-stream-id for retry classification");
   end Test_HTTP2_Multiplexed_Goaway_Classifies_Active_Streams;

   procedure Test_HTTP2_Multiplexed_Goaway_Allows_Accepted_Stream_Completion
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      S4      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 3;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream 1 should open before GOAWAY completion test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream 3 should open before GOAWAY completion test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "stream 5 should open before GOAWAY completion test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream 1 request side should be half-closed before response frames");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream 3 request side should be half-closed before response frames");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "stream 5 request side should be half-closed before response frames");

      Frame.Header :=
        (Length       => 8,
         Kind         => Http_Client.HTTP2.Frames.GOAWAY,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.GOAWAY),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (3),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0),
              8 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "GOAWAY should retire the connection for new streams");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S4)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "a retired GOAWAY connection must not allocate new streams");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#04#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "accepted stream below GOAWAY last-stream-id should still accept response HEADERS");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 2;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("ok");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "accepted stream below GOAWAY last-stream-id should still complete with DATA");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "ok",
         "completed accepted stream should retain its decoded body bytes");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Header.Stream := S3;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Connection_Goaway,
         "stream above GOAWAY last-stream-id should not continue processing frames");
   end Test_HTTP2_Multiplexed_Goaway_Allows_Accepted_Stream_Completion;

   procedure Test_HTTP2_Multiplexed_Goaway_Rejects_Server_Stream_Boundary
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open before malformed GOAWAY boundary test");

      Frame.Header :=
        (Length       => 8,
         Kind         => Http_Client.HTTP2.Frames.GOAWAY,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.GOAWAY),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (2),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0),
              8 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "server GOAWAY with an even nonzero last-stream-id should be rejected");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "malformed GOAWAY boundary should retire the h2 connection");
   end Test_HTTP2_Multiplexed_Goaway_Rejects_Server_Stream_Boundary;

   procedure Test_HTTP2_Multiplexed_Goaway_Rejects_Unissued_Stream
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open before unissued GOAWAY stream-id test");

      Frame.Header :=
        (Length       => 8,
         Kind         => Http_Client.HTTP2.Frames.GOAWAY,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.GOAWAY),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (3),
              5 => Character'Val (0),
              6 => Character'Val (0),
              7 => Character'Val (0),
              8 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "GOAWAY last-stream-id must not name an unissued client stream");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "invalid GOAWAY last-stream-id should retire the h2 connection");
   end Test_HTTP2_Multiplexed_Goaway_Rejects_Unissued_Stream;

   procedure Test_HTTP2_Multiplexed_Interleaved_Data_And_Reset
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream 1 should open");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream 3 should open");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream 1 local side should half-close after request END_STREAM");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream 3 local side should half-close after request END_STREAM");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#04#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS for stream 1 should be accepted");

      Frame.Header.Stream := S2;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS for stream 3 should be accepted independently");

      Frame.Header :=
        (Length       => 2,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("he");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first DATA fragment for stream 1 should be buffered");

      Frame.Header.Stream := S2;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("xy");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "interleaved DATA for stream 3 should be buffered separately");

      Frame.Header.Stream := S1;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("ll");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "END_STREAM DATA for stream 1 should close remote side");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "hell",
         "stream 1 body should preserve only stream 1 DATA in order");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S2) = "xy",
         "stream 3 body should preserve only stream 3 DATA");

      Frame.Header :=
        (Length       => 4,
         Kind         => Http_Client.HTTP2.Frames.RST_STREAM,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.RST_STREAM),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S2);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (8)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_Reset,
         "RST_STREAM should fail only the addressed stream");
      Assert
        (Http_Client.HTTP2.Connection.Stream_State_Of (Conn, S2)
         = Http_Client.HTTP2.Streams.Reset,
         "reset stream should be marked reset");
      Assert
        (not Http_Client.HTTP2.Connection.Retired (Conn),
         "stream reset should not retire the whole HTTP/2 connection");
      Assert
        (Http_Client.HTTP2.Connection.Consume_Response_Bytes (Conn, S1, 4)
         = Http_Client.Errors.Ok,
         "consuming buffered response bytes should credit stream receive window");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Receive_Window (Conn, S1)
         = Options.Initial_Stream_Window_Size,
         "stream receive window should be restored after consumed bytes are credited");
      Assert
        (Http_Client.HTTP2.Connection.Release_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "closed stream bookkeeping should be releasable after response consumption");
      Assert
        (Http_Client.HTTP2.Connection.Release_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "reset stream bookkeeping should be releasable independently");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok
         and then S2 = 5,
         "released bookkeeping slots should allow later streams without reusing stream IDs");

      Frame.Header.Stream := S2;
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (7)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_Refused,
         "RST_STREAM REFUSED_STREAM should preserve retry-safe reset semantics");
      Assert
        (Http_Client.HTTP2.Connection.Release_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "refused stream bookkeeping should remain releasable");
   end Test_HTTP2_Multiplexed_Interleaved_Data_And_Reset;

   procedure Test_HTTP2_Multiplexed_Flow_Control_And_Settings
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options          : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn             : Http_Client.HTTP2.Connection.Connection_State;
      S1               : Http_Client.HTTP2.Frames.Stream_ID;
      Settings_Payload : constant String :=
        String'
          (1 => Character'Val (0),
           2 => Character'Val (4),
           3 => Character'Val (0),
           4 => Character'Val (0),
           5 => Character'Val (0),
           6 => Character'Val (8));
      Window_Update    : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Options.Initial_Stream_Window_Size := 8;
      Options.Initial_Connection_Window_Size := 8;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for flow-control test");
      Assert
        (Http_Client.HTTP2.Connection.Send_Data (Conn, S1, 9)
         = Http_Client.Errors.HTTP2_Flow_Control_Error,
         "outbound DATA must not exceed stream or connection windows");
      Assert
        (Http_Client.HTTP2.Connection.Send_Data (Conn, S1, 4)
         = Http_Client.Errors.Ok,
         "outbound DATA inside both windows should be accepted");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Send_Window (Conn) = 4
         and then
           Http_Client.HTTP2.Connection.Stream_Send_Window (Conn, S1) = 4,
         "sending DATA should decrement both connection and stream windows");
      Assert
        (Http_Client.HTTP2.Connection.Apply_Settings_Payload
           (Conn, Settings_Payload)
         = Http_Client.Errors.Ok,
         "SETTINGS_INITIAL_WINDOW_SIZE should be applicable while streams are active");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Send_Window (Conn, S1) = 4,
         "equal SETTINGS_INITIAL_WINDOW_SIZE should leave existing send window unchanged");

      Window_Update.Header :=
        (Length       => 4,
         Kind         => Http_Client.HTTP2.Frames.WINDOW_UPDATE,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.WINDOW_UPDATE),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 0);
      Window_Update.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (4)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Window_Update)
         = Http_Client.Errors.Ok,
         "connection WINDOW_UPDATE should increase the connection send window");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Send_Window (Conn) = 8,
         "connection send window should reflect WINDOW_UPDATE increment");

      Window_Update.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Window_Update)
         = Http_Client.Errors.HTTP2_Flow_Control_Error,
         "zero WINDOW_UPDATE increment must be a flow-control error");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "connection-level flow-control errors should retire the connection");
   end Test_HTTP2_Multiplexed_Flow_Control_And_Settings;

   procedure Test_HTTP2_Multiplexed_Frame_Validation
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for frame validation test");

      Frame.Header :=
        (Length       => 3,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("xy");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Incomplete_Message,
         "multiplexed dispatch should reject frame objects whose declared length does not match payload");
      Assert
        (Http_Client.HTTP2.Connection.Retired (Conn),
         "malformed frame objects should retire the HTTP/2 connection");
   end Test_HTTP2_Multiplexed_Frame_Validation;

   procedure Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Options.Max_Header_List_Size := 4;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first stream should open for padded/priority HEADERS accounting test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second stream should open for continuation header accounting test");

      Frame.Header :=
        (Length       => 15,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#2C#, --  END_HEADERS | PADDED | PRIORITY
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String
        (String'
           (1  => Character'Val (6),
            2  => Character'Val (0),
            3  => Character'Val (0),
            4  => Character'Val (0),
            5  => Character'Val (0),
            6  => Character'Val (1),
            7  => 'a',
            8  => 'b',
            9  => 'c',
            10 => 'p',
            11 => 'a',
            12 => 'd',
            13 => 'd',
            14 => 'e',
            15 => 'd'));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "padded/priority HEADERS should count only HPACK fragment bytes against header-list limit");

      Frame.Header :=
        (Length       => 9,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#28#, --  PADDED | PRIORITY, no END_HEADERS
         Reserved_Bit => False,
         Stream       => S2);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String
        (String'
           (1 => Character'Val (0),
            2 => Character'Val (0),
            3 => Character'Val (0),
            4 => Character'Val (0),
            5 => Character'Val (0),
            6 => Character'Val (1),
            7 => 'x',
            8 => 'y',
            9 => 'z'));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "pending padded/priority HEADERS should store only HPACK fragment length");

      Frame.Header :=
        (Length       => 2,
         Kind         => Http_Client.HTTP2.Frames.CONTINUATION,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.CONTINUATION),
         Flags        => 16#04#,
         Reserved_Bit => False,
         Stream       => S2);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("uv");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Header_Error,
         "CONTINUATION should enforce fragment-plus-continuation header-list limit");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Status_Of (Conn, S1)
         = Http_Client.Errors.Ok,
         "header-list overflow on stream B must not corrupt stream A");
   end Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted;

   procedure Test_HTTP2_Multiplexed_Invalid_Transitions_Do_Not_Mutate
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options               : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn                  : Http_Client.HTTP2.Connection.Connection_State;
      S1                    : Http_Client.HTTP2.Frames.Stream_ID;
      Frame                 : Http_Client.HTTP2.Frames.Frame;
      Send_Window_Before    : Natural;
      Receive_Window_Before : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for invalid-transition mutation test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "local side should half-close before receiving final response headers");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#05#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS with END_STREAM should close the stream");
      Assert
        (Http_Client.HTTP2.Connection.Stream_State_Of (Conn, S1)
         = Http_Client.HTTP2.Streams.Closed,
         "stream should be closed before illegal DATA and send attempts");

      Send_Window_Before :=
        Http_Client.HTTP2.Connection.Connection_Send_Window (Conn);
      Assert
        (Http_Client.HTTP2.Connection.Send_Data (Conn, S1, 1)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "illegal outbound DATA on a closed stream should fail as a state error");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Send_Window (Conn)
         = Send_Window_Before,
         "failed outbound DATA transition must not consume the connection send window");
      Assert
        (Http_Client.HTTP2.Connection.Send_Data (Conn, S1, 65_536)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "closed-stream DATA should be classified as a state error before flow-control limits");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Send_Window (Conn)
         = Send_Window_Before,
         "closed-stream DATA larger than the window must still leave send windows unchanged");

      Receive_Window_Before :=
        Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn);
      Frame.Header :=
        (Length       => 1,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("z");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "illegal inbound DATA on a closed stream should fail as a state error");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Receive_Window_Before,
         "failed inbound DATA transition must not consume the connection receive window");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "",
         "failed inbound DATA transition must not append body bytes");
   end Test_HTTP2_Multiplexed_Invalid_Transitions_Do_Not_Mutate;

   procedure Test_HTTP2_Multiplexed_Continuation_State_Commits_Only_On_Success
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for continuation commit test");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 99);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "HEADERS for an unknown stream should fail before committing continuation state");
      Assert
        (not Http_Client.HTTP2.Connection.Retired (Conn),
         "unknown-stream state errors should not retire the connection");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.SETTINGS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.SETTINGS),
         Flags        => 16#01#,
         Reserved_Bit => False,
         Stream       => 0);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "a later valid SETTINGS ACK should not be rejected by stale continuation state");
      Assert
        (not Http_Client.HTTP2.Connection.Retired (Conn),
         "valid frame after rejected HEADERS should leave connection usable");
   end Test_HTTP2_Multiplexed_Continuation_State_Commits_Only_On_Success;

   procedure Test_HTTP2_Multiplexed_Content_Length_And_Bodyless
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 3;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first stream should open for content-length validation");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first request side should half-close before response headers");
      Assert
        (Http_Client.HTTP2.Connection.Set_Response_Content_Length (Conn, S1, 5)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "Content-Length metadata must not be accepted before final response headers");

      Frame.Header :=
        (Length       => 0,
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => 16#04#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response headers should be accepted before Content-Length metadata");
      Assert
        (Http_Client.HTTP2.Connection.Set_Response_Content_Length (Conn, S1, 5)
         = Http_Client.Errors.Ok,
         "decoded Content-Length should be recorded after final response headers");

      Frame.Header :=
        (Length       => 3,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("abc");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "partial DATA below Content-Length should be accepted");

      Frame.Header :=
        (Length       => 2,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 16#01#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("de");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "DATA ending exactly at Content-Length should be accepted");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "abcde",
         "accepted DATA should accumulate exactly the declared response body");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second stream should open for Content-Length mismatch validation");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second request side should half-close before response headers");
      Frame.Header.Stream := S2;
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "second response headers should be accepted");
      Assert
        (Http_Client.HTTP2.Connection.Set_Response_Content_Length (Conn, S2, 4)
         = Http_Client.Errors.Ok,
         "second stream should record expected Content-Length four");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 3;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("abc");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Body_Length_Mismatch,
         "END_STREAM before the declared Content-Length should fail deterministically");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S2) = "",
         "mismatched DATA should not be appended before failure is reported");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "third stream should open for bodyless response validation");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "third request side should half-close before response headers");
      Frame.Header.Stream := S3;
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "bodyless response headers should be accepted before policy marking");
      Assert
        (Http_Client.HTTP2.Connection.Mark_Bodyless_Response (Conn, S3)
         = Http_Client.Errors.Ok,
         "HEAD/204/304-style response policy should mark DATA as forbidden");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 1;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("x");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "non-empty DATA on a bodyless HTTP/2 response should be rejected");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S3) = "",
         "bodyless response DATA rejection must not append bytes");
   end Test_HTTP2_Multiplexed_Content_Length_And_Bodyless;

   procedure Test_HTTP2_Response_Body_Stream_Reads_And_Early_Close
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 4);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Options.Max_Per_Stream_Buffered_Bytes := 16;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "HTTP/2 streamed response should allocate a client stream");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "GET-style streamed response should end request side");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "streamed response HEADERS should be accepted before DATA");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 5;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("hello");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "streamed response DATA should be queued as body bytes");

      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "HTTP/2 body stream should open after response headers");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 4
         and then Buffer = "hell",
         "first HTTP/2 body stream read should return queued DATA bytes only");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 1,
         "response body consumption should credit consumed bytes back to receive windows");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 1
         and then Buffer (Buffer'First) = 'o',
         "second HTTP/2 body stream read should return remaining byte");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "HTTP/2 body stream should report EOF after END_STREAM and full consumption");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "second HTTP/2 streamed response should allocate after release");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Header.Stream := S1;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "second streamed response HEADERS should be accepted");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 2;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("zz");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "early-close stream should be allowed to have unread queued DATA");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 2,
         "queued unread DATA should consume HTTP/2 receive window before close");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "second HTTP/2 body stream should open");
      Assert
        (Http_Client.HTTP2.Body_Streams.Close (B) = Http_Client.Errors.Ok,
         "early close should cancel only the addressed HTTP/2 stream");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size,
         "early close should credit unread queued DATA before releasing the HTTP/2 stream");
      Assert
        (Http_Client.HTTP2.Connection.Active_Stream_Count (Conn) = 0,
         "early close should cancel and release only the addressed HTTP/2 stream");
   end Test_HTTP2_Response_Body_Stream_Reads_And_Early_Close;

   procedure Test_HTTP2_Response_Data_Credit_Prevents_Double_Window_Update
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for response DATA credit test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "GET-style request should close local side before response DATA");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS should be accepted before DATA credit test");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 5;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("hello");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response DATA should queue before explicit WINDOW_UPDATE credit");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 5,
         "accepted queued DATA should consume the receive window first");

      Assert
        (Http_Client.HTTP2.Connection.Credit_Response_Data (Conn, S1, 5)
         = Http_Client.Errors.Ok,
         "transport WINDOW_UPDATE credit should restore the receive window");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size,
         "explicit DATA credit should restore the connection receive window");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Receive_Window (Conn, S1)
         = Options.Initial_Stream_Window_Size,
         "explicit DATA credit should restore the stream receive window");

      Assert
        (Http_Client.HTTP2.Connection.Consume_Response_Bytes (Conn, S1, 5)
         = Http_Client.Errors.Ok,
         "consuming already-credited DATA should remove bytes without double credit");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size,
         "consuming already-credited DATA must not grow the connection window");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Receive_Window (Conn, S1)
         = Options.Initial_Stream_Window_Size,
         "consuming already-credited DATA must not grow the stream window");
   end Test_HTTP2_Response_Data_Credit_Prevents_Double_Window_Update;

   procedure Test_HTTP2_Total_Queued_Body_Limit_Is_Connection_Wide
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Options.Max_Per_Stream_Buffered_Bytes := 10;
      Options.Max_Total_Queued_Body_Bytes := 5;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first stream should open for aggregate queue limit test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second stream should open for aggregate queue limit test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first request side should close before response DATA");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second request side should close before response DATA");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first response headers should be accepted before aggregate DATA limit test");
      Frame.Header.Stream := S2;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "second response headers should be accepted before aggregate DATA limit test");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Stream := S1;
      Frame.Header.Length := 3;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("abc");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first stream should queue DATA below aggregate limit");
      Assert
        (Http_Client.HTTP2.Connection.Total_Buffered_Response_Bytes (Conn) = 3,
         "aggregate queued DATA count should include first stream bytes");

      Frame.Header.Stream := S2;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("def");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Response_Too_Large,
         "second stream DATA should be rejected before aggregate queue exceeds limit");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "abc",
         "aggregate queue rejection on stream B must not corrupt stream A bytes");
      Assert
        (Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, S2) = 0,
         "rejected aggregate overflow DATA must not be queued on stream B");
      Assert
        (Http_Client.HTTP2.Connection.Total_Buffered_Response_Bytes (Conn) = 3,
         "aggregate queued DATA count should remain bounded after rejecting stream B");
      Assert
        (Http_Client.HTTP2.Connection.Stream_Status_Of (Conn, S2)
         = Http_Client.Errors.Response_Too_Large,
         "aggregate queue overflow should fail only the offending stream");
   end Test_HTTP2_Total_Queued_Body_Limit_Is_Connection_Wide;

   procedure Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. 2);
      Last    : Ada.Streams.Stream_Element_Offset;
      Payload : constant String :=
        Character'Val (16#30#) & Character'Val (16#00#) &
        Character'Val (16#FF#) & Character'Val (16#0A#);
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Options.Max_Per_Stream_Buffered_Bytes := 16;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "HTTP/2 byte-array Git stream should allocate a client stream");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "GET-style HTTP/2 Git stream should end request side");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "HTTP/2 Git response headers should be accepted before binary DATA");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := Payload'Length;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String (Payload);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "HTTP/2 Git binary DATA should be queued exactly");

      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "HTTP/2 byte-array body stream should open after response headers");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 2
         and then Buffer (1) = 16#30#
         and then Buffer (2) = 16#00#,
         "first HTTP/2 byte-array read should preserve pkt-line/NUL bytes");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 2
         and then Buffer (1) = 16#FF#
         and then Buffer (2) = 16#0A#,
         "second HTTP/2 byte-array read should preserve high bytes and LF");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream
         and then Last = Buffer'First - 1,
         "HTTP/2 byte-array stream should report EOF after exact binary body");
   end Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes;

   procedure Test_HTTP2_Upload_Body_Streaming
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      type Test_Producer is new Http_Client.Request_Bodies.Body_Producer
      with record
         Position : Natural := 0;
      end record;

      overriding
      function Read_Some
        (Item : in out Test_Producer; Buffer : out String; Count : out Natural)
         return Http_Client.Errors.Result_Status;

      overriding
      function Reset
        (Item : in out Test_Producer) return Http_Client.Errors.Result_Status;

      overriding
      function Read_Some
        (Item : in out Test_Producer; Buffer : out String; Count : out Natural)
         return Http_Client.Errors.Result_Status
      is
         Payload   : constant String := "abcdef";
         Remaining : Natural := Payload'Length - Item.Position;
         Chunk     : Natural := Natural'Min (Remaining, Buffer'Length);
      begin
         if Chunk = 0 then
            Count := 0;
            return Http_Client.Errors.Ok;
         end if;

         Buffer (Buffer'First .. Buffer'First + Chunk - 1) :=
           Payload
             (Payload'First + Integer (Item.Position)
              .. Payload'First + Integer (Item.Position + Chunk) - 1);
         Item.Position := Item.Position + Chunk;
         Count := Chunk;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Test_Producer) return Http_Client.Errors.Result_Status
      is
      begin
         Item.Position := 0;
         return Http_Client.Errors.Ok;
      end Reset;

      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : Http_Client.HTTP2.Connection.Connection_State;
      Conn2   : Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      P       : aliased Test_Producer;
      Result  : Http_Client.HTTP2.Uploads.Upload_Result;
      B       : Http_Client.Request_Bodies.Request_Body;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Upload_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Options.Initial_Connection_Window_Size := 3;
      Options.Initial_Stream_Window_Size := 3;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "HTTP/2 upload should allocate a stream");
      B := Http_Client.Request_Bodies.From_String ("abc");
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, S1, B, Result)
         = Http_Client.Errors.Ok,
         "buffered HTTP/2 upload body should send as DATA");
      Assert
        (Result.Bytes_Sent = 3
         and then Result.Data_Frames = 1
         and then Result.End_Stream_Sent,
         "buffered HTTP/2 upload should account DATA bytes and END_STREAM");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second HTTP/2 upload should allocate a stream");
      B :=
        Http_Client.Request_Bodies.From_Fixed_Length_Stream
          (P'Unchecked_Access,
           6,
           Replayable => True);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, S2, B, Result)
         = Http_Client.Errors.Timeout,
         "HTTP/2 upload should not pull producer bytes when send windows are exhausted");
      Assert
        (P.Position = 0,
         "flow-control timeout should occur before pulling bytes from the producer");

      Options.Initial_Connection_Window_Size := 10;
      Options.Initial_Stream_Window_Size := 10;
      Conn2 := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn2, S3)
         = Http_Client.Errors.Ok,
         "third HTTP/2 upload stream should open for overproduction detection");
      Assert
        (Reset (P) = Http_Client.Errors.Ok,
         "test producer should reset before overproduction detection");
      B :=
        Http_Client.Request_Bodies.From_Fixed_Length_Stream
          (P'Unchecked_Access,
           5,
           Replayable => True);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn2, S3, B, Result)
         = Http_Client.Errors.Body_Length_Mismatch,
         "fixed-length HTTP/2 producer that has extra bytes should be rejected before sending END_STREAM");
      Assert
        (Result.End_Stream_Sent = False,
         "overproducing HTTP/2 upload should not mark END_STREAM as sent");
   end Test_HTTP2_Upload_Body_Streaming;

   procedure Test_HTTP2_Execution_Common_Request_Body_Contracts
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_Body : Http_Client.Request_Bodies.Request_Body;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Req_Body := Http_Client.Request_Bodies.From_String ("abcdef");

      Assert
        (Http_Client.HTTP2_Execution_Common.Collect_Request_Body
           (Req_Body, 6, Output)
         = Http_Client.Errors.Ok,
         "shared HTTP/2 body collector should accept exact bounded body");
      Assert
        (Ada.Strings.Unbounded.To_String (Output) = "abcdef",
         "shared HTTP/2 body collector should preserve body bytes exactly");

      Assert
        (Http_Client.HTTP2_Execution_Common.Collect_Request_Body
           (Req_Body, 5, Output)
         = Http_Client.Errors.HTTP2_Flow_Control_Error,
         "shared HTTP/2 body collector should reject bodies over the bound");

      Assert
        (Http_Client.HTTP2_Execution_Common.Ensure_Content_Length_Header
           (Headers, 6)
         = Http_Client.Errors.Ok,
         "shared HTTP/2 helper should synthesize content-length");
      Assert
        (Http_Client.Headers.Get (Headers, "content-length") = "6",
         "shared HTTP/2 helper should synthesize lowercase content-length");
      Assert
        (Http_Client.HTTP2_Execution_Common.Request_Content_Length_Is_Valid
           (Headers, 6)
         = Http_Client.Errors.Ok,
         "shared HTTP/2 helper should accept matching content-length");
      Assert
        (Http_Client.HTTP2_Execution_Common.Request_Content_Length_Is_Valid
           (Headers, 7)
         = Http_Client.Errors.Body_Length_Mismatch,
         "shared HTTP/2 helper should reject mismatched content-length");
   end Test_HTTP2_Execution_Common_Request_Body_Contracts;

   procedure Test_HTTP2_Request_Trailers_As_Trailing_HEADERS
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options  : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn     : Http_Client.HTTP2.Connection.Connection_State;
      S1       : Http_Client.HTTP2.Frames.Stream_ID;
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      B        : Http_Client.Request_Bodies.Request_Body;
      Result   : Http_Client.HTTP2.Uploads.Upload_Result;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Upload_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.Headers.Add (Trailers, "x-checksum", "abc123")
         = Http_Client.Errors.Ok,
         "test trailer should be a valid ordinary HTTP field");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "HTTP/2 request trailer test should allocate a stream");

      B := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.From_String ("abc"), Trailers);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, S1, B, Result)
         = Http_Client.Errors.Ok,
         "HTTP/2 request trailers should be sent as trailing HEADERS");
      Assert
        (Result.Bytes_Sent = 3
         and then Result.Data_Frames = 1
         and then Result.Trailer_Headers = 1
         and then Result.End_Stream_Sent,
         "HTTP/2 request trailer upload should account DATA then one trailing HEADERS END_STREAM");
      Assert
        (Http_Client.HTTP2.Connection.Stream_State_Of (Conn, S1)
         = Http_Client.HTTP2.Streams.Half_Closed_Local,
         "trailing request HEADERS should close only the local request side");
   end Test_HTTP2_Request_Trailers_As_Trailing_HEADERS;

   procedure Test_HTTP2_Request_Trailer_Forbidden_Names_Rejected
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options  : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn     : Http_Client.HTTP2.Connection.Connection_State;
      S1       : Http_Client.HTTP2.Frames.Stream_ID;
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      B        : Http_Client.Request_Bodies.Request_Body;
      Result   : Http_Client.HTTP2.Uploads.Upload_Result;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Upload_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.Headers.Add (Trailers, "content-length", "3")
         = Http_Client.Errors.Ok,
         "forbidden trailer field must be syntactically valid before policy rejection");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "forbidden HTTP/2 request trailer test should allocate a stream");

      B := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.From_String ("abc"), Trailers);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, S1, B, Result)
         = Http_Client.Errors.HTTP2_Header_Error,
         "HTTP/2 request trailers should reject framing/sensitive fields before trailing HEADERS succeeds");
      Assert
        (Result.End_Stream_Sent = False
         and then Result.Trailer_Headers = 0,
         "rejected HTTP/2 request trailers should not report END_STREAM or trailer HEADERS sent");
   end Test_HTTP2_Request_Trailer_Forbidden_Names_Rejected;

   procedure Test_HTTP2_Response_Trailers_Not_Body_And_Forbid_Data_After
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      Stream_Body : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 8);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "HTTP/2 response trailer test should allocate a stream");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "response trailer test should half-close the request side");

      Frame :=
        (Header =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     => Http_Client.HTTP2.Frames.Type_Code
              (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "initial response HEADERS should be accepted");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 4;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("body");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response DATA before trailers should be body bytes");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#05#;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response trailing HEADERS with END_STREAM should be accepted");
      Assert
        (Http_Client.HTTP2.Connection.Response_Trailers_Received (Conn, S1),
         "response trailer state should be recorded per stream");
      Assert
        (Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, S1) = 4,
         "response trailers must not be exposed as body bytes");

      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, Stream_Body)
         = Http_Client.Errors.Ok,
         "body stream should open after trailer-closed response");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (Stream_Body, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 4
         and then Buffer (1 .. 4) = "body",
         "body stream should return DATA payload only");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 1;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("x");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "DATA after response trailers should be rejected");
   end Test_HTTP2_Response_Trailers_Not_Body_And_Forbid_Data_After;

   procedure Test_HTTP2_Public_Stream_Limits_Padding_And_Pending_Read
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options       : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn          : aliased Http_Client.HTTP2.Connection.Connection_State;
      Conn_Upload   : Http_Client.HTTP2.Connection.Connection_State;
      Conn_Flow     : Http_Client.HTTP2.Connection.Connection_State;
      S1            : Http_Client.HTTP2.Frames.Stream_ID;
      S2            : Http_Client.HTTP2.Frames.Stream_ID;
      SF            : Http_Client.HTTP2.Frames.Stream_ID;
      U1            : Http_Client.HTTP2.Frames.Stream_ID;
      U2            : Http_Client.HTTP2.Frames.Stream_ID;
      Frame         : Http_Client.HTTP2.Frames.Frame;
      Body1         : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Body2         : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer        : String (1 .. 4);
      Last          : Natural;
      Upload_Status : Http_Client.Errors.Result_Status;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Enable_Upload_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 2;
      Options.Max_Active_Streamed_Responses := 1;
      Options.Max_Active_Upload_Streams := 1;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first stream should open for HTTP/2 limit test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second stream should open for HTTP/2 limit test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "first request side should half-close");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "second request side should half-close");
      declare
         Rejected_Body : Http_Client.HTTP2.Body_Streams.Body_Stream;
      begin
         Assert
           (Http_Client.HTTP2.Body_Streams.Open
              (Conn'Unchecked_Access, S1, Rejected_Body)
            = Http_Client.Errors.HTTP2_Stream_State_Error,
            "public HTTP/2 response streams must not open before final "
            & "response headers are accepted");
      end;

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first streamed response headers should be accepted");
      Frame.Header.Stream := S2;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "second streamed response headers should be accepted");

      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, Body1)
         = Http_Client.Errors.Ok,
         "first public HTTP/2 response stream should reserve the only stream slot");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S2, Body2)
         = Http_Client.Errors.HTTP2_Stream_Limit_Reached,
         "second public response stream should respect Max_Active_Streamed_Responses");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (Body1, Buffer, Last)
         = Http_Client.Errors.Timeout
         and then Last = 0
         and then Http_Client.HTTP2.Body_Streams.Is_Open (Body1),
         "a public HTTP/2 stream with no queued DATA and no END_STREAM must not report false EOF");

      Frame.Header :=
        (Length       => 5,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA),
         Flags        => 16#09#,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (2),
              2 => 'h',
              3 => 'i',
              4 => Character'Val (0),
              5 => Character'Val (0)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "padded DATA with END_STREAM should be accepted when padding is valid");
      Assert
        (Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "hi",
         "HTTP/2 response streaming must deliver DATA bytes without pad length or padding bytes");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 2,
         "HTTP/2 receive flow control should keep only delivered body bytes "
         & "outstanding after padding is consumed internally");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (Body1, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 2
         and then Buffer (1 .. 2) = "hi",
         "public HTTP/2 response stream should read only decoded body bytes from padded DATA");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (Body1, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "public HTTP/2 response stream should reach EOF after padded END_STREAM is consumed");

      declare
         Flow_Options : Http_Client.HTTP2.HTTP2_Options := Options;
      begin
         Flow_Options.Initial_Connection_Window_Size := 1;
         Flow_Options.Initial_Stream_Window_Size := 1;
         Conn_Flow := Http_Client.HTTP2.Connection.Create (Flow_Options);
         Assert
           (Http_Client.HTTP2.Connection.Open_Stream (Conn_Flow, SF)
            = Http_Client.Errors.Ok,
            "flow-control violation test stream should open");
         Assert
           (Http_Client.HTTP2.Connection.End_Local_Stream (Conn_Flow, SF)
            = Http_Client.Errors.Ok,
            "flow-control violation test request side should half-close");
         Frame.Header :=
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => SF);
         Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
         Assert
           (Http_Client.HTTP2.Connection.Receive_Frame (Conn_Flow, Frame)
            = Http_Client.Errors.Ok,
            "headers should be accepted before receive flow-control violation");
         Frame.Header :=
           (Length       => 2,
            Kind         => Http_Client.HTTP2.Frames.DATA,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.DATA),
            Flags        => 0,
            Reserved_Bit => False,
            Stream       => SF);
         Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("zz");
         Assert
           (Http_Client.HTTP2.Connection.Receive_Frame (Conn_Flow, Frame)
            = Http_Client.Errors.HTTP2_Flow_Control_Error,
            "DATA exceeding receive flow-control windows should be a deterministic flow-control error");
         Assert
           (Http_Client.HTTP2.Connection.Retired (Conn_Flow),
            "receive flow-control violation should retire the HTTP/2 connection");
      end;

      Conn_Upload := Http_Client.HTTP2.Connection.Create (Options);
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn_Upload, U1)
         = Http_Client.Errors.Ok,
         "first upload stream should open for active-upload limit test");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn_Upload, U2)
         = Http_Client.Errors.Ok,
         "second upload stream should open for active-upload limit test");
      Assert
        (Http_Client.HTTP2.Connection.Begin_Upload_Stream (Conn_Upload, U1)
         = Http_Client.Errors.Ok,
         "first active upload stream should reserve the upload slot");
      Upload_Status :=
        Http_Client.HTTP2.Connection.Begin_Upload_Stream (Conn_Upload, U2);
      Assert
        (Upload_Status = Http_Client.Errors.HTTP2_Stream_Limit_Reached,
         "a second simultaneous HTTP/2 upload should not exceed the configured upload slot limit");
      Assert
        (Http_Client.HTTP2.Connection.End_Upload_Stream (Conn_Upload, U1)
         = Http_Client.Errors.Ok,
         "ending an upload reservation should release the upload slot");
      Assert
        (Http_Client.HTTP2.Connection.Begin_Upload_Stream (Conn_Upload, U2)
         = Http_Client.Errors.Ok,
         "released upload slot should allow a later active upload stream");
      Assert
        (Http_Client.HTTP2.Connection.End_Upload_Stream (Conn_Upload, U2)
         = Http_Client.Errors.Ok,
         "second upload reservation should release cleanly");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn_Upload, U2)
         = Http_Client.Errors.Ok,
         "test upload stream should become locally half-closed");
      Assert
        (Http_Client.HTTP2.Connection.Begin_Upload_Stream (Conn_Upload, U2)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "HTTP/2 upload reservation must not reopen a locally half-closed request stream");
   end Test_HTTP2_Public_Stream_Limits_Padding_And_Pending_Read;

   procedure Test_HTTP2_Public_Stream_Queue_Compaction_And_Bodyless_DATA
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      S3      : Http_Client.HTTP2.Frames.Stream_ID;
      S4      : Http_Client.HTTP2.Frames.Stream_ID;
      S5      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 4);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 4;
      Options.Max_Active_Streamed_Responses := 1;
      Options.Max_Per_Stream_Buffered_Bytes := 4;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for queue-compaction test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "request side should half-close for queue-compaction test");
      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response headers should be accepted for queue-compaction test");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "body stream should open for queue-compaction test");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 4;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("abcd");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first DATA chunk should fit the per-stream unread queue limit");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 4
         and then Buffer = "abcd",
         "reading the first chunk should consume and compact the queue");
      Assert
        (Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, S1) = 0
         and then
           Http_Client.HTTP2.Connection.Response_Body_Of (Conn, S1) = "",
         "consumed HTTP/2 DATA bytes should be removed from the unread queue");

      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("efgh");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "second DATA chunk should fit after the first chunk was consumed");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Ok
         and then Last = 4
         and then Buffer = "efgh",
         "second chunk should be readable after queue compaction");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "queue-compacted stream should still finish cleanly");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "stream should open for unread-close discard test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S2)
         = Http_Client.Errors.Ok,
         "request side should half-close for unread-close discard test");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Header.Stream := S2;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "headers should be accepted for unread-close discard test");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 2;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("xy");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "END_STREAM DATA should be queued for unread-close discard test");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S2, B)
         = Http_Client.Errors.Ok,
         "body stream should open with unread data already queued");
      Assert
        (Http_Client.HTTP2.Body_Streams.Close (B) = Http_Client.Errors.Ok,
         "closing after END_STREAM with unread DATA should discard and release cleanly");
      Assert
        (Http_Client.HTTP2.Connection.Active_Stream_Count (Conn) = 0,
         "closing a completed HTTP/2 stream with unread DATA should release its tracking slot");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S4)
         = Http_Client.Errors.Ok,
         "stream should open for half-closed-remote EOF test");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#05#;
      Frame.Header.Stream := S4;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS with END_STREAM should be accepted before local upload completion");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S4, B)
         = Http_Client.Errors.Ok,
         "body stream should open for a half-closed-remote HTTP/2 response");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "half-closed-remote HTTP/2 response with no queued DATA should report EOF, not Timeout");
      Assert
        (Http_Client.HTTP2.Connection.Stream_State_Of (Conn, S4)
         = Http_Client.HTTP2.Streams.Half_Closed_Remote,
         "EOF on the response side should not release an upload-capable half-closed-remote stream");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S5)
         = Http_Client.Errors.Ok,
         "second stream should open after half-closed-remote public response slot is released");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S5)
         = Http_Client.Errors.Ok,
         "second half-closed-remote slot test request side should half-close");
      Frame.Header.Stream := S5;
      Frame.Header.Flags := 16#04#;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "headers should be accepted after half-closed-remote public response slot release");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S5, B)
         = Http_Client.Errors.Ok,
         "released half-closed-remote public response slot should allow another streamed response");
      Assert
        (Http_Client.HTTP2.Body_Streams.Close (B) = Http_Client.Errors.Ok,
         "second streamed response slot should close cleanly");

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "stream should open for bodyless DATA rejection test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S3)
         = Http_Client.Errors.Ok,
         "request side should half-close for bodyless DATA rejection test");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#04#;
      Frame.Header.Stream := S3;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "headers should be accepted before marking response bodyless");
      Assert
        (Http_Client.HTTP2.Connection.Mark_Bodyless_Response (Conn, S3)
         = Http_Client.Errors.Ok,
         "bodyless response marker should be accepted after headers");
      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Protocol_Error,
         "bodyless HTTP/2 responses should reject DATA frames even when the DATA payload is empty");
   end Test_HTTP2_Public_Stream_Queue_Compaction_And_Bodyless_DATA;

   procedure Test_HTTP2_Reset_Public_Stream_Releases_Slot
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 4);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for public reset-release test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "request side should half-close before response headers");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response headers should be accepted before peer reset");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "public body stream should open before peer reset");

      Frame.Header :=
        (Length       => 4,
         Kind         => Http_Client.HTTP2.Frames.RST_STREAM,
         Raw_Type     =>
           Http_Client.HTTP2.Frames.Type_Code
             (Http_Client.HTTP2.Frames.RST_STREAM),
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => S1);
      Frame.Payload :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (String'
             (1 => Character'Val (0),
              2 => Character'Val (0),
              3 => Character'Val (0),
              4 => Character'Val (8)));
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_Reset,
         "peer RST_STREAM should reset the addressed public response stream");
      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.HTTP2_Stream_Reset,
         "public body stream read should report the reset deterministically");
      Assert
        (Http_Client.HTTP2.Connection.Active_Stream_Count (Conn) = 0,
         "observing a peer reset through the public body stream should release the stream slot");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok
         and then S2 = 3,
         "released reset stream should allow a later stream without reusing stream IDs");
   end Test_HTTP2_Reset_Public_Stream_Releases_Slot;

   procedure Test_HTTP2_Terminal_Public_Stream_Errors_Release_Slots
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 4);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Options.Max_Per_Stream_Buffered_Bytes := 8;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for terminal public-stream error cleanup test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "request side should half-close before response headers");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response headers should be accepted before unsupported trailer test");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "public body stream should open before a terminal protocol error");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 2;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("ab");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "queued DATA should consume receive-window capacity before trailer rejection");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 2,
         "queued DATA should remain flow-control outstanding before terminal cleanup");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.HEADERS;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.HEADERS);
      Frame.Header.Length := 0;
      Frame.Header.Flags := 16#05#;
      Frame.Payload := Ada.Strings.Unbounded.Null_Unbounded_String;
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "Phase 10 trailing HEADERS should close the response stream cleanly");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 1;
      Frame.Header.Flags := 16#01#;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("x");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "DATA after trailing HEADERS should fail the stream deterministically");

      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.HTTP2_Stream_State_Error,
         "public read should surface the DATA-after-trailers stream error");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size,
         "terminal error observation should credit queued unread DATA before release");
      Assert
        (Http_Client.HTTP2.Connection.Active_Stream_Count (Conn) = 0,
         "terminal public-stream error observation should release the stream slot");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok
         and then S2 = 3,
         "terminal public-stream error cleanup should allow a later stream without ID reuse");
   end Test_HTTP2_Terminal_Public_Stream_Errors_Release_Slots;

   procedure Test_HTTP2_DATA_Terminal_Error_Credits_Queued_Bytes
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
      Conn    : aliased Http_Client.HTTP2.Connection.Connection_State;
      S1      : Http_Client.HTTP2.Frames.Stream_ID;
      S2      : Http_Client.HTTP2.Frames.Stream_ID;
      Frame   : Http_Client.HTTP2.Frames.Frame;
      B       : Http_Client.HTTP2.Body_Streams.Body_Stream;
      Buffer  : String (1 .. 4);
      Last    : Natural;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Enable_Public_Streaming := True;
      Options.Local_Max_Concurrent_Streams := 1;
      Options.Max_Per_Stream_Buffered_Bytes := 2;
      Conn := Http_Client.HTTP2.Connection.Create (Options);

      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "stream should open for DATA terminal-error cleanup test");
      Assert
        (Http_Client.HTTP2.Connection.End_Local_Stream (Conn, S1)
         = Http_Client.Errors.Ok,
         "request side should half-close before response DATA");

      Frame :=
        (Header  =>
           (Length       => 0,
            Kind         => Http_Client.HTTP2.Frames.HEADERS,
            Raw_Type     =>
              Http_Client.HTTP2.Frames.Type_Code
                (Http_Client.HTTP2.Frames.HEADERS),
            Flags        => 16#04#,
            Reserved_Bit => False,
            Stream       => S1),
         Payload => Ada.Strings.Unbounded.Null_Unbounded_String);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "response HEADERS should be accepted before DATA terminal-error test");
      Assert
        (Http_Client.HTTP2.Body_Streams.Open (Conn'Unchecked_Access, S1, B)
         = Http_Client.Errors.Ok,
         "public body stream should open before DATA terminal error");

      Frame.Header.Kind := Http_Client.HTTP2.Frames.DATA;
      Frame.Header.Raw_Type :=
        Http_Client.HTTP2.Frames.Type_Code (Http_Client.HTTP2.Frames.DATA);
      Frame.Header.Length := 2;
      Frame.Header.Flags := 0;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("ab");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Ok,
         "first DATA frame should queue exactly at the configured limit");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size - 2,
         "queued DATA should consume receive-window capacity before terminal DATA error");

      Frame.Header.Length := 1;
      Frame.Payload := Ada.Strings.Unbounded.To_Unbounded_String ("c");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame (Conn, Frame)
         = Http_Client.Errors.Response_Too_Large,
         "DATA beyond per-stream queue limit should fail the stream deterministically");
      Assert
        (Http_Client.HTTP2.Connection.Connection_Receive_Window (Conn)
         = Options.Initial_Connection_Window_Size,
         "terminal DATA error should immediately credit previously queued unread DATA");

      Assert
        (Http_Client.HTTP2.Body_Streams.Read_Some (B, Buffer, Last)
         = Http_Client.Errors.Response_Too_Large,
         "public body stream should surface the original DATA terminal error");
      Assert
        (Http_Client.HTTP2.Connection.Active_Stream_Count (Conn) = 0,
         "observing a DATA terminal error should release stream bookkeeping");
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, S2)
         = Http_Client.Errors.Ok
         and then S2 = 3,
         "DATA terminal-error cleanup should allow a later stream without ID reuse");
   end Test_HTTP2_DATA_Terminal_Error_Credits_Queued_Bytes;

   procedure Test_HTTP2_Git_Metadata_And_Binary_Body
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request : Http_Client.Requests.Request;
      H2_H    : Http_Client.Headers.Header_List;
      Git_Body : constant Ada.Streams.Stream_Element_Array :=
        [1 => 16#30#, 2 => 16#30#, 3 => 16#30#, 4 => 16#8#,
         5 => 0, 6 => 16#80#, 7 => 16#FF#];
   begin
      Assert_Parse_Ok
        ("https://example.com/repo.git/git-upload-pack",
         URI,
         "HTTP/2 Git URI should parse");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers,
            "Content-Type",
            "application/x-git-upload-pack-request"),
         "HTTP/2 Git content type should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers,
            "Accept",
            "application/x-git-upload-pack-result"),
         "HTTP/2 Git accept header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2"),
         "HTTP/2 Git-Protocol header should be accepted");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "HTTP/2 Git request should construct");
      Assert
        (Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Bytes (Git_Body))
         = Http_Client.Errors.Ok,
         "HTTP/2 Git request should accept binary body");
      Assert
        (Http_Client.HTTP2.Mapping.Build_Request_Headers (Request, H2_H)
         = Http_Client.Errors.Ok,
         "HTTP/2 Git request headers should map to h2 pseudo/ordinary fields");
      Assert
        (Http_Client.Headers.Get (H2_H, ":method") = "POST",
         "HTTP/2 Git POST should map to :method");
      Assert
        (Http_Client.Headers.Get (H2_H, ":path") = "/repo.git/git-upload-pack",
         "HTTP/2 Git path should map to :path");
      Assert
        (Http_Client.Headers.Get (H2_H, "git-protocol") = "version=2",
         "HTTP/2 Git-Protocol should be lowercased and preserved");
      Assert
        (Http_Client.Headers.Get (H2_H, "content-type") =
         "application/x-git-upload-pack-request",
         "HTTP/2 Git content-type value should be preserved exactly");
      Assert
        (Http_Client.Request_Bodies.Buffered_Bytes
           (Http_Client.Requests.Request_Body (Request)) = Git_Body,
         "HTTP/2 Git binary body bytes should be preserved exactly");
   end Test_HTTP2_Git_Metadata_And_Binary_Body;

   procedure Test_Phase37_HPACK_QPACK_And_Frame_Fuzz_Corpus
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      H2_Header : Http_Client.HTTP2.Frames.Frame_Header;
      H2_Frame  : Http_Client.HTTP2.Frames.Frame;
      H3_Frame  : Http_Client.HTTP3.Frames.Frame;
      H3_Value  : Http_Client.HTTP3.Frames.Varint_Value;
      Q_Value   : Http_Client.HTTP3.QPACK.QPACK_Integer;
      Consumed  : Natural := 0;
      Position  : Positive := 1;
      H_Int     : Natural := 0;
      Field     : Http_Client.HTTP3.QPACK.Header_Field;
      Headers   : Http_Client.Headers.Header_List;
      Decoder   : Http_Client.HTTP2.HPACK.Decoder :=
        Http_Client.HTTP2.HPACK.Create_Decoder
          (Max_Dynamic_Table_Size => 32, Max_Header_List_Size => 64);
      Status    : Http_Client.Errors.Result_Status;
   begin
      declare
         Short_Header : Http_Client.HTTP2.Frames.Frame_Header;
         pragma Unreferenced (Short_Header);
      begin
         Status := Http_Client.HTTP2.Frames.Parse_Header ("abc", Short_Header);
         Assert
           (Status = Http_Client.Errors.Incomplete_Message,
            "short HTTP/2 frame header should be incomplete");
      end;
      H2_Header :=
        (Length       => 20_000,
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     => 0,
         Flags        => 0,
         Reserved_Bit => False,
         Stream       => 1);
      Status :=
        Http_Client.HTTP2.Frames.Validate_Header
          (H2_Header, Max_Frame_Size => 16_384);
      Assert
        (Status = Http_Client.Errors.Response_Too_Large,
         "oversized HTTP/2 frame length should fail before payload allocation");
      Status :=
        Http_Client.HTTP2.Frames.Parse_Frame
          (Http_Client.HTTP2.Frames.Serialize_Header
             ((Length       => 1,
               Kind         => Http_Client.HTTP2.Frames.PING,
               Raw_Type     => 0,
               Flags        => 0,
               Reserved_Bit => False,
               Stream       => 0))
           & "x",
           Max_Frame_Size => 16_384,
           Item           => H2_Frame);
      Assert
        (Status = Http_Client.Errors.HTTP2_Frame_Error,
         "invalid PING payload length should be rejected");

      Status :=
        Http_Client.HTTP2.HPACK.Decode_Integer
          (Character'Val (16#1F#) & Character'Val (16#80#),
           Position,
           Prefix_Bits => 5,
           Value       => H_Int);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "truncated HPACK integer continuation should fail");
      Status :=
        Http_Client.HTTP2.HPACK.Decode_Header_Block
          (Decoder, Character'Val (16#82#) & Character'Val (16#00#), Headers);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "malformed or trailing HPACK header block should fail deterministically");

      Status :=
        Http_Client.HTTP3.Frames.Decode_Varint
          ("" & Character'Val (16#80#), H3_Value, Consumed);
      Assert
        (Status = Http_Client.Errors.Incomplete_Message,
         "truncated HTTP/3 varint should be incomplete");
      Status :=
        Http_Client.HTTP3.Frames.Parse_Frame
          (Http_Client.HTTP3.Frames.Encode_Varint
             (Http_Client.HTTP3.Frames.Type_Code
                (Http_Client.HTTP3.Frames.HEADERS))
           & Http_Client.HTTP3.Frames.Encode_Varint (32)
           & "tiny",
           Max_Frame_Size => 16,
           Item           => H3_Frame);
      Assert
        (Status = Http_Client.Errors.Response_Too_Large,
         "oversized HTTP/3 frame should fail before accepting payload");
      Status :=
        Http_Client.HTTP3.QPACK.Decode_Integer
          ("" & Character'Val (16#FF#),
           Prefix_Bits => 6,
           Value       => Q_Value,
           Consumed    => Consumed);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "truncated QPACK integer should fail");
      Status :=
        Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
          (Character'Val (16#20#) & Character'Val (16#80#), Field, Consumed);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "truncated QPACK literal field line should fail");
      Status := Http_Client.HTTP3.QPACK.Validate_Header_Name ("authorization");
      Assert
        (Status = Http_Client.Errors.Ok,
         "ordinary lowercase QPACK header names should validate");
      Status := Http_Client.HTTP3.QPACK.Validate_Header_Name ("Authorization");
      Assert
        (Status = Http_Client.Errors.HTTP3_QPACK_Error,
         "uppercase QPACK header names should be rejected");
      Status :=
        Http_Client.HTTP3.QPACK.Validate_Header_Name
          ("Bad" & Character'Val (13));
      Assert
        (Status = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK header-name validation should reject controls");
   end Test_Phase37_HPACK_QPACK_And_Frame_Fuzz_Corpus;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("HTTP2");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_HTTP2_ALPN_And_Config'Access,
         "Test_HTTP2_ALPN_And_Config");
      Register_Routine
        (T,
         Test_HTTP2_Preface_And_Settings'Access,
         "Test_HTTP2_Preface_And_Settings");
      Register_Routine
        (T,
         Test_HTTP2_Frame_Header_And_Frame_Validation'Access,
         "Test_HTTP2_Frame_Header_And_Frame_Validation");
      Register_Routine
        (T,
         Test_HTTP2_Request_Response_Mapping_And_HPACK'Access,
         "Test_HTTP2_Request_Response_Mapping_And_HPACK");
      Register_Routine
        (T,
         Test_HTTP2_Single_Stream_Scripted_Execution'Access,
         "Test_HTTP2_Single_Stream_Scripted_Execution");
      Register_Routine
        (T, Test_HTTP2_Stream_State'Access, "Test_HTTP2_Stream_State");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Requires_Explicit_Enablement'Access,
         "Test_HTTP2_Multiplexed_Requires_Explicit_Enablement");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Stream_Limits_And_Goaway'Access,
         "Test_HTTP2_Multiplexed_Stream_Limits_And_Goaway");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Goaway_Classifies_Active_Streams'Access,
         "Test_HTTP2_Multiplexed_Goaway_Classifies_Active_Streams");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Goaway_Allows_Accepted_Stream_Completion'Access,
         "Test_HTTP2_Multiplexed_Goaway_Allows_Accepted_Stream_Completion");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Goaway_Rejects_Server_Stream_Boundary'Access,
         "Test_HTTP2_Multiplexed_Goaway_Rejects_Server_Stream_Boundary");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Goaway_Rejects_Unissued_Stream'Access,
         "Test_HTTP2_Multiplexed_Goaway_Rejects_Unissued_Stream");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Interleaved_Data_And_Reset'Access,
         "Test_HTTP2_Multiplexed_Interleaved_Data_And_Reset");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Flow_Control_And_Settings'Access,
         "Test_HTTP2_Multiplexed_Flow_Control_And_Settings");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Frame_Validation'Access,
         "Test_HTTP2_Multiplexed_Frame_Validation");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted'Access,
         "Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Invalid_Transitions_Do_Not_Mutate'Access,
         "Test_HTTP2_Multiplexed_Invalid_Transitions_Do_Not_Mutate");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Continuation_State_Commits_Only_On_Success'Access,
         "Test_HTTP2_Multiplexed_Continuation_State_Commits_Only_On_Success");
      Register_Routine
        (T,
         Test_HTTP2_Multiplexed_Content_Length_And_Bodyless'Access,
         "Test_HTTP2_Multiplexed_Content_Length_And_Bodyless");
      Register_Routine
        (T,
         Test_HTTP2_Response_Body_Stream_Reads_And_Early_Close'Access,
         "Test_HTTP2_Response_Body_Stream_Reads_And_Early_Close");
      Register_Routine
        (T,
         Test_HTTP2_Response_Data_Credit_Prevents_Double_Window_Update'Access,
         "Test_HTTP2_Response_Data_Credit_Prevents_Double_Window_Update");
      Register_Routine
        (T,
         Test_HTTP2_Total_Queued_Body_Limit_Is_Connection_Wide'Access,
         "Test_HTTP2_Total_Queued_Body_Limit_Is_Connection_Wide");
      Register_Routine
        (T,
         Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes'Access,
         "Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes");
      Register_Routine
        (T,
         Test_HTTP2_Upload_Body_Streaming'Access,
         "Test_HTTP2_Upload_Body_Streaming");
      Register_Routine
        (T,
         Test_HTTP2_Execution_Common_Request_Body_Contracts'Access,
         "Test_HTTP2_Execution_Common_Request_Body_Contracts");
      Register_Routine
        (T,
         Test_HTTP2_Request_Trailers_As_Trailing_HEADERS'Access,
         "Test_HTTP2_Request_Trailers_As_Trailing_HEADERS");
      Register_Routine
        (T,
         Test_HTTP2_Request_Trailer_Forbidden_Names_Rejected'Access,
         "Test_HTTP2_Request_Trailer_Forbidden_Names_Rejected");
      Register_Routine
        (T,
         Test_HTTP2_Response_Trailers_Not_Body_And_Forbid_Data_After'Access,
         "Test_HTTP2_Response_Trailers_Not_Body_And_Forbid_Data_After");
      Register_Routine
        (T,
         Test_HTTP2_Public_Stream_Limits_Padding_And_Pending_Read'Access,
         "Test_HTTP2_Public_Stream_Limits_Padding_And_Pending_Read");
      Register_Routine
        (T,
         Test_HTTP2_Public_Stream_Queue_Compaction_And_Bodyless_DATA'Access,
         "Test_HTTP2_Public_Stream_Queue_Compaction_And_Bodyless_DATA");
      Register_Routine
        (T,
         Test_HTTP2_Reset_Public_Stream_Releases_Slot'Access,
         "Test_HTTP2_Reset_Public_Stream_Releases_Slot");
      Register_Routine
        (T,
         Test_HTTP2_Terminal_Public_Stream_Errors_Release_Slots'Access,
         "Test_HTTP2_Terminal_Public_Stream_Errors_Release_Slots");
      Register_Routine
        (T,
         Test_HTTP2_DATA_Terminal_Error_Credits_Queued_Bytes'Access,
         "Test_HTTP2_DATA_Terminal_Error_Credits_Queued_Bytes");
      Register_Routine
        (T,
         Test_HTTP2_Git_Metadata_And_Binary_Body'Access,
         "Test_HTTP2_Git_Metadata_And_Binary_Body");
      Register_Routine
        (T,
         Test_Phase37_HPACK_QPACK_And_Frame_Fuzz_Corpus'Access,
         "Test_Phase37_HPACK_QPACK_And_Frame_Fuzz_Corpus");
   end Register_Tests;

end Http_Client.HTTP2.Tests;
