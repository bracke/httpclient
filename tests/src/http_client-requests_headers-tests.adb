with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Auth.Bearer;
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
with Http_Client.Multipart;
with Http_Client.Proxies;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Status_Test_Helpers;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Requests_Headers.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
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

   procedure Test_Auth_Base64_And_Basic_Header

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Buffer : String (1 .. 32) := [others => '?'];
   begin
      Assert
        (Http_Client.Auth.Base64_Encode ("") = "",
         "Base64 empty vector should encode to empty string");
      Assert
        (Http_Client.Auth.Base64_Encode ("f") = "Zg==",
         "Base64 one-octet vector should use two padding characters");
      Assert
        (Http_Client.Auth.Base64_Encode ("fo") = "Zm8=",
         "Base64 two-octet vector should use one padding character");
      Assert
        (Http_Client.Auth.Base64_Encode ("foo") = "Zm9v",
         "Base64 three-octet vector should use no padding");
      Assert
        (Http_Client.Auth.Base64_Encode ("foobar") = "Zm9vYmFy",
         "Base64 six-octet vector should match RFC test vector");

      Assert
        (Http_Client.Auth.Basic_Authorization_Value ("user", "pass")
         = "Basic dXNlcjpwYXNz",
         "Basic helper should encode username colon password exactly");
      Assert
        (Http_Client.Auth.Basic_Authorization_Value ("user", "")
         = "Basic dXNlcjo=",
         "Basic helper should allow an empty password and encode the trailing separator");
      Assert
        (Http_Client.Auth.Basic_Authorization_Value ("user", "p:a:ss")
         = "Basic dXNlcjpwOmE6c3M=",
         "Basic helper should allow colons in passwords");
      Assert
        (Http_Client.Auth.Basic_Proxy_Authorization_Value ("proxy", "secret")
         = "Basic cHJveHk6c2VjcmV0",
         "proxy Basic helper should use the same field value syntax");

      Assert
        (Http_Client.Auth.Basic_Authorization ("user", "pass", Buffer)
         = Http_Client.Errors.Ok,
         "bounded Basic helper should write to a sufficiently large caller buffer");
      Assert
        (Buffer (1 .. 18) = "Basic dXNlcjpwYXNz",
         "bounded Basic helper should place the generated header at the start of the buffer");
   end Test_Auth_Base64_And_Basic_Header;

   procedure Test_Auth_Bearer_Header_And_Request_Helper

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI          : Http_Client.URI.URI_Reference;
      Request      : Http_Client.Requests.Request;
      With_Auth    : Http_Client.Requests.Request;
      Buffer       : String (1 .. 32) := [others => '?'];
      Short_Buffer : String (1 .. 6) := [others => '?'];
      Long_Token   : constant String (1 .. 8_200) := [others => 'x'];
      Proxy        : Http_Client.Proxies.Proxy_Config;
      Auth_Proxy   : Http_Client.Proxies.Proxy_Config;
   begin
      Assert
        (Http_Client.Auth.Bearer.Is_Valid_Token ("opaque.token-123"),
         "ordinary opaque Bearer token should validate");
      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token (""),
         "empty Bearer token should be rejected");
      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token
               ("token" & Character'Val (13)),
         "CR in Bearer token should be rejected");
      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token
               ("token" & Character'Val (0)),
         "NUL in Bearer token should be rejected");
      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token (Long_Token),
         "overlong Bearer tokens should be rejected before header storage");
      Assert
        (Http_Client.Auth.Bearer.Authorization_Value ("opaque.token-123")
         = "Bearer opaque.token-123",
         "Bearer helper should treat token as opaque caller-supplied text");
      Assert
        (Http_Client.Auth.Bearer.Bearer_Authorization
           ("opaque.token-123", Buffer)
         = Http_Client.Errors.Ok,
         "bounded Bearer helper should write to caller buffer");
      Assert
        (Buffer (1 .. 23) = "Bearer opaque.token-123",
         "bounded Bearer helper should place generated value at buffer start");
      Assert
        (Http_Client.Auth.Bearer.Bearer_Authorization
           ("opaque.token-123", Short_Buffer)
         = Http_Client.Errors.Invalid_Header,
         "bounded Bearer helper should reject too-small caller buffers");

      Assert_Parse_Ok
        ("http://example.com/resource",
         URI,
         "Bearer integration URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "Bearer integration request should construct");
      Assert
        (Http_Client.Auth.Bearer.Set_Bearer_Authorization
           (Request, "opaque.token-123", With_Auth)
         = Http_Client.Errors.Ok,
         "Bearer request helper should attach origin Authorization");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Requests.Headers (With_Auth), "Authorization")
         = "Bearer opaque.token-123",
         "Bearer request helper should store exact field value");
      Assert
        (Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy)
         = Http_Client.Errors.Ok,
         "Bearer proxy helper proxy URI should parse");
      Http_Client.Status_Test_Helpers.Assert_Bearer_Proxy_Authorization_Status
        (Http_Client.Proxies.No_Proxy_Config,
         "proxy-token",
         Http_Client.Errors.Invalid_Proxy,
         "Bearer proxy helper must not attach proxy credentials to No_Proxy_Config");
      Assert
        (Http_Client.Auth.Bearer.Set_Bearer_Proxy_Authorization
           (Proxy, "proxy-token", Auth_Proxy)
         = Http_Client.Errors.Ok,
         "Bearer proxy helper should attach proxy-only credentials");
      Assert
        (Http_Client.Proxies.Proxy_Authorization (Auth_Proxy)
         = "Bearer proxy-token",
         "Bearer proxy helper should produce Proxy-Authorization field value only");
   end Test_Auth_Bearer_Header_And_Request_Helper;

   procedure Test_Header_List

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Assert
        (Http_Client.Headers.Length (Headers) = 0,
         "new header list should be empty");

      Assert
        (Http_Client.Headers.Is_Valid_Name ("Accept"),
         "simple header name should be valid");

      Assert
        (Http_Client.Headers.Is_Valid_Name ("X-Test!#$%&'*+-.^_`|~9"),
         "token punctuation should be accepted in header names");

      Assert
        (not Http_Client.Headers.Is_Valid_Name (""),
         "empty header name should be rejected");

      Assert
        (not Http_Client.Headers.Is_Valid_Name ("Bad Name"),
         "spaces should be rejected in header names");

      Assert
        (not Http_Client.Headers.Is_Valid_Name ("Bad:Name"),
         "colons should be rejected in header names");

      Assert
        (not Http_Client.Headers.Is_Valid_Name
               ("Bad" & Character'Val (9) & "Name"),
         "tabs should be rejected in header names");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, Name => "Accept", Value => "*/*"),
         "adding a valid header should succeed");

      Assert
        (Http_Client.Headers.Length (Headers) = 1,
         "adding one header should increase total count to one");

      Assert
        (Http_Client.Headers.Contains (Headers, "accept"),
         "header lookup should be case-insensitive");

      Assert
        (Http_Client.Headers.Get (Headers, "ACCEPT") = "*/*",
         "case-insensitive get should return the first value");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, Name => "ACCEPT", Value => "application/json"),
         "adding duplicate header field should succeed");

      Assert
        (Http_Client.Headers.Length (Headers) = 2,
         "duplicate add should preserve both fields");

      Assert
        (Http_Client.Headers.Count (Headers, "Accept") = 2,
         "duplicate add should be counted by case-insensitive name");

      Assert
        (Http_Client.Headers.Get (Headers, "Accept") = "*/*",
         "get should return first duplicate value deterministically");

      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers, Name => "accept", Value => "text/plain"),
         "set should replace all duplicates");

      Assert
        (Http_Client.Headers.Length (Headers) = 1,
         "set should collapse duplicate fields to one field");

      Assert
        (Http_Client.Headers.Count (Headers, "ACCEPT") = 1,
         "set should leave exactly one matching field");

      Assert
        (Http_Client.Headers.Get (Headers, "Accept") = "text/plain",
         "set should store replacement value");

      Assert
        (Http_Client.Headers.Set (Headers, Name => "Bad:Name", Value => "x")
         = Http_Client.Errors.Invalid_Header,
         "invalid header name should be rejected by Set");

      Assert
        (Http_Client.Headers.Length (Headers) = 1
         and then Http_Client.Headers.Get (Headers, "Accept") = "text/plain",
         "failed Set should not mutate existing fields");

      Assert
        (Http_Client.Headers.Add (Headers, Name => "Bad Name", Value => "x")
         = Http_Client.Errors.Invalid_Header,
         "invalid header name should be rejected by Add");

      Assert
        (Http_Client.Headers.Length (Headers) = 1,
         "failed Add should not append a field");

      Assert
        (Http_Client.Headers.Add
           (Headers,
            Name  => "X-Test",
            Value => "line" & Character'Val (10) & "break")
         = Http_Client.Errors.Invalid_Header,
         "LF in header value should be rejected");

      Assert
        (Http_Client.Headers.Add
           (Headers,
            Name  => "X-Test",
            Value => "line" & Character'Val (13) & "break")
         = Http_Client.Errors.Invalid_Header,
         "CR in header value should be rejected");

      Assert
        (Http_Client.Headers.Add
           (Headers, Name => "X-Test", Value => "bad" & Character'Val (0))
         = Http_Client.Errors.Invalid_Header,
         "NUL in header value should be rejected");

      Assert
        (Http_Client.Headers.Add
           (Headers, Name => "X-Test", Value => "bad" & Character'Val (9))
         = Http_Client.Errors.Invalid_Header,
         "horizontal tab in header value should be rejected explicitly");

      Assert
        (Http_Client.Headers.Add
           (Headers, Name => "X-Test", Value => "bad" & Character'Val (128))
         = Http_Client.Errors.Invalid_Header,
         "C1 control characters in header values should be rejected");

      Assert
        (Http_Client.Headers.Length (Headers) = 1,
         "failed value validation should not append fields");

      Assert
        (Http_Client.Headers.Remove (Headers, "Bad Name")
         = Http_Client.Errors.Invalid_Header,
         "remove should reject invalid header names");

      Assert_Header_Status
        (Http_Client.Headers.Remove (Headers, "ACCEPT"),
         "remove should accept valid case-insensitive name");

      Assert
        (Http_Client.Headers.Length (Headers) = 0,
         "remove should delete matching header fields");

      Http_Client.Headers.Clear (Headers);

      Assert
        (Http_Client.Headers.Length (Headers) = 0,
         "clearing headers should restore empty header list");
   end Test_Header_List;

   procedure Test_Header_Iteration_Order

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "A", "1"),
         "adding first ordered header should succeed");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "B", "2"),
         "adding second ordered header should succeed");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "A", "3"),
         "adding duplicate ordered header should succeed");

      Assert
        (Http_Client.Headers.Name_At (Headers, 1) = "A"
         and then Http_Client.Headers.Value_At (Headers, 1) = "1",
         "first header should retain insertion order");

      Assert
        (Http_Client.Headers.Name_At (Headers, 2) = "B"
         and then Http_Client.Headers.Value_At (Headers, 2) = "2",
         "second header should retain insertion order");

      Assert
        (Http_Client.Headers.Name_At (Headers, 3) = "A"
         and then Http_Client.Headers.Value_At (Headers, 3) = "3",
         "duplicate header should retain insertion order");
   end Test_Header_Iteration_Order;

   procedure Test_Default_Request

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      use Http_Client.Types;

      Request : Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
   begin
      Assert
        (not Http_Client.Requests.Is_Valid (Request),
         "default request should not be a validated outbound request");

      Assert
        (Http_Client.Requests.Method (Request) = GET,
         "default request should use GET");

      Assert
        (Http_Client.Requests.Target_Text (Request) = "",
         "default request target should be empty");

      Assert
        (Http_Client.Headers.Length (Http_Client.Requests.Headers (Request))
         = 0,
         "default request should have no headers");

      Http_Client.Requests.Set_Target (Request, "http://example.invalid/");

      Assert
        (Http_Client.Requests.Target_Text (Request)
         = "http://example.invalid/",
         "Set_Target should preserve legacy target text");
   end Test_Default_Request;

   procedure Test_Request_Construction

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List;
   begin
      Assert_Parse_Ok
        ("https://example.com/a/b?x=1", URI, "request construction URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "GET request construction should succeed for parsed URI");

      Assert
        (Http_Client.Requests.Is_Valid (Request),
         "constructed request should be valid");

      Assert
        (Http_Client.Requests.Method (Request) = Http_Client.Types.GET,
         "constructed request should preserve method");

      Headers := Http_Client.Requests.Headers (Request);

      Assert
        (Http_Client.Headers.Contains (Headers, "host"),
         "request construction should add Host by default");

      Assert
        (Http_Client.Headers.Get (Headers, "Host") = "example.com",
         "default HTTPS port should be omitted from Host header");

      Assert
        (Http_Client.Requests.Request_Target (Request) = "/a/b?x=1",
         "request target should be path plus query");

      Assert
        (Http_Client.Requests.Host_Header_Value (Request) = "example.com",
         "host helper should match URI host header helper");
   end Test_Request_Construction;

   procedure Test_Request_Default_Port_And_Empty_Query

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List;
   begin
      Assert_Parse_Ok
        ("http://example.com:80/path?",
         URI,
         "request URI with explicit default port and empty query");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "request with explicit default port should construct successfully");

      Headers := Http_Client.Requests.Headers (Request);

      Assert
        (Http_Client.Headers.Get (Headers, "Host") = "example.com",
         "explicit default HTTP port should be omitted from Host header");

      Assert
        (Http_Client.Requests.Request_Target (Request) = "/path?",
         "request target should preserve explicit empty query");
   end Test_Request_Default_Port_And_Empty_Query;

   procedure Test_Request_Post_Payload_And_Explicit_Host

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI            : Http_Client.URI.URI_Reference;
      Request        : Http_Client.Requests.Request;
      Headers        : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Result_Headers : Http_Client.Headers.Header_List;
   begin
      Assert_Parse_Ok
        ("http://example.com:8080/upload",
         URI,
         "POST request URI with explicit non-default port");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Host", "caller.example"),
         "explicit caller Host should be valid");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "POST request with payload should construct successfully");

      Result_Headers := Http_Client.Requests.Headers (Request);

      Assert
        (Http_Client.Headers.Get (Result_Headers, "Host") = "caller.example",
         "explicit caller Host header should not be overwritten");

      Assert
        (Http_Client.Requests.Host_Header_Value (Request) = "example.com:8080",
         "host helper should include explicit non-default port");

      Assert
        (Http_Client.Requests.Payload (Request) = "payload",
         "POST payload should be stored verbatim");

      Assert
        (Http_Client.Requests.Has_Payload (Request),
         "non-empty payload should be reported");

      Assert
        (Http_Client.Requests.Set_Payload (Request, "changed")
         = Http_Client.Errors.Ok,
         "payload replacement should succeed on valid request");

      Assert
        (Http_Client.Requests.Payload (Request) = "changed",
         "payload replacement should update stored payload");
   end Test_Request_Post_Payload_And_Explicit_Host;

   procedure Test_Request_Auto_Host_Disabled

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List;
   begin
      Assert_Parse_Ok
        ("https://example.com/no-host",
         URI,
         "request URI for disabled automatic Host");

      Assert
        (Http_Client.Requests.Create
           (Method    => Http_Client.Types.OPTIONS,
            URI       => URI,
            Item      => Request,
            Auto_Host => False)
         = Http_Client.Errors.Ok,
         "request construction should allow Auto_Host to be disabled");

      Headers := Http_Client.Requests.Headers (Request);

      Assert
        (not Http_Client.Headers.Contains (Headers, "Host"),
         "Auto_Host disabled should leave Host absent");

      Assert
        (Http_Client.Requests.Host_Header_Value (Request) = "example.com",
         "host helper should still compute the URI-derived Host value");
   end Test_Request_Auto_Host_Disabled;

   procedure Test_Request_Method_Image_And_Invalid_URI

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Request : Http_Client.Requests.Request;
      URI     : constant Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("http://example.com/");
   begin
      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.GET) = "GET",
         "GET method should render as GET");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.HEAD) = "HEAD",
         "HEAD method should render as HEAD");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.POST) = "POST",
         "POST method should render as POST");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.PUT) = "PUT",
         "PUT method should render as PUT");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.PATCH) = "PATCH",
         "PATCH method should render as PATCH");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.DELETE)
         = "DELETE",
         "DELETE method should render as DELETE");

      Assert
        (Http_Client.Requests.Method_Image (Http_Client.Types.OPTIONS)
         = "OPTIONS",
         "OPTIONS method should render as OPTIONS");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Invalid_URI,
         "request construction should reject unchecked URI values");

      Assert
        (Http_Client.Requests.Set_Payload (Request, "x")
         = Http_Client.Errors.Invalid_Request,
         "payload replacement should reject invalid default request values");
   end Test_Request_Method_Image_And_Invalid_URI;

   procedure Test_HTTP1_Host_Header_Ports

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Http_URI       : Http_Client.URI.URI_Reference;
      Https_URI      : Http_Client.URI.URI_Reference;
      Nondefault_URI : Http_Client.URI.URI_Reference;
      Request        : Http_Client.Requests.Request;
      CRLF           : constant String :=
        Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com:80/a",
         Http_URI,
         "HTTP URI with explicit default port for serialization");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => Http_URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTP default-port request should construct");
      Assert_Serialize_Ok
        (Request,
         "GET /a HTTP/1.1" & CRLF & "Host: example.com" & CRLF & CRLF,
         "HTTP default port should be omitted from Host");

      Assert_Parse_Ok
        ("https://example.com:443/a",
         Https_URI,
         "HTTPS URI with explicit default port for serialization");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => Https_URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS default-port request should construct");
      Assert_Serialize_Ok
        (Request,
         "GET /a HTTP/1.1" & CRLF & "Host: example.com" & CRLF & CRLF,
         "HTTPS default port should be omitted from Host");

      Assert_Parse_Ok
        ("https://example.com:8443/a",
         Nondefault_URI,
         "HTTPS URI with non-default port for serialization");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => Nondefault_URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "HTTPS non-default-port request should construct");
      Assert_Serialize_Ok
        (Request,
         "GET /a HTTP/1.1" & CRLF & "Host: example.com:8443" & CRLF & CRLF,
         "HTTPS non-default port should be included in Host");
   end Test_HTTP1_Host_Header_Ports;

   procedure Test_HTTP1_Response_Parse_Header_Whitespace_And_Binary_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF             : constant String :=
        Character'Val (13) & Character'Val (10);
      Response         : Http_Client.Responses.Response;
      Status           : Http_Client.Errors.Result_Status;
      Headers          : Http_Client.Headers.Header_List;
      Response_Content : constant String :=
        "A" & Character'Val (0) & Character'Val (255) & "Z";
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & CRLF
           & "X-Trim: "
           & Character'Val (9)
           & " value "
           & Character'Val (9)
           & CRLF
           & "Content-Length: 4"
           & CRLF
           & CRLF
           & Response_Content,
           Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "response parser should accept binary body bytes with fixed length");

      Headers := Http_Client.Responses.Headers (Response);

      Assert
        (Http_Client.Headers.Get (Headers, "x-trim") = "value",
         "response header optional whitespace should be stripped");

      Assert
        (Http_Client.Responses.Response_Body (Response) = Response_Content,
         "binary response body bytes should be preserved exactly");
   end Test_HTTP1_Response_Parse_Header_Whitespace_And_Binary_Body;

   procedure Test_HTTP1_Response_Parse_Invalid_Headers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);

   begin
      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK" & CRLF & "Bad Name: x" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "invalid response header name should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK"
         & CRLF
         & "X-Test: ok"
         & CRLF
         & " folded"
         & CRLF
         & CRLF,
         Http_Client.Errors.Unsupported_Feature,
         "obsolete folded response header line should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Content-Length: 0"
         & CRLF
         & "Content-Length: 0"
         & CRLF
         & CRLF,
         Http_Client.Errors.Invalid_Header,
         "duplicate Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length: abc" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "non-numeric Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length: -1" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "negative Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length:" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "empty Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 1 2" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "internally whitespace-malformed Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Content-Length: 999999999999999999999999999999"
         & CRLF
         & CRLF,
         Http_Client.Errors.Invalid_Header,
         "overflowing Content-Length should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK"
         & CRLF
         & "X-Test: bad"
         & Character'Val (13)
         & "value"
         & CRLF
         & CRLF,
         Http_Client.Errors.Protocol_Error,
         "embedded CR in a header value should be rejected");

      Http_Client.Status_Test_Helpers.Assert_Response_Parse_Status
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Transfer-Encoding: chunked"
         & CRLF
         & CRLF,
         Http_Client.Errors.Unsupported_Feature,
         "buffered response parser rejects raw Transfer-Encoding metadata");
   end Test_HTTP1_Response_Parse_Invalid_Headers;

   procedure Test_HTTP1_Fixed_Length_Stream_Headers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      type Test_Producer is new Http_Client.Request_Bodies.Body_Producer
      with record
         Done : Boolean := False;
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
         return Http_Client.Errors.Result_Status is
      begin
         if Item.Done then
            Count := 0;
         else
            Buffer (Buffer'First .. Buffer'First + 2) := "abc";
            Count := 3;
            Item.Done := True;
         end if;

         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Test_Producer) return Http_Client.Errors.Result_Status
      is
      begin
         Item.Done := False;
         return Http_Client.Errors.Ok;
      end Reset;

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : constant Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
      P       : aliased Test_Producer;
   begin
      Assert_Parse_Ok
        ("http://example.com/upload", URI, "upload URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "streaming request construction should succeed");
      Assert
        (Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Fixed_Length_Stream
              (P'Unchecked_Access,
               3,
               Replayable => True))
         = Http_Client.Errors.Ok,
         "fixed-length stream body should attach to request");
      Assert
        (Http_Client.HTTP1.Serialize_Headers (Request, Output)
         = Http_Client.Errors.Ok,
         "fixed-length stream headers should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Output)
         = "POST /upload HTTP/1.1"
           & Character'Val (13)
           & Character'Val (10)
           & "Host: example.com"
           & Character'Val (13)
           & Character'Val (10)
           & "Content-Length: 3"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10),
         "fixed-length stream should synthesize exact Content-Length");
   end Test_HTTP1_Fixed_Length_Stream_Headers;

   procedure Test_HTTP1_Unknown_Length_Stream_Chunked_Headers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      type Test_Producer is new Http_Client.Request_Bodies.Body_Producer
      with null record;

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
         pragma Unreferenced (Item, Buffer);
      begin
         Count := 0;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Test_Producer) return Http_Client.Errors.Result_Status
      is
         pragma Unreferenced (Item);
      begin
         return Http_Client.Errors.Body_Not_Replayable;
      end Reset;

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
      P       : aliased Test_Producer;
   begin
      Assert_Parse_Ok
        ("http://example.com/upload", URI, "upload URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.POST, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "unknown-length request construction should succeed");
      Assert
        (Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream
              (P'Unchecked_Access))
         = Http_Client.Errors.Ok,
         "unknown-length stream body should attach to request");
      Assert
        (Http_Client.HTTP1.Serialize_Headers (Request, Output)
         = Http_Client.Errors.Ok,
         "unknown-length streams should serialize with chunked upload framing");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "Transfer-Encoding: chunked") > 0,
         "unknown-length streams should synthesize Transfer-Encoding: chunked");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "Content-Length:") = 0,
         "chunked request uploads must not synthesize Content-Length");
   end Test_HTTP1_Unknown_Length_Stream_Chunked_Headers;

   procedure Test_HTTP1_Chunked_Upload_Header_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      type Test_Producer is new Http_Client.Request_Bodies.Body_Producer
      with null record;

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
         pragma Unreferenced (Item, Buffer);
      begin
         Count := 0;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Test_Producer) return Http_Client.Errors.Result_Status
      is
         pragma Unreferenced (Item);
      begin
         return Http_Client.Errors.Body_Not_Replayable;
      end Reset;

      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Headers  : Http_Client.Headers.Header_List;
      Output   : Ada.Strings.Unbounded.Unbounded_String;
      Producer : aliased Test_Producer;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("http://example.com/upload", URI, "chunked validation URI should parse");

      Status := Http_Client.Headers.Set (Headers, "Transfer-Encoding", "chunked");
      Assert (Status = Http_Client.Errors.Ok, "explicit chunked TE header should be accepted");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.POST,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
      Assert (Status = Http_Client.Errors.Ok, "explicit chunked request should construct");
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream
           (Producer'Unchecked_Access));
      Assert (Status = Http_Client.Errors.Ok, "explicit chunked body should attach");
      Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
      Assert (Status = Http_Client.Errors.Ok, "explicit chunked TE should serialize");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "Transfer-Encoding: chunked") > 0,
         "explicit chunked TE should be preserved");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "Content-Length:") = 0,
         "explicit chunked TE must not synthesize Content-Length");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Set (Headers, "Transfer-Encoding", "gzip");
      Assert (Status = Http_Client.Errors.Ok, "unsupported TE header should store before serialization");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.POST,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
      Assert (Status = Http_Client.Errors.Ok, "unsupported TE request should construct");
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream
           (Producer'Unchecked_Access));
      Assert (Status = Http_Client.Errors.Ok, "unsupported TE body should attach");
      Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "unsupported request Transfer-Encoding must fail deterministically");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Set (Headers, "Transfer-Encoding", "chunked");
      Assert (Status = Http_Client.Errors.Ok, "conflict TE header should store");
      Status := Http_Client.Headers.Set (Headers, "Content-Length", "4");
      Assert (Status = Http_Client.Errors.Ok, "conflict CL header should store");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.POST,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
      Assert (Status = Http_Client.Errors.Ok, "conflicting framing request should construct");
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream
           (Producer'Unchecked_Access));
      Assert (Status = Http_Client.Errors.Ok, "conflicting framing body should attach");
      Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
      Assert
        (Status = Http_Client.Errors.Protocol_Error,
         "Content-Length plus Transfer-Encoding must be rejected");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Set (Headers, "Expect", "100-continue");
      Assert (Status = Http_Client.Errors.Ok, "Expect 100-continue header should store");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.POST,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
      Assert (Status = Http_Client.Errors.Ok, "Expect request should construct");
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream
           (Producer'Unchecked_Access));
      Assert (Status = Http_Client.Errors.Ok, "Expect body should attach");
      Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
      Assert
        (Status = Http_Client.Errors.Ok,
         "Expect: 100-continue should be a supported explicit upload header");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Set (Headers, "Expect", "something-else");
      Assert (Status = Http_Client.Errors.Ok, "unsupported Expect value should store");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.POST,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
      Assert (Status = Http_Client.Errors.Ok, "unsupported Expect request should construct");
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream
           (Producer'Unchecked_Access));
      Assert (Status = Http_Client.Errors.Ok, "unsupported Expect body should attach");
      Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "unsupported Expect values must fail deterministically");

      Headers := Http_Client.Headers.Empty;
      declare
         Trailer_Fields : Http_Client.Headers.Header_List :=
           Http_Client.Headers.Empty;
      begin
         Status := Http_Client.Headers.Set (Trailer_Fields, "X-Git-SHA256", "abc");
         Assert (Status = Http_Client.Errors.Ok, "request trailer should store");
         Status := Http_Client.Requests.Create
           (Method => Http_Client.Types.POST, URI => URI, Item => Request);
         Assert (Status = Http_Client.Errors.Ok, "trailer request should construct");
         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
              (Producer => Producer'Unchecked_Access,
               Trailers => Trailer_Fields));
         Assert (Status = Http_Client.Errors.Ok, "trailer body should attach");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert (Status = Http_Client.Errors.Ok, "chunked trailer headers should serialize");
         Assert
           (Ada.Strings.Fixed.Index
              (Ada.Strings.Unbounded.To_String (Output),
               "Transfer-Encoding: chunked") > 0,
            "trailer upload should synthesize chunked transfer coding");
         Assert
           (Ada.Strings.Fixed.Index
              (Ada.Strings.Unbounded.To_String (Output),
               "Trailer: X-Git-SHA256") > 0,
            "trailer upload should synthesize Trailer declaration");

         Headers := Http_Client.Headers.Empty;
         Status := Http_Client.Headers.Set
           (Headers, "Trailer", "X-Git-SHA256, X-Extra");
         Assert (Status = Http_Client.Errors.Ok,
                 "explicit covering Trailer declaration should store");
         Status := Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers);
         Assert (Status = Http_Client.Errors.Ok,
                 "explicit trailer declaration request should construct");
         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
              (Producer => Producer'Unchecked_Access,
               Trailers => Trailer_Fields));
         Assert (Status = Http_Client.Errors.Ok,
                 "explicit trailer declaration body should attach");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert
           (Status = Http_Client.Errors.Ok,
            "explicit Trailer declaration that covers all attached trailers should serialize");

         Headers := Http_Client.Headers.Empty;
         Status := Http_Client.Headers.Set (Headers, "Trailer", "X-Other");
         Assert (Status = Http_Client.Errors.Ok,
                 "incomplete Trailer declaration should store before serialization");
         Status := Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers);
         Assert (Status = Http_Client.Errors.Ok,
                 "incomplete trailer declaration request should construct");
         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
              (Producer => Producer'Unchecked_Access,
               Trailers => Trailer_Fields));
         Assert (Status = Http_Client.Errors.Ok,
                 "incomplete trailer declaration body should attach");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert
           (Status = Http_Client.Errors.Invalid_Header,
            "explicit Trailer declaration must cover all attached trailer fields");

         Headers := Http_Client.Headers.Empty;
         Status := Http_Client.Headers.Set (Headers, "Trailer", "X-Git-SHA256");
         Assert (Status = Http_Client.Errors.Ok,
                 "orphan Trailer declaration should store before serialization");
         Status := Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers);
         Assert (Status = Http_Client.Errors.Ok,
                 "orphan trailer declaration request should construct");
         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream
              (Producer => Producer'Unchecked_Access));
         Assert (Status = Http_Client.Errors.Ok,
                 "orphan trailer declaration body should attach");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert
           (Status = Http_Client.Errors.Protocol_Error,
            "Trailer header without attached request trailers must be rejected");

         Headers := Http_Client.Headers.Empty;

         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.With_Trailers
              (Http_Client.Request_Bodies.From_Fixed_Length_Stream
                 (Producer => Producer'Unchecked_Access, Length => 4),
               Trailer_Fields));
         Assert (Status = Http_Client.Errors.Ok, "fixed trailer body should attach before serialization");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert
           (Status = Http_Client.Errors.Protocol_Error,
            "request trailers on fixed-length bodies must be rejected");

         Trailer_Fields := Http_Client.Headers.Empty;
         Status := Http_Client.Headers.Set (Trailer_Fields, "Content-Length", "4");
         Assert (Status = Http_Client.Errors.Ok, "forbidden trailer name should store before serialization");
         Status := Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
              (Producer => Producer'Unchecked_Access,
               Trailers => Trailer_Fields));
         Assert (Status = Http_Client.Errors.Ok, "forbidden trailer body should attach");
         Status := Http_Client.HTTP1.Serialize_Headers (Request, Output);
         Assert
           (Status = Http_Client.Errors.Invalid_Header,
            "forbidden request trailer names must be rejected");
      end;
   end Test_HTTP1_Chunked_Upload_Header_Validation;

   procedure Test_Client_Cookie_Explicit_Header_Conflict_Loopback

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Conflict_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Conflict_Server;

      task body Conflict_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         First_Text  : Unbounded_String;
         Second_Text : Unbounded_String;

         procedure Receive_Request (Text : out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            Text := Null_Unbounded_String;
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end Receive_Request;

         procedure Send_OK is
            Text : constant String :=
              "HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF;
            Raw  :
              Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_OK;
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
         Receive_Request (First_Text);
         Send_OK;
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Text);
         Send_OK;
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Text;
            Second := Second_Text;
         end Requests_Seen;
      end Conflict_Server;

      Server      : Conflict_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Response    : Http_Client.Responses.Response;
      Jar         : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Cookie      : Http_Client.Cookies.Cookie;
      Options     : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/page",
         URI,
         "cookie conflict URI should parse");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("jar=auto; Path=/app", URI, Cookie)
         = Http_Client.Errors.Ok,
         "jar cookie should parse for conflict test");
      Assert
        (Http_Client.Cookies.Add (Jar, Cookie) = Http_Client.Errors.Ok,
         "jar cookie should be seeded for conflict test");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Cookie", "manual=yes"),
         "explicit Cookie header should be accepted");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "explicit-cookie request should construct");

      Options.Cookie_Jar := Jar'Unchecked_Access;
      Options.Merge_Jar_Cookies := False;
      Assert
        (Http_Client.Clients.Execute_Once (Request, Response, Options)
         = Http_Client.Errors.Ok,
         "explicit-cookie request without merge should execute");

      Options.Merge_Jar_Cookies := True;
      Assert
        (Http_Client.Clients.Execute_Once (Request, Response, Options)
         = Http_Client.Errors.Ok,
         "explicit-cookie request with merge should execute");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "Cookie: manual=yes") > 0,
         "explicit Cookie header should win when merging is disabled");
      Assert
        (Index (First_Text, "jar=auto") = 0,
         "jar cookie should not be silently duplicated when merging is disabled");
      Assert
        (Index (Second_Text, "Cookie: manual=yes; jar=auto") > 0,
         "merge option should produce one deterministic combined Cookie header");
   end Test_Client_Cookie_Explicit_Header_Conflict_Loopback;

   procedure Test_High_Level_Client_Default_Header_Policy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Set_Default_Header (Config, "X-Default", "yes");

      Assert
        (Status = Http_Client.Errors.Ok,
         "ordinary default headers should be accepted");

      Assert
        (Http_Client.Headers.Contains (Config.Default_Headers, "X-Default"),
         "accepted default header should be stored in configuration");

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "Authorization", "Basic abc");

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "Authorization must not be accepted as a broad default header");

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "Proxy-Authorization", "Basic abc");

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "Proxy-Authorization must not be accepted as a broad default header");

      Status :=
        Http_Client.Clients.Set_Default_Header (Config, "Cookie", "a=b");

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "Cookie must not be accepted as a broad default header");

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "Proxy-Connection", "keep-alive");

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "Proxy-Connection must not be accepted as a broad default header");
   end Test_High_Level_Client_Default_Header_Policy;

   procedure Test_High_Level_Client_Default_Header_Validation_Bypass

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Headers.Set
          (Config.Default_Headers, "Host", "example.com");

      Assert
        (Status = Http_Client.Errors.Ok,
         "test setup should be able to place Host directly in public header list");

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "Validate should reject forbidden default headers even if caller bypassed helper");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Status :=
        Http_Client.Headers.Set
          (Config.Default_Headers, "Content-Length", "123");

      Assert
        (Status = Http_Client.Errors.Ok,
         "test setup should be able to place Content-Length directly in public header list");

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "Validate should reject framing default headers inserted directly");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Status :=
        Http_Client.Headers.Set
          (Config.Default_Headers, "Connection", "keep-alive");

      Assert
        (Status = Http_Client.Errors.Ok,
         "test setup should be able to place Connection directly in public header list");

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "Validate should reject hop-by-hop default headers inserted directly");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Status :=
        Http_Client.Headers.Set
          (Config.Default_Headers, "Proxy-Connection", "keep-alive");

      Assert
        (Status = Http_Client.Errors.Ok,
         "test setup should be able to place Proxy-Connection directly in public header list");

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "Validate should reject non-standard proxy hop-by-hop defaults inserted directly");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Status :=
        Http_Client.Clients.Set_Default_Header (Config, "Bad Header", "x");

      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid default header names should remain header-validation errors");

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "X-Bad-Value", "bad" & Character'Val (10));

      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid default header values should remain header-validation errors");
   end Test_High_Level_Client_Default_Header_Validation_Bypass;

   procedure Test_High_Level_Client_Default_Header_Remove_And_Result_Reset

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Result : Http_Client.Clients.Client_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Set_Default_Header (Config, "X-Temporary", "yes");

      Assert
        (Status = Http_Client.Errors.Ok,
         "temporary default header should be accepted before remove test");

      Status :=
        Http_Client.Clients.Remove_Default_Header (Config, "x-temporary");

      Assert
        (Status = Http_Client.Errors.Ok,
         "removing default header should be case-insensitive and succeed");

      Assert
        (not Http_Client.Headers.Contains
               (Config.Default_Headers, "X-Temporary"),
         "removed default header should not remain in configuration");

      Assert
        (Http_Client.Clients.Validate (Config) = Http_Client.Errors.Ok,
         "configuration should remain valid after removing a default header");

      Status := Http_Client.Clients.Get (Client, "not-a-url", Result);

      Assert
        (Status = Http_Client.Errors.Invalid_URI,
         "invalid convenience URL should still fail deterministically in result reset test");

      Assert
        (Result.Redirect_Count = 0
         and then Result.Retry_Attempt_Count = 0
         and then not Result.Retry_Exhausted
         and then not Result.Used_Decoded_View,
         "failed high-level convenience execution should leave neutral metadata");

      Assert
        (Http_Client.URI.Image (Result.Final_URI) = "",
         "failed high-level convenience execution should leave empty final URI");
   end Test_High_Level_Client_Default_Header_Remove_And_Result_Reset;

   procedure Test_High_Level_Client_Post_Default_Header_Loopback

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

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
            Raw  :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response_Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response_Text
                         (Response_Text'First + Natural (Index - Raw'First))));
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
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client        : Http_Client.Clients.Client;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert
        (Http_Client.Clients.Set_Default_Header
           (Config, "X-Default", "configured")
         = Http_Client.Errors.Ok,
         "ordinary high-level default header should be configurable");

      Assert
        (Http_Client.Clients.Set_Default_Header
           (Config, "Content-Type", "text/plain")
         = Http_Client.Errors.Ok,
         "non-sensitive content type may be a default header");

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level client should initialize with default headers");

      Status :=
        Http_Client.Clients.Post
          (Item         => Client,
           URL          =>
             "http://127.0.0.1:" & To_String (Port_Text) & "/submit",
           Payload      => "abc",
           Result       => Result,
           Content_Type => "application/json");

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level POST convenience execution should succeed against loopback server");

      Assert
        (Http_Client.Responses.Response_Body (Result.Response) = "OK",
         "high-level result should expose parsed response body");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "POST /submit HTTP/1.1") = 1,
         "high-level POST should serialize origin-form request target");

      Assert
        (Index (Captured_Text, "X-Default: configured" & CRLF) > 0,
         "high-level client should apply configured default headers");

      Assert
        (Index (Captured_Text, "Content-Type: application/json" & CRLF) > 0,
         "request-specific POST content type should override configured default content type");

      Assert
        (Index (Captured_Text, "Content-Type: text/plain" & CRLF) = 0,
         "default Content-Type must not overwrite request-specific Content-Type");

      Assert
        (Index (Captured_Text, "Content-Length: 3" & CRLF) > 0,
         "high-level POST should preserve deterministic Content-Length synthesis");

      Assert
        (Index (Captured_Text, CRLF & CRLF & "abc") > 0,
         "high-level POST should send the supplied payload bytes");
   end Test_High_Level_Client_Post_Default_Header_Loopback;

   procedure Test_High_Level_Client_Chunked_Upload_Loopback

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      type Chunked_Producer is new Http_Client.Request_Bodies.Body_Producer with record
         Data   : String (1 .. 6) :=
           "AB" & Character'Val (0) & Character'Val (255) & "CD";
         Cursor : Natural := 1;
      end record;

      overriding
      function Read_Some
        (Item   : in out Chunked_Producer;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status;

      overriding
      function Reset
        (Item : in out Chunked_Producer) return Http_Client.Errors.Result_Status;

      overriding
      function Read_Some
        (Item   : in out Chunked_Producer;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status
      is
         Take : Natural := 0;
      begin
         Count := 0;
         if Item.Cursor > Item.Data'Last then
            return Http_Client.Errors.Ok;
         end if;
         Take := Natural'Min
           (Natural'Min (Buffer'Length, 2), Item.Data'Last - Item.Cursor + 1);
         Buffer (Buffer'First .. Buffer'First + Take - 1) :=
           Item.Data (Item.Cursor .. Item.Cursor + Take - 1);
         Item.Cursor := Item.Cursor + Take;
         Count := Take;
         return Http_Client.Errors.Ok;
      end Read_Some;

      overriding
      function Reset
        (Item : in out Chunked_Producer) return Http_Client.Errors.Result_Status is
      begin
         Item.Cursor := Item.Data'First;
         return Http_Client.Errors.Ok;
      end Reset;

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

         loop
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

            exit when Index (Request_Text, "0" & CRLF & "X-Git-SHA256: abc" & CRLF & CRLF) > 0;
         end loop;

         declare
            Raw  :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response_Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response_Text
                         (Response_Text'First + Natural (Index - Raw'First))));
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
      Producer      : aliased Chunked_Producer;
      Port          : Http_Client.URI.TCP_Port;
      Port_Text     : Unbounded_String;
      Client        : Http_Client.Clients.Client;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Trailer_Fields : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Status := Http_Client.Clients.Initialize
        (Client, Http_Client.Clients.Default_Client_Configuration);
      Assert (Status = Http_Client.Errors.Ok, "client initialization should succeed");

      Status := Http_Client.URI.Parse
        ("http://127.0.0.1:" & To_String (Port_Text) & "/chunked", URI);
      Assert (Status = Http_Client.Errors.Ok, "chunked upload URI should parse");

      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST, URI => URI, Item => Request);
      Assert (Status = Http_Client.Errors.Ok, "chunked upload request should construct");

      Status := Http_Client.Headers.Set (Trailer_Fields, "X-Git-SHA256", "abc");
      Assert (Status = Http_Client.Errors.Ok, "chunked upload trailer should store");

      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
           (Producer => Producer'Unchecked_Access,
            Trailers => Trailer_Fields,
            Replayable => False));
      Assert (Status = Http_Client.Errors.Ok, "unknown-length upload body should attach");

      Status := Http_Client.Clients.Execute (Client, Request, Response);
      Assert (Status = Http_Client.Errors.Ok, "chunked upload execution should succeed");
      Assert
        (Http_Client.Responses.Response_Body (Response) = "OK",
         "chunked upload response should be parsed");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Transfer-Encoding: chunked" & CRLF) > 0,
         "unknown-length upload should send Transfer-Encoding: chunked");
      Assert
        (Index (Captured_Text, "Content-Length:") = 0,
         "chunked upload must not send Content-Length");
      Assert
        (Index (Captured_Text, "Trailer: X-Git-SHA256" & CRLF) > 0,
         "chunked upload should declare request trailers");
      Assert
        (Index
           (Captured_Text,
            CRLF & CRLF
            & "2" & CRLF & "AB" & CRLF
            & "2" & CRLF & Character'Val (0) & Character'Val (255) & CRLF
            & "2" & CRLF & "CD" & CRLF
            & "0" & CRLF
            & "X-Git-SHA256: abc" & CRLF & CRLF) > 0,
         "chunked upload should frame producer bytes and trailers exactly");
   end Test_High_Level_Client_Chunked_Upload_Loopback;

   procedure Test_High_Level_Client_Expect_100_Continue_Loopback

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF           : constant String := Character'Val (13) & Character'Val (10);
      Continue_Text  : constant String := "HTTP/1.1 100 Continue" & CRLF & CRLF;
      Response_Text  : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Expect_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen
           (Before_Continue : out Unbounded_String;
            Full_Request    : out Unbounded_String);
      end Expect_Server;

      task body Expect_Server is
         Server        : GNAT.Sockets.Socket_Type;
         Peer          : GNAT.Sockets.Socket_Type;
         Server_Addr   : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr     : GNAT.Sockets.Sock_Addr_Type;
         Before_Text   : Unbounded_String;
         Request_Text  : Unbounded_String;

         procedure Receive_Append is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end Receive_Append;

         procedure Send_Text (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) := Stream_Element
                 (Character'Pos (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Text;
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
         loop
            Receive_Append;
            exit when Index (Request_Text, CRLF & CRLF) > 0;
         end loop;
         Before_Text := Request_Text;
         Send_Text (Continue_Text);

         loop
            exit when Index (Request_Text, CRLF & CRLF & "abc") > 0;
            Receive_Append;
         end loop;
         Send_Text (Response_Text);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen
           (Before_Continue : out Unbounded_String;
            Full_Request    : out Unbounded_String)
         do
            Before_Continue := Before_Text;
            Full_Request    := Request_Text;
         end Request_Seen;
      end Expect_Server;

      Server          : Expect_Server;
      Port            : Http_Client.URI.TCP_Port;
      URI             : Http_Client.URI.URI_Reference;
      Headers         : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request         : Http_Client.Requests.Request;
      Response        : Http_Client.Responses.Response;
      Client          : Http_Client.Clients.Client;
      Status          : Http_Client.Errors.Result_Status;
      Before_Continue : Unbounded_String;
      Full_Request    : Unbounded_String;
   begin
      Server.Ready (Port);
      Status := Http_Client.Clients.Initialize
        (Client, Http_Client.Clients.Default_Client_Configuration);
      Assert (Status = Http_Client.Errors.Ok, "client initialization should succeed");
      Status := Http_Client.URI.Parse
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/expect", URI);
      Assert (Status = Http_Client.Errors.Ok, "expect test URI should parse");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Expect", "100-continue"),
         "Expect: 100-continue should be accepted");
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI => URI,
         Item => Request,
         Headers => Headers,
         Payload => "abc");
      Assert (Status = Http_Client.Errors.Ok, "expect request should construct");

      Status := Http_Client.Clients.Execute (Client, Request, Response);
      Assert (Status = Http_Client.Errors.Ok, "expect execution should succeed");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "final response after 100 Continue should be returned");
      Assert
        (Http_Client.Responses.Response_Body (Response) = "OK",
         "final response body after 100 Continue should be parsed");

      Server.Request_Seen (Before_Continue, Full_Request);
      Assert
        (Index (Before_Continue, "Expect: 100-continue" & CRLF) > 0,
         "request headers should contain explicit Expect header");
      Assert
        (Index (Before_Continue, CRLF & CRLF & "abc") = 0,
         "buffered request body must not be sent before 100 Continue");
      Assert
        (Index (Full_Request, CRLF & CRLF & "abc") > 0,
         "buffered request body should be sent after 100 Continue");
   end Test_High_Level_Client_Expect_100_Continue_Loopback;

   procedure Test_High_Level_Client_Expect_Final_Response_Does_Not_Upload

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String := Character'Val (13) & Character'Val (10);
      Response_Body : constant String := "no-upload";
      Response_Text : constant String :=
        "HTTP/1.1 417 Expectation Failed" & CRLF &
        "Content-Length: " & Decimal_Image (Response_Body'Length) & CRLF &
        CRLF & Response_Body;

      task type Reject_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Reject_Server;

      task body Reject_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
         Raw          : Stream_Element_Array (1 .. 4096);
         Last         : Stream_Element_Offset;
         Out_Raw      : Stream_Element_Array (1 .. Stream_Element_Offset (Response_Text'Length));
         Out_Last     : Stream_Element_Offset;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);
         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type := GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;
         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         if Last >= Raw'First then
            for Index in Raw'First .. Last loop
               Append (Request_Text, Character'Val (Raw (Index)));
            end loop;
         end if;
         for Index in Out_Raw'Range loop
            Out_Raw (Index) := Stream_Element
              (Character'Pos (Response_Text (Response_Text'First + Natural (Index - Out_Raw'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Out_Raw, Out_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Reject_Server;

      Server       : Reject_Server;
      Port         : Http_Client.URI.TCP_Port;
      URI          : Http_Client.URI.URI_Reference;
      Headers      : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request      : Http_Client.Requests.Request;
      Response     : Http_Client.Responses.Response;
      Client       : Http_Client.Clients.Client;
      Status       : Http_Client.Errors.Result_Status;
      Captured     : Unbounded_String;
   begin
      Server.Ready (Port);
      Status := Http_Client.Clients.Initialize
        (Client, Http_Client.Clients.Default_Client_Configuration);
      Assert (Status = Http_Client.Errors.Ok, "client initialization should succeed");
      Status := Http_Client.URI.Parse
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/expect-reject", URI);
      Assert (Status = Http_Client.Errors.Ok, "expect reject URI should parse");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Expect", "100-continue"),
         "Expect header should be accepted");
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI => URI,
         Item => Request,
         Headers => Headers,
         Payload => "abc");
      Assert (Status = Http_Client.Errors.Ok, "expect reject request should construct");

      Status := Http_Client.Clients.Execute (Client, Request, Response);
      Assert (Status = Http_Client.Errors.Ok, "final expect rejection should be returned as response");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 417,
         "server final response before body should be exposed to caller");
      Assert
        (Http_Client.Responses.Response_Body (Response) = Response_Body,
         "server final response body before upload should be parsed");
      Server.Request_Seen (Captured);
      Assert
        (Index (Captured, CRLF & CRLF & "abc") = 0,
         "request body must not be sent when server rejects Expect before 100 Continue");
   end Test_High_Level_Client_Expect_Final_Response_Does_Not_Upload;

   procedure Test_High_Level_Client_Expect_Chunked_Final_Response_Does_Not_Upload

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String := Character'Val (13) & Character'Val (10);
      Response_Body : constant String := "no" & Character'Val (0) & "-upload";
      Response_Text : constant String :=
        "HTTP/1.1 417 Expectation Failed" & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        CRLF &
        "2;expect-test=true" & CRLF & "no" & CRLF &
        "8" & CRLF & Character'Val (0) & "-upload" & CRLF &
        "0" & CRLF &
        "X-Test-Trailer: ignored" & CRLF &
        CRLF;

      task type Reject_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Reject_Server;

      task body Reject_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
         Raw          : Stream_Element_Array (1 .. 4096);
         Last         : Stream_Element_Offset;
         Out_Raw      : Stream_Element_Array
           (1 .. Stream_Element_Offset (Response_Text'Length));
         Out_Last     : Stream_Element_Offset;
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
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         if Last >= Raw'First then
            for Index in Raw'First .. Last loop
               Append (Request_Text, Character'Val (Raw (Index)));
            end loop;
         end if;
         for Index in Out_Raw'Range loop
            Out_Raw (Index) := Stream_Element
              (Character'Pos
                 (Response_Text
                    (Response_Text'First + Natural (Index - Out_Raw'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Out_Raw, Out_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Reject_Server;

      Server       : Reject_Server;
      Port         : Http_Client.URI.TCP_Port;
      URI          : Http_Client.URI.URI_Reference;
      Headers      : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request      : Http_Client.Requests.Request;
      Response     : Http_Client.Responses.Response;
      Client       : Http_Client.Clients.Client;
      Status       : Http_Client.Errors.Result_Status;
      Captured     : Unbounded_String;
   begin
      Server.Ready (Port);
      Status := Http_Client.Clients.Initialize
        (Client, Http_Client.Clients.Default_Client_Configuration);
      Assert (Status = Http_Client.Errors.Ok, "client initialization should succeed");
      Status := Http_Client.URI.Parse
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port))
         & "/expect-reject-chunked", URI);
      Assert (Status = Http_Client.Errors.Ok, "expect reject URI should parse");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Expect", "100-continue"),
         "Expect header should be accepted");
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI => URI,
         Item => Request,
         Headers => Headers,
         Payload => "abc");
      Assert (Status = Http_Client.Errors.Ok, "expect reject request should construct");

      Status := Http_Client.Clients.Execute (Client, Request, Response);
      Assert (Status = Http_Client.Errors.Ok,
              "chunked final expect rejection should be returned as response");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 417,
         "server final chunked response before body should be exposed to caller");
      Assert
        (Http_Client.Responses.Response_Body (Response) = Response_Body,
         "server final chunked response body before upload should be decoded");
      Server.Request_Seen (Captured);
      Assert
        (Index (Captured, CRLF & CRLF & "abc") = 0,
         "request body must not be sent when server rejects Expect before 100 Continue");
   end Test_High_Level_Client_Expect_Chunked_Final_Response_Does_Not_Upload;

   procedure Test_High_Level_Client_Secure_Defaults_No_Implicit_Headers

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
      Client        : constant Http_Client.Clients.Client := Http_Client.Clients.Create;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/secure-defaults",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "default high-level GET should succeed against loopback server");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Authorization:") = 0,
         "high-level secure defaults must not send origin credentials");

      Assert
        (Index (Captured_Text, "Proxy-Authorization:") = 0,
         "high-level secure defaults must not send proxy credentials");

      Assert
        (Index (Captured_Text, "Cookie:") = 0,
         "high-level secure defaults must not send cookies without an explicit jar or request header");

      Assert
        (Index (Captured_Text, "User-Agent:") = 0,
         "high-level secure defaults must not synthesize a User-Agent");

      Assert
        (Index (Captured_Text, "Accept:") = 0,
         "high-level secure defaults must not synthesize an Accept header");

      Assert
        (Index (Captured_Text, "Connection: close" & CRLF) > 0,
         "one-shot high-level execution should still document itself on the wire with Connection: close");
   end Test_High_Level_Client_Secure_Defaults_No_Implicit_Headers;

   procedure Test_Response_Stream_Stores_Cookies_From_Headers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Set-Cookie: sid=abc; Path=/"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

      task type Cookie_Stream_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Cookie_Stream_Server;

      task body Cookie_Stream_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;
         Raw         :
           Stream_Element_Array
             (1 .. Stream_Element_Offset (Response_Text'Length));
         Sent_Last   : Stream_Element_Offset;
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
         GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Req_Last);
         for Index in Raw'Range loop
            Raw (Index) :=
              Stream_Element
                (Character'Pos
                   (Response_Text
                      (Response_Text'First + Natural (Index - Raw'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Raw, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Cookie_Stream_Server;

      Server  : Cookie_Stream_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Jar     : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Server.Ready (Port);
      Options.Cookie_Jar := Jar'Unchecked_Access;
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/cookies",
         URI,
         "streaming cookie URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming cookie request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming response with Set-Cookie should open successfully");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, URI) = "sid=abc",
         "streaming response headers should update the configured cookie jar before body consumption");
   end Test_Response_Stream_Stores_Cookies_From_Headers;

   procedure Test_Persistent_Cache_Unvaried_Headers_Do_Not_Fork_Files

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir       : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_g");
      Store     : Http_Client.Cache.Persistent.Persistent_Store;
      Config    : constant Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Headers_A : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Headers_B : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_A     : Http_Client.Requests.Request;
      Req_B     : Http_Client.Requests.Request;
      Res       : Http_Client.Responses.Response;
      Hit       : Http_Client.Responses.Response;
      Meta      : Http_Client.Cache.Cache_Metadata;
      T0        : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status    : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Assert
        (Http_Client.Headers.Set (Headers_A, "Accept-Language", "en")
         = Http_Client.Errors.Ok,
         "vary canonicalization setup should add language header A");
      Assert
        (Http_Client.Headers.Set (Headers_A, "User-Agent", "agent-a")
         = Http_Client.Errors.Ok,
         "vary canonicalization setup should add unvaried header A");
      Assert
        (Http_Client.Headers.Set (Headers_B, "Accept-Language", "en")
         = Http_Client.Errors.Ok,
         "vary canonicalization setup should add language header B");
      Assert
        (Http_Client.Headers.Set (Headers_B, "User-Agent", "agent-b")
         = Http_Client.Errors.Ok,
         "vary canonicalization setup should add unvaried header B");
      Build_Cache_Request ("http://example.com/vary-key", Req_A, Headers_A);
      Build_Cache_Request ("http://example.com/vary-key", Req_B, Headers_B);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 2"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "en",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "unvaried-header persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req_A, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "first unvaried-header variant should store");
      Status :=
        Http_Client.Cache.Persistent.Store (Store, Req_B, Res, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "second request differing only in unvaried header should replace same persistent key");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 1,
         "unvaried request headers must not fork persistent metadata files");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "unvaried-header persistent cache should reopen");
      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_A, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "matching varied dimension should hit after unvaried-header replacement");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "en",
         "replacement should preserve cached body for the varied dimension");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Unvaried_Headers_Do_Not_Fork_Files;

   procedure Test_Multipart_Binary_And_Header_Policy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Form      : Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Body_Data : Ada.Strings.Unbounded.Unbounded_String;
      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Binary    : constant String := "a" & Character'Val (0) & CRLF & "z";
   begin
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "bin-boundary")
         = Http_Client.Errors.Ok,
         "binary test boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Binary_Part
           (Form, "blob", Binary, "data.bin", "application/octet-stream")
         = Http_Client.Errors.Ok,
         "binary part with filename and content type should be accepted");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Body_Data)
         = Http_Client.Errors.Ok,
         "binary multipart body should render");
      Assert
        (Ada.Strings.Unbounded.To_String (Body_Data)
         = "--bin-boundary"
           & CRLF
           & "Content-Disposition: form-data; name=""blob""; filename=""data.bin"""
           & CRLF
           & "Content-Type: application/octet-stream"
           & CRLF
           & CRLF
           & Binary
           & CRLF
           & "--bin-boundary--"
           & CRLF,
         "binary part content should be preserved exactly inside framing");

      Assert
        (Http_Client.Multipart.Add_Field
           (Form, "bad" & Character'Val (10) & "name", "x")
         = Http_Client.Errors.Invalid_Form_Field,
         "field names must reject LF header injection");
      Assert
        (Http_Client.Multipart.Add_Binary_Part (Form, "good", "x", "bad""name")
         = Http_Client.Errors.Invalid_File_Name,
         "filenames must reject unsafe quoted-string characters");
   end Test_Multipart_Binary_And_Header_Policy;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Requests_Headers");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Auth_Base64_And_Basic_Header'Access,
         "Test_Auth_Base64_And_Basic_Header");
      Register_Routine
        (T,
         Test_Auth_Bearer_Header_And_Request_Helper'Access,
         "Test_Auth_Bearer_Header_And_Request_Helper");
      Register_Routine (T, Test_Header_List'Access, "Test_Header_List");
      Register_Routine
        (T,
         Test_Header_Iteration_Order'Access,
         "Test_Header_Iteration_Order");
      Register_Routine
        (T, Test_Default_Request'Access, "Test_Default_Request");
      Register_Routine
        (T,
         Test_Request_Construction'Access,
         "Test_Request_Construction");
      Register_Routine
        (T,
         Test_Request_Default_Port_And_Empty_Query'Access,
         "Test_Request_Default_Port_And_Empty_Query");
      Register_Routine
        (T,
         Test_Request_Post_Payload_And_Explicit_Host'Access,
         "Test_Request_Post_Payload_And_Explicit_Host");
      Register_Routine
        (T,
         Test_Request_Auto_Host_Disabled'Access,
         "Test_Request_Auto_Host_Disabled");
      Register_Routine
        (T,
         Test_Request_Method_Image_And_Invalid_URI'Access,
         "Test_Request_Method_Image_And_Invalid_URI");
      Register_Routine
        (T,
         Test_HTTP1_Host_Header_Ports'Access,
         "Test_HTTP1_Host_Header_Ports");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Header_Whitespace_And_Binary_Body'Access,
         "Test_HTTP1_Response_Parse_Header_Whitespace_And_Binary_Body");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Invalid_Headers'Access,
         "Test_HTTP1_Response_Parse_Invalid_Headers");
      Register_Routine
        (T,
         Test_HTTP1_Fixed_Length_Stream_Headers'Access,
         "Test_HTTP1_Fixed_Length_Stream_Headers");
      Register_Routine
        (T,
         Test_HTTP1_Unknown_Length_Stream_Chunked_Headers'Access,
         "Test_HTTP1_Unknown_Length_Stream_Chunked_Headers");
      Register_Routine
        (T,
         Test_HTTP1_Chunked_Upload_Header_Validation'Access,
         "Test_HTTP1_Chunked_Upload_Header_Validation");
      Register_Routine
        (T,
         Test_Client_Cookie_Explicit_Header_Conflict_Loopback'Access,
         "Test_Client_Cookie_Explicit_Header_Conflict_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Default_Header_Policy'Access,
         "Test_High_Level_Client_Default_Header_Policy");
      Register_Routine
        (T,
         Test_High_Level_Client_Default_Header_Validation_Bypass'Access,
         "Test_High_Level_Client_Default_Header_Validation_Bypass");
      Register_Routine
        (T,
         Test_High_Level_Client_Default_Header_Remove_And_Result_Reset'Access,
         "Test_High_Level_Client_Default_Header_Remove_And_Result_Reset");
      Register_Routine
        (T,
         Test_High_Level_Client_Post_Default_Header_Loopback'Access,
         "Test_High_Level_Client_Post_Default_Header_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Chunked_Upload_Loopback'Access,
         "Test_High_Level_Client_Chunked_Upload_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Expect_100_Continue_Loopback'Access,
         "Test_High_Level_Client_Expect_100_Continue_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Expect_Final_Response_Does_Not_Upload'Access,
         "Test_High_Level_Client_Expect_Final_Response_Does_Not_Upload");
      Register_Routine
        (T,
         Test_High_Level_Client_Expect_Chunked_Final_Response_Does_Not_Upload'Access,
         "Test_High_Level_Client_Expect_Chunked_Final_Response_Does_Not_Upload");
      Register_Routine
        (T,
         Test_High_Level_Client_Secure_Defaults_No_Implicit_Headers'Access,
         "Test_High_Level_Client_Secure_Defaults_No_Implicit_Headers");
      Register_Routine
        (T,
         Test_Response_Stream_Stores_Cookies_From_Headers'Access,
         "Test_Response_Stream_Stores_Cookies_From_Headers");
      Register_Routine
        (T,
         Test_Persistent_Cache_Unvaried_Headers_Do_Not_Fork_Files'Access,
         "Test_Persistent_Cache_Unvaried_Headers_Do_Not_Fork_Files");
      Register_Routine
        (T,
         Test_Multipart_Binary_And_Header_Policy'Access,
         "Test_Multipart_Binary_And_Header_Policy");
   end Register_Tests;

end Http_Client.Requests_Headers.Tests;
