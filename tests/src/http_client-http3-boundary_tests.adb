with Ada.Calendar;
with Ada.Streams;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Clients;
with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3.Body_Streams;
with Http_Client.HTTP3.Execution;
with Http_Client.HTTP3.QPACK;
with Http_Client.QUIC;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.HTTP3.Boundary_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Diagnostics.Event_Kind;
   use type Http_Client.Diagnostics.Protocol_Version;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Proxies.Proxy_Kind;

   Diagnostic_Callback_Count : Natural := 0;
   Diagnostic_Last_Event     : Http_Client.Diagnostics.Diagnostic_Event;
   Diagnostic_Current_Time   : Ada.Calendar.Time :=
     Ada.Calendar.Time_Of (2026, 5, 13, 12.0);

   function Diagnostic_Test_Time return Ada.Calendar.Time is
   begin
      return Diagnostic_Current_Time;
   end Diagnostic_Test_Time;

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status)
   is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;
      Status := Http_Client.Errors.Ok;
   end Capture_Diagnostic;

   procedure Abort_On_Error_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status)
   is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;

      if Event.Kind = Http_Client.Diagnostics.Error_Event then
         Status := Http_Client.Errors.Cancelled;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Abort_On_Error_Diagnostic;

   procedure Abort_On_QUIC_Failed_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status)
   is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;

      if Event.Kind = Http_Client.Diagnostics.QUIC_Connection_Failed then
         Status := Http_Client.Errors.Cancelled;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Abort_On_QUIC_Failed_Diagnostic;

   procedure Abort_On_HTTP3_Unsupported_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status)
   is
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;
      Diagnostic_Last_Event := Event;

      if Event.Kind = Http_Client.Diagnostics.HTTP3_Execution_Unsupported then
         Status := Http_Client.Errors.Cancelled;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Abort_On_HTTP3_Unsupported_Diagnostic;

   procedure Make_HTTPS_Request
     (Req : out Http_Client.Requests.Request) is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse ("https://example.test/repo.git/info/refs?service=git-upload-pack", URI);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 boundary HTTPS URI should parse");
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.GET,
         URI    => URI,
         Item   => Req);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 boundary request should construct");
   end Make_HTTPS_Request;

   function Forced_No_Backend_Options return Http_Client.HTTP3.HTTP3_Options is
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Required;
      Options.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
      return Options;
   end Forced_No_Backend_Options;

   Backend_Called          : Boolean := False;
   Backend_Last_Host       : Ada.Strings.Unbounded.Unbounded_String;
   Backend_Last_Port       : Natural := 0;
   Backend_Last_Header_Num : Natural := 0;
   Backend_Last_Max_Body   : Natural := 0;

   function Scripted_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced (Request, Options);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Backend_Called := True;
      Backend_Last_Host := Ada.Strings.Unbounded.To_Unbounded_String (Connect_Host);
      Backend_Last_Port := Connect_Port;
      Backend_Last_Header_Num := Http_Client.Headers.Length (Request_Headers);
      Backend_Last_Max_Body := Max_Body_Size;

      Status := Http_Client.Headers.Add (Headers, "content-type", "text/plain");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 203,
         Reason    => "HTTP3",
         Headers   => Headers,
         Body_Text => "h3 backend");
      return Http_Client.Errors.Ok;
   end Scripted_HTTP3_Backend;

   function Oversized_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
   begin
      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Http_Client.Headers.Empty,
         Body_Text => "too large");
      return Http_Client.Errors.Ok;
   end Oversized_HTTP3_Backend;

   function Failing_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
   begin
      Diagnostic_Current_Time := Ada.Calendar.Time_Of (2026, 5, 13, 13.25);
      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 599,
         Reason    => "backend failure body must be cleared",
         Headers   => Http_Client.Headers.Empty,
         Body_Text => "must not escape");
      return Http_Client.Errors.Connection_Failed;
   end Failing_HTTP3_Backend;

   function Forbidden_Response_Header_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add
        (Headers, "transfer-encoding", "chunked");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Forbidden_Response_Header_HTTP3_Backend;

   function Uppercase_Response_Header_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Headers, "X-Upper", "value");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Uppercase_Response_Header_HTTP3_Backend;

   function Large_Response_Header_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
      Value   : constant String (1 .. 300) := [others => 'x'];
   begin
      Status := Http_Client.Headers.Add (Headers, "x-large", Value);
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Large_Response_Header_HTTP3_Backend;

   function Invalid_Reason_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
   begin
      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK" & Character'Val (13) & Character'Val (10),
         Headers   => Http_Client.Headers.Empty,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Invalid_Reason_HTTP3_Backend;

   function HTTP10_Response_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
   begin
      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_0,
         Status    => 200,
         Reason    => "OK",
         Headers   => Http_Client.Headers.Empty,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end HTTP10_Response_HTTP3_Backend;

   function Bodyless_Status_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
   begin
      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 204,
         Reason    => "No Content",
         Headers   => Http_Client.Headers.Empty,
         Body_Text => "not allowed");
      return Http_Client.Errors.Ok;
   end Bodyless_Status_HTTP3_Backend;

   function Mismatched_Content_Length_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Headers, "content-length", "99");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Mismatched_Content_Length_HTTP3_Backend;

   function Duplicate_Content_Length_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Headers, "content-length", "7");
      if Status = Http_Client.Errors.Ok then
         Status := Http_Client.Headers.Add (Headers, "content-length", "7");
      end if;

      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Duplicate_Content_Length_HTTP3_Backend;

   function Non_Numeric_Content_Length_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Headers, "content-length", "seven");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.From_Components
        (Version   => Http_Client.Responses.HTTP_1_1,
         Status    => 200,
         Reason    => "OK",
         Headers   => Headers,
         Body_Text => "decoded");
      return Http_Client.Errors.Ok;
   end Non_Numeric_Content_Length_HTTP3_Backend;

   function Forbidden_Response_Trailer_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Trailers, "content-length", "7");
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.Copy_With_Trailers
        (Http_Client.Responses.From_Components
           (Version   => Http_Client.Responses.HTTP_1_1,
            Status    => 200,
            Reason    => "OK",
            Headers   => Http_Client.Headers.Empty,
            Body_Text => "decoded"),
         Trailers);
      return Http_Client.Errors.Ok;
   end Forbidden_Response_Trailer_HTTP3_Backend;

   function Large_Response_Trailer_HTTP3_Backend
     (Request         : Http_Client.Requests.Request;
      Request_Headers : Http_Client.Headers.Header_List;
      Options         : Http_Client.HTTP3.HTTP3_Options;
      Connect_Host    : String;
      Connect_Port    : Natural;
      Max_Body_Size   : Natural;
      Response        : out Http_Client.Responses.Response)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced
        (Request, Request_Headers, Options, Connect_Host, Connect_Port,
         Max_Body_Size);
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status   : Http_Client.Errors.Result_Status;
      Value    : constant String (1 .. 300) := [others => 't'];
   begin
      Status := Http_Client.Headers.Add (Trailers, "x-large-trailer", Value);
      if Status /= Http_Client.Errors.Ok then
         Response := Http_Client.Responses.Default_Response;
         return Status;
      end if;

      Response := Http_Client.Responses.Copy_With_Trailers
        (Http_Client.Responses.From_Components
           (Version   => Http_Client.Responses.HTTP_1_1,
            Status    => 200,
            Reason    => "OK",
            Headers   => Http_Client.Headers.Empty,
            Body_Text => "decoded"),
         Trailers);
      return Http_Client.Errors.Ok;
   end Large_Response_Trailer_HTTP3_Backend;

   procedure Test_HTTP3_Force_No_Backend_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Make_HTTPS_Request (Req);
      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request => Req, Options => Options, Response => Resp)
         = Http_Client.Errors.QUIC_Unsupported,
         "Force_HTTP_3 no-backend execution must fail with a deterministic unsupported status");
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "Force_HTTP_3 must disable fallback even before request bytes are sent");
   end Test_HTTP3_Force_No_Backend_Fails_Deterministically;

   procedure Test_HTTP3_Buffered_Backend_Callback_Executes

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Backend_Called := False;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request       => Req,
         Options       => Options,
         Response      => Resp,
         Max_Body_Size => 123,
         Backend       => Scripted_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTP/3 execution should return backend status when a backend is supplied");
      Assert (Backend_Called, "HTTP/3 backend callback should be invoked");
      Assert
        (Ada.Strings.Unbounded.To_String (Backend_Last_Host) = "example.test"
         and then Backend_Last_Port = 443
         and then Backend_Last_Header_Num > 0
         and then Backend_Last_Max_Body = 123,
         "HTTP/3 backend should receive mapped headers, endpoint, and limits");
      Assert
        (Http_Client.Responses.Status_Code (Resp) = 203
         and then Http_Client.Responses.Response_Body (Resp) = "h3 backend",
         "HTTP/3 backend response should be returned to the caller");
   end Test_HTTP3_Buffered_Backend_Callback_Executes;

   procedure Test_HTTP3_Backend_Success_Diagnostics

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Snap    : Http_Client.Diagnostics.Metrics_Snapshot;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Diagnostic_Current_Time := Ada.Calendar.Time_Of (2026, 5, 13, 12.0);
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access,
         Clock    => Diagnostic_Test_Time'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request       => Req,
         Options       => Options,
         Response      => Resp,
         Diagnostics   => Context'Unchecked_Access,
         Request_ID    => 11,
         Connection_ID => 13,
         Backend       => Scripted_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Ok,
         "successful HTTP/3 backend execution should preserve Ok status");
      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Assert
        (Diagnostic_Callback_Count = 2,
         "successful HTTP/3 backend execution should emit start and response diagnostics");
      Assert
        (Snap.HTTP3_Events = 1,
         "successful HTTP/3 backend execution should count only the QUIC start as an HTTP/3 event");
      Assert
        (Snap.Bytes_Received = Http_Client.Responses.Response_Body (Resp)'Length,
         "successful HTTP/3 backend response diagnostics should count decoded response bytes");
   end Test_HTTP3_Backend_Success_Diagnostics;

   procedure Test_HTTP3_Backend_Failure_Diagnostics
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Diagnostic_Current_Time := Ada.Calendar.Time_Of (2026, 5, 13, 12.0);
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access,
         Clock    => Diagnostic_Test_Time'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access,
         Backend     => Failing_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Connection_Failed,
         "HTTP/3 backend failure diagnostics should preserve backend failure status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "HTTP/3 backend failure should emit start and failed diagnostics");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.QUIC_Connection_Failed
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Connection_Failed,
         "HTTP/3 backend failure diagnostic should carry backend failure status");
      Assert
        (Diagnostic_Last_Event.Elapsed_Milliseconds = 1_250,
         "HTTP/3 backend failure diagnostic should include QUIC/backend elapsed milliseconds");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "failed HTTP/3 backend responses should not be exposed");
   end Test_HTTP3_Backend_Failure_Diagnostics;

   procedure Test_HTTP3_Backend_Failure_Diagnostic_Abort
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context        => Context,
         Enabled        => True,
         Observer       => Abort_On_QUIC_Failed_Diagnostic'Unrestricted_Access,
         Failure_Policy => Http_Client.Diagnostics.Abort_On_Callback_Failure);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access,
         Backend     => Failing_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "abort-on-callback diagnostics should override backend failure status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "abort-on-callback diagnostics should stop at the failed-backend event");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.QUIC_Connection_Failed
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Connection_Failed,
         "abort-on-callback diagnostics should abort from the backend failure event");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "aborted HTTP/3 backend failure diagnostics should still clear the response");
   end Test_HTTP3_Backend_Failure_Diagnostic_Abort;

   procedure Test_HTTP3_QUIC_Open_Failure_Diagnostics
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported,
         "HTTP/3 QUIC open failure diagnostics should preserve QUIC failure status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "HTTP/3 QUIC open failure should emit start and failed diagnostics");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.QUIC_Connection_Failed
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.QUIC_Unsupported,
         "HTTP/3 QUIC open failure diagnostic should carry QUIC failure status");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "failed HTTP/3 QUIC opens should not expose a response");
   end Test_HTTP3_QUIC_Open_Failure_Diagnostics;

   procedure Test_HTTP3_QUIC_Open_Failure_Diagnostic_Abort
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context        => Context,
         Enabled        => True,
         Observer       => Abort_On_QUIC_Failed_Diagnostic'Unrestricted_Access,
         Failure_Policy => Http_Client.Diagnostics.Abort_On_Callback_Failure);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "abort-on-callback diagnostics should override QUIC open failure status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "abort-on-callback diagnostics should stop at the QUIC open failure event");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.QUIC_Connection_Failed
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.QUIC_Unsupported,
         "abort-on-callback diagnostics should abort from the QUIC open failure event");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "aborted HTTP/3 QUIC open failures should still clear the response");
   end Test_HTTP3_QUIC_Open_Failure_Diagnostic_Abort;

   procedure Test_HTTP3_Request_Trailers_Unsupported_Diagnostics
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req      : Http_Client.Requests.Request;
      Resp     : Http_Client.Responses.Response;
      Trailer  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_Body : Http_Client.Request_Bodies.Request_Body;
      Options  : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context  : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Status := Http_Client.Headers.Add (Trailer, "x-finish", "yes");
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 trailer test header should construct");
      Req_Body := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.From_String ("abc"), Trailer);
      Status := Http_Client.Requests.Set_Body (Req, Req_Body);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 trailer test body should attach");
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "HTTP/3 request trailer diagnostics should preserve unsupported status");
      Assert
        (Diagnostic_Callback_Count = 1,
         "HTTP/3 request trailers should be rejected before QUIC start diagnostics");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.HTTP3_Execution_Unsupported
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Unsupported_Feature
         and then Diagnostic_Last_Event.Protocol = Http_Client.Diagnostics.Protocol_HTTP_3,
         "HTTP/3 request trailer diagnostic should carry protocol and result");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "unsupported HTTP/3 request trailers should not expose a response");
   end Test_HTTP3_Request_Trailers_Unsupported_Diagnostics;

   procedure Test_HTTP3_Request_Trailers_Unsupported_Diagnostic_Abort
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req      : Http_Client.Requests.Request;
      Resp     : Http_Client.Responses.Response;
      Trailer  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req_Body : Http_Client.Request_Bodies.Request_Body;
      Options  : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context  : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Status := Http_Client.Headers.Add (Trailer, "x-finish", "yes");
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 trailer abort test header should construct");
      Req_Body := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.From_String ("abc"), Trailer);
      Status := Http_Client.Requests.Set_Body (Req, Req_Body);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 trailer abort test body should attach");
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context        => Context,
         Enabled        => True,
         Observer       => Abort_On_HTTP3_Unsupported_Diagnostic'Unrestricted_Access,
         Failure_Policy => Http_Client.Diagnostics.Abort_On_Callback_Failure);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "abort-on-callback diagnostics should override unsupported request trailers");
      Assert
        (Diagnostic_Callback_Count = 1,
         "abort-on-callback request trailer diagnostics should stop before QUIC start");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.HTTP3_Execution_Unsupported
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Unsupported_Feature,
         "abort-on-callback diagnostics should abort from the request trailer event");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "aborted HTTP/3 request trailer rejection should not expose a response");
   end Test_HTTP3_Request_Trailers_Unsupported_Diagnostic_Abort;

   procedure Test_HTTP3_Streaming_Upload_Unsupported_Diagnostics
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req      : Http_Client.Requests.Request;
      Resp     : Http_Client.Responses.Response;
      Req_Body : Http_Client.Request_Bodies.Request_Body;
      Options  : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context  : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Req_Body := Http_Client.Request_Bodies.From_Fixed_Length_Stream
        (Producer => null,
         Length   => 0,
         Replayable => True);
      Status := Http_Client.Requests.Set_Body (Req, Req_Body);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 streaming upload test body should attach");
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "HTTP/3 streaming upload diagnostics should preserve unsupported status");
      Assert
        (Diagnostic_Callback_Count = 1,
         "HTTP/3 streaming uploads should be rejected before QUIC start diagnostics");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.HTTP3_Execution_Unsupported
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Unsupported_Feature
         and then Diagnostic_Last_Event.Protocol = Http_Client.Diagnostics.Protocol_HTTP_3,
         "HTTP/3 streaming upload diagnostic should carry protocol and result");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "unsupported HTTP/3 streaming uploads should not expose a response");
   end Test_HTTP3_Streaming_Upload_Unsupported_Diagnostics;

   procedure Test_HTTP3_Streaming_Upload_Unsupported_Diagnostic_Abort
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Req      : Http_Client.Requests.Request;
      Resp     : Http_Client.Responses.Response;
      Req_Body : Http_Client.Request_Bodies.Request_Body;
      Options  : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context  : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Req_Body := Http_Client.Request_Bodies.From_Fixed_Length_Stream
        (Producer => null,
         Length   => 0,
         Replayable => True);
      Status := Http_Client.Requests.Set_Body (Req, Req_Body);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 streaming upload abort test body should attach");
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context        => Context,
         Enabled        => True,
         Observer       => Abort_On_HTTP3_Unsupported_Diagnostic'Unrestricted_Access,
         Failure_Policy => Http_Client.Diagnostics.Abort_On_Callback_Failure);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request     => Req,
         Options     => Options,
         Response    => Resp,
         Diagnostics => Context'Unchecked_Access);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "abort-on-callback diagnostics should override unsupported streaming uploads");
      Assert
        (Diagnostic_Callback_Count = 1,
         "abort-on-callback streaming upload diagnostics should stop before QUIC start");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.HTTP3_Execution_Unsupported
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Unsupported_Feature,
         "abort-on-callback diagnostics should abort from the streaming upload event");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "aborted HTTP/3 streaming upload rejection should not expose a response");
   end Test_HTTP3_Streaming_Upload_Unsupported_Diagnostic_Abort;

   procedure Test_HTTP3_Backend_Response_Size_Limit

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request       => Req,
         Options       => Options,
         Response      => Resp,
         Max_Body_Size => 4,
         Backend       => Oversized_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Response_Too_Large,
         "HTTP/3 boundary should enforce Max_Body_Size after backend execution");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "oversized HTTP/3 backend responses should not be exposed");
   end Test_HTTP3_Backend_Response_Size_Limit;

   procedure Test_HTTP3_Backend_Rejection_Diagnostics

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request       => Req,
         Options       => Options,
         Response      => Resp,
         Max_Body_Size => 4,
         Diagnostics   => Context'Unchecked_Access,
         Request_ID    => 17,
         Connection_ID => 19,
         Backend       => Oversized_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Response_Too_Large,
         "HTTP/3 backend rejection diagnostics should preserve rejection status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "HTTP/3 backend rejection should emit start and error diagnostics");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.Error_Event
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Response_Too_Large
         and then Diagnostic_Last_Event.Protocol = Http_Client.Diagnostics.Protocol_HTTP_3,
         "HTTP/3 backend rejection diagnostic should carry protocol and result");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "rejected HTTP/3 backend responses should not be exposed");
   end Test_HTTP3_Backend_Rejection_Diagnostics;

   procedure Test_HTTP3_Backend_Rejection_Diagnostic_Abort

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context        => Context,
         Enabled        => True,
         Observer       => Abort_On_Error_Diagnostic'Unrestricted_Access,
         Failure_Policy => Http_Client.Diagnostics.Abort_On_Callback_Failure);

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request       => Req,
         Options       => Options,
         Response      => Resp,
         Max_Body_Size => 4,
         Diagnostics   => Context'Unchecked_Access,
         Backend       => Oversized_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "abort-on-callback diagnostics should override backend rejection status");
      Assert
        (Diagnostic_Callback_Count = 2,
         "abort-on-callback diagnostics should stop at the rejection event");
      Assert
        (Diagnostic_Last_Event.Kind = Http_Client.Diagnostics.Error_Event
         and then Diagnostic_Last_Event.Result = Http_Client.Errors.Response_Too_Large,
         "abort-on-callback diagnostics should abort from the backend rejection event");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "aborted HTTP/3 backend rejection diagnostics should still clear the response");
   end Test_HTTP3_Backend_Rejection_Diagnostic_Abort;

   procedure Test_HTTP3_Backend_Response_Header_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Forbidden_Response_Header_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTP/3 boundary should reject forbidden backend response headers");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "invalid HTTP/3 backend response headers should clear the response");
   end Test_HTTP3_Backend_Response_Header_Validation;

   procedure Test_HTTP3_Backend_Response_Header_Lowercase_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Uppercase_Response_Header_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTP/3 boundary should reject non-lowercase backend response headers");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "non-lowercase HTTP/3 backend response headers should clear the response");
   end Test_HTTP3_Backend_Response_Header_Lowercase_Validation;

   procedure Test_HTTP3_Backend_Response_Header_List_Limit

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Options.Max_Header_List_Size := 256;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Large_Response_Header_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Header_Too_Large,
         "HTTP/3 boundary should enforce Max_Header_List_Size on backend response headers");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "oversized HTTP/3 backend response headers should clear the response");
   end Test_HTTP3_Backend_Response_Header_List_Limit;

   procedure Test_HTTP3_Backend_Reason_Phrase_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Invalid_Reason_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject control characters in backend reason phrase");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "invalid HTTP/3 backend reason phrases should clear the response");
   end Test_HTTP3_Backend_Reason_Phrase_Validation;

   procedure Test_HTTP3_Backend_Response_Version_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => HTTP10_Response_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject misleading HTTP/1.0 backend response versions");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "invalid HTTP/3 backend response versions should clear the response");
   end Test_HTTP3_Backend_Response_Version_Validation;

   procedure Test_HTTP3_Backend_Bodyless_Status_Body_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Bodyless_Status_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject bodies on no-body response statuses");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "bodyless-status protocol errors should clear the response");
   end Test_HTTP3_Backend_Bodyless_Status_Body_Validation;

   procedure Test_HTTP3_Backend_Content_Length_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Mismatched_Content_Length_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject mismatched backend Content-Length");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "Content-Length protocol errors should clear the response");
   end Test_HTTP3_Backend_Content_Length_Validation;

   procedure Test_HTTP3_Backend_Duplicate_Content_Length_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Duplicate_Content_Length_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject duplicate backend Content-Length fields");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "duplicate Content-Length protocol errors should clear the response");
   end Test_HTTP3_Backend_Duplicate_Content_Length_Validation;

   procedure Test_HTTP3_Backend_Non_Numeric_Content_Length_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Non_Numeric_Content_Length_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.HTTP3_Protocol_Error,
         "HTTP/3 boundary should reject non-numeric backend Content-Length fields");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "non-numeric Content-Length protocol errors should clear the response");
   end Test_HTTP3_Backend_Non_Numeric_Content_Length_Validation;

   procedure Test_HTTP3_Backend_Response_Trailer_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Forbidden_Response_Trailer_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTP/3 boundary should reject forbidden backend response trailers");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "invalid HTTP/3 backend response trailers should clear the response");
   end Test_HTTP3_Backend_Response_Trailer_Validation;

   procedure Test_HTTP3_Backend_Response_Trailer_List_Limit

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Options.Max_Header_List_Size := 256;

      Status := Http_Client.HTTP3.Execution.Execute_Buffered
        (Request  => Req,
         Options  => Options,
         Response => Resp,
         Backend  => Large_Response_Trailer_HTTP3_Backend'Unrestricted_Access);

      Assert
        (Status = Http_Client.Errors.Header_Too_Large,
         "HTTP/3 boundary should enforce Max_Header_List_Size on backend response trailers");
      Assert
        (Http_Client.Responses.Response_Body (Resp) = "",
         "oversized HTTP/3 backend response trailers should clear the response");
   end Test_HTTP3_Backend_Response_Trailer_List_Limit;

   procedure Test_HTTP3_Force_No_Fallback_To_HTTP2

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "Force_HTTP_3 must not downgrade to HTTP/2 when the QUIC backend is absent");
   end Test_HTTP3_Force_No_Fallback_To_HTTP2;

   procedure Test_HTTP3_Force_No_Fallback_To_HTTP1

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "Force_HTTP_3 must not downgrade to HTTP/1.1 when the QUIC backend is absent");
   end Test_HTTP3_Force_No_Fallback_To_HTTP1;

   procedure Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_Force_HTTP_3;
      Options.HTTP3 := Forced_No_Backend_Options;
      Status := Http_Client.Response_Streams.Open
        (Request => Req, Stream => Stream, Options => Options);
      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported,
         "Streaming_Force_HTTP_3 must fail before HTTP/1.1 or HTTP/2 request bytes when no QUIC backend exists");
      Assert
        (Http_Client.Response_Streams.Last_Status (Stream) = Status,
         "failed streaming HTTP/3 open should preserve the deterministic last status");
   end Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically;

   procedure Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req    : Http_Client.Requests.Request;
      Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Result : Http_Client.Clients.Client_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Config.HTTP3 := Forced_No_Backend_Options;
      Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
      Config.Retries.Enable_Retries := True;
      Config.Retries.Maximum_Attempts := 3;
      Status := Http_Client.Clients.Configure (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "forced HTTP/3 client configuration should validate");
      Status := Http_Client.Clients.Execute (Client, Req, Result);
      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported,
         "high-level buffered Force_HTTP_3 must fail deterministically without a backend");
      Assert
        (Result.Status = Http_Client.Errors.QUIC_Unsupported,
         "client result must preserve the forced HTTP/3 no-backend status");
   end Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically;

   procedure Test_HTTP3_High_Level_Client_Uses_Configured_Backend

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Result  : Http_Client.Clients.Client_Result;
      Client  : Http_Client.Clients.Client;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Config.HTTP3 := Forced_No_Backend_Options;
      Config.HTTP3.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Config.HTTP3_Backend := Scripted_HTTP3_Backend'Unrestricted_Access;
      Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
      Config.Enable_Decompression := False;
      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "HTTP/3 backend client config should initialize");

      Backend_Called := False;
      Status := Http_Client.Clients.Execute
        (Item    => Client,
         Request => Req,
         Result  => Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level Force_HTTP_3 should use the configured HTTP/3 backend: " &
         Http_Client.Errors.Result_Status'Image (Status));
      Assert (Backend_Called, "high-level client should invoke HTTP/3 backend");
      Assert
        (Http_Client.Responses.Status_Code (Result.Response) = 203
         and then Http_Client.Responses.Response_Body (Result.Response) = "h3 backend",
         "high-level HTTP/3 backend response should be returned");
   end Test_HTTP3_High_Level_Client_Uses_Configured_Backend;

   procedure Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Options.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
      Status := Http_Client.Clients.Execute_Once
        (Request => Req, Response => Resp, Options => Options);
      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported,
         "one-shot Force_HTTP_3 must fail with the no-backend status rather than entering HTTP/1.1");
   end Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically;

   procedure Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Make_HTTPS_Request (Req);
      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request          => Req,
            Options          => Options,
            Response         => Resp,
            Proxy_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "Force_HTTP_3 with an HTTP proxy must fail at the proxy boundary instead of opening a direct QUIC route");
   end Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy;

   procedure Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Make_HTTPS_Request (Req);
      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request          => Req,
            Options          => Options,
            Response         => Resp,
            SOCKS_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "Force_HTTP_3 with a SOCKS5 proxy must fail at the proxy boundary instead of opening a direct QUIC route");
   end Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy;

   procedure Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
      Proxy   : constant Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.HTTP ("proxy.example", 8080);
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
      Assert (Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.HTTP_Proxy,
              "HTTP proxy fixture config should remain an HTTP proxy");
      Assert
        (Http_Client.HTTP3.Execution_Status (Options, Proxy_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "Prefer_HTTP_3 must detect that HTTP/3 over the configured HTTP proxy is unsupported");
      Assert
        (Http_Client.HTTP3.Fallback_Status (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.Ok,
         "Prefer_HTTP_3 may fall back only before request bytes, " &
         "preserving the configured HTTP proxy route for the fallback protocol");
   end Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy;

   procedure Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
      Proxy   : constant Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.SOCKS5 ("socks.example", 1080);
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
      Assert (Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.SOCKS5_Proxy,
              "SOCKS5 proxy fixture config should remain a SOCKS5 proxy");
      Assert
        (Http_Client.HTTP3.Execution_Status (Options, SOCKS_Configured => True)
         = Http_Client.Errors.HTTP3_Proxy_Unsupported,
         "Prefer_HTTP_3 must detect that HTTP/3 over the configured SOCKS5 proxy is unsupported");
      Assert
        (Http_Client.HTTP3.Fallback_Status (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.Ok,
         "Prefer_HTTP_3 may fall back only before request bytes, " &
         "preserving the configured SOCKS5 proxy route for the fallback protocol");
   end Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy;

   procedure Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Options.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
      Assert
        (Http_Client.HTTP3.Execution_Status (Options)
         = Http_Client.Errors.QUIC_Unsupported,
         "Prefer_HTTP_3 without backend should report the no-backend status before fallback is considered");
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "Prefer_HTTP_3 with fallback disabled must fail deterministically instead of downgrading");
   end Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically;

   procedure Test_HTTP3_Fallback_After_Request_Bytes_Disallowed

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Options, Request_Bytes_Already_Sent => True)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "HTTP/3 fallback must be rejected after any request bytes may have been sent");
   end Test_HTTP3_Fallback_After_Request_Bytes_Disallowed;

   procedure Test_HTTP3_Experimental_Unsafe_Features_Rejected

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   begin
      Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Options.Enable_Server_Push := True;
      Assert
        (Http_Client.HTTP3.Validate (Options) = Http_Client.Errors.HTTP3_Unsupported,
         "HTTP/3 server push must remain unsupported at this boundary");
      Options.Enable_Server_Push := False;
      Options.Enable_Zero_RTT := True;
      Assert
        (Http_Client.HTTP3.Validate (Options) = Http_Client.Errors.Invalid_Configuration,
         "HTTP/3 0-RTT must remain disabled until a real audited backend exists");
   end Test_HTTP3_Experimental_Unsafe_Features_Rejected;

   procedure Test_HTTP3_No_Backend_Not_Retried_As_HTTP1

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req    : Http_Client.Requests.Request;
      Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Result : Http_Client.Clients.Client_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Make_HTTPS_Request (Req);
      Config.HTTP3 := Forced_No_Backend_Options;
      Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
      Config.Retries.Enable_Retries := True;
      Config.Retries.Maximum_Attempts := 3;
      Status := Http_Client.Clients.Configure (Client, Config);
      Assert (Status = Http_Client.Errors.Ok, "retry-enabled forced HTTP/3 client should configure");
      Status := Http_Client.Clients.Execute (Client, Req, Result);
      Assert
        (Status = Http_Client.Errors.QUIC_Unsupported,
         "forced HTTP/3 no-backend status must not be retried as HTTP/1.1");
   end Test_HTTP3_No_Backend_Not_Retried_As_HTTP1;

   procedure Test_HTTP3_Redirect_Keeps_Forced_Policy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : constant Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Assert
        (Options.Fallback = Http_Client.HTTP3.Fallback_Disallowed,
         "forced HTTP/3 policy must remain forced across redirect processing");
      Assert
        (Http_Client.HTTP3.Fallback_Status (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "redirect handling must not silently convert forced HTTP/3 into a fallback-capable policy");
   end Test_HTTP3_Redirect_Keeps_Forced_Policy;

   procedure Test_HTTP3_Request_Header_Preflight_Before_QUIC_Open

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI     : Http_Client.URI.URI_Reference;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse ("https://example.test/forbidden-hop-header", URI);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTP/3 forbidden-header URI should parse");
      Status := Http_Client.Headers.Add (Headers, "Connection", "close");
      Assert
        (Status = Http_Client.Errors.Ok,
         "ordinary request headers may contain HTTP/1 hop-by-hop names before " &
         "protocol mapping");
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.GET,
         URI     => URI,
         Item    => Req,
         Headers => Headers);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTP/3 forbidden-header request should construct");

      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request => Req, Options => Options, Response => Resp)
         = Http_Client.Errors.Invalid_Header,
         "HTTP/3 execution must reject forbidden connection headers before opening QUIC");
   end Test_HTTP3_Request_Header_Preflight_Before_QUIC_Open;

   procedure Test_HTTP3_Request_Header_List_Limit_Before_QUIC_Open

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Options.Max_Header_List_Size := 1;

      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request => Req, Options => Options, Response => Resp)
         = Http_Client.Errors.Response_Too_Large,
         "HTTP/3 execution must enforce request header-list limits before " &
         "opening QUIC");
   end Test_HTTP3_Request_Header_List_Limit_Before_QUIC_Open;

   procedure Test_HTTP3_Invalid_Alternative_Host_Before_QUIC_Open

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Req     : Http_Client.Requests.Request;
      Resp    : Http_Client.Responses.Response;
      Options : Http_Client.HTTP3.HTTP3_Options := Forced_No_Backend_Options;
      Context : aliased Http_Client.Diagnostics.Diagnostics_Context;
      Snap    : Http_Client.Diagnostics.Metrics_Snapshot;
   begin
      Make_HTTPS_Request (Req);
      Options.QUIC.Backend := Http_Client.QUIC.Backend_Available;
      Diagnostic_Callback_Count := 0;
      Http_Client.Diagnostics.Initialize
        (Context  => Context,
         Enabled  => True,
         Observer => Capture_Diagnostic'Unrestricted_Access);

      Assert
        (Http_Client.HTTP3.Execution.Execute_Buffered
           (Request          => Req,
            Options          => Options,
            Response         => Resp,
            Alternative_Host => "bad host",
            Diagnostics      => Context'Unchecked_Access)
         = Http_Client.Errors.Invalid_URI,
         "HTTP/3 execution must reject invalid alternative endpoint hosts " &
         "before opening QUIC");

      Snap := Http_Client.Diagnostics.Snapshot (Context);
      Assert
        (Snap.HTTP3_Events = 0,
         "invalid HTTP/3 alternative endpoint host must not emit QUIC events");
      Assert
        (Diagnostic_Callback_Count = 0,
         "invalid HTTP/3 alternative endpoint host must not call diagnostics");
   end Test_HTTP3_Invalid_Alternative_Host_Before_QUIC_Open;

   procedure Test_HTTP3_Body_Stream_Byte_Array_API_Compiles

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Stream : Http_Client.HTTP3.Body_Streams.Body_Stream;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4);
      Data   : constant Ada.Streams.Stream_Element_Array (1 .. 3) :=
        [1 => 0, 2 => 1, 3 => 255];
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert
        (Http_Client.HTTP3.Body_Streams.Open (Stream, Max_Body_Size => 16)
         = Http_Client.Errors.Ok,
         "HTTP/3 body stream should open with a byte-array read API");
      Assert
        (Http_Client.HTTP3.Body_Streams.Append_Data (Stream, Data)
         = Http_Client.Errors.Ok,
         "HTTP/3 body stream must accept arbitrary binary DATA payload bytes");
      Assert
        (Http_Client.HTTP3.Body_Streams.Mark_End_Stream (Stream)
         = Http_Client.Errors.Ok,
         "HTTP/3 body stream should accept end-of-stream after binary DATA");
      Assert
        (Http_Client.HTTP3.Body_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.Ok,
         "HTTP/3 body stream byte-array read should return queued DATA bytes");
      Assert (Last = 3, "HTTP/3 byte-array read should report the last written offset");
      Assert
        (Buffer (1) = Ada.Streams.Stream_Element (0)
         and then Buffer (2) = Ada.Streams.Stream_Element (1)
         and then Buffer (3) = Ada.Streams.Stream_Element (255),
         "HTTP/3 byte-array read must preserve NUL and high-bit bytes without text conversion");
   end Test_HTTP3_Body_Stream_Byte_Array_API_Compiles;

   procedure Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Stream : Http_Client.HTTP3.Body_Streams.Body_Stream;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Assert
        (Http_Client.HTTP3.Body_Streams.Read_Some (Stream, Buffer, Last)
         = Http_Client.Errors.Not_Connected,
         "HTTP/3 body stream read before backend/open must fail deterministically");
      Assert
        (Last = Buffer'First - 1,
         "failed HTTP/3 byte-array read should return an empty byte range");
   end Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically;

   procedure Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Field : Http_Client.HTTP3.QPACK.Header_Field;
      Used  : Natural := 0;
   begin
      Assert
        (Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
           ("" & Character'Val (16#80#), Field, Used)
         = Http_Client.Errors.HTTP3_QPACK_Error,
         "QPACK indexed/dynamic forms outside the static literal subset must fail deterministically");
   end Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("HTTP3 boundary");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_HTTP3_Force_No_Backend_Fails_Deterministically'Access,
         "Test_HTTP3_Force_No_Backend_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_Buffered_Backend_Callback_Executes'Access,
         "Test_HTTP3_Buffered_Backend_Callback_Executes");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Success_Diagnostics'Access,
         "Test_HTTP3_Backend_Success_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Failure_Diagnostics'Access,
         "Test_HTTP3_Backend_Failure_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Failure_Diagnostic_Abort'Access,
         "Test_HTTP3_Backend_Failure_Diagnostic_Abort");
      Register_Routine
        (T,
         Test_HTTP3_QUIC_Open_Failure_Diagnostics'Access,
         "Test_HTTP3_QUIC_Open_Failure_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_QUIC_Open_Failure_Diagnostic_Abort'Access,
         "Test_HTTP3_QUIC_Open_Failure_Diagnostic_Abort");
      Register_Routine
        (T,
         Test_HTTP3_Request_Trailers_Unsupported_Diagnostics'Access,
         "Test_HTTP3_Request_Trailers_Unsupported_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_Request_Trailers_Unsupported_Diagnostic_Abort'Access,
         "Test_HTTP3_Request_Trailers_Unsupported_Diagnostic_Abort");
      Register_Routine
        (T,
         Test_HTTP3_Streaming_Upload_Unsupported_Diagnostics'Access,
         "Test_HTTP3_Streaming_Upload_Unsupported_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_Streaming_Upload_Unsupported_Diagnostic_Abort'Access,
         "Test_HTTP3_Streaming_Upload_Unsupported_Diagnostic_Abort");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Size_Limit'Access,
         "Test_HTTP3_Backend_Response_Size_Limit");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Rejection_Diagnostics'Access,
         "Test_HTTP3_Backend_Rejection_Diagnostics");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Rejection_Diagnostic_Abort'Access,
         "Test_HTTP3_Backend_Rejection_Diagnostic_Abort");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Header_Validation'Access,
         "Test_HTTP3_Backend_Response_Header_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Header_Lowercase_Validation'Access,
         "Test_HTTP3_Backend_Response_Header_Lowercase_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Header_List_Limit'Access,
         "Test_HTTP3_Backend_Response_Header_List_Limit");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Reason_Phrase_Validation'Access,
         "Test_HTTP3_Backend_Reason_Phrase_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Version_Validation'Access,
         "Test_HTTP3_Backend_Response_Version_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Bodyless_Status_Body_Validation'Access,
         "Test_HTTP3_Backend_Bodyless_Status_Body_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Content_Length_Validation'Access,
         "Test_HTTP3_Backend_Content_Length_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Duplicate_Content_Length_Validation'Access,
         "Test_HTTP3_Backend_Duplicate_Content_Length_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Non_Numeric_Content_Length_Validation'Access,
         "Test_HTTP3_Backend_Non_Numeric_Content_Length_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Trailer_Validation'Access,
         "Test_HTTP3_Backend_Response_Trailer_Validation");
      Register_Routine
        (T,
         Test_HTTP3_Backend_Response_Trailer_List_Limit'Access,
         "Test_HTTP3_Backend_Response_Trailer_List_Limit");
      Register_Routine
        (T,
         Test_HTTP3_Force_No_Fallback_To_HTTP2'Access,
         "Test_HTTP3_Force_No_Fallback_To_HTTP2");
      Register_Routine
        (T,
         Test_HTTP3_Force_No_Fallback_To_HTTP1'Access,
         "Test_HTTP3_Force_No_Fallback_To_HTTP1");
      Register_Routine
        (T,
         Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically'Access,
         "Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically'Access,
         "Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_High_Level_Client_Uses_Configured_Backend'Access,
         "Test_HTTP3_High_Level_Client_Uses_Configured_Backend");
      Register_Routine
        (T,
         Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically'Access,
         "Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy'Access,
         "Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy");
      Register_Routine
        (T,
         Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy'Access,
         "Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy");
      Register_Routine
        (T,
         Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy'Access,
         "Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy");
      Register_Routine
        (T,
         Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy'Access,
         "Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy");
      Register_Routine
        (T,
         Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically'Access,
         "Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_Fallback_After_Request_Bytes_Disallowed'Access,
         "Test_HTTP3_Fallback_After_Request_Bytes_Disallowed");
      Register_Routine
        (T,
         Test_HTTP3_Experimental_Unsafe_Features_Rejected'Access,
         "Test_HTTP3_Experimental_Unsafe_Features_Rejected");
      Register_Routine
        (T,
         Test_HTTP3_No_Backend_Not_Retried_As_HTTP1'Access,
         "Test_HTTP3_No_Backend_Not_Retried_As_HTTP1");
      Register_Routine
        (T,
         Test_HTTP3_Redirect_Keeps_Forced_Policy'Access,
         "Test_HTTP3_Redirect_Keeps_Forced_Policy");
      Register_Routine
        (T,
         Test_HTTP3_Request_Header_Preflight_Before_QUIC_Open'Access,
         "Test_HTTP3_Request_Header_Preflight_Before_QUIC_Open");
      Register_Routine
        (T,
         Test_HTTP3_Request_Header_List_Limit_Before_QUIC_Open'Access,
         "Test_HTTP3_Request_Header_List_Limit_Before_QUIC_Open");
      Register_Routine
        (T,
         Test_HTTP3_Invalid_Alternative_Host_Before_QUIC_Open'Access,
         "Test_HTTP3_Invalid_Alternative_Host_Before_QUIC_Open");
      Register_Routine
        (T,
         Test_HTTP3_Body_Stream_Byte_Array_API_Compiles'Access,
         "Test_HTTP3_Body_Stream_Byte_Array_API_Compiles");
      Register_Routine
        (T,
         Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically'Access,
         "Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically");
      Register_Routine
        (T,
         Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically'Access,
         "Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically");
   end Register_Tests;

end Http_Client.HTTP3.Boundary_Tests;
