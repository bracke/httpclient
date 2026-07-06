with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Clients;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Cookies.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
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

   procedure Test_Cookies_Parse_Basic

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Cookie : Http_Client.Cookies.Cookie;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://www.example.com/account/login",
         URI,
         "cookie origin URI should parse");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("sid=abc123; Path=/account; Secure; HttpOnly; SameSite=Lax",
           URI,
           Cookie);

      Assert (Status = Http_Client.Errors.Ok, "valid Set-Cookie should parse");
      Assert
        (Http_Client.Cookies.Name (Cookie) = "sid",
         "cookie name should be stored");
      Assert
        (Http_Client.Cookies.Value (Cookie) = "abc123",
         "cookie value should be stored");
      Assert
        (Http_Client.Cookies.Domain (Cookie) = "www.example.com",
         "cookie without Domain should use origin host");
      Assert
        (Http_Client.Cookies.Host_Only (Cookie),
         "cookie without Domain should be host-only");
      Assert
        (Http_Client.Cookies.Path (Cookie) = "/account",
         "Path attribute should be stored");
      Assert
        (Http_Client.Cookies.Secure (Cookie),
         "Secure attribute should be stored");
      Assert
        (Http_Client.Cookies.Http_Only (Cookie),
         "HttpOnly attribute should be stored");
      Assert
        (Http_Client.Cookies.SameSite (Cookie)
         = Http_Client.Cookies.SameSite_Lax,
         "SameSite=Lax should be parsed as metadata");
   end Test_Cookies_Parse_Basic;

   procedure Test_Cookies_Reject_Invalid_And_Unrelated_Domain

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI          : Http_Client.URI.URI_Reference;
      Unparsed_URI : Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("https://www.example.com/");
      Cookie       : Http_Client.Cookies.Cookie;
      Empty_Jar    : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
   begin
      Assert_Parse_Ok
        ("https://www.example.com/",
         URI,
         "cookie origin URI should parse for rejection tests");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("sid=x", Unparsed_URI, Cookie)
         = Http_Client.Errors.Invalid_URI,
         "cookie parser should reject unchecked/unparsed origin URIs without relying on URI accessor preconditions");

      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Empty_Jar, Unparsed_URI) = "",
         "cookie header generation should return empty for unchecked/unparsed target URIs");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "empty Set-Cookie values should be rejected explicitly");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("   ", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "blank Set-Cookie values should be rejected explicitly");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("sid", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "Set-Cookie values without equals should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("; Path=/", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "Set-Cookie values without a leading name/value pair should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie ("=x", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "empty cookie names should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=line" & Character'Val (10) & "break", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "cookie values with LF should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=x; Domain=attacker.test", URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "unrelated Domain attributes should be rejected");
   end Test_Cookies_Reject_Invalid_And_Unrelated_Domain;

   procedure Test_Cookies_Path_Domain_And_Default_Path

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
   begin
      Assert
        (Http_Client.Cookies.Default_Path ("/docs/Web/HTTP/index.html")
         = "/docs/Web/HTTP",
         "default path should be the parent directory");
      Assert
        (Http_Client.Cookies.Default_Path ("/single") = "/",
         "single-segment paths should default to root");
      Assert
        (Http_Client.Cookies.Path_Matches ("/docs", "/docs/Web"),
         "nested request path should match cookie path");
      Assert
        (not Http_Client.Cookies.Path_Matches ("/docs", "/docsets"),
         "sibling path prefixes should not match cookie path");
      Assert
        (Http_Client.Cookies.Domain_Matches
           ("example.com", "www.example.com", False),
         "domain cookies should match subdomains");
      Assert
        (not Http_Client.Cookies.Domain_Matches
               ("example.com", "www.example.com", True),
         "host-only cookies should not match subdomains");
   end Test_Cookies_Path_Domain_And_Default_Path;

   procedure Test_Cookies_Quoted_Value_Unknown_Attributes_And_Path_Edges

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Cookie : Http_Client.Cookies.Cookie;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/dir/page",
         URI,
         "cookie origin URI should parse for quoted value tests");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("quoted=hello world; Path=relative; SameSite=Experimental; Priority=High",
           URI,
           Cookie);

      Assert
        (Status = Http_Client.Errors.Ok,
         "unknown attributes and SameSite values should not reject a cookie");
      Assert
        (Http_Client.Cookies.Value (Cookie) = "hello world",
         "cookie value should preserve valid embedded spaces");
      Assert
        (Http_Client.Cookies.Path (Cookie) = "/dir",
         "invalid relative Path attribute should fall back to default path");
      Assert
        (Http_Client.Cookies.SameSite (Cookie)
         = Http_Client.Cookies.SameSite_Unknown,
         "unknown SameSite value should be exposed as metadata");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("quoted=""abc def""; Path=/dir", URI, Cookie);

      Assert
        (Status = Http_Client.Errors.Ok,
         "quoted cookie value should parse when its contents are valid");
      Assert
        (Http_Client.Cookies.Value (Cookie) = "abc def",
         "surrounding quotes should not be retained in the stored value");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("quoted=""unterminated; Path=/dir", URI, Cookie)
         = Http_Client.Errors.Invalid_Cookie,
         "unterminated quoted cookie value should be rejected");
   end Test_Cookies_Quoted_Value_Unknown_Attributes_And_Path_Edges;

   procedure Test_Cookie_Jar_Storage_Matching_And_Ordering

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin  : Http_Client.URI.URI_Reference;
      Target  : Http_Client.URI.URI_Reference;
      Jar     : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://www.example.com/docs/page",
         Origin,
         "origin should parse for jar test");
      Assert_Parse_Ok
        ("https://www.example.com/docs/deep/item",
         Target,
         "target should parse for jar test");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "root=r; Path=/"),
         "first Set-Cookie header should be accepted by header model");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "deep=d; Path=/docs"),
         "second Set-Cookie header should be accepted by header model");

      Http_Client.Cookies.Store_From_Response
        (Jar, Origin, Headers, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Set-Cookie fields should be stored");
      Assert
        (Http_Client.Cookies.Length (Jar) = 2,
         "jar should contain two cookies");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Target)
         = "deep=d; root=r",
         "Cookie header should order longer paths before earlier root cookies");
   end Test_Cookie_Jar_Storage_Matching_And_Ordering;

   procedure Test_Cookie_Jar_Expiration_And_Secure

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      HTTP_URI  : Http_Client.URI.URI_Reference;
      HTTPS_URI : Http_Client.URI.URI_Reference;
      Jar       : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status    : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/",
         HTTPS_URI,
         "HTTPS URI should parse for Secure cookie test");
      Assert_Parse_Ok
        ("http://example.com/",
         HTTP_URI,
         "HTTP URI should parse for Secure cookie test");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "sid=s; Secure; Max-Age=60"),
         "secure persistent cookie should be representable as a header");
      Http_Client.Cookies.Store_From_Response
        (Jar, HTTPS_URI, Headers, Status => Status);
      Assert
        (Status = Http_Client.Errors.Ok,
         "secure cookie should store from HTTPS response");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, HTTPS_URI) = "sid=s",
         "secure cookie should be sent to HTTPS target");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, HTTP_URI) = "",
         "secure cookie must not be sent to HTTP target");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "sid=s; Max-Age=0"),
         "Max-Age zero deletion cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, HTTPS_URI, Headers, Status => Status);
      Assert
        (Http_Client.Cookies.Length (Jar) = 0,
         "Max-Age=0 should remove the matching cookie");
   end Test_Cookie_Jar_Expiration_And_Secure;

   procedure Test_Cookies_HTTP_Set_Secure_And_Domain_Edges

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      HTTP_URI          : Http_Client.URI.URI_Reference;
      HTTPS_URI         : Http_Client.URI.URI_Reference;
      IP_URI            : Http_Client.URI.URI_Reference;
      Parent_Origin_URI : Http_Client.URI.URI_Reference;
      Subdomain_URI     : Http_Client.URI.URI_Reference;
      Jar               : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers           : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Cookie            : Http_Client.Cookies.Cookie;
      Status            : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("http://example.com/account/login",
         HTTP_URI,
         "HTTP URI should parse for HTTP-set Secure cookie test");
      Assert_Parse_Ok
        ("https://example.com/account/home",
         HTTPS_URI,
         "HTTPS URI should parse for HTTP-set Secure cookie test");
      Assert_Parse_Ok
        ("http://127.0.0.1/",
         IP_URI,
         "IPv4 origin should parse for Domain rejection test");
      Assert_Parse_Ok
        ("https://www.example.com/account/login",
         Parent_Origin_URI,
         "subdomain origin should parse for parent-domain cookie test");
      Assert_Parse_Ok
        ("https://api.example.com/account/home",
         Subdomain_URI,
         "sibling subdomain target should parse for parent-domain cookie test");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "sid=s; Secure; Path=/account"),
         "HTTP-set Secure cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, HTTP_URI, Headers, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "policy accepts HTTP-set Secure cookies for future HTTPS use");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, HTTP_URI) = "",
         "HTTP-set Secure cookie still must not be sent over HTTP");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, HTTPS_URI) = "sid=s",
         "HTTP-set Secure cookie may be sent over matching HTTPS target");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=x; Domain=127.0.0.1", IP_URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "Domain attributes for IP-literal origins should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=x; Domain=bad-.example.com", HTTP_URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "Domain labels ending with hyphen should be rejected");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("parent=p; Domain=example.com; Path=/account",
            Parent_Origin_URI,
            Cookie)
         = Http_Client.Errors.Ok,
         "parent Domain attributes that domain-match the origin should be accepted");
      Assert
        (not Http_Client.Cookies.Host_Only (Cookie),
         "Domain attributes should create domain cookies rather than host-only cookies");
      Assert
        (Http_Client.Cookies.Domain (Cookie) = "example.com",
         "accepted Domain attributes should be normalized and stored");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers,
            "Set-Cookie",
            "parent=p; Domain=example.com; Path=/account"),
         "parent-domain Set-Cookie header should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, Parent_Origin_URI, Headers, Status => Status);
      Assert
        (Status = Http_Client.Errors.Ok,
         "parent-domain Set-Cookie should store from a matching subdomain origin");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Subdomain_URI)
         = "parent=p",
         "stored parent-domain cookies should be selected for matching sibling subdomains");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Secure-sid=x; Path=/account", HTTPS_URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "__Secure- cookies should require the Secure attribute");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Secure-sid=x; Secure; Path=/account", HTTP_URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "__Secure- cookies should require an HTTPS origin");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Secure-sid=x; Secure; Path=/account", HTTPS_URI, Cookie)
         = Http_Client.Errors.Ok,
         "valid __Secure- cookies should parse over HTTPS with Secure");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Host-sid=x; Secure; Path=/; Domain=example.com",
            HTTPS_URI,
            Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "__Host- cookies should reject Domain attributes");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Host-sid=x; Secure; Path=/account", HTTPS_URI, Cookie)
         = Http_Client.Errors.Cookie_Rejected,
         "__Host- cookies should require explicit Path=/");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("__Host-sid=x; Secure; Path=/", HTTPS_URI, Cookie)
         = Http_Client.Errors.Ok,
         "valid __Host- cookies should parse over HTTPS with Secure and Path=/");
   end Test_Cookies_HTTP_Set_Secure_And_Domain_Edges;

   procedure Test_Cookie_Jar_Remove_Expired_And_Cookie_At

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Jar     : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
      Now     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 1, 1);
      Later   : constant Ada.Calendar.Time := Now + 120.0;
   begin
      Assert_Parse_Ok
        ("https://example.com/root/page",
         URI,
         "cookie origin should parse for Remove_Expired test");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "short=s; Max-Age=60; Path=/root"),
         "short-lived cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, URI, Headers, Now => Now, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "short-lived cookie should store successfully");
      Assert
        (Http_Client.Cookies.Length (Jar) = 1,
         "jar should contain one cookie before expiration removal");
      Assert
        (Http_Client.Cookies.Name (Http_Client.Cookies.Cookie_At (Jar, 1))
         = "short",
         "Cookie_At should expose deterministic storage order");

      Http_Client.Cookies.Remove_Expired (Jar, Later);
      Assert
        (Http_Client.Cookies.Length (Jar) = 0,
         "Remove_Expired should remove cookies expired at supplied time");
   end Test_Cookie_Jar_Remove_Expired_And_Cookie_At;

   procedure Test_Cookies_Expires_And_Max_Age_Precedence

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Cookie : Http_Client.Cookies.Cookie;
      Now    : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (2026, 1, 1);
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/path/page",
         URI,
         "cookie origin URI should parse for expiration tests");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("exp=x; Expires=Wed, 01 Jan 2030 00:00:00 GMT",
           URI,
           Cookie,
           Now => Now);

      Assert
        (Status = Http_Client.Errors.Ok,
         "conservative IMF-fixdate Expires value should parse");
      Assert
        (Http_Client.Cookies.Is_Persistent (Cookie),
         "Expires should make the cookie persistent");
      Assert
        (not Http_Client.Cookies.Is_Expired (Cookie, Now),
         "future Expires value should not be expired at Now");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("exp=x; Expires=Wed, 01 Jan 2030 00:00:00 GMT; Max-Age=0",
           URI,
           Cookie,
           Now => Now);

      Assert
        (Status = Http_Client.Errors.Ok, "Max-Age with Expires should parse");
      Assert
        (Http_Client.Cookies.Is_Expired (Cookie, Now),
         "Max-Age=0 should take precedence over future Expires");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("exp=x; Max-Age=999999999999999999999999999999999999999999999",
           URI,
           Cookie,
           Now => Now);

      Assert
        (Status = Http_Client.Errors.Invalid_Cookie,
         "overflowing Max-Age should be rejected deterministically");
   end Test_Cookies_Expires_And_Max_Age_Precedence;

   procedure Test_Cookies_Duplicate_Attributes_And_Clear_Reuses_Order

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin  : Http_Client.URI.URI_Reference;
      Target  : Http_Client.URI.URI_Reference;
      Cookie  : Http_Client.Cookies.Cookie;
      Jar     : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
      Now     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 1, 1);
   begin
      Assert_Parse_Ok
        ("https://www.example.com/base/page",
         Origin,
         "origin URI should parse for duplicate-attribute cookie tests");
      Assert_Parse_Ok
        ("https://www.example.com/second/child",
         Target,
         "target URI should parse for clear/reuse cookie tests");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("sid=x; Domain=.; Path=/", Origin, Cookie, Now => Now);
      Assert
        (Status = Http_Client.Errors.Cookie_Rejected,
         "empty Domain after leading-dot normalization should be rejected");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("sid=x; Path=/first; Path=/second; SameSite=Lax; SameSite=Strict",
           Origin,
           Cookie,
           Now => Now);
      Assert
        (Status = Http_Client.Errors.Ok,
         "duplicate benign attributes should parse deterministically");
      Assert
        (Http_Client.Cookies.Path (Cookie) = "/second",
         "last valid duplicate Path attribute should win deterministically");
      Assert
        (Http_Client.Cookies.SameSite (Cookie)
         = Http_Client.Cookies.SameSite_Strict,
         "last duplicate SameSite metadata should win deterministically");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "old=o; Path=/"),
         "pre-clear cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, Origin, Headers, Status => Status);
      Assert
        (Status = Http_Client.Errors.Ok,
         "pre-clear cookie should store successfully");

      Http_Client.Cookies.Clear (Jar);
      Assert
        (Http_Client.Cookies.Length (Jar) = 0,
         "Clear should empty the jar before reuse");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "first=1; Path=/second"),
         "first post-clear cookie should be representable");
      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "second=2; Path=/second"),
         "second post-clear cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, Origin, Headers, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "post-clear cookies should store successfully");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Target)
         = "first=1; second=2",
         "Clear should reset deterministic creation ordering for subsequent cookies");
   end Test_Cookies_Duplicate_Attributes_And_Clear_Reuses_Order;

   procedure Test_High_Level_Client_No_Cookie_Jar_Remains_Stateless

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Cookie_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Cookie_Server;

      task body Cookie_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         First_Text  : Unbounded_String;
         Second_Text : Unbounded_String;

         procedure Read_Request (Text : in out Unbounded_String) is
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
         end Read_Request;

         procedure Send_Response (Text : String) is
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
         end Send_Response;
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
         Read_Request (First_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Set-Cookie: sid=abc; Path=/"
            & CRLF
            & "Content-Length: 2"
            & CRLF
            & CRLF
            & "OK");
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Read_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Length: 2"
            & CRLF
            & CRLF
            & "OK");
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Text;
            Second := Second_Text;
         end Requests_Seen;
      end Cookie_Server;

      Server      : Cookie_Server;
      Port        : Http_Client.URI.TCP_Port;
      Port_Text   : Unbounded_String;
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
      First_Seen  : Unbounded_String;
      Second_Seen : Unbounded_String;
      Base_URL    : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));
      Base_URL :=
        To_Unbounded_String ("http://127.0.0.1:" & To_String (Port_Text));

      Status :=
        Http_Client.Clients.Get
          (Client, To_String (Base_URL) & "/set", Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level stateless cookie setup response should succeed");

      Status :=
        Http_Client.Clients.Get
          (Client, To_String (Base_URL) & "/next", Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level stateless second request should succeed");

      Server.Requests_Seen (First_Seen, Second_Seen);

      Assert
        (Index (First_Seen, "Cookie:") = 0,
         "first stateless high-level request should not send cookies");

      Assert
        (Index (Second_Seen, "Cookie:") = 0,
         "high-level client must not store or replay cookies without a configured jar");
   end Test_High_Level_Client_No_Cookie_Jar_Remains_Stateless;

   procedure Test_High_Level_Client_Cookie_Jar_Opt_In_Replays

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Cookie_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Cookie_Server;

      task body Cookie_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         First_Text  : Unbounded_String;
         Second_Text : Unbounded_String;

         procedure Read_Request (Text : in out Unbounded_String) is
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
         end Read_Request;

         procedure Send_Response (Text : String) is
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
         end Send_Response;
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
         Read_Request (First_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Set-Cookie: sid=abc; Path=/"
            & CRLF
            & "Content-Length: 2"
            & CRLF
            & CRLF
            & "OK");
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Read_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Length: 2"
            & CRLF
            & CRLF
            & "OK");
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Text;
            Second := Second_Text;
         end Requests_Seen;
      end Cookie_Server;

      Server      : Cookie_Server;
      Port        : Http_Client.URI.TCP_Port;
      Port_Text   : Unbounded_String;
      Jar         : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Config      : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client      : Http_Client.Clients.Client;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
      First_Seen  : Unbounded_String;
      Second_Seen : Unbounded_String;
      Base_URL    : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));
      Base_URL :=
        To_Unbounded_String ("http://127.0.0.1:" & To_String (Port_Text));

      Config.Execution.Cookie_Jar := Jar'Unchecked_Access;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level cookie-jar configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client, To_String (Base_URL) & "/set", Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level cookie setup response should succeed");

      Assert
        (Http_Client.Cookies.Length (Jar) = 1,
         "configured high-level cookie jar should store Set-Cookie response state");

      Status :=
        Http_Client.Clients.Get
          (Client, To_String (Base_URL) & "/next", Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level cookie replay request should succeed");

      Server.Requests_Seen (First_Seen, Second_Seen);

      Assert
        (Index (First_Seen, "Cookie:") = 0,
         "first high-level cookie request should not send a not-yet-stored cookie");

      Assert
        (Index (Second_Seen, "Cookie: sid=abc" & CRLF) > 0,
         "configured high-level cookie jar should replay matching cookies on later requests");
   end Test_High_Level_Client_Cookie_Jar_Opt_In_Replays;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Cookies");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Cookies_Parse_Basic'Access, "Test_Cookies_Parse_Basic");
      Register_Routine
        (T,
         Test_Cookies_Reject_Invalid_And_Unrelated_Domain'Access,
         "Test_Cookies_Reject_Invalid_And_Unrelated_Domain");
      Register_Routine
        (T,
         Test_Cookies_Path_Domain_And_Default_Path'Access,
         "Test_Cookies_Path_Domain_And_Default_Path");
      Register_Routine
        (T,
         Test_Cookies_Quoted_Value_Unknown_Attributes_And_Path_Edges'Access,
         "Test_Cookies_Quoted_Value_Unknown_Attributes_And_Path_Edges");
      Register_Routine
        (T,
         Test_Cookie_Jar_Storage_Matching_And_Ordering'Access,
         "Test_Cookie_Jar_Storage_Matching_And_Ordering");
      Register_Routine
        (T,
         Test_Cookie_Jar_Expiration_And_Secure'Access,
         "Test_Cookie_Jar_Expiration_And_Secure");
      Register_Routine
        (T,
         Test_Cookies_HTTP_Set_Secure_And_Domain_Edges'Access,
         "Test_Cookies_HTTP_Set_Secure_And_Domain_Edges");
      Register_Routine
        (T,
         Test_Cookie_Jar_Remove_Expired_And_Cookie_At'Access,
         "Test_Cookie_Jar_Remove_Expired_And_Cookie_At");
      Register_Routine
        (T,
         Test_Cookies_Expires_And_Max_Age_Precedence'Access,
         "Test_Cookies_Expires_And_Max_Age_Precedence");
      Register_Routine
        (T,
         Test_Cookies_Duplicate_Attributes_And_Clear_Reuses_Order'Access,
         "Test_Cookies_Duplicate_Attributes_And_Clear_Reuses_Order");
      Register_Routine
        (T,
         Test_High_Level_Client_No_Cookie_Jar_Remains_Stateless'Access,
         "Test_High_Level_Client_No_Cookie_Jar_Remains_Stateless");
      Register_Routine
        (T,
         Test_High_Level_Client_Cookie_Jar_Opt_In_Replays'Access,
         "Test_High_Level_Client_Cookie_Jar_Opt_In_Replays");
   end Register_Tests;

end Http_Client.Cookies.Tests;
