with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO;

with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.HTTP2;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

procedure Interop_Runner is
   use type Http_Client.Errors.Result_Status;

   type Probe_Kind is
     (Buffered_HTTP,
      Buffered_HTTPS,
      Buffered_HTTP2_Required,
      Streaming_HTTP,
      HTTP_Proxy,
      SOCKS5_Proxy,
      HTTP3_Required_Boundary);

   type Probe_Summary is record
      Ran     : Natural := 0;
      Passed  : Natural := 0;
      Failed  : Natural := 0;
      Skipped : Natural := 0;
   end record;

   function Env (Name : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name) then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return "";
   end Env;

   function Has_Only_Case (Name : String) return Boolean is
   begin
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (I) = "--case=" & Name then
            return True;
         end if;
      end loop;
      return False;
   end Has_Only_Case;

   function Has_Any_Case_Filter return Boolean is
   begin
      for I in 1 .. Ada.Command_Line.Argument_Count loop
         if Ada.Command_Line.Argument (I)'Length > 7
           and then Ada.Command_Line.Argument (I) (1 .. 7) = "--case="
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Any_Case_Filter;

   function Should_Run (Name : String) return Boolean is
   begin
      return (not Has_Any_Case_Filter) or else Has_Only_Case (Name);
   end Should_Run;

   function Make_Get
     (URL     : String;
      Request : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse (URL, URI);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Requests.Create
        (Method => Http_Client.Types.GET,
         URI    => URI,
         Item   => Request);
   end Make_Get;

   procedure Print_Result
     (Name    : String;
      Outcome : String;
      Detail  : String)
   is
   begin
      Ada.Text_IO.Put_Line (Outcome & " " & Name & " " & Detail);
   end Print_Result;

   procedure Mark_Skip
     (Summary : in out Probe_Summary;
      Name    : String;
      Reason  : String)
   is
   begin
      Summary.Skipped := Summary.Skipped + 1;
      Print_Result (Name, "SKIP", Reason);
   end Mark_Skip;

   procedure Mark_Fail
     (Summary : in out Probe_Summary;
      Name    : String;
      Status  : Http_Client.Errors.Result_Status)
   is
   begin
      Summary.Ran := Summary.Ran + 1;
      Summary.Failed := Summary.Failed + 1;
      Print_Result (Name, "FAIL", Http_Client.Errors.Result_Status'Image (Status));
   end Mark_Fail;

   procedure Mark_Pass
     (Summary     : in out Probe_Summary;
      Name        : String;
      Status_Code : Http_Client.Types.Status_Code;
      Body_Bytes  : Natural)
   is
   begin
      Summary.Ran := Summary.Ran + 1;
      Summary.Passed := Summary.Passed + 1;
      Print_Result
        (Name,
         "PASS",
         "status="
         & Http_Client.Types.Status_Code'Image (Status_Code)
         & " body_bytes="
         & Natural'Image (Body_Bytes));
   end Mark_Pass;

   procedure Run_Buffered
     (Summary : in out Probe_Summary;
      Name    : String;
      URL     : String;
      Kind    : Probe_Kind;
      Proxy   : Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.No_Proxy_Config)
   is
      Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Strict_Client_Configuration;
      Request : Http_Client.Requests.Request;
      Result  : Http_Client.Clients.Client_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if URL = "" then
         Mark_Skip (Summary, Name, "missing endpoint");
         return;
      end if;

      Config.Execution.Max_Body_Size := 64 * 1024 * 1024;
      Config.Execution.Max_Response_Size := 64 * 1024 * 1024;
      Config.Execution.Proxy := Proxy;

      case Kind is
         when Buffered_HTTP2_Required =>
            Config.Execution.Protocol_Policy :=
              Http_Client.Clients.Force_HTTP_2;
            Config.Execution.TLS.HTTP2.Mode :=
              Http_Client.HTTP2.HTTP2_Required;
         when HTTP3_Required_Boundary =>
            Config.Execution.Protocol_Policy :=
              Http_Client.Clients.Force_HTTP_3;
         when others =>
            Config.Execution.Protocol_Policy :=
              Http_Client.Clients.Protocol_From_Configuration;
      end case;

      Status := Http_Client.Clients.Configure (Client, Config);
      if Status = Http_Client.Errors.Ok then
         Status := Make_Get (URL, Request);
      end if;
      if Status = Http_Client.Errors.Ok then
         Status := Http_Client.Clients.Execute (Client, Request, Result);
      end if;

      if Status = Http_Client.Errors.Ok then
         Mark_Pass
           (Summary,
            Name,
            Http_Client.Responses.Status_Code (Result.Response),
            Http_Client.Responses.Response_Body (Result.Response)'Length);
      elsif Kind = HTTP3_Required_Boundary
        and then Status = Http_Client.Errors.QUIC_Unsupported
      then
         Summary.Ran := Summary.Ran + 1;
         Summary.Passed := Summary.Passed + 1;
         Print_Result (Name, "PASS", "deterministic " & Status'Image);
      else
         Mark_Fail (Summary, Name, Status);
      end if;
   end Run_Buffered;

   procedure Run_Streaming
     (Summary : in out Probe_Summary;
      Name    : String;
      URL     : String)
   is
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Buffer  : String (1 .. 16 * 1024);
      Last    : Natural;
      Bytes   : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if URL = "" then
         Mark_Skip (Summary, Name, "missing endpoint");
         return;
      end if;

      Options.Max_Body_Size := 64 * 1024 * 1024;
      Status := Make_Get (URL, Request);
      if Status = Http_Client.Errors.Ok then
         Status := Http_Client.Response_Streams.Open
           (Request => Request,
            Stream  => Stream,
            Options => Options);
      end if;

      if Status /= Http_Client.Errors.Ok then
         Mark_Fail (Summary, Name, Status);
         return;
      end if;

      loop
         Status := Http_Client.Response_Streams.Read_Some
           (Stream, Buffer, Last);
         exit when Status = Http_Client.Errors.End_Of_Stream;
         if Status /= Http_Client.Errors.Ok then
            declare
               Close_Status : constant Http_Client.Errors.Result_Status :=
                 Http_Client.Response_Streams.Close (Stream);
            begin
               pragma Unreferenced (Close_Status);
            end;
            Mark_Fail (Summary, Name, Status);
            return;
         end if;
         Bytes := Bytes + Last;
      end loop;

      declare
         Code : constant Http_Client.Types.Status_Code :=
           Http_Client.Response_Streams.Status_Code (Stream);
         Close_Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.Response_Streams.Close (Stream);
      begin
         if Close_Status /= Http_Client.Errors.Ok then
            Mark_Fail (Summary, Name, Close_Status);
         else
            Mark_Pass (Summary, Name, Code, Bytes);
         end if;
      end;
   end Run_Streaming;

   procedure Run_Proxy
     (Summary   : in out Probe_Summary;
      Name      : String;
      Target    : String;
      Proxy_URL : String)
   is
      Proxy  : Http_Client.Proxies.Proxy_Config;
      Status : Http_Client.Errors.Result_Status;
   begin
      if Target = "" or else Proxy_URL = "" then
         Mark_Skip (Summary, Name, "missing target or proxy endpoint");
         return;
      end if;

      Status := Http_Client.Proxies.Parse (Proxy_URL, Proxy);
      if Status /= Http_Client.Errors.Ok then
         Mark_Fail (Summary, Name, Status);
         return;
      end if;

      Run_Buffered (Summary, Name, Target, HTTP_Proxy, Proxy);
   end Run_Proxy;

   Summary : Probe_Summary;
begin
   if Should_Run ("http") then
      Run_Buffered
        (Summary, "http", Env ("HTTPCLIENT_INTEROP_HTTP_URL"), Buffered_HTTP);
   end if;

   if Should_Run ("https") then
      Run_Buffered
        (Summary, "https", Env ("HTTPCLIENT_INTEROP_HTTPS_URL"), Buffered_HTTPS);
   end if;

   if Should_Run ("http2") then
      Run_Buffered
        (Summary,
         "http2",
         Env ("HTTPCLIENT_INTEROP_HTTP2_URL"),
         Buffered_HTTP2_Required);
   end if;

   if Should_Run ("stream") then
      declare
         Stream_URL : constant String := Env ("HTTPCLIENT_INTEROP_STREAM_URL");
      begin
         Run_Streaming
           (Summary,
            "stream",
            (if Stream_URL /= "" then Stream_URL
             else Env ("HTTPCLIENT_INTEROP_HTTP_URL")));
      end;
   end if;

   if Should_Run ("http-proxy") then
      Run_Proxy
        (Summary,
         "http-proxy",
         Env ("HTTPCLIENT_INTEROP_PROXY_TARGET_URL"),
         Env ("HTTPCLIENT_INTEROP_HTTP_PROXY_URL"));
   end if;

   if Should_Run ("socks5-proxy") then
      Run_Proxy
        (Summary,
         "socks5-proxy",
         Env ("HTTPCLIENT_INTEROP_PROXY_TARGET_URL"),
         Env ("HTTPCLIENT_INTEROP_SOCKS5_PROXY_URL"));
   end if;

   if Should_Run ("http3-boundary") then
      Run_Buffered
        (Summary,
         "http3-boundary",
         Env ("HTTPCLIENT_INTEROP_HTTP3_URL"),
         HTTP3_Required_Boundary);
   end if;

   Ada.Text_IO.Put_Line
     ("SUMMARY ran="
      & Natural'Image (Summary.Ran)
      & " passed="
      & Natural'Image (Summary.Passed)
      & " failed="
      & Natural'Image (Summary.Failed)
      & " skipped="
      & Natural'Image (Summary.Skipped));

   if Summary.Failed /= 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Interop_Runner;
