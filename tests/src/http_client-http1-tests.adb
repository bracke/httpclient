with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

pragma Style_Checks (Off);
with GNAT.Sockets; use GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Async;
with Http_Client.Clients;
with Http_Client.Cookies;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Body_Streams;
with Http_Client.HTTP1.Reader;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.HTTP1.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Responses.HTTP_Version;
   use type Http_Client.HTTP3.HTTP3_Mode;

   procedure Configure_Test_Socket_Timeouts
     (Socket : GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Receive_Timeout,
          Timeout => 1.0));
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Send_Timeout,
          Timeout => 1.0));
   exception
      when others =>
         null;
   end Configure_Test_Socket_Timeouts;

   procedure Apply_Test_Timeouts
     (Options : in out Http_Client.Clients.Execution_Options) is
      Bounded : constant Http_Client.Transports.TCP.Timeout_Config :=
        (Connect => 200,
         Read    => 200,
         Write   => 200);
   begin
      Options.Timeouts := Bounded;
      Options.TLS.Timeouts := Bounded;
   end Apply_Test_Timeouts;

   procedure Apply_Test_Timeouts
     (Options : in out Http_Client.Response_Streams.Streaming_Options) is
      Bounded : constant Http_Client.Transports.TCP.Timeout_Config :=
        (Connect => 200,
         Read    => 200,
         Write   => 200);
   begin
      Options.Timeouts := Bounded;
      Options.TLS.Timeouts := Bounded;
   end Apply_Test_Timeouts;

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

   procedure Test_HTTP1_Basic_GET_Serialization

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok ("http://example.com/", URI, "basic HTTP/1.1 GET URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "basic GET request should construct");

      Assert_Serialize_Ok
        (Request,
         "GET / HTTP/1.1" & CRLF & "Host: example.com" & CRLF & CRLF,
         "basic GET serialization");
   end Test_HTTP1_Basic_GET_Serialization;

   procedure Test_HTTP1_Method_Tokens_All_Known

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);

      procedure Check
        (Method : Http_Client.Types.Method_Name; Expected : String) is
      begin
         Assert
           (Http_Client.Requests.Create
              (Method => Method, URI => URI, Item => Request)
            = Http_Client.Errors.Ok,
            Expected & " request should construct for method serialization");

         Assert_Serialize_Ok
           (Request,
            Expected
            & " /methods HTTP/1.1"
            & CRLF
            & "Host: example.com"
            & CRLF
            & CRLF,
            Expected & " method token serialization");
      end Check;
   begin
      Assert_Parse_Ok
        ("http://example.com/methods",
         URI,
         "URI for all known method token serialization");

      Check (Http_Client.Types.GET, "GET");
      Check (Http_Client.Types.HEAD, "HEAD");
      Check (Http_Client.Types.POST, "POST");
      Check (Http_Client.Types.PUT, "PUT");
      Check (Http_Client.Types.PATCH, "PATCH");
      Check (Http_Client.Types.DELETE, "DELETE");
      Check (Http_Client.Types.OPTIONS, "OPTIONS");
   end Test_HTTP1_Method_Tokens_All_Known;

   procedure Test_HTTP1_CRLF_Line_Endings_And_Terminator

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Output  : Unbounded_String;
      Text    : Unbounded_String;
      CR      : constant Character := Character'Val (13);
      LF      : constant Character := Character'Val (10);
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/lines",
         URI,
         "URI for CRLF line ending verification");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Payload => "abc")
         = Http_Client.Errors.Ok,
         "CRLF verification request should construct");

      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Ok,
         "CRLF verification serialization",
         Output);

      Text := Output;

      for Index in 1 .. Length (Text) loop
            C : constant Character := Element (Text, Index);
         begin
            if C = LF then
               Assert
                 (Index > 1 and then Element (Text, Index - 1) = CR,
                  "serializer must not emit LF without preceding CR");
            elsif C = CR then
               Assert
                 (Index < Length (Text)
                  and then Element (Text, Index + 1) = LF,
                  "serializer must not emit CR without following LF");
            end if;
         end;
      end loop;

      Assert
        (Index (Text, CRLF & CRLF) > 0,
         "serializer should emit final blank header line before payload");

      Assert
        (Slice (Text, Length (Text) - 2, Length (Text)) = "abc",
         "payload should follow the CRLF CRLF header terminator");
   end Test_HTTP1_CRLF_Line_Endings_And_Terminator;

   procedure Test_HTTP1_Query_Empty_Path_And_Fragment

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("https://example.com?x=1#hidden",
         URI,
         "HTTPS URI with empty path, query, and fragment");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "query request should construct");

      Assert_Serialize_Ok
        (Request,
         "GET /?x=1 HTTP/1.1" & CRLF & "Host: example.com" & CRLF & CRLF,
         "request target should use slash, preserve query, and omit fragment");
   end Test_HTTP1_Query_Empty_Path_And_Fragment;

   procedure Test_HTTP1_Explicit_Empty_Query_Target

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/path?",
         URI,
         "URI with explicit empty query for serialization");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "empty-query request should construct");

      Assert_Serialize_Ok
        (Request,
         "GET /path? HTTP/1.1" & CRLF & "Host: example.com" & CRLF & CRLF,
         "explicit empty query should be preserved in request line");
   end Test_HTTP1_Explicit_Empty_Query_Target;

   procedure Test_HTTP1_Synthesizes_Host_When_Absent

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/no-host",
         URI,
         "URI for serializer Host synthesis");

      Assert
        (Http_Client.Requests.Create
           (Method    => Http_Client.Types.OPTIONS,
            URI       => URI,
            Item      => Request,
            Auto_Host => False)
         = Http_Client.Errors.Ok,
         "request without Host should construct when Auto_Host is disabled");

      Assert_Serialize_Ok
        (Request,
         "OPTIONS /no-host HTTP/1.1"
         & CRLF
         & "Host: example.com"
         & CRLF
         & CRLF,
         "serializer should synthesize missing Host header");
   end Test_HTTP1_Synthesizes_Host_When_Absent;

   procedure Test_HTTP1_Preserves_Explicit_Host_And_Order

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/order",
         URI,
         "URI for explicit Host and header order serialization");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "X-First", "1"),
         "first ordered header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Host", "caller.example"),
         "explicit Host should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "X-Second", "2"),
         "second ordered header should be accepted");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "request with explicit Host should construct");

      Assert_Serialize_Ok
        (Request,
         "GET /order HTTP/1.1"
         & CRLF
         & "X-First: 1"
         & CRLF
         & "Host: caller.example"
         & CRLF
         & "X-Second: 2"
         & CRLF
         & CRLF,
         "serializer should preserve explicit Host and insertion order");
   end Test_HTTP1_Preserves_Explicit_Host_And_Order;

   procedure Test_HTTP1_Payload_And_Content_Length

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/upload", URI, "URI for payload serialization");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "POST payload request should construct");

      Assert_Serialize_Ok
        (Request,
         "POST /upload HTTP/1.1"
         & CRLF
         & "Host: example.com"
         & CRLF
         & "Content-Length: 7"
         & CRLF
         & CRLF
         & "payload",
         "serializer should synthesize Content-Length before payload");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "7"),
         "matching Content-Length should be accepted by header model");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.PUT,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "PUT payload request with explicit Content-Length should construct");

      Assert_Serialize_Ok
        (Request,
         "PUT /upload HTTP/1.1"
         & CRLF
         & "Content-Length: 7"
         & CRLF
         & "Host: example.com"
         & CRLF
         & CRLF
         & "payload",
         "serializer should preserve matching explicit Content-Length");
   end Test_HTTP1_Payload_And_Content_Length;

   procedure Test_HTTP1_Content_Length_Rejections

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Output  : Unbounded_String;
   begin
      Assert_Parse_Ok
        ("http://example.com/upload",
         URI,
         "URI for Content-Length rejection tests");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "8"),
         "mismatched Content-Length header should be constructible");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "mismatched Content-Length request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Protocol_Error,
         "mismatched Content-Length serialization",
         Output);

      Headers := Http_Client.Headers.Empty;
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Content-Length", "7"),
         "first duplicate Content-Length should be constructible");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Content-Length", "7"),
         "second duplicate Content-Length should be constructible");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "duplicate Content-Length request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Header,
         "duplicate Content-Length serialization",
         Output);

      Headers := Http_Client.Headers.Empty;
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "abc"),
         "non-numeric Content-Length should be constructible");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "invalid Content-Length request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Header,
         "non-numeric Content-Length serialization",
         Output);

      Headers := Http_Client.Headers.Empty;
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "-1"),
         "negative Content-Length should be constructible as a header value");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "negative Content-Length request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Header,
         "negative Content-Length serialization",
         Output);
   end Test_HTTP1_Content_Length_Rejections;

   procedure Test_HTTP1_Content_Length_Zero_Without_Payload

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Output  : Unbounded_String;
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/empty-body",
         URI,
         "URI for zero Content-Length without payload");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "0"),
         "zero Content-Length should be accepted by header model");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "request with explicit zero Content-Length should construct");

      Assert_Serialize_Ok
        (Request,
         "POST /empty-body HTTP/1.1"
         & CRLF
         & "Content-Length: 0"
         & CRLF
         & "Host: example.com"
         & CRLF
         & CRLF,
         "explicit zero Content-Length should be valid without payload");

      Headers := Http_Client.Headers.Empty;
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Length", "1"),
         "nonzero Content-Length without payload should be constructible");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "request with mismatched zero-length payload should construct");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Protocol_Error,
         "nonzero Content-Length without payload serialization",
         Output);
   end Test_HTTP1_Content_Length_Zero_Without_Payload;

   procedure Test_HTTP1_Rejects_Duplicate_And_Empty_Host

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Output  : Unbounded_String;
   begin
      Assert_Parse_Ok
        ("http://example.com/host-validation",
         URI,
         "URI for Host validation during serialization");

      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Host", "one.example"),
         "first duplicate Host should be constructible");
      Assert_Header_Status
        (Http_Client.Headers.Add (Headers, "Host", "two.example"),
         "second duplicate Host should be constructible");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "duplicate Host request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Header,
         "duplicate Host serialization",
         Output);

      Headers := Http_Client.Headers.Empty;
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Host", ""),
         "empty Host should be constructible as a header value");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "empty Host request should construct before serialization");
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Header,
         "empty Host serialization",
         Output);
   end Test_HTTP1_Rejects_Duplicate_And_Empty_Host;

   procedure Test_HTTP1_Rejects_Invalid_Default_Request

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      Request : constant Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Output  : Unbounded_String;
   begin
      Assert_Serialize_Status
        (Request,
         Http_Client.Errors.Invalid_Request,
         "invalid default request serialization",
         Output);
   end Test_HTTP1_Rejects_Invalid_Default_Request;

   procedure Test_HTTP1_Absolute_Form_Proxy_Serialization

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert_Parse_Ok
        ("http://Example.COM:8081/proxy/path?x=1#frag",
         URI,
         "absolute-form serialization URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "absolute-form serialization request should construct");

      Assert
        (Http_Client.HTTP1.Serialize_Request
           (Request, Output, Http_Client.HTTP1.Absolute_Form)
         = Http_Client.Errors.Ok,
         "absolute-form serialization should succeed");

      Assert
        (Ada.Strings.Unbounded.To_String (Output)
         = "GET http://example.com:8081/proxy/path?x=1 HTTP/1.1"
           & CRLF
           & "Host: example.com:8081"
           & CRLF
           & CRLF,
         "absolute-form request line should include full origin URI without fragment");
   end Test_HTTP1_Absolute_Form_Proxy_Serialization;

   procedure Test_Default_Response
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Response : constant Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
   begin
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "default response should use status code 200");

      Assert
        (Http_Client.Headers.Length (Http_Client.Responses.Headers (Response))
         = 0,
         "default response should have no headers");
   end Test_Default_Response;

   procedure Test_HTTP1_Response_Parse_Valid_Minimal
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK" & CRLF & CRLF, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "minimal HTTP/1.1 response should parse");

      Assert
        (Http_Client.Responses.Version (Response)
         = Http_Client.Responses.HTTP_1_1,
         "minimal response should record HTTP/1.1");

      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "minimal response should record status 200");

      Assert
        (Http_Client.Responses.Reason_Phrase (Response) = "OK",
         "minimal response should preserve reason phrase");

      Assert
        (Http_Client.Headers.Length (Http_Client.Responses.Headers (Response))
         = 0,
         "minimal response should have no headers");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "minimal response should have empty body");
   end Test_HTTP1_Response_Parse_Valid_Minimal;

   procedure Test_HTTP1_Response_Parse_Content_Length_Body
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & CRLF
           & "Content-Type: text/plain"
           & CRLF
           & "X-Test: first"
           & CRLF
           & "x-test: second"
           & CRLF
           & "Content-Length: 5"
           & CRLF
           & CRLF
           & "Hello",
           Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "response with fixed Content-Length body should parse");

      Assert
        (Http_Client.Headers.Contains
           (Http_Client.Responses.Headers (Response), "content-type"),
         "response header lookup should be case-insensitive");

      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Response), "CONTENT-TYPE")
         = "text/plain",
         "response header value should be retrievable case-insensitively");

      Assert
        (Http_Client.Headers.Count
           (Http_Client.Responses.Headers (Response), "X-Test")
         = 2,
         "ordinary duplicate response headers should be preserved");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "Hello",
         "fixed response body should be stored exactly");
   end Test_HTTP1_Response_Parse_Content_Length_Body;

   procedure Test_HTTP1_Response_Parse_Empty_Reason_And_HTTP10
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.0 204 " & CRLF & "Content-Length: 0" & CRLF & CRLF,
           Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTP/1.0 response with empty reason phrase should parse");

      Assert
        (Http_Client.Responses.Version (Response)
         = Http_Client.Responses.HTTP_1_0,
         "HTTP/1.0 policy should be accepted and recorded");

      Assert
        (Http_Client.Responses.Reason_Phrase (Response) = "",
         "empty reason phrase should be preserved as empty");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "204 response should not require or store a body");
   end Test_HTTP1_Response_Parse_Empty_Reason_And_HTTP10;

   procedure Test_HTTP1_Response_Parse_No_Body_Statuses_And_HEAD
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 304 Not Modified" & CRLF & CRLF, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "304 without Content-Length should parse as no-body response");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "304 response body should be empty");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK" & CRLF & CRLF,
           Response,
           (Request_Was_HEAD => True));

      Assert
        (Status = Http_Client.Errors.Ok,
         "HEAD response context should parse without requiring body framing");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "HEAD response body should be empty");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & CRLF & CRLF & "unexpected",
            Response,
            (Request_Was_HEAD => True))
         = Http_Client.Errors.Protocol_Error,
         "HEAD response context should reject unexpected trailing body bytes");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 205 Reset Content" & CRLF & CRLF, Response)
         = Http_Client.Errors.Ok,
         "205 response without body should parse as no-body response");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 101 Switching Protocols" & CRLF & CRLF, Response)
         = Http_Client.Errors.Ok,
         "1xx response without body should parse as no-body response");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 204 No Content" & CRLF & CRLF & "unexpected", Response)
         = Http_Client.Errors.Protocol_Error,
         "no-body status should reject unexpected trailing body bytes");
   end Test_HTTP1_Response_Parse_No_Body_Statuses_And_HEAD;

   procedure Test_HTTP1_Response_Parse_No_Content_Length_Body
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK" & CRLF & CRLF & "tail-body", Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "response without Content-Length should treat trailing bytes as body");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "tail-body",
         "no-Content-Length body policy should store trailing bytes");
   end Test_HTTP1_Response_Parse_No_Content_Length_Body;

   procedure Test_HTTP1_Response_Parse_Invalid_Status_Lines
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
   begin
      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/2 200 OK" & CRLF & CRLF, Response)
         = Http_Client.Errors.Protocol_Error,
         "unsupported or malformed protocol version should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 ABC OK" & CRLF & CRLF, Response)
         = Http_Client.Errors.Protocol_Error,
         "non-numeric status code should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 099 Low" & CRLF & CRLF, Response)
         = Http_Client.Errors.Protocol_Error,
         "out-of-range status code should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & Character'Val (10) & Character'Val (10),
            Response)
         = Http_Client.Errors.Protocol_Error,
         "LF-only response should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200OK" & CRLF & CRLF, Response)
         = Http_Client.Errors.Protocol_Error,
         "missing status-line space should be rejected");
   end Test_HTTP1_Response_Parse_Invalid_Status_Lines;

   procedure Test_HTTP1_Response_Parse_Incomplete_And_Length_Mismatch
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
   begin
      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 5", Response)
         = Http_Client.Errors.Incomplete_Message,
         "missing header terminator should report incomplete message");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Length: 5"
            & CRLF
            & CRLF
            & "abc",
            Response)
         = Http_Client.Errors.Incomplete_Message,
         "truncated Content-Length body should report incomplete message");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Length: 2"
            & CRLF
            & CRLF
            & "abcd",
            Response)
         = Http_Client.Errors.Protocol_Error,
         "extra bytes after fixed Content-Length should be rejected");
   end Test_HTTP1_Response_Parse_Incomplete_And_Length_Mismatch;

   procedure Test_HTTP1_Response_Parse_Additional_Edges
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 204 No Content" & CRLF & CRLF, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "204 without Content-Length should parse as a no-body response");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "204 without Content-Length should store an empty body");

      Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: "
           & Character'Val (9)
           & "3 "
           & CRLF
           & CRLF
           & "abc",
           Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "Content-Length should allow surrounding optional whitespace");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "abc",
         "body with whitespace-trimmed Content-Length should parse exactly");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length : 0" & CRLF & CRLF,
            Response)
         = Http_Client.Errors.Invalid_Header,
         "field name whitespace before colon should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & CRLF & "Header-Without-Colon" & CRLF & CRLF,
            Response)
         = Http_Client.Errors.Invalid_Header,
         "header line without colon should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & Character'Val (13)
            & Character'Val (13)
            & Character'Val (10),
            Response)
         = Http_Client.Errors.Protocol_Error,
         "bare CR in response line ending should be rejected");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 bad" & Character'Val (127) & CRLF & CRLF, Response)
         = Http_Client.Errors.Protocol_Error,
         "control characters in reason phrase should be rejected");
   end Test_HTTP1_Response_Parse_Additional_Edges;

   procedure Test_Client_And_Transport_Availability
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Client : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Assert
        (Http_Client.Clients.Supports_Network_IO (Client),
         "client should report minimal network I/O support");

      Assert
        (Http_Client.Transports.Is_Implemented
           (Http_Client.Transports.Plain_HTTP),
         "plain HTTP transport should remain implemented");

      Assert
        (Http_Client.Transports.Is_Implemented
           (Http_Client.Transports.HTTPS_TLS),
         "HTTPS/TLS transport should remain implemented");
   end Test_Client_And_Transport_Availability;

   procedure Test_Client_Cookie_Stateless_No_Jar_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Stateless_Cookie_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Stateless_Cookie_Server;

      task body Stateless_Cookie_Server is
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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request (First_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Set-Cookie: sid=stateless; Path=/app"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Requests_Seen
              (First : out Unbounded_String; Second : out Unbounded_String)
            do
               First := First_Text;
               Second := Second_Text;
            end Requests_Seen;
         or
            delay 2.0;
         end select;
      end Stateless_Cookie_Server;

      Server      : Stateless_Cookie_Server;
      Port        : Http_Client.URI.TCP_Port;
      Login_URI   : Http_Client.URI.URI_Reference;
      Page_URI    : Http_Client.URI.URI_Reference;
      Login_Req   : Http_Client.Requests.Request;
      Page_Req    : Http_Client.Requests.Request;
      Response    : Http_Client.Responses.Response;
      Options     : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/login",
         Login_URI,
         "stateless cookie login URI should parse");
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/page",
         Page_URI,
         "stateless cookie page URI should parse");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => Login_URI,
            Item   => Login_Req)
         = Http_Client.Errors.Ok,
         "stateless cookie login request should construct");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => Page_URI, Item => Page_Req)
         = Http_Client.Errors.Ok,
         "stateless cookie page request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Login_Req, Response, Options)
         = Http_Client.Errors.Ok,
         "first stateless cookie request should succeed");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Response), "Set-Cookie")
         = "sid=stateless; Path=/app",
         "Set-Cookie should remain visible as an ordinary response header");

      Assert
        (Http_Client.Clients.Execute_Once (Page_Req, Response, Options)
         = Http_Client.Errors.Ok,
         "second stateless cookie request should succeed");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "Cookie:") = 0,
         "first stateless request should not have a Cookie header");
      Assert
        (Index (Second_Text, "Cookie:") = 0,
         "no jar means Set-Cookie must not be replayed later");
   end Test_Client_Cookie_Stateless_No_Jar_Loopback;

   procedure Test_Client_Strict_Cookie_Error_Preserves_Response_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Strict_Cookie_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Strict_Cookie_Server;

      task body Strict_Cookie_Server is
         Server        : GNAT.Sockets.Socket_Type;
         Peer          : GNAT.Sockets.Socket_Type;
         Server_Addr   : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr     : GNAT.Sockets.Sock_Addr_Type;
         Request_Text  : Unbounded_String;
         Raw           : Stream_Element_Array (1 .. 4096);
         Last          : Stream_Element_Offset;
         Response_Text : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Set-Cookie: sid=x; Domain=attacker.test"
           & CRLF
           & "Content-Length: 0"
           & CRLF
           & CRLF;
         Response_Raw  :
           Stream_Element_Array
             (1 .. Stream_Element_Offset (Response_Text'Length));
         Sent_Last     : Stream_Element_Offset;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         Request_Text := Null_Unbounded_String;
         if Last >= Raw'First then
            for Index in Raw'First .. Last loop
               Append (Request_Text, Character'Val (Raw (Index)));
            end loop;
         end if;

         for Index in Response_Raw'Range loop
            Response_Raw (Index) :=
              Stream_Element
                (Character'Pos
                   (Response_Text
                      (Response_Text'First
                       + Natural (Index - Response_Raw'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Response_Raw, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Strict_Cookie_Server;

      Server       : Strict_Cookie_Server;
      Port         : Http_Client.URI.TCP_Port;
      URI          : Http_Client.URI.URI_Reference;
      Request      : Http_Client.Requests.Request;
      Response     : Http_Client.Responses.Response;
      Jar          : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Options      : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Request_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Cookie_Jar := Jar'Unchecked_Access;
      Options.Strict_Cookies := True;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/login",
         URI,
         "strict cookie URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "strict cookie request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response, Options)
         = Http_Client.Errors.Cookie_Rejected,
         "strict cookie execution should report rejected Set-Cookie after parsing response");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "strict cookie error should still leave the parsed response available");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Response), "Set-Cookie")
         = "sid=x; Domain=attacker.test",
         "strict cookie error should not hide the ordinary Set-Cookie response header");
      Assert
        (Http_Client.Cookies.Length (Jar) = 0,
         "rejected strict cookie should not be stored");

      Server.Request_Seen (Request_Text);
      Assert
        (Index (Request_Text, "Cookie:") = 0,
         "strict test request should not have a generated Cookie header");
   end Test_Client_Strict_Cookie_Error_Preserves_Response_Loopback;

   procedure Test_Client_Cookie_Jar_Opt_In_And_Replay_Loopback
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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request (First_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Set-Cookie: sid=jar; Path=/app; HttpOnly"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Requests_Seen
              (First : out Unbounded_String; Second : out Unbounded_String)
            do
               First := First_Text;
               Second := Second_Text;
            end Requests_Seen;
         or
            delay 2.0;
         end select;
      end Cookie_Server;

      Server      : Cookie_Server;
      Port        : Http_Client.URI.TCP_Port;
      Login_URI   : Http_Client.URI.URI_Reference;
      Page_URI    : Http_Client.URI.URI_Reference;
      Login_Req   : Http_Client.Requests.Request;
      Page_Req    : Http_Client.Requests.Request;
      Response    : Http_Client.Responses.Response;
      Jar         : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Options     : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Cookie_Jar := Jar'Unchecked_Access;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/login",
         Login_URI,
         "cookie login URI should parse");
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/app/page",
         Page_URI,
         "cookie page URI should parse");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => Login_URI,
            Item   => Login_Req)
         = Http_Client.Errors.Ok,
         "cookie login request should construct");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => Page_URI, Item => Page_Req)
         = Http_Client.Errors.Ok,
         "cookie page request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Login_Req, Response, Options)
         = Http_Client.Errors.Ok,
         "first cookie-enabled request should succeed");
      Assert
        (Http_Client.Cookies.Length (Jar) = 1,
         "supplied jar should store Set-Cookie from the first response");

      Assert
        (Http_Client.Clients.Execute_Once (Page_Req, Response, Options)
         = Http_Client.Errors.Ok,
         "second cookie-enabled request should succeed");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "Cookie:") = 0,
         "first request should not invent a Cookie header before jar storage");
      Assert
        (Index (Second_Text, "Cookie: sid=jar") > 0,
         "second request should replay the stored matching cookie");
   end Test_Client_Cookie_Jar_Opt_In_And_Replay_Loopback;

   procedure Test_Client_Execute_Decoded_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Decode_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Decode_Server;

      task body Decode_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type(GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;

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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
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

         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 33"
            & CRLF
            & CRLF
            & Gzip_Body);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Decode_Server;

      Server        : Decode_Server;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Result        : Http_Client.Decompression.Decoded_Response;
      Captured_Text : Unbounded_String;
      Client        : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/gzip",
         URI,
         "decoded execution URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "decoded execution request should construct");

      Assert
        (Http_Client.Clients.Execute_Decoded
           (Item => Client, Request => Request, Result => Result)
         = Http_Client.Errors.Ok,
         "decoded execution should succeed");
      Assert
        (Http_Client.Decompression.Decoded (Result),
         "decoded execution should mark gzip body decoded");
      Assert
        (Http_Client.Decompression.Decoded_Body (Result) = "final decoded",
         "decoded execution should expose decompressed final body");
      Assert
        (Http_Client.Responses.Response_Body
           (Http_Client.Decompression.Original_Response (Result))
         = Gzip_Body,
         "decoded execution should preserve original encoded body");

      Server.Request_Seen (Captured_Text);
      Assert
        (Index (Captured_Text, "Accept-Encoding: gzip, deflate") > 0,
         "decoded execution should advertise only supported encodings");
   end Test_Client_Execute_Decoded_Loopback;

   procedure Test_Client_Execute_Decoded_Redirect_Final_Only
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Redirect_Decode_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Redirect_Decode_Server;

      task body Redirect_Decode_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Receive_Request is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end Receive_Request;

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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request;
         Send_Response
           ("HTTP/1.1 302 Found"
            & CRLF
            & "Location: /final"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Receive_Request;
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 33"
            & CRLF
            & CRLF
            & Gzip_Body);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Redirect_Decode_Server;

      Server    : Redirect_Decode_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Result    : Http_Client.Clients.Decoded_Redirect_Result;
      Redirects : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      Options   : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Client    : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Redirects.Follow_Redirects := True;
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "decoded redirect execution URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "decoded redirect request should construct");

      Assert
        (Http_Client.Clients.Execute_Decoded_Following_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Execution => Options,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "decoded redirect execution should succeed");
      Assert
        (Result.Redirect_Count = 1,
         "decoded redirect execution should follow one hop");
      Assert
        (Http_Client.Decompression.Decoded_Body (Result.Final_Response)
         = "final decoded",
         "decoded redirect execution should decode only final body");
   end Test_Client_Execute_Decoded_Redirect_Final_Only;

   procedure Test_Client_Plain_HTTP_Proxy_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Proxy_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Proxy_Server;

      task body Proxy_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type(GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;

         procedure Send_Response is
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
         end Send_Response;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

         loop
            declare
               Raw  : Stream_Element_Array (1 .. 4096);
               Last : Stream_Element_Offset;
            begin
               GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
               exit when Last < Raw'First;

               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;

               exit when Index (Request_Text, CRLF & CRLF) /= 0;
            end;
         end loop;

         Send_Response;
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Proxy_Server;

      Server     : Proxy_Server;
      Port       : Http_Client.URI.TCP_Port;
      Proxy      : Http_Client.Proxies.Proxy_Config;
      Auth_Proxy : Http_Client.Proxies.Proxy_Config;
      URI        : Http_Client.URI.URI_Reference;
      Request    : Http_Client.Requests.Request;
      Response   : Http_Client.Responses.Response;
      Options    : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Client     : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Captured   : Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);

      Assert
        (Http_Client.Proxies.Parse
           ("http://127.0.0.1:" & Decimal_Image (Natural (Port)), Proxy)
         = Http_Client.Errors.Ok,
         "loopback proxy URI should parse");
      Assert
        (Http_Client.Auth.Set_Basic_Proxy_Authorization
           (Proxy, "user", "pass", Auth_Proxy)
         = Http_Client.Errors.Ok,
         "explicit Basic proxy credentials should attach to proxy config");
      Options.Proxy := Auth_Proxy;

      Assert_Parse_Ok
        ("http://origin.example:8081/resource?q=1",
         URI,
         "proxied origin URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "proxied origin request should construct");

      Assert
        (Http_Client.Clients.Execute
           (Item     => Client,
            Request  => Request,
            Response => Response,
            Options  => Options)
         = Http_Client.Errors.Ok,
         "plain HTTP proxy execution should succeed through loopback proxy");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "proxied loopback response should be parsed as final response");

      Server.Request_Seen (Captured);
      Assert
        (To_String (Captured)
         = "GET http://origin.example:8081/resource?q=1 HTTP/1.1"
           & CRLF
           & "Host: origin.example:8081"
           & CRLF
           & "Connection: close"
           & CRLF
           & "Proxy-Authorization: Basic dXNlcjpwYXNz"
           & CRLF
           & CRLF,
         "proxied plain HTTP request should use absolute-form, origin Host, and proxy-only auth");
   end Test_Client_Plain_HTTP_Proxy_Loopback;

   procedure Test_Client_Retry_503_Then_200_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      First_Response : constant String :=
        "HTTP/1.1 503 Service Unavailable"
        & CRLF
        & "Retry-After: 0"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Loopback_Server;

      task body Loopback_Server is
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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request (First_Text);
         Send_Response (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request (Second_Text);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Requests_Seen
              (First : out Unbounded_String; Second : out Unbounded_String)
            do
               First := First_Text;
               Second := Second_Text;
            end Requests_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server      : Loopback_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      With_Auth   : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Retry_Result;
      Options     : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Execution   : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Status      : Http_Client.Errors.Result_Status;
      First_Seen  : Unbounded_String;
      Second_Seen : Unbounded_String;
      Port_Text   : Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Execution);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/retry",
         URI,
         "retry loopback URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "retry loopback GET request should construct");

      Assert
        (Http_Client.Auth.Set_Basic_Authorization
           (Request, "user", "pass", With_Auth)
         = Http_Client.Errors.Ok,
         "retry loopback request should accept explicit Basic origin credentials");

      Assert
        (not Http_Client.Headers.Contains
               (Http_Client.Requests.Headers (Request), "Authorization"),
         "Set_Basic_Authorization must not mutate the original retry request");

      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 2;
      Options.Retry_5xx_Responses := True;
      Options.Respect_Retry_After := True;
      Options.Maximum_Delay := 1_000;
      Options.Maximum_Retry_After := 1_000;

      Status :=
        Http_Client.Clients.Execute_Once_With_Retry
          (Request   => With_Auth,
           Result    => Result,
           Execution => Execution,
           Retries   => Options);

      Assert
        (Status = Http_Client.Errors.Ok,
         "503 followed by 200 should return Ok");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 200,
         "retry result should expose final successful response");

      Assert
        (Result.Attempts = 2,
         "503 followed by 200 should consume two attempts");

      Assert
        (not Result.Retries_Exhausted,
         "successful second attempt should not report exhaustion");

      Server.Requests_Seen (First_Seen, Second_Seen);

      Assert
        (To_String (First_Seen) = To_String (Second_Seen),
         "retry should serialize the same in-memory GET request on each attempt");

      Assert
        (Index (First_Seen, "Authorization: Basic dXNlcjpwYXNz") > 0,
         "first authenticated retry attempt should send explicit origin Authorization");

      Assert
        (Index (Second_Seen, "Authorization: Basic dXNlcjpwYXNz") > 0,
         "retried same-origin attempt should preserve explicit origin Authorization");
   end Test_Client_Retry_503_Then_200_Loopback;

   procedure Test_High_Level_Client_Redirect_Enabled_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Redirect_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Redirect_Server;

      task body Redirect_Server is
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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request (First_Text);
         Send_Response
           ("HTTP/1.1 302 Found"
            & CRLF
            & "Location: /final"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Length: 5"
            & CRLF
            & CRLF
            & "final");
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Requests_Seen
              (First : out Unbounded_String; Second : out Unbounded_String)
            do
               First := First_Text;
               Second := Second_Text;
            end Requests_Seen;
         or
            delay 2.0;
         end select;
      end Redirect_Server;

      Server      : Redirect_Server;
      Port        : Http_Client.URI.TCP_Port;
      Port_Text   : Unbounded_String;
      Config      : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client      : Http_Client.Clients.Client;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
      First_Seen  : Unbounded_String;
      Second_Seen : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Config.Redirects.Follow_Redirects := True;
      Config.Redirects.Max_Redirects := 2;

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level redirect client configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/start",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level GET should follow an enabled relative redirect");

      Assert
        (Http_Client.Responses.Response_Body (Result.Response) = "final",
         "high-level redirect result should expose final response body");

      Assert
        (Result.Redirect_Count = 1,
         "high-level redirect result should expose redirect count");

      Assert
        (Http_Client.URI.Path (Result.Final_URI) = "/final",
         "high-level redirect result should expose final URI");

      Server.Requests_Seen (First_Seen, Second_Seen);

      Assert
        (Index (First_Seen, "GET /start HTTP/1.1") = 1,
         "first high-level redirect request should target original path");

      Assert
        (Index (Second_Seen, "GET /final HTTP/1.1") = 1,
         "second high-level redirect request should target redirected path");
   end Test_High_Level_Client_Redirect_Enabled_Loopback;

   procedure Test_High_Level_Client_Retry_503_Then_200_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Retry_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Retry_Server;

      task body Retry_Server is
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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request (First_Text);
         Send_Response
           ("HTTP/1.1 503 Service Unavailable"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
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

         select
            accept Requests_Seen
              (First : out Unbounded_String; Second : out Unbounded_String)
            do
               First := First_Text;
               Second := Second_Text;
            end Requests_Seen;
         or
            delay 2.0;
         end select;
      end Retry_Server;

      Server      : Retry_Server;
      Port        : Http_Client.URI.TCP_Port;
      Port_Text   : Unbounded_String;
      Config      : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client      : Http_Client.Clients.Client;
      Result      : Http_Client.Clients.Client_Result;
      Status      : Http_Client.Errors.Result_Status;
      First_Seen  : Unbounded_String;
      Second_Seen : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Config.Retries.Enable_Retries := True;
      Config.Retries.Maximum_Attempts := 2;
      Config.Retries.Retry_5xx_Responses := True;

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level retry client configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/retry",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level retry should return final successful response");

      Assert
        (Http_Client.Responses.Status_Code (Result.Response) = 200,
         "high-level retry result should expose final 200 response");

      Assert
        (Result.Retry_Attempt_Count = 2,
         "high-level retry result should expose attempt count");

      Assert
        (not Result.Retry_Exhausted,
         "high-level successful retry result should not report exhaustion");

      Server.Requests_Seen (First_Seen, Second_Seen);

      Assert
        (To_String (First_Seen) = To_String (Second_Seen),
         "high-level retry should replay the same in-memory GET request");
   end Test_High_Level_Client_Retry_503_Then_200_Loopback;

   procedure Test_High_Level_Client_Retry_Exhaustion_Metadata_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 503 Service Unavailable"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

      task type Retry_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Retry_Server;

      task body Retry_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Drain_Request is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end Drain_Request;

         procedure Send_Response is
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
         end Send_Response;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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

         for Attempt in 1 .. 2 loop
            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
            Drain_Request;
            Send_Response;
            GNAT.Sockets.Close_Socket (Peer);
         end loop;

         GNAT.Sockets.Close_Socket (Server);
      end Retry_Server;

      Server    : Retry_Server;
      Port      : Http_Client.URI.TCP_Port;
      Port_Text : Unbounded_String;
      Config    : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client    : Http_Client.Clients.Client;
      Result    : Http_Client.Clients.Client_Result;
      Status    : Http_Client.Errors.Result_Status;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Config.Retries.Enable_Retries := True;
      Config.Retries.Maximum_Attempts := 2;
      Config.Retries.Retry_5xx_Responses := True;

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level retry exhaustion client configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/exhaust",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "exhausted high-level response-status retry should still return Ok with final response");

      Assert
        (Http_Client.Responses.Status_Code (Result.Response) = 503,
         "high-level retry exhaustion should expose final 503 response");

      Assert
        (Result.Retry_Attempt_Count = 2,
         "high-level retry exhaustion should expose attempts used");

      Assert
        (Result.Retry_Exhausted,
         "high-level retry exhaustion should expose exhausted retry metadata");
   end Test_High_Level_Client_Retry_Exhaustion_Metadata_Loopback;

   procedure Test_High_Level_Client_Decompression_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Decode_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Decode_Server;

      task body Decode_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;

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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

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

         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 33"
            & CRLF
            & CRLF
            & Gzip_Body);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Decode_Server;

      Server        : Decode_Server;
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

      Config.Enable_Decompression := True;

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level decompression client configuration should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/gzip",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level decompression should succeed for gzip response");

      Assert
        (Result.Used_Decoded_View,
         "high-level result should mark decoded view as active");

      Assert
        (Http_Client.Decompression.Decoded_Body (Result.Decoded_Response)
         = "final decoded",
         "high-level decoded response should expose decompressed body");

      Assert
        (Http_Client.Responses.Response_Body (Result.Response) = Gzip_Body,
         "high-level raw response should preserve encoded body");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Accept-Encoding: gzip, deflate") > 0,
         "high-level decompression should advertise supported encodings");
   end Test_High_Level_Client_Decompression_Loopback;

   procedure Test_High_Level_Client_Execute_Stream_Decompression_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Stream_Decode_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Stream_Decode_Server;

      task body Stream_Decode_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;

         procedure Send_Response (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

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

         Send_Response
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Encoding: gzip" & CRLF
            & "Content-Length: 33" & CRLF
            & CRLF
            & Gzip_Body);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Stream_Decode_Server;

      Server        : Stream_Decode_Server;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client        : Http_Client.Clients.Client;
      Stream        : Http_Client.Response_Streams.Streaming_Response;
      Status        : Http_Client.Errors.Result_Status;
      Buffer        : String (1 .. 4);
      Last          : Natural := 0;
      Decoded_Body  : Unbounded_String := Null_Unbounded_String;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Config.Enable_Decompression := True;
      Config.Decompression.Maximum_Decoded_Body_Size := 64;
      Config.Execution.Max_Body_Size := 128;

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming decompression client configuration should initialize");

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/gzip-stream-client",
         URI,
         "high-level streaming decompression URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "high-level streaming decompression request should construct");

      Status := Http_Client.Clients.Execute_Stream (Client, Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level Execute_Stream should open gzip response with decompression enabled");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "high-level Execute_Stream decompression read should succeed");
         if Last > 0 then
            Append (Decoded_Body, Buffer (Buffer'First .. Buffer'First + Last - 1));
         end if;
      end loop;

      Assert
        (To_String (Decoded_Body) = "final decoded",
         "high-level Execute_Stream should return decoded response bytes");

      Status := Http_Client.Response_Streams.Close (Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level Execute_Stream decompression stream should close cleanly");

      Server.Request_Seen (Captured_Text);
      Assert
        (Index (Captured_Text, "Accept-Encoding: gzip, deflate") > 0,
         "high-level Execute_Stream decompression should advertise supported encodings");
   end Test_High_Level_Client_Execute_Stream_Decompression_Loopback;

   procedure Test_Response_Stream_Decompression_Chunked_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Stream_Decode_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Stream_Decode_Server;

      task body Stream_Decode_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Send_Text (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Text;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end;

         Send_Text
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Encoding: gzip" & CRLF
            & "Transfer-Encoding: chunked" & CRLF
            & CRLF
            & "5;first=yes" & CRLF
            & Gzip_Body (Gzip_Body'First .. Gzip_Body'First + 4) & CRLF
            & "7" & CRLF
            & Gzip_Body (Gzip_Body'First + 5 .. Gzip_Body'First + 11) & CRLF
            & "15" & CRLF
            & Gzip_Body (Gzip_Body'First + 12 .. Gzip_Body'Last) & CRLF
            & "0" & CRLF
            & "X-Trailer: ignored" & CRLF
            & CRLF);

         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Stream_Decode_Server;

      Server  : Stream_Decode_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
      Buffer  : String (1 .. 3);
      Last    : Natural := 0;
      Decoded_Body : Unbounded_String := Null_Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Enable_Decompression := True;
      Options.Max_Body_Size := 128;
      Options.Decompression.Maximum_Decoded_Body_Size := 64;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/gzip-stream",
         URI,
         "streaming decompression URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "streaming decompression request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming decompression should open gzip chunked response");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "streaming decompression read should return decoded chunks");
         if Last > 0 then
            Append (Decoded_Body, Buffer (Buffer'First .. Buffer'First + Last - 1));
         end if;
      end loop;

      Assert
        (To_String (Decoded_Body) = "final decoded",
         "streaming decompression should expose decoded entity bytes only");
   end Test_Response_Stream_Decompression_Chunked_Loopback;

   procedure Test_Response_Stream_Decompression_Malformed_Gzip_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Bad_Gzip_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Bad_Gzip_Server;

      task body Bad_Gzip_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Send_Text (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Text;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end;

         Send_Text
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Encoding: gzip" & CRLF
            & "Content-Length: 9" & CRLF
            & CRLF
            & "not-gzip!");
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Bad_Gzip_Server;

      Server  : Bad_Gzip_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
      Buffer  : String (1 .. 8);
      Last    : Natural := 0;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Enable_Decompression := True;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/bad-gzip",
         URI,
         "malformed streaming gzip URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "malformed streaming gzip request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "malformed streaming gzip should still expose response metadata");

      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Decompression_Failed,
         "malformed streaming gzip should fail deterministically while reading");
   end Test_Response_Stream_Decompression_Malformed_Gzip_Loopback;

   procedure Test_Response_Stream_Decompression_Deflate_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Deflate_Body : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (34)
        & Character'Val (150)
        & Character'Val (4)
        & Character'Val (243);

      task type Deflate_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Deflate_Server;

      task body Deflate_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Send_Text (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Text;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end;

         Send_Text
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Encoding: deflate" & CRLF
            & "Transfer-Encoding: chunked" & CRLF
            & CRLF
            & "4" & CRLF
            & Deflate_Body (Deflate_Body'First .. Deflate_Body'First + 3) & CRLF
            & "11;split=yes" & CRLF
            & Deflate_Body (Deflate_Body'First + 4 .. Deflate_Body'Last) & CRLF
            & "0" & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Deflate_Server;

      Server  : Deflate_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
      Buffer  : Stream_Element_Array (1 .. 2);
      Last    : Stream_Element_Offset := 0;
      Decoded_Body : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Enable_Decompression := True;
      Options.Max_Body_Size := 128;
      Options.Decompression.Maximum_Decoded_Body_Size := 64;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/deflate-stream",
         URI,
         "streaming deflate URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "streaming deflate request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming decompression should open deflate chunked response");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "streaming deflate read should return decoded bytes");
         if Last >= Buffer'First then
            declare
               Text : String (1 .. Natural (Last - Buffer'First + 1));
            begin
               for I in Text'Range loop
                  Text (I) := Character'Val
                    (Buffer (Buffer'First + Stream_Element_Offset (I - Text'First)));
               end loop;
               Ada.Strings.Unbounded.Append (Decoded_Body, Text);
            end;
         end if;
      end loop;

      Assert
        (Ada.Strings.Unbounded.To_String (Decoded_Body) = "final decoded",
         "streaming deflate should expose decoded entity bytes only");
   end Test_Response_Stream_Decompression_Deflate_Loopback;

   procedure Test_Response_Stream_Decompression_Decoded_Size_Limit
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (117)
        & Character'Val (39)
        & Character'Val (7)
        & Character'Val (106)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (51)
        & Character'Val (48)
        & Character'Val (52)
        & Character'Val (50)
        & Character'Val (54)
        & Character'Val (49)
        & Character'Val (53)
        & Character'Val (51)
        & Character'Val (183)
        & Character'Val (176)
        & Character'Val (116)
        & Character'Val (116)
        & Character'Val (114)
        & Character'Val (118)
        & Character'Val (113)
        & Character'Val (117)
        & Character'Val (115)
        & Character'Val (247)
        & Character'Val (240)
        & Character'Val (244)
        & Character'Val (2)
        & Character'Val (0)
        & Character'Val (22)
        & Character'Val (16)
        & Character'Val (19)
        & Character'Val (104)
        & Character'Val (20)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Limit_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Limit_Server;

      task body Limit_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Send_Text (Text : String) is
            Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Text;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end;

         Send_Text
           ("HTTP/1.1 200 OK" & CRLF
            & "Content-Encoding: gzip" & CRLF
            & "Content-Length: 40" & CRLF
            & CRLF
            & Gzip_Body);
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
      Status  : Http_Client.Errors.Result_Status;
      Buffer  : String (1 .. 32);
      Last    : Natural := 0;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Enable_Decompression := True;
      Options.Max_Body_Size := 128;
      Options.Decompression.Maximum_Decoded_Body_Size := 8;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/gzip-limit",
         URI,
         "streaming decoded-size limit URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "streaming decoded-size limit request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "decoded-size limit response metadata should be exposed");

      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Decoded_Body_Too_Large,
         "streaming decompression should enforce decoded-size limit");
   end Test_Response_Stream_Decompression_Decoded_Size_Limit;

   procedure Test_Async_Buffered_GET_Loopback_And_Lifecycle
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 5"
        & CRLF
        & "X-Async: yes"
        & CRLF
        & CRLF
        & "Hello";

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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      Port_Text     : Unbounded_String;
      Context       : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Strict_Client_Configuration;
      Sync_Client   : Http_Client.Clients.Client;
      Async_Client  : Http_Client.Async.Async_Client;
      Handle        : Http_Client.Async.Request_Handle;
      Value         : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Diagnostic_Callback_Count := 0;
      Diagnostic_Fail_Next := False;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Config.Execution.Diagnostics := Context'Unchecked_Access;
      Status := Http_Client.Clients.Initialize (Sync_Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "diagnostic async client config should initialize");

      Status :=
        Http_Client.Async.Initialize
          (Async_Client,
           Sync_Client,
           (Max_Workers => 1, Max_Queued => 4, Cancel_On_Finalize => True));
      Assert
        (Status = Http_Client.Errors.Ok,
         "async loopback client should initialize");

      Status :=
        Http_Client.Async.Submit_Get
          (Async_Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/async",
           Handle);
      Assert
        (Status = Http_Client.Errors.Ok, "async loopback GET should queue");

      Status := Http_Client.Async.Wait (Handle);
      Assert
        (Status = Http_Client.Errors.Ok,
         "async loopback GET should complete successfully");

      Status := Http_Client.Async.Result (Handle, Value);
      Assert
        (Status = Http_Client.Errors.Ok,
         "first async result consume should return stored status");
      Assert
        (Http_Client.Responses.Response_Body (Value.Response) = "Hello",
         "async result should preserve buffered response body");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Value.Response), "X-Async")
         = "yes",
         "async result should preserve response headers");

      Status := Http_Client.Async.Result (Handle, Value);
      Assert
        (Status = Http_Client.Errors.Async_Result_Already_Taken,
         "async result should be consumable exactly once");

      Status := Http_Client.Async.Cancel (Handle);
      Assert
        (Status = Http_Client.Errors.Ok,
         "cancelling an already completed successful async request should return the completed status");

      Server.Request_Seen (Captured_Text);
      Assert
        (To_String (Captured_Text)
         = "GET /async HTTP/1.1"
           & CRLF
           & "Host: 127.0.0.1:"
           & To_String (Port_Text)
           & CRLF
           & "Connection: close"
           & CRLF
           & CRLF,
         "async worker should execute the same buffered HTTP/1.1 serialization path");
      Assert
        (Diagnostic_Callback_Count > 0,
         "async execution with diagnostics configured should emit structural lifecycle events");

      Http_Client.Async.Shutdown (Async_Client, Cancel_Pending => True);
   end Test_Async_Buffered_GET_Loopback_And_Lifecycle;

   procedure Test_High_Level_Client_Execute_Stream_Follows_Redirect
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      First_Response  : constant String :=
        "HTTP/1.1 302 Found"
        & CRLF
        & "Location: /final"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;
      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 5" & CRLF & CRLF & "Hello";

      task type Redirect_Stream_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Redirect_Stream_Server;

      task body Redirect_Stream_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Read_Request is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         end Read_Request;

         procedure Send_Text (Text : String) is
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
         end Send_Text;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request;
         Send_Text (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Configure_Test_Socket_Timeouts (Peer);
         Read_Request;
         Send_Text (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Redirect_Stream_Server;

      Server           : Redirect_Stream_Server;
      Port             : Http_Client.URI.TCP_Port;
      URI              : Http_Client.URI.URI_Reference;
      Request          : Http_Client.Requests.Request;
      Config           : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client           : Http_Client.Clients.Client;
      Stream           : Http_Client.Response_Streams.Streaming_Response;
      Status           : Http_Client.Errors.Result_Status;
      Buffer           : String (1 .. 8);
      Last             : Natural := 0;
      Response_Content : Unbounded_String := Null_Unbounded_String;
   begin
      Server.Ready (Port);
      Config.Redirects.Follow_Redirects := True;
      Assert
        (Http_Client.Clients.Initialize (Client, Config)
         = Http_Client.Errors.Ok,
         "streaming redirect client should initialize");
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "streaming redirect URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming redirect request should construct");

      Status := Http_Client.Clients.Execute_Stream (Client, Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level streaming redirect should return final response stream");
      Assert
        (Http_Client.Response_Streams.Status_Code (Stream) = 200,
         "high-level streaming redirect should expose final response metadata");
      Assert
        (Http_Client.URI.Path
           (Http_Client.Response_Streams.Effective_URI (Stream))
         = "/final",
         "high-level streaming redirect should record final URI");
      Assert
        (Http_Client.Response_Streams.Redirect_Count (Stream) = 1,
         "high-level streaming redirect should record followed redirect count");
      Assert
        (Http_Client.Response_Streams.Retry_Attempt_Count (Stream) = 1,
         "high-level streaming redirect should record open attempt count");

      loop
         Status :=
           Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "high-level redirected stream should read final body");
         if Last > 0 then
            Append
              (Response_Content,
               Buffer (Buffer'First .. Buffer'First + Last - 1));
         end if;
      end loop;
      Assert
        (To_String (Response_Content) = "Hello",
         "high-level redirected stream should return final body bytes only");
   end Test_High_Level_Client_Execute_Stream_Follows_Redirect;

   procedure Test_TCP_Not_Connected_And_Close_Safe
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Conn   : Http_Client.Transports.TCP.Connection;
      Buffer : String (1 .. 16);
      Count  : Natural := 99;
   begin
      Assert
        (not Http_Client.Transports.TCP.Is_Open (Conn),
         "new TCP connection should start closed");

      Assert
        (Http_Client.Transports.TCP.Write_All (Conn, "GET / HTTP/1.1")
         = Http_Client.Errors.Not_Connected,
         "Write_All on a closed TCP connection should report Not_Connected");

      Assert
        (Http_Client.Transports.TCP.Read_Some (Conn, Buffer, Count)
         = Http_Client.Errors.Not_Connected,
         "Read_Some on a closed TCP connection should report Not_Connected");

      Assert
        (Count = 0,
         "Read_Some failure should leave returned byte count as zero");

      Assert
        (Http_Client.Transports.TCP.Close (Conn) = Http_Client.Errors.Ok,
         "closing an already closed TCP connection should be safe");
   end Test_TCP_Not_Connected_And_Close_Safe;

   procedure Test_TCP_Rejects_HTTPS_URI
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      URI    : Http_Client.URI.URI_Reference;
      Conn   : Http_Client.Transports.TCP.Connection;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/", URI, "HTTPS URI for unsupported TCP open");

      Status := Http_Client.Transports.TCP.Open_URI (Conn, URI);

      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "plain TCP Open_URI should reject HTTPS instead of faking TLS");

      Assert
        (not Http_Client.Transports.TCP.Is_Open (Conn),
         "failed HTTPS Open_URI should leave TCP connection closed");
   end Test_TCP_Rejects_HTTPS_URI;

   procedure Test_HTTP1_Response_Reader_Fragmented_And_Framed
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      type Scripted_Connection is record
         Bytes      : Unbounded_String := Null_Unbounded_String;
         Offset     : Natural := 0;
         Fragment   : Positive := 1;
         Force_Fail : Boolean := False;
      end record;

      function Scripted_Read_Some
        (Item   : in out Scripted_Connection;
         Buffer : out String;
         Count  : out Natural) return Http_Client.Errors.Result_Status
      is
         Text      : constant String := To_String (Item.Bytes);
         Remaining : Natural := 0;
         To_Copy   : Natural := 0;
      begin
         Buffer := [others => Character'Val (0)];
         Count := 0;

         if Item.Force_Fail then
            return Http_Client.Errors.Read_Failed;
         end if;

         if Item.Offset >= Text'Length then
            return Http_Client.Errors.End_Of_Stream;
         end if;

         Remaining := Text'Length - Item.Offset;
         To_Copy :=
           Natural'Min (Remaining, Natural'Min (Buffer'Length, Item.Fragment));

         for Index in 1 .. To_Copy loop
            Buffer (Buffer'First + Index - 1) :=
              Text (Text'First + Item.Offset + Index - 1);
         end loop;

         Item.Offset := Item.Offset + To_Copy;
         Count := To_Copy;
         return Http_Client.Errors.Ok;
      end Scripted_Read_Some;

      function Read_Scripted_Response is new
        Http_Client.HTTP1.Reader.Read_Response
          (Connection_Type => Scripted_Connection,
           Read_Some       => Scripted_Read_Some);

      Conn     : Scripted_Connection;
      Raw      : Unbounded_String;
      Response : Http_Client.Responses.Response;
      Options  : Http_Client.HTTP1.Reader.Reader_Options :=
        Http_Client.HTTP1.Reader.Default_Reader_Options;
   begin
      Conn.Bytes :=
        To_Unbounded_String
          ("HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 5"
           & CRLF
           & CRLF
           & "Hello"
           & "NEXT-RESPONSE-BYTES");
      Conn.Fragment := 1;
      Options.Read_Buffer_Size := 2;

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Ok,
         "reader should accept headers and body split across many reads");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "Hello",
         "reader should consume exactly the declared Content-Length body");

      Assert
        (To_String (Raw)
         = "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 5"
           & CRLF
           & CRLF
           & "Hello",
         "reader should pass only the first framed response to the parser");

      Options := Http_Client.HTTP1.Reader.Default_Reader_Options;

      declare
         Framed_Response   : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 5"
           & CRLF
           & CRLF
           & "Hello";
         Overread_Response : constant String :=
           Framed_Response & "NEXT-RESPONSE-BYTES";
      begin
         Conn :=
           (Bytes      => To_Unbounded_String (Overread_Response),
            Offset     => 0,
            Fragment   => Overread_Response'Length,
            Force_Fail => False);
         Options.Read_Buffer_Size := Overread_Response'Length;
         Options.Max_Response_Size := Framed_Response'Length;

         Assert
           (Read_Scripted_Response
              (Connection => Conn,
               Context    => Http_Client.Responses.Default_Context,
               Raw        => Raw,
               Response   => Response,
               Options    => Options)
            = Http_Client.Errors.Ok,
            "reader should not count over-read bytes after a complete "
            & "fixed-length response against the framed response limit");

         Assert
           (To_String (Raw) = Framed_Response,
            "reader should discard over-read bytes when returning the framed response");
      end;

      Options := Http_Client.HTTP1.Reader.Default_Reader_Options;
      Options.Read_Buffer_Size := 2;

      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 200 OK" & CRLF & CRLF & "close-body"),
         Offset     => 0,
         Fragment   => 3,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Ok,
         "reader should accept close-delimited response bodies after clean EOF");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "close-body",
         "close-delimited body should be retained in memory");

      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 200 OK"
              & CRLF
              & "Transfer-Encoding: chunked"
              & CRLF
              & CRLF
              & "0"
              & CRLF
              & CRLF),
         Offset     => 0,
         Fragment   => 7,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Ok,
         "reader should decode a zero-length chunked response");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "decoded zero-length chunked body should be empty");

      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 200 OK"
              & CRLF
              & "Transfer-Encoding: chunked"
              & CRLF
              & CRLF
              & "4"
              & CRLF
              & "0008"
              & CRLF
              & "6;git=test"
              & CRLF
              & "NAK"
              & Character'Val (0)
              & Character'Val (255)
              & Character'Val (10)
              & CRLF
              & "0"
              & CRLF
              & "Git-Trailer: ok"
              & CRLF
              & CRLF),
         Offset     => 0,
         Fragment   => 2,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Ok,
         "reader should decode chunked Git-like binary body with split metadata");

      Assert
        (Http_Client.Responses.Response_Body (Response)
         = "0008"
           & "NAK"
           & Character'Val (0)
           & Character'Val (255)
           & Character'Val (10),
         "decoded chunked Git-like body bytes should be preserved exactly");

      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 204 No Content"
              & CRLF
              & "Content-Length: 10"
              & CRLF
              & CRLF
              & "ignored"),
         Offset     => 0,
         Fragment   => 64,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Ok,
         "reader should stop at the header section for no-body status codes");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "",
         "no-body status response should expose an empty body");

      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 200 OK" & Character'Val (10) & Character'Val (10)),
         Offset     => 0,
         Fragment   => 64,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Protocol_Error,
         "reader should reject LF-only header terminators");

      Options.Max_Header_Size := 16;
      Conn :=
        (Bytes      =>
           To_Unbounded_String
             ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF),
         Offset     => 0,
         Fragment   => 64,
         Force_Fail => False);

      Assert
        (Read_Scripted_Response
           (Connection => Conn,
            Context    => Http_Client.Responses.Default_Context,
            Raw        => Raw,
            Response   => Response,
            Options    => Options)
         = Http_Client.Errors.Header_Too_Large,
         "reader should enforce the configured header section limit");
   end Test_HTTP1_Response_Reader_Fragmented_And_Framed;

   procedure Test_TCP_Failed_Open_Leaves_Closed
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Probe      : GNAT.Sockets.Socket_Type;
      Probe_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
      Bound      : GNAT.Sockets.Sock_Addr_Type;
      Conn       : Http_Client.Transports.TCP.Connection;
      Status     : Http_Client.Errors.Result_Status;
   begin
      GNAT.Sockets.Create_Socket (Probe);

      Probe_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Probe_Addr.Port := 0;

      GNAT.Sockets.Bind_Socket (Probe, Probe_Addr);
      Bound := GNAT.Sockets.Get_Socket_Name (Probe);
      GNAT.Sockets.Close_Socket (Probe);

      Status :=
        Http_Client.Transports.TCP.Open
          (Item => Conn,
           Host => "127.0.0.1",
           Port => Http_Client.URI.TCP_Port (Bound.Port));

      Assert
        (Status = Http_Client.Errors.Connection_Failed,
         "loopback TCP Open to a closed local port should fail deterministically");

      Assert
        (not Http_Client.Transports.TCP.Is_Open (Conn),
         "failed TCP Open should leave connection state closed");

      Assert
        (Http_Client.Transports.TCP.Close (Conn) = Http_Client.Errors.Ok,
         "Close after failed TCP Open should be safe");

      Status :=
        Http_Client.Transports.TCP.Open (Item => Conn, Host => "", Port => 80);

      Assert
        (Status = Http_Client.Errors.DNS_Failed,
         "TCP Open with an empty host should report DNS_Failed");

      Assert
        (not Http_Client.Transports.TCP.Is_Open (Conn),
         "DNS failure should leave connection state closed");
   end Test_TCP_Failed_Open_Leaves_Closed;

   procedure Test_TCP_Loopback_Raw_Bytes
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Request  : constant String :=
        "GET /raw HTTP/1.1" & CRLF & "Host: 127.0.0.1" & CRLF & CRLF;
      Response : constant String :=
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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

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
                (1 .. Stream_Element_Offset (Response'Length));
            Last : Stream_Element_Offset;
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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      Conn          : Http_Client.Transports.TCP.Connection;
      Status        : Http_Client.Errors.Result_Status;
      Buffer        : String (1 .. 128);
      Count         : Natural := 0;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);

      Status :=
        Http_Client.Transports.TCP.Open
          (Item => Conn, Host => "127.0.0.1", Port => Port);

      Assert
        (Status = Http_Client.Errors.Ok, "loopback TCP Open should succeed");

      Assert
        (Http_Client.Transports.TCP.Is_Open (Conn),
         "loopback TCP connection should report open after successful Open");

      Assert
        (Http_Client.Transports.TCP.Write_All (Conn, Request)
         = Http_Client.Errors.Ok,
         "loopback Write_All should transmit serialized request bytes");

      Assert
        (Http_Client.Transports.TCP.Read_Some (Conn, Buffer, Count)
         = Http_Client.Errors.Ok,
         "loopback Read_Some should return first raw response bytes");

      Assert
        (Count = Response'Length and then Buffer (1 .. Count) = Response,
         "loopback Read_Some should preserve raw response bytes without parsing");

      Assert
        (Http_Client.Transports.TCP.Close (Conn) = Http_Client.Errors.Ok,
         "loopback Close should succeed");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text) = Request,
         "loopback server should receive exactly the bytes supplied to Write_All");
   end Test_TCP_Loopback_Raw_Bytes;

   procedure Test_TCP_Write_All_Large_Request_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Payload  : constant String (1 .. 5000) := [others => 'x'];
      Request  : constant String :=
        "POST /large HTTP/1.1"
        & CRLF
        & "Host: 127.0.0.1"
        & CRLF
        & "Content-Length: 5000"
        & CRLF
        & CRLF
        & Payload;
      Response : constant String :=
        "HTTP/1.1 204 No Content" & CRLF & "Content-Length: 0" & CRLF & CRLF;

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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

         while Length (Request_Text) < Request'Length loop
            declare
               Raw  : Stream_Element_Array (1 .. 1024);
               Last : Stream_Element_Offset;
            begin
               GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

               exit when Last < Raw'First;

               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end;
         end loop;

         declare
            Raw  :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response'Length));
            Last : Stream_Element_Offset;
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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      Conn          : Http_Client.Transports.TCP.Connection;
      Status        : Http_Client.Errors.Result_Status;
      Buffer        : String (1 .. 128);
      Count         : Natural := 0;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);

      Status :=
        Http_Client.Transports.TCP.Open
          (Item => Conn, Host => "127.0.0.1", Port => Port);

      Assert
        (Status = Http_Client.Errors.Ok,
         "large loopback TCP Open should succeed");

      Assert
        (Http_Client.Transports.TCP.Write_All (Conn, Request)
         = Http_Client.Errors.Ok,
         "Write_All should transmit large request bytes through bounded chunks");

      Assert
        (Http_Client.Transports.TCP.Read_Some (Conn, Buffer, Count)
         = Http_Client.Errors.Ok,
         "large Write_All loopback should receive response after complete send");

      Assert
        (Count = Response'Length and then Buffer (1 .. Count) = Response,
         "large Write_All loopback should preserve raw response bytes");

      Assert
        (Http_Client.Transports.TCP.Close (Conn) = Http_Client.Errors.Ok,
         "large Write_All loopback Close should succeed");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text) = Request,
         "large Write_All loopback server should receive every byte exactly");
   end Test_TCP_Write_All_Large_Request_Loopback;

   procedure Test_Client_Execute_GET_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 5"
        & CRLF
        & "X-Test: loop"
        & CRLF
        & CRLF
        & "Hello";

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
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Headers       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Port_Text     : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/hello",
         URI,
         "loopback execution URI");

      Assert
        (Http_Client.Headers.Set
           (Headers, "Proxy-Authorization", "Basic should-not-reach-origin")
         = Http_Client.Errors.Ok,
         "direct loopback request should accept caller proxy authorization before client sanitization");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "loopback GET request should construct");

      Status := Http_Client.Clients.Execute_Once (Request, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "loopback GET execution should succeed");

      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "loopback execution should parse response status code");

      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Response), "X-Test")
         = "loop",
         "loopback execution should preserve parsed response headers");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "Hello",
         "loopback execution should parse fixed-length response body");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text)
         = "GET /hello HTTP/1.1"
           & CRLF
           & "Host: 127.0.0.1:"
           & To_String (Port_Text)
           & CRLF
           & "Connection: close"
           & CRLF
           & CRLF,
         "loopback server should receive exact execution-time request bytes without leaking Proxy-Authorization");
   end Test_Client_Execute_GET_Loopback;

   procedure Test_Client_Execute_GET_IPv6_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 2"
        & CRLF
        & "X-Test: ipv6"
        & CRLF
        & CRLF
        & "OK";

      task type IPv6_Loopback_Server is
         entry Ready
           (Available : out Boolean;
            Port      : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end IPv6_Loopback_Server;

      task body IPv6_Loopback_Server is
         Server       : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
         Peer         : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet6);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
         Bound_Port   : Http_Client.URI.TCP_Port := 1;
         Is_Available : Boolean := False;

         procedure Close_Peer is
         begin
            if Peer /= GNAT.Sockets.No_Socket then
               GNAT.Sockets.Close_Socket (Peer);
               Peer := GNAT.Sockets.No_Socket;
            end if;
         exception
            when others =>
               Peer := GNAT.Sockets.No_Socket;
         end Close_Peer;

         procedure Close_Server is
         begin
            if Server /= GNAT.Sockets.No_Socket then
               GNAT.Sockets.Close_Socket (Server);
               Server := GNAT.Sockets.No_Socket;
            end if;
         exception
            when others =>
               Server := GNAT.Sockets.No_Socket;
         end Close_Server;
      begin
         begin
            GNAT.Sockets.Create_Socket
              (Socket => Server,
               Family => GNAT.Sockets.Family_Inet6);
            Configure_Test_Socket_Timeouts (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("::1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               Bound_Port := Http_Client.URI.TCP_Port (Bound.Port);
               Is_Available := True;
            end;
         exception
            when others =>
               Close_Server;
               Is_Available := False;
         end;

         accept Ready
           (Available : out Boolean;
            Port      : out Http_Client.URI.TCP_Port)
         do
            Available := Is_Available;
            Port := Bound_Port;
         end Ready;

         if Is_Available then
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

            Close_Peer;
            Close_Server;

            select
               accept Request_Seen (Text : out Unbounded_String) do
                  Text := Request_Text;
               end Request_Seen;
            or
               delay 2.0;
            end select;
         end if;
      exception
         when others =>
            Close_Peer;
            Close_Server;
      end IPv6_Loopback_Server;

      Server        : IPv6_Loopback_Server;
      Available     : Boolean;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Port_Text     : Unbounded_String;
   begin
      Server.Ready (Available, Port);

      if not Available then
         return;
      end if;

      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://[::1]:" & To_String (Port_Text) & "/hello",
         URI,
         "IPv6 loopback execution URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "IPv6 loopback GET request should construct");

      Status := Http_Client.Clients.Execute_Once (Request, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "IPv6 loopback GET execution should succeed when loopback is available");
      Assert
        (Http_Client.Responses.Status_Code (Response) = 200,
         "IPv6 loopback execution should parse response status code");
      Assert
        (Http_Client.Responses.Response_Body (Response) = "OK",
         "IPv6 loopback execution should parse response body");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text)
         = "GET /hello HTTP/1.1"
           & CRLF
           & "Host: [::1]:"
           & To_String (Port_Text)
           & CRLF
           & "Connection: close"
           & CRLF
           & CRLF,
         "IPv6 loopback server should receive exact bracketed Host header bytes");
   end Test_Client_Execute_GET_IPv6_Loopback;

   procedure Test_Client_Execute_POST_Loopback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 201 Created"
        & CRLF
        & "Content-Length: 2"
        & CRLF
        & CRLF
        & "OK";

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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Port_Text     : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/upload",
         URI,
         "loopback POST execution URI");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "loopback POST request should construct");

      Status := Http_Client.Clients.Execute_Once (Request, Response);

      Assert
        (Status = Http_Client.Errors.Ok,
         "loopback POST execution should succeed");

      Assert
        (Http_Client.Responses.Status_Code (Response) = 201,
         "loopback POST should parse created status code");

      Assert
        (Http_Client.Responses.Response_Body (Response) = "OK",
         "loopback POST should parse fixed-length body");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text)
         = "POST /upload HTTP/1.1"
           & CRLF
           & "Host: 127.0.0.1:"
           & To_String (Port_Text)
           & CRLF
           & "Connection: close"
           & CRLF
           & "Content-Length: 7"
           & CRLF
           & CRLF
           & "payload",
         "loopback server should receive exact POST bytes and payload");
   end Test_Client_Execute_POST_Loopback;

   procedure Test_Client_Execution_Failed_Connect
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is

      pragma Unreferenced (Case_Context);
      Probe      : GNAT.Sockets.Socket_Type;
      Probe_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
      Bound      : GNAT.Sockets.Sock_Addr_Type;
      URI        : Http_Client.URI.URI_Reference;
      Request    : Http_Client.Requests.Request;
      Response   : Http_Client.Responses.Response;
   begin
      GNAT.Sockets.Create_Socket (Probe);

      Probe_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Probe_Addr.Port := 0;

      GNAT.Sockets.Bind_Socket (Probe, Probe_Addr);
      Bound := GNAT.Sockets.Get_Socket_Name (Probe);
      GNAT.Sockets.Close_Socket (Probe);

      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Http_Client.URI.TCP_Port (Bound.Port)))
         & "/unavailable",
         URI,
         "unavailable loopback execution URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "unavailable loopback request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response)
         = Http_Client.Errors.Connection_Failed,
         "execution to a closed loopback port should report Connection_Failed");
   end Test_Client_Execution_Failed_Connect;

   procedure Test_Client_Execution_Malformed_Response
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String := "BAD RESPONSE" & CRLF & CRLF;

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Loopback_Server;

      task body Loopback_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

         declare
            Raw_Request  : Stream_Element_Array (1 .. 4096);
            Request_Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Request_Last);
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
      end Loopback_Server;

      Server    : Loopback_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Response  : Http_Client.Responses.Response;
      Port_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/bad",
         URI,
         "malformed response execution URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "malformed response request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response)
         = Http_Client.Errors.Protocol_Error,
         "malformed response should propagate parser failure status");
   end Test_Client_Execution_Malformed_Response;

   procedure Test_Client_Execution_Accepts_Close_Delimited_Body
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & CRLF & "close-delimited-body";

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Loopback_Server;

      task body Loopback_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

         declare
            Raw_Request  : Stream_Element_Array (1 .. 4096);
            Request_Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Request_Last);
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
      end Loopback_Server;

      Server   : Loopback_Server;
      Port     : Http_Client.URI.TCP_Port;
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/close-body",
         URI,
         "loopback execution URI for close-delimited body support");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "close-delimited body request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response)
         = Http_Client.Errors.Ok,
         "execution should accept connection-close-delimited bodies");

      Assert
        (Http_Client.Responses.Response_Body (Response)
         = "close-delimited-body",
         "close-delimited response body should be parsed after clean EOF");
   end Test_Client_Execution_Accepts_Close_Delimited_Body;

   procedure Test_Client_Execution_Options_And_Preservation
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      use type Http_Client.Clients.Protocol_Selection_Policy;

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF;

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
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

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

         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 2.0;
         end select;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Headers       : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Captured_Text : Unbounded_String;
      Port_Text     : Unbounded_String;
      Options       : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Strict_Execution_Options;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/no-close",
         URI,
         "loopback execution URI for options test");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "X-Caller", "kept"),
         "caller header should be accepted for options test");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "options test request should construct");

      Assert
        (Options.Protocol_Policy = Http_Client.Clients.Protocol_From_Configuration,
         "default execution protocol policy should preserve configured protocols");

      Options.Add_Connection_Close := False;
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;

      Assert
        (Http_Client.Clients.Execute_Once
           (Request => Request, Response => Response, Options => Options)
         = Http_Client.Errors.Ok,
         "execution should succeed when automatic Connection: close is disabled and HTTP/1.1 is forced");

      Server.Request_Seen (Captured_Text);

      Assert
        (To_String (Captured_Text)
         = "GET /no-close HTTP/1.1"
           & CRLF
           & "X-Caller: kept"
           & CRLF
           & "Host: 127.0.0.1:"
           & To_String (Port_Text)
           & CRLF
           & CRLF,
         "disabled automatic close should not add a Connection header");

      Assert
        (not Http_Client.Headers.Contains
               (Http_Client.Requests.Headers (Request), "Connection"),
         "execution-time headers must not mutate the original request object");
   end Test_Client_Execution_Options_And_Preservation;

   procedure Test_High_Level_Client_Force_HTTP1_Overrides_HTTP3_Required
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF;

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Done;
      end Loopback_Server;

      task body Loopback_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);
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
         Configure_Test_Socket_Timeouts (Peer);

         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
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

         accept Done;
      end Loopback_Server;

      Server : Loopback_Server;
      Port   : Http_Client.URI.TCP_Port;
      URI    : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Result  : Http_Client.Clients.Client_Result;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/force-http1",
         URI,
         "loopback URI for forced HTTP/1.1 over HTTP3-required client config");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "force-http1 request should construct");

      Config.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Required;
      Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;

      Assert
        (Http_Client.Clients.Configure (Client, Config) = Http_Client.Errors.Ok,
         "client configuration with HTTP3 required and per-request HTTP/1.1 force should validate");

      Assert
        (Http_Client.Clients.Execute (Client, Request, Result) = Http_Client.Errors.Ok,
         "Force_HTTP_1_1 should bypass HTTP3-required network selection for this execution");

      Server.Done;

      Assert
        (Http_Client.Responses.Status_Code (Result.Response) = 200,
         "forced HTTP/1.1 execution should return the loopback HTTP response");
   end Test_High_Level_Client_Force_HTTP1_Overrides_HTTP3_Required;

   procedure Test_High_Level_Client_Force_HTTP2_Rejects_Plain_HTTP
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Result  : Http_Client.Clients.Client_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("http://127.0.0.1:1/force-http2",
         URI,
         "plain HTTP URI for Force_HTTP_2 rejection test");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "force-http2 plain HTTP request should construct");

      Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_2;

      Assert
        (Http_Client.Clients.Configure (Client, Config) = Http_Client.Errors.Ok,
         "client configuration with Force_HTTP_2 should validate");

      Status := Http_Client.Clients.Execute (Client, Request, Result);

      Assert
        (Status = Http_Client.Errors.HTTP2_Unsupported_Feature,
         "Force_HTTP_2 must reject plain HTTP before opening a TCP connection");
      Assert
        (Result.Status = Http_Client.Errors.HTTP2_Unsupported_Feature,
         "client result should preserve the Force_HTTP_2 plain HTTP rejection status");
   end Test_High_Level_Client_Force_HTTP2_Rejects_Plain_HTTP;

   procedure Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("http://127.0.0.1:1/stream-force-http2",
         URI,
         "plain HTTP URI for streaming Force_HTTP_2 rejection test");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming force-http2 plain HTTP request should construct");

      Options.Protocol_Policy :=
        Http_Client.Response_Streams.Streaming_Force_HTTP_2;

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);

      Assert
        (Status = Http_Client.Errors.HTTP2_Unsupported_Feature,
         "Streaming_Force_HTTP_2 must reject plain HTTP before opening a TCP connection");
      Assert
        (Http_Client.Response_Streams.Last_Status (Stream) =
         Http_Client.Errors.HTTP2_Unsupported_Feature,
         "stream should preserve the streaming Force_HTTP_2 rejection status");
   end Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP;

   procedure Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert_Parse_Ok
        ("https://example.com/repo.git/info/refs?service=git-upload-pack",
         URI,
         "HTTPS URI for streaming Force_HTTP_3 no-backend rejection test");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming force-http3 request should construct");

      Options.Protocol_Policy :=
        Http_Client.Response_Streams.Streaming_Force_HTTP_3;
      Options.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Required;
      Options.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Disallowed;

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);

      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported
         or else Status = Http_Client.Errors.HTTP3_Unsupported,
         "Streaming_Force_HTTP_3 must fail deterministically before request bytes when no QUIC backend is available");
      Assert
        (Http_Client.Response_Streams.Is_Open (Stream) = False,
         "failed HTTP/3 streaming open must not leave a public stream open");
   end Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend;

   procedure Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      B      : Http_Client.HTTP3.Body_Streams.Body_Stream;
      Status : Http_Client.Errors.Result_Status;
      Buffer : Stream_Element_Array (1 .. 3);
      Last   : Stream_Element_Offset;
      Data   : constant Stream_Element_Array (1 .. 7) :=
        [1 => Stream_Element (Character'Pos ('0')),
         2 => Stream_Element (Character'Pos ('0')),
         3 => Stream_Element (Character'Pos ('0')),
         4 => Stream_Element (Character'Pos ('8')),
         5 => Stream_Element (0),
         6 => Stream_Element (16#FF#),
         7 => Stream_Element (10)];
   begin
      Status := Http_Client.HTTP3.Body_Streams.Open (B, Max_Body_Size => 64);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 scripted body stream should open");

      Status := Http_Client.HTTP3.Body_Streams.Append_Data (B, Data);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 body stream should accept scripted DATA payload");

      Status := Http_Client.HTTP3.Body_Streams.Mark_End_Stream (B);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 body stream should accept END_STREAM");

      Status := Http_Client.HTTP3.Body_Streams.Read_Some (B, Buffer, Last);
      Assert (Status = Http_Client.Errors.Ok, "first HTTP/3 byte-array read should return DATA bytes");
      Assert (Last = Buffer'First + 2, "first HTTP/3 byte-array read should fill the tiny caller buffer");
      Assert
        (Buffer (1) = Stream_Element (Character'Pos ('0'))
         and then Buffer (2) = Stream_Element (Character'Pos ('0'))
         and then Buffer (3) = Stream_Element (Character'Pos ('0')),
         "first HTTP/3 byte-array read should preserve pkt-line bytes");

      Status := Http_Client.HTTP3.Body_Streams.Read_Some (B, Buffer, Last);
      Assert (Status = Http_Client.Errors.Ok, "second HTTP/3 byte-array read should return remaining DATA bytes");
      Assert (Last = Buffer'First + 2, "second HTTP/3 byte-array read should fill the tiny caller buffer");
      Assert
        (Buffer (1) = Stream_Element (Character'Pos ('8'))
         and then Buffer (2) = Stream_Element (0)
         and then Buffer (3) = Stream_Element (16#FF#),
         "second HTTP/3 byte-array read should preserve NUL and high-byte Git bytes");

      Status := Http_Client.HTTP3.Body_Streams.Read_Some (B, Buffer, Last);
      Assert (Status = Http_Client.Errors.Ok, "third HTTP/3 byte-array read should return LF");
      Assert (Last = Buffer'First, "third HTTP/3 byte-array read should return one byte");
      Assert (Buffer (1) = Stream_Element (10), "third HTTP/3 byte-array read should preserve LF");

      Status := Http_Client.HTTP3.Body_Streams.Read_Some (B, Buffer, Last);
      Assert (Status = Http_Client.Errors.End_Of_Stream, "HTTP/3 byte-array stream should finish after queued DATA is consumed");
      Assert (Last = Buffer'First - 1, "HTTP/3 EOF should not report body bytes");
   end Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes;

   procedure Test_Client_Execution_Max_Response_Size
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 5" & CRLF & CRLF & "Hello";

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Loopback_Server;

      task body Loopback_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Configure_Test_Socket_Timeouts (Server);

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
         Configure_Test_Socket_Timeouts (Peer);

         declare
            Raw_Request  : Stream_Element_Array (1 .. 4096);
            Request_Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Request_Last);
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
      end Loopback_Server;

      Server   : Loopback_Server;
      Port     : Http_Client.URI.TCP_Port;
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Options  : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/too-large",
         URI,
         "loopback execution URI for response-size limit test");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "response-size limit request should construct");

      Options.Max_Response_Size := 16;

      Assert
        (Http_Client.Clients.Execute_Once
           (Request => Request, Response => Response, Options => Options)
         = Http_Client.Errors.Response_Too_Large,
         "response larger than the configured raw byte limit should fail safely");
   end Test_Client_Execution_Max_Response_Size;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("HTTP1_Execution");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_HTTP1_Basic_GET_Serialization'Access,
         "Test_HTTP1_Basic_GET_Serialization");
      Register_Routine
        (T,
         Test_HTTP1_Method_Tokens_All_Known'Access,
         "Test_HTTP1_Method_Tokens_All_Known");
      Register_Routine
        (T,
         Test_HTTP1_CRLF_Line_Endings_And_Terminator'Access,
         "Test_HTTP1_CRLF_Line_Endings_And_Terminator");
      Register_Routine
        (T,
         Test_HTTP1_Query_Empty_Path_And_Fragment'Access,
         "Test_HTTP1_Query_Empty_Path_And_Fragment");
      Register_Routine
        (T,
         Test_HTTP1_Explicit_Empty_Query_Target'Access,
         "Test_HTTP1_Explicit_Empty_Query_Target");
      Register_Routine
        (T,
         Test_HTTP1_Synthesizes_Host_When_Absent'Access,
         "Test_HTTP1_Synthesizes_Host_When_Absent");
      Register_Routine
        (T,
         Test_HTTP1_Preserves_Explicit_Host_And_Order'Access,
         "Test_HTTP1_Preserves_Explicit_Host_And_Order");
      Register_Routine
        (T,
         Test_HTTP1_Payload_And_Content_Length'Access,
         "Test_HTTP1_Payload_And_Content_Length");
      Register_Routine
        (T,
         Test_HTTP1_Content_Length_Rejections'Access,
         "Test_HTTP1_Content_Length_Rejections");
      Register_Routine
        (T,
         Test_HTTP1_Content_Length_Zero_Without_Payload'Access,
         "Test_HTTP1_Content_Length_Zero_Without_Payload");
      Register_Routine
        (T,
         Test_HTTP1_Rejects_Duplicate_And_Empty_Host'Access,
         "Test_HTTP1_Rejects_Duplicate_And_Empty_Host");
      Register_Routine
        (T,
         Test_HTTP1_Rejects_Invalid_Default_Request'Access,
         "Test_HTTP1_Rejects_Invalid_Default_Request");
      Register_Routine
        (T,
         Test_HTTP1_Absolute_Form_Proxy_Serialization'Access,
         "Test_HTTP1_Absolute_Form_Proxy_Serialization");
      Register_Routine
        (T, Test_Default_Response'Access, "Test_Default_Response");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Valid_Minimal'Access,
         "Test_HTTP1_Response_Parse_Valid_Minimal");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Content_Length_Body'Access,
         "Test_HTTP1_Response_Parse_Content_Length_Body");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Empty_Reason_And_HTTP10'Access,
         "Test_HTTP1_Response_Parse_Empty_Reason_And_HTTP10");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_No_Body_Statuses_And_HEAD'Access,
         "Test_HTTP1_Response_Parse_No_Body_Statuses_And_HEAD");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_No_Content_Length_Body'Access,
         "Test_HTTP1_Response_Parse_No_Content_Length_Body");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Invalid_Status_Lines'Access,
         "Test_HTTP1_Response_Parse_Invalid_Status_Lines");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Incomplete_And_Length_Mismatch'Access,
         "Test_HTTP1_Response_Parse_Incomplete_And_Length_Mismatch");
      Register_Routine
        (T,
         Test_HTTP1_Response_Parse_Additional_Edges'Access,
         "Test_HTTP1_Response_Parse_Additional_Edges");
      Register_Routine
        (T,
         Test_Client_And_Transport_Availability'Access,
         "Test_Client_And_Transport_Availability");
      Register_Routine
        (T,
         Test_Client_Cookie_Stateless_No_Jar_Loopback'Access,
         "Test_Client_Cookie_Stateless_No_Jar_Loopback");
      Register_Routine
        (T,
         Test_Client_Strict_Cookie_Error_Preserves_Response_Loopback'Access,
         "Test_Client_Strict_Cookie_Error_Preserves_Response_Loopback");
      Register_Routine
        (T,
         Test_Client_Cookie_Jar_Opt_In_And_Replay_Loopback'Access,
         "Test_Client_Cookie_Jar_Opt_In_And_Replay_Loopback");
      Register_Routine
        (T,
         Test_Client_Execute_Decoded_Loopback'Access,
         "Test_Client_Execute_Decoded_Loopback");
      Register_Routine
        (T,
         Test_Client_Execute_Decoded_Redirect_Final_Only'Access,
         "Test_Client_Execute_Decoded_Redirect_Final_Only");
      Register_Routine
        (T,
         Test_Client_Plain_HTTP_Proxy_Loopback'Access,
         "Test_Client_Plain_HTTP_Proxy_Loopback");
      Register_Routine
        (T,
         Test_Client_Retry_503_Then_200_Loopback'Access,
         "Test_Client_Retry_503_Then_200_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Redirect_Enabled_Loopback'Access,
         "Test_High_Level_Client_Redirect_Enabled_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Retry_503_Then_200_Loopback'Access,
         "Test_High_Level_Client_Retry_503_Then_200_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Retry_Exhaustion_Metadata_Loopback'Access,
         "Test_High_Level_Client_Retry_Exhaustion_Metadata_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Decompression_Loopback'Access,
         "Test_High_Level_Client_Decompression_Loopback");
      Register_Routine
        (T,
         Test_High_Level_Client_Execute_Stream_Decompression_Loopback'Access,
         "Test_High_Level_Client_Execute_Stream_Decompression_Loopback");
      Register_Routine
        (T,
         Test_Response_Stream_Decompression_Chunked_Loopback'Access,
         "Test_Response_Stream_Decompression_Chunked_Loopback");
      Register_Routine
        (T,
         Test_Response_Stream_Decompression_Malformed_Gzip_Loopback'Access,
         "Test_Response_Stream_Decompression_Malformed_Gzip_Loopback");
      Register_Routine
        (T,
         Test_Response_Stream_Decompression_Deflate_Loopback'Access,
         "Test_Response_Stream_Decompression_Deflate_Loopback");
      Register_Routine
        (T,
         Test_Response_Stream_Decompression_Decoded_Size_Limit'Access,
         "Test_Response_Stream_Decompression_Decoded_Size_Limit");
      Register_Routine
        (T,
         Test_Async_Buffered_GET_Loopback_And_Lifecycle'Access,
         "Test_Async_Buffered_GET_Loopback_And_Lifecycle");
      Register_Routine
        (T,
         Test_High_Level_Client_Execute_Stream_Follows_Redirect'Access,
         "Test_High_Level_Client_Execute_Stream_Follows_Redirect");
      Register_Routine
        (T,
         Test_TCP_Not_Connected_And_Close_Safe'Access,
         "Test_TCP_Not_Connected_And_Close_Safe");
      Register_Routine
        (T,
         Test_TCP_Rejects_HTTPS_URI'Access,
         "Test_TCP_Rejects_HTTPS_URI");
      Register_Routine
        (T,
         Test_HTTP1_Response_Reader_Fragmented_And_Framed'Access,
         "Test_HTTP1_Response_Reader_Fragmented_And_Framed");
      Register_Routine
        (T,
         Test_TCP_Failed_Open_Leaves_Closed'Access,
         "Test_TCP_Failed_Open_Leaves_Closed");
      Register_Routine
        (T,
         Test_TCP_Loopback_Raw_Bytes'Access,
         "Test_TCP_Loopback_Raw_Bytes");
      Register_Routine
        (T,
         Test_TCP_Write_All_Large_Request_Loopback'Access,
         "Test_TCP_Write_All_Large_Request_Loopback");
      Register_Routine
        (T,
         Test_Client_Execute_GET_Loopback'Access,
         "Test_Client_Execute_GET_Loopback");
      Register_Routine
        (T,
         Test_Client_Execute_GET_IPv6_Loopback'Access,
         "Test_Client_Execute_GET_IPv6_Loopback");
      Register_Routine
        (T,
         Test_Client_Execute_POST_Loopback'Access,
         "Test_Client_Execute_POST_Loopback");
      Register_Routine
        (T,
         Test_Client_Execution_Failed_Connect'Access,
         "Test_Client_Execution_Failed_Connect");
      Register_Routine
        (T,
         Test_Client_Execution_Malformed_Response'Access,
         "Test_Client_Execution_Malformed_Response");
      Register_Routine
        (T,
         Test_Client_Execution_Accepts_Close_Delimited_Body'Access,
         "Test_Client_Execution_Accepts_Close_Delimited_Body");
      Register_Routine
        (T,
         Test_Client_Execution_Options_And_Preservation'Access,
         "Test_Client_Execution_Options_And_Preservation");
      Register_Routine
        (T,
         Test_High_Level_Client_Force_HTTP1_Overrides_HTTP3_Required'Access,
         "Test_High_Level_Client_Force_HTTP1_Overrides_HTTP3_Required");
      Register_Routine
        (T,
         Test_High_Level_Client_Force_HTTP2_Rejects_Plain_HTTP'Access,
         "Test_High_Level_Client_Force_HTTP2_Rejects_Plain_HTTP");
      Register_Routine
        (T,
         Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP'Access,
         "Test_Response_Stream_Protocol_Policy_Force_HTTP2_Rejects_Plain_HTTP");
      Register_Routine
        (T,
         Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend'Access,
         "Test_Response_Stream_Protocol_Policy_Force_HTTP3_Rejects_No_Backend");
      Register_Routine
        (T,
         Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes'Access,
         "Test_HTTP3_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes");
      Register_Routine
        (T,
         Test_Client_Execution_Max_Response_Size'Access,
         "Test_Client_Execution_Max_Response_Size");
   end Register_Tests;

end Http_Client.HTTP1.Tests;
