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
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Resources.Tests is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
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

   procedure Test_Cookies_Max_Age_And_Header_Limit_Edges

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Target  : Http_Client.URI.URI_Reference;
      Cookie  : Http_Client.Cookies.Cookie;
      Jar     : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar
          ((Max_Cookies              => 10,
            Max_Cookies_Per_Domain   => 10,
            Max_Name_Length          => 256,
            Max_Value_Length         => 4_096,
            Max_Cookie_Header_Length => 3));
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
      Now     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 1, 1);
   begin
      Assert_Parse_Ok
        ("https://example.com/path/page",
         URI,
         "cookie origin should parse for Max-Age edge tests");
      Assert_Parse_Ok
        ("https://example.com/path/child",
         Target,
         "cookie target should parse for header-size edge tests");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=x; Max-Age=+1", URI, Cookie, Now => Now)
         = Http_Client.Errors.Invalid_Cookie,
         "Max-Age with an explicit plus sign should be rejected conservatively");

      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           ("sid=x; Max-Age=abc", URI, Cookie, Now => Now)
         = Http_Client.Errors.Invalid_Cookie,
         "non-decimal Max-Age should be rejected");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "long=value; Path=/path"),
         "cookie exceeding generated header limit should still be storable");
      Http_Client.Cookies.Store_From_Response
        (Jar, URI, Headers, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "storing a cookie should not depend on outbound header cap");
      Assert
        (Http_Client.Cookies.Length (Jar) = 1,
         "cookie should be retained even when later header generation is capped");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Target) = "",
         "generated Cookie header should be suppressed when it exceeds cap");
   end Test_Cookies_Max_Age_And_Header_Limit_Edges;

   procedure Test_Cookie_Jar_Case_Sensitive_Names_Replacement_And_Limits

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin        : Http_Client.URI.URI_Reference;
      Target        : Http_Client.URI.URI_Reference;
      Jar           : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Limited_Value : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar
          ((Max_Cookies              => 1,
            Max_Cookies_Per_Domain   => 1,
            Max_Name_Length          => 256,
            Max_Value_Length         => 4_096,
            Max_Cookie_Header_Length => 16_384));
      Headers       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Status        : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/root/page",
         Origin,
         "origin URI should parse for replacement tests");
      Assert_Parse_Ok
        ("https://example.com/root/child",
         Target,
         "target URI should parse for replacement tests");

      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "SID=upper; Path=/root"),
         "uppercase cookie name should be representable");
      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "sid=lower; Path=/root"),
         "lowercase cookie name should be representable");

      Http_Client.Cookies.Store_From_Response
        (Jar, Origin, Headers, Status => Status);

      Assert
        (Status = Http_Client.Errors.Ok,
         "case-distinct cookies should store successfully");
      Assert
        (Http_Client.Cookies.Length (Jar) = 2,
         "cookie names are case-sensitive and should not replace each other");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Target)
         = "SID=upper; sid=lower",
         "case-distinct cookies should retain deterministic creation order");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add
           (Headers, "Set-Cookie", "sid=new; Path=/root"),
         "same-name replacement cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Jar, Origin, Headers, Status => Status);

      Assert
        (Http_Client.Cookies.Length (Jar) = 2,
         "same name/domain/path cookie should replace rather than append");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Jar, Target)
         = "SID=upper; sid=new",
         "replacement should preserve original creation order for that key");

      Http_Client.Cookies.Clear (Jar);
      Assert
        (Http_Client.Cookies.Length (Jar) = 0,
         "Clear should remove all cookies");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "a=1; Path=/"),
         "first limited cookie should be representable");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "b=2; Path=/"),
         "second limited cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Limited_Value, Origin, Headers, Status => Status);

      Assert
        (Http_Client.Cookies.Length (Limited_Value) = 1,
         "configured jar limit should deterministically evict oldest cookie");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Limited_Value, Target) = "b=2",
         "limited jar should retain the newest cookie after eviction");
   end Test_Cookie_Jar_Case_Sensitive_Names_Replacement_And_Limits;

   procedure Test_Cookies_Limits_And_Strict_Store_Behavior

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Origin        : Http_Client.URI.URI_Reference;
      Target        : Http_Client.URI.URI_Reference;
      Cookie        : Http_Client.Cookies.Cookie;
      Limited_Value : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar
          ((Max_Cookies              => 10,
            Max_Cookies_Per_Domain   => 1,
            Max_Name_Length          => 256,
            Max_Value_Length         => 4_096,
            Max_Cookie_Header_Length => 16_384));
      Non_Strict    : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Strict_Jar    : Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Headers       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Status        : Http_Client.Errors.Result_Status;
      Tiny_Limits   : constant Http_Client.Cookies.Cookie_Limits :=
        (Max_Cookies              => 10,
         Max_Cookies_Per_Domain   => 10,
         Max_Name_Length          => 3,
         Max_Value_Length         => 3,
         Max_Cookie_Header_Length => 16_384);
   begin
      Assert_Parse_Ok
        ("https://example.com/root/page",
         Origin,
         "origin URI should parse for limit and strict-store tests");
      Assert_Parse_Ok
        ("https://example.com/root/child",
         Target,
         "target URI should parse for per-domain limit tests");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("abcd=x", Origin, Cookie, Limits => Tiny_Limits);
      Assert
        (Status = Http_Client.Errors.Cookie_Too_Large,
         "cookie names beyond the configured limit should be rejected deterministically");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("abc=toolong", Origin, Cookie, Limits => Tiny_Limits);
      Assert
        (Status = Http_Client.Errors.Cookie_Too_Large,
         "cookie values beyond the configured limit should be rejected deterministically");

      Status :=
        Http_Client.Cookies.Parse_Set_Cookie
          ("empty=; Path=/root", Origin, Cookie);
      Assert
        (Status = Http_Client.Errors.Ok,
         "empty cookie values should be valid ordinary cookie values");
      Assert
        (Http_Client.Cookies.Value (Cookie) = "",
         "empty cookie values should be stored as an empty string");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "a=1; Path=/root"),
         "first per-domain-limited cookie should be representable");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "b=2; Path=/root"),
         "second per-domain-limited cookie should be representable");
      Http_Client.Cookies.Store_From_Response
        (Limited_Value, Origin, Headers, Status => Status);
      Assert
        (Status = Http_Client.Errors.Ok,
         "per-domain limit storage should complete in non-strict mode");
      Assert
        (Http_Client.Cookies.Length (Limited_Value) = 1,
         "per-domain limit should evict the oldest cookie for that domain");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Limited_Value, Target) = "b=2",
         "per-domain limit should retain the newest cookie for that domain");

      Http_Client.Headers.Clear (Headers);
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "bad"),
         "malformed Set-Cookie text should still be storable as a generic response header");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Set-Cookie", "ok=1; Path=/root"),
         "valid Set-Cookie after malformed one should be representable");

      Http_Client.Cookies.Store_From_Response
        (Non_Strict, Origin, Headers, Strict => False, Status => Status);
      Assert
        (Status = Http_Client.Errors.Ok,
         "non-strict cookie storage should ignore malformed cookies and continue");
      Assert
        (Http_Client.Cookies.Get_Cookie_Header (Non_Strict, Target) = "ok=1",
         "non-strict cookie storage should keep later valid Set-Cookie fields");

      Http_Client.Cookies.Store_From_Response
        (Strict_Jar, Origin, Headers, Strict => True, Status => Status);
      Assert
        (Status = Http_Client.Errors.Invalid_Cookie,
         "strict cookie storage should report the first malformed Set-Cookie field");
      Assert
        (Http_Client.Cookies.Length (Strict_Jar) = 0,
         "strict cookie storage should stop before later Set-Cookie fields after an error");
   end Test_Cookies_Limits_And_Strict_Store_Behavior;

   procedure Test_High_Level_Client_Invalid_Limit_Relationships

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
   begin
      Config.Execution.Max_Header_Size := 128;
      Config.Execution.Max_Header_Line_Size := 256;

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "header line limit larger than total header limit should be rejected");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Execution.Max_Response_Size := 512;
      Config.Execution.Max_Body_Size := 1024;

      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "body limit larger than total response limit should be rejected");
   end Test_High_Level_Client_Invalid_Limit_Relationships;

   procedure Test_Response_Stream_Body_Limit_Before_Return

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 6" & CRLF & CRLF;

      task type Limit_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Limit_Server;

      task body Limit_Server is
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
      end Limit_Server;

      Server  : Limit_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
   begin
      Server.Ready (Port);
      Options.Max_Body_Size := 5;
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/too-large",
         URI,
         "streaming body-limit URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming body-limit request should construct");
      Assert
        (Http_Client.Response_Streams.Open (Request, Stream, Options)
         = Http_Client.Errors.Response_Too_Large,
         "streaming Content-Length larger than configured limit should fail before return");
      Assert
        (not Http_Client.Response_Streams.Is_Open (Stream),
         "body-limit failure should leave no open stream");
   end Test_Response_Stream_Body_Limit_Before_Return;

   procedure Test_Connection_Pool_Key_And_Limits

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_A   : Http_Client.URI.URI_Reference;
      URI_B   : Http_Client.URI.URI_Reference;
      Status  : Http_Client.Errors.Result_Status;
      Options : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Pool    : Http_Client.Connection_Pools.Connection_Pool;
      Key_A   : Http_Client.Connection_Pools.Pool_Key;
      Key_A2  : Http_Client.Connection_Pools.Pool_Key;
      Key_B   : Http_Client.Connection_Pools.Pool_Key;
      Token   : Http_Client.Connection_Pools.Pool_Token;
      Reused  : Boolean := False;
   begin
      Status := Http_Client.URI.Parse ("http://example.test/a", URI_A);
      Assert (Status = Http_Client.Errors.Ok, "pool test URI A should parse");
      Status := Http_Client.URI.Parse ("http://example.test:81/a", URI_B);
      Assert (Status = Http_Client.Errors.Ok, "pool test URI B should parse");

      Key_A := Http_Client.Connection_Pools.Key_For (URI_A);
      Key_A2 := Http_Client.Connection_Pools.Key_For (URI_A);
      Key_B := Http_Client.Connection_Pools.Key_For (URI_B);

      Assert
        (Http_Client.Connection_Pools.Is_Valid (Key_A),
         "pool key should be valid for parsed http URI");
      Assert
        (Http_Client.Connection_Pools.Same_Key (Key_A, Key_A2),
         "same URI and config should produce same pool key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_A, Key_B),
         "different effective ports must not share pool key");

      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 2;
      Options.Max_Idle_Connections_Per_Key := 1;
      Options.Max_Requests_Per_Connection := 10;
      Http_Client.Connection_Pools.Initialize (Pool, Options);

      Assert
        (Http_Client.Connection_Pools.Register_Fresh_Idle (Pool, Key_A)
         = Http_Client.Errors.Ok,
         "registering first idle connection should succeed");
      Assert
        (Http_Client.Connection_Pools.Register_Fresh_Idle (Pool, Key_A)
         = Http_Client.Errors.Ok,
         "registering second same-key idle connection should enforce per-key limit");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool, Key_A) = 1,
         "per-key idle limit should retain one entry");

      Assert
        (Http_Client.Connection_Pools.Check_Out (Pool, Key_A, Token, Reused)
         = Http_Client.Errors.Ok,
         "checkout should succeed");
      Assert (Reused, "checkout should reuse the retained idle entry");
      Assert
        (Http_Client.Connection_Pools.Is_Valid (Token),
         "reused checkout should return valid token");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool) = 0,
         "checked-out entry should leave idle list");
      Assert
        (Http_Client.Connection_Pools.Check_In (Pool, Token, Reusable => True)
         = Http_Client.Errors.Ok,
         "checkin should succeed");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool) = 1,
         "checked-in reusable entry should be idle again");
   end Test_Connection_Pool_Key_And_Limits;

   procedure Test_Persistent_Cache_Cleanup_And_Limits

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir         : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_d");
      Store       : Http_Client.Cache.Persistent.Persistent_Store;
      Config      : constant Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir,
           Create_If_Missing        => True,
           Max_Total_Stored_Bytes   => 32,
           Max_Body_Bytes_Per_Entry => 16);
      Req         : Http_Client.Requests.Request;
      Res         : Http_Client.Responses.Response;
      F           : Ada.Text_IO.File_Type;
      Status      : Http_Client.Errors.Result_Status;
      Temp_Name   : constant String := "0123456789abcdef.body.tmp";
      Backup_Name : constant String := "0123456789abcdef.meta.2.tmp";
      Orphan_Name : constant String := "fedcba9876543210.body";
   begin
      Remove_Test_Directory (Dir);
      Ada.Directories.Create_Path (Dir);
      Ada.Text_IO.Create
        (F, Ada.Text_IO.Out_File, Ada.Directories.Compose (Dir, Temp_Name));
      Ada.Text_IO.Put_Line (F, "partial");
      Ada.Text_IO.Close (F);
      Ada.Text_IO.Create
        (F, Ada.Text_IO.Out_File, Ada.Directories.Compose (Dir, Backup_Name));
      Ada.Text_IO.Put_Line (F, "staged-old-meta");
      Ada.Text_IO.Close (F);
      Ada.Text_IO.Create
        (F, Ada.Text_IO.Out_File, Ada.Directories.Compose (Dir, Orphan_Name));
      Ada.Text_IO.Put_Line (F, "orphan");
      Ada.Text_IO.Close (F);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should open while cleaning stale files");
      Assert
        (not Ada.Directories.Exists (Ada.Directories.Compose (Dir, Temp_Name)),
         "temporary persistent cache files should be cleaned on open");
      Assert
        (not Ada.Directories.Exists
               (Ada.Directories.Compose (Dir, Backup_Name)),
         "staged replacement metadata should be cleaned on open");
      Assert
        (not Ada.Directories.Exists
               (Ada.Directories.Compose (Dir, Orphan_Name)),
         "orphan persistent body files should be cleaned on open");

      Build_Cache_Request ("http://example.com/limit", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 5"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "limit",
         Res);
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res);
      Assert
        (Status = Http_Client.Errors.Cache_Limit_Exceeded,
         "persistent cache should enforce total metadata/body limit before writing");
      Assert
        (Http_Client.Cache.Persistent.Entry_Count (Store) = 0,
         "limit rejection should not add an in-memory persistent entry");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Cleanup_And_Limits;

   procedure Test_Cache_Security_Bypass_And_Size_Limits

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
      Status  : Http_Client.Errors.Result_Status;
   begin
      Config.Enabled := True;
      Config.Max_Single_Response_Bytes := 2;
      Http_Client.Cache.Initialize (Cache, Config);
      Assert
        (Http_Client.Headers.Set (Headers, "Authorization", "Basic abc")
         = Http_Client.Errors.Ok,
         "auth header should set");
      Build_Cache_Request ("http://example.com/private", Req, Headers);
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
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Disabled,
         "Authorization responses should bypass by default");

      Headers := Http_Client.Headers.Empty;
      Build_Cache_Request ("http://example.com/public", Req, Headers);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res) = Http_Client.Errors.Ok,
         "public response should store for security lookup checks");

      Assert
        (Http_Client.Headers.Set (Headers, "Authorization", "Basic abc")
         = Http_Client.Errors.Ok,
         "auth lookup header should set");
      Build_Cache_Request ("http://example.com/public", Req, Headers);
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "Authorization request should not receive default cached response");

      Headers := Http_Client.Headers.Empty;
      Assert
        (Http_Client.Headers.Set (Headers, "Cookie", "sid=1")
         = Http_Client.Errors.Ok,
         "cookie lookup header should set");
      Build_Cache_Request ("http://example.com/public", Req, Headers);
      Status := Http_Client.Cache.Lookup (Cache, Req, Hit, Meta);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "Cookie request should not receive default cached response without Vary: Cookie support");

      Build_Cache_Request ("http://example.com/large", Req);
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
         & "abc",
         Res);
      Assert
        (Http_Client.Cache.Store (Cache, Req, Res)
         = Http_Client.Errors.Cache_Entry_Too_Large,
         "oversize cache body should be rejected deterministically");
   end Test_Cache_Security_Bypass_And_Size_Limits;

   procedure Test_Multipart_Limits_And_Invalid_Part_Headers

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Form      : aliased Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Status    : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Length    : Natural := 0;
      Body_Data : Http_Client.Request_Bodies.Request_Body;
   begin
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "limit-boundary")
         = Http_Client.Errors.Ok,
         "limit-test boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Binary_Part
           (Form,
            "good",
            "x",
            "file.bin",
            "application/octet-stream"
            & Character'Val (13)
            & Character'Val (10)
            & "Injected: x")
         = Http_Client.Errors.Invalid_Header,
         "part Content-Type should reject CRLF header injection");

      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "collision-boundary")
         = Http_Client.Errors.Ok,
         "collision-test boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field
           (Form, "field", "payload --collision-boundary payload")
         = Http_Client.Errors.Invalid_Multipart_Boundary,
         "memory fields should reject content containing the active boundary marker");

      Http_Client.Multipart.Clear (Form);
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "initial-boundary")
         = Http_Client.Errors.Ok,
         "initial boundary should be accepted before later collision test");
      Assert
        (Http_Client.Multipart.Add_Field
           (Form, "field", "payload --later-boundary payload")
         = Http_Client.Errors.Ok,
         "memory field should be accepted when it does not contain the active boundary marker");
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "later-boundary")
         = Http_Client.Errors.Invalid_Multipart_Boundary,
         "changing boundary should reject collisions with existing memory parts");

      Http_Client.Multipart.Clear (Form);
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "limit-boundary")
         = Http_Client.Errors.Ok,
         "length-limit boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field (Form, "f", "x")
         = Http_Client.Errors.Ok,
         "length-limit field should be accepted");
      Assert
        (Http_Client.Multipart.Set_Max_Encoded_Length (Form, 1)
         = Http_Client.Errors.Ok,
         "encoded multipart length limit should be configurable");
      Assert
        (Http_Client.Multipart.Content_Length (Form, Length)
         = Http_Client.Errors.Multipart_Too_Large,
         "encoded multipart length above configured limit should be rejected");
      Assert
        (Http_Client.Multipart.To_Request_Body (Form, Body_Data)
         = Http_Client.Errors.Multipart_Too_Large,
         "checked multipart request-body construction should honor encoded length limit");
      Assert
        (Http_Client.Request_Bodies.Kind (Body_Data)
         = Http_Client.Request_Bodies.Empty_Body,
         "failed checked multipart request-body construction should leave an empty body");
      Assert
        (Http_Client.Multipart.Set_Max_Encoded_Length (Form, Natural'Last)
         = Http_Client.Errors.Ok,
         "encoded multipart length limit should be restorable for later tests");

      Http_Client.Multipart.Clear (Form);
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "limit-boundary")
         = Http_Client.Errors.Ok,
         "boundary should survive limit-test reset");
      for I in 1 .. Http_Client.Multipart.Max_Part_Count loop
         Status := Http_Client.Multipart.Add_Field (Form, "f", "x");
         Assert
           (Status = Http_Client.Errors.Ok,
            "part within Max_Part_Count should be accepted");
      end loop;
      Assert
        (Http_Client.Multipart.Add_Field (Form, "f", "x")
         = Http_Client.Errors.Too_Many_Parts,
         "part count above Max_Part_Count should be rejected deterministically");
   end Test_Multipart_Limits_And_Invalid_Part_Headers;

   procedure Test_Phase36_Resource_Counters_And_Idempotent_Cleanup

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Pool      : Http_Client.Connection_Pools.Connection_Pool;
      Options   : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      URI_Value : Http_Client.URI.URI_Reference;
      Key       : Http_Client.Connection_Pools.Pool_Key;
      Token     : Http_Client.Connection_Pools.Pool_Token;
      Reused    : Boolean := False;
      Status    : Http_Client.Errors.Result_Status;
      Diag      : Http_Client.Diagnostics.Diagnostics_Context;
      Snapshot  : Http_Client.Resources.Resource_Snapshot;
   begin
      Http_Client.Resources.Reset_All;
      Http_Client.Resources.Decrement
        (Http_Client.Resources.Streaming_Responses_Open);
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Streaming_Responses_Open)
         = 0,
         "resource counters should saturate at zero for idempotent cleanup");
      Http_Client.Resources.Increment
        (Http_Client.Resources.Streaming_Responses_Open, Natural'Last);
      Http_Client.Resources.Increment
        (Http_Client.Resources.Streaming_Responses_Open);
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Streaming_Responses_Open)
         = Natural'Last,
         "resource counters should saturate at Natural'Last instead of overflowing");
      Http_Client.Resources.Reset_All;

      Status :=
        Http_Client.URI.Parse ("http://example.test/resource", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok, "phase36 URI fixture should parse");
      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 2;
      Options.Max_Idle_Connections_Per_Key := 2;
      Options.Max_Requests_Per_Connection := 2;
      Http_Client.Connection_Pools.Initialize (Pool, Options);
      Key := Http_Client.Connection_Pools.Key_For (URI_Value);

      Status := Http_Client.Connection_Pools.Begin_Fresh (Pool, Key, Token);
      Assert
        (Status = Http_Client.Errors.Ok, "fresh pool token should be created");
      Status := Http_Client.Connection_Pools.Check_In (Pool, Token);
      Assert
        (Status = Http_Client.Errors.Ok,
         "checkin should retain one idle entry");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Pool_Idle_Entries)
         = 1,
         "resource counter should track one idle pooled entry");

      Status :=
        Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused);
      Assert
        (Status = Http_Client.Errors.Ok and then Reused,
         "checkout should reuse the retained idle entry");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Pool_Idle_Entries)
         = 0,
         "checkout should decrement idle resource counter");

      Status := Http_Client.Connection_Pools.Check_In (Pool, Token);
      Assert (Status = Http_Client.Errors.Ok, "second checkin should succeed");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Pool_Idle_Entries)
         = 0,
         "max-request retirement should not retain over-age logical entries");

      Status := Http_Client.Connection_Pools.Register_Fresh_Idle (Pool, Key);
      Assert
        (Status = Http_Client.Errors.Ok,
         "test idle registration should succeed");
      Http_Client.Connection_Pools.Shutdown (Pool);
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Pool_Idle_Entries)
         = 0,
         "pool shutdown should release all idle resource counters");

      Http_Client.Diagnostics.Initialize (Diag, Enabled => False);
      Status :=
        Http_Client.Diagnostics.Emit
          (Diag,
           (Kind => Http_Client.Diagnostics.Request_Start, others => <>));
      Assert
        (Status = Http_Client.Errors.Ok,
         "disabled diagnostics emit should be a no-op");
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Diagnostics_Events_Emitted)
         = 0,
         "disabled diagnostics should not construct observable events");

      Http_Client.Diagnostics.Initialize (Diag, Enabled => True);
      Status :=
        Http_Client.Diagnostics.Emit
          (Diag,
           (Kind => Http_Client.Diagnostics.Request_Start, others => <>));
      Assert
        (Status = Http_Client.Errors.Ok,
         "enabled diagnostics emit should succeed");
      Snapshot := Http_Client.Resources.Snapshot;
      Assert
        (Snapshot.Diagnostics_Events_Emitted = 1,
         "enabled diagnostics should increment bounded event counter");

      Http_Client.Resources.Reset_All;
   end Test_Phase36_Resource_Counters_And_Idempotent_Cleanup;

   procedure Test_Phase36_Header_Hot_Path_Scale_And_Order

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      for Index in 1 .. 96 loop
         Status :=
           Http_Client.Headers.Add
             (Headers,
              "X-Test-"
              & Ada.Strings.Fixed.Trim (Index'Image, Ada.Strings.Left),
              "value");
         Assert
           (Status = Http_Client.Errors.Ok,
            "bounded header insertion should accept valid synthetic field");
      end loop;

      Status :=
        Http_Client.Headers.Add (Headers, "Content-Type", "text/plain");
      Assert
        (Status = Http_Client.Errors.Ok,
         "content-type header should append after synthetic fields");
      Status :=
        Http_Client.Headers.Add (Headers, "content-type", "application/json");
      Assert
        (Status = Http_Client.Errors.Ok,
         "duplicate case-insensitive header should append without reorder");

      Assert
        (Http_Client.Headers.Length (Headers) = 98,
         "bounded scale header list should retain all inserted fields");
      Assert
        (Http_Client.Headers.Count (Headers, "CONTENT-TYPE") = 2,
         "case-insensitive count should use stored normalized keys");
      Assert
        (Http_Client.Headers.Get (Headers, "content-type") = "text/plain",
         "first duplicate header value should remain stable");
      Assert
        (Http_Client.Headers.Name_At (Headers, 97) = "Content-Type"
         and then Http_Client.Headers.Name_At (Headers, 98) = "content-type",
         "header iteration and serialization order must remain insertion order");
      Assert
        (not Http_Client.Headers.Contains (Headers, "bad header"),
         "invalid lookup names should fail without mutating storage");
      Assert
        (Http_Client.Headers.Length (Headers) = 98,
         "invalid header lookup should not alter bounded collection state");
   end Test_Phase36_Header_Hot_Path_Scale_And_Order;

   procedure Test_Phase36_Protocol_Parser_Hostile_Input_Bounds

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_Value : Http_Client.URI.URI_Reference;
      Status    : Http_Client.Errors.Result_Status;
      Value     : Http_Client.HTTP3.Frames.Varint_Value;
      Consumed  : Natural := 0;
      Frame     : Http_Client.HTTP3.Frames.Frame;
      Long_Name : constant String (1 .. 8_192) := [others => 'a'];
   begin
      Status :=
        Http_Client.URI.Parse ("http://" & Long_Name & " " & "/", URI_Value);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "long invalid URI should fail deterministically under parser bounds");

      Status :=
        Http_Client.HTTP3.Frames.Decode_Varint
          (Character'Val (16#C0#) & Character'Val (16#00#), Value, Consumed);
      Assert
        (Status = Http_Client.Errors.Incomplete_Message,
         "truncated 8-byte QUIC varint should fail deterministically");
      Assert
        (Consumed = 0,
         "failed varint decode should not report consumed input");

      Status :=
        Http_Client.HTTP3.Frames.Parse_Frame
          (Http_Client.HTTP3.Frames.Encode_Varint
             (Http_Client.HTTP3.Frames.Type_Code
                (Http_Client.HTTP3.Frames.DATA))
           & Http_Client.HTTP3.Frames.Encode_Varint (128)
           & "abc",
           Max_Frame_Size => 16,
           Item           => Frame);
      Assert
        (Status = Http_Client.Errors.Response_Too_Large,
         "oversized HTTP/3 frame should fail before accepting payload");
   end Test_Phase36_Protocol_Parser_Hostile_Input_Bounds;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Resources");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Cookies_Max_Age_And_Header_Limit_Edges'Access,
         "Test_Cookies_Max_Age_And_Header_Limit_Edges");
      Register_Routine
        (T,
         Test_Cookie_Jar_Case_Sensitive_Names_Replacement_And_Limits'Access,
         "Test_Cookie_Jar_Case_Sensitive_Names_Replacement_And_Limits");
      Register_Routine
        (T,
         Test_Cookies_Limits_And_Strict_Store_Behavior'Access,
         "Test_Cookies_Limits_And_Strict_Store_Behavior");
      Register_Routine
        (T,
         Test_High_Level_Client_Invalid_Limit_Relationships'Access,
         "Test_High_Level_Client_Invalid_Limit_Relationships");
      Register_Routine
        (T,
         Test_Response_Stream_Body_Limit_Before_Return'Access,
         "Test_Response_Stream_Body_Limit_Before_Return");
      Register_Routine
        (T,
         Test_Connection_Pool_Key_And_Limits'Access,
         "Test_Connection_Pool_Key_And_Limits");
      Register_Routine
        (T,
         Test_Persistent_Cache_Cleanup_And_Limits'Access,
         "Test_Persistent_Cache_Cleanup_And_Limits");
      Register_Routine
        (T,
         Test_Cache_Security_Bypass_And_Size_Limits'Access,
         "Test_Cache_Security_Bypass_And_Size_Limits");
      Register_Routine
        (T,
         Test_Multipart_Limits_And_Invalid_Part_Headers'Access,
         "Test_Multipart_Limits_And_Invalid_Part_Headers");
      Register_Routine
        (T,
         Test_Phase36_Resource_Counters_And_Idempotent_Cleanup'Access,
         "Test_Phase36_Resource_Counters_And_Idempotent_Cleanup");
      Register_Routine
        (T,
         Test_Phase36_Header_Hot_Path_Scale_And_Order'Access,
         "Test_Phase36_Header_Hot_Path_Scale_And_Order");
      Register_Routine
        (T,
         Test_Phase36_Protocol_Parser_Hostile_Input_Bounds'Access,
         "Test_Phase36_Protocol_Parser_Hostile_Input_Bounds");
   end Register_Tests;

end Http_Client.Resources.Tests;
