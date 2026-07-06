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
with Http_Client.Responses;
with Http_Client.Status_Test_Helpers;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Retry.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
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

   Diagnostic_Callback_Count      : Natural := 0;
   Diagnostic_Last_Retry_Event    : Http_Client.Diagnostics.Diagnostic_Event;
   Diagnostic_Fail_Next           : Boolean := False;

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status) is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      if Event.Kind = Http_Client.Diagnostics.Retry_Decision then
         Diagnostic_Last_Retry_Event := Event;
      end if;

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

   procedure Test_Retry_Policy_Defaults_And_Methods

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Assert
        (not Options.Enable_Retries,
         "retry options should be disabled by default");

      Assert
        (Options.Maximum_Attempts = 1,
         "default retry options should allow exactly one attempt");

      Assert
        (Http_Client.Retry.Is_Retryable_Method
           (Http_Client.Types.GET, Options),
         "GET should be retryable by method policy");

      Assert
        (Http_Client.Retry.Is_Retryable_Method
           (Http_Client.Types.PUT, Options),
         "PUT should be retryable by method policy");

      Assert
        (not Http_Client.Retry.Is_Retryable_Method
               (Http_Client.Types.POST, Options),
         "POST should not be retryable by default");

      Options.Allow_Non_Idempotent_Retry := True;

      Assert
        (Http_Client.Retry.Is_Retryable_Method
           (Http_Client.Types.POST, Options),
         "POST should become retryable only with explicit non-idempotent opt-in");

      Assert
        (not Http_Client.Retry.Is_Request_Body_Replayable
               (Http_Client.Requests.Default_Request),
         "invalid default request should not be reported as replayable");
   end Test_Retry_Policy_Defaults_And_Methods;

   procedure Test_Retry_Failure_Classification

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.Connection_Failed, Options),
         "connection failure should be retryable when connect retries are enabled");

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.SOCKS_Reply_Network_Unreachable, Options),
         "transient SOCKS network-unreachable reply should follow connect retry policy");

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.Incomplete_Message, Options),
         "incomplete message should be retryable when read retries are enabled");

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.HTTP2_Stream_Refused, Options),
         "HTTP/2 REFUSED_STREAM should be retryable when read retries are enabled");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.HTTP2_Stream_Reset, Options),
         "generic HTTP/2 stream resets should not be retried without REFUSED_STREAM semantics");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Certificate_Verification_Failed, Options),
         "certificate verification failure must not be retried by default");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Hostname_Verification_Failed, Options),
         "hostname verification failure must not be retried by default");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Unsupported_Feature, Options),
         "unsupported features should not be classified as retryable");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Invalid_Request, Options),
         "invalid requests should not be classified as retryable");
   end Test_Retry_Failure_Classification;

   procedure Test_Retry_Backoff_And_Retry_After

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;

   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 4;
      Options.Base_Delay := 100;
      Options.Maximum_Delay := 350;
      Options.Backoff := Http_Client.Retry.Exponential_Delay;

      Assert
        (Http_Client.Retry.Delay_For_Attempt (1, Options) = 100,
         "first retry delay should use base delay");

      Assert
        (Http_Client.Retry.Delay_For_Attempt (2, Options) = 200,
         "second retry delay should double under exponential backoff");

      Assert
        (Http_Client.Retry.Delay_For_Attempt (3, Options) = 350,
         "exponential backoff should be capped by maximum delay");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Status
        (Options,
         "5",
         False,
         "Retry-After should be ignored unless explicitly enabled");

      Options.Respect_Retry_After := True;
      Options.Maximum_Retry_After := 250;

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Delay
        (Options,
         "5",
         250,
         "delta-seconds Retry-After should parse when enabled");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Status
        (Options,
         "Wed, 21 Oct 2015 07:28:00 GMT",
         False,
         "HTTP-date Retry-After is intentionally not accepted yet");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Status
        (Options,
         " 5",
         False,
         "Retry-After parser should reject leading whitespace rather than guessing");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Status
        (Options,
         "5 ",
         False,
         "Retry-After parser should reject trailing whitespace rather than guessing");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Status
        (Options,
         "-1",
         False,
         "Retry-After parser should reject negative values");

      Options.Maximum_Retry_After := 0;
      Options.Maximum_Delay := 0;

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Delay
        (Options,
         "999999999999999999999999",
         Http_Client.Retry.Delay_Milliseconds'Last,
         "oversized Retry-After delta should still be bounded deterministically");

      Http_Client.Status_Test_Helpers.Assert_Retry_After_Delay
        (Options,
         Decimal_Image (Natural'Last) & "9",
         Http_Client.Retry.Delay_Milliseconds'Last,
         "Retry-After parser should saturate Natural overflow before arithmetic wraps");
   end Test_Retry_Backoff_And_Retry_After;

   procedure Test_Retry_Failure_Option_Gates

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;
      Options.Retry_Connect_Failures := False;
      Options.Retry_Read_Failures := False;
      Options.Retry_Write_Failures := False;
      Options.Retry_Timeouts := False;

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Connection_Failed, Options),
         "connect retry option should gate connection failures");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Proxy_Connection_Failed, Options),
         "connect retry option should gate proxy connection failures");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Read_Failed, Options),
         "read retry option should gate read failures");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.HTTP2_Stream_Refused, Options),
         "read retry option should gate HTTP/2 REFUSED_STREAM retries");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Write_Failed, Options),
         "write retry option should gate write failures");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Timeout, Options),
         "timeout retry option should gate timeout failures");

      Options.Retry_Connect_Failures := True;
      Options.Retry_Read_Failures := True;
      Options.Retry_Write_Failures := True;
      Options.Retry_Timeouts := True;

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.DNS_Failed, Options),
         "DNS failures should be treated as connect failures when enabled");

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.End_Of_Stream, Options),
         "end-of-stream should be treated as a retryable read failure when enabled");
   end Test_Retry_Failure_Option_Gates;

   procedure Test_Client_Retry_Disabled_Remains_One_Attempt

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Request : constant Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Result  : Http_Client.Clients.Retry_Result;
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Options.Enable_Retries := False;
      Options.Maximum_Attempts := 3;

      Status :=
        Http_Client.Clients.Execute_Once_With_Retry
          (Request => Request, Result => Result, Retries => Options);

      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "invalid default request should fail before any retry loop");

      Assert
        (Result.Attempts = 1,
         "disabled retry policy should make exactly one attempt");

      Assert
        (not Result.Retries_Exhausted,
         "disabled retry policy should not report retry exhaustion");
   end Test_Client_Retry_Disabled_Remains_One_Attempt;

   procedure Test_Retry_Response_Status_Classification

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Options  : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Response : Http_Client.Responses.Response;
   begin
      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 503 Service Unavailable" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "503 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "5xx response retries should be disabled by default");

      Options.Retry_5xx_Responses := True;
      Assert
        (Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "503 should be retryable when 5xx response retries are enabled");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 501 Not Implemented" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "501 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "501 should not be included in the conservative 5xx retry set");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 429 Too Many Requests" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "429 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "429 should require its own opt-in");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 401 Unauthorized" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "401 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "401 Unauthorized should not be retried as an authentication workflow");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 407 Proxy Authentication Required" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "407 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "407 Proxy Authentication Required should not be retried as an authentication workflow");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 429 Too Many Requests" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "429 response should parse again for explicit opt-in check");

      Options.Retry_429 := True;
      Assert
        (Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "429 should be retryable only after explicit 429 opt-in");
      Assert
        (Http_Client.Retry.Is_Retryable_Status_Code (429, Options),
         "bare 429 status should use the same retry classification");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 425 Too Early" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "425 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "425 should require its own opt-in");

      Options.Retry_425 := True;
      Assert
        (Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "425 should be retryable only after explicit 425 opt-in");
      Assert
        (Http_Client.Retry.Is_Retryable_Status_Code (425, Options),
         "bare 425 status should use the same retry classification");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 408 Request Timeout" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "408 response should parse for retry classification test");
      Assert
        (not Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "408 should require its own opt-in");

      Options.Retry_408 := True;
      Assert
        (Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "408 should be retryable only after explicit 408 opt-in");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 504 Gateway Timeout" & CRLF & CRLF,
            Response) = Http_Client.Errors.Ok,
         "504 response should parse for retry classification test");
      Assert
        (Http_Client.Retry.Is_Retryable_Response (Response, Options),
         "504 should remain in the conservative 5xx retry set");
   end Test_Retry_Response_Status_Classification;

   procedure Test_Retry_Non_Retryable_Security_And_Protocol_Failures

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;
      Options.Retry_Transient_TLS_Failure := True;

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Http_Client.Errors.TLS_Handshake_Failed, Options),
         "transient TLS handshake retry should require explicit opt-in");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.CA_Store_Failed, Options),
         "CA store failure should never be classified as transient retryable");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Proxy_Authentication_Required, Options),
         "proxy authentication required should not be retried by default helpers");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Proxy_Unsupported, Options),
         "unsupported proxy scheme/path should not be retried");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.SOCKS_Authentication_Failed, Options),
         "SOCKS authentication failure should not be retried by default helpers");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.SOCKS_Malformed_Reply, Options),
         "malformed SOCKS replies should not be retried by default helpers");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Decompression_Failed, Options),
         "decompression failure should not be retried by default helpers");

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
               (Http_Client.Errors.Protocol_Error, Options),
         "protocol errors should not be retried by default helpers");
   end Test_Retry_Non_Retryable_Security_And_Protocol_Failures;

   procedure Test_Client_Retry_Exhaustion_Returns_Final_Response

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

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Loopback_Server;

      task body Loopback_Server is
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

         procedure Send_503 is
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
         end Send_503;
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

         for Attempt in 1 .. 2 loop
            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            Drain_Request;
            Send_503;
            GNAT.Sockets.Close_Socket (Peer);
         end loop;

         GNAT.Sockets.Close_Socket (Server);
      end Loopback_Server;

      Server    : Loopback_Server;
      Port      : Http_Client.URI.TCP_Port;
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Result    : Http_Client.Clients.Retry_Result;
      Options   : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Execution : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Context   : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Snap      : Http_Client.Diagnostics.Metrics_Snapshot;
      Status    : Http_Client.Errors.Result_Status;
      Port_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/exhaust",
         URI,
         "retry exhaustion URI");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "retry exhaustion GET request should construct");

      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 2;
      Options.Retry_5xx_Responses := True;
      Options.Base_Delay := 125;
      Options.Maximum_Delay := 125;

      Diagnostic_Callback_Count := 0;
      Diagnostic_Last_Retry_Event := (others => <>);
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access,
         Clock    => Diagnostic_Test_Time'Unrestricted_Access);
      Execution.Diagnostics := Context'Unchecked_Access;

      Status :=
        Http_Client.Clients.Execute_Once_With_Retry
          (Request   => Request,
           Result    => Result,
           Execution => Execution,
           Retries   => Options);

      Assert
        (Status = Http_Client.Errors.Ok,
         "exhausted response-status retry should still return Ok with final response");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 503,
         "exhausted response-status retry should preserve final 503 response");

      Assert
        (Result.Attempts = 2,
         "exhausted retry should report maximum attempts used");

      Assert
        (Result.Retries_Exhausted,
         "final retryable response at the attempt limit should report exhaustion");

      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Assert
        (Snap.Retries_Attempted = 1,
         "retry diagnostics should count only actual retry attempts");
      Assert
        (Diagnostic_Last_Retry_Event.Kind = Http_Client.Diagnostics.Retry_Decision,
         "retry diagnostics should emit a retry decision event");
      Assert
        (Diagnostic_Last_Retry_Event.Retry_Attempt = 1,
         "retry diagnostics should include the completed attempt number");
      Assert
        (Diagnostic_Last_Retry_Event.Status_Code = 503,
         "retry diagnostics should include retryable response status code");
      Assert
        (Diagnostic_Last_Retry_Event.Result = Http_Client.Errors.Ok,
         "retry diagnostics should preserve operation result for response retries");
      Assert
        (Diagnostic_Last_Retry_Event.Elapsed_Milliseconds = 125,
         "retry diagnostics should include planned backoff milliseconds");
      Assert
        (Http_Client.Diagnostics.Text (Diagnostic_Last_Retry_Event.Message)
         = "retrying response status; body replayable",
         "retry diagnostics should include reason and body replayability");
   end Test_Client_Retry_Exhaustion_Returns_Final_Response;

   procedure Test_Client_Retry_Post_503_Not_Retried_By_Default

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
      Result        : Http_Client.Clients.Retry_Result;
      Options       : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
      Port_Text     : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/post-retry",
         URI,
         "POST no-retry URI");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "POST retry request should construct");

      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;
      Options.Retry_5xx_Responses := True;

      Status :=
        Http_Client.Clients.Execute_Once_With_Retry
          (Request => Request, Result => Result, Retries => Options);

      Assert
        (Status = Http_Client.Errors.Ok,
         "POST 503 response should be returned without retry by default");

      Assert
        (Result.Attempts = 1,
         "POST should not retry without explicit non-idempotent opt-in");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 503,
         "POST no-retry result should preserve the 503 response");

      Server.Request_Seen (Captured_Text);

      Assert
        (Length (Captured_Text) > 0,
         "server should have received exactly the first POST attempt");
   end Test_Client_Retry_Post_503_Not_Retried_By_Default;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Retries");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Retry_Policy_Defaults_And_Methods'Access,
         "Test_Retry_Policy_Defaults_And_Methods");
      Register_Routine
        (T,
         Test_Retry_Failure_Classification'Access,
         "Test_Retry_Failure_Classification");
      Register_Routine
        (T,
         Test_Retry_Backoff_And_Retry_After'Access,
         "Test_Retry_Backoff_And_Retry_After");
      Register_Routine
        (T,
         Test_Retry_Failure_Option_Gates'Access,
         "Test_Retry_Failure_Option_Gates");
      Register_Routine
        (T,
         Test_Client_Retry_Disabled_Remains_One_Attempt'Access,
         "Test_Client_Retry_Disabled_Remains_One_Attempt");
      Register_Routine
        (T,
         Test_Retry_Response_Status_Classification'Access,
         "Test_Retry_Response_Status_Classification");
      Register_Routine
        (T,
         Test_Retry_Non_Retryable_Security_And_Protocol_Failures'Access,
         "Test_Retry_Non_Retryable_Security_And_Protocol_Failures");
      Register_Routine
        (T,
         Test_Client_Retry_Exhaustion_Returns_Final_Response'Access,
         "Test_Client_Retry_Exhaustion_Returns_Final_Response");
      Register_Routine
        (T,
         Test_Client_Retry_Post_503_Not_Retried_By_Default'Access,
         "Test_Client_Retry_Post_503_Not_Retried_By_Default");
   end Register_Tests;

end Http_Client.Retry.Tests;
