with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Auth.Digest;
with Http_Client.Alt_Svc;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Clients;
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

package body Http_Client.Auth.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
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

   procedure Test_Auth_Credential_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Short_Buffer : String (1 .. 4) := [others => '?'];
   begin
      Assert
        (Http_Client.Auth.Is_Valid_Basic_Credentials ("user", "pass"),
         "ordinary Basic credentials should validate");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials ("", "pass"),
         "empty Basic username should be rejected by the Basic-auth policy");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials ("user:name", "pass"),
         "colon in Basic username should be rejected because Basic uses colon as separator");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user" & Character'Val (13), "pass"),
         "CR in Basic username should be rejected");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user", "pass" & Character'Val (10)),
         "LF in Basic password should be rejected");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user" & Character'Val (0), "pass"),
         "NUL in Basic username should be rejected");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user" & Character'Val (128), "pass"),
         "C1 control in Basic username should be rejected");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user", "pass" & Character'Val (127)),
         "DEL in Basic password should be rejected");
      Assert
        (not Http_Client.Auth.Is_Valid_Basic_Credentials
               ("user", "pass" & Character'Val (159)),
         "C1 control in Basic password should be rejected");

      Assert
        (Http_Client.Auth.Basic_Authorization ("", "pass", Short_Buffer)
         = Http_Client.Errors.Invalid_Credentials,
         "bounded Basic helper should report invalid credentials as a status");
      Assert
        (Http_Client.Auth.Basic_Authorization ("user", "pass", Short_Buffer)
         = Http_Client.Errors.Invalid_Header,
         "bounded Basic helper should reject an undersized output buffer with a status");
   end Test_Auth_Credential_Validation;

   procedure Test_Auth_Request_Integration_And_Clear

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      URI       : Http_Client.URI.URI_Reference;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request   : Http_Client.Requests.Request;
      With_Auth : Http_Client.Requests.Request;
      Cleared   : Http_Client.Requests.Request;
      Output    : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert_Parse_Ok
        ("http://example.com/protected",
         URI,
         "auth request integration URI should parse");
      Assert
        (Http_Client.Headers.Set (Headers, "Authorization", "Bearer old")
         = Http_Client.Errors.Ok,
         "existing Authorization should be set up for replacement test");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => URI,
            Item    => Request,
            Headers => Headers)
         = Http_Client.Errors.Ok,
         "request with existing Authorization should construct");

      Assert
        (Http_Client.Auth.Set_Basic_Authorization
           (Request, "user", "pass", With_Auth)
         = Http_Client.Errors.Ok,
         "Set_Basic_Authorization should return a request with Basic credentials");
      Assert
        (Http_Client.Headers.Count
           (Http_Client.Requests.Headers (With_Auth), "Authorization")
         = 1,
         "Set_Basic_Authorization should replace duplicate origin credentials deterministically");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Requests.Headers (With_Auth), "Authorization")
         = "Basic dXNlcjpwYXNz",
         "Set_Basic_Authorization should store the expected Basic field value");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Requests.Headers (Request), "Authorization")
         = "Bearer old",
         "Set_Basic_Authorization must not mutate the input request");

      Assert
        (Http_Client.HTTP1.Serialize_Request (With_Auth, Output)
         = Http_Client.Errors.Ok,
         "request with Basic Authorization should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Output)
         = "GET /protected HTTP/1.1"
           & CRLF
           & "Authorization: Basic dXNlcjpwYXNz"
           & CRLF
           & "Host: example.com"
           & CRLF
           & CRLF,
         "serialized request should contain exact Basic Authorization bytes");

      Assert
        (Http_Client.Auth.Clear_Authorization (With_Auth, Cleared)
         = Http_Client.Errors.Ok,
         "Clear_Authorization should return a request without origin credentials");
      Assert
        (not Http_Client.Headers.Contains
               (Http_Client.Requests.Headers (Cleared), "Authorization"),
         "cleared request should not contain Authorization");
      Assert
        (Http_Client.Auth.Set_Basic_Authorization
           (Request, "bad:name", "pass", With_Auth)
         = Http_Client.Errors.Invalid_Credentials,
         "request auth helper should reject invalid credentials with a status");
      Assert
        (Http_Client.Auth.Set_Basic_Authorization
           (Http_Client.Requests.Default_Request, "user", "pass", With_Auth)
         = Http_Client.Errors.Invalid_Request,
         "request auth helper should reject invalid request input with a status");
   end Test_Auth_Request_Integration_And_Clear;

   procedure Test_Auth_Digest_Parse_And_MD5_Vector

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Parsed : Http_Client.Auth.Digest.Challenge;
      Header : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""testrealm@host.com"", "
            & "qop=""auth,auth-int"", "
            & "nonce=""dcd98b7102dd2f0e8b11d0f600bfb0c093"", "
            & "opaque=""5ccc069c403ebaf9f0171e9517f40e41""",
            Parsed)
         = Http_Client.Errors.Ok,
         "Digest challenge with quoted qop list should parse");
      Assert (Parsed.Valid, "parsed Digest challenge should be marked valid");
      Assert (Parsed.Offers_Auth, "Digest challenge should offer qop auth");
      Assert
        (Parsed.Offers_Auth_Int,
         "Digest challenge should remember auth-int offer");
      Assert
        (Http_Client.Auth.Digest.CNonce_From_Octets
           (Character'Val (0) & Character'Val (16) & Character'Val (255))
         = "0010ff",
         "Digest deterministic cnonce octet helper should emit lowercase hex");

      Assert
        (Http_Client.Auth.Digest.Generate_Response
           (Parsed,
            "Mufasa",
            "Circle Of Life",
            "GET",
            "/dir/index.html",
            1,
            "0a4f113b",
            Header,
            Allow_Legacy_MD5 => True)
         = Http_Client.Errors.Ok,
         "Digest MD5 RFC vector should generate when legacy MD5 is explicitly allowed");
      Assert
        (Ada.Strings.Unbounded.To_String (Header)
         = "Digest username=""Mufasa"", realm=""testrealm@host.com"", "
           & "nonce=""dcd98b7102dd2f0e8b11d0f600bfb0c093"", "
           & "uri=""/dir/index.html"", algorithm=MD5, "
           & "response=""6629fae49393a05397450978507c4ef1"", "
           & "qop=auth, nc=00000001, cnonce=""0a4f113b"", "
           & "opaque=""5ccc069c403ebaf9f0171e9517f40e41""",
         "Digest MD5 vector should match the RFC response hash exactly");
      Assert
        (Http_Client.Auth.Digest.Generate_Response
           (Parsed,
            "Mufasa",
            "Circle Of Life",
            "GET",
            "/dir/index.html",
            1,
            "0a4f113b",
            Header)
         = Http_Client.Errors.Digest_Algorithm_Unsupported,
         "legacy MD5 Digest should be rejected unless caller explicitly allows it");
   end Test_Auth_Digest_Parse_And_MD5_Vector;

   procedure Test_Auth_Digest_Malformed_Unsupported_And_SHA256

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Parsed     : Http_Client.Auth.Digest.Challenge;
      Header     : Ada.Strings.Unbounded.Unbounded_String;
      Long_Value : constant String (1 .. 2_100) := [others => 'x'];
   begin
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", algorithm=SHA-256, qop=auth",
            Parsed)
         = Http_Client.Errors.Ok,
         "Digest SHA-256 challenge should parse");
      Assert
        (Http_Client.Auth.Digest.Generate_Response
           (Parsed, "user", "pass", "GET", "/path?x=1", 2, "abcdef", Header)
         = Http_Client.Errors.Ok,
         "Digest SHA-256 response should generate without legacy MD5 opt-in");
      Assert
        (Ada.Strings.Unbounded.To_String (Header)'Length > 0
         and then
           Ada.Strings.Fixed.Index
             (Ada.Strings.Unbounded.To_String (Header), "algorithm=SHA-256")
           > 0,
         "Digest SHA-256 header should disclose selected algorithm but not secrets");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", realm=""again"", nonce=""n""", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "duplicate critical Digest parameters should be rejected");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "unterminated Digest quoted string should be rejected");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"" nonce=""n""", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "Digest parameters without a comma separator should be rejected");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", algorithm=SHA-512", Parsed)
         = Http_Client.Errors.Digest_Algorithm_Unsupported,
         "unsupported Digest algorithm should be rejected deterministically");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", qop=auth-int", Parsed)
         = Http_Client.Errors.Digest_QOP_Unsupported,
         "auth-int-only Digest challenge should be rejected until entity hashing is implemented");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", stale=maybe", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "Digest stale parameter should be restricted to true or false");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"",", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "Digest challenge with trailing comma should be rejected as malformed");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""" & Long_Value & """", Parsed)
         = Http_Client.Errors.Authentication_Challenge_Malformed,
         "overlong Digest parameter values should be rejected deterministically");
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge
           ("Digest realm=""r"", nonce=""n"", algorithm=SHA-256", Parsed)
         = Http_Client.Errors.Ok,
         "Digest challenge without qop should parse for legacy servers");
      Assert
        (Http_Client.Auth.Digest.Generate_Response
           (Parsed, "user", "pass", "GET", "/path", 1, "", Header)
         = Http_Client.Errors.Ok,
         "Digest response without qop and non-sess algorithm should not require cnonce");
      Assert
        (Ada.Strings.Fixed.Index
           (Ada.Strings.Unbounded.To_String (Header), "cnonce=")
         = 0,
         "Digest response without qop and non-sess algorithm should not emit cnonce");
      Assert
        (Http_Client.Auth.Digest.Nonce_Count_Text (16) = "00000010",
         "Digest nonce-count formatting should be eight lowercase hex digits");
   end Test_Auth_Digest_Malformed_Unsupported_And_SHA256;

   procedure Test_High_Level_Client_Request_Basic_Authorization_Is_Explicit

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Auth_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Auth_Server;

      task body Auth_Server is
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
            Response : constant String :=
              "HTTP/1.1 200 OK"
              & CRLF
              & "Content-Length: 2"
              & CRLF
              & CRLF
              & "OK";
            Raw      :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response'Length));
            Last     : Stream_Element_Offset;
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

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Auth_Server;

      Server        : Auth_Server;
      Port          : Http_Client.URI.TCP_Port;
      Port_Text     : Unbounded_String;
      URI           : Http_Client.URI.URI_Reference;
      Request       : Http_Client.Requests.Request;
      Auth_Request  : Http_Client.Requests.Request;
      Client        : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Expected      : constant String :=
        Http_Client.Auth.Basic_Authorization_Value ("user", "pass");
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert
        (Http_Client.URI.Parse
           ("http://127.0.0.1:" & To_String (Port_Text) & "/auth", URI)
         = Http_Client.Errors.Ok,
         "explicit Basic-auth high-level request URI should parse");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "explicit Basic-auth base request should construct");

      Status :=
        Http_Client.Auth.Set_Basic_Authorization
          (Request  => Request,
           Username => "user",
           Password => "pass",
           Result   => Auth_Request);
      Assert
        (Status = Http_Client.Errors.Ok,
         "request-specific Basic authorization helper should succeed");

      Status := Http_Client.Clients.Execute (Client, Auth_Request, Result);
      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level client should execute explicitly authorized request");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Authorization: " & Expected & CRLF) > 0,
         "high-level client should send request-specific Basic Authorization " &
         " only when explicitly configured on the request");
   end Test_High_Level_Client_Request_Basic_Authorization_Is_Explicit;

   procedure Test_Cache_Authenticated_Store_Requires_Vary_Authorization

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Cache     : Http_Client.Cache.Cache_Store;
      Config    : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
      Headers_A : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Headers_B : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_A     : Http_Client.Requests.Request;
      Req_B     : Http_Client.Requests.Request;
      Res       : Http_Client.Responses.Response;
      Hit       : Http_Client.Responses.Response;
      Meta      : Http_Client.Cache.Cache_Metadata;
   begin
      Config.Enabled := True;
      Config.Allow_Authenticated_Store := True;
      Http_Client.Cache.Initialize (Cache, Config);
      Assert
        (Http_Client.Headers.Set (Headers_A, "Authorization", "Basic aaa")
         = Http_Client.Errors.Ok,
         "authorization A should set");
      Assert
        (Http_Client.Headers.Set (Headers_B, "Authorization", "Basic bbb")
         = Http_Client.Errors.Ok,
         "authorization B should set");
      Build_Cache_Request ("http://example.com/auth-cache", Req_A, Headers_A);
      Build_Cache_Request ("http://example.com/auth-cache", Req_B, Headers_B);

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: public, max-age=60"
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
        (Http_Client.Cache.Store (Cache, Req_A, Res)
         = Http_Client.Errors.Cache_Disabled,
         "authenticated response storage should require Vary: Authorization");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: public, max-age=60"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Authorization"
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
        (Http_Client.Cache.Store (Cache, Req_A, Res) = Http_Client.Errors.Ok,
         "authenticated response with explicit Vary: Authorization should store when enabled");
      Assert
        (Http_Client.Cache.Lookup (Cache, Req_A, Hit, Meta)
         = Http_Client.Errors.Ok,
         "same Authorization value should hit authenticated cache entry");
      Assert
        (Http_Client.Cache.Lookup (Cache, Req_B, Hit, Meta)
         = Http_Client.Errors.Cache_Miss,
         "different Authorization value must miss authenticated cache entry");
   end Test_Cache_Authenticated_Store_Requires_Vary_Authorization;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Auth");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Auth_Credential_Validation'Access,
         "Test_Auth_Credential_Validation");
      Register_Routine
        (T,
         Test_Auth_Request_Integration_And_Clear'Access,
         "Test_Auth_Request_Integration_And_Clear");
      Register_Routine
        (T,
         Test_Auth_Digest_Parse_And_MD5_Vector'Access,
         "Test_Auth_Digest_Parse_And_MD5_Vector");
      Register_Routine
        (T,
         Test_Auth_Digest_Malformed_Unsupported_And_SHA256'Access,
         "Test_Auth_Digest_Malformed_Unsupported_And_SHA256");
      Register_Routine
        (T,
         Test_High_Level_Client_Request_Basic_Authorization_Is_Explicit'Access,
         "Test_High_Level_Client_Request_Basic_Authorization_Is_Explicit");
      Register_Routine
        (T,
         Test_Cache_Authenticated_Store_Requires_Vary_Authorization'Access,
         "Test_Cache_Authenticated_Store_Requires_Vary_Authorization");
   end Register_Tests;

end Http_Client.Auth.Tests;
