with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.Sockets;

with AUnit.Assertions;
with Http_Client.Connection_Pools;

with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Resources;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Response_Streams.Tests is

   use AUnit.Assertions;
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Diagnostics.Event_Kind;
   use type Http_Client.Diagnostics.Protocol_Version;
   use type Http_Client.Types.Method_Name;

   Diagnostic_Callback_Count      : Natural := 0;
   Diagnostic_Last_Event          : Http_Client.Diagnostics.Diagnostic_Event;
   Diagnostic_Last_Closed_Event   : Http_Client.Diagnostics.Diagnostic_Event;
   Diagnostic_Fail_Next           : Boolean := False;
   Diagnostic_Current_Time        : Ada.Calendar.Time :=
     Ada.Calendar.Time_Of (2026, 5, 13, 12.0);

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status) is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;
      if Event.Kind = Http_Client.Diagnostics.Streaming_Response_Closed then
         Diagnostic_Last_Closed_Event := Event;
      end if;

      if Diagnostic_Fail_Next then
         Diagnostic_Fail_Next := False;
         Status := Http_Client.Errors.Internal_Error;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Capture_Diagnostic;

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
     (Options : in out Http_Client.Response_Streams.Streaming_Options) is
      Bounded : constant Http_Client.Transports.TCP.Timeout_Config :=
        (Connect => 200,
         Read    => 200,
         Write   => 200);
   begin
      Options.Timeouts := Bounded;
      Options.TLS.Timeouts := Bounded;
   end Apply_Test_Timeouts;

   function Diagnostic_Test_Time return Ada.Calendar.Time is
   begin
      return Diagnostic_Current_Time;
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

   function Unused_Loopback_Port return Http_Client.URI.TCP_Port is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Opened  : Boolean := False;
   begin
      GNAT.Sockets.Create_Socket (Socket);
      Opened := True;
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Reuse_Address,
          Enabled => True));
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := 0;
      GNAT.Sockets.Bind_Socket (Socket, Address);
      Address := GNAT.Sockets.Get_Socket_Name (Socket);
      GNAT.Sockets.Close_Socket (Socket);
      Opened := False;
      return Http_Client.URI.TCP_Port (Address.Port);
   exception
      when others =>
         if Opened then
            GNAT.Sockets.Close_Socket (Socket);
         end if;
         return 9;
   end Unused_Loopback_Port;

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

   procedure Test_Response_Stream_Lifecycle_Default_Close

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Stream : Http_Client.Response_Streams.Streaming_Response;
      Buffer : String (1 .. 4);
      Last   : Natural := 99;
   begin
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "closing a default streaming response should be safe");
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "closing a default streaming response twice should be idempotent");
      Assert
        (Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.Not_Connected,
         "read after close/default stream should report Not_Connected");
      Assert (Last = 0, "failed streaming read should leave Last at zero");
   end Test_Response_Stream_Lifecycle_Default_Close;

   procedure Test_Response_Stream_Content_Length_Fragmented_Reads

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF        : constant String := Character'Val (13) & Character'Val (10);
      Header_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 5"
        & CRLF
        & "X-Stream: yes"
        & CRLF
        & CRLF;

      task type Stream_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Stream_Server;

      task body Stream_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;

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
         GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Req_Last);
         Send_Text (Header_Text & "He");
         Send_Text ("llo");
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Stream_Server;

      Server           : Stream_Server;
      Port             : Http_Client.URI.TCP_Port;
      URI              : Http_Client.URI.URI_Reference;
      Request          : Http_Client.Requests.Request;
      Stream           : Http_Client.Response_Streams.Streaming_Response;
      Options          : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status           : Http_Client.Errors.Result_Status;
      Chunk            : String (1 .. 2);
      Last             : Natural := 0;
      Response_Content : Unbounded_String := Null_Unbounded_String;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Read_Buffer_Size := 16;
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/stream",
         URI,
         "streaming content-length URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming content-length request should construct");

      Http_Client.Resources.Reset_All;
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming open should return after headers for Content-Length response");
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Streaming_Responses_Open)
         = 1,
         "streaming open should expose one owned response resource");
      Assert
        (Http_Client.Response_Streams.Status_Code (Stream) = 200,
         "streaming metadata should expose status before body is fully consumed");
      Assert
        (Http_Client.Responses.Response_Body
           (Http_Client.Response_Streams.Metadata (Stream))
         = "",
         "streaming metadata response should not buffer the body");

      loop
         Status :=
           Http_Client.Response_Streams.Read_Some (Stream, Chunk, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "streaming content-length read should return Ok until EOF");
         if Last > 0 then
            Append
              (Response_Content,
               Chunk (Chunk'First .. Chunk'First + Last - 1));
         end if;
      end loop;

      Assert
        (To_String (Response_Content) = "Hello",
         "streaming content-length reads should return exact decoded body bytes");
      Assert
        (Http_Client.Response_Streams.End_Of_Body (Stream),
         "streaming content-length response should report end-of-body after exact reads");
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Streaming_Responses_Open)
         = 0,
         "streaming EOF should release the owned response resource");
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "closing consumed stream should remain idempotent");
      Assert
        (Http_Client.Resources.Value
           (Http_Client.Resources.Streaming_Responses_Open)
         = 0,
         "idempotent stream close should not underflow resource counters");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Content_Length_Fragmented_Reads;

   procedure Test_Response_Stream_HEAD_Reports_Immediate_EOF

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 5" & CRLF & CRLF;

      task type Head_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Head_Server;

      task body Head_Server is
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
      end Head_Server;

      Server  : Head_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Buffer  : String (1 .. 4);
      Last    : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/head",
         URI,
         "streaming HEAD URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.HEAD, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming HEAD request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming HEAD response should open successfully");
      Assert
        (Http_Client.Response_Streams.End_Of_Body (Stream),
         "HEAD streaming response should immediately report end-of-body");
      Assert
        (Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "HEAD streaming read should return ordinary EOF");
      Assert (Last = 0, "HEAD streaming EOF should not return body bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_HEAD_Reports_Immediate_EOF;

   procedure Test_Response_Stream_Accepts_Chunked_Transfer_Encoding
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Transfer-Encoding: chunked"
        & CRLF
        & CRLF
        & "0"
        & CRLF
        & CRLF;

      task type TE_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end TE_Server;

      task body TE_Server is
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
      end TE_Server;

      Server  : TE_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/chunked",
         URI,
         "streaming transfer-encoding URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "streaming transfer-encoding request should construct");
      Assert
        (Http_Client.Response_Streams.Open (Request, Stream)
         = Http_Client.Errors.Ok,
         "streaming chunked Transfer-Encoding should open successfully");
      declare
         Buffer : String (1 .. 8);
         Last   : Natural := 0;
      begin
         Assert
           (Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last)
            = Http_Client.Errors.End_Of_Stream,
            "zero-length chunked stream should report ordinary EOF");
         Assert (Last = 0, "zero-length chunked stream should not return bytes");
      end;
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Accepts_Chunked_Transfer_Encoding;

   procedure Test_Response_Stream_Git_Pkt_Line_Chunked_Binary
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Expected_Body : constant String :=
        "0008"
        & "NAK"
        & Character'Val (0)
        & Character'Val (255)
        & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
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
        & CRLF;

      task type Git_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Git_Server;

      task body Git_Server is
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
      end Git_Server;

      Server    : Git_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request   : Http_Client.Requests.Request;
      Stream    : Http_Client.Response_Streams.Streaming_Response;
      Buffer    : Stream_Element_Array (1 .. 3);
      Last      : Stream_Element_Offset;
      Status    : Http_Client.Errors.Result_Status;
      Collected : String (1 .. Expected_Body'Length);
      Used      : Natural := 0;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Port))
         & "/repo.git/git-upload-pack",
         URI,
         "Git-like streaming URI should parse");
      Assert
        (Http_Client.Headers.Set
           (Headers, "Accept", "application/x-git-upload-pack-result")
         = Http_Client.Errors.Ok,
         "Git upload-pack Accept header should be valid");
      Assert
        (Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity")
         = Http_Client.Errors.Ok,
         "Git identity Accept-Encoding header should be valid");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.POST,
            URI => URI,
            Item => Request,
            Headers => Headers,
            Payload => "0000")
         = Http_Client.Errors.Ok,
         "Git-like upload-pack request should construct");
      Status := Http_Client.Response_Streams.Open (Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "Git-like chunked response stream should open successfully");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "Git-like chunked response read should succeed until EOF");
         Assert
           (Last >= Buffer'First,
            "Git-like chunked response read should return bytes before EOF");
         declare
            Count : constant Natural := Natural (Last - Buffer'First + 1);
         begin
            Assert
              (Used + Count <= Collected'Length,
               "Git-like chunked decoded response should not exceed expected body");
            for I in 0 .. Count - 1 loop
               Collected (Collected'First + Used + I) :=
                 Character'Val
                   (Integer (Buffer (Buffer'First + Stream_Element_Offset (I))));
            end loop;
            Used := Used + Count;
         end;
      end loop;

      Assert
        (Used = Expected_Body'Length,
         "Git-like chunked decoded response length should match expected body");
      Assert
        (Collected = Expected_Body,
         "Git-like chunked streaming should expose exact decoded binary bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Git_Pkt_Line_Chunked_Binary;

   procedure Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Expected_Body : constant String :=
        "A" & Character'Val (0) & Character'Val (255) & Character'Val (10) & "Z";
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        CRLF &
        "1;phase3=split" & CRLF & "A" & CRLF &
        "4" & CRLF &
        Character'Val (0) & Character'Val (255) & Character'Val (10) & "Z" & CRLF &
        "0" & CRLF &
        "Git-Trailer: bounded" & CRLF &
        CRLF;

      task type Split_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Split_Server;

      task body Split_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;
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
         GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Req_Last);
         for Index in Response_Text'Range loop
            declare
               Raw       : Stream_Element_Array (1 .. 1);
               Sent_Last : Stream_Element_Offset;
            begin
               Raw (1) := Stream_Element (Character'Pos (Response_Text (Index)));
               GNAT.Sockets.Send_Socket (Peer, Raw, Sent_Last);
            end;
         end loop;
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Split_Server;

      Server    : Split_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Stream    : Http_Client.Response_Streams.Streaming_Response;
      Options   : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Buffer    : Stream_Element_Array (1 .. 1);
      Last      : Stream_Element_Offset;
      Status    : Http_Client.Errors.Result_Status;
      Collected : String (1 .. Expected_Body'Length);
      Used      : Natural := 0;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Read_Buffer_Size := 1;
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Port))
         & "/split-chunk-metadata",
         URI,
         "split chunk metadata URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "split chunk metadata request should construct");
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "split chunk metadata stream should open successfully");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "split chunk metadata read should succeed until EOF");
         Assert
           (Last = Buffer'First,
            "tiny byte-array buffer should return exactly one byte per read");
         Used := Used + 1;
         Assert
           (Used <= Collected'Length,
            "split chunk metadata body should not exceed expected length");
         Collected (Collected'First + Used - 1) :=
           Character'Val (Integer (Buffer (Buffer'First)));
      end loop;

      Assert
        (Used = Expected_Body'Length,
         "split chunk metadata decoded body length should match expected");
      Assert
        (Collected = Expected_Body,
         "split chunk metadata path should expose only entity bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer;

   procedure Test_Response_Stream_Chunked_Trailer_Line_Limit
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        CRLF &
        "1" & CRLF & "A" & CRLF &
        "0" & CRLF &
        "Very-Long-Trailer-Name: trailer-value" & CRLF &
        CRLF;

      task type Trailer_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Trailer_Server;

      task body Trailer_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;
         Raw         : Stream_Element_Array
           (1 .. Stream_Element_Offset (Response_Text'Length));
         Sent_Last   : Stream_Element_Offset;
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
      end Trailer_Server;

      Server  : Trailer_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Buffer  : String (1 .. 4);
      Last    : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Max_Header_Line_Size := 32;
      Options.Max_Header_Size := 128;
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Port))
         & "/oversized-trailer",
         URI,
         "oversized trailer line-limit URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "oversized trailer line-limit request should construct");
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "oversized trailer line-limit stream should open before body/trailers are read");
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Ok and then Last = 1 and then Buffer (1) = 'A',
         "oversized trailer line-limit test should first expose the decoded body byte");
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Header_Too_Large,
         "oversized chunked response trailer line should fail deterministically");
      Assert (Last = 0, "failed trailer line-limit read should not expose trailer bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Chunked_Trailer_Line_Limit;

   procedure Test_Response_Stream_Chunked_Trailer_Total_Limit
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        CRLF &
        "1" & CRLF & "B" & CRLF &
        "0" & CRLF &
        "X-A: 1111111111" & CRLF &
        "X-B: 2222222222" & CRLF &
        "X-C: 3333333333" & CRLF &
        "X-D: 4444444444" & CRLF &
        "X-E: 5555555555" & CRLF &
        CRLF;

      task type Trailer_Total_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Trailer_Total_Server;

      task body Trailer_Total_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;
         Raw         : Stream_Element_Array
           (1 .. Stream_Element_Offset (Response_Text'Length));
         Sent_Last   : Stream_Element_Offset;
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
      end Trailer_Total_Server;

      Server  : Trailer_Total_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Buffer  : String (1 .. 4);
      Last    : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Server.Ready (Port);
      Apply_Test_Timeouts (Options);
      Options.Max_Header_Line_Size := 64;
      Options.Max_Header_Size := 64;
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Port))
         & "/oversized-trailer-total",
         URI,
         "oversized trailer total-limit URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "oversized trailer total-limit request should construct");
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "oversized trailer total-limit stream should open before body/trailers are read");
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Ok and then Last = 1 and then Buffer (1) = 'B',
         "oversized trailer total-limit test should first expose the decoded body byte");
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      Assert
        (Status = Http_Client.Errors.Header_Too_Large,
         "oversized chunked response trailer section should fail deterministically");
      Assert (Last = 0, "failed trailer total-limit read should not expose trailer bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Chunked_Trailer_Total_Limit;

   procedure Test_Response_Stream_Expect_Chunked_Final_Response_Does_Not_Upload
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String := Character'Val (13) & Character'Val (10);
      Response_Body : constant String := "no" & Character'Val (0) & "-upload";
      Response_Text : constant String :=
        "HTTP/1.1 417 Expectation Failed" & CRLF &
        "Transfer-Encoding: chunked" & CRLF &
        CRLF &
        "2;expect-stream=true" & CRLF & "no" & CRLF &
        "8" & CRLF & Character'Val (0) & "-upload" & CRLF &
        "0" & CRLF &
        "X-Stream-Trailer: ignored" & CRLF &
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
         select
            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request_Text;
            end Request_Seen;
         or
            delay 0.2;
         end select;
      end Reject_Server;

      Server    : Reject_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request   : Http_Client.Requests.Request;
      Stream    : Http_Client.Response_Streams.Streaming_Response;
      Status    : Http_Client.Errors.Result_Status;
      Buffer    : String (1 .. 3);
      Last      : Natural := 0;
      Collected : String (1 .. Response_Body'Length);
      Used      : Natural := 0;
      Captured  : Unbounded_String;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Port))
         & "/expect-stream-reject-chunked",
         URI,
         "streaming expect reject URI should parse");
      Assert
        (Http_Client.Headers.Set (Headers, "Expect", "100-continue")
         = Http_Client.Errors.Ok,
         "streaming Expect header should be accepted");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.POST,
            URI => URI,
            Item => Request,
            Headers => Headers,
            Payload => "abc")
         = Http_Client.Errors.Ok,
         "streaming expect reject request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "streaming chunked final expect rejection should open as a response stream");
      Assert
        (Http_Client.Response_Streams.Status_Code (Stream) = 417,
         "streaming early final response should expose 417 before reading body");

      loop
         Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "streaming early final chunked body should decode until EOF");
         Assert
           (Last >= Buffer'First,
            "streaming early final chunked read should return bytes before EOF");
         declare
            Count : constant Natural := Last - Buffer'First + 1;
         begin
            Assert
              (Used + Count <= Collected'Length,
               "streaming early final decoded body should not exceed expected length");
            Collected (Collected'First + Used .. Collected'First + Used + Count - 1) :=
              Buffer (Buffer'First .. Buffer'First + Count - 1);
            Used := Used + Count;
         end;
      end loop;

      Assert
        (Used = Response_Body'Length,
         "streaming early final decoded body length should match expected body");
      Assert
        (Collected = Response_Body,
         "streaming early final chunked body should be decoded exactly");
      select
         Server.Request_Seen (Captured);
      or
         delay 0.5;
         Assert
           (False,
            "response-stream reject server did not publish captured request");
      end select;
      Assert
        (Index (Captured, CRLF & CRLF & "abc") = 0,
         "streaming request body must not be sent when server rejects Expect");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Expect_Chunked_Final_Response_Does_Not_Upload;

   procedure Test_Response_Stream_Content_Length_Zero_Immediate_EOF
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 0" & CRLF & CRLF;

      task type Zero_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Zero_Server;

      task body Zero_Server is
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
      end Zero_Server;

      Server  : Zero_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Buffer  : String (1 .. 4);
      Last    : Natural := 99;
      Status  : Http_Client.Errors.Result_Status;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Timing  : Http_Client.Diagnostics.Timing_Snapshot;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/zero",
         URI,
         "zero-length streaming URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "zero-length streaming request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "zero-length streaming response should open successfully");
      Assert
        (Http_Client.Response_Streams.End_Of_Body (Stream),
         "zero-length Content-Length streaming response should immediately be complete");
      Assert
        (Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.End_Of_Stream,
         "zero-length streaming read should return ordinary EOF");
      Assert (Last = 0, "zero-length streaming EOF should return no bytes");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Content_Length_Zero_Immediate_EOF;

   procedure Test_Response_Stream_Close_Delimited_Reads_To_EOF
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "X-Close-Delimited: yes"
        & CRLF
        & CRLF
        & "close-body";

      task type Close_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Close_Server;

      task body Close_Server is
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
      end Close_Server;

      Server           : Close_Server;
      Port             : Http_Client.URI.TCP_Port;
      URI              : Http_Client.URI.URI_Reference;
      Request          : Http_Client.Requests.Request;
      Stream           : Http_Client.Response_Streams.Streaming_Response;
      Buffer           : String (1 .. 3);
      Last             : Natural := 0;
      Status           : Http_Client.Errors.Result_Status;
      Response_Content : Unbounded_String := Null_Unbounded_String;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/close",
         URI,
         "close-delimited streaming URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "close-delimited streaming request should construct");

      Status := Http_Client.Response_Streams.Open (Request, Stream);
      Assert
        (Status = Http_Client.Errors.Ok,
         "close-delimited streaming open should succeed after headers");
      loop
         Status :=
           Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         Assert
           (Status = Http_Client.Errors.Ok,
            "close-delimited streaming read should return Ok before EOF");
         if Last > 0 then
            Append
              (Response_Content,
               Buffer (Buffer'First .. Buffer'First + Last - 1));
         end if;
      end loop;
      Assert
        (To_String (Response_Content) = "close-body",
         "close-delimited streaming should return body bytes until clean EOF");
      Assert
        (Http_Client.Response_Streams.End_Of_Body (Stream),
         "close-delimited streaming should report end-of-body after EOF");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Close_Delimited_Reads_To_EOF;

   procedure Test_Response_Stream_Early_Close_Read_After_Close
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF          : constant String :=
        Character'Val (13) & Character'Val (10);
      Response_Text : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 10"
        & CRLF
        & CRLF
        & "0123456789";

      task type Early_Close_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Early_Close_Server;

      task body Early_Close_Server is
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
      end Early_Close_Server;

      Server  : Early_Close_Server;
      Port    : Http_Client.URI.TCP_Port;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Buffer  : String (1 .. 4);
      Last    : Natural := 99;
      Status  : Http_Client.Errors.Result_Status;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Timing  : Http_Client.Diagnostics.Timing_Snapshot;
   begin
      Server.Ready (Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:" & Decimal_Image (Natural (Port)) & "/early-close",
         URI,
         "early-close streaming URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "early-close streaming request should construct");

      Diagnostic_Callback_Count := 0;
      Diagnostic_Last_Closed_Event := (others => <>);
      Diagnostic_Current_Time := Ada.Calendar.Time_Of (2026, 5, 13, 12.0);
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access,
         Clock    => Diagnostic_Test_Time'Unrestricted_Access);
      Options.Diagnostics := Context'Unchecked_Access;

      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "early-close streaming response should open successfully");
      Diagnostic_Current_Time := Ada.Calendar.Time_Of (2026, 5, 13, 13.25);
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "explicit early close should succeed");
      Timing := Http_Client.Diagnostics.Timing (Context);
      Assert
        (Timing.Request_Finish_Count = 1,
         "streaming close should contribute one request-finish timing");
      Assert
        (Timing.Request_Total_Milliseconds = 1_250,
         "streaming close should contribute elapsed request milliseconds");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.Request_Finish,
         "streaming close should emit request-finish as the final diagnostic event");
      Assert
        (Diagnostic_Last_Event.Elapsed_Milliseconds = 1_250,
         "streaming request-finish event should include elapsed milliseconds");
      Assert
        (Diagnostic_Last_Event.Status_Code = 200,
         "streaming request-finish event should include final status code");
      Assert
        (Diagnostic_Last_Event.Redirect_Count = 0,
         "streaming request-finish event should include redirect count");
      Assert
        (Diagnostic_Last_Event.Retry_Attempt = 1,
         "streaming request-finish event should include retry attempt count");
      Assert
        (Diagnostic_Last_Event.Protocol = Http_Client.Diagnostics.Protocol_HTTP_1_1,
         "streaming request-finish event should include negotiated protocol");
      Assert
        (Diagnostic_Last_Closed_Event.Kind = Http_Client.Diagnostics.Streaming_Response_Closed,
         "streaming close should emit a closed diagnostic event");
      Assert
        (Diagnostic_Last_Closed_Event.Elapsed_Milliseconds = 1_250,
         "streaming closed event should include elapsed milliseconds");
      Assert
        (Diagnostic_Last_Closed_Event.Status_Code = 200,
         "streaming closed event should include final status code");
      Assert
        (Diagnostic_Last_Closed_Event.Redirect_Count = 0,
         "streaming closed event should include redirect count");
      Assert
        (Diagnostic_Last_Closed_Event.Retry_Attempt = 1,
         "streaming closed event should include retry attempt count");
      Assert
        (Diagnostic_Last_Closed_Event.Protocol = Http_Client.Diagnostics.Protocol_HTTP_1_1,
         "streaming closed event should include negotiated protocol");
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "explicit early close should be idempotent");
      Assert
        (Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.Not_Connected,
         "read after explicit early close should report Not_Connected");
      Assert (Last = 0, "read after explicit early close should clear Last");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_Early_Close_Read_After_Close;

   procedure Test_Response_Stream_HTTPS_Proxy_CONNECT_Attempts_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Proxy   : Http_Client.Proxies.Proxy_Config;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Port    : constant Http_Client.URI.TCP_Port := Unused_Loopback_Port;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Proxies.Parse
           ("http://127.0.0.1:" & Decimal_Image (Natural (Port)), Proxy)
         = Http_Client.Errors.Ok,
         "proxy for streaming HTTPS CONNECT test should parse");
      Options.Proxy := Proxy;
      Apply_Test_Timeouts (Options);
      Options.TLS.Disable_Certificate_Verification := True;

      Assert_Parse_Ok
        ("https://example.com/repo.git/info/refs?service=git-upload-pack",
         URI,
         "HTTPS Git URI for streaming proxy CONNECT test should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS Git request for streaming proxy CONNECT test should construct");

      Status :=
        Http_Client.Response_Streams.Open
          (Request => Request,
           Stream  => Stream,
           Options => Options);
      Assert
        (Status = Http_Client.Errors.Proxy_Connection_Failed
         or else Status = Http_Client.Errors.Connection_Failed
         or else Status = Http_Client.Errors.Timeout,
         "streaming HTTPS through an HTTP proxy should attempt CONNECT and " &
         "report deterministic proxy connection failure when the proxy is " &
         "unreachable; actual status=" &
         Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "stream close after failed HTTPS proxy CONNECT should be idempotent");
   end Test_Response_Stream_HTTPS_Proxy_CONNECT_Attempts_Proxy;

   procedure Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type CONNECT_Proxy is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Finished
           (Saw_CONNECT      : out Boolean;
            Saw_Host         : out Boolean;
            Saw_Proxy_Auth   : out Boolean;
            Leaked_Origin    : out Boolean);
      end CONNECT_Proxy;

      task body CONNECT_Proxy is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw_Request : Stream_Element_Array (1 .. 4096);
         Req_Last    : Stream_Element_Offset;
         Response    : constant String :=
           "HTTP/1.1 403 Forbidden" & CRLF
           & "Content-Length: 0" & CRLF & CRLF;
         Raw_Response : Stream_Element_Array
           (1 .. Stream_Element_Offset (Response'Length));
         Sent_Last    : Stream_Element_Offset;
         Request_Text : String (1 .. 4096) := [others => Character'Val (0)];
         Request_Len  : Natural := 0;
         Local_CONNECT    : Boolean := False;
         Local_Host       : Boolean := False;
         Local_Proxy_Auth : Boolean := False;
         Local_Leak       : Boolean := False;
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
         GNAT.Sockets.Receive_Socket (Peer, Raw_Request, Req_Last);

         if Req_Last >= Raw_Request'First then
            Request_Len := Natural (Req_Last - Raw_Request'First + 1);
            for Index in 1 .. Request_Len loop
               Request_Text (Index) :=
                 Character'Val
                   (Integer (Raw_Request
                      (Raw_Request'First + Stream_Element_Offset (Index - 1))));
            end loop;
         end if;

         declare
            Observed : constant String := Request_Text (1 .. Request_Len);
         begin
            Local_CONNECT :=
              Ada.Strings.Fixed.Index
                (Observed, "CONNECT example.com:443 HTTP/1.1") > 0;
            Local_Host :=
              Ada.Strings.Fixed.Index (Observed, "Host: example.com:443") > 0;
            Local_Proxy_Auth :=
              Ada.Strings.Fixed.Index
                (Observed, "Proxy-Authorization: Basic dGVzdA==") > 0;
            Local_Leak :=
              Ada.Strings.Fixed.Index (Observed, "Git-Protocol:") > 0
              or else Ada.Strings.Fixed.Index
                (Observed, CRLF & "Authorization:") > 0
              or else Ada.Strings.Fixed.Index (Observed, "Cookie:") > 0
              or else Ada.Strings.Fixed.Index (Observed, "GET ") > 0
              or else Ada.Strings.Fixed.Index (Observed, "POST ") > 0;
         end;

         for Index in Raw_Response'Range loop
            Raw_Response (Index) :=
              Stream_Element
                (Character'Pos
                   (Response
                      (Response'First + Natural (Index - Raw_Response'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Raw_Response, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Finished
              (Saw_CONNECT      : out Boolean;
               Saw_Host         : out Boolean;
               Saw_Proxy_Auth   : out Boolean;
               Leaked_Origin    : out Boolean) do
               Saw_CONNECT := Local_CONNECT;
               Saw_Host := Local_Host;
               Saw_Proxy_Auth := Local_Proxy_Auth;
               Leaked_Origin := Local_Leak;
            end Finished;
         or
            delay 0.2;
         end select;
      end CONNECT_Proxy;

      Server          : CONNECT_Proxy;
      Port            : Http_Client.URI.TCP_Port;
      Base_Proxy      : Http_Client.Proxies.Proxy_Config;
      Proxy           : Http_Client.Proxies.Proxy_Config;
      URI             : Http_Client.URI.URI_Reference;
      Headers         : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request         : Http_Client.Requests.Request;
      Stream          : Http_Client.Response_Streams.Streaming_Response;
      Options         : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status          : Http_Client.Errors.Result_Status;
      Saw_CONNECT     : Boolean;
      Saw_Host        : Boolean;
      Saw_Proxy_Auth  : Boolean;
      Leaked_Origin   : Boolean;
   begin
      Server.Ready (Port);
      Base_Proxy := Http_Client.Proxies.HTTP ("127.0.0.1", Port);
      Assert
        (Http_Client.Proxies.With_Proxy_Authorization
           (Base_Proxy, "Basic dGVzdA==", Proxy) = Http_Client.Errors.Ok,
         "streaming CONNECT test proxy authorization should configure");
      Options.Proxy := Proxy;
      Apply_Test_Timeouts (Options);
      Options.TLS.Disable_Certificate_Verification := True;

      Assert_Parse_Ok
        ("https://example.com/repo.git/info/refs?service=git-upload-pack",
         URI,
         "HTTPS Git URI for successful CONNECT handshake-shape test should parse");
      Assert
        (Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2")
         = Http_Client.Errors.Ok,
         "Git-Protocol header should be valid");
      Assert
        (Http_Client.Headers.Set (Headers, "Authorization", "Bearer origin")
         = Http_Client.Errors.Ok,
         "origin Authorization header should be valid");
      Assert
        (Http_Client.Headers.Set (Headers, "Cookie", "sid=origin")
         = Http_Client.Errors.Ok,
         "origin Cookie header should be valid");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "HTTPS Git request for CONNECT handshake-shape test should construct");

      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Stream  => Stream,
         Options => Options);
      select
         Server.Finished
           (Saw_CONNECT, Saw_Host, Saw_Proxy_Auth, Leaked_Origin);
      or
         delay 0.5;
         Assert
           (False,
            "streaming CONNECT proxy did not publish handshake observation");
      end select;

      Assert
        (Status = Http_Client.Errors.Proxy_Tunnel_Failed,
         "non-2xx CONNECT response should fail before origin TLS while " &
         "still allowing proxy request-shape validation");
      Assert (Saw_CONNECT, "CONNECT request should target the HTTPS origin");
      Assert (Saw_Host, "CONNECT request should include the origin authority Host header");
      Assert
        (Saw_Proxy_Auth,
         "CONNECT request should send Proxy-Authorization only to the proxy");
      Assert
        (not Leaked_Origin,
         "CONNECT request must not leak origin request headers or methods before TLS");
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "stream close after CONNECT request-shape failure should be safe");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT;

   procedure Test_Response_Stream_HTTPS_SOCKS_Proxy_Attempts_Proxy
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Proxy   : Http_Client.Proxies.Proxy_Config;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Port    : constant Http_Client.URI.TCP_Port := Unused_Loopback_Port;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Proxy := Http_Client.Proxies.SOCKS5 ("127.0.0.1", Port);
      Options.Proxy := Proxy;
      Apply_Test_Timeouts (Options);
      Options.TLS.Disable_Certificate_Verification := True;

      Assert_Parse_Ok
        ("https://example.com/repo.git/info/refs?service=git-upload-pack",
         URI,
         "HTTPS Git URI for streaming SOCKS proxy test should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "HTTPS Git request for streaming SOCKS proxy test should construct");

      Status :=
        Http_Client.Response_Streams.Open
          (Request => Request,
           Stream  => Stream,
           Options => Options);
      Assert
        (Status = Http_Client.Errors.Proxy_Connection_Failed
         or else Status = Http_Client.Errors.Connection_Failed
         or else Status = Http_Client.Errors.Timeout,
         "streaming HTTPS through a SOCKS proxy should attempt the SOCKS " &
         "proxy and report deterministic proxy connection failure when " &
         "unreachable; actual status=" &
         Http_Client.Errors.Result_Status'Image (Status));
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "stream close after failed HTTPS SOCKS proxy should be idempotent");
   end Test_Response_Stream_HTTPS_SOCKS_Proxy_Attempts_Proxy;

   procedure Test_Response_Stream_HTTPS_SOCKS_Tunnel_Handshake_Shape

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      task type SOCKS_Proxy is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Finished
           (Saw_Greeting     : out Boolean;
            Saw_Auth         : out Boolean;
            Saw_CONNECT      : out Boolean;
            Leaked_Origin    : out Boolean);
      end SOCKS_Proxy;

      task body SOCKS_Proxy is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;

         Greeting    : Stream_Element_Array (1 .. 3);
         Auth        : Stream_Element_Array (1 .. 11);
         Connect_Req : Stream_Element_Array (1 .. 18);
         Last        : Stream_Element_Offset;
         Sent_Last   : Stream_Element_Offset;

         Method_Reply : constant Stream_Element_Array (1 .. 2) :=
           [1 => 16#05#, 2 => 16#02#];
         Auth_Reply   : constant Stream_Element_Array (1 .. 2) :=
           [1 => 16#01#, 2 => 16#00#];
         Connect_Reply : constant Stream_Element_Array (1 .. 10) :=
           [1 => 16#05#, 2 => 16#05#, 3 => 16#00#, 4 => 16#01#,
            5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
            9 => 16#00#, 10 => 16#00#];

         Local_Greeting : Boolean := False;
         Local_Auth     : Boolean := False;
         Local_CONNECT  : Boolean := False;
         Local_Leak     : Boolean := False;

         function Byte
           (Buffer : Stream_Element_Array;
            Offset : Stream_Element_Offset) return Natural is
         begin
            return Natural (Buffer (Buffer'First + Offset));
         end Byte;

         function Contains_ASCII
           (Buffer  : Stream_Element_Array;
            Length  : Natural;
            Pattern : String) return Boolean
         is
            Text : String (1 .. Length) := [others => Character'Val (0)];
         begin
            if Length = 0 or else Pattern'Length = 0
              or else Pattern'Length > Length
            then
               return False;
            end if;

            for Index in 1 .. Length loop
               Text (Index) :=
                 Character'Val
                   (Integer (Buffer (Buffer'First + Stream_Element_Offset (Index - 1))));
            end loop;

            return Ada.Strings.Fixed.Index (Text, Pattern) > 0;
         end Contains_ASCII;

         procedure Receive_Exact
           (Socket : GNAT.Sockets.Socket_Type;
            Buffer : out Stream_Element_Array;
            Last   : out Stream_Element_Offset)
         is
            Offset     : Stream_Element_Offset := Buffer'First;
            Chunk_Last : Stream_Element_Offset;
         begin
            Last := Buffer'First - 1;
            while Offset <= Buffer'Last loop
               declare
                  Slice : Stream_Element_Array (Offset .. Buffer'Last);
               begin
                  GNAT.Sockets.Receive_Socket (Socket, Slice, Chunk_Last);
                  exit when Chunk_Last < Slice'First;
                  Buffer (Offset .. Chunk_Last) := Slice (Offset .. Chunk_Last);
                  Offset := Chunk_Last + 1;
                  Last := Chunk_Last;
               end;
            end loop;
         end Receive_Exact;
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

         Receive_Exact (Peer, Greeting, Last);
         Local_Greeting :=
           Last = Greeting'Last
           and then Byte (Greeting, 0) = 16#05#
           and then Byte (Greeting, 1) = 16#01#
           and then Byte (Greeting, 2) = 16#02#;
         GNAT.Sockets.Send_Socket (Peer, Method_Reply, Sent_Last);

         Receive_Exact (Peer, Auth, Last);
         Local_Auth :=
           Last = Auth'Last
           and then Byte (Auth, 0) = 16#01#
           and then Byte (Auth, 1) = 4
           and then Byte (Auth, 2) = Character'Pos ('u')
           and then Byte (Auth, 3) = Character'Pos ('s')
           and then Byte (Auth, 4) = Character'Pos ('e')
           and then Byte (Auth, 5) = Character'Pos ('r')
           and then Byte (Auth, 6) = 4
           and then Byte (Auth, 7) = Character'Pos ('p')
           and then Byte (Auth, 8) = Character'Pos ('a')
           and then Byte (Auth, 9) = Character'Pos ('s')
           and then Byte (Auth, 10) = Character'Pos ('s');
         GNAT.Sockets.Send_Socket (Peer, Auth_Reply, Sent_Last);

         Receive_Exact (Peer, Connect_Req, Last);
         Local_CONNECT :=
           Last = Connect_Req'Last
           and then Byte (Connect_Req, 0) = 16#05#
           and then Byte (Connect_Req, 1) = 16#01#
           and then Byte (Connect_Req, 2) = 16#00#
           and then Byte (Connect_Req, 3) = 16#03#
           and then Byte (Connect_Req, 4) = 11
           and then Contains_ASCII (Connect_Req, 18, "example.com")
           and then Byte (Connect_Req, 16) = 16#01#
           and then Byte (Connect_Req, 17) = 16#BB#;
         Local_Leak :=
           Contains_ASCII (Greeting, 3, "Git-Protocol:")
           or else Contains_ASCII (Auth, 11, "Git-Protocol:")
           or else Contains_ASCII (Connect_Req, 18, "Git-Protocol:")
           or else Contains_ASCII (Connect_Req, 18, "Authorization:")
           or else Contains_ASCII (Connect_Req, 18, "Cookie:")
           or else Contains_ASCII (Connect_Req, 18, "GET ")
           or else Contains_ASCII (Connect_Req, 18, "POST ");

         GNAT.Sockets.Send_Socket (Peer, Connect_Reply, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         select
            accept Finished
              (Saw_Greeting     : out Boolean;
               Saw_Auth         : out Boolean;
               Saw_CONNECT      : out Boolean;
               Leaked_Origin    : out Boolean) do
               Saw_Greeting := Local_Greeting;
               Saw_Auth := Local_Auth;
               Saw_CONNECT := Local_CONNECT;
               Leaked_Origin := Local_Leak;
            end Finished;
         or
            delay 0.2;
         end select;
      end SOCKS_Proxy;

      Server        : SOCKS_Proxy;
      Port          : Http_Client.URI.TCP_Port;
      Base_Proxy    : Http_Client.Proxies.Proxy_Config;
      Proxy         : Http_Client.Proxies.Proxy_Config;
      URI           : Http_Client.URI.URI_Reference;
      Headers       : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request       : Http_Client.Requests.Request;
      Stream        : Http_Client.Response_Streams.Streaming_Response;
      Options       : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status        : Http_Client.Errors.Result_Status;
      Saw_Greeting  : Boolean;
      Saw_Auth      : Boolean;
      Saw_CONNECT   : Boolean;
      Leaked_Origin : Boolean;
   begin
      Server.Ready (Port);
      Base_Proxy := Http_Client.Proxies.SOCKS5 ("127.0.0.1", Port);
      Assert
        (Http_Client.Proxies.With_SOCKS5_Username_Password
           (Base_Proxy, "user", "pass", Proxy) = Http_Client.Errors.Ok,
         "streaming SOCKS tunnel test credentials should configure");
      Options.Proxy := Proxy;
      Apply_Test_Timeouts (Options);
      Options.TLS.Disable_Certificate_Verification := True;

      Assert_Parse_Ok
        ("https://example.com/repo.git/info/refs?service=git-upload-pack",
         URI,
         "HTTPS Git URI for SOCKS handshake-shape test should parse");
      Assert
        (Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2")
         = Http_Client.Errors.Ok,
         "Git-Protocol header should be valid");
      Assert
        (Http_Client.Headers.Set (Headers, "Authorization", "Bearer origin")
         = Http_Client.Errors.Ok,
         "origin Authorization header should be valid");
      Assert
        (Http_Client.Headers.Set (Headers, "Cookie", "sid=origin")
         = Http_Client.Errors.Ok,
         "origin Cookie header should be valid");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "HTTPS Git request for SOCKS handshake-shape test should construct");

      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Stream  => Stream,
         Options => Options);
      select
         Server.Finished (Saw_Greeting, Saw_Auth, Saw_CONNECT, Leaked_Origin);
      or
         delay 0.5;
         Assert
           (False,
            "streaming SOCKS proxy did not publish handshake observation");
      end select;

      Assert
        (Status = Http_Client.Errors.SOCKS_Reply_Connection_Refused
         or else Status = Http_Client.Errors.SOCKS_Connect_Failed,
         "SOCKS CONNECT failure reply should fail before origin TLS while " &
         "still allowing SOCKS request-shape validation");
      Assert
        (Saw_Greeting,
         "SOCKS handshake should offer only the configured username/password method");
      Assert
        (Saw_Auth,
         "SOCKS credentials should be serialized only in SOCKS authentication");
      Assert
        (Saw_CONNECT,
         "SOCKS CONNECT request should target the HTTPS origin authority");
      Assert
        (not Leaked_Origin,
         "SOCKS negotiation must not leak origin request headers or methods");
      Assert
        (Http_Client.Response_Streams.Close (Stream) = Http_Client.Errors.Ok,
         "stream close after SOCKS request-shape failure should be safe");
      abort Server;
   exception
      when others =>
         abort Server;
         raise;
   end Test_Response_Stream_HTTPS_SOCKS_Tunnel_Handshake_Shape;

   procedure Test_Connection_Pool_Fresh_Token_And_Stream_Completion

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
   begin
      Status := Http_Client.URI.Parse ("http://example.test/fresh", URI);
      Assert (Status = Http_Client.Errors.Ok, "fresh-token URI should parse");
      Key := Http_Client.Connection_Pools.Key_For (URI);

      Options.Enabled := True;
      Options.Max_Total_Idle_Connections := 2;
      Options.Max_Idle_Connections_Per_Key := 2;
      Options.Max_Requests_Per_Connection := 2;
      Http_Client.Connection_Pools.Initialize (Pool, Options);

      Assert
        (Http_Client.Connection_Pools.Begin_Fresh (Pool, Key, Token)
         = Http_Client.Errors.Ok,
         "fresh checked-out token should be creatable for a newly opened connection");
      Assert
        (Http_Client.Connection_Pools.Is_Valid (Token),
         "fresh checked-out token should be valid while the response is in flight");
      Assert
        (Http_Client.Connection_Pools.Check_In (Pool, Token, Reusable => True)
         = Http_Client.Errors.Ok,
         "fresh checked-out token should check in after complete response consumption");
      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool, Key) = 1,
         "fresh completed connection should become idle when request count limit permits it");

      declare
         Reused : Boolean := False;
      begin
         Assert
           (Http_Client.Connection_Pools.Check_Out (Pool, Key, Token, Reused)
            = Http_Client.Errors.Ok,
            "retained fresh connection should check out for a second request");
         Assert (Reused, "retained fresh connection should be reused");
         Assert
           (Http_Client.Connection_Pools.Check_In
              (Pool, Token, Reusable => True)
            = Http_Client.Errors.Ok,
            "max-request-limited reused token should be discarded without error");
      end;

      Assert
        (Http_Client.Connection_Pools.Idle_Count (Pool, Key) = 0,
         "connection reaching max request count should not return to idle state");

      Assert
        (Http_Client.Connection_Pools.Stream_Completion_Permits_Check_In
           (Reached_End_Of_Body        => True,
            Closed_Early               => False,
            Failed                     => False,
            Connection_Close_Delimited => False,
            Framing_Permits_Reuse      => True),
         "fully consumed framed stream should permit pooled checkin");
      Assert
        (not Http_Client.Connection_Pools.Stream_Completion_Permits_Check_In
               (Reached_End_Of_Body        => False,
                Closed_Early               => True,
                Failed                     => False,
                Connection_Close_Delimited => False,
                Framing_Permits_Reuse      => True),
         "early-closed stream must not permit pooled checkin");
      Assert
        (not Http_Client.Connection_Pools.Stream_Completion_Permits_Check_In
               (Reached_End_Of_Body        => True,
                Closed_Early               => False,
                Failed                     => True,
                Connection_Close_Delimited => False,
                Framing_Permits_Reuse      => True),
         "failed stream must not permit pooled checkin");
      Assert
        (not Http_Client.Connection_Pools.Stream_Completion_Permits_Check_In
               (Reached_End_Of_Body        => True,
                Closed_Early               => False,
                Failed                     => False,
                Connection_Close_Delimited => True,
                Framing_Permits_Reuse      => True),
         "close-delimited stream must not permit pooled checkin");
   end Test_Connection_Pool_Fresh_Token_And_Stream_Completion;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Streaming");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Response_Stream_Lifecycle_Default_Close'Access,
         "Test_Response_Stream_Lifecycle_Default_Close");
      Register_Routine
        (T,
         Test_Response_Stream_Content_Length_Fragmented_Reads'Access,
         "Test_Response_Stream_Content_Length_Fragmented_Reads");
      Register_Routine
        (T,
         Test_Response_Stream_HEAD_Reports_Immediate_EOF'Access,
         "Test_Response_Stream_HEAD_Reports_Immediate_EOF");
      Register_Routine
        (T,
         Test_Response_Stream_Accepts_Chunked_Transfer_Encoding'Access,
         "Test_Response_Stream_Accepts_Chunked_Transfer_Encoding");
      Register_Routine
        (T,
         Test_Response_Stream_Git_Pkt_Line_Chunked_Binary'Access,
         "Test_Response_Stream_Git_Pkt_Line_Chunked_Binary");
      Register_Routine
        (T,
         Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer'Access,
         "Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer");
      Register_Routine
        (T,
         Test_Response_Stream_Chunked_Trailer_Line_Limit'Access,
         "Test_Response_Stream_Chunked_Trailer_Line_Limit");
      Register_Routine
        (T,
         Test_Response_Stream_Chunked_Trailer_Total_Limit'Access,
         "Test_Response_Stream_Chunked_Trailer_Total_Limit");
      Register_Routine
        (T,
         Test_Response_Stream_Expect_Chunked_Final_Response_Does_Not_Upload'Access,
         "Test_Response_Stream_Expect_Chunked_Final_Response_Does_Not_Upload");
      Register_Routine
        (T,
         Test_Response_Stream_Content_Length_Zero_Immediate_EOF'Access,
         "Test_Response_Stream_Content_Length_Zero_Immediate_EOF");
      Register_Routine
        (T,
         Test_Response_Stream_Close_Delimited_Reads_To_EOF'Access,
         "Test_Response_Stream_Close_Delimited_Reads_To_EOF");
      Register_Routine
        (T,
         Test_Response_Stream_Early_Close_Read_After_Close'Access,
         "Test_Response_Stream_Early_Close_Read_After_Close");
      Register_Routine
        (T,
         Test_Response_Stream_HTTPS_Proxy_CONNECT_Attempts_Proxy'Access,
         "Test_Response_Stream_HTTPS_Proxy_CONNECT_Attempts_Proxy");
      Register_Routine
        (T,
         Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT'Access,
         "Test_Response_Stream_HTTPS_Proxy_CONNECT_Sends_Only_CONNECT");
      Register_Routine
        (T,
         Test_Response_Stream_HTTPS_SOCKS_Proxy_Attempts_Proxy'Access,
         "Test_Response_Stream_HTTPS_SOCKS_Proxy_Attempts_Proxy");
      Register_Routine
        (T,
         Test_Response_Stream_HTTPS_SOCKS_Tunnel_Handshake_Shape'Access,
         "Test_Response_Stream_HTTPS_SOCKS_Tunnel_Handshake_Shape");
      Register_Routine
        (T,
         Test_Connection_Pool_Fresh_Token_And_Stream_Completion'Access,
         "Test_Connection_Pool_Fresh_Token_And_Stream_Completion");
   end Register_Tests;

end Http_Client.Response_Streams.Tests;
