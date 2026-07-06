with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;
with Http_Client.Ada_Test_Fixtures;
with Http_Client.Cache;

with Http_Client.Clients;
with Http_Client.Connection_Pools;

with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;

with Http_Client.HTTP1;
with Http_Client.HTTP2;

with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.TLS.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Transports.TCP.Timeout_Milliseconds;

   Diagnostic_Callback_Count : Natural := 0;
   Diagnostic_Fail_Next      : Boolean := False;

   package Fixtures renames Http_Client.Ada_Test_Fixtures;

   Fixture_Fixed_Response   : constant Fixtures.Fixture_Mode :=
     Fixtures.TLS_Fixed_Response;
   Fixture_Chunked_Response : constant Fixtures.Fixture_Mode :=
     Fixtures.TLS_Chunked_Response;
   Fixture_Expect_Response  : constant Fixtures.Fixture_Mode :=
     Fixtures.TLS_Expect_Response;
   Fixture_OK_Response      : constant Fixtures.Fixture_Mode :=
     Fixtures.TLS_OK_Response;
   Fixture_H2_Large_Response : constant Fixtures.Fixture_Mode :=
     Fixtures.TLS_H2_Large_Response;

   H2_Large_Response_Size    : constant Natural := 98_304;
   H2_Response_Chunk_Size    : constant Natural := 16_384;

   Fixture_CA_File_Name        : constant String := "ca.crt";
   Fixture_Server_Cert_Name    : constant String := "server.crt";
   Fixture_Server_Key_Name     : constant String := "server.key";
   Fixture_Wronghost_Cert_Name : constant String := "wronghost-server.crt";
   Fixture_Wronghost_Key_Name  : constant String := "wronghost-server.key";

   function Decimal_Image (Value : Natural) return String;
   function Fixture_Path (Leaf_Name : String) return String;

   function Fixture_Path (Leaf_Name : String) return String is
      Candidates : constant array (Positive range <>) of
        Ada.Strings.Unbounded.Unbounded_String :=
          [Ada.Strings.Unbounded.To_Unbounded_String
             ("tests/fixtures/tls/" & Leaf_Name),
           Ada.Strings.Unbounded.To_Unbounded_String
             ("fixtures/tls/" & Leaf_Name),
           Ada.Strings.Unbounded.To_Unbounded_String
             ("../fixtures/tls/" & Leaf_Name),
           Ada.Strings.Unbounded.To_Unbounded_String
             ("../../tests/fixtures/tls/" & Leaf_Name),
           Ada.Strings.Unbounded.To_Unbounded_String
             ("../../../tests/fixtures/tls/" & Leaf_Name)];
   begin
      for Candidate of Candidates loop
         declare
            Path : constant String :=
              Ada.Strings.Unbounded.To_String (Candidate);
         begin
            if Exists (Path) then
               return Path;
            end if;
         end;
      end loop;

      return "tests/fixtures/tls/" & Leaf_Name;
   end Fixture_Path;

   function Binary_Test_String return String is
      Result : String (1 .. 7);
   begin
      Result (1) := Character'Val (16#00#);
      Result (2) := Character'Val (16#0D#);
      Result (3) := Character'Val (16#0A#);
      Result (4) := Character'Val (16#80#);
      Result (5) := Character'Val (16#FF#);
      Result (6) := 'P';
      Result (7) := 'K';
      return Result;
   end Binary_Test_String;

   function Binary_Test_Bytes return Ada.Streams.Stream_Element_Array is
   begin
      return
        [1 => 16#00#,
         2 => 16#0D#,
         3 => 16#0A#,
         4 => 16#80#,
         5 => 16#FF#,
         6 => Character'Pos ('P'),
         7 => Character'Pos ('K')];
   end Binary_Test_Bytes;

   function Start_TLS_Fixture
     (Mode                     : Fixtures.Fixture_Mode;
      Certificate_File_Name    : String := Fixture_Server_Cert_Name;
      Private_Key_File_Name    : String := Fixture_Server_Key_Name) return Natural
   is
      Port : Natural;
   begin
      Fixtures.Stop_TLS;
      Port :=
        Fixtures.Start_TLS
          (Fixture_Path (Certificate_File_Name),
           Fixture_Path (Private_Key_File_Name),
           Mode);
      Assert
        (Port > 0, "direct TLS fixture should start on an ephemeral port");
      return Port;
   end Start_TLS_Fixture;

   function Fixture_URL
     (Port : Natural; Host : String := "127.0.0.1") return String is
   begin
      return "https://" & Host & ":" & Decimal_Image (Port) & "/phase4";
   end Fixture_URL;

   function Build_HTTPS_Request
     (Port    : Natural;
      Method  : Http_Client.Types.Method_Name := Http_Client.Types.GET;
      Host    : String := "127.0.0.1";
      Payload : String := "") return Http_Client.Requests.Request
   is
      Parsed  : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse (Fixture_URL (Port, Host), Parsed);
      Assert
        (Status = Http_Client.Errors.Ok, "HTTPS fixture URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method  => Method,
           URI     => Parsed,
           Item    => Request,
           Payload => Payload);
      Assert
        (Status = Http_Client.Errors.Ok, "HTTPS fixture request should build");
      return Request;
   end Build_HTTPS_Request;

   function Verified_TLS_Options return Http_Client.Clients.Execution_Options
   is
      Options : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
   begin
      Options.TLS.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (Fixture_Path (Fixture_CA_File_Name));
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
      return Options;
   end Verified_TLS_Options;

   function Verified_Streaming_Options
      return Http_Client.Response_Streams.Streaming_Options
   is
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
   begin
      Options.TLS.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (Fixture_Path (Fixture_CA_File_Name));
      Options.Protocol_Policy :=
        Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;
      return Options;
   end Verified_Streaming_Options;

   procedure Assert_Binary_Body
     (Actual : Ada.Streams.Stream_Element_Array; Message : String)
   is
      Expected : constant Ada.Streams.Stream_Element_Array :=
        Binary_Test_Bytes;
   begin
      Assert (Actual'Length = Expected'Length, Message & " length mismatch");
      for Offset in 0 .. Expected'Length - 1 loop
         Assert
           (Actual (Actual'First + Ada.Streams.Stream_Element_Offset (Offset))
            = Expected
                (Expected'First + Ada.Streams.Stream_Element_Offset (Offset)),
            Message & " byte mismatch at offset" & Natural'Image (Offset));
      end loop;
   end Assert_Binary_Body;

   function Captured_Request_Contains (Needle : String) return Boolean is
   begin
      return Fixtures.TLS_Request_Contains (Needle);
   end Captured_Request_Contains;

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

   procedure Test_TLS_Metadata_After_Handshake
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Port    : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Conn    : Http_Client.Transports.TLS.Connection;
      Options : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Options.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (Fixture_Path (Fixture_CA_File_Name));

      Status := Http_Client.Transports.TLS.Open
        (Item    => Conn,
         Host    => "127.0.0.1",
         Port    => Http_Client.URI.TCP_Port (Port),
         Options => Options);

      Assert
        (Status = Http_Client.Errors.Ok,
         "verified TLS open should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Transports.TLS.TLS_Version (Conn)'Length > 0,
         "open TLS connection should expose negotiated protocol version");
      Assert
        (Http_Client.Transports.TLS.TLS_Version (Conn) /= "TLSv1"
         and then Http_Client.Transports.TLS.TLS_Version (Conn) /= "TLSv1.1"
         and then Http_Client.Transports.TLS.TLS_Version (Conn) /= "SSLv3",
         "negotiated TLS version should respect the TLS 1.2+ floor");
      Assert
        (Http_Client.Transports.TLS.Cipher_Name (Conn)'Length > 0,
         "open TLS connection should expose negotiated cipher name");

      Assert
        (Http_Client.Transports.TLS.Close (Conn) = Http_Client.Errors.Ok,
         "closing metadata test TLS connection should succeed");
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end Test_TLS_Metadata_After_Handshake;

   procedure Test_TLS_Defaults_And_Not_Connected
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Conn   : Http_Client.Transports.TLS.Connection;
      Buffer : String (1 .. 16);
      Count  : Natural := 99;
   begin
      Assert
        (Http_Client.Transports.TLS.Verification_Enabled_By_Default,
         "TLS certificate verification should be enabled by default");

      Assert
        (not Http_Client
               .Transports
               .TLS
               .Default_TLS_Options
               .Disable_Certificate_Verification,
         "default TLS options must not disable certificate verification");

      Assert
        (Http_Client.Transports.TLS.Default_TLS_Options.Send_SNI,
         "default TLS options should send SNI for suitable DNS names");

      Assert
        (not Http_Client.Transports.TLS.Is_Open (Conn),
         "new TLS connection should start closed");

      Assert
        (Http_Client.Transports.TLS.Write_All (Conn, "GET / HTTP/1.1")
         = Http_Client.Errors.Not_Connected,
         "Write_All on a closed TLS connection should report Not_Connected");

      Assert
        (Http_Client.Transports.TLS.Read_Some (Conn, Buffer, Count)
         = Http_Client.Errors.Not_Connected,
         "Read_Some on a closed TLS connection should report Not_Connected");

      Assert
        (Count = 0,
         "TLS Read_Some failure should leave returned byte count as zero");

      Assert
        (Http_Client.Transports.TLS.Close (Conn) = Http_Client.Errors.Ok,
         "closing an already closed TLS connection should be safe");
   end Test_TLS_Defaults_And_Not_Connected;

   procedure Test_TLS_Rejects_HTTP_URI
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Conn   : Http_Client.Transports.TLS.Connection;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("http://example.com/", URI, "HTTP URI for unsupported TLS open");

      Status := Http_Client.Transports.TLS.Open_URI (Conn, URI);

      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "TLS Open_URI should reject HTTP instead of silently changing schemes");

      Assert
        (not Http_Client.Transports.TLS.Is_Open (Conn),
         "failed HTTP Open_URI should leave TLS connection closed");
   end Test_TLS_Rejects_HTTP_URI;

   procedure Test_TLS_Rejects_NUL_C_Strings
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.Transports.TLS.Connection;
      Options : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
   begin
      Assert
        (Http_Client.Transports.TLS.Open
           (Item => Conn,
            Host => "example" & Character'Val (0) & ".com",
            Port => 443)
         = Http_Client.Errors.Invalid_URI,
         "TLS Open should reject embedded NUL in host before calling C");

      Assert
        (not Http_Client.Transports.TLS.Is_Open (Conn),
         "invalid NUL host should leave TLS connection closed");

      Options.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          ("ca" & Character'Val (0) & ".pem");

      Assert
        (Http_Client.Transports.TLS.Open
           (Item    => Conn,
            Host    => "example.com",
            Port    => 443,
            Options => Options)
         = Http_Client.Errors.CA_Store_Failed,
         "TLS Open should reject embedded NUL in CA file path before calling C");

      Assert
        (not Http_Client.Transports.TLS.Is_Open (Conn),
         "invalid NUL CA path should leave TLS connection closed");
   end Test_TLS_Rejects_NUL_C_Strings;

   procedure Test_TLS_Option_Validation
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
   begin
      Assert
        (Http_Client.Transports.TLS.Validate_Options (Options)
         = Http_Client.Errors.Ok,
         "default TLS options should validate deterministically");

      Options.CA_Directory :=
        Ada.Strings.Unbounded.To_Unbounded_String
          ("certs" & Character'Val (0));

      Assert
        (Http_Client.Transports.TLS.Validate_Options (Options)
         = Http_Client.Errors.CA_Store_Failed,
         "TLS option validation should reject embedded NUL in CA directory");

      Options := Http_Client.Transports.TLS.Default_TLS_Options;
      Options.Disable_Certificate_Verification := True;
      Options.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String ("test-ca.pem");

      Assert
        (Http_Client.Transports.TLS.Validate_Options (Options)
         = Http_Client.Errors.Invalid_Request,
         "TLS option validation should reject ignored CA settings when verification is disabled");
   end Test_TLS_Option_Validation;

   procedure Test_TLS_Client_Certificate_Config_And_Scope
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      HTTPS_A : Http_Client.URI.URI_Reference;
      HTTPS_B : Http_Client.URI.URI_Reference;
      HTTP_A  : Http_Client.URI.URI_Reference;
      Base    : Http_Client.TLS.Client_Certificates.Client_Certificate;
      Scoped  : Http_Client.TLS.Client_Certificates.Client_Certificate;
      Invalid : Http_Client.TLS.Client_Certificates.Client_Certificate;
      Options : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
   begin
      Assert_Parse_Ok
        ("https://mtls.example:9443/resource",
         HTTPS_A,
         "HTTPS URI for client-certificate scope");
      Assert_Parse_Ok
        ("https://other.example:9443/resource",
         HTTPS_B,
         "different HTTPS URI for client-certificate scope");
      Assert_Parse_Ok
        ("http://mtls.example/resource",
         HTTP_A,
         "HTTP URI for client-certificate rejection");

      Assert
        (not Http_Client.TLS.Client_Certificates.Is_Configured
               (Http_Client.TLS.Client_Certificates.No_Client_Certificate),
         "client certificates must be disabled by default");

      Base :=
        Http_Client.TLS.Client_Certificates.From_PEM_Files
          (Certificate_File => "client.pem", Private_Key_File => "client.key");

      Assert
        (Http_Client.TLS.Client_Certificates.Is_Configured (Base),
         "PEM-file constructor should explicitly enable a client certificate");

      Assert
        (not Base.Has_Passphrase,
         "omitting a client-key passphrase should leave passphrase mode disabled");

      declare
         With_Nonempty_Passphrase :
           constant Http_Client.TLS.Client_Certificates.Client_Certificate :=
             Http_Client.TLS.Client_Certificates.From_PEM_Files
               (Certificate_File => "client.pem",
                Private_Key_File => "client.key",
                Passphrase       => "secret");
         With_Empty_Passphrase    :
           constant Http_Client.TLS.Client_Certificates.Client_Certificate :=
             Http_Client.TLS.Client_Certificates.From_PEM_Files
               (Certificate_File => "client.pem",
                Private_Key_File => "client.key",
                Passphrase       => "",
                Has_Passphrase   => True);
      begin
         Assert
           (With_Nonempty_Passphrase.Has_Passphrase,
            "a non-empty client-key passphrase should enable passphrase mode automatically");

         Assert
           (With_Empty_Passphrase.Has_Passphrase,
            "an explicitly empty client-key passphrase should remain distinguishable from no passphrase");
      end;

      Assert
        (Http_Client.TLS.Client_Certificates.Validate (Base)
         = Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch,
         "non-broad client certificates should require an explicit HTTPS origin scope");

      Scoped := Http_Client.TLS.Client_Certificates.For_Origin (Base, HTTPS_A);

      Assert
        (Http_Client.TLS.Client_Certificates.Validate (Scoped)
         = Http_Client.Errors.Ok,
         "origin-scoped client certificate should validate");

      Assert
        (Http_Client.TLS.Client_Certificates.Matches (Scoped, HTTPS_A),
         "client certificate should match its configured HTTPS origin");

      Assert
        (not Http_Client.TLS.Client_Certificates.Matches (Scoped, HTTPS_B),
         "client certificate should not match a different redirect origin");

      Assert
        (not Http_Client.TLS.Client_Certificates.Matches (Scoped, HTTP_A),
         "client certificate should never match a plain HTTP origin");

      Options.Client_Certificate := Scoped;
      Assert
        (Http_Client.Transports.TLS.Validate_Options (Options)
         = Http_Client.Errors.Ok,
         "TLS options should accept a valid scoped client certificate without disabling server verification");

      Assert
        (not Options.Disable_Certificate_Verification,
         "configuring a client certificate must not disable server verification");

      declare
         Conn : Http_Client.Transports.TLS.Connection;
      begin
         Assert
           (Http_Client.Transports.TLS.Open
              (Item    => Conn,
               Host    => "other.example",
               Port    => 9443,
               Options => Options)
            = Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch,
            "TLS Open must reject cross-origin client-certificate scope before network I/O");
      end;

      Invalid :=
        Http_Client.TLS.Client_Certificates.From_PEM_Files
          (Certificate_File => "client" & Character'Val (0) & ".pem",
           Private_Key_File => "client.key",
           Allow_Any_Origin => True);
      Options := Http_Client.Transports.TLS.Default_TLS_Options;
      Options.Client_Certificate := Invalid;

      Assert
        (Http_Client.Transports.TLS.Validate_Options (Options)
         = Http_Client.Errors.TLS_Client_Certificate_Configuration_Invalid,
         "TLS option validation should reject NUL-bearing client certificate paths before C calls");
   end Test_TLS_Client_Certificate_Config_And_Scope;

   procedure Test_TLS_Client_Certificate_Pool_Key_Boundary
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI            : Http_Client.URI.URI_Reference;
      URI_Other      : Http_Client.URI.URI_Reference;
      Plain_TLS      : constant Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      TLS_A          : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      TLS_B          : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Key_None       : Http_Client.Connection_Pools.Pool_Key;
      Key_None_Other : Http_Client.Connection_Pools.Pool_Key;
      Key_A          : Http_Client.Connection_Pools.Pool_Key;
      Key_A_Again    : Http_Client.Connection_Pools.Pool_Key;
      Key_B          : Http_Client.Connection_Pools.Pool_Key;
      Key_A_Other    : Http_Client.Connection_Pools.Pool_Key;
      Credential_A   : Http_Client.TLS.Client_Certificates.Client_Certificate;
      Credential_B   : Http_Client.TLS.Client_Certificates.Client_Certificate;
   begin
      Assert_Parse_Ok
        ("https://pool.example/resource",
         URI,
         "HTTPS URI for client-certificate pool key");
      Assert_Parse_Ok
        ("https://other-pool.example/resource",
         URI_Other,
         "different HTTPS URI for client-certificate pool key scope");

      Credential_A :=
        Http_Client.TLS.Client_Certificates.For_Origin
          (Http_Client.TLS.Client_Certificates.From_PEM_Files
             (Certificate_File => "a-client.pem",
              Private_Key_File => "a-client.key"),
           URI);
      Credential_B :=
        Http_Client.TLS.Client_Certificates.For_Origin
          (Http_Client.TLS.Client_Certificates.From_PEM_Files
             (Certificate_File => "b-client.pem",
              Private_Key_File => "b-client.key"),
           URI);

      --  Force an identifier collision to verify that the private pool key
      --  discriminator is exact and not solely hash/id based.
      Credential_B.Identifier := Credential_A.Identifier;

      TLS_A.Client_Certificate := Credential_A;
      TLS_B.Client_Certificate := Credential_B;

      Key_None := Http_Client.Connection_Pools.Key_For (URI, TLS => Plain_TLS);
      Key_None_Other :=
        Http_Client.Connection_Pools.Key_For (URI_Other, TLS => Plain_TLS);
      Key_A := Http_Client.Connection_Pools.Key_For (URI, TLS => TLS_A);
      Key_A_Again := Http_Client.Connection_Pools.Key_For (URI, TLS => TLS_A);
      Key_B := Http_Client.Connection_Pools.Key_For (URI, TLS => TLS_B);
      Key_A_Other :=
        Http_Client.Connection_Pools.Key_For (URI_Other, TLS => TLS_A);

      Assert
        (Http_Client.Connection_Pools.Same_Key (Key_A, Key_A_Again),
         "same client-certificate identity should produce compatible pool keys");

      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_None, Key_A),
         "no-certificate TLS connections must not be pooled with mutual-TLS connections");

      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_A, Key_B),
         "different client certificates must not share one pooled TLS connection even if ids collide");

      Assert
        (Http_Client.Connection_Pools.Same_Key (Key_None_Other, Key_A_Other),
         "a credential scoped to a different origin should not partition that origin's no-certificate pool key");

      Assert
        (Ada.Strings.Fixed.Index
           (Http_Client.Connection_Pools.Image (Key_A),
            "tls-client-cert=present")
         > 0,
         "pool-key diagnostics should disclose only client-certificate presence, not paths or key material");
   end Test_TLS_Client_Certificate_Pool_Key_Boundary;

   procedure Test_TLS_Open_Rejects_Invalid_Host_Syntax
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Conn           : Http_Client.Transports.TLS.Connection;
      Sixty_Four_As  : constant String (1 .. 64) := [others => 'a'];
      Oversized_Host : constant String := Sixty_Four_As & ".example.com";
   begin
      Assert
        (Http_Client.Transports.TLS.Open
           (Item => Conn, Host => "bad host.example", Port => 443)
         = Http_Client.Errors.Invalid_URI,
         "TLS Open should reject spaces in direct host input before calling C");

      Assert
        (not Http_Client.Transports.TLS.Is_Open (Conn),
         "invalid direct TLS host should leave the connection closed");

      Assert
        (Http_Client.Transports.TLS.Open
           (Item => Conn, Host => "-bad.example", Port => 443)
         = Http_Client.Errors.Invalid_URI,
         "TLS Open should reject DNS labels starting with hyphen");

      Assert
        (Http_Client.Transports.TLS.Open
           (Item => Conn, Host => Oversized_Host, Port => 443)
         = Http_Client.Errors.Invalid_URI,
         "TLS Open should reject DNS labels longer than 63 octets");

      Assert
        (Http_Client.Transports.TLS.Open
           (Item => Conn, Host => "999.1.2.3", Port => 443)
         = Http_Client.Errors.Invalid_URI,
         "TLS Open should reject malformed IPv4 literals before calling C");
   end Test_TLS_Open_Rejects_Invalid_Host_Syntax;

   procedure Test_Execution_TLS_Options_Are_Independent
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
   begin
      Options.Timeouts.Connect := 111;
      Options.Timeouts.Read := 222;
      Options.Timeouts.Write := 333;

      Assert
        (Options.TLS.Timeouts.Connect
         = Http_Client.Transports.TCP.Default_Timeouts.Connect,
         "changing top-level HTTP connect timeout must not mutate TLS timeout options");

      Assert
        (Options.TLS.Timeouts.Read
         = Http_Client.Transports.TCP.Default_Timeouts.Read,
         "changing top-level HTTP read timeout must not mutate TLS timeout options");

      Assert
        (Options.TLS.Timeouts.Write
         = Http_Client.Transports.TCP.Default_Timeouts.Write,
         "changing top-level HTTP write timeout must not mutate TLS timeout options");

      Options.TLS.Timeouts.Connect := 444;

      Assert
        (Options.Timeouts.Connect = 111,
         "changing TLS timeout options must not mutate top-level HTTP timeout options");

      Assert
        (not Options.TLS.Disable_Certificate_Verification,
         "execution defaults must keep TLS certificate verification enabled");
   end Test_Execution_TLS_Options_Are_Independent;

   procedure Test_Client_HTTPS_Failed_Connect_Uses_TLS
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Probe      : GNAT.Sockets.Socket_Type;
      Probe_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
      Bound      : GNAT.Sockets.Sock_Addr_Type;
      URI        : Http_Client.URI.URI_Reference;
      Request    : Http_Client.Requests.Request;
      Response   : Http_Client.Responses.Response;
   begin
      GNAT.Sockets.Create_Socket (Probe);

      Probe_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Probe_Addr.Port := 0;

      GNAT.Sockets.Bind_Socket (Probe, Probe_Addr);
      Bound := GNAT.Sockets.Get_Socket_Name (Probe);
      GNAT.Sockets.Close_Socket (Probe);

      Assert_Parse_Ok
        ("https://127.0.0.1:"
         & Decimal_Image (Natural (Http_Client.URI.TCP_Port (Bound.Port)))
         & "/secure",
         URI,
         "HTTPS URI for TLS execution failed-connect path");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS request should construct before TLS execution");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response)
         = Http_Client.Errors.Connection_Failed,
         "HTTPS execution to a closed loopback port should use TLS "
         & "transport and report connection failure, not Unsupported_Feature");
   end Test_Client_HTTPS_Failed_Connect_Uses_TLS;

   procedure Test_Cache_Client_Certificate_Store_Is_Conservative
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
   begin
      Config.Enabled := True;
      Build_Cache_Request ("https://mtls.example/private", Req);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: public, max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "a",
         Res);

      Assert
        (not Http_Client.Cache.May_Store_With_Client_Certificate
               (Using_Client_Certificate => True,
                Request                  => Req,
                Response                 => Res,
                Config                   => Config),
         "mutual-TLS responses should not store by default even without Authorization headers");

      Config.Allow_Authenticated_Store := True;
      Assert
        (Http_Client.Cache.May_Store_With_Client_Certificate
           (Using_Client_Certificate => True,
            Request                  => Req,
            Response                 => Res,
            Config                   => Config),
         "explicit caller opt-in plus explicit public response directives may permit mutual-TLS cache storage");
   end Test_Cache_Client_Certificate_Store_Is_Conservative;

   procedure Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds is
      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Fixed_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified direct HTTPS GET should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "HTTPS status should be 200");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Response), "X-TLS-Fixture")
         = "direct",
         "HTTPS fixture response header should be parsed");
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Response),
         "verified direct HTTPS GET body");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds;

   procedure Test_Direct_HTTPS_GET_Localhost_Sends_SNI is
      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Fixed_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port => Port, Host => "localhost");
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified direct HTTPS GET to localhost should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Fixtures.TLS_SNI_Seen,
         "direct TLS fixture should observe localhost SNI");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_GET_Localhost_Sends_SNI;

   procedure Test_Direct_HTTPS_GET_Without_Test_CA_Fails is
      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Fixed_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Http_Client.Clients.Default_Execution_Options);
      Assert
        (Status = Http_Client.Errors.Certificate_Verification_Failed
         or else Status = Http_Client.Errors.TLS_Handshake_Failed
         or else Status = Http_Client.Errors.TLS_Failed
         or else Status = Http_Client.Errors.CA_Store_Failed
         or else Status = Http_Client.Errors.Connection_Failed,
         "untrusted local test CA should fail deterministically; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Fixtures.Stop_TLS;
   end Test_Direct_HTTPS_GET_Without_Test_CA_Fails;

   procedure Test_Direct_HTTPS_GET_Wrong_Hostname_Fails is
      Port     : constant Natural :=
        Start_TLS_Fixture
          (Mode             => Fixture_Fixed_Response,
           Certificate_File_Name => Fixture_Wronghost_Cert_Name,
           Private_Key_File_Name => Fixture_Wronghost_Key_Name);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Hostname_Verification_Failed
         or else Status = Http_Client.Errors.Certificate_Verification_Failed
         or else Status = Http_Client.Errors.TLS_Handshake_Failed
         or else Status = Http_Client.Errors.CA_Store_Failed
         or else Status = Http_Client.Errors.Connection_Failed,
         "wrong-host certificate should fail deterministic hostname/certificate "
         & "verification; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Fixtures.Stop_TLS;
   end Test_Direct_HTTPS_GET_Wrong_Hostname_Fails;

   procedure Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit is
      Options  : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Fixed_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Options.TLS.Disable_Certificate_Verification := True;
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "explicit unsafe verification disable should be required for this path; "
         & "actual status=" & Http_Client.Errors.Result_Status'Image (Status));
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Response),
         "unsafe-disabled HTTPS GET body");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit;

   procedure Test_Direct_HTTPS_GET_Chunked_Body_Preserved is
      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Chunked_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified chunked HTTPS GET should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Response),
         "verified chunked HTTPS GET body");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_GET_Chunked_Body_Preserved;

   procedure Test_Direct_HTTPS_GET_Streaming_Read_Succeeds is
      Port         : constant Natural :=
        Start_TLS_Fixture (Fixture_Chunked_Response);
      Request      : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Stream       : Http_Client.Response_Streams.Streaming_Response;
      Status       : Http_Client.Errors.Result_Status;
      Buffer       : Ada.Streams.Stream_Element_Array (1 .. 16);
      Last         : Ada.Streams.Stream_Element_Offset;
      Output       : Ada.Streams.Stream_Element_Array (1 .. 7);
      Count        : Natural := 0;
      Close_Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Response_Streams.Open
          (Request => Request,
           Stream  => Stream,
           Options => Verified_Streaming_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified HTTPS streaming open should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Response_Streams.Status_Code (Stream) = 200,
         "streaming HTTPS status should be 200");

      loop
         Status :=
           Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "HTTPS streaming Read_Some should return Ok or EOF");
         for Index in Buffer'First .. Last loop
            Count := Count + 1;
            Assert
              (Count <= Output'Length,
               "streaming HTTPS returned too many body bytes");
            Output (Ada.Streams.Stream_Element_Offset (Count)) :=
              Buffer (Index);
         end loop;
      end loop;

      Assert
        (Count = Output'Length,
         "streaming HTTPS should return the expected body length");
      Assert_Binary_Body (Output, "streaming HTTPS body");
      Close_Status := Http_Client.Response_Streams.Close (Stream);
      Assert
        (Close_Status = Http_Client.Errors.Ok
         or else Close_Status = Http_Client.Errors.Not_Connected,
         "streaming HTTPS close should be deterministic");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_GET_Streaming_Read_Succeeds;

   procedure Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds is
      Port         : constant Natural :=
        Start_TLS_Fixture (Fixture_H2_Large_Response);
      Request      : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port);
      Options      : Http_Client.Response_Streams.Streaming_Options :=
        Verified_Streaming_Options;
      Stream       : Http_Client.Response_Streams.Streaming_Response;
      Status       : Http_Client.Errors.Result_Status;
      Buffer       : Ada.Streams.Stream_Element_Array (1 .. 8_192);
      Last         : Ada.Streams.Stream_Element_Offset;
      Count        : Natural := 0;
      Close_Status : Http_Client.Errors.Result_Status;
   begin
      Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_Force_HTTP_2;
      Options.Max_Body_Size := H2_Large_Response_Size;

      Status :=
        Http_Client.Response_Streams.Open
          (Request => Request,
           Stream  => Stream,
           Options => Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified HTTPS h2 streaming open should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Response_Streams.Status_Code (Stream) = 200,
         "h2 streaming HTTPS status should be 200");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Response_Streams.Headers (Stream), "x-tls-fixture") =
         "h2-large",
         "h2 streaming fixture header should be parsed");

      loop
         Status :=
           Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "h2 streaming Read_Some should return Ok or EOF; actual status="
            & Http_Client.Errors.Result_Status'Image (Status));

         for Index in Buffer'First .. Last loop
            declare
               Expected : constant Ada.Streams.Stream_Element :=
                 Ada.Streams.Stream_Element
                   ((Count mod H2_Response_Chunk_Size) mod 251);
            begin
               Assert
                 (Buffer (Index) = Expected,
                  "h2 streaming byte mismatch at offset" & Natural'Image (Count));
            end;
            Count := Count + 1;
         end loop;
      end loop;

      Assert
        (Count = H2_Large_Response_Size,
         "h2 streaming should read the complete large response");
      Close_Status := Http_Client.Response_Streams.Close (Stream);
      Assert
        (Close_Status = Http_Client.Errors.Ok
         or else Close_Status = Http_Client.Errors.Not_Connected,
         "h2 streaming close should be deterministic");
      Assert
        (Fixtures.TLS_Join_Result = 0, "h2 TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds;

   procedure Test_Direct_HTTPS_POST_Buffered_Binary_Body is
      Port     : constant Natural := Start_TLS_Fixture (Fixture_OK_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : constant Http_Client.Requests.Request :=
        Build_HTTPS_Request
          (Port    => Port,
           Method  => Http_Client.Types.POST,
           Payload => Binary_Test_String);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS buffered binary POST should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Captured_Request_Contains ("Content-Length: 7"),
         "buffered HTTPS POST should send content length");
      Assert
        (Captured_Request_Contains ("PK"),
         "buffered HTTPS POST should preserve binary request bytes around printable bytes");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_POST_Buffered_Binary_Body;

   procedure Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect is
      type Chunked_Producer is new Http_Client.Request_Bodies.Body_Producer
      with record
         Data   : String (1 .. 7) := Binary_Test_String;
         Cursor : Natural := 1;
      end record;

      overriding
      function Read_Some
        (Item   : in out Chunked_Producer;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status;

      overriding
      function Reset
        (Item : in out Chunked_Producer)
         return Http_Client.Errors.Result_Status;

      overriding
      function Read_Some
        (Item   : in out Chunked_Producer;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status
      is
         Take : Natural;
      begin
         if Item.Cursor > Item.Data'Last then
            Count := 0;
            return Http_Client.Errors.Ok;
         end if;
         Take :=
           Natural'Min
             (2,
              Natural'Min (Buffer'Length, Item.Data'Last - Item.Cursor + 1));
         Buffer (Buffer'First .. Buffer'First + Take - 1) :=
           Item.Data (Item.Cursor .. Item.Cursor + Take - 1);
         Item.Cursor := Item.Cursor + Take;
         Count := Take;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Chunked_Producer)
         return Http_Client.Errors.Result_Status is
      begin
         Item.Cursor := 1;
         return Http_Client.Errors.Ok;
      end Reset;

      Port     : constant Natural :=
        Start_TLS_Fixture (Fixture_Expect_Response);
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Request  : Http_Client.Requests.Request :=
        Build_HTTPS_Request (Port => Port, Method => Http_Client.Types.POST);
      Headers  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Producer : aliased Chunked_Producer;
      Parsed   : constant Http_Client.URI.URI_Reference :=
        Http_Client.Requests.URI (Request);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Headers.Add (Headers, "Expect", "100-continue")
         = Http_Client.Errors.Ok,
         "Expect header should be valid");
      Assert
        (Http_Client.Headers.Add (Trailers, "X-Request-Trailer", "done")
         = Http_Client.Errors.Ok,
         "request trailer should be valid");
      Status :=
        Http_Client.Requests.Create
          (Method  => Http_Client.Types.POST,
           URI     => Parsed,
           Item    => Request,
           Headers => Headers);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS Expect request should rebuild with headers");
      Status :=
        Http_Client.Requests.Set_Body
          (Request,
           Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
             (Producer'Unchecked_Access, Trailers, Replayable => True));
      Assert
        (Status = Http_Client.Errors.Ok,
         "chunked HTTPS body with trailers should attach");

      Status :=
        Http_Client.Clients.Execute
          (Item     => Client,
           Request  => Request,
           Response => Response,
           Options  => Verified_TLS_Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS chunked upload with Expect should succeed; actual status="
         & Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Captured_Request_Contains ("Transfer-Encoding: chunked"),
         "HTTPS upload should be chunked");
      Assert
        (Captured_Request_Contains ("Trailer: X-Request-Trailer"),
         "HTTPS upload should declare trailer");
      Assert
        (Captured_Request_Contains ("X-Request-Trailer: done"),
         "HTTPS upload should send trailer");
      Assert
        (Captured_Request_Contains ("Expect: 100-continue"),
         "HTTPS upload should send Expect");
      Assert
        (Fixtures.TLS_Join_Result = 0, "TLS fixture should finish cleanly");
   end Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("TLS");
   end Name;
   procedure AUnit_Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds;

   procedure AUnit_Test_Direct_HTTPS_GET_Localhost_Sends_SNI
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_Localhost_Sends_SNI;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_Localhost_Sends_SNI;

   procedure AUnit_Test_Direct_HTTPS_GET_Without_Test_CA_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_Without_Test_CA_Fails;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_Without_Test_CA_Fails;

   procedure AUnit_Test_Direct_HTTPS_GET_Wrong_Hostname_Fails
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_Wrong_Hostname_Fails;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_Wrong_Hostname_Fails;

   procedure AUnit_Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit;

   procedure AUnit_Test_Direct_HTTPS_GET_Chunked_Body_Preserved
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_Chunked_Body_Preserved;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_Chunked_Body_Preserved;

   procedure AUnit_Test_Direct_HTTPS_GET_Streaming_Read_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_GET_Streaming_Read_Succeeds;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_GET_Streaming_Read_Succeeds;

   procedure AUnit_Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds;

   procedure AUnit_Test_Direct_HTTPS_POST_Buffered_Binary_Body
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_POST_Buffered_Binary_Body;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_POST_Buffered_Binary_Body;

   procedure AUnit_Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect;
      Fixtures.Stop_TLS;
   exception
      when others =>
         Fixtures.Stop_TLS;
         raise;
   end AUnit_Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds'Access,
         "Test_Direct_HTTPS_GET_With_Configured_CA_Succeeds");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_Localhost_Sends_SNI'Access,
         "Test_Direct_HTTPS_GET_Localhost_Sends_SNI");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_Without_Test_CA_Fails'Access,
         "Test_Direct_HTTPS_GET_Without_Test_CA_Fails");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_Wrong_Hostname_Fails'Access,
         "Test_Direct_HTTPS_GET_Wrong_Hostname_Fails");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit'Access,
         "Test_Direct_HTTPS_Unsafe_Disable_Is_Explicit");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_Chunked_Body_Preserved'Access,
         "Test_Direct_HTTPS_GET_Chunked_Body_Preserved");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_GET_Streaming_Read_Succeeds'Access,
         "Test_Direct_HTTPS_GET_Streaming_Read_Succeeds");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds'Access,
         "Test_Direct_HTTPS_H2_Large_Streaming_Read_Succeeds");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_POST_Buffered_Binary_Body'Access,
         "Test_Direct_HTTPS_POST_Buffered_Binary_Body");
      Register_Routine
        (T,
         AUnit_Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect'Access,
         "Test_Direct_HTTPS_POST_Chunked_Upload_Trailers_And_Expect");
      Register_Routine
        (T,
         Test_TLS_Metadata_After_Handshake'Access,
         "Test_TLS_Metadata_After_Handshake");
      Register_Routine
        (T,
         Test_TLS_Defaults_And_Not_Connected'Access,
         "Test_TLS_Defaults_And_Not_Connected");
      Register_Routine
        (T, Test_TLS_Rejects_HTTP_URI'Access, "Test_TLS_Rejects_HTTP_URI");
      Register_Routine
        (T,
         Test_TLS_Rejects_NUL_C_Strings'Access,
         "Test_TLS_Rejects_NUL_C_Strings");
      Register_Routine
        (T, Test_TLS_Option_Validation'Access, "Test_TLS_Option_Validation");
      Register_Routine
        (T,
         Test_TLS_Client_Certificate_Config_And_Scope'Access,
         "Test_TLS_Client_Certificate_Config_And_Scope");
      Register_Routine
        (T,
         Test_TLS_Client_Certificate_Pool_Key_Boundary'Access,
         "Test_TLS_Client_Certificate_Pool_Key_Boundary");
      Register_Routine
        (T,
         Test_TLS_Open_Rejects_Invalid_Host_Syntax'Access,
         "Test_TLS_Open_Rejects_Invalid_Host_Syntax");
      Register_Routine
        (T,
         Test_Execution_TLS_Options_Are_Independent'Access,
         "Test_Execution_TLS_Options_Are_Independent");
      Register_Routine
        (T,
         Test_Client_HTTPS_Failed_Connect_Uses_TLS'Access,
         "Test_Client_HTTPS_Failed_Connect_Uses_TLS");
      Register_Routine
        (T,
         Test_Cache_Client_Certificate_Store_Is_Conservative'Access,
         "Test_Cache_Client_Certificate_Store_Is_Conservative");
   end Register_Tests;

end Http_Client.TLS.Tests;
