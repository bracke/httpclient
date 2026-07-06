with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Ada_Test_Fixtures;
with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Response_Streams;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.SOCKS5_TLS_Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Status_Code;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;

   package Fixtures renames Http_Client.Ada_Test_Fixtures;

   Fixture_Fixed_Response   : constant Fixtures.Fixture_Mode := Fixtures.TLS_Fixed_Response;
   Fixture_Chunked_Response : constant Fixtures.Fixture_Mode := Fixtures.TLS_Chunked_Response;
   Fixture_Expect_Response  : constant Fixtures.Fixture_Mode := Fixtures.TLS_Expect_Response;
   Fixture_OK_Response      : constant Fixtures.Fixture_Mode := Fixtures.TLS_OK_Response;

   SOCKS_No_Auth_Success             : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_No_Auth_Success;
   SOCKS_Username_Password_Success   : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Userpass_Success;
   SOCKS_No_Acceptable_Methods       : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_No_Acceptable_Methods;
   SOCKS_Username_Password_Failure   : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Userpass_Failure;
   SOCKS_Malformed_Auth_Response     : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Malformed_Auth_Response;
   SOCKS_Connect_General_Failure     : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Connect_General_Failure;
   SOCKS_Connect_Host_Unreachable    : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Connect_Host_Unreachable;
   SOCKS_Connect_Connection_Refused  : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Connect_Connection_Refused;
   SOCKS_Malformed_Connect_Reply     : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Malformed_Connect_Reply;
   SOCKS_Close_Before_Reply          : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Close_Before_Reply;
   SOCKS_Close_During_TLS            : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Close_During_TLS;
   SOCKS_Unsupported_Version_Reply   : constant Fixtures.Fixture_Mode := Fixtures.SOCKS_Unsupported_Version_Reply;

   function Fixture_Path (Leaf : String) return String;
   function Fixture_CA_File return String;
   function Fixture_Server_Cert return String;
   function Fixture_Server_Key return String;
   function Fixture_Wronghost_Cert return String;
   function Fixture_Wronghost_Key return String;

   function Fixture_Path (Leaf : String) return String is
      Candidate_1 : constant String := "tests/fixtures/tls/" & Leaf;
      Candidate_2 : constant String := "fixtures/tls/" & Leaf;
      Candidate_3 : constant String := "../fixtures/tls/" & Leaf;
      Candidate_4 : constant String := "../../tests/fixtures/tls/" & Leaf;
      Candidate_5 : constant String := "../../../tests/fixtures/tls/" & Leaf;
   begin
      if Ada.Directories.Exists (Candidate_1) then
         return Candidate_1;
      elsif Ada.Directories.Exists (Candidate_2) then
         return Candidate_2;
      elsif Ada.Directories.Exists (Candidate_3) then
         return Candidate_3;
      elsif Ada.Directories.Exists (Candidate_4) then
         return Candidate_4;
      elsif Ada.Directories.Exists (Candidate_5) then
         return Candidate_5;
      else
         return Candidate_1;
      end if;
   end Fixture_Path;

   function Fixture_CA_File return String is
   begin
      return Fixture_Path ("ca.crt");
   end Fixture_CA_File;

   function Fixture_Server_Cert return String is
   begin
      return Fixture_Path ("server.crt");
   end Fixture_Server_Cert;

   function Fixture_Server_Key return String is
   begin
      return Fixture_Path ("server.key");
   end Fixture_Server_Key;

   function Fixture_Wronghost_Cert return String is
   begin
      return Fixture_Path ("wronghost-server.crt");
   end Fixture_Wronghost_Cert;

   function Fixture_Wronghost_Key return String is
   begin
      return Fixture_Path ("wronghost-server.key");
   end Fixture_Wronghost_Key;

   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Http_Client.SOCKS5_TLS_Tests");
   end Name;

   procedure Cleanup_Fixtures is
   begin
      --  Stop the TLS origin first.  In the proxy+TLS suites, the TLS
      --  server may be blocked inside OpenSSL while the proxy tunnel is
      --  still open; closing the origin side first lets the proxy pump see
      --  EOF and terminate instead of waiting for proxy teardown to unwind
      --  a still-live TLS peer.
      Fixtures.Stop_TLS;
      Fixtures.Stop_SOCKS5_Proxy;
   exception
      when others =>
         null;
   end Cleanup_Fixtures;

   overriding procedure Set_Up
     (T : in out Section_Test_Case)
   is
      pragma Unreferenced (T);
   begin
      Cleanup_Fixtures;
   end Set_Up;

   overriding procedure Tear_Down
     (T : in out Section_Test_Case)
   is
      pragma Unreferenced (T);
   begin
      Cleanup_Fixtures;
   end Tear_Down;

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   procedure Assert_Status
     (Actual   : Http_Client.Errors.Result_Status;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
   begin
      Assert
        (Actual = Expected,
         Message & " actual=" & Http_Client.Errors.Result_Status'Image (Actual)
         & " expected=" & Http_Client.Errors.Result_Status'Image (Expected));
   end Assert_Status;

   function Binary_Test_Bytes return Ada.Streams.Stream_Element_Array is
   begin
      return
        (1 => 16#00#,
         2 => 16#0D#,
         3 => 16#0A#,
         4 => 16#80#,
         5 => 16#FF#,
         6 => Character'Pos ('P'),
         7 => Character'Pos ('K'));
   end Binary_Test_Bytes;

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

   type Binary_Producer is new Http_Client.Request_Bodies.Body_Producer with record
      Cursor : Natural := 1;
   end record;

   overriding
   function Read_Some
     (Item   : in out Binary_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;

   overriding
   function Reset
     (Item : in out Binary_Producer) return Http_Client.Errors.Result_Status;

   overriding
   function Read_Some
     (Item   : in out Binary_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status
   is
      Data : constant String := Binary_Test_String;
      Take : Natural;
   begin
      if Item.Cursor > Data'Last then
         Count := 0;
         return Http_Client.Errors.Ok;
      end if;

      Take := Natural'Min (2, Natural'Min (Buffer'Length, Data'Last - Item.Cursor + 1));
      Buffer (Buffer'First .. Buffer'First + Take - 1) :=
        Data (Item.Cursor .. Item.Cursor + Take - 1);
      Item.Cursor := Item.Cursor + Take;
      Count := Take;
      return Http_Client.Errors.Ok;
   end Read_Some;

   overriding
   function Reset
     (Item : in out Binary_Producer) return Http_Client.Errors.Result_Status is
   begin
      Item.Cursor := 1;
      return Http_Client.Errors.Ok;
   end Reset;

   procedure Assert_Binary_Body
     (Actual  : Ada.Streams.Stream_Element_Array;
      Message : String)
   is
      Expected : constant Ada.Streams.Stream_Element_Array := Binary_Test_Bytes;
   begin
      Assert (Actual'Length = Expected'Length, Message & " length mismatch");
      for Offset in 0 .. Expected'Length - 1 loop
         Assert
           (Actual (Actual'First + Ada.Streams.Stream_Element_Offset (Offset)) =
            Expected (Expected'First + Ada.Streams.Stream_Element_Offset (Offset)),
            Message & " byte mismatch at offset" & Natural'Image (Offset));
      end loop;
   end Assert_Binary_Body;

   function Start_TLS_Fixture
     (Mode             : Fixtures.Fixture_Mode;
      Certificate_File : String;
      Private_Key_File : String) return Natural
   is
      Port : Natural;
   begin
      Fixtures.Stop_TLS;
      Port := Fixtures.Start_TLS (Certificate_File, Private_Key_File, Mode);
      Assert (Port > 0, "TLS origin fixture should start on loopback ephemeral port");
      return Port;
   end Start_TLS_Fixture;

   function Start_TLS_Fixture
     (Mode : Fixtures.Fixture_Mode) return Natural
   is
   begin
      return Start_TLS_Fixture
        (Mode, Fixture_Server_Cert, Fixture_Server_Key);
   end Start_TLS_Fixture;

   function Unused_Origin_Port return Natural is
      Probe      : GNAT.Sockets.Socket_Type;
      Probe_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
      Bound      : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Create_Socket (Probe);
      Probe_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Probe_Addr.Port := 0;
      GNAT.Sockets.Bind_Socket (Probe, Probe_Addr);
      Bound := GNAT.Sockets.Get_Socket_Name (Probe);
      GNAT.Sockets.Close_Socket (Probe);
      return Natural (Http_Client.URI.TCP_Port (Bound.Port));
   exception
      when others =>
         return 9;
   end Unused_Origin_Port;

   function Start_SOCKS5_Fixture
     (Origin_Port   : Natural;
      Mode          : Fixtures.Fixture_Mode := SOCKS_No_Auth_Success;
      Expected_User : String := "";
      Expected_Pass : String := "") return Natural
   is
      Port : constant Natural :=
        Fixtures.Start_SOCKS5_Proxy
          (Origin_Host   => "127.0.0.1",
           Origin_Port   => Origin_Port,
           Mode          => Mode,
           Expected_User => Expected_User,
           Expected_Pass => Expected_Pass);
   begin
      Assert (Port > 0, "SOCKS5 proxy fixture should start on loopback ephemeral port");
      return Port;
   end Start_SOCKS5_Fixture;

   function Fixture_URL
     (Port : Natural;
      Path : String := "/repo.git/info/refs?service=git-upload-pack";
      Host : String := "127.0.0.1") return String is
   begin
      return "https://" & Host & ":" & Decimal_Image (Port) & Path;
   end Fixture_URL;

   function Build_Request
     (Origin_Port : Natural;
      Method      : Http_Client.Types.Method_Name := Http_Client.Types.GET;
      Headers     : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Payload     : String := "";
      Host        : String := "127.0.0.1") return Http_Client.Requests.Request
   is
      Parsed  : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse (Fixture_URL (Origin_Port, Host => Host), Parsed);
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "SOCKS5 TLS origin URI should parse");
      Status := Http_Client.Requests.Create
        (Method  => Method,
         URI     => Parsed,
         Item    => Request,
         Headers => Headers,
         Payload => Payload);
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "SOCKS5 TLS request should build");
      return Request;
   end Build_Request;

   function SOCKS_Options
     (SOCKS_Port : Natural;
      Username   : String := "";
      Password   : String := "";
      Use_CA     : Boolean := True) return Http_Client.Clients.Execution_Options
   is
      Options : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
      Base    : Http_Client.Proxies.Proxy_Config;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Use_CA then
         Options.TLS.CA_File :=
           Ada.Strings.Unbounded.To_Unbounded_String (Fixture_CA_File);
      end if;
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
      Base := Http_Client.Proxies.SOCKS5 ("127.0.0.1", Http_Client.URI.TCP_Port (SOCKS_Port));
      if Username'Length > 0 or else Password'Length > 0 then
         Status := Http_Client.Proxies.With_SOCKS5_Username_Password
           (Base, Username, Password, Options.Proxy);
         Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "SOCKS5 username/password credentials should configure");
      else
         Options.Proxy := Base;
      end if;
      return Options;
   end SOCKS_Options;

   function SOCKS_Stream_Options
     (SOCKS_Port : Natural;
      Username   : String := "";
      Password   : String := "") return Http_Client.Response_Streams.Streaming_Options
   is
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Base    : Http_Client.Proxies.Proxy_Config;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Options.TLS.CA_File :=
        Ada.Strings.Unbounded.To_Unbounded_String (Fixture_CA_File);
      Options.Protocol_Policy :=
        Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;
      Base := Http_Client.Proxies.SOCKS5 ("127.0.0.1", Http_Client.URI.TCP_Port (SOCKS_Port));
      if Username'Length > 0 or else Password'Length > 0 then
         Status := Http_Client.Proxies.With_SOCKS5_Username_Password
           (Base, Username, Password, Options.Proxy);
         Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "SOCKS5 streaming credentials should configure");
      else
         Options.Proxy := Base;
      end if;
      return Options;
   end SOCKS_Stream_Options;

   function Capture_Contains (Needle : String) return Boolean is
   begin
      return Fixtures.SOCKS5_Capture_Contains (Needle);
   end Capture_Contains;

   function Origin_Contains (Needle : String) return Boolean is
   begin
      return Fixtures.TLS_Request_Contains (Needle);
   end Origin_Contains;

   function CONNECT_Target_Is
     (Host : String;
      Port : Natural) return Boolean
   is
   begin
      return Fixtures.SOCKS5_Origin_Equals (Host, Port);
   end CONNECT_Target_Is;

   procedure Execute_Through_SOCKS5
     (Request : Http_Client.Requests.Request;
      Options : Http_Client.Clients.Execution_Options;
      Result  : out Http_Client.Clients.Client_Result;
      Status  : out Http_Client.Errors.Result_Status)
   is
      Client : Http_Client.Clients.Client;
      Config : Http_Client.Clients.Client_Configuration := Http_Client.Clients.Default_Client_Configuration;
   begin
      Config.Execution := Options;
      Client := Http_Client.Clients.Create;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "SOCKS5 TLS client should initialize");
      Status := Http_Client.Clients.Execute (Client, Request, Result);
   end Execute_Through_SOCKS5;

   procedure Test_SOCKS5_TLS_GET_No_Auth_With_Configured_CA_Succeeds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "HTTPS over SOCKS5 no-auth should execute successfully");
      Assert (Result.Status = Http_Client.Errors.Ok, "client result status should be Ok");
      Assert (Http_Client.Responses.Status_Code (Result.Response) = 200, "origin response status should be 200");
      Assert (Fixtures.SOCKS5_Saw_CONNECT, "SOCKS5 proxy should receive CONNECT before TLS");
      Assert (CONNECT_Target_Is ("127.0.0.1", Origin_Port), "SOCKS5 CONNECT should target origin authority");
      Assert (Fixtures.SOCKS5_Tunnel_Client_To_Origin_Bytes > 0, "SOCKS5 proxy should tunnel encrypted client bytes");
      Assert (Fixtures.SOCKS5_Tunnel_Origin_To_Client_Bytes > 0, "SOCKS5 proxy should tunnel encrypted origin bytes");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_GET_No_Auth_With_Configured_CA_Succeeds;

   procedure Test_SOCKS5_TLS_GET_Username_Password_With_Configured_CA_Succeeds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture
        (Origin_Port, SOCKS_Username_Password_Success, "socks-user", "socks-pass");
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5
        (Build_Request (Origin_Port),
         SOCKS_Options (SOCKS_Port, "socks-user", "socks-pass"), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "HTTPS over SOCKS5 username/password should execute");
      Assert (Fixtures.SOCKS5_Auth_Seen, "SOCKS5 username/password auth should be observed by proxy");
      Assert (not Origin_Contains ("socks-user"), "SOCKS username must not be visible to origin");
      Assert (not Origin_Contains ("socks-pass"), "SOCKS password must not be visible to origin");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_GET_Username_Password_With_Configured_CA_Succeeds;

   procedure Test_SOCKS5_TLS_Streaming_GET_No_Auth_Succeeds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : constant Http_Client.Requests.Request := Build_Request (Origin_Port);
      Stream      : Http_Client.Response_Streams.Streaming_Response;
      Status      : Http_Client.Errors.Result_Status;
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. 2);
      Last        : Ada.Streams.Stream_Element_Offset;
      Total       : Natural := 0;
   begin
      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Options => SOCKS_Stream_Options (SOCKS_Port),
         Stream  => Stream);
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "streaming HTTPS over SOCKS5 should open");
      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "streaming HTTPS over SOCKS5 read should succeed");
         exit when Last < Buffer'First;
         Total := Total + Natural (Last - Buffer'First + 1);
      end loop;
      Status := Http_Client.Response_Streams.Close (Stream);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "streaming HTTPS over SOCKS5 close should succeed");
      Assert (Total = 7, "streaming HTTPS over SOCKS5 should preserve fixed binary body length");
   exception
      when others =>
         declare
            Ignore : Http_Client.Errors.Result_Status;
         begin
            Ignore := Http_Client.Response_Streams.Close (Stream);
            pragma Unreferenced (Ignore);
         end;
         Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Streaming_GET_No_Auth_Succeeds;

   procedure Test_SOCKS5_TLS_Binary_Body_Preserved

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "binary HTTPS over SOCKS5 should execute");
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Result.Response),
         "binary HTTPS over SOCKS5 response");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Binary_Body_Preserved;

   procedure Test_SOCKS5_TLS_Chunked_Response_Preserved

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Chunked_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "chunked HTTPS over SOCKS5 should execute");
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Result.Response),
         "chunked HTTPS over SOCKS5 response");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Chunked_Response_Preserved;

   procedure Test_SOCKS5_TLS_Proxy_Sees_Only_SOCKS_Handshake_Before_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Headers     : Http_Client.Headers.Header_List;
      Request     : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Assert (Http_Client.Headers.Add (Headers, "Authorization", "Basic origin-secret") = Http_Client.Errors.Ok,
              "origin Authorization header should be accepted");
      Assert (Http_Client.Headers.Add (Headers, "Cookie", "sid=origin-cookie") = Http_Client.Errors.Ok,
              "origin Cookie header should be accepted");
      Assert (Http_Client.Headers.Add (Headers, "Git-Protocol", "version=2") = Http_Client.Errors.Ok,
              "Git-Protocol header should be accepted");
      Assert
        (Http_Client.Headers.Add
           (Headers, "Content-Type", "application/x-git-upload-pack-request") = Http_Client.Errors.Ok,
         "Git content type header should be accepted");
      Request := Build_Request (Origin_Port, Http_Client.Types.POST, Headers, "0032want secret-body-pkt-line");
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "POST through SOCKS5 should execute");
      Assert (not Capture_Contains ("Authorization: Basic origin-secret"),
              "origin Authorization must not be visible to SOCKS5 before tunnel");
      Assert (not Capture_Contains ("Cookie: sid=origin-cookie"),
              "origin Cookie must not be visible to SOCKS5 before tunnel");
      Assert (not Capture_Contains ("Git-Protocol: version=2"),
              "Git-Protocol must not be visible to SOCKS5 before tunnel");
      Assert (not Capture_Contains ("application/x-git-upload-pack-request"),
              "Git Content-Type must not be visible to SOCKS5 before tunnel");
      Assert (not Capture_Contains ("secret-body-pkt-line"),
              "origin body bytes must not be visible to SOCKS5 before tunnel");
      Assert (not Capture_Contains ("/repo.git/info/refs"),
              "origin request path/query must not be visible to SOCKS5 before tunnel");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Proxy_Sees_Only_SOCKS_Handshake_Before_Tunnel;

   procedure Test_SOCKS5_TLS_POST_Buffered_Binary_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : constant Http_Client.Requests.Request :=
        Build_Request (Origin_Port, Http_Client.Types.POST, Payload => "abc" & Character'Val (0) & "xyz");
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "buffered binary POST through SOCKS5 should execute");
      Assert (Origin_Contains ("abc"), "origin should see buffered upload inside TLS tunnel");
      Assert (not Capture_Contains ("abc"), "SOCKS5 pre-tunnel bytes must not contain buffered body");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_POST_Buffered_Binary_Body;

   procedure Test_SOCKS5_TLS_POST_Fixed_Length_Stream

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : Http_Client.Requests.Request :=
        Build_Request (Origin_Port, Http_Client.Types.POST);
      Producer    : aliased Binary_Producer;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Requests.Set_Body
          (Request,
           Http_Client.Request_Bodies.From_Fixed_Length_Stream
             (Producer'Unchecked_Access,
              Length     => 7,
              Replayable => True));
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "fixed-length SOCKS5 upload body should attach");
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "fixed-length streaming upload through SOCKS5 should execute");
      Assert (Origin_Contains ("Content-Length: 7"), "fixed-length upload should use Content-Length inside TLS");
      Assert (not Origin_Contains ("Transfer-Encoding: chunked"), "fixed-length upload must not use chunked framing");
      Assert (Origin_Contains ("PK"), "origin should see fixed-length upload bytes inside TLS");
      Assert (not Capture_Contains ("PK"), "SOCKS5 pre-tunnel bytes must not contain fixed-length body");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_POST_Fixed_Length_Stream;

   procedure Test_SOCKS5_TLS_POST_Chunked_Upload

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : Http_Client.Requests.Request :=
        Build_Request (Origin_Port, Http_Client.Types.POST);
      Producer    : aliased Binary_Producer;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Requests.Set_Body
          (Request,
           Http_Client.Request_Bodies.From_Unknown_Length_Stream
             (Producer'Unchecked_Access, Replayable => True));
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "chunked SOCKS5 upload body should attach");
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "chunked streaming upload through SOCKS5 should execute");
      Assert (Origin_Contains ("Transfer-Encoding: chunked"),
         "unknown-length upload should use chunked framing inside TLS");
      Assert (not Origin_Contains ("Content-Length:"),
         "chunked upload must not send Content-Length");
      Assert (Origin_Contains ("P"),
         "origin should see first chunked upload byte inside TLS");
      Assert (Origin_Contains ("K"),
         "origin should see second chunked upload byte inside TLS");
      Assert (not Capture_Contains ("PK"),
         "SOCKS5 pre-tunnel bytes must not contain chunked body");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_POST_Chunked_Upload;

   procedure Test_SOCKS5_TLS_Request_Trailers_After_Chunked_Upload

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : Http_Client.Requests.Request :=
        Build_Request (Origin_Port, Http_Client.Types.POST);
      Trailers    : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Producer    : aliased Binary_Producer;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Headers.Add (Trailers, "X-Request-Trailer", "done") = Http_Client.Errors.Ok,
         "SOCKS5 request trailer should be valid");
      Status :=
        Http_Client.Requests.Set_Body
          (Request,
           Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
             (Producer'Unchecked_Access, Trailers, Replayable => True));
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "chunked SOCKS5 trailer body should attach");
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "request trailers through SOCKS5 should execute");
      Assert (Origin_Contains ("Trailer: X-Request-Trailer"),
         "chunked upload should declare trailer inside TLS");
      Assert (Origin_Contains ("X-Request-Trailer: done"),
         "chunked upload should send trailer after zero chunk");
      Assert (not Capture_Contains ("X-Request-Trailer"),
         "request trailers must not be visible to SOCKS5 before tunnel");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Request_Trailers_After_Chunked_Upload;

   procedure Test_SOCKS5_TLS_Expect_Continue_With_Trailers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Expect_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Headers     : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Trailers    : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request     : Http_Client.Requests.Request;
      Producer    : aliased Binary_Producer;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Headers.Add (Headers, "Expect", "100-continue") = Http_Client.Errors.Ok,
         "Expect header should be valid");
      Assert
        (Http_Client.Headers.Add (Trailers, "X-Request-Trailer", "done") = Http_Client.Errors.Ok,
         "Expect/trailer request trailer should be valid");
      Request := Build_Request (Origin_Port, Http_Client.Types.POST, Headers);
      Status :=
        Http_Client.Requests.Set_Body
          (Request,
           Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
             (Producer'Unchecked_Access, Trailers, Replayable => True));
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "Expect chunked SOCKS5 trailer body should attach");
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "Expect: 100-continue through SOCKS5 should execute");
      Assert (Origin_Contains ("Expect: 100-continue"),
         "Expect header should be sent inside TLS tunnel");
      Assert (Origin_Contains ("Transfer-Encoding: chunked"),
         "Expect upload should remain chunked");
      Assert (Origin_Contains ("X-Request-Trailer: done"),
         "Expect upload should send trailer after body");
      Assert (not Capture_Contains ("Expect: 100-continue"),
         "SOCKS5 pre-tunnel bytes must not contain origin Expect header");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Expect_Continue_With_Trailers;

   procedure Test_SOCKS5_TLS_Localhost_SNI_Uses_Origin_Host

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Request     : constant Http_Client.Requests.Request := Build_Request (Origin_Port, Host => "localhost");
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Request, SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.Ok,
         "localhost HTTPS over SOCKS5 should execute");
      Assert (Fixtures.TLS_SNI_Seen, "TLS SNI should use the origin host, not the SOCKS5 proxy host");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Localhost_SNI_Uses_Origin_Host;

   procedure Test_SOCKS5_TLS_Certificate_Failure_After_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Options     : Http_Client.Clients.Execution_Options := SOCKS_Options (SOCKS_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Options.TLS.CA_File := Ada.Strings.Unbounded.Null_Unbounded_String;
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), Options, Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Certificate_Verification_Failed
              or else Status = Http_Client.Errors.TLS_Handshake_Failed,
              "untrusted origin certificate after SOCKS5 CONNECT should fail deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Certificate_Failure_After_Tunnel;

   procedure Test_SOCKS5_TLS_Hostname_Failure_After_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response, Fixture_Wronghost_Cert, Fixture_Wronghost_Key);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Hostname_Verification_Failed
              or else Status = Http_Client.Errors.Certificate_Verification_Failed
              or else Status = Http_Client.Errors.TLS_Handshake_Failed,
              "origin hostname verification should use origin host after SOCKS5 CONNECT");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_TLS_Hostname_Failure_After_Tunnel;

   procedure Test_SOCKS5_No_Acceptable_Methods_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_No_Acceptable_Methods);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Unsupported_Authentication_Method,
         "no acceptable SOCKS5 method should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_No_Acceptable_Methods_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Username_Password_Auth_Failure_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture
        (Origin_Port, SOCKS_Username_Password_Failure, "socks-user", "socks-pass");
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5
        (Build_Request (Origin_Port),
         SOCKS_Options
           (SOCKS_Port, "socks-user", "wrong-pass", Use_CA => False),
         Result,
         Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Authentication_Failed,
         "SOCKS5 username/password auth failure should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Username_Password_Auth_Failure_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Malformed_Auth_Response_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Start_TLS_Fixture (Fixture_OK_Response);
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture
        (Origin_Port, SOCKS_Malformed_Auth_Response, "socks-user", "socks-pass");
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5
        (Build_Request (Origin_Port),
         SOCKS_Options
           (SOCKS_Port, "socks-user", "socks-pass", Use_CA => False),
         Result,
         Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Unsupported_Version,
         "malformed SOCKS5 auth response should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Malformed_Auth_Response_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Connect_General_Failure_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Connect_General_Failure);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_General_Server_Failure,
         "SOCKS5 general failure reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Connect_General_Failure_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Connect_Host_Unreachable_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Connect_Host_Unreachable);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Reply_Host_Unreachable,
         "SOCKS5 host unreachable reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Connect_Host_Unreachable_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Connect_Connection_Refused_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Connect_Connection_Refused);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Reply_Connection_Refused,
         "SOCKS5 connection refused reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Connect_Connection_Refused_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Malformed_Connect_Reply_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Malformed_Connect_Reply);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert_Status
        (Status,
         Http_Client.Errors.SOCKS_Malformed_Reply,
         "malformed SOCKS5 CONNECT reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Malformed_Connect_Reply_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Close_Before_Reply_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Close_Before_Reply);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.SOCKS_Malformed_Reply
              or else Status = Http_Client.Errors.SOCKS_Connect_Failed,
              "SOCKS5 close before CONNECT reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Close_Before_Reply_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Tunnel_Close_During_TLS_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Close_During_TLS);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert (Status /= Http_Client.Errors.Ok,
              "tunnel close during origin TLS handshake should return deterministic failure");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Tunnel_Close_During_TLS_Returns_Deterministic_Status;

   procedure Test_SOCKS5_Unsupported_Version_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : Natural := Unused_Origin_Port;
      SOCKS_Port  : Natural := Start_SOCKS5_Fixture (Origin_Port, SOCKS_Unsupported_Version_Reply);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_SOCKS5 (Build_Request (Origin_Port), SOCKS_Options (SOCKS_Port, Use_CA => False), Result, Status);
      Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS;
      Assert
        (Status = Http_Client.Errors.SOCKS_Unsupported_Version
         or else Status = Http_Client.Errors.SOCKS_Malformed_Reply,
         "unsupported SOCKS5 version reply should map deterministically");
   exception
      when others => Fixtures.Stop_SOCKS5_Proxy; Fixtures.Stop_TLS; raise;
   end Test_SOCKS5_Unsupported_Version_Returns_Deterministic_Status;

   overriding procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_SOCKS5_TLS_GET_No_Auth_With_Configured_CA_Succeeds'Access,
                        "Test_SOCKS5_TLS_GET_No_Auth_With_Configured_CA_Succeeds");
      Register_Routine (T, Test_SOCKS5_TLS_GET_Username_Password_With_Configured_CA_Succeeds'Access,
                        "Test_SOCKS5_TLS_GET_Username_Password_With_Configured_CA_Succeeds");
      Register_Routine (T, Test_SOCKS5_TLS_Streaming_GET_No_Auth_Succeeds'Access,
                        "Test_SOCKS5_TLS_Streaming_GET_No_Auth_Succeeds");
      Register_Routine (T, Test_SOCKS5_TLS_Binary_Body_Preserved'Access,
                        "Test_SOCKS5_TLS_Binary_Body_Preserved");
      Register_Routine (T, Test_SOCKS5_TLS_Chunked_Response_Preserved'Access,
                        "Test_SOCKS5_TLS_Chunked_Response_Preserved");
      Register_Routine (T, Test_SOCKS5_TLS_Proxy_Sees_Only_SOCKS_Handshake_Before_Tunnel'Access,
                        "Test_SOCKS5_TLS_Proxy_Sees_Only_SOCKS_Handshake_Before_Tunnel");
      Register_Routine (T, Test_SOCKS5_TLS_POST_Buffered_Binary_Body'Access,
                        "Test_SOCKS5_TLS_POST_Buffered_Binary_Body");
      Register_Routine (T, Test_SOCKS5_TLS_POST_Fixed_Length_Stream'Access,
                        "Test_SOCKS5_TLS_POST_Fixed_Length_Stream");
      Register_Routine (T, Test_SOCKS5_TLS_POST_Chunked_Upload'Access,
                        "Test_SOCKS5_TLS_POST_Chunked_Upload");
      Register_Routine (T, Test_SOCKS5_TLS_Request_Trailers_After_Chunked_Upload'Access,
                        "Test_SOCKS5_TLS_Request_Trailers_After_Chunked_Upload");
      Register_Routine (T, Test_SOCKS5_TLS_Expect_Continue_With_Trailers'Access,
                        "Test_SOCKS5_TLS_Expect_Continue_With_Trailers");
      Register_Routine (T, Test_SOCKS5_TLS_Localhost_SNI_Uses_Origin_Host'Access,
                        "Test_SOCKS5_TLS_Localhost_SNI_Uses_Origin_Host");
      Register_Routine (T, Test_SOCKS5_TLS_Certificate_Failure_After_Tunnel'Access,
                        "Test_SOCKS5_TLS_Certificate_Failure_After_Tunnel");
      Register_Routine (T, Test_SOCKS5_TLS_Hostname_Failure_After_Tunnel'Access,
                        "Test_SOCKS5_TLS_Hostname_Failure_After_Tunnel");
      Register_Routine (T, Test_SOCKS5_No_Acceptable_Methods_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_No_Acceptable_Methods_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Username_Password_Auth_Failure_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Username_Password_Auth_Failure_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Malformed_Auth_Response_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Malformed_Auth_Response_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Connect_General_Failure_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Connect_General_Failure_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Connect_Host_Unreachable_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Connect_Host_Unreachable_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Connect_Connection_Refused_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Connect_Connection_Refused_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Malformed_Connect_Reply_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Malformed_Connect_Reply_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Close_Before_Reply_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Close_Before_Reply_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Tunnel_Close_During_TLS_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Tunnel_Close_During_TLS_Returns_Deterministic_Status");
      Register_Routine (T, Test_SOCKS5_Unsupported_Version_Returns_Deterministic_Status'Access,
                        "Test_SOCKS5_Unsupported_Version_Returns_Deterministic_Status");
   end Register_Tests;
end Http_Client.SOCKS5_TLS_Tests;
