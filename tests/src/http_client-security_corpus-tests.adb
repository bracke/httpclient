with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.Sockets;

with AUnit.Assertions;

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
with Http_Client.Proxies;
with Http_Client.Protocol_Discovery;
with Http_Client.Proxies.SOCKS;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Resources;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Status_Test_Helpers;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Security_Corpus.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

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

   procedure Test_Phase37_URI_Security_Corpus

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      procedure Check_URI (Text : String; Must_Be_Valid : Boolean := False) is
         First_Item  : Http_Client.URI.URI_Reference;
         Second_Item : Http_Client.URI.URI_Reference;
         First       : Http_Client.Errors.Result_Status;
         Second      : Http_Client.Errors.Result_Status;
      begin
         First := Http_Client.URI.Parse (Text, First_Item);
         Second := Http_Client.URI.Parse (Text, Second_Item);

         Assert
           (First = Second,
            "URI corpus status should be deterministic for: " & Text);

         if Must_Be_Valid then
            Assert
              (First = Http_Client.Errors.Ok,
               "expected URI corpus entry to parse: " & Text);
            Assert
              (Http_Client.URI.Request_Target (First_Item)'Length > 0,
               "parsed URI should expose a request target");
            Assert
              (Http_Client.URI.Request_Target (First_Item)
               = Http_Client.URI.Request_Target (Second_Item),
               "parsed URI target should be deterministic");
         else
            Assert
              (First /= Http_Client.Errors.Ok,
               "hostile URI corpus entry should be rejected: " & Text);
         end if;
      end Check_URI;

      Long_Host : constant String (1 .. 4_096) := [others => 'a'];
   begin
      Check_URI ("http://example.test/ok?x=1#fragment", Must_Be_Valid => True);
      Check_URI ("");
      Check_URI ("example.test/path");
      Check_URI ("ftp://example.test/");
      Check_URI ("http://user:pass@example.test/");
      Check_URI ("http://example.test:" & Character'Val (13) & "80/");
      Check_URI ("http://example.test:999999/");
      Check_URI ("http://[::1/");
      Check_URI ("http://example.test/%zz");
      Check_URI ("http://example.test/a b");
      Check_URI ("http://" & Long_Host & ".test/");
      Check_URI ("https://example.test" & Character'Val (0) & "/");
   end Test_Phase37_URI_Security_Corpus;

   procedure Test_Phase37_Header_And_Serialization_Injection_Corpus

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert
        (not Http_Client.Headers.Is_Valid_Name (""),
         "empty header names must be rejected");
      Assert
        (not Http_Client.Headers.Is_Valid_Name ("Bad:Name"),
         "colon-bearing ordinary header names must be rejected");
      Assert
        (not Http_Client.Headers.Is_Valid_Name ("Bad Name"),
         "space-bearing header names must be rejected");
      Assert
        (not Http_Client.Headers.Is_Valid_Value
               ("safe"
                & Character'Val (13)
                & Character'Val (10)
                & "Injected: yes"),
         "CRLF header injection values must be rejected");
      Assert
        (not Http_Client.Headers.Is_Valid_Value
               ("nul" & Character'Val (0) & "byte"),
         "NUL header values must be rejected");

      Status := Http_Client.Headers.Add (Headers, "X-Ok", "safe");
      Assert
        (Status = Http_Client.Errors.Ok,
         "safe header should be accepted before hostile operations");
      Status :=
        Http_Client.Headers.Add
          (Headers, "X-Bad", "safe" & Character'Val (10) & "Injected: yes");
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "injected header value should return Invalid_Header");
      Assert
        (Http_Client.Headers.Length (Headers) = 1,
         "failed hostile insertion must not mutate header collection");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Add (Headers, "Content-Length", "4");
      Assert
        (Status = Http_Client.Errors.Ok,
         "first content-length fixture should insert");
      Status := Http_Client.Headers.Add (Headers, "content-length", "5");
      Assert
        (Status = Http_Client.Errors.Ok,
         "conflicting content-length can be represented before serialization review");
      Status := Http_Client.URI.Parse ("http://example.test/upload", URI);
      Assert
        (Status = Http_Client.Errors.Ok,
         "serialization URI fixture should parse");
      Status :=
        Http_Client.Requests.Create
          (Http_Client.Types.POST, URI, Request, Headers, Payload => "test");
      Assert
        (Status = Http_Client.Errors.Ok,
         "request construction should preserve existing header set for serializer validation");
      Status := Http_Client.HTTP1.Serialize_Request (Request, Output);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "serializer must reject conflicting Content-Length instead of emitting smuggling bytes");
      Assert
        (Ada.Strings.Unbounded.To_String (Output) = "",
         "failed serialization must not leave partial request bytes");
   end Test_Phase37_Header_And_Serialization_Injection_Corpus;

   procedure Test_Phase37_HTTP1_Response_Parser_Corpus

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      procedure Check_Response (Raw : String; Expected_Fail : Boolean := True)
      is
         First_Response  : Http_Client.Responses.Response;
         Second_Response : Http_Client.Responses.Response;
         First           : Http_Client.Errors.Result_Status;
         Second          : Http_Client.Errors.Result_Status;
      begin
         First := Http_Client.Responses.Parse_Response (Raw, First_Response);
         Second := Http_Client.Responses.Parse_Response (Raw, Second_Response);
         Assert
           (First = Second,
            "HTTP/1 response parse status should be deterministic");

         if Expected_Fail then
            Assert
              (First /= Http_Client.Errors.Ok,
               "hostile HTTP/1 response corpus entry should fail");
         else
            Assert
              (First = Http_Client.Errors.Ok,
               "valid HTTP/1 response corpus entry should parse");
            Assert
              (Http_Client.Responses.Response_Body (First_Response)
               = Http_Client.Responses.Response_Body (Second_Response),
               "parsed response body should be deterministic");
         end if;
      end Check_Response;
   begin
      Check_Response
        ("HTTP/1.1 200 OK"
         & Character'Val (13)
         & Character'Val (10)
         & "Content-Length: 2"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10)
         & "ok",
         Expected_Fail => False);
      Check_Response
        ("HTTP/1.1 20 OK" & Character'Val (13) & Character'Val (10));
      Check_Response
        ("HTTP/2 200 OK" & Character'Val (13) & Character'Val (10));
      Check_Response ("HTTP/1.1 200 OK" & Character'Val (10));
      Check_Response
        ("HTTP/1.1 200 OK"
         & Character'Val (13)
         & Character'Val (10)
         & "Bad Header: value"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10));
      Check_Response
        ("HTTP/1.1 200 OK"
         & Character'Val (13)
         & Character'Val (10)
         & "Content-Length: 5"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10)
         & "abc");
      Check_Response
        ("HTTP/1.1 200 OK"
         & Character'Val (13)
         & Character'Val (10)
         & "Content-Length: 1"
         & Character'Val (13)
         & Character'Val (10)
         & "Content-Length: 2"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10)
         & "xx");
      Check_Response
        ("HTTP/1.1 204 No Content"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10)
         & "x");
      Check_Response
        ("HTTP/1.1 200 OK"
         & Character'Val (13)
         & Character'Val (10)
         & "Transfer-Encoding: chunked"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10)
         & "1"
         & Character'Val (13)
         & Character'Val (10)
         & "x"
         & Character'Val (13)
         & Character'Val (10)
         & "0"
         & Character'Val (13)
         & Character'Val (10)
         & Character'Val (13)
         & Character'Val (10));
   end Test_Phase37_HTTP1_Response_Parser_Corpus;

   procedure Test_Phase37_Cookie_Auth_And_Diagnostics_Secrets

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin_HTTP  : Http_Client.URI.URI_Reference;
      Origin_HTTPS : Http_Client.URI.URI_Reference;
      Other_HTTPS  : Http_Client.URI.URI_Reference;
      Cookie       : Http_Client.Cookies.Cookie;
      Jar          : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.URI.Parse
          ("http://example.test/account/path", Origin_HTTP);
      Assert
        (Status = Http_Client.Errors.Ok, "cookie HTTP origin should parse");
      Status :=
        Http_Client.URI.Parse
          ("https://example.test/account/path", Origin_HTTPS);
      Assert
        (Status = Http_Client.Errors.Ok, "cookie HTTPS origin should parse");
      Status :=
        Http_Client.URI.Parse ("https://other.test/account/path", Other_HTTPS);
      Assert
        (Status = Http_Client.Errors.Ok, "cookie other origin should parse");

      Http_Client.Status_Test_Helpers.Assert_Cookie_Parse_Status
        ("sid=secret; Domain=other.test; Path=/",
         Origin_HTTPS,
         Http_Client.Errors.Cookie_Rejected,
         "unrelated Domain cookie must be rejected");
      Http_Client.Status_Test_Helpers.Assert_Cookie_Parse_Status
        ("__Host-sid=secret; Secure; Domain=example.test; Path=/",
         Origin_HTTPS,
         Http_Client.Errors.Cookie_Rejected,
         "__Host- cookies with Domain must be rejected");
      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("sid=secret; Secure; Path=/account", Origin_HTTPS, Cookie);
      Assert
        (Status = Http_Client.Errors.Ok,
         "secure cookie fixture should parse for HTTPS origin");
      Status := Http_Client.Cookies.Add (Jar, Cookie);
      Assert
        (Status = Http_Client.Errors.Ok,
         "secure cookie fixture should be retained");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Origin_HTTP) = "",
         "secure cookie must not be generated for HTTP requests");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Other_HTTPS) = "",
         "cookie must not leak to another origin");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Origin_HTTPS)
         = "sid=secret",
         "cookie should be generated only for matching HTTPS origin/path");

      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token
               ("token" & Character'Val (10) & "Injected: yes"),
         "Bearer token validation must reject CR/LF injection");
      Http_Client.Status_Test_Helpers.Assert_Digest_Challenge_Status
        ("Digest realm=""r"", nonce=""n"", nonce=""duplicate""",
         Http_Client.Errors.Authentication_Challenge_Malformed,
         "duplicate Digest nonce must be rejected deterministically");

      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Http_Client.Diagnostics.Default_Redaction_Policy,
            "Authorization",
            "Bearer top-secret-token")
         /= "Bearer top-secret-token",
         "Authorization must be redacted by default");
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Http_Client.Diagnostics.Default_Redaction_Policy,
            "Cookie",
            "sid=secret")
         /= "sid=secret",
         "Cookie must be redacted by default");
      Assert
        (Http_Client.Diagnostics.Safe_Body_Preview
           (Http_Client.Diagnostics.Default_Redaction_Policy,
            "password=secret")
         = "",
         "body previews must be disabled by default");
   end Test_Phase37_Cookie_Auth_And_Diagnostics_Secrets;

   procedure Test_Phase37_Proxy_SOCKS_And_Storage_Boundary_Corpus

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Output     : Ada.Strings.Unbounded.Unbounded_String;
      Long_Name  : constant String (1 .. 256) := [others => 'a'];

   begin
      declare
         Proxy      : Http_Client.Proxies.Proxy_Config;
         Proxy_With : Http_Client.Proxies.Proxy_Config;
      begin
         Assert
           (Http_Client.Proxies.Parse ("http://proxy.test:8080", Proxy)
            = Http_Client.Errors.Ok,
            "safe HTTP proxy fixture should parse");
         Assert
           (Http_Client.Proxies.With_Proxy_Authorization
              (Proxy,
               "Basic "
               & Character'Val (13)
               & Character'Val (10)
               & "Injected: yes",
               Proxy_With)
            = Http_Client.Errors.Invalid_Header,
            "HTTP proxy authorization must reject CRLF injection");
         Assert
           (not Http_Client.Proxies.Has_Proxy_Authorization (Proxy_With),
            "failed proxy auth helper should not produce proxy credentials");
      end;

      Http_Client.Status_Test_Helpers.Assert_Proxy_Parse_Status
        ("http://user:pass@proxy.test:8080",
         Http_Client.Errors.Invalid_Proxy,
         "proxy URI userinfo must be rejected instead of silently storing credentials");
      Http_Client.Status_Test_Helpers.Assert_Proxy_Parse_Status
        ("https://proxy.test:8443",
         Http_Client.Errors.Proxy_Unsupported,
         "unsupported HTTPS proxy endpoint should fail explicitly");
      Http_Client.Status_Test_Helpers.Assert_Proxy_Parse_Status
        ("socks4://proxy.test:1080",
         Http_Client.Errors.Proxy_Unsupported,
         "SOCKS4 proxy endpoint should fail explicitly");
      Http_Client.Status_Test_Helpers.Assert_Proxy_Parse_Status
        ("socks5://user:pass@proxy.test:1080",
         Http_Client.Errors.Invalid_SOCKS_Proxy,
         "SOCKS URI userinfo must be rejected");

      declare
         Proxy      : Http_Client.Proxies.Proxy_Config;
         Proxy_With : Http_Client.Proxies.Proxy_Config;
      begin
         Assert
           (Http_Client.Proxies.Parse ("socks5h://proxy.test:1080", Proxy)
            = Http_Client.Errors.Ok,
            "safe SOCKS5 proxy fixture should parse");
         declare
            Invalid_Proxy_With : Http_Client.Proxies.Proxy_Config;
         begin
            Assert
              (Http_Client.Proxies.With_SOCKS5_Username_Password
                 (Proxy,
                  "user" & Character'Val (10),
                  "password",
                  Invalid_Proxy_With)
               = Http_Client.Errors.Invalid_Credentials,
               "SOCKS username must reject controls");
            Assert
              (not Http_Client.Proxies.Has_Proxy_Authorization
                     (Invalid_Proxy_With),
               "failed SOCKS auth helper should not produce proxy credentials");
         end;
         Assert
           (Http_Client.Proxies.With_SOCKS5_Username_Password
              (Proxy, "user", "password", Proxy_With)
            = Http_Client.Errors.Ok,
            "safe SOCKS credentials should be accepted for SOCKS negotiation only");
         Assert
           (Http_Client.Proxies.SOCKS.Greeting (Proxy_With, Output)
            = Http_Client.Errors.Ok,
            "SOCKS greeting should serialize for authenticated SOCKS config");
      end;
      Assert
        (Ada.Strings.Unbounded.To_String (Output)'Length = 3,
         "SOCKS greeting should remain a bounded fixed-size prefix");

      Http_Client.Status_Test_Helpers.Assert_SOCKS_Method_Selection_Status
        (Character'Val (4) & Character'Val (0),
         Http_Client.Errors.SOCKS_Unsupported_Version,
         "SOCKS method reply with wrong version should fail deterministically");
      Http_Client.Status_Test_Helpers.Assert_SOCKS_Method_Selection_Status
        (Character'Val (5) & Character'Val (16#FF#),
         Http_Client.Errors.SOCKS_Unsupported_Authentication_Method,
         "SOCKS no-acceptable-methods reply should fail deterministically");
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Username_Password_Reply
           (Character'Val (1) & Character'Val (1))
         = Http_Client.Errors.SOCKS_Authentication_Failed,
         "SOCKS username/password failure should not be accepted");
      Http_Client.Status_Test_Helpers.Assert_SOCKS_Connect_Request_Status
        (Long_Name,
         443,
         Http_Client.Proxies.SOCKS5_Remote_DNS,
         Http_Client.Errors.Invalid_URI,
         "overlong SOCKS domain name should be rejected before serialization");
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
         "SOCKS domain reply with zero-length bound address should be rejected");
   end Test_Phase37_Proxy_SOCKS_And_Storage_Boundary_Corpus;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Security_Corpus");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Phase37_URI_Security_Corpus'Access,
         "Test_Phase37_URI_Security_Corpus");
      Register_Routine
        (T,
         Test_Phase37_Header_And_Serialization_Injection_Corpus'Access,
         "Test_Phase37_Header_And_Serialization_Injection_Corpus");
      Register_Routine
        (T,
         Test_Phase37_HTTP1_Response_Parser_Corpus'Access,
         "Test_Phase37_HTTP1_Response_Parser_Corpus");
      Register_Routine
        (T,
         Test_Phase37_Cookie_Auth_And_Diagnostics_Secrets'Access,
         "Test_Phase37_Cookie_Auth_And_Diagnostics_Secrets");
      Register_Routine
        (T,
         Test_Phase37_Proxy_SOCKS_And_Storage_Boundary_Corpus'Access,
         "Test_Phase37_Proxy_SOCKS_And_Storage_Boundary_Corpus");
   end Register_Tests;

end Http_Client.Security_Corpus.Tests;
