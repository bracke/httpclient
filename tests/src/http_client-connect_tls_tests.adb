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
with Http_Client.Response_Streams;
with Http_Client.Responses;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Connect_TLS_Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;

   package Fixtures renames Http_Client.Ada_Test_Fixtures;

   Fixture_Fixed_Response   : constant Fixtures.Fixture_Mode := Fixtures.TLS_Fixed_Response;
   Fixture_Chunked_Response : constant Fixtures.Fixture_Mode := Fixtures.TLS_Chunked_Response;
   Fixture_OK_Response      : constant Fixtures.Fixture_Mode := Fixtures.TLS_OK_Response;

   Proxy_CONNECT_Success       : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Success;
   Proxy_Return_407            : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Return_407;
   Proxy_Return_403            : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Return_403;
   Proxy_Return_502            : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Return_502;
   Proxy_Malformed_Response    : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Malformed;
   Proxy_Close_Before_Response : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Close_Before;
   Proxy_Close_During_TLS      : constant Fixtures.Fixture_Mode := Fixtures.CONNECT_Close_During;

   Fixture_CA_File_Name        : constant String := "ca.crt";
   Fixture_Server_Cert_Name    : constant String := "server.crt";
   Fixture_Server_Key_Name     : constant String := "server.key";
   Fixture_Wronghost_Cert_Name : constant String := "wronghost-server.crt";
   Fixture_Wronghost_Key_Name  : constant String := "wronghost-server.key";

   function Fixture_Path (Leaf : String) return String;
   function Fixture_CA_File return String;

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
      return Fixture_Path (Fixture_CA_File_Name);
   end Fixture_CA_File;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Http_Client.Connect_TLS_Tests");
   end Name;

   procedure Cleanup_Fixtures is
   begin
      --  Stop the TLS origin first.  In the proxy+TLS suites, the TLS
      --  server may be blocked inside OpenSSL while the proxy tunnel is
      --  still open; closing the origin side first lets the proxy pump see
      --  EOF and terminate instead of waiting for proxy teardown to unwind
      --  a still-live TLS peer.
      Fixtures.Stop_TLS;
      Fixtures.Stop_CONNECT_Proxy;
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

   procedure Apply_Test_Timeouts
     (Options : in out Http_Client.Clients.Execution_Options)
   is
      Bounded : constant Http_Client.Transports.TCP.Timeout_Config :=
        (Connect => 200,
         Read    => 200,
         Write   => 200);
   begin
      Options.Timeouts := Bounded;
      Options.TLS.Timeouts := Bounded;
   end Apply_Test_Timeouts;

   procedure Apply_Test_Timeouts
     (Options : in out Http_Client.Response_Streams.Streaming_Options)
   is
      Bounded : constant Http_Client.Transports.TCP.Timeout_Config :=
        (Connect => 200,
         Read    => 200,
         Write   => 200);
   begin
      Options.Timeouts := Bounded;
      Options.TLS.Timeouts := Bounded;
   end Apply_Test_Timeouts;

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
     (Mode                  : Fixtures.Fixture_Mode;
      Certificate_File_Name : String := Fixture_Server_Cert_Name;
      Private_Key_File_Name : String := Fixture_Server_Key_Name) return Natural
   is
      Port : Natural;
   begin
      Fixtures.Stop_TLS;
      Port :=
        Fixtures.Start_TLS
          (Fixture_Path (Certificate_File_Name),
           Fixture_Path (Private_Key_File_Name),
           Mode);
      Assert (Port > 0, "TLS origin fixture should start on loopback ephemeral port");
      return Port;
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

   function Start_Proxy_Fixture
     (Origin_Port         : Natural;
      Mode                : Fixtures.Fixture_Mode := Proxy_CONNECT_Success;
      Expected_Proxy_Auth : String := "") return Natural
   is
      Port : constant Natural :=
        Fixtures.Start_CONNECT_Proxy
          (Origin_Host         => "127.0.0.1",
           Origin_Port         => Origin_Port,
           Mode                => Mode,
           Expected_Proxy_Auth => Expected_Proxy_Auth);
   begin
      Assert (Port > 0, "HTTP CONNECT proxy fixture should start on loopback ephemeral port");
      return Port;
   end Start_Proxy_Fixture;

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
      Assert (Status = Http_Client.Errors.Ok, "CONNECT TLS origin URI should parse");
      Status := Http_Client.Requests.Create
        (Method  => Method,
         URI     => Parsed,
         Item    => Request,
         Headers => Headers,
         Payload => Payload);
      Assert (Status = Http_Client.Errors.Ok, "CONNECT TLS request should build");
      return Request;
   end Build_Request;

   function Proxy_Options (Proxy_Port : Natural) return Http_Client.Clients.Execution_Options is
      Options : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
   begin
      Options.TLS.CA_File := Ada.Strings.Unbounded.To_Unbounded_String (Fixture_CA_File);
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
      Options.Proxy := Http_Client.Proxies.HTTP ("127.0.0.1", Http_Client.URI.TCP_Port (Proxy_Port));
      Apply_Test_Timeouts (Options);
      return Options;
   end Proxy_Options;

   function Proxy_Stream_Options
     (Proxy_Port : Natural) return Http_Client.Response_Streams.Streaming_Options
   is
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
   begin
      Options.TLS.CA_File := Ada.Strings.Unbounded.To_Unbounded_String (Fixture_CA_File);
      Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;
      Options.Proxy := Http_Client.Proxies.HTTP ("127.0.0.1", Http_Client.URI.TCP_Port (Proxy_Port));
      Apply_Test_Timeouts (Options);
      return Options;
   end Proxy_Stream_Options;

   function Capture_Contains (Needle : String) return Boolean is
   begin
      return Fixtures.CONNECT_Capture_Contains (Needle);
   end Capture_Contains;

   function Origin_Contains (Needle : String) return Boolean is
   begin
      return Fixtures.TLS_Request_Contains (Needle);
   end Origin_Contains;

   procedure Execute_Through_Proxy
     (Origin_Port : Natural;
      Proxy_Port  : Natural;
      Request     : Http_Client.Requests.Request;
      Result      : out Http_Client.Clients.Client_Result;
      Status      : out Http_Client.Errors.Result_Status)
   is
      Client : Http_Client.Clients.Client;
      Config : Http_Client.Clients.Client_Configuration := Http_Client.Clients.Default_Client_Configuration;
   begin
      Config.Execution := Proxy_Options (Proxy_Port);
      Client := Http_Client.Clients.Create;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "CONNECT TLS client should initialize");
      Status := Http_Client.Clients.Execute (Client, Request, Result);
      pragma Unreferenced (Origin_Port);
   end Execute_Through_Proxy;

   procedure Test_CONNECT_TLS_GET_With_Configured_CA_Succeeds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "HTTPS over CONNECT should execute successfully");
      Assert (Result.Status = Http_Client.Errors.Ok, "client result status should be Ok");
      Assert (Http_Client.Responses.Status_Code (Result.Response) = 200, "origin response status should be 200");
      Assert (Fixtures.CONNECT_Saw_CONNECT, "proxy should receive CONNECT before TLS");
      Assert (Fixtures.CONNECT_Tunnel_Client_To_Origin_Bytes > 0, "proxy should tunnel encrypted client bytes");
      Assert (Fixtures.CONNECT_Tunnel_Origin_To_Client_Bytes > 0, "proxy should tunnel encrypted origin bytes");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_GET_With_Configured_CA_Succeeds;

   procedure Test_CONNECT_TLS_Binary_Body_Preserved

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "binary HTTPS over CONNECT should execute");
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Result.Response),
         "binary HTTPS over CONNECT response");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Binary_Body_Preserved;

   procedure Test_CONNECT_TLS_Proxy_Receives_CONNECT_Only_Before_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_OK_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
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
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Request, Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "POST through CONNECT should execute");
      Assert (Capture_Contains ("CONNECT 127.0.0.1:" & Decimal_Image (Origin_Port) & " HTTP/1.1"),
              "proxy capture should contain only CONNECT authority for the origin");
      Assert (not Capture_Contains ("Authorization: Basic origin-secret"),
              "origin Authorization must not be visible to proxy before tunnel");
      Assert (not Capture_Contains ("Cookie: sid=origin-cookie"),
              "origin Cookie must not be visible to proxy before tunnel");
      Assert (not Capture_Contains ("Git-Protocol: version=2"),
              "Git-Protocol must not be visible to proxy before tunnel");
      Assert (not Capture_Contains ("application/x-git-upload-pack-request"),
              "Git Content-Type must not be visible to proxy before tunnel");
      Assert (not Capture_Contains ("secret-body-pkt-line"),
              "origin body bytes must not be visible to proxy before tunnel");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Proxy_Receives_CONNECT_Only_Before_Tunnel;

   procedure Test_CONNECT_TLS_Proxy_Authorization_Sent_Only_To_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_OK_Response);
      Proxy_Port  : constant Natural :=
        Start_Proxy_Fixture
          (Origin_Port, Expected_Proxy_Auth => "Basic proxy-secret");
      Options     : Http_Client.Clients.Execution_Options := Proxy_Options (Proxy_Port);
      Config      : Http_Client.Clients.Client_Configuration := Http_Client.Clients.Default_Client_Configuration;
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Request     : constant Http_Client.Requests.Request := Build_Request (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Proxies.With_Proxy_Authorization
        (Options.Proxy, "Basic proxy-secret", Options.Proxy);
      Assert (Status = Http_Client.Errors.Ok, "proxy authorization should attach to proxy config");
      Config.Execution := Options;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "proxy-auth CONNECT client should initialize");
      Status := Http_Client.Clients.Execute (Client, Request, Result);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "proxy-auth CONNECT request should succeed");
      Assert (Result.Status = Http_Client.Errors.Ok, "proxy-auth CONNECT result should be Ok");
      Assert (Capture_Contains ("Proxy-Authorization: Basic proxy-secret"),
              "Proxy-Authorization should be sent on CONNECT");
      Assert (not Origin_Contains ("Proxy-Authorization: Basic proxy-secret"),
              "Proxy-Authorization must not be forwarded to the origin request");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Proxy_Authorization_Sent_Only_To_Proxy;

   procedure Test_CONNECT_TLS_Streaming_GET_Succeeds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Request     : constant Http_Client.Requests.Request := Build_Request (Origin_Port);
      Stream      : Http_Client.Response_Streams.Streaming_Response;
      Status      : Http_Client.Errors.Result_Status;
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. 3);
      Last        : Ada.Streams.Stream_Element_Offset;
      Total       : Natural := 0;
   begin
      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Options => Proxy_Stream_Options (Proxy_Port),
         Stream  => Stream);
      Assert (Status = Http_Client.Errors.Ok, "streaming HTTPS over CONNECT should open");
      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert (Status = Http_Client.Errors.Ok, "streaming HTTPS over CONNECT read should succeed");
         exit when Last < Buffer'First;
         Total := Total + Natural (Last - Buffer'First + 1);
      end loop;
      Status := Http_Client.Response_Streams.Close (Stream);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "streaming HTTPS over CONNECT close should succeed");
      Assert (Total = 7, "streaming HTTPS over CONNECT should preserve fixed binary body length");
   exception
      when others =>
         declare
            Ignore : Http_Client.Errors.Result_Status;
         begin
            Ignore := Http_Client.Response_Streams.Close (Stream);
            pragma Unreferenced (Ignore);
         end;
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Streaming_GET_Succeeds;

   procedure Test_CONNECT_TLS_Chunked_Response_Preserved

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Chunked_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok, "chunked HTTPS over CONNECT should execute");
      Assert_Binary_Body
        (Http_Client.Responses.Response_Body_Bytes (Result.Response),
         "chunked HTTPS over CONNECT response");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Chunked_Response_Preserved;

   procedure Test_CONNECT_TLS_Localhost_SNI_Uses_Origin_Host

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy
        (Origin_Port,
         Proxy_Port,
         Build_Request (Origin_Port, Host => "localhost"),
         Result,
         Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Ok,
              "localhost HTTPS over CONNECT should execute with configured CA");
      Assert (Capture_Contains ("CONNECT localhost:" & Decimal_Image (Origin_Port) & " HTTP/1.1"),
              "CONNECT authority should use the origin URI host, not the proxy host");
      Assert (Fixtures.TLS_SNI_Seen,
              "TLS SNI should use the DNS origin host inside the CONNECT tunnel");
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Localhost_SNI_Uses_Origin_Host;

   procedure Test_CONNECT_TLS_Certificate_Failure_After_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Start_TLS_Fixture (Fixture_Fixed_Response);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Options     : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
      Config      : Http_Client.Clients.Client_Configuration := Http_Client.Clients.Default_Client_Configuration;
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Request     : constant Http_Client.Requests.Request := Build_Request (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
      Options.Proxy := Http_Client.Proxies.HTTP ("127.0.0.1", Http_Client.URI.TCP_Port (Proxy_Port));
      Apply_Test_Timeouts (Options);
      Config.Execution := Options;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "CONNECT certificate failure client should initialize");
      Status := Http_Client.Clients.Execute (Client, Request, Result);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Result.Status /= Http_Client.Errors.Ok,
              "certificate failure result should not be Ok");
      Assert (Fixtures.CONNECT_Saw_CONNECT,
              "certificate verification failure should happen after successful CONNECT");
      Assert (Status = Http_Client.Errors.Certificate_Verification_Failed
              or else Status = Http_Client.Errors.TLS_Handshake_Failed
              or else Status = Http_Client.Errors.TLS_Failed
              or else Status = Http_Client.Errors.Connection_Failed,
              "untrusted origin certificate after CONNECT should fail deterministically; actual status="
              & Http_Client.Errors.Result_Status'Image (Status));
   exception
      when others =>
         Fixtures.Stop_CONNECT_Proxy;
         Fixtures.Stop_TLS;
         raise;
   end Test_CONNECT_TLS_Certificate_Failure_After_Tunnel;

   procedure Test_CONNECT_Close_Before_Response_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Close_Before_Response);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
              "proxy close before CONNECT response should map to Proxy_Tunnel_Failed");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Close_Before_Response_Returns_Deterministic_Status;

   procedure Test_CONNECT_TLS_IPv6_Authority_Is_Bracketed

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Return_403);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy
        (Origin_Port,
         Proxy_Port,
         Build_Request (Origin_Port, Host => "[::1]"),
         Result,
         Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;

      Assert
        (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
         "403 CONNECT response for IPv6 literal should map to Proxy_Tunnel_Failed");
      Assert
        (Capture_Contains ("CONNECT [::1]:" & Decimal_Image (Origin_Port) & " HTTP/1.1"),
         "CONNECT authority should bracket IPv6 literal targets");
      Assert
        (Capture_Contains ("Host: [::1]:" & Decimal_Image (Origin_Port)),
         "CONNECT Host header should bracket IPv6 literal targets");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_TLS_IPv6_Authority_Is_Bracketed;

   procedure Test_CONNECT_Proxy_407_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Return_407);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Proxy_Authentication_Required,
              "407 CONNECT response should map to Proxy_Authentication_Required");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Proxy_407_Returns_Deterministic_Status;

   procedure Test_CONNECT_Proxy_403_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Return_403);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
              "403 CONNECT response should map to Proxy_Tunnel_Failed");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Proxy_403_Returns_Deterministic_Status;

   procedure Test_CONNECT_Proxy_502_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Return_502);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
              "502 CONNECT response should map to Proxy_Tunnel_Failed");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Proxy_502_Returns_Deterministic_Status;

   procedure Test_CONNECT_Malformed_Response_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Malformed_Response);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
              "malformed CONNECT response should map to Proxy_Tunnel_Failed");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Malformed_Response_Returns_Deterministic_Status;

   procedure Test_CONNECT_Tunnel_Close_During_TLS_Returns_Deterministic_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural := Unused_Origin_Port;
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port, Proxy_Close_During_TLS);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status /= Http_Client.Errors.Ok,
              "tunnel close during origin TLS handshake should return deterministic failure");
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_Tunnel_Close_During_TLS_Returns_Deterministic_Status;

   procedure Test_CONNECT_TLS_Hostname_Failure_After_Tunnel

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_Port : constant Natural :=
        Start_TLS_Fixture
          (Fixture_OK_Response, Fixture_Wronghost_Cert_Name, Fixture_Wronghost_Key_Name);
      Proxy_Port  : constant Natural := Start_Proxy_Fixture (Origin_Port);
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Execute_Through_Proxy (Origin_Port, Proxy_Port, Build_Request (Origin_Port), Result, Status);
      Fixtures.Stop_CONNECT_Proxy;
      Fixtures.Stop_TLS;
      Assert (Status = Http_Client.Errors.Hostname_Verification_Failed
              or else Status = Http_Client.Errors.Certificate_Verification_Failed
              or else Status = Http_Client.Errors.TLS_Handshake_Failed
              or else Status = Http_Client.Errors.Connection_Failed,
              "origin hostname verification should use origin host after CONNECT; actual status="
              & Http_Client.Errors.Result_Status'Image (Status));
   exception
      when others => Fixtures.Stop_CONNECT_Proxy; Fixtures.Stop_TLS; raise;
   end Test_CONNECT_TLS_Hostname_Failure_After_Tunnel;

   overriding procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_CONNECT_TLS_GET_With_Configured_CA_Succeeds'Access,
                        "Test_CONNECT_TLS_GET_With_Configured_CA_Succeeds");
      Register_Routine (T, Test_CONNECT_TLS_Streaming_GET_Succeeds'Access,
                        "Test_CONNECT_TLS_Streaming_GET_Succeeds");
      Register_Routine (T, Test_CONNECT_TLS_Binary_Body_Preserved'Access,
                        "Test_CONNECT_TLS_Binary_Body_Preserved");
      Register_Routine (T, Test_CONNECT_TLS_Chunked_Response_Preserved'Access,
                        "Test_CONNECT_TLS_Chunked_Response_Preserved");
      Register_Routine (T, Test_CONNECT_TLS_Proxy_Receives_CONNECT_Only_Before_Tunnel'Access,
                        "Test_CONNECT_TLS_Proxy_Receives_CONNECT_Only_Before_Tunnel");
      Register_Routine (T, Test_CONNECT_TLS_Proxy_Authorization_Sent_Only_To_Proxy'Access,
                        "Test_CONNECT_TLS_Proxy_Authorization_Sent_Only_To_Proxy");
      Register_Routine (T, Test_CONNECT_TLS_Localhost_SNI_Uses_Origin_Host'Access,
                        "Test_CONNECT_TLS_Localhost_SNI_Uses_Origin_Host");
      Register_Routine (T, Test_CONNECT_TLS_Certificate_Failure_After_Tunnel'Access,
                        "Test_CONNECT_TLS_Certificate_Failure_After_Tunnel");
      Register_Routine (T, Test_CONNECT_TLS_IPv6_Authority_Is_Bracketed'Access,
                        "Test_CONNECT_TLS_IPv6_Authority_Is_Bracketed");
      Register_Routine (T, Test_CONNECT_Proxy_407_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Proxy_407_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_Proxy_403_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Proxy_403_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_Proxy_502_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Proxy_502_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_Malformed_Response_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Malformed_Response_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_Close_Before_Response_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Close_Before_Response_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_Tunnel_Close_During_TLS_Returns_Deterministic_Status'Access,
                        "Test_CONNECT_Tunnel_Close_During_TLS_Returns_Deterministic_Status");
      Register_Routine (T, Test_CONNECT_TLS_Hostname_Failure_After_Tunnel'Access,
                        "Test_CONNECT_TLS_Hostname_Failure_After_Tunnel");
   end Register_Tests;
end Http_Client.Connect_TLS_Tests;
