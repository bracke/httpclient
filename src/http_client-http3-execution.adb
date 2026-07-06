with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Mapping;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.QUIC;
with Http_Client.Types;
with Http_Client.Request_Bodies;
with Http_Client.URI;

package body Http_Client.HTTP3.Execution is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Diagnostics.Context_Access;
   use type Http_Client.Responses.HTTP_Version;
   use type Http_Client.Types.Method_Name;

   function Emit
     (Diagnostics   : Http_Client.Diagnostics.Context_Access;
      Event         : Http_Client.Diagnostics.Diagnostic_Event)
      return Http_Client.Errors.Result_Status is
   begin
      if Diagnostics = null then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Diagnostics.Emit (Diagnostics.all, Event);
      end if;
   end Emit;

   function Header_List_Size_Within_Limit
     (List  : Http_Client.Headers.Header_List;
      Limit : Natural) return Boolean
   is
      Total : Natural := 0;
      Field : Natural;
   begin
      for I in 1 .. Http_Client.Headers.Length (List) loop
         declare
            Name  : constant String := Http_Client.Headers.Name_At (List, I);
            Value : constant String := Http_Client.Headers.Value_At (List, I);
         begin
            Field := Name'Length + Value'Length + 32;
         end;

         if Field > Limit or else Total > Limit - Field then
            return False;
         end if;

         Total := Total + Field;
      end loop;

      return True;
   end Header_List_Size_Within_Limit;

   function Endpoint_Host_Text_Is_Valid (Host : String) return Boolean is
   begin
      if Host'Length = 0 then
         return False;
      end if;

      for Ch of Host loop
         if Ch <= ' '
           or else Character'Pos (Ch) >= 127
           or else Ch = '/'
           or else Ch = Character'Val (16#5C#)
           or else Ch = '@'
         then
            return False;
         end if;
      end loop;

      return True;
   end Endpoint_Host_Text_Is_Valid;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Is_Forbidden_HTTP3_Response_Header (Name : String) return Boolean is
      Key : constant String := Lower (Name);
   begin
      return Key = "connection"
        or else Key = "keep-alive"
        or else Key = "proxy-connection"
        or else Key = "transfer-encoding"
        or else Key = "te"
        or else Key = "trailer"
        or else Key = "upgrade";
   end Is_Forbidden_HTTP3_Response_Header;

   function Response_Body_Is_Disallowed
     (Request_Method : Http_Client.Types.Method_Name;
      Code           : Http_Client.Types.Status_Code) return Boolean is
   begin
      return Request_Method = Http_Client.Types.HEAD
        or else (Code >= 100 and then Code <= 199)
        or else Code = 204
        or else Code = 205
        or else Code = 304;
   end Response_Body_Is_Disallowed;

   function Parse_Natural (Text : String; Value : out Natural) return Boolean is
      Acc : Natural := 0;
   begin
      Value := 0;

      if Text'Length = 0 then
         return False;
      end if;

      for C of Text loop
         if C not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Natural := Character'Pos (C) - Character'Pos ('0');
         begin
            if Acc > (Natural'Last - Digit) / 10 then
               return False;
            end if;

            Acc := Acc * 10 + Digit;
         end;
      end loop;

      Value := Acc;
      return True;
   end Parse_Natural;

   function Has_Control (Text : String) return Boolean is
   begin
      for C of Text loop
         if Character'Pos (C) < 32
           or else Character'Pos (C) = 127
           or else (Character'Pos (C) >= 128
                    and then Character'Pos (C) <= 159)
         then
            return True;
         end if;
      end loop;

      return False;
   end Has_Control;

   function Emit_HTTP3_Execution_Unsupported
     (Diagnostics   : Http_Client.Diagnostics.Context_Access;
      Request_ID    : Http_Client.Diagnostics.Diagnostic_ID;
      Connection_ID : Http_Client.Diagnostics.Diagnostic_ID;
      Message       : String)
      return Http_Client.Errors.Result_Status
   is
      Emit_Status : constant Http_Client.Errors.Result_Status :=
        Emit
          (Diagnostics,
           (Kind          => Http_Client.Diagnostics.HTTP3_Execution_Unsupported,
            Request_ID    => Request_ID,
            Connection_ID => Connection_ID,
            Result        => Http_Client.Errors.Unsupported_Feature,
            Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
            Message       => Http_Client.Diagnostics.To_Text (Message),
            others        => <>));
   begin
      if Emit_Status /= Http_Client.Errors.Ok then
         return Emit_Status;
      end if;

      return Http_Client.Errors.Unsupported_Feature;
   end Emit_HTTP3_Execution_Unsupported;

   function Emit_Backend_Response_Rejected
     (Diagnostics      : Http_Client.Diagnostics.Context_Access;
      Request_ID       : Http_Client.Diagnostics.Diagnostic_ID;
      Connection_ID    : Http_Client.Diagnostics.Diagnostic_ID;
      Rejection_Status : Http_Client.Errors.Result_Status)
      return Http_Client.Errors.Result_Status
   is
      Emit_Status : constant Http_Client.Errors.Result_Status :=
        Emit
          (Diagnostics,
           (Kind          => Http_Client.Diagnostics.Error_Event,
            Request_ID    => Request_ID,
            Connection_ID => Connection_ID,
            Result        => Rejection_Status,
            Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
            Message       => Http_Client.Diagnostics.To_Text
              ("HTTP/3 backend response rejected"),
            others        => <>));
   begin
      if Emit_Status /= Http_Client.Errors.Ok then
         return Emit_Status;
      end if;

      return Rejection_Status;
   end Emit_Backend_Response_Rejected;

   function Emit_Backend_Failed
     (Diagnostics          : Http_Client.Diagnostics.Context_Access;
      Request_ID           : Http_Client.Diagnostics.Diagnostic_ID;
      Connection_ID        : Http_Client.Diagnostics.Diagnostic_ID;
      Connect_Host         : String;
      Failure              : Http_Client.Errors.Result_Status;
      Elapsed_Milliseconds : Natural := 0)
      return Http_Client.Errors.Result_Status
   is
      Emit_Status : constant Http_Client.Errors.Result_Status :=
        Emit
          (Diagnostics,
           (Kind                 => Http_Client.Diagnostics.QUIC_Connection_Failed,
            Request_ID           => Request_ID,
            Connection_ID        => Connection_ID,
            URI_Or_Origin        => Http_Client.Diagnostics.To_Text (Connect_Host),
            Result               => Failure,
            Protocol             => Http_Client.Diagnostics.Protocol_HTTP_3,
            Elapsed_Milliseconds => Elapsed_Milliseconds,
            others               => <>));
   begin
      if Emit_Status /= Http_Client.Errors.Ok then
         return Emit_Status;
      end if;

      return Failure;
   end Emit_Backend_Failed;

   function Validate_Backend_Response
     (Request              : Http_Client.Requests.Request;
      Response             : Http_Client.Responses.Response;
      Max_Header_List_Size : Natural)
      return Http_Client.Errors.Result_Status
   is
      Response_Headers  : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Response_Trailers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Trailers (Response);
      Declared_Length   : Natural := 0;
      Bodyless          : Boolean;
      Status            : Http_Client.Errors.Result_Status;
   begin
      if Http_Client.Responses.Version (Response) /=
        Http_Client.Responses.HTTP_1_1
      then
         return Http_Client.Errors.HTTP3_Protocol_Error;
      elsif Has_Control (Http_Client.Responses.Reason_Phrase (Response)) then
         return Http_Client.Errors.HTTP3_Protocol_Error;
      elsif not Header_List_Size_Within_Limit
        (Response_Headers, Max_Header_List_Size)
        or else not Header_List_Size_Within_Limit
          (Response_Trailers, Max_Header_List_Size)
      then
         return Http_Client.Errors.Header_Too_Large;
      end if;

      for I in 1 .. Http_Client.Headers.Length (Response_Headers) loop
         declare
            Name : constant String :=
              Http_Client.Headers.Name_At (Response_Headers, I);
         begin
            if Name /= Lower (Name)
              or else (Name'Length > 0 and then Name (Name'First) = ':')
              or else Is_Forbidden_HTTP3_Response_Header (Name)
            then
               return Http_Client.Errors.Invalid_Header;
            end if;
         end;
      end loop;

      Bodyless := Response_Body_Is_Disallowed
        (Http_Client.Requests.Method (Request),
         Http_Client.Responses.Status_Code (Response));

      if Bodyless
        and then Http_Client.Responses.Response_Body (Response)'Length > 0
      then
         return Http_Client.Errors.HTTP3_Protocol_Error;
      end if;

      if Http_Client.Headers.Count (Response_Headers, "content-length") > 1
      then
         return Http_Client.Errors.HTTP3_Protocol_Error;
      elsif Http_Client.Headers.Contains (Response_Headers, "content-length")
      then
         if not Parse_Natural
           (Http_Client.Headers.Get (Response_Headers, "content-length"),
            Declared_Length)
         then
            return Http_Client.Errors.HTTP3_Protocol_Error;
         elsif not Bodyless
           and then Declared_Length /=
             Http_Client.Responses.Response_Body (Response)'Length
         then
            return Http_Client.Errors.HTTP3_Protocol_Error;
         end if;
      end if;

      Status := Http_Client.Headers.Validate_HTTP2_Trailers
        (Response_Trailers, Response => True);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Errors.Ok;
   end Validate_Backend_Response;


   function Execute_Buffered
     (Request                       : Http_Client.Requests.Request;
      Options                       : Http_Client.HTTP3.HTTP3_Options;
      Response                      : out Http_Client.Responses.Response;
      Proxy_Configured              : Boolean := False;
      SOCKS_Configured              : Boolean := False;
      Client_Certificate_Configured : Boolean := False;
      Alternative_Host              : String := "";
      Alternative_Port              : Natural := 0;
      Requires_Origin_TLS_Authority : Boolean := True;
      Max_Body_Size                 : Natural := 16_777_216;
      Diagnostics                   : Http_Client.Diagnostics.Context_Access := null;
      Request_ID                    : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID                 : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Backend                       : Buffered_Backend_Callback := null)
      return Http_Client.Errors.Result_Status
   is
      URI             : Http_Client.URI.URI_Reference;
      Status          : Http_Client.Errors.Result_Status;
      Request_Headers : Http_Client.Headers.Header_List;
      B               : Http_Client.Request_Bodies.Request_Body;
      Conn   : Http_Client.QUIC.Connection;
      Connect_Host : Ada.Strings.Unbounded.Unbounded_String;
      Connect_Port : Natural := 0;
      QUIC_Start_Time : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);

      function QUIC_Elapsed return Natural is
      begin
         if Diagnostics /= null
           and then Http_Client.Diagnostics.Is_Enabled (Diagnostics.all)
         then
            return Http_Client.Diagnostics.Elapsed_Milliseconds
              (Diagnostics.all,
               QUIC_Start_Time,
               Http_Client.Diagnostics.Now (Diagnostics.all));
         else
            return 0;
         end if;
      end QUIC_Elapsed;
   begin
      Response := Http_Client.Responses.Default_Response;

      if Max_Body_Size = 0 or else not Requires_Origin_TLS_Authority then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Alternative_Port > 65_535 then
         return Http_Client.Errors.Invalid_Configuration;
      elsif not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      URI := Http_Client.Requests.URI (Request);

      if not Http_Client.URI.Is_Parsed (URI) then
         return Http_Client.Errors.Invalid_URI;
      elsif not Http_Client.URI.Requires_TLS (URI) then
         return Http_Client.Errors.HTTP3_Unsupported;
      end if;

      if Alternative_Host'Length = 0 then
         Connect_Host := Ada.Strings.Unbounded.To_Unbounded_String
           (Http_Client.URI.Host (URI));
      else
         Connect_Host := Ada.Strings.Unbounded.To_Unbounded_String (Alternative_Host);
      end if;

      Connect_Port := (if Alternative_Port = 0
                       then Natural (Http_Client.URI.Effective_Port (URI))
                       else Alternative_Port);

      Status := Http_Client.HTTP3.Execution_Status
        (Options                       => Options,
         Proxy_Configured              => Proxy_Configured,
         SOCKS_Configured              => SOCKS_Configured,
         Client_Certificate_Configured => Client_Certificate_Configured);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif not Endpoint_Host_Text_Is_Valid
        (Ada.Strings.Unbounded.To_String (Connect_Host))
      then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Status := Http_Client.HTTP3.Mapping.Build_Request_Headers
        (Request => Request,
         Output  => Request_Headers);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif not Header_List_Size_Within_Limit
        (Request_Headers, Options.Max_Header_List_Size)
      then
         return Http_Client.Errors.Response_Too_Large;
      end if;

      --  This release only defines a buffered HTTP/3 execution contract. Reject
      --  producer-backed upload bodies before opening UDP sockets or creating
      --  QUIC streams. Do this after configuration/proxy policy validation so
      --  proxy-forbidden HTTP/3 requests are reported as proxy policy failures
      --  rather than as request-shape failures. Buffered in-memory bodies remain
      --  replayable and can be handed to a future backend implementation through
      --  this same boundary.
      B := Http_Client.Requests.Request_Body (Request);
      if Http_Client.Request_Bodies.Has_Trailers (B) then
         return Emit_HTTP3_Execution_Unsupported
           (Diagnostics   => Diagnostics,
            Request_ID    => Request_ID,
            Connection_ID => Connection_ID,
            Message       => "HTTP/3 request trailers unsupported");
      end if;

      case Http_Client.Request_Bodies.Kind (B) is
         when Http_Client.Request_Bodies.Empty_Body
            | Http_Client.Request_Bodies.Buffered_Body =>
            null;
         when Http_Client.Request_Bodies.Fixed_Length_Stream
            | Http_Client.Request_Bodies.Unknown_Length_Stream =>
            return Emit_HTTP3_Execution_Unsupported
              (Diagnostics   => Diagnostics,
               Request_ID    => Request_ID,
               Connection_ID => Connection_ID,
               Message       => "HTTP/3 streaming upload body unsupported");
      end case;

      --  If a future production backend makes Execution_Status return Ok, keep
      --  the first network transition centralized here. The current uploaded
      --  codebase has no selected QUIC backend, so Open still returns a precise
      --  unsupported status instead of faking HTTP/3 over the TCP/TLS stack.
      if Diagnostics /= null
        and then Http_Client.Diagnostics.Is_Enabled (Diagnostics.all)
      then
         QUIC_Start_Time := Http_Client.Diagnostics.Now (Diagnostics.all);
      end if;

      Status := Emit
        (Diagnostics,
         (Kind          => Http_Client.Diagnostics.QUIC_Connection_Start,
          Request_ID    => Request_ID,
          Connection_ID => Connection_ID,
          URI_Or_Origin => Http_Client.Diagnostics.To_Text
            (Ada.Strings.Unbounded.To_String (Connect_Host)),
          Protocol      => Http_Client.Diagnostics.Protocol_HTTP_3,
          others        => <>));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Backend /= null then
         Status := Backend
           (Request         => Request,
            Request_Headers => Request_Headers,
            Options         => Options,
            Connect_Host    => Ada.Strings.Unbounded.To_String (Connect_Host),
            Connect_Port    => Connect_Port,
            Max_Body_Size   => Max_Body_Size,
            Response        => Response);

         if Status /= Http_Client.Errors.Ok then
            Status := Emit_Backend_Failed
              (Diagnostics   => Diagnostics,
               Request_ID           => Request_ID,
               Connection_ID        => Connection_ID,
               Connect_Host         => Ada.Strings.Unbounded.To_String (Connect_Host),
               Failure              => Status,
               Elapsed_Milliseconds => QUIC_Elapsed);
            Response := Http_Client.Responses.Default_Response;
            return Status;
         elsif Http_Client.Responses.Response_Body (Response)'Length > Max_Body_Size then
            Status := Emit_Backend_Response_Rejected
              (Diagnostics      => Diagnostics,
               Request_ID       => Request_ID,
               Connection_ID    => Connection_ID,
               Rejection_Status => Http_Client.Errors.Response_Too_Large);
            Response := Http_Client.Responses.Default_Response;
            return Status;
         else
            Status := Validate_Backend_Response
              (Request              => Request,
               Response             => Response,
               Max_Header_List_Size => Options.Max_Header_List_Size);
            if Status /= Http_Client.Errors.Ok then
               Status := Emit_Backend_Response_Rejected
                 (Diagnostics      => Diagnostics,
                  Request_ID       => Request_ID,
                  Connection_ID    => Connection_ID,
                  Rejection_Status => Status);
               Response := Http_Client.Responses.Default_Response;
               return Status;
            end if;

            Status := Emit
              (Diagnostics,
               (Kind                => Http_Client.Diagnostics.Response_Headers_Received,
                Request_ID          => Request_ID,
                Connection_ID       => Connection_ID,
                Status_Code         =>
                  Natural (Http_Client.Responses.Status_Code (Response)),
                Response_Byte_Count =>
                  Http_Client.Responses.Response_Body (Response)'Length,
                Protocol            => Http_Client.Diagnostics.Protocol_HTTP_3,
                others              => <>));
            if Status /= Http_Client.Errors.Ok then
               Response := Http_Client.Responses.Default_Response;
               return Status;
            end if;
         end if;

         return Status;
      end if;

      Status := Http_Client.QUIC.Open
        (Conn    => Conn,
         Host    => Ada.Strings.Unbounded.To_String (Connect_Host),
         Port    => Connect_Port,
         Options => Options.QUIC);

      if Status /= Http_Client.Errors.Ok then
         Status := Emit_Backend_Failed
           (Diagnostics   => Diagnostics,
            Request_ID           => Request_ID,
            Connection_ID        => Connection_ID,
            Connect_Host         => Ada.Strings.Unbounded.To_String (Connect_Host),
            Failure              => Status,
            Elapsed_Milliseconds => QUIC_Elapsed);
         Http_Client.QUIC.Close (Conn);
         return Status;
      end if;

      --  No built-in production QUIC backend is linked into this crate. The
      --  optional Backend callback above is the audited insertion point for
      --  QUIC/TLS 1.3 and HTTP/3 stream I/O; the default path remains
      --  deterministic and must not fake HTTP/3 over TCP/TLS.
      Http_Client.QUIC.Close (Conn);
      return Http_Client.Errors.QUIC_Unsupported;
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         Http_Client.QUIC.Close (Conn);
         return Http_Client.Errors.Internal_Error;
   end Execute_Buffered;

end Http_Client.HTTP3.Execution;
