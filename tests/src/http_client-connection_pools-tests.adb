with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Clients;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Connection_Pools.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;

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

   procedure Test_Connection_Pool_Key_Security_Boundaries

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_A       : Http_Client.URI.URI_Reference;
      URI_B       : Http_Client.URI.URI_Reference;
      Status      : Http_Client.Errors.Result_Status;
      TLS_A       : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      TLS_B       : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Proxy_A     : Http_Client.Proxies.Proxy_Config;
      Proxy_B     : Http_Client.Proxies.Proxy_Config;
      SOCKS_A     : Http_Client.Proxies.Proxy_Config;
      SOCKS_B     : Http_Client.Proxies.Proxy_Config;
      SOCKS_C     : Http_Client.Proxies.Proxy_Config;
      Key_Direct  : Http_Client.Connection_Pools.Pool_Key;
      Key_TLS_A   : Http_Client.Connection_Pools.Pool_Key;
      Key_TLS_B   : Http_Client.Connection_Pools.Pool_Key;
      Key_Proxy_A : Http_Client.Connection_Pools.Pool_Key;
      Key_Proxy_B : Http_Client.Connection_Pools.Pool_Key;
      Key_SOCKS_A : Http_Client.Connection_Pools.Pool_Key;
      Key_SOCKS_B : Http_Client.Connection_Pools.Pool_Key;
      Key_SOCKS_C : Http_Client.Connection_Pools.Pool_Key;
   begin
      Status := Http_Client.URI.Parse ("https://example.test/a", URI_A);
      Assert (Status = Http_Client.Errors.Ok, "https pool URI A should parse");
      Status := Http_Client.URI.Parse ("https://other.example.test/a", URI_B);
      Assert (Status = Http_Client.Errors.Ok, "https pool URI B should parse");

      TLS_B.Disable_Certificate_Verification := True;
      Proxy_A := Http_Client.Proxies.HTTP ("proxy.test", 8080);
      Status :=
        Http_Client.Proxies.With_Proxy_Authorization
          (Proxy_A, "Basic cHJveHk=", Proxy_B);
      Assert
        (Status = Http_Client.Errors.Ok,
         "proxy authorization test value should validate");

      SOCKS_A := Http_Client.Proxies.SOCKS5 ("socks.test", 1080);
      Status :=
        Http_Client.Proxies.With_SOCKS5_Username_Password
          (SOCKS_A, "user-a", "pass-a", SOCKS_B);
      Assert
        (Status = Http_Client.Errors.Ok,
         "SOCKS credentials for pool key should validate");
      SOCKS_C :=
        Http_Client.Proxies.SOCKS5
          ("socks.test", 1080, Http_Client.Proxies.SOCKS5_Local_DNS);

      Key_Direct := Http_Client.Connection_Pools.Key_For (URI_A);
      Key_TLS_A := Http_Client.Connection_Pools.Key_For (URI_A, TLS => TLS_A);
      Key_TLS_B := Http_Client.Connection_Pools.Key_For (URI_A, TLS => TLS_B);
      Key_Proxy_A :=
        Http_Client.Connection_Pools.Key_For (URI_A, Proxy => Proxy_A);
      Key_Proxy_B :=
        Http_Client.Connection_Pools.Key_For (URI_A, Proxy => Proxy_B);
      Key_SOCKS_A :=
        Http_Client.Connection_Pools.Key_For (URI_A, Proxy => SOCKS_A);
      Key_SOCKS_B :=
        Http_Client.Connection_Pools.Key_For (URI_A, Proxy => SOCKS_B);
      Key_SOCKS_C :=
        Http_Client.Connection_Pools.Key_For (URI_A, Proxy => SOCKS_C);

      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_TLS_A, Key_TLS_B),
         "different TLS verification policy must not share a pooled key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_Direct, Key_Proxy_A),
         "direct and proxied connections must not share a pooled key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_Proxy_A, Key_Proxy_B),
         "proxy authorization presence must be part of pooled compatibility");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_Proxy_A, Key_SOCKS_A),
         "HTTP proxy and SOCKS proxy connections must not share a pooled key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_SOCKS_A, Key_SOCKS_B),
         "SOCKS authentication scope must be part of pooled compatibility");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_SOCKS_A, Key_SOCKS_C),
         "SOCKS DNS mode must be part of pooled compatibility");
      Assert
        (not Http_Client.Connection_Pools.Same_Key
               (Key_TLS_A,
                Http_Client.Connection_Pools.Key_For (URI_B, TLS => TLS_A)),
         "different HTTPS origin hosts must not share a TLS pooled key");
      Assert
        (Http_Client.Connection_Pools.Image (Key_Proxy_B)'Length > 0,
         "pool key image should be available for diagnostics without exposing secrets");
      Assert
        (Ada.Strings.Fixed.Index
           (Http_Client.Connection_Pools.Image (Key_SOCKS_B), "user-a")
         = 0
         and then
           Ada.Strings.Fixed.Index
             (Http_Client.Connection_Pools.Image (Key_SOCKS_B), "pass-a")
           = 0,
         "SOCKS pool key image must not expose SOCKS username or password");
   end Test_Connection_Pool_Key_Security_Boundaries;

   procedure Test_Connection_Pool_IPv6_Key_Does_Not_Collide
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI_IPv6  : Http_Client.URI.URI_Reference;
      URI_IPv4  : Http_Client.URI.URI_Reference;
      URI_DNS   : Http_Client.URI.URI_Reference;
      Status    : Http_Client.Errors.Result_Status;
      Key_IPv6  : Http_Client.Connection_Pools.Pool_Key;
      Key_IPv4  : Http_Client.Connection_Pools.Pool_Key;
      Key_DNS   : Http_Client.Connection_Pools.Pool_Key;
      IPv6_Image : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Status := Http_Client.URI.Parse ("http://[::1]:8080/", URI_IPv6);
      Assert (Status = Http_Client.Errors.Ok, "IPv6 pool URI should parse");
      Status := Http_Client.URI.Parse ("http://127.0.0.1:8080/", URI_IPv4);
      Assert (Status = Http_Client.Errors.Ok, "IPv4 pool URI should parse");
      Status := Http_Client.URI.Parse ("http://localhost:8080/", URI_DNS);
      Assert (Status = Http_Client.Errors.Ok, "DNS pool URI should parse");

      Key_IPv6 := Http_Client.Connection_Pools.Key_For (URI_IPv6);
      Key_IPv4 := Http_Client.Connection_Pools.Key_For (URI_IPv4);
      Key_DNS := Http_Client.Connection_Pools.Key_For (URI_DNS);
      IPv6_Image := Ada.Strings.Unbounded.To_Unbounded_String (Http_Client.Connection_Pools.Image (Key_IPv6));

      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_IPv6, Key_IPv4),
         "IPv6 and IPv4 loopback origins must not share a pool key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_IPv6, Key_DNS),
         "IPv6 and DNS loopback origins must not share a pool key");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_IPv4, Key_DNS),
         "IPv4 and DNS loopback origins must not share a pool key");
      Assert
        (Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (IPv6_Image), "http://[::1]:8080") /= 0,
         "IPv6 pool key image must use bracketed authority formatting");
   end Test_Connection_Pool_IPv6_Key_Does_Not_Collide;

   procedure Test_Connection_Pool_Protocol_Key_Boundary
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI        : Http_Client.URI.URI_Reference;
      Status     : Http_Client.Errors.Result_Status;
      Key_H1     : Http_Client.Connection_Pools.Pool_Key;
      Key_H1_2   : Http_Client.Connection_Pools.Pool_Key;
      Key_H2     : Http_Client.Connection_Pools.Pool_Key;
      Key_H3     : Http_Client.Connection_Pools.Pool_Key;
      Image_H2   : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Status := Http_Client.URI.Parse ("https://example.test/protocol", URI);
      Assert (Status = Http_Client.Errors.Ok, "protocol pool URI should parse");

      Key_H1 := Http_Client.Connection_Pools.Key_For (URI);
      Key_H1_2 := Http_Client.Connection_Pools.Key_For
        (URI, Protocol => Http_Client.Connection_Pools.Pool_HTTP_1_1);
      Key_H2 := Http_Client.Connection_Pools.Key_For
        (URI, Protocol => Http_Client.Connection_Pools.Pool_HTTP_2);
      Key_H3 := Http_Client.Connection_Pools.Key_For
        (URI, Protocol => Http_Client.Connection_Pools.Pool_HTTP_3);
      Image_H2 := Ada.Strings.Unbounded.To_Unbounded_String
        (Http_Client.Connection_Pools.Image (Key_H2));

      Assert
        (Http_Client.Connection_Pools.Same_Key (Key_H1, Key_H1_2),
         "default pool protocol should remain HTTP/1.1 for compatibility");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_H1, Key_H2),
         "HTTP/1.1 and HTTP/2 must not share pool compatibility keys");
      Assert
        (not Http_Client.Connection_Pools.Same_Key (Key_H2, Key_H3),
         "HTTP/2 and HTTP/3 must not share pool compatibility keys");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Image_H2), "protocol=h2") /= 0,
         "pool key image should expose non-secret protocol identity");
   end Test_Connection_Pool_Protocol_Key_Boundary;

   procedure Test_Connection_Pool_Nonreusable_And_Shutdown_Lifecycle

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Status  : Http_Client.Errors.Result_Status;
      Options : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Pool    : Http_Client.Connection_Pools.Connection_Pool;
      Key     : Http_Client.Connection_Pools.Pool_Key;
      Token   : Http_Client.Connection_Pools.Pool_Token;
      Reused  : Boolean := False;
   begin
      Status := Http_Client.URI.Parse ("http://example.test/reuse", URI);
      Assert
        (Status = Http_Client.Errors.Ok, "pool lifecycle URI should parse");
      Key := Http_Client.Connection_Pools.Key_For (URI);

      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 1;
      Options.Max_Idle_Connections_Per_Key := 1;
      Options.Max_Requests_Per_Connection := 10;
      Http_Client.Connection_Pools.Initialize (Pool, Options);

      Assert
        (Http_Client.Connection_Pools.Register_Fresh_Idle
           (Pool, Key, Reusable => False)
         = Http_Client.Errors.Ok,
         "non-reusable fresh completion should be discarded without error");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool) = 0,
         "non-reusable fresh completion must not be retained");

      Assert
        (Http_Client.Connection_Pools.Register_Fresh_Idle (Pool, Key)
         = Http_Client.Errors.Ok,
         "reusable fresh completion should be retained");
      Assert
        (Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused)
         = Http_Client.Errors.Ok,
         "checkout before non-reusable checkin should succeed");
      Assert (Reused, "checkout should reuse the one retained entry");
      Assert
        (Http_Client.Connection_Pools.Check_In (Pool, Token, Reusable => False)
         = Http_Client.Errors.Ok,
         "non-reusable checkin should discard without error");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool) = 0,
         "non-reusable checkin must not return the entry to idle state");

      Http_Client.Connection_Pools.Shutdown (Pool);
      Assert
        (Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused)
         = Http_Client.Errors.Pool_Closed,
         "checkout after shutdown should be rejected deterministically");
      Assert
        (Http_Client.Connection_Pools.Check_In (Pool, Token, Reusable => True)
         = Http_Client.Errors.Pool_Closed,
         "checkin after shutdown should be rejected deterministically");
   end Test_Connection_Pool_Nonreusable_And_Shutdown_Lifecycle;

   procedure Test_Connection_Pool_Response_Reuse_Predicate

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI      : Http_Client.URI.URI_Reference;
      Headers  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse ("http://example.test/predicate", URI);
      Assert
        (Status = Http_Client.Errors.Ok, "reuse predicate URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method => Http_Client.Types.GET, URI => URI, Item => Request);
      Assert
        (Status = Http_Client.Errors.Ok,
         "reuse predicate request should construct");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & Character'Val (13)
           & Character'Val (10)
           & "Content-Length: 5"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10)
           & "Hello",
           Response);
      Assert
        (Status = Http_Client.Errors.Ok,
         "content-length response should parse");
      Assert
        (Http_Client.Connection_Pools.Response_Permits_Reuse
           (Request, Response),
         "fully buffered HTTP/1.1 content-length response should permit reuse");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & Character'Val (13)
           & Character'Val (10)
           & "Connection: close"
           & Character'Val (13)
           & Character'Val (10)
           & "Content-Length: 5"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10)
           & "Hello",
           Response);
      Assert
        (Status = Http_Client.Errors.Ok,
         "connection-close response should parse");
      Assert
        (not Http_Client.Connection_Pools.Response_Permits_Reuse
               (Request, Response),
         "server Connection: close must prevent reuse");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10)
           & "Hello",
           Response);
      Assert
        (Status = Http_Client.Errors.Ok,
         "close-delimited-looking response should parse");
      Assert
        (not Http_Client.Connection_Pools.Response_Permits_Reuse
               (Request, Response),
         "missing reusable framing on a body response must prevent reuse");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 204 No Content"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10),
           Response);
      Assert (Status = Http_Client.Errors.Ok, "204 response should parse");
      Assert
        (Http_Client.Connection_Pools.Response_Permits_Reuse
           (Request, Response),
         "no-body status without content-length should still permit reuse");

      Status :=
        Http_Client.Headers.Set (Headers, "Connection", "keep-alive, close");
      Assert
        (Status = Http_Client.Errors.Ok,
         "request Connection header should validate");
      Status :=
        Http_Client.Requests.Create
          (Method    => Http_Client.Types.GET,
           URI       => URI,
           Item      => Request,
           Headers   => Headers,
           Auto_Host => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "request with Connection close should construct");
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & Character'Val (13)
           & Character'Val (10)
           & "Content-Length: 0"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10),
           Response);
      Assert
        (Status = Http_Client.Errors.Ok, "zero-length response should parse");
      Assert
        (not Http_Client.Connection_Pools.Request_Permits_Persistent_Reuse
               (Request),
         "request-only reuse predicate should reject caller Connection: close");
      Assert
        (not Http_Client.Connection_Pools.Response_Permits_Reuse
               (Request, Response),
         "caller Connection: close must prevent reuse");

      Headers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Set (Headers, "Connection", "Upgrade");
      Assert
        (Status = Http_Client.Errors.Ok,
         "request Connection upgrade header should validate");
      Status := Http_Client.Headers.Set (Headers, "Upgrade", "websocket");
      Assert
        (Status = Http_Client.Errors.Ok,
         "request Upgrade header should validate");
      Status :=
        Http_Client.Requests.Create
          (Method    => Http_Client.Types.GET,
           URI       => URI,
           Item      => Request,
           Headers   => Headers,
           Auto_Host => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "request with Upgrade should construct");
      Assert
        (not Http_Client.Connection_Pools.Request_Permits_Persistent_Reuse
               (Request),
         "protocol upgrade requests must not be considered pool-reusable");

      Headers := Http_Client.Headers.Empty;
      Status :=
        Http_Client.Requests.Create
          (Method => Http_Client.Types.GET, URI => URI, Item => Request);
      Assert
        (Status = Http_Client.Errors.Ok,
         "plain reuse predicate request should reconstruct");
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 101 Switching Protocols"
           & Character'Val (13)
           & Character'Val (10)
           & "Connection: Upgrade"
           & Character'Val (13)
           & Character'Val (10)
           & "Upgrade: websocket"
           & Character'Val (13)
           & Character'Val (10)
           & Character'Val (13)
           & Character'Val (10),
           Response);
      Assert
        (Status = Http_Client.Errors.Ok, "101 upgrade response should parse");
      Assert
        (not Http_Client.Connection_Pools.Response_Permits_Reuse
               (Request, Response),
         "101 protocol-switching response must never return to the HTTP pool");
   end Test_Connection_Pool_Response_Reuse_Predicate;

   procedure Test_Connection_Pool_Disabled_And_Empty_Checkout

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Status  : Http_Client.Errors.Result_Status;
      Options : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Pool    : Http_Client.Connection_Pools.Connection_Pool;
      Key     : Http_Client.Connection_Pools.Pool_Key;
      Token   : Http_Client.Connection_Pools.Pool_Token;
      Reused  : Boolean := True;
   begin
      Status := Http_Client.URI.Parse ("http://example.test/empty", URI);
      Assert
        (Status = Http_Client.Errors.Ok, "empty checkout URI should parse");
      Key := Http_Client.Connection_Pools.Key_For (URI);

      Options.Enabled := False;
      Http_Client.Connection_Pools.Initialize (Pool, Options);

      Assert
        (Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused)
         = Http_Client.Errors.Ok,
         "disabled pool checkout should succeed as no reusable entry");
      Assert
        (not Reused,
         "disabled pool checkout must report no reused connection");
      Assert
        (not Http_Client.Connection_Pools.Is_Valid (Token),
         "disabled pool checkout must return an invalid token");

      Assert
        (Http_Client.Connection_Pools.Begin_Fresh (Pool, Key, Token)
         = Http_Client.Errors.Ok,
         "disabled pool fresh registration should be a no-op success");
      Assert
        (not Http_Client.Connection_Pools.Is_Valid (Token),
         "disabled pool fresh registration must return an invalid token");

      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 1;
      Options.Max_Idle_Connections_Per_Key := 1;
      Http_Client.Connection_Pools.Initialize (Pool, Options);
      Reused := True;

      Assert
        (Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused)
         = Http_Client.Errors.Ok,
         "empty enabled pool checkout should succeed so caller can open fresh transport");
      Assert
        (not Reused,
         "empty enabled pool checkout must report no reused connection");
      Assert
        (not Http_Client.Connection_Pools.Is_Valid (Token),
         "empty enabled pool checkout must return an invalid token until Begin_Fresh");
   end Test_Connection_Pool_Disabled_And_Empty_Checkout;

   procedure Test_Connection_Pool_Shutdown_And_Client_Config

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Pool    : Http_Client.Connection_Pools.Connection_Pool;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client  : Http_Client.Clients.Client;
   begin
      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 0;
      Options.Max_Idle_Connections_Per_Key := 1;
      Assert
        (Http_Client.Connection_Pools.Validate (Options)
         = Http_Client.Errors.Invalid_Configuration,
         "enabled pooling should reject zero global idle limit");

      Options.Max_Total_Idle_Connections := 1;
      Options.Max_Idle_Connections_Per_Key := 0;
      Assert
        (Http_Client.Connection_Pools.Validate (Options)
         = Http_Client.Errors.Invalid_Configuration,
         "enabled pooling should reject zero per-key idle limit");

      Options.Max_Total_Idle_Connections := 1;
      Options.Max_Idle_Connections_Per_Key := 2;
      Assert
        (Http_Client.Connection_Pools.Validate (Options)
         = Http_Client.Errors.Invalid_Configuration,
         "enabled pooling should reject per-key idle limit greater than global idle limit");

      Options.Max_Idle_Connections_Per_Key := 1;
      Http_Client.Connection_Pools.Initialize (Pool, Options);
      Http_Client.Connection_Pools.Shutdown (Pool);
      Assert
        (Http_Client.Connection_Pools.Is_Closed (Pool),
         "shutdown should close the pool");

      Assert
        (Http_Client.Connection_Pools.Transport_Attached_Reuse_Available,
         "pooling policy should report that real handle-attached reuse is wired");

      Config.Pooling := Options;
      Assert
        (Http_Client.Clients.Initialize (Client, Config)
         = Http_Client.Errors.Ok,
         "high-level client configuration should accept valid pooling options");
      Assert
        (Http_Client.Clients.Is_Initialized (Client),
         "client with pooling config should be initialized");
   end Test_Connection_Pool_Shutdown_And_Client_Config;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Connection_Pools");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Connection_Pool_Key_Security_Boundaries'Access,
         "Test_Connection_Pool_Key_Security_Boundaries");
      Register_Routine
        (T,
         Test_Connection_Pool_IPv6_Key_Does_Not_Collide'Access,
         "Test_Connection_Pool_IPv6_Key_Does_Not_Collide");
      Register_Routine
        (T,
         Test_Connection_Pool_Protocol_Key_Boundary'Access,
         "Test_Connection_Pool_Protocol_Key_Boundary");
      Register_Routine
        (T,
         Test_Connection_Pool_Nonreusable_And_Shutdown_Lifecycle'Access,
         "Test_Connection_Pool_Nonreusable_And_Shutdown_Lifecycle");
      Register_Routine
        (T,
         Test_Connection_Pool_Response_Reuse_Predicate'Access,
         "Test_Connection_Pool_Response_Reuse_Predicate");
      Register_Routine
        (T,
         Test_Connection_Pool_Disabled_And_Empty_Checkout'Access,
         "Test_Connection_Pool_Disabled_And_Empty_Checkout");
      Register_Routine
        (T,
         Test_Connection_Pool_Shutdown_And_Client_Config'Access,
         "Test_Connection_Pool_Shutdown_And_Client_Config");
   end Register_Tests;

end Http_Client.Connection_Pools.Tests;
