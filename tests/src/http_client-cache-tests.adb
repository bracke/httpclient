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
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Cache.Tests is

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

   procedure Test_Cache_Key_Query_And_Fragment

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req_A : Http_Client.Requests.Request;
      Req_B : Http_Client.Requests.Request;
   begin
      Build_Cache_Request ("http://example.com/a?x=1#frag", Req_A);
      Build_Cache_Request ("http://example.com/a?x=1#other", Req_B);
      Assert
        (Http_Client.Cache.Origin_Key (Req_A)
         = Http_Client.Cache.Origin_Key (Req_B),
         "cache origin key must exclude URI fragment");

      Build_Cache_Request ("http://example.com/a?x=2#frag", Req_B);
      Assert
        (Http_Client.Cache.Origin_Key (Req_A)
         /= Http_Client.Cache.Origin_Key (Req_B),
         "cache origin key must include query string");

      Build_Cache_Request ("HTTP://EXAMPLE.COM:80/a?x=1#frag", Req_B);
      Assert
        (Http_Client.Cache.Origin_Key (Req_A)
         = Http_Client.Cache.Origin_Key (Req_B),
         "cache origin key should normalize scheme, host, and effective default port");
   end Test_Cache_Key_Query_And_Fragment;

   procedure Test_Cache_Key_IPv6_Authority_Is_Bracketed

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req_IPv6      : Http_Client.Requests.Request;
      Req_IPv4      : Http_Client.Requests.Request;
      Req_DNS       : Http_Client.Requests.Request;
      IPv6_Key      : constant String := "http://[::1]:8080/cache";
   begin
      Build_Cache_Request (IPv6_Key, Req_IPv6);
      Build_Cache_Request ("http://127.0.0.1:8080/cache", Req_IPv4);
      Build_Cache_Request ("http://localhost:8080/cache", Req_DNS);

      Assert
        (Http_Client.Cache.Origin_Key (Req_IPv6) = IPv6_Key,
         "cache origin key should bracket IPv6 literal authority");
      Assert
        (Http_Client.Cache.Origin_Key (Req_IPv6)
         /= Http_Client.Cache.Origin_Key (Req_IPv4),
         "IPv6 literal cache origin should not collide with IPv4 literal origin");
      Assert
        (Http_Client.Cache.Origin_Key (Req_IPv6)
         /= Http_Client.Cache.Origin_Key (Req_DNS),
         "IPv6 literal cache origin should not collide with DNS origin");
   end Test_Cache_Key_IPv6_Authority_Is_Bracketed;

   procedure Test_Cache_Freshness_And_Stale_Transition

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache  : Http_Client.Cache.Cache_Store;
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
      Lifetime_MS : Natural := 0;
      Conditional : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Assert
        (Http_Client.Cache.Is_Weak_ETag ("W/""abc"""),
         "weak ETag helper should recognize W/ prefix");
      Assert
        (not Http_Client.Cache.Is_Weak_ETag ("""abc"""),
         "weak ETag helper should not mark strong validators weak");
      Assert
        (Http_Client.Cache.Cache_Control_Has_Directive
           ("max-age=10, must-revalidate", "must-revalidate"),
         "Cache-Control directive helper should match directive boundaries");
      Assert
        (Http_Client.Cache.Cache_Control_Directive_Value
           ("private, max-age=""10""", "max-age") = "10",
         "Cache-Control directive value helper should unquote values");
      Assert
        (Http_Client.Cache.Freshness_Lifetime_MS
           ("max-age=10", "", T0, True, Lifetime_MS),
         "max-age should produce an explicit freshness lifetime");
      Assert (Lifetime_MS = 10_000, "max-age lifetime should be milliseconds");
      Assert
        (Http_Client.Cache.Is_Fresh
           ("max-age=10", "", T0, True, Max_Stale_MS => 0, Now => T0 + 5.0),
         "public freshness helper should accept fresh max-age metadata");
      Assert
        (not Http_Client.Cache.Is_Fresh
           ("no-cache, max-age=10", "", T0, True, Max_Stale_MS => 0, Now => T0 + 5.0),
         "public freshness helper should reject revalidation-required metadata");

      Http_Client.Cache.Add_Conditional_Validators
        (Conditional, """etag-v1""", "Wed, 21 Oct 2015 07:28:00 GMT");
      Assert
        (Http_Client.Headers.Get (Conditional, "If-None-Match") = """etag-v1""",
         "conditional helper should add If-None-Match");
      Assert
        (Http_Client.Headers.Get (Conditional, "If-Modified-Since")
         = "Wed, 21 Oct 2015 07:28:00 GMT",
         "conditional helper should add If-Modified-Since");

      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/data", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=10"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 5"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "hello",
         Res);

      Status := Http_Client.Cache.Store (Cache, Req, Res, T0);
      Assert (Status = Http_Client.Errors.Ok, "fresh response should store");

      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 5.0);
      Assert (Status = Http_Client.Errors.Ok, "fresh response should hit");
      Assert
        (Meta.Source = Http_Client.Cache.From_Fresh_Cache,
         "fresh hit metadata should be set");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "hello",
         "fresh hit should return cached body");

      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 11.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "expired response should be stale");
      Assert
        (Meta.Source = Http_Client.Cache.From_Stale_Cache,
         "stale metadata should be set");
   end Test_Cache_Freshness_And_Stale_Transition;

   procedure Test_Cache_Expires_Date_Age_And_Invalid_Date

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache  : Http_Client.Cache.Cache_Store;
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);

      Build_Cache_Request ("http://example.com/expires", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Date: Wed, 13 May 2026 00:00:00 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Expires: Wed, 13 May 2026 00:00:30 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 7"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "expires",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "Expires response should store");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 20.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Expires later than Date should produce a fresh cache hit");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 31.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "Expires freshness should expire deterministically");

      Build_Cache_Request ("http://example.com/late-expires", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Date: Wed, 13 May 2026 00:00:00 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Expires: Wed, 13 May 2026 00:00:30 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "late",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0 + 20.0)
         = Http_Client.Errors.Ok,
         "late-stored Expires response should store");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 25.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "Expires absolute time should remain fresh before the Expires timestamp");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 31.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "Expires absolute time must not be extended by local store time");

      Build_Cache_Request ("http://example.com/age", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=30"
         & ASCII.CR
         & ASCII.LF
         & "Age: 20"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "age",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "Age response should store");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 9.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "Age should reduce max-age freshness but remain fresh inside the remaining lifetime");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 11.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "Age should reduce max-age freshness deterministically");

      Build_Cache_Request ("http://example.com/huge-age", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=30"
         & ASCII.CR
         & ASCII.LF
         & "Age: 999999999999999999999999999999999999999999999"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "huge",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "huge Age response should store without arithmetic exceptions");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 20.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "overflowing Age should be ignored as invalid instead of wrapping");

      Build_Cache_Request ("http://example.com/invalid-expires", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Expires: not-a-date"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 7"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "invalid",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "invalid Expires response may store but should not become fresh");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "invalid Expires should be treated as requiring revalidation");
   end Test_Cache_Expires_Date_Age_And_Invalid_Date;

   procedure Test_Cache_Date_Apparent_Age_For_Max_Age

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache  : Http_Client.Cache.Cache_Store;
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/apparent-age", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Date: Tue, 12 May 2026 23:59:50 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=20"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "age",
         Res);

      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "response with Date apparent age should store");

      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 9.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "apparent age should still allow freshness before max-age is exhausted");
      Assert
        (Meta.Age_Seconds = 19,
         "reported cache age should include apparent age from Date plus resident time");

      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 11.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "apparent age from Date should reduce max-age freshness");
   end Test_Cache_Date_Apparent_Age_For_Max_Age;

   procedure Test_Cache_Request_Directives

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache   : Http_Client.Cache.Cache_Store;
      Config  : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req     : Http_Client.Requests.Request;
      Res     : Http_Client.Responses.Response;
      Hit     : Http_Client.Responses.Response;
      Meta    : Http_Client.Cache.Cache_Metadata;
      T0      : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status  : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/directives", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=20"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 5"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "hello",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "directive response should store");

      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "max-age=5")
         = Http_Client.Errors.Ok,
         "request max-age header should set");
      Build_Cache_Request ("http://example.com/directives", Req, Headers);
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 6.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "request Cache-Control max-age should cap acceptable cached age");

      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "min-fresh=15")
         = Http_Client.Errors.Ok,
         "request min-fresh header should set");
      Build_Cache_Request ("http://example.com/directives", Req, Headers);
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 10.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "request Cache-Control min-fresh should require enough remaining freshness");

      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set
           (Headers, "Cache-Control", "no-cache=""Set-Cookie""")
         = Http_Client.Errors.Ok,
         "request no-cache field-name form should set");
      Build_Cache_Request ("http://example.com/directives", Req, Headers);
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "request no-cache with a value should still force revalidation");
   end Test_Cache_Request_Directives;

   procedure Test_Cache_Vary_And_Vary_Star_Rejection

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache  : Http_Client.Cache.Cache_Store;
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      H1     : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      H2     : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_En : Http_Client.Requests.Request;
      Req_De : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      Status : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Assert
        (Http_Client.Headers.Set (H1, "Accept-Language", "en")
         = Http_Client.Errors.Ok,
         "vary test header en should set");
      Assert
        (Http_Client.Headers.Set (H2, "Accept-Language", "de")
         = Http_Client.Errors.Ok,
         "vary test header de should set");
      Build_Cache_Request ("http://example.com/vary", Req_En, H1);
      Build_Cache_Request ("http://example.com/vary", Req_De, H2);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
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
      Assert
        (Http_Client.Cache.Store (Cache, Req_En, Res) = Http_Client.Errors.Ok,
         "vary response should store");
      Status := Http_Client.Cache.Lookup (Cache, Req_De, Hit, Meta);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "mismatched Vary header must miss");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: *"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req_En, Res)
         = Http_Client.Errors.Cache_Disabled,
         "Vary star response must not be stored");
   end Test_Cache_Vary_And_Vary_Star_Rejection;

   procedure Test_Cache_Vary_Canonicalization_And_Duplicate_Rejection

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache   : Http_Client.Cache.Cache_Store;
      Config  : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req     : Http_Client.Requests.Request;
      Res     : Http_Client.Responses.Response;
      Hit     : Http_Client.Responses.Response;
      Meta    : Http_Client.Cache.Cache_Metadata;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Assert
        (Http_Client.Headers.Set (Headers, "Accept-Language", "en")
         = Http_Client.Errors.Ok,
         "canonical vary request language should set");
      Assert
        (Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity")
         = Http_Client.Errors.Ok,
         "canonical vary request encoding should set");
      Build_Cache_Request ("http://example.com/canon", Req, Headers);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language, Accept-Encoding"
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
        (Http_Client.Cache.Store (Cache, Req, Res) = Http_Client.Errors.Ok,
         "first canonical vary response should store");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: accept-encoding, accept-language"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "b",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res) = Http_Client.Errors.Ok,
         "same vary dimensions in a different order should replace the entry");
      Assert
        (Http_Client.Cache.Length (Cache) = 1,
         "canonical vary ordering should avoid duplicate equivalent entries");
      Assert
        (Http_Client.Cache.Lookup (Cache, Req, Hit, Meta)
         = Http_Client.Errors.Ok,
         "canonical vary entry should be retrievable");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "b",
         "canonical vary replacement should preserve newest body");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language, accept-language"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "duplicate Vary field names should be rejected conservatively");
   end Test_Cache_Vary_Canonicalization_And_Duplicate_Rejection;

   procedure Test_Cache_Max_Stale_Request_Directive

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache   : Http_Client.Cache.Cache_Store;
      Config  : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req     : Http_Client.Requests.Request;
      Res     : Http_Client.Responses.Response;
      Hit     : Http_Client.Responses.Response;
      Meta    : Http_Client.Cache.Cache_Metadata;
      T0      : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/stale", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=1"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "s",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "max-stale base response should store");

      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "max-stale=5")
         = Http_Client.Errors.Ok,
         "request max-stale should set");
      Build_Cache_Request ("http://example.com/stale", Req, Headers);
      Assert
        (Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 3.0)
         = Http_Client.Errors.Ok,
         "max-stale should allow bounded stale response");
      Assert
        (Meta.Source = Http_Client.Cache.From_Stale_Cache,
         "max-stale hit should be reported as stale cache");

      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "max-stale")
         = Http_Client.Errors.Ok,
         "bare max-stale request directive should set");
      Build_Cache_Request ("http://example.com/stale", Req, Headers);
      Assert
        (Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 3.0)
         = Http_Client.Errors.Cache_Entry_Stale,
         "bare max-stale should not authorize unbounded stale reuse");

      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "max-stale=abc")
         = Http_Client.Errors.Ok,
         "invalid max-stale value should set as raw request directive");
      Build_Cache_Request ("http://example.com/stale", Req, Headers);
      Assert
        (Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 3.0)
         = Http_Client.Errors.Cache_Entry_Stale,
         "invalid max-stale value should not authorize stale reuse");

      Http_Client.Cache.Clear (Cache);
      Build_Cache_Request ("http://example.com/stale", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=1, must-revalidate"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "s",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "must-revalidate max-stale base response should store");
      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "max-stale=5")
         = Http_Client.Errors.Ok,
         "request max-stale should set for must-revalidate test");
      Build_Cache_Request ("http://example.com/stale", Req, Headers);
      Assert
        (Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 3.0)
         = Http_Client.Errors.Cache_Entry_Stale,
         "must-revalidate should prevent serving stale even with request max-stale");
   end Test_Cache_Max_Stale_Request_Directive;

   procedure Test_Cache_Eviction_And_Clear

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache  : Http_Client.Cache.Cache_Store;
      Config : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req1   : Http_Client.Requests.Request;
      Req2   : Http_Client.Requests.Request;
      Req3   : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      Status : Http_Client.Errors.Result_Status;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
   begin
      Config.Enabled := True;
      Config.Max_Entries := 2;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Build_Cache_Request ("http://example.com/1", Req1);
      Build_Cache_Request ("http://example.com/2", Req2);
      Build_Cache_Request ("http://example.com/3", Req3);
      Assert
        (Http_Client.Cache.Store (Cache, Req1, Res, T0)
         = Http_Client.Errors.Ok,
         "entry 1 should store");
      Assert
        (Http_Client.Cache.Store (Cache, Req2, Res, T0 + 1.0)
         = Http_Client.Errors.Ok,
         "entry 2 should store");
      Assert
        (Http_Client.Cache.Store (Cache, Req3, Res, T0 + 2.0)
         = Http_Client.Errors.Ok,
         "entry 3 should store and evict LRU");
      Assert
        (Http_Client.Cache.Length (Cache) = 2,
         "cache should enforce entry count limit");
      Status := Http_Client.Cache.Lookup (Cache, Req1, Hit, Meta, T0 + 3.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "least recently used entry should be evicted");
      Http_Client.Cache.Clear (Cache);
      Assert
        (Http_Client.Cache.Length (Cache) = 0, "clear should remove entries");
      Assert
        (Http_Client.Cache.Stored_Body_Bytes (Cache) = 0,
         "clear should reset body byte accounting");
   end Test_Cache_Eviction_And_Clear;

   procedure Test_Cache_Conditional_Request_And_304_Update

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache        : Http_Client.Cache.Cache_Store;
      Config       : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req          : Http_Client.Requests.Request;
      Conditional  : Http_Client.Requests.Request;
      Res          : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      T0           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/revalidate", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""abc"""
         & ASCII.CR
         & ASCII.LF
         & "Last-Modified: Wed, 13 May 2026 10:00:00 GMT"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "validator response should store");
      Assert
        (Http_Client.Cache.Prepare_Conditional_Request (Req, Res, Conditional)
         = Http_Client.Errors.Ok,
         "validator response should produce conditional request");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Requests.Headers (Conditional), "If-None-Match")
         = """abc""",
         "conditional request should include ETag validator");
      Assert
        (Http_Client.Headers.Contains
           (Http_Client.Requests.Headers (Conditional), "If-Modified-Since"),
         "conditional request should include Last-Modified validator");
      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Assert
        (Http_Client.Cache.Update_From_304
           (Cache, Req, Not_Modified, Meta, T0 + 1.0)
         = Http_Client.Errors.Ok,
         "304 should update cache metadata");
      Assert
        (Meta.Source = Http_Client.Cache.From_Revalidated_Cache
         and then Meta.Revalidation_Count = 1,
         "304 metadata should report revalidated cache entry");
   end Test_Cache_Conditional_Request_And_304_Update;

   procedure Test_Cache_Bypass_Policy_Edges

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache   : Http_Client.Cache.Cache_Store;
      Config  : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      URI     : Http_Client.URI.URI_Reference;
      Req     : Http_Client.Requests.Request;
      Res     : Http_Client.Responses.Response;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);

      Status := Http_Client.URI.Parse ("http://example.com/post", URI);
      Assert
        (Status = Http_Client.Errors.Ok,
         "non-GET cache test URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method  => Http_Client.Types.POST,
           URI     => URI,
           Item    => Req,
           Payload => "payload");
      Assert
        (Status = Http_Client.Errors.Ok,
         "non-GET cache test request should build");
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "non-GET requests and request bodies should bypass cache storage");

      Status :=
        Http_Client.Requests.Create
          (Method  => Http_Client.Types.GET,
           URI     => URI,
           Item    => Req,
           Payload => "payload");
      Assert
        (Status = Http_Client.Errors.Ok,
         "GET cache test request with payload should build");
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "GET requests with legacy buffered payloads should bypass cache storage");

      Assert
        (Http_Client.Headers.Set (Headers, "Cache-Control", "no-store")
         = Http_Client.Errors.Ok,
         "request no-store header should set");
      Build_Cache_Request ("http://example.com/no-store", Req, Headers);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "request Cache-Control no-store should bypass cache storage");

      Build_Cache_Request ("http://example.com/set-cookie", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Set-Cookie: sid=1"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "Set-Cookie responses should bypass cache storage by default");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Encoding: gzip"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "encoded representations should bypass storage until encoded-byte caching is explicit");

      Build_Cache_Request ("http://example.com/partial", Req);
      Build_Cache_Response
        ("HTTP/1.1 206 Partial Content"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Range: bytes 0-0/10"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "partial-content 206 responses should not populate complete cache entries");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Range: bytes 0-0/10"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "x",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "responses carrying Content-Range should not be stored as complete representations");
   end Test_Cache_Bypass_Policy_Edges;

   procedure Test_Cache_Nonstoreable_Replacement_Invalidates

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache   : Http_Client.Cache.Cache_Store;
      Config  : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req     : Http_Client.Requests.Request;
      Old_Res : Http_Client.Responses.Response;
      New_Res : Http_Client.Responses.Response;
      Hit     : Http_Client.Responses.Response;
      Meta    : Http_Client.Cache.Cache_Metadata;
      T0      : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status  : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/replaced", Req);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "old",
         Old_Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Old_Res, T0)
         = Http_Client.Errors.Ok,
         "old cache entry should store before replacement");
      Assert
        (Http_Client.Cache.Length (Cache) = 1,
         "old cache entry should be retained before non-storeable replacement");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: no-store"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "new",
         New_Res);
      Status := Http_Client.Cache.Store (Cache, Req, New_Res, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Disabled,
         "non-storeable replacement should not be stored");

      Http_Client.Cache.Invalidate (Cache, Req);
      Assert
        (Http_Client.Cache.Length (Cache) = 0,
         "cache-aware execution should invalidate stale entries after non-storeable replacement");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "invalidated non-storeable replacement should not leave old data available");
   end Test_Cache_Nonstoreable_Replacement_Invalidates;

   procedure Test_Cache_304_Metadata_Merge_Refreshes_Freshness

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache        : Http_Client.Cache.Cache_Store;
      Config       : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req          : Http_Client.Requests.Request;
      Res          : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response;
      Hit          : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      T0           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status       : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/merge304", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""old"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "stale validator response should store before 304 merge");

      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=30"
         & ASCII.CR
         & ASCII.LF
         & "Age: 5"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""new"""
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Assert
        (Http_Client.Cache.Update_From_304
           (Cache, Req, Not_Modified, Meta, T0 + 1.0)
         = Http_Client.Errors.Ok,
         "304 metadata merge should succeed");
      Assert
        (Meta.Age_Seconds = 5,
         "304 metadata should report conservative current age after merged Age header");

      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "304-updated entry should be fresh after max-age merge");
      Assert
        (Http_Client.Headers.Get (Http_Client.Responses.Headers (Hit), "ETag")
         = """new""",
         "304 metadata merge should update stored entity tag");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "body",
         "304 metadata merge must preserve cached response body");
   end Test_Cache_304_Metadata_Merge_Refreshes_Freshness;

   procedure Test_Cache_304_Malformed_And_No_Store_Invalidates

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache        : Http_Client.Cache.Cache_Store;
      Config       : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Req          : Http_Client.Requests.Request;
      Res          : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response;
      Hit          : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      T0           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status       : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Build_Cache_Request ("http://example.com/bad304", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""tag"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "entry should store before malformed 304 test");

      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 1"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Assert
        (Http_Client.Cache.Update_From_304
           (Cache, Req, Not_Modified, Meta, T0 + 1.0)
         = Http_Client.Errors.Protocol_Error,
         "304 responses with non-zero body framing must be rejected deterministically");

      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: no-store"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Status :=
        Http_Client.Cache.Update_From_304
          (Cache, Req, Not_Modified, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Invalid_Cache_Metadata,
         "304 no-store metadata should invalidate the stored entry");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 3.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "entry invalidated by 304 no-store should no longer be served");

      Build_Cache_Request ("http://example.com/invalid-vary304", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""tag"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res, T0) = Http_Client.Errors.Ok,
         "entry should store before invalid 304 Vary test");
      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Vary: *"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Status :=
        Http_Client.Cache.Update_From_304
          (Cache, Req, Not_Modified, Meta, T0 + 4.0);
      Assert
        (Status = Http_Client.Errors.Invalid_Cache_Metadata,
         "304 invalid Vary metadata should invalidate the stored entry");
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta, T0 + 5.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "entry invalidated by 304 invalid Vary should no longer be served");
   end Test_Cache_304_Malformed_And_No_Store_Invalidates;

   procedure Test_Cache_304_Vary_Update_Collapses_Duplicate

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache        : Http_Client.Cache.Cache_Store;
      Config       : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      H_En         : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Req_En       : Http_Client.Requests.Request;
      Req_Generic  : Http_Client.Requests.Request;
      Res_En       : Http_Client.Responses.Response;
      Res_Generic  : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response;
      Hit          : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      T0           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status       : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Http_Client.Cache.Initialize (Cache, Config);

      Assert
        (Http_Client.Headers.Set (H_En, "Accept-Language", "en")
         = Http_Client.Errors.Ok,
         "language header should set for Vary-update test");
      Build_Cache_Request ("http://example.com/vary304", Req_En, H_En);
      Build_Cache_Request ("http://example.com/vary304", Req_Generic);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""en"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 2"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "en",
         Res_En);
      Assert
        (Http_Client.Cache.Store (Cache, Req_En, Res_En, T0)
         = Http_Client.Errors.Ok,
         "language-varying entry should store before 304 Vary update");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: User-Agent"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 5"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "other",
         Res_Generic);
      Assert
        (Http_Client.Cache.Store (Cache, Req_Generic, Res_Generic, T0)
         = Http_Client.Errors.Ok,
         "user-agent-varying entry should coexist before 304 Vary update");
      Assert
        (Http_Client.Cache.Length (Cache) = 2,
         "precondition should retain two distinct Vary variants");

      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=30"
         & ASCII.CR
         & ASCII.LF
         & "Vary: User-Agent"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""en-refreshed"""
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);
      Status :=
        Http_Client.Cache.Update_From_304
          (Cache    => Cache,
           Request  => Req_En,
           Response => Not_Modified,
           Metadata => Meta,
           Now      => T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "304 Vary update should refresh the matching entry");
      Assert
        (Http_Client.Cache.Length (Cache) = 1,
         "304 Vary update should collapse equivalent duplicate variants");

      Status :=
        Http_Client.Cache.Lookup (Cache, Req_Generic, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "remaining updated variant should be lookup-compatible after duplicate collapse");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "en",
         "duplicate collapse should keep the revalidated cached body");
      Assert
        (Http_Client.Headers.Get (Http_Client.Responses.Headers (Hit), "ETag")
         = """en-refreshed""",
         "duplicate collapse should keep the revalidated metadata");
   end Test_Cache_304_Vary_Update_Collapses_Duplicate;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Cache");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Cache_Key_Query_And_Fragment'Access,
         "Test_Cache_Key_Query_And_Fragment");
      Register_Routine
        (T,
         Test_Cache_Key_IPv6_Authority_Is_Bracketed'Access,
         "Test_Cache_Key_IPv6_Authority_Is_Bracketed");
      Register_Routine
        (T,
         Test_Cache_Freshness_And_Stale_Transition'Access,
         "Test_Cache_Freshness_And_Stale_Transition");
      Register_Routine
        (T,
         Test_Cache_Expires_Date_Age_And_Invalid_Date'Access,
         "Test_Cache_Expires_Date_Age_And_Invalid_Date");
      Register_Routine
        (T,
         Test_Cache_Date_Apparent_Age_For_Max_Age'Access,
         "Test_Cache_Date_Apparent_Age_For_Max_Age");
      Register_Routine
        (T,
         Test_Cache_Request_Directives'Access,
         "Test_Cache_Request_Directives");
      Register_Routine
        (T,
         Test_Cache_Vary_And_Vary_Star_Rejection'Access,
         "Test_Cache_Vary_And_Vary_Star_Rejection");
      Register_Routine
        (T,
         Test_Cache_Vary_Canonicalization_And_Duplicate_Rejection'Access,
         "Test_Cache_Vary_Canonicalization_And_Duplicate_Rejection");
      Register_Routine
        (T,
         Test_Cache_Max_Stale_Request_Directive'Access,
         "Test_Cache_Max_Stale_Request_Directive");
      Register_Routine
        (T,
         Test_Cache_Eviction_And_Clear'Access,
         "Test_Cache_Eviction_And_Clear");
      Register_Routine
        (T,
         Test_Cache_Conditional_Request_And_304_Update'Access,
         "Test_Cache_Conditional_Request_And_304_Update");
      Register_Routine
        (T,
         Test_Cache_Bypass_Policy_Edges'Access,
         "Test_Cache_Bypass_Policy_Edges");
      Register_Routine
        (T,
         Test_Cache_Nonstoreable_Replacement_Invalidates'Access,
         "Test_Cache_Nonstoreable_Replacement_Invalidates");
      Register_Routine
        (T,
         Test_Cache_304_Metadata_Merge_Refreshes_Freshness'Access,
         "Test_Cache_304_Metadata_Merge_Refreshes_Freshness");
      Register_Routine
        (T,
         Test_Cache_304_Malformed_And_No_Store_Invalidates'Access,
         "Test_Cache_304_Malformed_And_No_Store_Invalidates");
      Register_Routine
        (T,
         Test_Cache_304_Vary_Update_Collapses_Duplicate'Access,
         "Test_Cache_304_Vary_Update_Collapses_Duplicate");
   end Register_Tests;

end Http_Client.Cache.Tests;
