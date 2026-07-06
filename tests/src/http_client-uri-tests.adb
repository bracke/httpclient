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
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;

package body Http_Client.URI.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Errors.Result_Category;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;
   use type Http_Client.URI.TCP_Port;
   use type Http_Client.URI.Host_Kind;
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

   procedure Test_URI_Holder

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : constant Http_Client.URI.URI_Reference :=
        Http_Client.URI.Create_Unchecked ("https://example.invalid/");
   begin
      Assert
        (Http_Client.URI.Image (Item) = "https://example.invalid/",
         "URI holder should return stored unchecked text");

      Assert
        (not Http_Client.URI.Is_Empty (Item),
         "URI holder should not report non-empty text as empty");

      Assert
        (not Http_Client.URI.Is_Parsed (Item),
         "unchecked URI holder should not be reported as parsed");
   end Test_URI_Holder;

   procedure Test_URI_Parse_Basic_HTTP_Host_Only

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("http://example.com", Item, "basic HTTP URI with host only");

      Assert
        (Http_Client.URI.Scheme (Item) = "http",
         "HTTP scheme should be normalized to lowercase");

      Assert
        (Http_Client.URI.Host (Item) = "example.com",
         "host should be parsed from basic HTTP URI");

      Assert
        (not Http_Client.URI.Has_Explicit_Port (Item),
         "basic HTTP URI should not have an explicit port");

      Assert
        (Http_Client.URI.Effective_Port (Item) = 80,
         "HTTP default port should be 80");

      Assert
        (Http_Client.URI.Path (Item) = "/",
         "empty URI path should be normalized to slash");

      Assert
        (Http_Client.URI.Request_Target (Item) = "/",
         "request target for host-only URI should be slash");

      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "example.com",
         "Host header should omit default absent port");
   end Test_URI_Parse_Basic_HTTP_Host_Only;

   procedure Test_URI_Parse_HTTPS_Path

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok ("https://Example.COM/a/b", Item, "HTTPS URI with path");

      Assert
        (Http_Client.URI.Scheme (Item) = "https",
         "HTTPS scheme should be normalized to lowercase");

      Assert
        (Http_Client.URI.Host (Item) = "example.com",
         "host should be normalized to lowercase");

      Assert
        (Http_Client.URI.Path (Item) = "/a/b",
         "HTTPS URI path should be preserved");

      Assert
        (Http_Client.URI.Effective_Port (Item) = 443,
         "HTTPS default port should be 443");

      Assert
        (Http_Client.URI.Requires_TLS (Item),
         "HTTPS URI should require TLS in later phases");
   end Test_URI_Parse_HTTPS_Path;

   procedure Test_URI_Parse_Explicit_Port

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("http://example.com:8080/api",
         Item,
         "HTTP URI with explicit non-default port");

      Assert
        (Http_Client.URI.Has_Explicit_Port (Item),
         "explicit port should be recorded");

      Assert
        (Http_Client.URI.Explicit_Port (Item) = 8080,
         "explicit port should be parsed numerically");

      Assert
        (Http_Client.URI.Effective_Port (Item) = 8080,
         "effective port should use explicit port when present");

      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "example.com:8080",
         "Host header should include non-default explicit port");
   end Test_URI_Parse_Explicit_Port;

   procedure Test_URI_Parse_Query_And_Fragment

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("https://example.com/search?q=ada%202022#section-1",
         Item,
         "URI with query and fragment");

      Assert
        (Http_Client.URI.Has_Query (Item),
         "query marker should be represented");

      Assert
        (Http_Client.URI.Query (Item) = "q=ada%202022",
         "raw query should be preserved without interpreting parameters");

      Assert
        (Http_Client.URI.Has_Fragment (Item),
         "fragment marker should be represented");

      Assert
        (Http_Client.URI.Fragment (Item) = "section-1",
         "raw fragment should be preserved");

      Assert
        (Http_Client.URI.Request_Target (Item) = "/search?q=ada%202022",
         "request target should include query but exclude fragment");
   end Test_URI_Parse_Query_And_Fragment;

   procedure Test_URI_Parse_Empty_Query_And_Fragment

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("http://example.com/path?#",
         Item,
         "URI with empty query and empty fragment");

      Assert
        (Http_Client.URI.Has_Query (Item),
         "empty query after question mark should be represented");

      Assert
        (Http_Client.URI.Query (Item) = "",
         "empty query should be preserved as empty string");

      Assert
        (Http_Client.URI.Has_Fragment (Item),
         "empty fragment after hash should be represented");

      Assert
        (Http_Client.URI.Fragment (Item) = "",
         "empty fragment should be preserved as empty string");

      Assert
        (Http_Client.URI.Request_Target (Item) = "/path?",
         "request target should preserve an explicitly empty query");
   end Test_URI_Parse_Empty_Query_And_Fragment;

   procedure Test_URI_Parse_Percent_Escaped_Path_And_Query

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("http://example.com/a%20b?x=%2F",
         Item,
         "URI with valid percent escapes in path and query");

      Assert
        (Http_Client.URI.Path (Item) = "/a%20b",
         "percent escapes in path should be preserved raw");

      Assert
        (Http_Client.URI.Query (Item) = "x=%2F",
         "percent escapes in query should be preserved raw");
   end Test_URI_Parse_Percent_Escaped_Path_And_Query;

   procedure Test_URI_Percent_Encodes_Raw_UTF8_Path_Query_And_Fragment

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item    : Http_Client.URI.URI_Reference;
      Thorn   : constant String := Character'Val (16#C3#) & Character'Val (16#BE#);
      Eth     : constant String := Character'Val (16#C3#) & Character'Val (16#B0#);
      O_Acute : constant String := Character'Val (16#C3#) & Character'Val (16#B3#);
      URL     : constant String :=
        "http://example.com/" & Thorn & "orkell-gu" & Eth & "j" & O_Acute
        & "nsson.jpg?name=" & Thorn & O_Acute & "r#hluti-" & O_Acute;
   begin
      Assert_Parse_Ok
        (URL,
         Item,
         "URI with raw UTF-8 bytes in path, query, and fragment");

      Assert
        (Http_Client.URI.Path (Item) = "/%C3%BEorkell-gu%C3%B0j%C3%B3nsson.jpg",
         "raw UTF-8 path bytes should be percent-encoded");

      Assert
        (Http_Client.URI.Query (Item) = "name=%C3%BE%C3%B3r",
         "raw UTF-8 query bytes should be percent-encoded");

      Assert
        (Http_Client.URI.Fragment (Item) = "hluti-%C3%B3",
         "raw UTF-8 fragment bytes should be percent-encoded");

      Assert
        (Http_Client.URI.Request_Target (Item)
         = "/%C3%BEorkell-gu%C3%B0j%C3%B3nsson.jpg?name=%C3%BE%C3%B3r",
         "request target should use percent-encoded path and query");
   end Test_URI_Percent_Encodes_Raw_UTF8_Path_Query_And_Fragment;

   procedure Test_URI_Converts_Raw_UTF8_Host_To_IDNA

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item        : Http_Client.URI.URI_Reference;
      U_Umlaut    : constant String := Character'Val (16#C3#) & Character'Val (16#BC#);
      Invalid_UTF8 : constant String := Character'Val (16#C3#) & "x";
   begin
      Assert_Parse_Ok
        ("http://b" & U_Umlaut & "cher.example/path",
         Item,
         "URI with raw UTF-8 DNS label");

      Assert
        (Http_Client.URI.Host (Item) = "xn--bcher-kva.example",
         "raw UTF-8 DNS label should be converted to punycode");

      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "xn--bcher-kva.example",
         "Host header should use the IDNA ASCII hostname");

      Assert
        (Http_Client.URI.Image (Item) = "http://xn--bcher-kva.example/path",
         "URI image should use the IDNA ASCII hostname");

      Assert_Parse_Status
        ("http://" & Invalid_UTF8 & ".example/",
         Http_Client.Errors.Invalid_URI,
         "malformed raw UTF-8 hostname should be rejected");
   end Test_URI_Converts_Raw_UTF8_Host_To_IDNA;

   procedure Test_URI_Host_Validation_Helpers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      U_Umlaut : constant String := Character'Val (16#C3#) & Character'Val (16#BC#);
   begin
      Assert
        (Http_Client.URI.Raw_Authority_Host_Has_Non_ASCII
           ("http://b" & U_Umlaut & "cher.example/path"),
         "raw non-ASCII URI authority host should be detected before IDNA conversion");
      Assert
        (Http_Client.URI.Raw_Authority_Host_Has_Non_ASCII
           ("user:pass@b" & U_Umlaut & "cher.example:8080"),
         "raw non-ASCII authority host should be detected with userinfo and port");
      Assert
        (not Http_Client.URI.Raw_Authority_Host_Has_Non_ASCII
           ("http://xn--bcher-kva.example/path"),
         "punycode ASCII host should not be reported as raw non-ASCII");

      Assert (Http_Client.URI.Is_Valid_ASCII_Host ("example.com"), "DNS host should be valid");
      Assert
        (Http_Client.URI.Kind_Of_ASCII_Host ("example.com") = Http_Client.URI.DNS_Name,
         "DNS host kind should be reported");
      Assert
        (Http_Client.URI.Is_Valid_ASCII_Host ("xn--bcher-kva.example"),
         "punycode host should be valid");
      Assert (Http_Client.URI.Is_Valid_ASCII_Host ("192.0.2.1"), "IPv4 host should be valid");
      Assert
        (Http_Client.URI.Kind_Of_ASCII_Host ("192.0.2.1") = Http_Client.URI.IPv4_Literal,
         "IPv4 host kind should be reported");
      Assert
        (Http_Client.URI.Is_Valid_ASCII_Host ("2001:db8::1"),
         "unbracketed IPv6 host should be valid");
      Assert
        (Http_Client.URI.Kind_Of_ASCII_Host ("2001:db8::1") = Http_Client.URI.IPv6_Literal,
         "IPv6 host kind should be reported");
      Assert
        (not Http_Client.URI.Is_Valid_ASCII_Host ("bad_host.example"),
         "underscore host should be invalid");
      Assert
        (not Http_Client.URI.Is_Valid_ASCII_Host ("-bad.example"),
         "leading hyphen label should be invalid");
      Assert
        (not Http_Client.URI.Is_Valid_ASCII_Host ("bad-.example"),
         "trailing hyphen label should be invalid");
      Assert
        (not Http_Client.URI.Is_Valid_ASCII_Host ("bad..example"),
         "empty label should be invalid");
      Assert
        (not Http_Client.URI.Is_Valid_ASCII_Host ("b" & U_Umlaut & "cher.example"),
         "raw non-ASCII host should be invalid without IDNA conversion");
   end Test_URI_Host_Validation_Helpers;

   procedure Test_URI_Parse_IPv4_Literal

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok
        ("http://192.0.2.10/resource",
         Item,
         "HTTP URI with IPv4 literal host");

      Assert
        (Http_Client.URI.Host (Item) = "192.0.2.10",
         "IPv4 literal host should be preserved");

      Assert
        (Http_Client.URI.Request_Target (Item) = "/resource",
         "IPv4 literal URI should expose the path as request target");
   end Test_URI_Parse_IPv4_Literal;

   procedure Test_URI_Parse_IPv6_Literals
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Item : Http_Client.URI.URI_Reference;
   begin
      Assert_Parse_Ok ("http://[::1]/", Item, "IPv6 loopback URI");
      Assert (Http_Client.URI.Host (Item) = "::1", "IPv6 host should be stored without brackets");
      Assert (Http_Client.URI.Kind_Of_Host (Item) = Http_Client.URI.IPv6_Literal, "IPv6 host kind should be exposed");
      Assert (Http_Client.URI.Authority_Host (Item) = "[::1]", "IPv6 authority host should be bracketed");
      Assert
        (Http_Client.URI.Image (Item) = "http://[::1]/",
         "IPv6 URI image should be bracketed");
      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "[::1]",
         "IPv6 Host header should be bracketed");

      Assert_Parse_Ok
        ("http://[::1]:8080/a?b=c", Item,
         "IPv6 URI with port and query");
      Assert
        (Http_Client.URI.Host (Item) = "::1",
         "IPv6 host should remain unbracketed with port");
      Assert
        (Http_Client.URI.Explicit_Port (Item) = 8080,
         "IPv6 explicit port should parse");
      Assert
        (Http_Client.URI.Request_Target (Item) = "/a?b=c",
         "IPv6 request target should preserve path and query");
      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "[::1]:8080",
         "IPv6 Host header should include non-default port");
      Assert
        (Http_Client.URI.Image (Item) = "http://[::1]:8080/a?b=c",
         "IPv6 image should include bracketed port authority");

      Assert_Parse_Ok
        ("http://[2001:db8::1]/path", Item,
         "HTTP IPv6 URI with path");
      Assert
        (Http_Client.URI.Host (Item) = "2001:db8::1",
         "IPv6 documentation prefix should parse");
      Assert
        (Http_Client.URI.Request_Target (Item) = "/path",
         "IPv6 path should parse");
      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "[2001:db8::1]",
         "HTTP IPv6 Host header should omit default port");

      Assert_Parse_Ok
        ("https://[2001:db8::1]:8443/a?b=c", Item,
         "HTTPS IPv6 URI with explicit port");
      Assert
        (Http_Client.URI.Host (Item) = "2001:db8::1",
         "IPv6 documentation prefix should parse for HTTPS");
      Assert
        (Http_Client.URI.Host_Header_Value (Item) = "[2001:db8::1]:8443",
         "HTTPS IPv6 Host header should be bracketed");

      Assert_Parse_Ok
        ("http://[2001:db8:0:0:0:0:2:1]/", Item,
         "full IPv6 literal URI");
      Assert
        (Http_Client.URI.Host (Item) = "2001:db8:0:0:0:0:2:1",
         "full IPv6 host should be preserved");

      Assert_Parse_Ok
        ("http://[::ffff:192.0.2.128]/", Item,
         "IPv6 literal with embedded IPv4 tail");
      Assert
        (Http_Client.URI.Host (Item) = "::ffff:192.0.2.128",
         "embedded IPv4 tail should be preserved");
   end Test_URI_Parse_IPv6_Literals;

   procedure Test_URI_Rejects_Malformed_IPv6_Literals
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      use Http_Client.Errors;
   begin
      Assert_Parse_Status
        ("http://::1/", Invalid_URI,
         "bracketless IPv6 authority should be rejected");
      Assert_Parse_Status
        ("http://[::1", Invalid_URI,
         "missing IPv6 closing bracket should be rejected");
      Assert_Parse_Status
        ("http://[::1]bad/", Invalid_URI,
         "IPv6 bracket suffix should be rejected");
      Assert_Parse_Status
        ("http://[::1]:bad/", Invalid_URI,
         "IPv6 non-numeric port should be rejected");
      Assert_Parse_Status
        ("http://[::1]:999999/", Invalid_URI,
         "IPv6 out-of-range port should be rejected");
      Assert_Parse_Status
        ("http://[]/", Invalid_URI,
         "empty IPv6 literal should be rejected");
      Assert_Parse_Status
        ("http://[not-ipv6]/", Invalid_URI,
         "non-IPv6 bracketed host should be rejected");
      Assert_Parse_Status
        ("http://[2001:db8:::1]/", Invalid_URI,
         "triple colon IPv6 literal should be rejected");
      Assert_Parse_Status
        ("http://[2001:db8::1%lo0]/", Invalid_URI,
         "IPv6 zone identifier should be rejected");
      Assert_Parse_Status
        ("http://[fe80::1%25lo0]/", Invalid_URI,
         "percent-encoded IPv6 zone identifier should be rejected");
   end Test_URI_Rejects_Malformed_IPv6_Literals;

   procedure Test_HTTP1_IPv6_Authority_Formatting
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert_Parse_Ok ("http://[::1]:8080/path", URI, "HTTP/1 IPv6 request URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method => Http_Client.Types.GET,
           URI    => URI,
           Item   => Request);
      Assert (Status = Http_Client.Errors.Ok, "IPv6 request should build");

      Status :=
        Http_Client.HTTP1.Serialize_Request
          (Request     => Request,
           Output      => Output,
           Target_Mode => Http_Client.HTTP1.Absolute_Form);
      Assert (Status = Http_Client.Errors.Ok, "IPv6 absolute-form serialization should succeed");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "GET http://[::1]:8080/path HTTP/1.1") /= 0,
         "absolute-form request target should bracket IPv6 authority");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Output),
            "Host: [::1]:8080") /= 0,
         "Host header should bracket IPv6 authority");
   end Test_HTTP1_IPv6_Authority_Formatting;

   procedure Test_URI_Invalid_And_Unsupported_Forms
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      use Http_Client.Errors;

      Overlong_Label : constant String := [1 .. 64 => 'a'];
      Max_Label      : constant String := [1 .. 63 => 'b'];
   begin
      Assert_Parse_Status ("example.com/path", Invalid_URI, "missing scheme");

      Assert_Parse_Status
        ("ftp://example.com/", Unsupported_Feature, "unsupported ftp scheme");

      Assert_Parse_Status
        ("h ttp://example.com/", Invalid_URI, "scheme containing whitespace");

      Assert_Parse_Status
        ("1http://example.com/", Invalid_URI, "scheme beginning with a digit");

      Assert_Parse_Status ("http:///path", Invalid_URI, "empty host");

      Assert_Parse_Status ("http://example.com:", Invalid_URI, "empty port");

      Assert_Parse_Status
        ("http://example.com:abc/", Invalid_URI, "non-numeric port");

      Assert_Parse_Status
        ("http://example.com:-1/", Invalid_URI, "negative port");

      Assert_Parse_Status ("http://example.com:0/", Invalid_URI, "zero port");

      Assert_Parse_Status
        ("http://example.com:65536/", Invalid_URI, "out-of-range port");

      Assert_Parse_Status
        ("http://exa mple.com/", Invalid_URI, "whitespace in host");

      Assert_Parse_Status
        ("http://" & Overlong_Label & ".example/",
         Invalid_URI,
         "DNS host label longer than 63 octets should be rejected");

      Assert_Parse_Status
        ("http://"
         & Max_Label
         & "."
         & Max_Label
         & "."
         & Max_Label
         & "."
         & Max_Label
         & "/",
         Invalid_URI,
         "DNS host longer than 253 octets should be rejected");

      Assert_Parse_Status
        ("http://999.1.2.3/", Invalid_URI, "IPv4 literal octet above 255");

      Assert_Parse_Status
        ("http://1.2.3./",
         Invalid_URI,
         "IPv4-like host with empty final octet");

      Assert_Parse_Status
        ("http://example.com/a b", Invalid_URI, "unescaped space in path");

      Assert_Parse_Status
        ("http://example.com/%xz",
         Invalid_URI,
         "malformed percent escape in path");

      Assert_Parse_Status
        ("http://example.com/" & Character'Val (10),
         Invalid_URI,
         "control character in URI text");

      Assert_Parse_Status
        ("http://example.com/?q=%",
         Invalid_URI,
         "truncated percent escape in query");

      Assert_Parse_Status
        ("http://user:pass@example.com/",
         Unsupported_Feature,
         "userinfo should not be accepted in the current URI layer");

      Assert_Parse_Status
        ("http://[2001:db8::1/", Invalid_URI, "missing closing IPv6 bracket");

      Assert_Parse_Status
        ("http://[2001:db8:::1]/",
         Invalid_URI,
         "malformed bracketed IPv6 literal should be rejected");

      Assert_Parse_Status
        ("/relative/path",
         Invalid_URI,
         "relative path should not be accepted as absolute URI");
   end Test_URI_Invalid_And_Unsupported_Forms;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("URI");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_URI_Holder'Access, "Test_URI_Holder");
      Register_Routine
        (T,
         Test_URI_Parse_Basic_HTTP_Host_Only'Access,
         "Test_URI_Parse_Basic_HTTP_Host_Only");
      Register_Routine
        (T,
         Test_URI_Parse_HTTPS_Path'Access,
         "Test_URI_Parse_HTTPS_Path");
      Register_Routine
        (T,
         Test_URI_Parse_Explicit_Port'Access,
         "Test_URI_Parse_Explicit_Port");
      Register_Routine
        (T,
         Test_URI_Parse_Query_And_Fragment'Access,
         "Test_URI_Parse_Query_And_Fragment");
      Register_Routine
        (T,
         Test_URI_Parse_Empty_Query_And_Fragment'Access,
         "Test_URI_Parse_Empty_Query_And_Fragment");
      Register_Routine
        (T,
         Test_URI_Parse_Percent_Escaped_Path_And_Query'Access,
         "Test_URI_Parse_Percent_Escaped_Path_And_Query");
      Register_Routine
        (T,
         Test_URI_Percent_Encodes_Raw_UTF8_Path_Query_And_Fragment'Access,
         "Test_URI_Percent_Encodes_Raw_UTF8_Path_Query_And_Fragment");
      Register_Routine
        (T,
         Test_URI_Converts_Raw_UTF8_Host_To_IDNA'Access,
         "Test_URI_Converts_Raw_UTF8_Host_To_IDNA");
      Register_Routine
        (T,
         Test_URI_Host_Validation_Helpers'Access,
         "Test_URI_Host_Validation_Helpers");
      Register_Routine
        (T,
         Test_URI_Parse_IPv4_Literal'Access,
         "Test_URI_Parse_IPv4_Literal");
      Register_Routine
        (T,
         Test_URI_Parse_IPv6_Literals'Access,
         "Test_URI_Parse_IPv6_Literals");
      Register_Routine
        (T,
         Test_URI_Rejects_Malformed_IPv6_Literals'Access,
         "Test_URI_Rejects_Malformed_IPv6_Literals");
      Register_Routine
        (T,
         Test_HTTP1_IPv6_Authority_Formatting'Access,
         "Test_HTTP1_IPv6_Authority_Formatting");
      Register_Routine
        (T,
         Test_URI_Invalid_And_Unsupported_Forms'Access,
         "Test_URI_Invalid_And_Unsupported_Forms");
   end Register_Tests;

end Http_Client.URI.Tests;
