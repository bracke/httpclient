with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Auth.Bearer;
with Http_Client.Auth.Digest;
with Http_Client.Alt_Svc;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
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
with Http_Client.Proxies;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Conformance.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.HTTP3.HTTP3_Mode;
   use type Http_Client.QUIC.Backend_Availability;

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

   procedure Test_Phase35_Conformance_Fixture_Vectors

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);

      procedure Check_URI
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
            Message
            & ": expected "
            & Http_Client.Errors.Result_Status'Image (Expected)
            & ", got "
            & Http_Client.Errors.Result_Status'Image (Status));
      end Check_URI;

      procedure Check_Response
        (Raw      : String;
         Expected : Http_Client.Errors.Result_Status;
         Message  : String)
      is
         Response : Http_Client.Responses.Response;
         Status   : constant Http_Client.Errors.Result_Status :=
           Http_Client.Responses.Parse_Response (Raw, Response);
      begin
         Assert
           (Status = Expected,
            Message
            & ": expected "
            & Http_Client.Errors.Result_Status'Image (Expected)
            & ", got "
            & Http_Client.Errors.Result_Status'Image (Status));
      end Check_Response;

      procedure Check_Cookie
        (Header   : String;
         Expected : Http_Client.Errors.Result_Status;
         Message  : String)
      is
         Origin : Http_Client.URI.URI_Reference;
         Cookie : Http_Client.Cookies.Cookie;
         Status : Http_Client.Errors.Result_Status;
      begin
         Status :=
           Http_Client.URI.Parse
             ("https://example.com/account/index.html", Origin);
         Assert
           (Status = Http_Client.Errors.Ok,
            "phase35 cookie test setup should parse origin URI");

         Status :=
           Http_Client.Cookies.Parse_Set_Cookie
             (Header,
              Origin,
              Cookie,
              Now => Ada.Calendar.Time_Of (2026, 5, 14, 12.0));
         Assert
           (Status = Expected,
            Message
            & ": expected "
            & Http_Client.Errors.Result_Status'Image (Expected)
            & ", got "
            & Http_Client.Errors.Result_Status'Image (Status));
      end Check_Cookie;

      H3_Options       : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      Digest_Challenge : Http_Client.Auth.Digest.Challenge;
   begin
      --  Conformance vectors stay local, deterministic, and
      --  deliberately small. These tests complement tests/fixtures/* and never
      --  require DNS, network access, public services, credentials, or live
      --  timing behavior.
      Assert
        (Http_Client.Auth.Base64_Encode ("phase35") = "cGhhc2UzNQ==",
         "phase35 Base64 fixture should preserve RFC padding behavior");
      Assert
        (Http_Client.Auth.Basic_Authorization_Value ("phase35", "interop")
         = "Basic cGhhc2UzNTppbnRlcm9w",
         "phase35 Basic auth fixture should produce deterministic header value");
      Assert
        (not Http_Client.Auth.Bearer.Is_Valid_Token
               ("token" & Character'Val (10) & "injected"),
         "phase35 Bearer fixture should reject line-injected tokens");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""phase35"", nonce=""n"", algorithm=SHA-512",
            Digest_Challenge)
         = Http_Client.Errors.Digest_Algorithm_Unsupported,
         "phase35 Digest fixture should reject unsupported algorithms");

      Check_URI
        ("http://example.com/",
         Http_Client.Errors.Ok,
         "phase35 URI fixture should accept basic http origin");
      Check_URI
        ("https://Example.COM:443/path?q=1#frag",
         Http_Client.Errors.Ok,
         "phase35 URI fixture should accept HTTPS with query and fragment");
      Check_URI
        ("http://127.0.0.1:8080/a/b?empty=",
         Http_Client.Errors.Ok,
         "phase35 URI fixture should accept IPv4 literal with explicit port");
      Check_URI
        ("http://",
         Http_Client.Errors.Invalid_URI,
         "phase35 URI fixture should reject missing authority");
      Check_URI
        ("ftp://example.com/",
         Http_Client.Errors.Unsupported_Feature,
         "phase35 URI fixture should reject unsupported scheme explicitly");
      Check_URI
        ("http://[::1]/",
         Http_Client.Errors.Ok,
         "phase17 URI fixture should accept bracketed IPv6 literals");

      Check_Response
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Content-Length: 5"
         & CRLF
         & CRLF
         & "hello",
         Http_Client.Errors.Ok,
         "phase35 HTTP/1 fixture should accept exact fixed-length body");
      Check_Response
        ("HTTP/1.0 204 No Content" & CRLF & CRLF,
         Http_Client.Errors.Ok,
         "phase35 HTTP/1 fixture should accept no-body 204 response");
      Check_Response
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 5" & CRLF & CRLF & "abc",
         Http_Client.Errors.Incomplete_Message,
         "phase35 HTTP/1 fixture should classify truncated body");
      Check_Response
        ("HTTP/1.1 200 OK" & CRLF & "Bad Header" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "phase35 HTTP/1 fixture should classify malformed header");
      Check_Response
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Transfer-Encoding: chunked"
         & CRLF
         & CRLF
         & "0"
         & CRLF
         & CRLF,
         Http_Client.Errors.Unsupported_Feature,
         "buffered response parser rejects raw chunked transfer framing");
      Check_Response
        ("HTTP/1.1 200 OK" & CRLF & "Content-Length: bad" & CRLF & CRLF,
         Http_Client.Errors.Invalid_Header,
         "phase35 HTTP/1 fixture should classify invalid Content-Length");
      Check_Response
        ("HTTP/1.1 200 OK"
         & CRLF
         & "Content-Length: 1"
         & CRLF
         & "Content-Length: 2"
         & CRLF
         & CRLF
         & "xy",
         Http_Client.Errors.Invalid_Header,
         "phase35 HTTP/1 fixture should reject conflicting Content-Length fields");

      Check_Cookie
        ("sid=abc; Path=/account; Secure; HttpOnly; SameSite=Lax",
         Http_Client.Errors.Ok,
         "phase35 cookie fixture should accept common secure host-only cookie");
      Check_Cookie
        ("sid=abc; Domain=other.example; Path=/",
         Http_Client.Errors.Cookie_Rejected,
         "phase35 cookie fixture should reject unrelated Domain attribute");
      Check_Cookie
        ("__Host-sid=abc; Secure; Domain=example.com; Path=/",
         Http_Client.Errors.Cookie_Rejected,
         "phase35 cookie fixture should enforce __Host prefix constraints");
      Check_Cookie
        ("bad cookie",
         Http_Client.Errors.Invalid_Cookie,
         "phase35 cookie fixture should reject missing name/value separator");

      H3_Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      H3_Options.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;
      Assert
        (Http_Client.HTTP3.Execution_Status (H3_Options)
         = Http_Client.Errors.QUIC_Unsupported,
         "phase35 HTTP/3 fixture should report unavailable QUIC backend without fallback magic");
      Assert
        (Http_Client.HTTP3.Execution_Status
           (H3_Options, Proxy_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "phase35 HTTP/3 fixture should reject HTTP proxy before QUIC execution");
      Assert
        (Http_Client.HTTP3.Execution_Status
           (H3_Options, SOCKS_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "phase35 HTTP/3 fixture should reject SOCKS proxy before QUIC execution");
   end Test_Phase35_Conformance_Fixture_Vectors;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Conformance");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Phase35_Conformance_Fixture_Vectors'Access,
         "Test_Phase35_Conformance_Fixture_Vectors");
   end Register_Tests;

end Http_Client.Conformance.Tests;
