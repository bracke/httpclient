with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Auth.Digest;
with Http_Client.Auth.Scopes;
with Http_Client.Alt_Svc;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Clients;
with Http_Client.Cookies;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTPS_Records;
with Http_Client.HTTP1;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Frames;
with Http_Client.HTTP3.Streams;
with Http_Client.QUIC;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Proxies.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;

   function Natural_Image_No_Space (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image_No_Space;

   function Closed_Loopback_Port return Http_Client.URI.TCP_Port is
      Server      : GNAT.Sockets.Socket_Type;
      Server_Addr : GNAT.Sockets.Sock_Addr_Type
        (GNAT.Sockets.Family_Inet);
      Bound       : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Create_Socket (Server);

      Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Server_Addr.Port := 0;

      GNAT.Sockets.Bind_Socket (Server, Server_Addr);
      Bound := GNAT.Sockets.Get_Socket_Name (Server);
      GNAT.Sockets.Close_Socket (Server);

      return Http_Client.URI.TCP_Port (Bound.Port);
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Server);
         exception
            when others =>
               null;
         end;

         return 9;
   end Closed_Loopback_Port;

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

   procedure Test_Auth_Proxy_Helper_Separation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Proxy      : Http_Client.Proxies.Proxy_Config;
      Auth_Proxy : Http_Client.Proxies.Proxy_Config;
   begin
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "proxy URI for auth helper should parse");
      Assert
        (Http_Client.Auth.Set_Basic_Proxy_Authorization
           (Proxy, "proxy", "secret", Auth_Proxy)
         = Http_Client.Errors.Ok,
         "proxy auth helper should attach Basic credentials to proxy config");
      Assert
        (Http_Client.Proxies.Has_Proxy_Authorization (Auth_Proxy),
         "proxy config should report helper-generated proxy authorization");
      Assert
        (Http_Client.Proxies.Proxy_Authorization (Auth_Proxy)
         = "Basic cHJveHk6c2VjcmV0",
         "proxy auth helper should generate the expected proxy-only field value");
      Assert
        (Http_Client.Auth.Set_Basic_Proxy_Authorization
           (Http_Client.Proxies.No_Proxy_Config, "proxy", "secret", Auth_Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy auth helper should not attach credentials to No_Proxy_Config");
      Assert
        (Http_Client.Auth.Set_Basic_Proxy_Authorization
           (Proxy, "proxy:name", "secret", Auth_Proxy)
         = Http_Client.Errors.Invalid_Credentials,
         "proxy auth helper should validate credentials before storing proxy metadata");
   end Test_Auth_Proxy_Helper_Separation;

   procedure Test_Auth_Digest_Request_Proxy_And_Scope_Helpers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_One    : Http_Client.URI.URI_Reference;
      URI_Two    : Http_Client.URI.URI_Reference;
      URI_HTTPS  : Http_Client.URI.URI_Reference;
      Request    : Http_Client.Requests.Request;
      With_Auth  : Http_Client.Requests.Request;
      Parsed     : Http_Client.Auth.Digest.Challenge;
      Header     : Ada.Strings.Unbounded.Unbounded_String;
      Proxy      : Http_Client.Proxies.Proxy_Config;
      Auth_Proxy : Http_Client.Proxies.Proxy_Config;
      Scope      : Http_Client.Auth.Scopes.Origin_Scope;
   begin
      Assert_Parse_Ok
        ("http://Example.com:80/dir/index.html?x=1#frag",
         URI_One,
         "Digest request helper URI should parse");
      Assert_Parse_Ok
        ("http://example.com/other",
         URI_Two,
         "same-origin scope URI should parse");
      Assert_Parse_Ok
        ("https://example.com/other",
         URI_HTTPS,
         "cross-scheme scope URI should parse");
      Assert
        (Http_Client.Auth.Scopes.Create_Origin (URI_One, Scope)
         = Http_Client.Errors.Ok,
         "origin authentication scope should be constructible from parsed URI");
      Assert
        (Http_Client.Auth.Scopes.Scheme (Scope) = "http"
         and then Http_Client.Auth.Scopes.Host (Scope) = "example.com"
         and then Http_Client.Auth.Scopes.Port (Scope) = 80,
         "origin authentication scope should normalize scheme host and effective port");
      Assert
        (Http_Client.Auth.Scopes.Matches (Scope, URI_Two),
         "same scheme host and effective port should match authentication scope");
      Assert
        (not Http_Client.Auth.Scopes.Matches (Scope, URI_HTTPS),
         "different scheme must not match authentication scope");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI_One, Item => Request)
         = Http_Client.Errors.Ok,
         "Digest request helper request should construct");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", algorithm=SHA-256, qop=auth",
            Parsed)
         = Http_Client.Errors.Ok,
         "Digest request helper challenge should parse");
      Assert
        (Http_Client.Auth.Digest.Generate_Response_For_Request
           (Parsed, Request, "user", "pass", 1, "abcdef", Header)
         = Http_Client.Errors.Ok,
         "Digest request helper should compute response using request target");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Header),
            "uri=""/dir/index.html?x=1""")
         > 0,
         "Digest request helper must exclude fragment from digest uri");
      Assert
        (Http_Client.Auth.Digest.Set_Digest_Authorization
           (Request, Ada.Strings.Unbounded.To_String (Header), With_Auth)
         = Http_Client.Errors.Ok,
         "Digest origin helper should attach generated Authorization");
      Assert
        (Ada.Strings.Fixed.Index
           (Http_Client.Headers.Get
              (Http_Client.Requests.Headers (With_Auth), "Authorization"),
            "Digest username=""user""")
         = 1,
         "Digest origin helper should store Digest Authorization only on request");
      Assert
        (Http_Client.Auth.Digest.Set_Digest_Authorization
           (Request, "Basic abc", With_Auth)
         = Http_Client.Errors.Invalid_Header,
         "Digest origin helper should reject non-Digest header values");
      Assert
        (Http_Client.Auth.Digest.Set_Digest_Authorization
           (Request, "Digest abc" & Character'Val (10), With_Auth)
         = Http_Client.Errors.Invalid_Header,
         "Digest origin helper should reject header injection in generated values");

      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "Digest proxy helper proxy URI should parse");
      Assert
        (Http_Client.Auth.Digest.Set_Digest_Proxy_Authorization
           (Proxy, Ada.Strings.Unbounded.To_String (Header), Auth_Proxy)
         = Http_Client.Errors.Ok,
         "Digest proxy helper should attach proxy-only credentials");
      Assert
        (Http_Client.Proxies.Proxy_Authorization (Auth_Proxy)
         = Ada.Strings.Unbounded.To_String (Header),
         "Digest proxy helper should preserve generated proxy authorization value");
      Assert
        (Http_Client.Auth.Digest.Set_Digest_Proxy_Authorization
           (Http_Client.Proxies.No_Proxy_Config,
            Ada.Strings.Unbounded.To_String (Header),
            Auth_Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "Digest proxy helper must not attach credentials to No_Proxy_Config");
   end Test_Auth_Digest_Request_Proxy_And_Scope_Helpers;

   procedure Test_Proxy_Config_Parsing

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Proxy      : Http_Client.Proxies.Proxy_Config;
      Auth_Proxy : Http_Client.Proxies.Proxy_Config;
   begin
      Assert
        (not Http_Client.Proxies.Is_Enabled
               (Http_Client.Proxies.No_Proxy_Config),
         "no-proxy config should not route through a proxy");

      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "http proxy URI should parse");
      Assert
        (Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.HTTP_Proxy,
         "parsed proxy should be HTTP_Proxy");
      Assert
        (Http_Client.Proxies.Host (Proxy) = "proxy.example",
         "proxy host should be normalized by URI parser");
      Assert
        (Http_Client.Proxies.Port (Proxy) = 8080,
         "explicit proxy port should be preserved");

      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example", Proxy)
         = Http_Client.Errors.Ok,
         "http proxy URI without explicit port should parse");
      Assert
        (Http_Client.Proxies.Port (Proxy) = 80,
         "http proxy URI default port should be 80");

      Proxy := Http_Client.Proxies.HTTP ("proxy.example");
      Assert
        (Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.HTTP_Proxy,
         "HTTP proxy constructor with default port should create HTTP proxy");
      Assert
        (Http_Client.Proxies.Port (Proxy) = 80,
         "HTTP proxy constructor default port should be 80");

      Assert
        (Http_Client.Proxies.Parse ("HTTP://Proxy.Example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "proxy URI parsing should accept uppercase scheme and normalize host");
      Assert
        (Http_Client.Proxies.Host (Proxy) = "proxy.example",
         "proxy URI parsing should normalize proxy host case");

      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example/", Proxy)
         = Http_Client.Errors.Ok,
         "proxy URI with empty root path should parse");
      Assert
        (Http_Client.Proxies.Parse ("http://:8080", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI with empty host should be invalid");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:0", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI with port zero should be invalid");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:65536", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI with out-of-range port should be invalid");

      Assert
        (Http_Client.Proxies.Parse ("https://proxy.example:8443", Proxy)
         = Http_Client.Errors.Proxy_Unsupported,
         "https proxy URI should be explicitly unsupported");
      Assert
        (Http_Client.Proxies.Parse ("socks5://proxy.example:1080", Proxy)
         = Http_Client.Errors.Ok,
         "SOCKS5 proxy URI should be explicitly supported");
      Assert
        (Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.SOCKS5_Proxy,
         "SOCKS5 proxy URI should produce SOCKS5 proxy config");
      Assert
        (Http_Client.Proxies.Parse
           ("http://user:pass@proxy.example:8080", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "userinfo proxy credentials should be rejected");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080/path", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI path beyond / should be rejected");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example?x=1", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI with query should be rejected");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example#frag", Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy URI with fragment should be rejected");
      Assert
        (Http_Client.Proxies.With_Proxy_Authorization
           (Http_Client.Proxies.No_Proxy_Config,
            "Basic dXNlcjpwYXNz",
            Auth_Proxy)
         = Http_Client.Errors.Invalid_Proxy,
         "proxy authorization should require an enabled proxy config");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "proxy URI for authorization test should parse");
      Assert
        (Http_Client.Proxies.With_Proxy_Authorization (Proxy, "", Auth_Proxy)
         = Http_Client.Errors.Invalid_Header,
         "empty proxy authorization field value should be rejected");
      Assert
        (Http_Client.Proxies.With_Proxy_Authorization
           (Proxy, "Basic dXNlcjpwYXNz", Auth_Proxy)
         = Http_Client.Errors.Ok,
         "valid explicit proxy authorization field value should be accepted");
      Assert
        (Http_Client.Proxies.Has_Proxy_Authorization (Auth_Proxy),
         "proxy config should report attached proxy authorization");
      Assert
        (Http_Client.Proxies.Proxy_Authorization (Auth_Proxy)
         = "Basic dXNlcjpwYXNz",
         "proxy authorization accessor should return attached value");
   end Test_Proxy_Config_Parsing;

   procedure Test_Client_HTTPS_Proxy_CONNECT_Attempts_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Proxy    : Http_Client.Proxies.Proxy_Config;
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Options  : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Proxy_Port : constant Http_Client.URI.TCP_Port := Closed_Loopback_Port;
   begin
      Assert
        (Http_Client.Proxies.Parse
           ("http://127.0.0.1:" & Natural_Image_No_Space (Natural (Proxy_Port)), Proxy)
         = Http_Client.Errors.Ok,
         "proxy for HTTPS CONNECT test should parse");
      Options.Proxy := Proxy;

      Assert_Parse_Ok
        ("https://example.com/secure",
         URI,
         "HTTPS URI for proxy CONNECT test should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS request for proxy CONNECT test should construct");

      Assert
        (Http_Client.Clients.Execute
           (Item     => Client,
            Request  => Request,
            Response => Response,
            Options  => Options)
         = Http_Client.Errors.Proxy_Connection_Failed,
         "HTTPS through HTTP proxy should attempt CONNECT and report " &
         "proxy connection failure when the proxy is unreachable");
   end Test_Client_HTTPS_Proxy_CONNECT_Attempts_Proxy;

   procedure Test_Client_HTTPS_SOCKS_Proxy_Attempts_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Proxy    : Http_Client.Proxies.Proxy_Config;
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Options  : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Client   : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Proxy_Port : constant Http_Client.URI.TCP_Port := Closed_Loopback_Port;
   begin
      Proxy := Http_Client.Proxies.SOCKS5 ("127.0.0.1", Proxy_Port);
      Options.Proxy := Proxy;

      Assert_Parse_Ok
        ("https://example.com/secure",
         URI,
         "HTTPS URI for SOCKS proxy test should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS request for SOCKS proxy test should construct");

      Assert
        (Http_Client.Clients.Execute
           (Item     => Client,
            Request  => Request,
            Response => Response,
            Options  => Options)
         = Http_Client.Errors.Proxy_Connection_Failed,
         "HTTPS through SOCKS proxy should attempt the SOCKS proxy and " &
         "report proxy connection failure when unreachable");
   end Test_Client_HTTPS_SOCKS_Proxy_Attempts_Proxy;

   procedure Test_High_Level_Client_Strips_Request_Proxy_Authorization_Direct

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Loopback_Server;

      task body Loopback_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
      begin
         GNAT.Sockets.Create_Socket (Server);

         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;

         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);

         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end;

         declare
            Response : constant String :=
              "HTTP/1.1 200 OK"
              & CRLF
              & "Content-Length: 2"
              & CRLF
              & CRLF
              & "OK";
            Raw      :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response'Length));
            Last     : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response
                         (Response'First + Natural (Index - Raw'First))));
            end loop;

            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end;

         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      Port_Text     : Unbounded_String;
      URI           : Http_Client.URI.URI_Reference;
      Headers       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Request       : Http_Client.Requests.Request;
      Client        : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert
        (Http_Client.URI.Parse
           ("http://127.0.0.1:" & To_String (Port_Text) & "/direct", URI)
         = Http_Client.Errors.Ok,
         "direct request URI with loopback port should parse");

      Assert
        (Http_Client.Headers.Set
           (Headers, "Proxy-Authorization", "Basic should-not-leak")
         = Http_Client.Errors.Ok,
         "request-specific proxy authorization header should be constructible for leak test");

      Assert
        (Http_Client.Headers.Set (Headers, "X-Origin", "kept")
         = Http_Client.Errors.Ok,
         "ordinary request header should be constructible for proxy leak test");

      Assert
        (Http_Client.Requests.Create
           (Method    => Http_Client.Types.GET,
            URI       => URI,
            Item      => Request,
            Headers   => Headers,
            Auto_Host => True)
         = Http_Client.Errors.Ok,
         "direct request with proxy authorization test header should construct");

      Status := Http_Client.Clients.Execute (Client, Request, Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level direct request should succeed while sanitizing proxy metadata");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Proxy-Authorization:") = 0,
         "high-level direct origin-form execution must strip request Proxy-Authorization");

      Assert
        (Index (Captured_Text, "X-Origin: kept" & CRLF) > 0,
         "high-level direct execution should preserve ordinary request headers");
   end Test_High_Level_Client_Strips_Request_Proxy_Authorization_Direct;

   procedure Test_High_Level_Client_Proxy_Config_Routes_HTTP_And_Proxy_Auth

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Proxy_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Proxy_Server;

      task body Proxy_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);

         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end;

         declare
            Response : constant String :=
              "HTTP/1.1 200 OK"
              & CRLF
              & "Content-Length: 5"
              & CRLF
              & CRLF
              & "proxy";
            Raw      :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response'Length));
            Last     : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response
                         (Response'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end;

         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Proxy_Server;

      Server        : Proxy_Server;
      Port          : Http_Client.URI.TCP_Port;
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Proxy_Config  : Http_Client.Proxies.Proxy_Config;
      Client        : Http_Client.Clients.Client;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Expected      : constant String :=
        Http_Client.Auth.Basic_Proxy_Authorization_Value ("proxy", "secret");
   begin
      Server.Ready (Port);

      Proxy_Config := Http_Client.Proxies.HTTP ("127.0.0.1", Port);
      Assert
        (Http_Client.Proxies.Is_Enabled (Proxy_Config),
         "loopback HTTP proxy config should be enabled");

      Status :=
        Http_Client.Auth.Set_Basic_Proxy_Authorization
          (Config   => Proxy_Config,
           Username => "proxy",
           Password => "secret",
           Result   => Config.Execution.Proxy);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level proxy Basic authorization helper should configure proxy metadata");

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level proxy client configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client, "http://origin.example/resource?x=1", Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level HTTP proxy request should return proxy response");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index
           (Captured_Text,
            "GET http://origin.example/resource?x=1 HTTP/1.1" & CRLF)
         > 0,
         "high-level proxy execution should use absolute-form request target");

      Assert
        (Index (Captured_Text, "Host: origin.example" & CRLF) > 0,
         "high-level proxy execution should preserve the origin Host header");

      Assert
        (Index (Captured_Text, "Proxy-Authorization: " & Expected & CRLF) > 0,
         "high-level proxy execution should send configured proxy credentials only to the proxy hop");
   end Test_High_Level_Client_Proxy_Config_Routes_HTTP_And_Proxy_Auth;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Proxies");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Auth_Proxy_Helper_Separation'Access,
         "Test_Auth_Proxy_Helper_Separation");
      Register_Routine
        (T,
         Test_Auth_Digest_Request_Proxy_And_Scope_Helpers'Access,
         "Test_Auth_Digest_Request_Proxy_And_Scope_Helpers");
      Register_Routine
        (T,
         Test_Proxy_Config_Parsing'Access,
         "Test_Proxy_Config_Parsing");
      Register_Routine
        (T,
         Test_Client_HTTPS_Proxy_CONNECT_Attempts_Proxy'Access,
         "Test_Client_HTTPS_Proxy_CONNECT_Attempts_Proxy");
      Register_Routine
        (T,
         Test_Client_HTTPS_SOCKS_Proxy_Attempts_Proxy'Access,
         "Test_Client_HTTPS_SOCKS_Proxy_Attempts_Proxy");
      Register_Routine
        (T,
         Test_High_Level_Client_Strips_Request_Proxy_Authorization_Direct'Access,
         "Test_High_Level_Client_Strips_Request_Proxy_Authorization_Direct");
      Register_Routine
        (T,
         Test_High_Level_Client_Proxy_Config_Routes_HTTP_And_Proxy_Auth'Access,
         "Test_High_Level_Client_Proxy_Config_Routes_HTTP_And_Proxy_Auth");
   end Register_Tests;

end Http_Client.Proxies.Tests;
