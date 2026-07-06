with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.Sockets;

with AUnit.Assertions;
with AUnit.Test_Suites;

with Http_Client.Auth;
with Http_Client.Auth.Bearer;
with Http_Client.Auth.Digest;
with Http_Client.Auth.Scopes;
with Http_Client.Alt_Svc;
with Http_Client.Async;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Clients;
with Http_Client.Connection_Pools;
with Http_Client.Cookies;
with Http_Client.Crypto;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTPS_Records;
with Http_Client.HTTP1;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Body_Streams;
with Http_Client.HTTP2.Uploads;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.HTTP2.Single_Stream;
with Http_Client.HTTP2.Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Execution;
with Http_Client.HTTP3.Frames;
with Http_Client.HTTP3.Mapping;
with Http_Client.HTTP3.QPACK;
with Http_Client.HTTP3.Settings;
with Http_Client.HTTP3.Streams;
with Http_Client.QUIC;
with Http_Client.Multipart;
with Http_Client.HTTP1.Reader;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Resources;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Proxies.SOCKS.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Errors.Result_Category;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;
   use type Http_Client.URI.TCP_Port;
   use type Http_Client.Transports.TCP.Timeout_Milliseconds;
   use type Http_Client.Responses.HTTP_Version;
   use type Http_Client.Cookies.SameSite_Policy;
   use type Http_Client.Cookies.Cookie_Jar_Access;
   use type Http_Client.Request_Bodies.Body_Kind;
   use type Http_Client.Cache.Cache_Source;
   use type Http_Client.Cache.Cache_Store_Access;
   use type Http_Client.Cache.Persistent.Persistent_Store_Access;
   use type Http_Client.Diagnostics.Event_Kind;
   use type Http_Client.Diagnostics.Cache_Result;
   use type Http_Client.Diagnostics.Diagnostic_ID;
   use type Http_Client.Diagnostics.Context_Access;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Alt_Svc.Alternative_Protocol;
   use type Http_Client.Protocol_Discovery.Selection_Source;
   use type Http_Client.HTTPS_Records.ALPN_ID;
   use type Http_Client.HTTP2.HTTP2_Mode;
   use type Http_Client.HTTP2.Selected_Protocol;
   use type Http_Client.HTTP2.Frames.Frame_Type;
   use type Http_Client.HTTP2.Frames.Frame_Length;
   use type Http_Client.HTTP2.Frames.Stream_ID;
   use type Http_Client.HTTP2.Streams.Stream_State;
   use type Http_Client.HTTP3.HTTP3_Mode;
   use type Http_Client.HTTP3.Selected_Protocol;
   use type Http_Client.HTTP3.Frames.Frame_Type;
   use type Http_Client.HTTP3.Streams.Stream_Kind;
   use type Http_Client.QUIC.Backend_Availability;
   use type Ada.Calendar.Time;

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

   procedure Test_SOCKS5_Proxy_Config_And_Protocol

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Proxies.Proxy_Config;
      Auth   : Http_Client.Proxies.Proxy_Config;
      Bytes  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert
        (Http_Client.Proxies.Parse ("socks5://127.0.0.1:1080", Config)
         = Http_Client.Errors.Ok,
         "socks5 proxy URI should parse explicitly");
      Assert
        (Http_Client.Proxies.Parse ("socks5h://proxy.example:1080", Config)
         = Http_Client.Errors.Ok,
         "socks5h proxy URI should parse explicitly for remote DNS");
      Assert
        (Http_Client.Proxies.SOCKS5_DNS_Resolution (Config)
         = Http_Client.Proxies.SOCKS5_Remote_DNS,
         "socks5h proxy URI should select remote DNS");
      Assert
        (Http_Client.Proxies.Parse ("socks4://proxy.example:1080", Config)
         = Http_Client.Errors.Proxy_Unsupported,
         "socks4 proxy URI should be explicitly unsupported");
      Assert
        (Http_Client.Proxies.Parse ("socks5://user@proxy.example:1080", Config)
         = Http_Client.Errors.Invalid_SOCKS_Proxy,
         "SOCKS proxy URI userinfo should be rejected rather than treated as credentials");
      Assert
        (Http_Client.Proxies.Parse ("SOCKS5://127.0.0.1:1080", Config)
         = Http_Client.Errors.Ok,
         "SOCKS5 proxy URI scheme parsing should be case-insensitive");
      Assert
        (Http_Client.Proxies.Kind (Config) = Http_Client.Proxies.SOCKS5_Proxy,
         "socks5 proxy URI should produce SOCKS5_Proxy kind");
      Assert
        (Http_Client.Proxies.SOCKS5_DNS_Resolution (Config)
         = Http_Client.Proxies.SOCKS5_Remote_DNS,
         "socks5 default DNS mode should be remote DNS");
      Assert
        (Http_Client.Proxies.With_Proxy_Authorization
           (Config, "Basic abc", Auth)
         = Http_Client.Errors.Invalid_Proxy,
         "HTTP proxy authorization must not attach to SOCKS proxies");
      Assert
        (Http_Client.Proxies.With_SOCKS5_Username_Password
           (Config, "", "pass", Auth)
         = Http_Client.Errors.Invalid_Credentials,
         "SOCKS5 empty username should be rejected deterministically");
      Assert
        (Http_Client.Proxies.With_SOCKS5_Username_Password
           (Config, "user", Character'Val (10) & "pass", Auth)
         = Http_Client.Errors.Invalid_Credentials,
         "SOCKS5 control characters in credentials should be rejected");
      Assert
        (Http_Client.Proxies.With_SOCKS5_Username_Password
           (Config, "user", "pass", Auth)
         = Http_Client.Errors.Ok,
         "SOCKS5 username/password credentials should attach to SOCKS proxy config");
      Assert
        (Http_Client.Proxies.SOCKS.Greeting (Config, Bytes)
         = Http_Client.Errors.Ok,
         "SOCKS5 no-auth greeting should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Bytes)
         = Character'Val (16#05#) & Character'Val (1) & Character'Val (0),
         "SOCKS5 no-auth greeting bytes should be exact");
      Assert
        (Http_Client.Proxies.SOCKS.Greeting (Auth, Bytes)
         = Http_Client.Errors.Ok,
         "SOCKS5 authenticated greeting should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Bytes)
         = Character'Val (16#05#) & Character'Val (1) & Character'Val (2),
         "SOCKS5 authenticated greeting bytes should be exact");
      Assert
        (Http_Client.Proxies.SOCKS.Username_Password_Request (Auth, Bytes)
         = Http_Client.Errors.Ok,
         "SOCKS5 username/password subnegotiation should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Bytes)
         = Character'Val (1)
           & Character'Val (4)
           & "user"
           & Character'Val (4)
           & "pass",
         "SOCKS5 username/password subnegotiation bytes should be exact");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Method_Selection
           (Character'Val (16#05#) & Character'Val (2), Auth)
         = Http_Client.Errors.Ok,
         "SOCKS5 method selection should accept the configured method");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Method_Selection
           (Character'Val (16#05#) & Character'Val (16#FF#), Auth)
         = Http_Client.Errors.SOCKS_Unsupported_Authentication_Method,
         "SOCKS5 no-acceptable-methods reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Username_Password_Reply
           (Character'Val (1) & Character'Val (1))
         = Http_Client.Errors.SOCKS_Authentication_Failed,
         "SOCKS5 auth failure should map deterministically");
   end Test_SOCKS5_Proxy_Config_And_Protocol;

   procedure Test_SOCKS5_CONNECT_Request_And_Replies

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Bytes : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("example.com", 443, Http_Client.Proxies.SOCKS5_Remote_DNS, Bytes)
         = Http_Client.Errors.Ok,
         "SOCKS5 remote-DNS CONNECT request should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Bytes)
         = Character'Val (5)
           & Character'Val (1)
           & Character'Val (0)
           & Character'Val (3)
           & Character'Val (11)
           & "example.com"
           & Character'Val (1)
           & Character'Val (187),
         "SOCKS5 domain CONNECT bytes should be exact");
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("127.0.0.1", 80, Http_Client.Proxies.SOCKS5_Remote_DNS, Bytes)
         = Http_Client.Errors.Ok,
         "SOCKS5 IPv4 CONNECT request should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Bytes)
         = Character'Val (5)
           & Character'Val (1)
           & Character'Val (0)
           & Character'Val (1)
           & Character'Val (127)
           & Character'Val (0)
           & Character'Val (0)
           & Character'Val (1)
           & Character'Val (0)
           & Character'Val (80),
         "SOCKS5 IPv4 CONNECT bytes should be exact");
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("127.0.0.1", 80, Http_Client.Proxies.SOCKS5_Local_DNS, Bytes)
         = Http_Client.Errors.Ok,
         "local-DNS mode should accept already-resolved IPv4 literals");
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("example.com", 80, Http_Client.Proxies.SOCKS5_Local_DNS, Bytes)
         = Http_Client.Errors.SOCKS_Address_Type_Unsupported,
         "local-DNS mode should reject non-literal host when no portable resolver encoding is available");
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("bad" & Character'Val (10) & "host",
            80,
            Http_Client.Proxies.SOCKS5_Remote_DNS,
            Bytes)
         = Http_Client.Errors.Invalid_URI,
         "SOCKS5 CONNECT request should reject control characters in domain targets");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (127)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (1)
            & Character'Val (187))
         = Http_Client.Errors.Ok,
         "SOCKS5 successful CONNECT reply should parse");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (5)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Reply_Connection_Refused,
         "SOCKS5 connection-refused reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_General_Server_Failure,
         "SOCKS5 general-server-failure reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (2)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Connection_Not_Allowed,
         "SOCKS5 connection-not-allowed reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (3)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Reply_Network_Unreachable,
         "SOCKS5 network-unreachable reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (4)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Reply_Host_Unreachable,
         "SOCKS5 host-unreachable reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (6)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_TTL_Expired,
         "SOCKS5 TTL-expired reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (7)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Command_Unsupported,
         "SOCKS5 command-unsupported reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (8)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Address_Type_Unsupported,
         "SOCKS5 address-type-unsupported reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (4)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (1)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Unsupported_Version,
         "SOCKS5 wrong version reply should map deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           ("2001:db8::1", 443, Http_Client.Proxies.SOCKS5_Remote_DNS, Bytes)
         = Http_Client.Errors.SOCKS_Address_Type_Unsupported,
         "SOCKS5 CONNECT request should reject IPv6 text with deterministic unsupported address status");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Connect_Reply
           (Character'Val (5)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (3)
            & Character'Val (0)
            & Character'Val (0)
            & Character'Val (0))
         = Http_Client.Errors.SOCKS_Malformed_Reply,
         "SOCKS5 domain reply with zero-length bound address should be malformed");
   end Test_SOCKS5_CONNECT_Request_And_Replies;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("SOCKS");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_SOCKS5_Proxy_Config_And_Protocol'Access,
         "Test_SOCKS5_Proxy_Config_And_Protocol");
      Register_Routine
        (T,
         Test_SOCKS5_CONNECT_Request_And_Replies'Access,
         "Test_SOCKS5_CONNECT_Request_And_Replies");
   end Register_Tests;

end Http_Client.Proxies.SOCKS.Tests;
