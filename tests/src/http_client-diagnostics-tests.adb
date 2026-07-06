with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Alt_Svc;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Clients;
with Http_Client.Cookies;
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
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Diagnostics.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
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

   procedure Test_Diagnostics_Default_Redaction

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Policy : Http_Client.Diagnostics.Redaction_Policy :=
        Http_Client.Diagnostics.Default_Redaction_Policy;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "Authorization"),
         "Authorization should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header
           (Policy, "proxy-authorization"),
         "Proxy-Authorization should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "Cookie"),
         "Cookie should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "Set-Cookie"),
         "Set-Cookie should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "X-Api-Key"),
         "common API-key headers should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "X-Auth-Token"),
         "common token headers should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header (Policy, "X-Goog-Api-Key"),
         "vendor API-key headers should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Is_Redacted_Header
           (Policy, "X-Amz-Security-Token"),
         "temporary cloud credential headers should be redacted by default");
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "Authorization", "Basic dXNlcjpwYXNz")
         = "<redacted>",
         "default diagnostics must not expose authorization values");
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "X-Trace", "visible")
         = "",
         "header values should be structural-only unless explicitly enabled");

      Policy.Allow_Header_Values := True;
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "X-Trace", "visible")
         = "visible",
         "non-sensitive header values may be enabled explicitly");

      Status :=
        Http_Client.Diagnostics.Add_Redacted_Header
          (Policy, "X-Private-Diagnostic");
      Assert
        (Status = Http_Client.Errors.Ok,
         "adding a redacted header should succeed");
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "X-Private-Diagnostic", "secret")
         = "<redacted>",
         "caller redaction extensions should override verbose header values");

      Assert
        (Http_Client.Diagnostics.Safe_Body_Preview (Policy, "body-secret")
         = "",
         "body previews should be disabled by default even when header values are enabled");
      Policy.Allow_Body_Previews := True;
      Policy.Max_Body_Preview_Bytes := 4;
      Assert
        (Http_Client.Diagnostics.Safe_Body_Preview (Policy, "body-secret")
         = "body",
         "explicit body previews should be bounded by the configured cap");

      Policy.Unsafe_Disable_Redaction := True;
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "Authorization", "unsafe")
         = "unsafe",
         "only the unmistakably unsafe option should disable redaction");
   end Test_Diagnostics_Default_Redaction;

   procedure Test_Diagnostics_Context_Metrics_And_Callbacks

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Event   : Http_Client.Diagnostics.Diagnostic_Event;
      Snap    : Http_Client.Diagnostics.Metrics_Snapshot;
      Timing  : Http_Client.Diagnostics.Timing_Snapshot;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Diagnostic_Callback_Count := 0;
      Diagnostic_Fail_Next := False;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Event :=
        (Kind       => Http_Client.Diagnostics.Request_Start,
         Request_ID => 1,
         others     => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok, "request-start event should emit");

      Event :=
        (Kind                 => Http_Client.Diagnostics.Request_Finish,
         Request_ID           => 1,
         Response_Byte_Count  => 12,
         Result               => Http_Client.Errors.Ok,
         Elapsed_Milliseconds => 37,
         others               => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok, "request-finish event should emit");

      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Assert
        (Diagnostic_Callback_Count = 2,
         "observer should receive emitted events");
      Assert
        (Snap.Requests_Started = 1, "metrics should count request starts");
      Assert
        (Snap.Requests_Completed = 1, "metrics should count request finishes");
      Timing := Http_Client.Diagnostics.Timing (Context);
      Assert
        (Timing.Request_Finish_Count = 1,
         "timing metrics should count completed request events");
      Assert
        (Timing.Request_Total_Milliseconds = 37,
         "timing metrics should aggregate request elapsed milliseconds");
      Assert
        (Http_Client.Diagnostics.Average_Request_Milliseconds (Timing) = 37,
         "request timing average should divide totals by completed count");

      Event :=
        (Kind                 => Http_Client.Diagnostics.TLS_Handshake_Finished,
         Request_ID           => 1,
         Connection_ID        => 1,
         Result               => Http_Client.Errors.Ok,
         Elapsed_Milliseconds => 11,
         others               => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok, "TLS timing event should emit");
      Timing := Http_Client.Diagnostics.Timing (Context);
      Assert
        (Timing.TLS_Handshake_Count = 1,
         "timing metrics should count TLS handshake completions");
      Assert
        (Timing.TLS_Handshake_Total_Milliseconds = 11,
         "timing metrics should aggregate TLS handshake elapsed milliseconds");
      Assert
        (Http_Client.Diagnostics.Average_TLS_Handshake_Milliseconds (Timing) = 11,
         "TLS timing average should divide totals by handshake count");

      Event :=
        (Kind               => Http_Client.Diagnostics.Request_Body_Progress,
         Request_ID         => 1,
         Request_Byte_Count => 5,
         others             => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "request body metrics event should emit");

      Event :=
        (Kind                =>
           Http_Client.Diagnostics.Response_Headers_Received,
         Request_ID          => 1,
         Response_Byte_Count => 17,
         others              => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "response header metrics event should emit");

      Event :=
        (Kind                => Http_Client.Diagnostics.Response_Body_Progress,
         Request_ID          => 1,
         Response_Byte_Count => 7,
         others              => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "response body metrics event should emit");

      Event :=
        (Kind               => Http_Client.Diagnostics.Upload_Producer_Event,
         Request_ID         => 1,
         Request_Byte_Count => 5,
         Result             => Http_Client.Errors.Ok,
         others             => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok, "upload producer event should emit");

      Event :=
        (Kind       => Http_Client.Diagnostics.Multipart_Event,
         Request_ID => 1,
         Result     => Http_Client.Errors.Ok,
         Message    =>
           Http_Client.Diagnostics.To_Text ("multipart structure prepared"),
         others     => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "multipart structural event should emit");

      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Assert
        (Snap.Bytes_Sent = 5,
         "metrics should count sent request-body bytes without double-counting producer events");
      Assert
        (Snap.Bytes_Received = 24,
         "metrics should count header and body bytes once");
      Assert
        (Snap.Upload_Producer_Events = 1,
         "metrics should count upload producer structural events");
      Assert
        (Snap.Multipart_Events = 1,
         "metrics should count multipart structural events");

      Event :=
        (Kind         => Http_Client.Diagnostics.Request_Headers_Sent,
         Request_ID   => 1,
         Header_Name  => Http_Client.Diagnostics.To_Text ("Authorization"),
         Header_Value => Http_Client.Diagnostics.To_Text ("Basic secret"),
         others       => <>);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok, "redacted header event should emit");
      Assert
        (Http_Client.Diagnostics.Last_Callback_Status (Context)
         = Http_Client.Errors.Ok,
         "successful callbacks should leave last callback status as Ok");
      Assert
        (Http_Client.Diagnostics.Text (Diagnostic_Last_Event.Header_Value)
         = "<redacted>",
         "observer must receive redacted sensitive header values by default");
      Assert
        (Diagnostic_Last_Event.Header_Redacted,
         "observer should be told that a header value was redacted");

      Diagnostic_Fail_Next := True;
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "default callback failure policy should isolate diagnostics");
      Assert
        (Http_Client.Diagnostics.Last_Callback_Status (Context)
         = Http_Client.Errors.Internal_Error,
         "ignored callback failures should still be observable for tests");

      Http_Client.Diagnostics.Set_Callback_Failure_Policy
        (Context, Http_Client.Diagnostics.Abort_On_Callback_Failure);
      Diagnostic_Fail_Next := True;
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Internal_Error,
         "abort callback policy should convert observer failure into a status");
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "a later successful callback should be allowed after an abort-policy failure");
      Assert
        (Http_Client.Diagnostics.Last_Callback_Status (Context)
         = Http_Client.Errors.Ok,
         "later successful callbacks should reset the last callback failure status");

      Http_Client.Diagnostics.Reset_Metrics (Context);
      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Timing := Http_Client.Diagnostics.Timing (Context);
      Assert
        (Snap.Requests_Started = 0, "metrics reset should clear counters");
      Assert
        (Timing.Request_Finish_Count = 0,
         "metrics reset should clear timing counts");
      Assert
        (Timing.TLS_Handshake_Total_Milliseconds = 0,
         "metrics reset should clear timing totals");
      Assert
        (Http_Client.Diagnostics.Average_Request_Milliseconds (Timing) = 0,
         "empty request timing average should be zero");
      Assert
        (Http_Client.Diagnostics.Average_TLS_Handshake_Milliseconds (Timing) = 0,
         "empty TLS timing average should be zero");

      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => null,
         Clock    => Diagnostic_Test_Time'Unrestricted_Access);
      Assert
        (Http_Client.Diagnostics.Now (Context)
         = Ada.Calendar.Time_Of (2026, 5, 13, 12.0),
         "diagnostics should use an injected test clock when configured");
      Assert
        (Http_Client.Diagnostics.Elapsed_Milliseconds
           (Context,
            Ada.Calendar.Time_Of (2026, 5, 13, 12.0),
            Ada.Calendar.Time_Of (2026, 5, 13, 13.25))
         = 1_250,
         "elapsed milliseconds should be deterministic and not require sleeps");
   end Test_Diagnostics_Context_Metrics_And_Callbacks;

   procedure Test_Diagnostics_Disabled_And_Client_Defaults

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Context        : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Event          : Http_Client.Diagnostics.Diagnostic_Event :=
        (Kind => Http_Client.Diagnostics.Request_Start, others => <>);
      Options        : constant Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Config         : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Stream_Options :
        constant Http_Client.Response_Streams.Streaming_Options :=
          Http_Client.Response_Streams.Default_Streaming_Options;
      Status         : Http_Client.Errors.Result_Status;
   begin
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => False,
         Observer => Capture_Diagnostic'Unrestricted_Access);
      Status := Http_Client.Diagnostics.Emit (Context, Event);
      Assert
        (Status = Http_Client.Errors.Ok,
         "disabled diagnostics should be a no-op");
      Assert
        (Diagnostic_Callback_Count = 0,
         "disabled diagnostics must not call observers");
      Assert
        (Options.Diagnostics = null,
         "low-level diagnostics should be disabled by default");
      Assert
        (Config.Execution.Diagnostics = null,
         "high-level client configuration should not attach diagnostics by default");
      Assert
        (Stream_Options.Diagnostics = null,
         "streaming response diagnostics should be disabled by default");
      Assert
        (Http_Client.Diagnostics.Next_Request_ID (Context) = 1,
         "fresh diagnostics contexts should allocate deterministic request ids");
      Assert
        (Http_Client.Diagnostics.Next_Connection_ID (Context) = 1,
         "fresh diagnostics contexts should allocate deterministic connection ids");
   end Test_Diagnostics_Disabled_And_Client_Defaults;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Diagnostics");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Diagnostics_Default_Redaction'Access,
         "Test_Diagnostics_Default_Redaction");
      Register_Routine
        (T,
         Test_Diagnostics_Context_Metrics_And_Callbacks'Access,
         "Test_Diagnostics_Context_Metrics_And_Callbacks");
      Register_Routine
        (T,
         Test_Diagnostics_Disabled_And_Client_Defaults'Access,
         "Test_Diagnostics_Disabled_And_Client_Defaults");
   end Register_Tests;

end Http_Client.Diagnostics.Tests;
