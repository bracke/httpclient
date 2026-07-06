package Http_Client.Ada_Test_Fixtures is
   --  Ada task-based local test fixtures for release-gating TLS, CONNECT,
   --  and SOCKS5 coverage.  The fixture implementation is Ada and uses Ada
   --  tasking plus GNAT.Sockets.  It does not provide or require C test
   --  fixture objects, POSIX thread fixture support, or C ABI glue between
   --  AUnit tests and fixture control APIs.
   pragma Elaborate_Body;

   subtype Fixture_Mode is Integer;

   TLS_Fixed_Response   : constant Fixture_Mode := 1;
   TLS_Chunked_Response : constant Fixture_Mode := 2;
   TLS_Expect_Response  : constant Fixture_Mode := 3;
   TLS_OK_Response      : constant Fixture_Mode := 4;
   TLS_H2_Large_Response : constant Fixture_Mode := 5;

   CONNECT_Success       : constant Fixture_Mode := 1;
   CONNECT_Return_407    : constant Fixture_Mode := 2;
   CONNECT_Return_403    : constant Fixture_Mode := 3;
   CONNECT_Return_502    : constant Fixture_Mode := 4;
   CONNECT_Malformed     : constant Fixture_Mode := 5;
   CONNECT_Close_Before  : constant Fixture_Mode := 6;
   CONNECT_Close_During  : constant Fixture_Mode := 7;

   SOCKS_No_Auth_Success            : constant Fixture_Mode := 1;
   SOCKS_Userpass_Success           : constant Fixture_Mode := 2;
   SOCKS_No_Acceptable_Methods      : constant Fixture_Mode := 3;
   SOCKS_Userpass_Failure           : constant Fixture_Mode := 4;
   SOCKS_Malformed_Auth_Response    : constant Fixture_Mode := 5;
   SOCKS_Connect_General_Failure    : constant Fixture_Mode := 6;
   SOCKS_Connect_Host_Unreachable   : constant Fixture_Mode := 7;
   SOCKS_Connect_Connection_Refused : constant Fixture_Mode := 8;
   SOCKS_Malformed_Connect_Reply    : constant Fixture_Mode := 9;
   SOCKS_Close_Before_Reply         : constant Fixture_Mode := 10;
   SOCKS_Close_During_TLS           : constant Fixture_Mode := 11;
   SOCKS_Unsupported_Version_Reply  : constant Fixture_Mode := 12;

   function Start_TLS
     (Certificate_File : String;
      Private_Key_File : String;
      Mode             : Fixture_Mode) return Natural;

   procedure Stop_TLS;
   function TLS_Join_Result return Integer;
   function TLS_Request_Contains (Needle : String) return Boolean;
   function TLS_SNI_Seen return Boolean;

   function Start_CONNECT_Proxy
     (Origin_Host         : String;
      Origin_Port         : Natural;
      Mode                : Fixture_Mode;
      Expected_Proxy_Auth : String := "") return Natural;

   procedure Stop_CONNECT_Proxy;
   function CONNECT_Capture_Contains (Needle : String) return Boolean;
   function CONNECT_Saw_CONNECT return Boolean;
   function CONNECT_Tunnel_Client_To_Origin_Bytes return Natural;
   function CONNECT_Tunnel_Origin_To_Client_Bytes return Natural;

   function Start_SOCKS5_Proxy
     (Origin_Host   : String;
      Origin_Port   : Natural;
      Mode          : Fixture_Mode;
      Expected_User : String := "";
      Expected_Pass : String := "") return Natural;

   procedure Stop_SOCKS5_Proxy;
   function SOCKS5_Capture_Contains (Needle : String) return Boolean;
   function SOCKS5_Saw_CONNECT return Boolean;
   function SOCKS5_Tunnel_Client_To_Origin_Bytes return Natural;
   function SOCKS5_Tunnel_Origin_To_Client_Bytes return Natural;
   function SOCKS5_Auth_Seen return Boolean;
   function SOCKS5_Origin_Equals (Host : String; Port : Natural) return Boolean;
end Http_Client.Ada_Test_Fixtures;
