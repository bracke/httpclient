with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces; use Interfaces;
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
with Http_Client.URI;

package body Http_Client.HTTP3.Tests is

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
   Diagnostic_Last_Event     : Http_Client.Diagnostics.Diagnostic_Event;
   Diagnostic_Fail_Next      : Boolean := False;

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status) is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;

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

   procedure Test_HTTP3_Config_And_Unsupported_Execution

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options       : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      Conn          : Http_Client.QUIC.Connection;
      Client_Config : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
   begin
      Assert
        (Options.Mode = Http_Client.HTTP3.HTTP3_Disabled,
         "HTTP/3 should be disabled by default");
      Assert
        (Client_Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled,
         "high-level client configuration should also disable HTTP/3 by default");
      Assert
        (Http_Client.HTTP3.ALPN_Token (Options) = "",
         "disabled HTTP/3 must not advertise h3");
      Assert
        (Http_Client.HTTP3.Normalize_ALPN_Selected ("h3")
         = Http_Client.HTTP3.Protocol_HTTP_3,
         "h3 ALPN token should normalize only for QUIC HTTP/3 policy");
      Assert
        (Http_Client.HTTP3.Execution_Status (Options)
         = Http_Client.Errors.HTTP3_Unsupported,
         "disabled HTTP/3 execution should fail before sending request data");

      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Assert
        (Http_Client.HTTP3.ALPN_Token (Options) = "h3",
         "enabled HTTP/3 should advertise the QUIC h3 token");
      Assert
        (Http_Client.HTTP3.Execution_Status (Options)
         = Http_Client.Errors.QUIC_Unsupported,
         "experimental HTTP/3 foundation default QUIC backend should be explicitly unsupported");
      Options.Enable_Zero_RTT := True;
      Assert
        (Http_Client.HTTP3.Validate (Options)
         = Http_Client.Errors.Invalid_Configuration,
         "HTTP/3 0-RTT should remain disabled in experimental HTTP/3 foundation");
      Options.Enable_Zero_RTT := False;
      Options.Enable_Server_Push := True;
      Assert
        (Http_Client.HTTP3.Validate (Options)
         = Http_Client.Errors.HTTP3_Unsupported,
         "HTTP/3 server push should remain unsupported in experimental HTTP/3 foundation");
      Options.Enable_Server_Push := False;
      Assert
        (Http_Client.HTTP3.Execution_Status (Options, Proxy_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "HTTP/3 must not bypass configured HTTP proxies");
      Assert
        (Http_Client.HTTP3.Execution_Status (Options, SOCKS_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "HTTP/3 must not silently use SOCKS without UDP support");
      Assert
        (Http_Client.HTTP3.Execution_Status
           (Options, Client_Certificate_Configured => True)
         = Http_Client.Errors.TLS_Client_Certificate_Unsupported,
         "HTTP/3 client certificates are deferred without QUIC/TLS support");
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Assert
        (Http_Client.HTTP3.Execution_Status (Options) = Http_Client.Errors.Ok,
         "selected QUIC backend should make HTTP/3 a candidate before backend open");
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;

      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "fallback is disabled unless caller opts in");
      Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.Ok,
         "fallback may occur before request bytes are sent when enabled");
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => True)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "fallback after HTTP/3 request bytes are sent must be rejected");

      Assert
        (Http_Client.QUIC.Open (Conn, "example.test", 443)
         = Http_Client.Errors.QUIC_Unsupported,
         "unavailable QUIC backend must not fake HTTP/3 over TCP/TLS");
      Assert
        (not Http_Client.QUIC.Is_Open (Conn),
         "unsupported QUIC open should leave connection closed");
      Assert
        (Http_Client.QUIC.Open (Conn, "", 443)
         = Http_Client.Errors.Invalid_URI,
         "QUIC open should reject an empty hostname before backend selection");
      Assert
        (not Http_Client.QUIC.Is_Open (Conn),
         "invalid QUIC open should leave connection closed");
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Assert
        (Http_Client.QUIC.Open (Conn, "example.test", 443, Options.QUIC)
         = Http_Client.Errors.QUIC_Unsupported,
         "selected unavailable backend path must still fail honestly until a real UDP/QUIC binding exists");
      Assert
        (not Http_Client.QUIC.Is_Open (Conn),
         "selected unavailable QUIC backend should not leave a phantom open connection");
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;

      declare
         URI  : Http_Client.URI.URI_Reference;
         Req  : Http_Client.Requests.Request;
         Resp : Http_Client.Responses.Response;
      begin
         Assert_Parse_Ok
           ("https://example.test/",
            URI,
            "HTTP/3 execution test URI should parse");
         Assert
           (Http_Client.Requests.Create
              (Method => Http_Client.Types.GET, URI => URI, Item => Req)
            = Http_Client.Errors.Ok,
            "HTTP/3 execution request should construct");
         Options.Mode := Http_Client.HTTP3.HTTP3_Required;
         Options.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
         Assert
           (Http_Client.HTTP3.Execution.Execute_Buffered
              (Request => Req, Options => Options, Response => Resp)
            = Http_Client.Errors.QUIC_Unsupported,
            "HTTP/3 execution should fail honestly when no QUIC backend is configured");
         Assert
           (Http_Client.HTTP3.Execution.Execute_Buffered
              (Request          => Req,
               Options          => Options,
               Response         => Resp,
               Proxy_Configured => True)
            = Http_Client.Errors.HTTP3_Proxy_Unsupported,
            "HTTP/3 execution should reject proxies before opening QUIC");

         declare
            Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
            Snap    : Http_Client.Diagnostics.Metrics_Snapshot;
         begin
            Diagnostic_Callback_Count := 0;
            Http_Client.Diagnostics.Initialize
              (Context  => Context,
               Enabled  => True,
               Observer => Capture_Diagnostic'Unrestricted_Access);
            Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
            Assert
              (Http_Client.HTTP3.Execution.Execute_Buffered
                 (Request       => Req,
                  Options       => Options,
                  Response      => Resp,
                  Diagnostics   => Context'Unchecked_Access,
                  Request_ID    => 7,
                  Connection_ID => 9)
               = Http_Client.Errors.QUIC_Unsupported,
               "HTTP/3 unavailable backend path should still fail honestly with diagnostics enabled");
            Snap := Http_Client.Diagnostics.Snapshot (Context);
            Assert
              (Snap.HTTP3_Events = 2,
               "HTTP/3 diagnostics should count QUIC start and failed-open events");
            Assert
              (Diagnostic_Callback_Count = 2,
               "HTTP/3 execution should emit QUIC start and failed-open diagnostics");
            Assert
              (Diagnostic_Last_Event.Kind
               = Http_Client.Diagnostics.QUIC_Connection_Failed,
               "last HTTP/3 diagnostic should report QUIC open failure");
            Assert
              (Diagnostic_Last_Event.Result
               = Http_Client.Errors.QUIC_Unsupported,
               "QUIC failed-open diagnostic should preserve the deterministic status");
            Options.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;
         end;

         declare
            HTTP_URI      : Http_Client.URI.URI_Reference;
            HTTP_Req      : Http_Client.Requests.Request;
            Client        : Http_Client.Clients.Client :=
              Http_Client.Clients.Create;
            Config        : Http_Client.Clients.Client_Configuration :=
              Http_Client.Clients.Strict_Client_Configuration;
            Client_Result : Http_Client.Clients.Client_Result;
         begin
            Assert_Parse_Ok
              ("http://example.test/",
               HTTP_URI,
               "HTTP/3 required non-HTTPS test URI should parse");
            Assert
              (Http_Client.Requests.Create
                 (Method => Http_Client.Types.GET,
                  URI    => HTTP_URI,
                  Item   => HTTP_Req)
               = Http_Client.Errors.Ok,
               "HTTP/3 required non-HTTPS test request should construct");
            Config.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Required;
            Config.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
            Assert
              (Http_Client.Clients.Configure (Client, Config)
               = Http_Client.Errors.Ok,
               "HTTP/3 required non-HTTPS test client should configure");
            Assert
              (Http_Client.Clients.Execute (Client, HTTP_Req, Client_Result)
               = Http_Client.Errors.HTTP3_Unsupported,
               "required HTTP/3 must not fall through to HTTP/1.1 for plain HTTP URIs");
            Assert
              (Client_Result.Status = Http_Client.Errors.HTTP3_Unsupported,
               "client result should preserve required HTTP/3 non-HTTPS rejection");
         end;

         declare
            type Test_Producer is new Http_Client.Request_Bodies.Body_Producer
            with null record;

            overriding
            function Read_Some
              (Item   : in out Test_Producer;
               Buffer : out String;
               Count  : out Natural) return Http_Client.Errors.Result_Status;

            overriding
            function Reset
              (Item : in out Test_Producer)
               return Http_Client.Errors.Result_Status;

            overriding
            function Read_Some
              (Item   : in out Test_Producer;
               Buffer : out String;
               Count  : out Natural) return Http_Client.Errors.Result_Status
            is
               pragma Unreferenced (Item);
               pragma Unreferenced (Buffer);
            begin
               Count := 0;
               return Http_Client.Errors.Ok;
            end Read_Some;

            overriding
            function Reset
              (Item : in out Test_Producer)
               return Http_Client.Errors.Result_Status
            is
               pragma Unreferenced (Item);
            begin
               return Http_Client.Errors.Ok;
            end Reset;

            Producer : aliased Test_Producer;
         begin
            Assert
              (Http_Client.Requests.Set_Body
                 (Req,
                  Http_Client.Request_Bodies.From_Fixed_Length_Stream
                    (Producer'Unchecked_Access,
                     0,
                     Replayable => True))
               = Http_Client.Errors.Ok,
               "HTTP/3 streaming-body rejection test body should attach");
            Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
            Assert
              (Http_Client.HTTP3.Execution.Execute_Buffered
                 (Request          => Req,
                  Options          => Options,
                  Response         => Resp,
                  Proxy_Configured => True)
               = Http_Client.Errors.HTTP3_Proxy_Unsupported,
               "HTTP/3 proxy policy should be reported before streaming-body shape checks");
            Assert
              (Http_Client.HTTP3.Execution.Execute_Buffered
                 (Request => Req, Options => Options, Response => Resp)
               = Http_Client.Errors.Unsupported_Feature,
               "HTTP/3 execution should reject streaming upload bodies before QUIC I/O");
            Options.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;
         end;
      end;
   end Test_HTTP3_Config_And_Unsupported_Execution;

   procedure Test_HTTP3_Request_Response_Mapping

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Req    : Http_Client.Requests.Request;
      In_H   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      H3_H   : Http_Client.Headers.Header_List;
      Resp_H : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status : Http_Client.Types.Status_Code;
   begin
      Assert_Header_Status
        (Http_Client.Headers.Add (In_H, "accept", "text/plain"),
         "lowercase request header should be accepted before HTTP/3 mapping");
      Assert_Parse_Ok
        ("https://example.com:8443/a/b?x=1#frag",
         URI,
         "HTTP/3 request URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Req,
            Headers => In_H)
         = Http_Client.Errors.Ok,
         "request for HTTP/3 mapping should construct");
      Assert
        (Http_Client.HTTP3.Mapping.Build_Request_Headers (Req, H3_H)
         = Http_Client.Errors.Ok,
         "valid request should map to HTTP/3 headers");
      Assert
        (Http_Client.Headers.Name_At (H3_H, 1) = ":method"
         and then Http_Client.Headers.Value_At (H3_H, 1) = "GET",
         "HTTP/3 request mapping should start with :method");
      Assert
        (Http_Client.Headers.Get (H3_H, ":authority") = "example.com:8443",
         "Host authority should map to :authority for HTTP/3");
      Assert
        (Http_Client.Headers.Get (H3_H, ":path") = "/a/b?x=1",
         "HTTP/3 :path should preserve query and omit fragment");
      Assert
        (not Http_Client.Headers.Contains (H3_H, "host"),
         "ordinary Host header must not be emitted in HTTP/3 request headers");

      Assert
        (Http_Client.Headers.Add_HTTP2_Pseudo (Resp_H, ":status", "200")
         = Http_Client.Errors.Ok,
         "response :status pseudo-header should be constructible for HTTP/3 mapping tests");
      Assert_Header_Status
        (Http_Client.Headers.Add (Resp_H, "content-type", "text/plain"),
         "lowercase HTTP/3 response field should be accepted");
      Assert
        (Http_Client.HTTP3.Mapping.Validate_Response_Headers (Resp_H)
         = Http_Client.Errors.Ok,
         "valid HTTP/3 response headers should validate");
      Assert
        (Http_Client.HTTP3.Mapping.Parse_Status (Resp_H, Status)
         = Http_Client.Errors.Ok
         and then Status = 200,
         ":status should map to numeric HTTP/3 response status");

      Assert_Header_Status
        (Http_Client.Headers.Add (Resp_H, "connection", "close"),
         "connection field can be constructed but must be rejected by HTTP/3 mapping");
      Assert
        (Http_Client.HTTP3.Mapping.Validate_Response_Headers (Resp_H)
         = Http_Client.Errors.Invalid_Header,
         "connection-specific response fields must be rejected for HTTP/3");
   end Test_HTTP3_Request_Response_Mapping;

   procedure Test_HTTP3_Git_Metadata_And_Binary_Body
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request : Http_Client.Requests.Request;
      H3_H    : Http_Client.Headers.Header_List;
      Git_Body : constant Ada.Streams.Stream_Element_Array :=
        [1 => 16#30#, 2 => 16#30#, 3 => 16#30#, 4 => 16#8#,
         5 => 0, 6 => 16#80#, 7 => 16#FF#];
   begin
      Assert_Parse_Ok
        ("https://example.com/repo.git/git-receive-pack",
         URI,
         "HTTP/3 Git URI should parse");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers,
            "Content-Type",
            "application/x-git-receive-pack-request"),
         "HTTP/3 Git content type should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers,
            "Accept",
            "application/x-git-receive-pack-result"),
         "HTTP/3 Git accept header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2"),
         "HTTP/3 Git-Protocol header should be accepted");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "HTTP/3 Git request should construct");
      Assert
        (Http_Client.Requests.Set_Body
           (Request,
            Http_Client.Request_Bodies.From_Bytes (Git_Body))
         = Http_Client.Errors.Ok,
         "HTTP/3 Git request should accept binary body");
      Assert
        (Http_Client.HTTP3.Mapping.Build_Request_Headers (Request, H3_H)
         = Http_Client.Errors.Ok,
         "HTTP/3 Git request headers should map to h3 pseudo/ordinary fields");
      Assert
        (Http_Client.Headers.Get (H3_H, ":method") = "POST",
         "HTTP/3 Git POST should map to :method");
      Assert
        (Http_Client.Headers.Get (H3_H, ":path") = "/repo.git/git-receive-pack",
         "HTTP/3 Git path should map to :path");
      Assert
        (Http_Client.Headers.Get (H3_H, "git-protocol") = "version=2",
         "HTTP/3 Git-Protocol should be lowercased and preserved");
      Assert
        (Http_Client.Headers.Get (H3_H, "content-type") =
         "application/x-git-receive-pack-request",
         "HTTP/3 Git content-type value should be preserved exactly");
      Assert
        (Http_Client.Request_Bodies.Buffered_Bytes
           (Http_Client.Requests.Request_Body (Request)) = Git_Body,
         "HTTP/3 Git binary body bytes should be preserved exactly");
   end Test_HTTP3_Git_Metadata_And_Binary_Body;

   procedure Test_HTTP3_Varint_And_Frame_Binary

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Value     : Http_Client.HTTP3.Frames.Varint_Value;
      Used      : Natural;
      Outp      : Unbounded_String;
      Item      : Http_Client.HTTP3.Frames.Frame;
      Header    : Http_Client.HTTP3.Frames.Frame_Header;
      Stream_ID : Http_Client.HTTP3.Frames.Varint_Value;
   begin
      Assert
        (Http_Client.HTTP3.Frames.Encode_Varint (0) = "" & Character'Val (0),
         "varint zero should use one byte");
      Assert
        (Http_Client.HTTP3.Frames.Encode_Varint (63) = "" & Character'Val (63),
         "varint 63 should use one byte");
      Assert
        (Http_Client.HTTP3.Frames.Encode_Varint (64)
         = ("" & Character'Val (16#40#) & Character'Val (16#40#)),
         "varint 64 should use shortest two-byte form");
      Assert
        (Http_Client.HTTP3.Frames.Decode_Varint
           ("" & Character'Val (16#40#), Value, Used)
         = Http_Client.Errors.Incomplete_Message,
         "truncated two-byte varint should be incomplete");
      Assert
        (Http_Client.HTTP3.Frames.Decode_Varint
           ("" & Character'Val (16#40#) & Character'Val (16#00#), Value, Used)
         = Http_Client.Errors.Ok
         and then Value = 0
         and then Used = 2,
         "protocol-valid non-shortest QUIC varint encodings should decode");

      Header :=
        (Kind => Http_Client.HTTP3.Frames.DATA, Raw_Type => 0, Length => 3);
      Assert
        (Http_Client.HTTP3.Frames.Serialize_Frame (Header, "abc", Outp)
         = Http_Client.Errors.Ok,
         "DATA frame serialization should succeed");
      Assert
        (To_String (Outp) = "" & Character'Val (0) & Character'Val (3) & "abc",
         "DATA frame serialization should be byte-exact");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Frame (To_String (Outp), 16_384, Item)
         = Http_Client.Errors.Ok,
         "serialized DATA frame should parse");
      Assert
        (Item.Header.Kind = Http_Client.HTTP3.Frames.DATA
         and then Item.Header.Length = 3
         and then To_String (Item.Payload) = "abc",
         "parsed DATA frame should preserve type, length, and payload");

      Header :=
        (Kind => Http_Client.HTTP3.Frames.UNKNOWN, Raw_Type => 0, Length => 0);
      Assert
        (Http_Client.HTTP3.Frames.Serialize_Frame (Header, "", Outp)
         = Http_Client.Errors.HTTP3_Frame_Error,
         "UNKNOWN frame serialization must not mask a known HTTP/3 frame type");

      Header :=
        (Kind     => Http_Client.HTTP3.Frames.UNKNOWN,
         Raw_Type => 16#21#,
         Length   => 1);
      Assert
        (Http_Client.HTTP3.Frames.Serialize_Frame
           (Header, "" & Character'Val (16#AA#), Outp)
         = Http_Client.Errors.Ok,
         "unknown HTTP/3 frames should serialize for skip handling");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Frame (To_String (Outp), 16_384, Item)
         = Http_Client.Errors.Ok,
         "unknown HTTP/3 frames should parse within bounds");
      Assert
        (Item.Header.Kind = Http_Client.HTTP3.Frames.UNKNOWN
         and then
           Http_Client.HTTP3.Frames.Skip_Unknown_Frame (Item.Header, 16_384)
           = Http_Client.Errors.Ok,
         "unknown HTTP/3 frame should be skippable within size limits");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Frame
           ("" & Character'Val (0) & Character'Val (5) & "abc", 16_384, Item)
         = Http_Client.Errors.Incomplete_Message,
         "truncated HTTP/3 frame payload should be rejected");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Frame
           ("" & Character'Val (0) & Character'Val (3) & "abc", 2, Item)
         = Http_Client.Errors.Response_Too_Large,
         "oversized HTTP/3 frame payload should be rejected before allocation");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Goaway_Payload
           (Http_Client.HTTP3.Frames.Encode_Varint (0), Stream_ID)
         = Http_Client.Errors.Ok
         and then Stream_ID = 0,
         "GOAWAY payload with a client-initiated bidirectional stream id should parse");
      Assert
        (Http_Client.HTTP3.Frames.Parse_Goaway_Payload
           (Http_Client.HTTP3.Frames.Encode_Varint (2), Stream_ID)
         = Http_Client.Errors.HTTP3_Goaway,
         "GOAWAY payload with a non-client-bidirectional stream id should be rejected");
   end Test_HTTP3_Varint_And_Frame_Binary;

   procedure Test_HTTP3_Settings_Streams_And_QPACK

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Payload   : Unbounded_String;
      Settings  : Http_Client.HTTP3.Settings.Settings_Record;
      Field     : Http_Client.HTTP3.QPACK.Header_Field;
      Encoded   : Unbounded_String;
      Used      : Natural;
      Hdr_Block : constant String :=
        Http_Client.HTTP3.QPACK.Encode_Header_Block_Prefix;
   begin
      Assert
        (Hdr_Block = "" & Character'Val (0) & Character'Val (0),
         "no-dynamic-table QPACK header-block prefix should be zero/zero");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Header_Block_Prefix (Hdr_Block, Used)
         = Http_Client.Errors.Ok
         and then Used = 2,
         "no-dynamic-table QPACK header-block prefix should decode exactly");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Header_Block_Prefix
           ("" & Character'Val (1) & Character'Val (0), Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK header-block prefixes requiring dynamic table state should be rejected");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Header_Block_Prefix
           ("" & Character'Val (0) & Character'Val (1), Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK header-block prefixes with nonzero base should be rejected");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Header_Block_Prefix
           ("" & Character'Val (0) & Character'Val (16#80#), Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK header-block prefixes with dynamic base sign bits should be rejected");
      Assert
        (Http_Client.HTTP3.Settings.Serialize_Payload
           (Http_Client.HTTP3.Settings.Default_Settings, Payload)
         = Http_Client.Errors.Ok,
         "default HTTP/3 SETTINGS should serialize");
      Assert
        (Http_Client.HTTP3.Settings.Parse_Payload
           (To_String (Payload), Settings)
         = Http_Client.Errors.Ok,
         "default HTTP/3 SETTINGS should parse");
      Assert
        (Settings.QPACK_Max_Table_Capacity = 0
         and then Settings.QPACK_Blocked_Streams = 0,
         "experimental HTTP/3 foundation SETTINGS should keep QPACK dynamic table disabled");
      Assert
        (Http_Client.HTTP3.Settings.Parse_Payload
           (Http_Client.HTTP3.Frames.Encode_Varint
              (Http_Client.HTTP3.Frames.Varint_Value
                 (Http_Client.HTTP3.Settings.SETTINGS_QPACK_BLOCKED_STREAMS))
            & Character'Val (1),
            Settings)
         = Http_Client.Errors.HTTP3_Settings_Error,
         "nonzero QPACK blocked streams should be rejected while dynamic table is unsupported");

      Assert
        (Http_Client.HTTP3.Settings.Parse_Payload
           (Http_Client.HTTP3.Frames.Encode_Varint
              (Http_Client.HTTP3.Frames.Varint_Value
                 (Http_Client
                    .HTTP3
                    .Settings
                    .SETTINGS_QPACK_MAX_TABLE_CAPACITY))
            & Character'Val (0)
            & Http_Client.HTTP3.Frames.Encode_Varint
                (Http_Client.HTTP3.Frames.Varint_Value
                   (Http_Client
                      .HTTP3
                      .Settings
                      .SETTINGS_QPACK_MAX_TABLE_CAPACITY))
            & Character'Val (0),
            Settings)
         = Http_Client.Errors.HTTP3_Settings_Error,
         "duplicate HTTP/3 SETTINGS identifiers should be rejected deterministically");

      Assert
        (Http_Client.HTTP3.Streams.Validate_Frame_On_Stream
           (Http_Client.HTTP3.Streams.Request_Bidirectional,
            Http_Client.HTTP3.Frames.HEADERS)
         = Http_Client.Errors.Ok,
         "HEADERS should be allowed on request streams");
      Assert
        (Http_Client.HTTP3.Streams.Validate_Frame_On_Stream
           (Http_Client.HTTP3.Streams.Request_Bidirectional,
            Http_Client.HTTP3.Frames.SETTINGS)
         = Http_Client.Errors.HTTP3_Stream_Error,
         "SETTINGS must not appear on request streams");
      Assert
        (Http_Client.HTTP3.Streams.Validate_Frame_On_Stream
           (Http_Client.HTTP3.Streams.Control_Unidirectional,
            Http_Client.HTTP3.Frames.PUSH_PROMISE)
         = Http_Client.Errors.HTTP3_Unsupported,
         "server push frames remain unsupported");

      Assert
        (Http_Client.HTTP3.Streams.Validate_Frame_On_Stream
           (Http_Client.HTTP3.Streams.Control_Unidirectional,
            Http_Client.HTTP3.Frames.DATA)
         = Http_Client.Errors.HTTP3_Stream_Error,
         "DATA must not appear on the HTTP/3 control stream");

      Assert
        (Http_Client.HTTP3.QPACK.Encode_Literal_Field_Line
           (":method", "GET", True, Encoded)
         = Http_Client.Errors.Ok,
         "literal QPACK pseudo-header should encode without dynamic indexing");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
           (To_String (Encoded), Field, Used)
         = Http_Client.Errors.Ok,
         "literal QPACK field line should decode");
      Assert
        (To_String (Field.Name) = ":method"
         and then To_String (Field.Value) = "GET"
         and then Field.Sensitive
         and then Used = Length (Encoded),
         "decoded QPACK sensitive literal field should preserve name, value, never-index flag, and length");
      Assert
        (Character'Pos (To_String (Encoded) (1)) = 16#30#,
         "sensitive QPACK literal field lines should set the never-indexed bit");
      Assert
        (Http_Client.HTTP3.QPACK.Encode_Literal_Field_Line
           ("x-test", "ok", False, Encoded)
         = Http_Client.Errors.Ok,
         "non-sensitive literal QPACK field should encode");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
           (To_String (Encoded), Field, Used)
         = Http_Client.Errors.Ok
         and then not Field.Sensitive,
         "non-sensitive literal QPACK field should decode without the never-indexed bit");
      Assert
        (Http_Client.HTTP3.QPACK.Encode_Literal_Field_Line
           ("Connection", "close", False, Encoded)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "uppercase and connection-specific HTTP/3 headers should be rejected");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_String_Literal
           ("" & Character'Val (16#80#), Encoded, Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "Huffman-coded QPACK strings should be rejected in experimental HTTP/3 foundation");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
           ("" & Character'Val (16#28#), Field, Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "Huffman-coded QPACK literal field names should be rejected in experimental HTTP/3 foundation");
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
           ("" & Character'Val (16#80#), Field, Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK dynamic/static indexed field-line forms outside the experimental HTTP/3 subset should be rejected");
   end Test_HTTP3_Settings_Streams_And_QPACK;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("HTTP3");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_HTTP3_Config_And_Unsupported_Execution'Access,
         "Test_HTTP3_Config_And_Unsupported_Execution");
      Register_Routine
        (T,
         Test_HTTP3_Request_Response_Mapping'Access,
         "Test_HTTP3_Request_Response_Mapping");
      Register_Routine
        (T,
         Test_HTTP3_Git_Metadata_And_Binary_Body'Access,
         "Test_HTTP3_Git_Metadata_And_Binary_Body");
      Register_Routine
        (T,
         Test_HTTP3_Varint_And_Frame_Binary'Access,
         "Test_HTTP3_Varint_And_Frame_Binary");
      Register_Routine
        (T,
         Test_HTTP3_Settings_Streams_And_QPACK'Access,
         "Test_HTTP3_Settings_Streams_And_QPACK");
   end Register_Tests;

end Http_Client.HTTP3.Tests;
