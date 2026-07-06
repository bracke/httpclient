with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.Sockets;
with AUnit.Assertions;
with Http_Client.Clients;
with Http_Client.Cookies;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Requests;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Redirects.Tests is

   use AUnit.Assertions;
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type GNAT.Sockets.Socket_Type;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;

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

   procedure Test_Client_Redirect_Stores_Cookie_For_Next_Hop

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Redirect_Cookie_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Redirect_Cookie_Server;

      task body Redirect_Cookie_Server is
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
         Send_Response
           ("HTTP/1.1 302 Found"
            & CRLF
            & "Location: /final"
            & CRLF
            & "Set-Cookie: hop=one; Path=/"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Text);
         Send_Response
           ("HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Text;
            Second := Second_Text;
         end Requests_Seen;
      end Redirect_Cookie_Server;

      Server      : Redirect_Cookie_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Redirect_Result;
      Jar         : aliased Http_Client.Cookies.Cookie_Jar :=
        Http_Client.Cookies.Empty_Jar;
      Execution   : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);
      Execution.Cookie_Jar := Jar'Unchecked_Access;
      Redirects.Follow_Redirects := True;

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "redirect cookie start URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "redirect cookie request should construct");

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Execution => Execution,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "redirect cookie flow should execute");
      Assert
        (Result.Redirect_Count = 1,
         "redirect cookie flow should follow one hop");
      Assert
        (Http_Client.Cookies.Length (Jar) = 1,
         "redirect Set-Cookie should be stored in the supplied jar");

      Server.Requests_Seen (First_Text, Second_Text);
      Assert
        (Index (First_Text, "Cookie:") = 0,
         "initial redirect request should not have a generated Cookie");
      Assert
        (Index (Second_Text, "Cookie: hop=one") > 0,
         "redirect next hop should receive the newly stored cookie");
   end Test_Client_Redirect_Stores_Cookie_For_Next_Hop;

   procedure Test_Client_Redirect_Retry_Disabled_Remains_One_Attempt

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Request        : constant Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Redirects      : Http_Client.Clients.Redirect_Result;
      Retry_Metadata : Http_Client.Clients.Retry_Result;
      Options        : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Status         : Http_Client.Errors.Result_Status;
   begin
      Options.Enable_Retries := False;
      Options.Maximum_Attempts := 3;

      Status :=
        Http_Client.Clients.Execute_Once_With_Redirects_And_Retry
          (Request        => Request,
           Result         => Redirects,
           Retry_Metadata => Retry_Metadata,
           Retries        => Options);

      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "invalid default request should fail before redirect-aware retry loop");

      Assert
        (Retry_Metadata.Attempts = 1,
         "redirect-aware disabled retry policy should make exactly one attempt");

      Assert
        (not Retry_Metadata.Retries_Exhausted,
         "redirect-aware disabled retry policy should not report exhaustion");
   end Test_Client_Redirect_Retry_Disabled_Remains_One_Attempt;

   procedure Test_Client_Redirect_Disabled_Returns_302

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 302 Found"
        & CRLF
        & "Location: /final"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

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
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Response      : Http_Client.Responses.Response;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "redirect-disabled URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "redirect-disabled request should construct");

      Assert
        (Http_Client.Clients.Execute_Once (Request, Response)
         = Http_Client.Errors.Ok,
         "one-shot execution should return redirect response successfully");

      Assert
        (Http_Client.Responses.Status_Code (Response) = 302,
         "one-shot execution should not follow 302 by default");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "GET /start HTTP/1.1") = 1,
         "redirect-disabled server should only receive the original request");
   end Test_Client_Redirect_Disabled_Returns_302;

   procedure Test_Client_Redirect_Missing_Location_Is_Invalid

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 302 Found" & CRLF & "Content-Length: 0" & CRLF & CRLF;

      task type Missing_Location_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Missing_Location_Server;

      task body Missing_Location_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request  : Stream_Element_Array (1 .. 4096);
         Request_Last : Stream_Element_Offset;
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
         GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Request_Last);

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
      end Missing_Location_Server;

      Server    : Missing_Location_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Result    : Http_Client.Clients.Redirect_Result;
      Redirects : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      Client    : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "missing-location redirect start URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "missing-location redirect request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Invalid_Redirect,
         "followed redirect without Location should fail deterministically");

      Assert
        (Result.Redirect_Count = 0,
         "missing-location redirect should not count as a followed hop");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 302,
         "missing-location redirect should expose the received 302 response");
   end Test_Client_Redirect_Missing_Location_Is_Invalid;

   procedure Test_Client_Redirect_307_Body_Replay_Disallowed

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 307 Temporary Redirect"
        & CRLF
        & "Location: /again"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

      task type Replay_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Replay_Server;

      task body Replay_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
         Raw          :
           Stream_Element_Array
             (1 .. Stream_Element_Offset (Response_Text'Length));
         Last         : Stream_Element_Offset;
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
            Request_Raw  : Stream_Element_Array (1 .. 4096);
            Request_Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Request_Raw, Request_Last);
            if Request_Last >= Request_Raw'First then
               for Index in Request_Raw'First .. Request_Last loop
                  Append (Request_Text, Character'Val (Request_Raw (Index)));
               end loop;
            end if;
         end;

         for Index in Raw'Range loop
            Raw (Index) :=
              Stream_Element
                (Character'Pos
                   (Response_Text
                      (Response_Text'First + Natural (Index - Raw'First))));
         end loop;

         GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Replay_Server;

      Server    : Replay_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Result    : Http_Client.Clients.Redirect_Result;
      Redirects : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      Client    : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Seen      : Unbounded_String;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "307 replay-disallowed start URI");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "307 replay-disallowed request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Redirect_Body_Replay_Disallowed,
         "307 with a payload should not be replayed unless explicitly allowed");

      Assert
        (Result.Redirect_Count = 0,
         "disallowed 307 body replay should not count as a followed redirect");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 307,
         "disallowed 307 body replay should expose the redirect response");

      Server.Request_Seen (Seen);

      Assert
        (Index (Seen, "POST /start HTTP/1.1") = 1,
         "307 replay-disallowed server should receive only the original POST");
   end Test_Client_Redirect_307_Body_Replay_Disallowed;

   procedure Test_Client_Redirect_303_Preserves_HEAD
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      First_Response  : constant String :=
        "HTTP/1.1 303 See Other"
        & CRLF
        & "Location: /head-final"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;
      Second_Response : constant String :=
        "HTTP/1.1 204 No Content" & CRLF & "Content-Length: 0" & CRLF & CRLF;

      task type Head_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Head_Server;

      task body Head_Server is
         Server         : GNAT.Sockets.Socket_Type;
         Peer           : GNAT.Sockets.Socket_Type;
         Server_Addr    :
           GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
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
         Receive_Request (First_Request);
         Send_Response (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Request);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Request;
            Second := Second_Request;
         end Requests_Seen;
      end Head_Server;

      Server      : Head_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/head-start",
         URI,
         "303 HEAD redirect start URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.HEAD, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "303 HEAD redirect request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "303 redirect from HEAD should follow successfully");

      Assert
        (Result.Redirect_Count = 1,
         "303 HEAD redirect should report one followed hop");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "HEAD /head-start HTTP/1.1") = 1,
         "first 303 HEAD request should use HEAD");

      Assert
        (Index (Second_Text, "HEAD /head-final HTTP/1.1") = 1,
         "303 redirect should preserve HEAD rather than rewrite to GET");
   end Test_Client_Redirect_303_Preserves_HEAD;

   procedure Test_Client_Redirect_303_Post_Drops_Body_Headers
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      First_Response  : constant String :=
        "HTTP/1.1 303 See Other"
        & CRLF
        & "Location: /post-final"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;
      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Post_303_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Post_303_Server;

      task body Post_303_Server is
         Server         : GNAT.Sockets.Socket_Type;
         Peer           : GNAT.Sockets.Socket_Type;
         Server_Addr    :
           GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
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
         Receive_Request (First_Request);
         Send_Response (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Request);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Request;
            Second := Second_Request;
         end Requests_Seen;
      end Post_303_Server;

      Server      : Post_303_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/post-start",
         URI,
         "303 POST redirect start URI");

      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers, "Content-Type", "application/x-git-upload-pack-request"),
         "Git upload-pack content type should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Content-Encoding", "identity"),
         "content encoding should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers, "Content-MD5", "unsafe-stale-digest"),
         "content md5 should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers, "Digest", "sha-256=unsafe-stale-digest"),
         "digest should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Expect", "100-continue"),
         "expect header should be accepted");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload =>
              "0032want binary" & Character'Val (0) & Character'Val (255))
         = Http_Client.Errors.Ok,
         "303 POST redirect request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "303 redirect from POST should follow successfully");

      Assert
        (Result.Redirect_Count = 1,
         "303 POST redirect should report one followed hop");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "POST /post-start HTTP/1.1") = 1,
         "first 303 POST request should use POST");

      Assert
        (Index
           (First_Text, "Content-Type: application/x-git-upload-pack-request")
         > 0,
         "first 303 POST request should carry original Git Content-Type");

      Assert
        (Index (Second_Text, "GET /post-final HTTP/1.1") = 1,
         "303 redirect should rewrite POST to GET");

      Assert
        (Index (Second_Text, "Content-Length:") = 0,
         "303 rewritten GET must not retain Content-Length");

      Assert
        (Index (Second_Text, "Content-Type:") = 0,
         "303 rewritten GET must not retain Git Content-Type");

      Assert
        (Index (Second_Text, "Content-Encoding:") = 0,
         "303 rewritten GET must not retain Content-Encoding");

      Assert
        (Index (Second_Text, "Content-MD5:") = 0,
         "303 rewritten GET must not retain Content-MD5");

      Assert
        (Index (Second_Text, "Digest:") = 0,
         "303 rewritten GET must not retain Digest");

      Assert
        (Index (Second_Text, "Expect:") = 0,
         "303 rewritten GET must not retain Expect: 100-continue");
   end Test_Client_Redirect_303_Post_Drops_Body_Headers;

   procedure Test_Client_Redirect_308_Replays_Body_When_Allowed

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      First_Response  : constant String :=
        "HTTP/1.1 308 Permanent Redirect"
        & CRLF
        & "Location: /put-final"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;
      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Replay_Allowed_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Replay_Allowed_Server;

      task body Replay_Allowed_Server is
         Server         : GNAT.Sockets.Socket_Type;
         Peer           : GNAT.Sockets.Socket_Type;
         Server_Addr    :
           GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
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
         Receive_Request (First_Request);
         Send_Response (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Request);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Request;
            Second := Second_Request;
         end Requests_Seen;
      end Replay_Allowed_Server;

      Server      : Replay_Allowed_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/put-start",
         URI,
         "308 replay redirect start URI");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.PUT,
            URI     => URI,
            Item    => Request,
            Payload => "again")
         = Http_Client.Errors.Ok,
         "308 replay request should construct");

      Redirects.Follow_Redirects := True;
      Redirects.Allow_Body_Replay := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "308 redirect should replay an in-memory body only when explicitly allowed");

      Assert
        (Result.Redirect_Count = 1,
         "308 replay redirect should report one followed hop");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "PUT /put-start HTTP/1.1") = 1,
         "first 308 request should use original PUT");

      Assert
        (Index (Second_Text, "PUT /put-final HTTP/1.1") = 1,
         "308 redirect should preserve the original PUT method");

      Assert
        (Index (Second_Text, "Content-Length: 5") > 0,
         "308 replay should serialize a recomputed Content-Length for the replayed body");

      Assert
        (Index (Second_Text, CRLF & CRLF & "again") > 0,
         "308 replay should preserve the original in-memory payload bytes");
   end Test_Client_Redirect_308_Replays_Body_When_Allowed;

   procedure Test_Client_Cross_Origin_Redirect_Strips_Credentials

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type Cross_Origin_Server is
         entry Ready (First_Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Cross_Origin_Server;

      task body Cross_Origin_Server is
         First_Server   : GNAT.Sockets.Socket_Type;
         Second_Server  : GNAT.Sockets.Socket_Type;
         Peer           : GNAT.Sockets.Socket_Type;
         First_Addr     :
           GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Second_Addr    :
           GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;
         First_Port_No  : Http_Client.URI.TCP_Port;
         Second_Port_No : Http_Client.URI.TCP_Port;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
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

         GNAT.Sockets.Create_Socket (First_Server);
         First_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         First_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (First_Server, First_Addr);
         GNAT.Sockets.Listen_Socket (First_Server);

         GNAT.Sockets.Create_Socket (Second_Server);
         Second_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Second_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Second_Server, Second_Addr);
         GNAT.Sockets.Listen_Socket (Second_Server);

         declare
            First_Bound  : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (First_Server);
            Second_Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Second_Server);
         begin
            First_Port_No := Http_Client.URI.TCP_Port (First_Bound.Port);
            Second_Port_No := Http_Client.URI.TCP_Port (Second_Bound.Port);

            accept Ready (First_Port : out Http_Client.URI.TCP_Port) do
               First_Port := First_Port_No;
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (First_Server, Peer, Peer_Addr);
         Receive_Request (First_Request);
         Send_Response
           ("HTTP/1.1 302 Found"
            & CRLF
            & "Location: http://127.0.0.1:"
            & Decimal_Image (Natural (Second_Port_No))
            & "/final"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (First_Server);

         GNAT.Sockets.Accept_Socket (Second_Server, Peer, Peer_Addr);
         Receive_Request (Second_Request);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Second_Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Request;
            Second := Second_Request;
         end Requests_Seen;
      end Cross_Origin_Server;

      Server      : Cross_Origin_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "cross-origin redirect start URI");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Authorization", "Bearer secret"),
         "authorization header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Cookie", "sid=secret"),
         "cookie header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set
           (Headers, "Proxy-Authorization", "Basic proxy-secret"),
         "proxy authorization header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Accept", "text/plain"),
         "accept header should be accepted");
      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2"),
         "Git-Protocol header should be accepted");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "cross-origin redirect request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "cross-origin redirect should follow when scheme is not downgraded");

      Assert
        (Result.Redirect_Count = 1,
         "cross-origin redirect should count one followed hop");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "Authorization: Bearer secret") > 0,
         "original cross-origin request should include caller authorization");

      Assert
        (Index (First_Text, "Proxy-Authorization:") = 0,
         "original direct request should not leak proxy authorization to origin");

      Assert
        (Index (First_Text, "Git-Protocol: version=2") > 0,
         "original cross-origin request should include caller Git-Protocol header");

      Assert
        (Index (Second_Text, "GET /final HTTP/1.1") = 1,
         "cross-origin target should receive final GET request");

      Assert
        (Index (Second_Text, "Authorization:") = 0,
         "cross-origin redirect should strip Authorization");

      Assert
        (Index (Second_Text, "Cookie:") = 0,
         "cross-origin redirect should strip Cookie");

      Assert
        (Index (Second_Text, "Proxy-Authorization:") = 0,
         "cross-origin redirect should strip Proxy-Authorization");

      Assert
        (Index (Second_Text, "Git-Protocol:") = 0,
         "cross-origin redirect should strip Git-Protocol by default");

      Assert
        (Index (Second_Text, "Accept: text/plain") > 0,
         "cross-origin redirect should preserve non-sensitive ordinary headers");
   end Test_Client_Cross_Origin_Redirect_Strips_Credentials;

   procedure Test_Client_Redirect_Max_Count
      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 302 Found"
        & CRLF
        & "Location: /loop"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;

      task type Loop_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Loop_Server;

      task body Loop_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         procedure Serve_Once is
            Raw_Request  : Stream_Element_Array (1 .. 4096);
            Request_Last : Stream_Element_Offset;
            Raw          :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response_Text'Length));
            Last         : Stream_Element_Offset;
         begin
            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Request_Last);
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response_Text
                         (Response_Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
            GNAT.Sockets.Close_Socket (Peer);
         end Serve_Once;
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

         Serve_Once;
         Serve_Once;
         GNAT.Sockets.Close_Socket (Server);
      end Loop_Server;

      Server    : Loop_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Result    : Http_Client.Clients.Redirect_Result;
      Redirects : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      Client    : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Port);

      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/loop",
         URI,
         "redirect loop start URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "redirect loop request should construct");

      Redirects.Follow_Redirects := True;
      Redirects.Max_Redirects := 1;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Too_Many_Redirects,
         "redirect loop should stop deterministically at the configured limit");

      Assert
        (Result.Redirect_Count = 1,
         "too-many-redirects result should preserve the number of followed hops");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 302,
         "too-many-redirects result should preserve the last redirect response");
   end Test_Client_Redirect_Max_Count;

   procedure Test_Client_Redirect_IPv6_Relative_Preserves_Authority

      (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF           : constant String :=
        Character'Val (13) & Character'Val (10);
      Final_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 2" & CRLF & CRLF & "OK";

      task type IPv6_Redirect_Server is
         entry Ready
           (Available : out Boolean;
            Port      : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First  : out Unbounded_String;
            Second : out Unbounded_String);
      end IPv6_Redirect_Server;

      task body IPv6_Redirect_Server is
         Server_Socket  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
         Peer           : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
         Server_Addr    : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet6);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;
         Bound_Port     : Http_Client.URI.TCP_Port := 1;
         Is_Available   : Boolean := False;

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
            if Server_Socket /= GNAT.Sockets.No_Socket then
               GNAT.Sockets.Close_Socket (Server_Socket);
               Server_Socket := GNAT.Sockets.No_Socket;
            end if;
         exception
            when others =>
               Server_Socket := GNAT.Sockets.No_Socket;
         end Close_Server;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
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
         begin
            GNAT.Sockets.Create_Socket
              (Socket => Server_Socket,
               Family => GNAT.Sockets.Family_Inet6);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("::1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server_Socket, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server_Socket);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server_Socket);
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
            GNAT.Sockets.Accept_Socket (Server_Socket, Peer, Peer_Addr);
            Receive_Request (First_Request);
            Send_Response
              ("HTTP/1.1 302 Found"
               & CRLF
               & "Location: /final"
               & CRLF
               & "Content-Length: 0"
               & CRLF
               & CRLF);
            Close_Peer;

            GNAT.Sockets.Accept_Socket (Server_Socket, Peer, Peer_Addr);
            Receive_Request (Second_Request);
            Send_Response (Final_Response);
            Close_Peer;
            Close_Server;

            accept Requests_Seen
              (First  : out Unbounded_String;
               Second : out Unbounded_String)
            do
               First := First_Request;
               Second := Second_Request;
            end Requests_Seen;
         end if;
      exception
         when others =>
            Close_Peer;
            Close_Server;
      end IPv6_Redirect_Server;

      Server      : IPv6_Redirect_Server;
      Available   : Boolean;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Server.Ready (Available, Port);

      if not Available then
         return;
      end if;

      Assert_Parse_Ok
        ("http://[::1]:" & Decimal_Image (Natural (Port)) & "/start",
         URI,
         "IPv6 relative redirect start URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => URI,
            Item   => Request)
         = Http_Client.Errors.Ok,
         "IPv6 relative redirect request should construct");

      Redirects.Follow_Redirects := True;
      Redirects.Max_Redirects := 1;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "IPv6 relative redirect should follow successfully when loopback is available");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Result.Redirect_Count = 1,
         "IPv6 relative redirect should report one followed hop");
      Assert
        (Http_Client.URI.Image (Result.Final_URI) =
         "http://[::1]:" & Decimal_Image (Natural (Port)) & "/final",
         "relative redirect from IPv6 origin should preserve bracketed authority");
      Assert
        (Index (To_String (First_Text), "Host: [::1]:" & Decimal_Image (Natural (Port))) > 0,
         "initial IPv6 redirect request should send bracketed Host header");
      Assert
        (Index (To_String (Second_Text), "GET /final HTTP/1.1") > 0,
         "followed IPv6 relative redirect should request the relative target");
      Assert
        (Index (To_String (Second_Text), "Host: [::1]:" & Decimal_Image (Natural (Port))) > 0,
         "followed IPv6 relative redirect should preserve bracketed Host header");
   end Test_Client_Redirect_IPv6_Relative_Preserves_Authority;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Redirects");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Client_Redirect_Stores_Cookie_For_Next_Hop'Access,
         "Test_Client_Redirect_Stores_Cookie_For_Next_Hop");
      Register_Routine
        (T,
         Test_Client_Redirect_Retry_Disabled_Remains_One_Attempt'Access,
         "Test_Client_Redirect_Retry_Disabled_Remains_One_Attempt");
      Register_Routine
        (T,
         Test_Client_Redirect_Disabled_Returns_302'Access,
         "Test_Client_Redirect_Disabled_Returns_302");
      Register_Routine
        (T,
         Test_Client_Redirect_Missing_Location_Is_Invalid'Access,
         "Test_Client_Redirect_Missing_Location_Is_Invalid");
      Register_Routine
        (T,
         Test_Client_Redirect_307_Body_Replay_Disallowed'Access,
         "Test_Client_Redirect_307_Body_Replay_Disallowed");
      Register_Routine
        (T,
         Test_Client_Redirect_303_Preserves_HEAD'Access,
         "Test_Client_Redirect_303_Preserves_HEAD");
      Register_Routine
        (T,
         Test_Client_Redirect_303_Post_Drops_Body_Headers'Access,
         "Test_Client_Redirect_303_Post_Drops_Body_Headers");
      Register_Routine
        (T,
         Test_Client_Redirect_308_Replays_Body_When_Allowed'Access,
         "Test_Client_Redirect_308_Replays_Body_When_Allowed");
      Register_Routine
        (T,
         Test_Client_Cross_Origin_Redirect_Strips_Credentials'Access,
         "Test_Client_Cross_Origin_Redirect_Strips_Credentials");
      Register_Routine
        (T,
         Test_Client_Redirect_Max_Count'Access,
         "Test_Client_Redirect_Max_Count");
      Register_Routine
        (T,
         Test_Client_Redirect_IPv6_Relative_Preserves_Authority'Access,
         "Test_Client_Redirect_IPv6_Relative_Preserves_Authority");
   end Register_Tests;

end Http_Client.Redirects.Tests;
