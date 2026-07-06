with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Resources;

package body Http_Client.Diagnostics is
   use Ada.Calendar;
   use type Http_Client.Errors.Result_Status;
   use type Event_Callback;
   use type Clock_Function;

   function To_Text (Value : String) return Bounded_Text is
   begin
      if Value'Length > 256 then
         return Text_256.To_Bounded_String (Value (Value'First .. Value'First + 255));
      else
         return Text_256.To_Bounded_String (Value);
      end if;
   end To_Text;

   function Text (Value : Bounded_Text) return String is
   begin
      return Text_256.To_String (Value);
   end Text;

   function Lower (Value : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower
        (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));
   end Lower;

   function Add_Redacted_Header
     (Policy : in out Redaction_Policy;
      Name   : String) return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Headers.Set (Policy.Extra_Redacted_Headers, Name, "redacted");
   end Add_Redacted_Header;

   function Is_Default_Sensitive_Header (Name : String) return Boolean is
      Key : constant String := Lower (Name);
   begin
      return Key = "authorization"
        or else Key = "proxy-authorization"
        or else Key = "cookie"
        or else Key = "set-cookie"
        or else Key = "www-authenticate"
        or else Key = "proxy-authenticate"
        or else Key = "authentication-info"
        or else Key = "proxy-authentication-info"
        or else Key = "x-api-key"
        or else Key = "api-key"
        or else Key = "x-goog-api-key"
        or else Key = "x-amz-security-token"
        or else Key = "x-auth-token"
        or else Key = "x-access-token"
        or else Key = "x-csrf-token"
        or else Key = "csrf-token"
        or else Key = "bearer";
   end Is_Default_Sensitive_Header;

   function Is_Redacted_Header
     (Policy : Redaction_Policy;
      Name   : String) return Boolean
   is
   begin
      if Policy.Unsafe_Disable_Redaction then
         return False;
      end if;

      return Is_Default_Sensitive_Header (Name)
        or else Http_Client.Headers.Contains (Policy.Extra_Redacted_Headers, Name);
   end Is_Redacted_Header;

   function Safe_Header_Value
     (Policy : Redaction_Policy;
      Name   : String;
      Value  : String) return String
   is
   begin
      if Is_Redacted_Header (Policy, Name) then
         return "<redacted>";
      elsif Policy.Allow_Header_Values then
         return Value;
      else
         return "";
      end if;
   end Safe_Header_Value;

   function Safe_Body_Preview
     (Policy : Redaction_Policy;
      Body_Data   : String) return String
   is
      Max_Count : Natural;
   begin
      if not Policy.Allow_Body_Previews or else Policy.Max_Body_Preview_Bytes = 0 then
         return "";
      end if;

      if Body_Data'Length <= Policy.Max_Body_Preview_Bytes then
         return Body_Data;
      end if;

      Max_Count := Policy.Max_Body_Preview_Bytes;
      return Body_Data (Body_Data'First .. Body_Data'First + Max_Count - 1);
   end Safe_Body_Preview;

   procedure Initialize
     (Context         : in out Diagnostics_Context;
      Enabled         : Boolean := True;
      Observer        : Event_Callback := null;
      Redaction       : Redaction_Policy := Default_Redaction_Policy;
      Failure_Policy  : Callback_Failure_Policy := Ignore_Callback_Failures;
      Clock           : Clock_Function := null;
      Metrics_Enabled : Boolean := True)
   is
   begin
      Context.Enabled_Value := Enabled;
      Context.Observer_Value := Observer;
      Context.Redaction_Value := Redaction;
      Context.Failure_Value := Failure_Policy;
      Context.Clock_Value := Clock;
      Context.Metrics_On := Metrics_Enabled;
      Context.Metrics_Value := (others => 0);
      Context.Timing_Value := (others => 0);
      Context.Next_Request_Value := 1;
      Context.Next_Conn_Value := 1;
      Context.Last_Callback := Http_Client.Errors.Ok;
   end Initialize;

   procedure Set_Observer
     (Context  : in out Diagnostics_Context;
      Observer : Event_Callback)
   is
   begin
      Context.Observer_Value := Observer;
   end Set_Observer;

   procedure Set_Redaction_Policy
     (Context   : in out Diagnostics_Context;
      Redaction : Redaction_Policy)
   is
   begin
      Context.Redaction_Value := Redaction;
   end Set_Redaction_Policy;

   procedure Set_Callback_Failure_Policy
     (Context : in out Diagnostics_Context;
      Policy  : Callback_Failure_Policy)
   is
   begin
      Context.Failure_Value := Policy;
   end Set_Callback_Failure_Policy;

   function Is_Enabled (Context : Diagnostics_Context) return Boolean is
   begin
      return Context.Enabled_Value;
   end Is_Enabled;

   function Next_Request_ID
     (Context : in out Diagnostics_Context) return Diagnostic_ID
   is
      Result : constant Diagnostic_ID := Context.Next_Request_Value;
   begin
      Context.Next_Request_Value := Context.Next_Request_Value + 1;
      return Result;
   end Next_Request_ID;

   function Next_Connection_ID
     (Context : in out Diagnostics_Context) return Diagnostic_ID
   is
      Result : constant Diagnostic_ID := Context.Next_Conn_Value;
   begin
      Context.Next_Conn_Value := Context.Next_Conn_Value + 1;
      return Result;
   end Next_Connection_ID;

   function Now (Context : Diagnostics_Context) return Ada.Calendar.Time is
   begin
      if Context.Clock_Value /= null then
         return Context.Clock_Value.all;
      else
         return Ada.Calendar.Clock;
      end if;
   end Now;

   function Elapsed_Milliseconds
     (Context : Diagnostics_Context;
      Start   : Ada.Calendar.Time;
      Stop    : Ada.Calendar.Time) return Natural
   is
      pragma Unreferenced (Context);
      Span : constant Duration := Stop - Start;
   begin
      if Span <= 0.0 then
         return 0;
      elsif Span > Duration (Natural'Last / 1_000) then
         return Natural'Last;
      else
         return Natural (Span * 1_000.0);
      end if;
   end Elapsed_Milliseconds;

   function Saturating_Add (Left, Right : Natural) return Natural is
   begin
      if Natural'Last - Left < Right then
         return Natural'Last;
      else
         return Left + Right;
      end if;
   end Saturating_Add;

   procedure Count_Event
     (Context : in out Diagnostics_Context;
      Event   : Diagnostic_Event)
   is
   begin
      if not Context.Metrics_On then
         return;
      end if;

      case Event.Kind is
         when Request_Start =>
            Context.Metrics_Value.Requests_Started :=
              Context.Metrics_Value.Requests_Started + 1;
         when Request_Finish =>
            Context.Metrics_Value.Requests_Completed :=
              Context.Metrics_Value.Requests_Completed + 1;
            Context.Timing_Value.Request_Finish_Count :=
              Context.Timing_Value.Request_Finish_Count + 1;
            Context.Timing_Value.Request_Total_Milliseconds :=
              Saturating_Add
                (Context.Timing_Value.Request_Total_Milliseconds,
                 Event.Elapsed_Milliseconds);
         when Request_Headers_Sent | Request_Body_Progress =>
            Context.Metrics_Value.Bytes_Sent :=
              Context.Metrics_Value.Bytes_Sent + Event.Request_Byte_Count;
         when Upload_Producer_Event =>
            Context.Metrics_Value.Upload_Producer_Events :=
              Context.Metrics_Value.Upload_Producer_Events + 1;
         when Multipart_Event =>
            Context.Metrics_Value.Multipart_Events :=
              Context.Metrics_Value.Multipart_Events + 1;
         when Response_Headers_Received | Response_Body_Progress =>
            Context.Metrics_Value.Bytes_Received :=
              Context.Metrics_Value.Bytes_Received + Event.Response_Byte_Count;
         when Cache_Lookup_Result =>
            if Event.Cache = Cache_Hit then
               Context.Metrics_Value.Cache_Hits :=
                 Context.Metrics_Value.Cache_Hits + 1;
            elsif Event.Cache = Cache_Miss then
               Context.Metrics_Value.Cache_Misses :=
                 Context.Metrics_Value.Cache_Misses + 1;
            end if;
         when Retry_Decision =>
            Context.Metrics_Value.Retries_Attempted :=
              Context.Metrics_Value.Retries_Attempted + 1;
         when Redirect_Decision =>
            Context.Metrics_Value.Redirects_Followed :=
              Context.Metrics_Value.Redirects_Followed + 1;
         when TCP_Connection_Opened =>
            Context.Metrics_Value.Connections_Opened :=
              Context.Metrics_Value.Connections_Opened + 1;
         when Connection_Pool_Checkout =>
            Context.Metrics_Value.Pooled_Reuses :=
              Context.Metrics_Value.Pooled_Reuses + 1;
         when HTTP2_Stream_Opened =>
            Context.Metrics_Value.HTTP2_Streams_Opened :=
              Context.Metrics_Value.HTTP2_Streams_Opened + 1;
         when HTTP2_Stream_Closed =>
            if Event.Result = Http_Client.Errors.HTTP2_Stream_Reset
              or else Event.Result = Http_Client.Errors.HTTP2_Stream_Refused
            then
               Context.Metrics_Value.HTTP2_Resets :=
                 Context.Metrics_Value.HTTP2_Resets + 1;
            end if;
         when TLS_Handshake_Finished =>
            Context.Timing_Value.TLS_Handshake_Count :=
              Context.Timing_Value.TLS_Handshake_Count + 1;
            Context.Timing_Value.TLS_Handshake_Total_Milliseconds :=
              Saturating_Add
                (Context.Timing_Value.TLS_Handshake_Total_Milliseconds,
                 Event.Elapsed_Milliseconds);
            if Event.Result /= Http_Client.Errors.Ok then
               Context.Metrics_Value.TLS_Failures :=
                 Context.Metrics_Value.TLS_Failures + 1;
            end if;
         when HTTP3_Enabled | HTTP3_Candidate_Selected
            | QUIC_Connection_Start | QUIC_Connection_Failed
            | HTTP3_Unsupported_Fallback | HTTP3_Settings_Exchanged
            | HTTP3_Stream_Opened | HTTP3_Frame_Diagnostic
            | HTTP3_QPACK_Decode_Failure | HTTP3_GOAWAY_Received
            | HTTP3_Execution_Unsupported =>
            Context.Metrics_Value.HTTP3_Events :=
              Context.Metrics_Value.HTTP3_Events + 1;
         when others =>
            null;
      end case;
   end Count_Event;

   function Redacted_Copy
     (Context : Diagnostics_Context;
      Event   : Diagnostic_Event) return Diagnostic_Event
   is
      Result : Diagnostic_Event := Event;
      Name   : constant String := Text (Event.Header_Name);
      Value  : constant String := Text (Event.Header_Value);
   begin
      if Name'Length > 0 then
         Result.Header_Redacted := Is_Redacted_Header (Context.Redaction_Value, Name);
         Result.Header_Value := To_Text
           (Safe_Header_Value (Context.Redaction_Value, Name, Value));
      end if;

      return Result;
   end Redacted_Copy;

   function Emit
     (Context : in out Diagnostics_Context;
      Event   : Diagnostic_Event) return Http_Client.Errors.Result_Status
   is
      Delivered       : Diagnostic_Event;
      Callback_Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   begin
      if not Context.Enabled_Value then
         return Http_Client.Errors.Ok;
      end if;

      Delivered := Redacted_Copy (Context, Event);
      Count_Event (Context, Delivered);
      Http_Client.Resources.Increment
        (Http_Client.Resources.Diagnostics_Events_Emitted);

      Context.Last_Callback := Http_Client.Errors.Ok;

      if Context.Observer_Value /= null then
         begin
            Context.Observer_Value.all (Delivered, Callback_Status);
         exception
            when others =>
               Callback_Status := Http_Client.Errors.Internal_Error;
         end;

         if Callback_Status /= Http_Client.Errors.Ok then
            Context.Last_Callback := Callback_Status;
            if Context.Metrics_On then
               Context.Metrics_Value.Callback_Failures :=
                 Context.Metrics_Value.Callback_Failures + 1;
            end if;

            if Context.Failure_Value = Abort_On_Callback_Failure then
               return Callback_Status;
            end if;
         end if;
      end if;

      return Http_Client.Errors.Ok;
   end Emit;

   function Snapshot (Context : Diagnostics_Context) return Metrics_Snapshot is
   begin
      return Context.Metrics_Value;
   end Snapshot;

   function Timing (Context : Diagnostics_Context) return Timing_Snapshot is
   begin
      return Context.Timing_Value;
   end Timing;

   function Average_Request_Milliseconds
     (Snapshot : Timing_Snapshot) return Natural is
   begin
      if Snapshot.Request_Finish_Count = 0 then
         return 0;
      else
         return Snapshot.Request_Total_Milliseconds / Snapshot.Request_Finish_Count;
      end if;
   end Average_Request_Milliseconds;

   function Average_TLS_Handshake_Milliseconds
     (Snapshot : Timing_Snapshot) return Natural is
   begin
      if Snapshot.TLS_Handshake_Count = 0 then
         return 0;
      else
         return Snapshot.TLS_Handshake_Total_Milliseconds / Snapshot.TLS_Handshake_Count;
      end if;
   end Average_TLS_Handshake_Milliseconds;

   procedure Reset_Metrics (Context : in out Diagnostics_Context) is
   begin
      Context.Metrics_Value := (others => 0);
      Context.Timing_Value := (others => 0);
      Context.Last_Callback := Http_Client.Errors.Ok;
   end Reset_Metrics;

   function Last_Callback_Status
     (Context : Diagnostics_Context) return Http_Client.Errors.Result_Status
   is
   begin
      return Context.Last_Callback;
   end Last_Callback_Status;
end Http_Client.Diagnostics;
