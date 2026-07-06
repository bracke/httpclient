with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Cancellation;
with Http_Client.Clients;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Body_Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Body_Streams;
with Http_Client.HTTP3.QPACK;
with Http_Client.HTTP3.Execution;
with Http_Client.QUIC;
with Http_Client.Proxies;
with Http_Client.Request_Bodies;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Responses;
with Http_Client.Retry;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.Types;
with Http_Client.URI;

procedure API_Stability_Compile is
   use type Http_Client.Clients.File_Durability_Mode;

   type Dummy_Producer is limited new Http_Client.Request_Bodies.Body_Producer with record
      Pos : Natural := 0;
   end record;

   overriding function Read_Some
     (Item   : in out Dummy_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;

   overriding function Reset
     (Item : in out Dummy_Producer) return Http_Client.Errors.Result_Status;

   overriding function Read_Some
     (Item   : in out Dummy_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status is
   begin
      Count := 0;
      if Item.Pos = 0 and then Buffer'Length > 0 then
         Buffer (Buffer'First) := 'x';
         Count := 1;
         Item.Pos := 1;
      end if;
      return Http_Client.Errors.Ok;
   end Read_Some;

   overriding function Reset
     (Item : in out Dummy_Producer) return Http_Client.Errors.Result_Status is
   begin
      Item.Pos := 0;
      return Http_Client.Errors.Ok;
   end Reset;

   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Errors.Result_Category;
   use type Http_Client.Clients.Download_File_Mode;

   URI_Value       : Http_Client.URI.URI_Reference;
   Headers         : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Trailers        : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request         : Http_Client.Requests.Request;
   Response        : Http_Client.Responses.Response := Http_Client.Responses.Default_Response;
   Client          : Http_Client.Clients.Client := Http_Client.Clients.Create;
   Client_Result   : Http_Client.Clients.Client_Result;
   Download_Result : Http_Client.Clients.Download_Result;
   Redirect_Result : Http_Client.Clients.Redirect_Result;
   Retry_Result    : Http_Client.Clients.Retry_Result;
   Bytes           : constant Ada.Streams.Stream_Element_Array (1 .. 4) := [1, 2, 3, 4];
   Response_Bytes  : Ada.Streams.Stream_Element_Array := Http_Client.Responses.Response_Body_Bytes (Response);
   Response_Header_Text : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
   Response_Metadata_Present : Boolean := False;
   Stream_Redirect_Count : Natural := 0;
   Stream_Retry_Attempt_Count : Natural := 0;
   Producer_A      : aliased Dummy_Producer;
   Producer_B      : aliased Dummy_Producer;
   Fixed_Body      : Http_Client.Request_Bodies.Request_Body;
   Chunked_Body    : Http_Client.Request_Bodies.Request_Body;
   Chunked_No_Trailers_Body : Http_Client.Request_Bodies.Request_Body;
   Binary_Body     : Http_Client.Request_Bodies.Request_Body;
   Config          : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Strict_Config   : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Strict_Client_Configuration;
   Status          : Http_Client.Errors.Result_Status;
   Token           : aliased Http_Client.Cancellation.Cancellation_Token;
   Diagnostics     : Http_Client.Diagnostics.Diagnostics_Context;
   Metrics         : Http_Client.Diagnostics.Metrics_Snapshot;
   Timings         : Http_Client.Diagnostics.Timing_Snapshot;
   Exec            : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
   Stream_Opts     : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   TLS             : Http_Client.Transports.TLS.TLS_Options :=
     Http_Client.Transports.TLS.Default_TLS_Options;
   Timeouts        : Http_Client.Transports.TCP.Timeout_Config :=
     Http_Client.Transports.TCP.Default_Timeouts;
   Proxy_HTTP      : Http_Client.Proxies.Proxy_Config := Http_Client.Proxies.HTTP ("proxy.example", 8080);
   Proxy_SOCKS     : Http_Client.Proxies.Proxy_Config :=
     Http_Client.Proxies.SOCKS5 ("socks.example", 1080, Http_Client.Proxies.SOCKS5_Remote_DNS);
   Retry_Opts      : Http_Client.Retry.Retry_Options := Http_Client.Retry.Default_Retry_Options;
   Redirect_Opts   : Http_Client.Clients.Redirect_Options := Http_Client.Clients.Default_Redirect_Options;
   Download_Opts   : Http_Client.Clients.Download_Options := Http_Client.Clients.Default_Download_Options;
   Download_Max    : Natural := Http_Client.Clients.Default_Max_Download_Size;
   Strict_Redirects : Http_Client.Clients.Redirect_Options := Http_Client.Clients.Strict_Redirect_Options;
   Deflate_Mode    : Http_Client.Decompression.Deflate_Decoding_Mode :=
     Http_Client.Decompression.Zlib_Wrapped_Only;
   Decomp          : Http_Client.Decompression.Decompression_Options :=
     Http_Client.Decompression.Default_Decompression_Options;
   H2              : Http_Client.HTTP2.HTTP2_Options := Http_Client.HTTP2.Default_HTTP2_Options;
   H2_Conn         : Http_Client.HTTP2.Connection.Connection_State;
   H3              : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   H3_Forced       : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   Stream          : Http_Client.Response_Streams.Streaming_Response;
   H2_Stream       : Http_Client.HTTP2.Body_Streams.Body_Stream;
   H3_Stream       : Http_Client.HTTP3.Body_Streams.Body_Stream;
   H3_Response     : Http_Client.Responses.Response;
   H3_Field        : Http_Client.HTTP3.QPACK.Header_Field;
   H3_Used         : Natural := 0;
   Buffer          : Ada.Streams.Stream_Element_Array (1 .. 64);
   Last            : Ada.Streams.Stream_Element_Offset;
   Text_Body       : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
   URL_Text        : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
begin
   Status := Http_Client.URI.Parse ("https://example.com/repo.git/info/refs?service=git-upload-pack", URI_Value);
   Status := Http_Client.Headers.Set (Headers, "Accept", "application/x-git-upload-pack-advertisement");
   Status := Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2");
   Status := Http_Client.Headers.Set (Headers, "Expect", "100-continue");
   Status := Http_Client.Headers.Set (Trailers, "X-Git-SHA256", "abc123");
   Deflate_Mode := Http_Client.Decompression.Raw_Only;
   Deflate_Mode := Http_Client.Decompression.Auto_Zlib_Then_Raw;
   Decomp.Deflate_Mode := Deflate_Mode;

   Status := Http_Client.Requests.Create
     (Method  => Http_Client.Types.GET,
      URI     => URI_Value,
      Item    => Request,
      Headers => Headers);

   Binary_Body := Http_Client.Request_Bodies.From_Bytes (Bytes);
   Status := Http_Client.Requests.Set_Body (Request, Binary_Body);
   Response_Bytes := Http_Client.Responses.Response_Body_Bytes (Response);
   Response_Header_Text := Ada.Strings.Unbounded.To_Unbounded_String
     (Http_Client.Responses.Header (Response, "Content-Type")
      & Http_Client.Responses.Content_Type (Response)
      & Http_Client.Responses.Media_Type (Response)
      & Http_Client.Responses.Charset (Response));
   Response_Metadata_Present :=
     Http_Client.Responses.Has_Header (Response, "Content-Type")
     or else Http_Client.Responses.Has_Content_Type (Response)
     or else Http_Client.Responses.Has_Charset (Response);

   Fixed_Body := Http_Client.Request_Bodies.From_Fixed_Length_Stream
     (Producer   => Producer_A'Unchecked_Access,
      Length     => 1,
      Replayable => True);
   Status := Http_Client.Requests.Set_Body (Request, Fixed_Body);

   Chunked_No_Trailers_Body := Http_Client.Request_Bodies.From_Unknown_Length_Stream
     (Producer   => Producer_B'Unchecked_Access,
      Replayable => False);
   Status := Http_Client.Requests.Set_Body (Request, Chunked_No_Trailers_Body);

   Chunked_Body := Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
     (Producer   => Producer_B'Unchecked_Access,
      Trailers   => Trailers,
      Replayable => False);
   Status := Http_Client.Requests.Set_Body (Request, Chunked_Body);

   Timeouts.Connect := 1_000;
   Timeouts.Read := 1_000;
   Timeouts.Write := 1_000;
   TLS.Timeouts := Timeouts;
   TLS.CA_File := Ada.Strings.Unbounded.To_Unbounded_String ("/tmp/ca.pem");
   TLS.CA_Directory := Ada.Strings.Unbounded.To_Unbounded_String ("/tmp/certs");
   TLS.Send_SNI := True;
   TLS.HTTP2 := H2;

   Config.Execution.Timeouts := Timeouts;
   Status := Http_Client.Clients.Set_Default_Header (Config, "User-Agent", "httpclient-api-stability");
   Status := Http_Client.Clients.Remove_Default_Header (Config, "User-Agent");
   Status := Http_Client.Clients.Validate (Config);
   Status := Http_Client.Clients.Configure (Client, Config);

   Http_Client.Cancellation.Cancel (Token);
   if not Http_Client.Cancellation.Is_Cancelled (Token) then
      raise Program_Error;
   end if;
   Http_Client.Cancellation.Reset (Token);

   Http_Client.Diagnostics.Initialize (Diagnostics, Enabled => True, Observer => null);
   Metrics := Http_Client.Diagnostics.Snapshot (Diagnostics);
   Timings := Http_Client.Diagnostics.Timing (Diagnostics);
   if Metrics.Requests_Started /= 0
     or else Http_Client.Diagnostics.Average_Request_Milliseconds (Timings) /= 0
     or else Http_Client.Diagnostics.Average_TLS_Handshake_Milliseconds (Timings) /= 0
   then
      raise Program_Error;
   end if;

   Exec.Timeouts := Timeouts;
   Exec.Cancellation := Token'Unchecked_Access;
   Exec.TLS := TLS;
   Exec.Proxy := Proxy_HTTP;
   Exec.Protocol_Policy := Http_Client.Clients.Force_HTTP_1_1;
   Exec.Advertise_Accept_Encoding := False;

   Stream_Opts.Timeouts := Timeouts;
   Stream_Opts.Cancellation := Token'Unchecked_Access;
   Stream_Opts.TLS := TLS;
   Stream_Opts.Proxy := Proxy_SOCKS;
   Stream_Opts.Enable_Decompression := False;
   Stream_Opts.Protocol_Policy := Http_Client.Response_Streams.Streaming_HTTP_1_1_Only;

   Retry_Opts.Enable_Retries := True;
   Retry_Opts.Maximum_Attempts := 2;
   Redirect_Opts.Follow_Redirects := True;
   Redirect_Opts.Allow_Body_Replay := False;
   Download_Max := Http_Client.Clients.Default_Max_Download_Size;
   Download_Opts.Max_Download_Size := Download_Max;
   Download_Opts.File_Mode := Http_Client.Clients.Replace_Atomically;
   Download_Opts.Durability := Http_Client.Clients.File_Durability_Sync_Data_And_Directory;
   Download_Opts.Require_Success_Status := True;
   Download_Opts.Create_Parent_Dirs := True;
   Download_Opts.Enable_Resume := False;
   Download_Opts.Resume_If_Range := Ada.Strings.Unbounded.To_Unbounded_String ("""etag""");
   if Download_Opts.File_Mode /= Http_Client.Clients.Replace_Atomically then
      raise Program_Error;
   end if;
   if Download_Opts.Durability /= Http_Client.Clients.File_Durability_Sync_Data_And_Directory then
      raise Program_Error;
   end if;
   Download_Result :=
     (Status        => Http_Client.Errors.Ok,
      Response      => Response,
      Final_URI     => URI_Value,
      HTTP_Status_Code    => 200,
      Expected_Final_Size => 0,
      Redirect_Count      => 0,
      Retry_Attempt_Count => 0,
      Resumed             => False,
      Resume_Offset       => 0,
      Bytes_Written       => 0,
      Final_Size          => 0);
   Decomp.Unsupported_Policy := Http_Client.Decompression.Leave_Encoded;
   H2.Mode := Http_Client.HTTP2.HTTP2_Allowed;
   H2.Enable_Public_Streaming := True;
   H2.Enable_Upload_Streaming := True;
   H2.Max_Per_Stream_Buffered_Bytes := 1024;
   H2.Max_Total_Queued_Body_Bytes := 4096;
   H2_Conn := Http_Client.HTTP2.Connection.Create (H2);
   Status := (if Http_Client.HTTP2.Connection.Total_Buffered_Response_Bytes (H2_Conn) = 0
              then Http_Client.Errors.Ok else Http_Client.Errors.Internal_Error);
   Status := (if not Http_Client.HTTP2.Connection.Response_Trailers_Received (H2_Conn, 1)
              then Http_Client.Errors.Ok else Http_Client.Errors.Internal_Error);
   Trailers := Http_Client.Responses.Trailers (Response);
   H3.Mode := Http_Client.HTTP3.HTTP3_Allowed;
   H3.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
   H3_Forced.Mode := Http_Client.HTTP3.HTTP3_Required;
   H3_Forced.Fallback := Http_Client.HTTP3.Fallback_Disallowed;
   H3_Forced.QUIC.Backend := Http_Client.QUIC.Backend_Unavailable;
   if Config.Redirects.Follow_Redirects
     and then Config.Enable_Decompression
     and then not Strict_Config.Redirects.Follow_Redirects
     and then not Strict_Config.Enable_Decompression
     and then not Strict_Redirects.Follow_Redirects
   then
      null;
   end if;

   Text_Body := Ada.Strings.Unbounded.To_Unbounded_String
     (Http_Client.Clients.Response_Text (Client_Result));
   URL_Text := Ada.Strings.Unbounded.To_Unbounded_String
     (Http_Client.Clients.Final_URL (Client_Result));
   Status := Http_Client.Clients.Get
     (URL           => "https://example.com/",
      Result        => Client_Result,
      Configuration => Strict_Config);
   Status := Http_Client.Clients.Head
     (URL           => "https://example.com/",
      Result        => Client_Result,
      Configuration => Strict_Config);

   Config.HTTP3 := H3_Forced;
   Config.Execution.Protocol_Policy := Http_Client.Clients.Force_HTTP_3;
   Exec.Protocol_Policy := Http_Client.Clients.Prefer_HTTP_3;
   Stream_Opts.HTTP3 := H3_Forced;
   Stream_Opts.Protocol_Policy := Http_Client.Response_Streams.Streaming_Force_HTTP_3;

   if False then
      Status := Http_Client.Clients.Execute
        (Item => Client, Request => Request, Response => Response, Options => Exec);
      Status := Http_Client.Clients.Execute_Once
        (Request => Request, Response => Response, Options => Exec);
      Status := Http_Client.Clients.Execute_With_Retry
        (Item => Client, Request => Request, Result => Retry_Result,
         Execution => Exec, Retries => Retry_Opts);
      Download_Opts.Expected_Size := 0;
      Download_Opts.Verify_SHA256 := False;
      Download_Opts.Expected_SHA256_Hex := (others => '0');
      Download_Opts.Progress_Callback := null;
      Download_Opts.Progress_Interval_Bytes := 0;
      Download_Opts.Cancellation := Token'Unchecked_Access;

      Status := Http_Client.Clients.Execute_Once_With_Retry
        (Request => Request, Result => Retry_Result, Execution => Exec, Retries => Retry_Opts);
      Status := Http_Client.Clients.Execute_With_Redirects
        (Item => Client, Request => Request, Result => Redirect_Result,
         Execution => Exec, Redirects => Redirect_Opts);
      Status := Http_Client.Clients.Execute
        (Item => Client, Request => Request, Result => Client_Result);
      Status := Http_Client.Clients.Head
        (Item => Client, URL => "https://example.com/", Result => Client_Result);
      Status := Http_Client.Clients.Execute_Stream
        (Request => Request, Stream => Stream, Options => Exec);
      Status := Http_Client.Clients.Execute_Stream
        (Item => Client, Request => Request, Stream => Stream);
      Status := Http_Client.Clients.Execute_To_File
        (Item    => Client,
         Request => Request,
         Path    => "/tmp/http_client_api_stability_download.bin",
         Result  => Download_Result,
         Options => Download_Opts);
      Status := Http_Client.Clients.Download_To_File
        (Item    => Client,
         URL     => "https://example.com/file.bin",
         Path    => "/tmp/http_client_api_stability_download.bin",
         Result  => Download_Result,
         Options => Download_Opts);
      Status := Http_Client.Clients.Download_To_File
        (URL           => "https://example.com/file.bin",
         Path          => "/tmp/http_client_api_stability_download.bin",
         Result        => Download_Result,
         Options       => Download_Opts,
         Configuration => Strict_Config);
      Status := Http_Client.Response_Streams.Open
        (Request => Request, Stream => Stream, Options => Stream_Opts);
      Stream_Redirect_Count := Http_Client.Response_Streams.Redirect_Count (Stream);
      Stream_Retry_Attempt_Count := Http_Client.Response_Streams.Retry_Attempt_Count (Stream);
      Status := Http_Client.Response_Streams.Read_Some (Stream => Stream, Buffer => Buffer, Last => Last);
      if Stream_Redirect_Count > 0 or else Stream_Retry_Attempt_Count > 0 then
         null;
      end if;
      Status := Http_Client.Response_Streams.Close (Stream);
   end if;

   Status := Http_Client.Transports.TLS.Validate_Options (TLS);
   Status := Http_Client.Proxies.With_Proxy_Authorization (Proxy_HTTP, "Basic token", Proxy_HTTP);
   Status := Http_Client.Proxies.With_SOCKS5_Username_Password (Proxy_SOCKS, "user", "pass", Proxy_SOCKS);
   Status := Http_Client.HTTP2.Validate (H2);
   Status := Http_Client.HTTP3.Validate (H3);
   Status := Http_Client.HTTP3.Execution_Status (H3_Forced);
   Status := Http_Client.HTTP3.Fallback_Status (H3_Forced, Request_Bytes_Already_Sent => False);
   Status := Http_Client.HTTP3.Execution.Execute_Buffered
     (Request          => Request,
      Options          => H3_Forced,
      Response         => H3_Response,
      Proxy_Configured => False,
      SOCKS_Configured => False);
   Status := Http_Client.HTTP3.Execution.Execute_Buffered
     (Request          => Request,
      Options          => H3_Forced,
      Response         => H3_Response,
      Proxy_Configured => True);
   Status := Http_Client.HTTP3.QPACK.Decode_Literal_Field_Line
     ("" & Character'Val (16#80#), H3_Field, H3_Used);
   Status := Http_Client.HTTP3.Body_Streams.Open (H3_Stream, Max_Body_Size => 64);
   Status := Http_Client.HTTP3.Body_Streams.Append_Data (H3_Stream, Bytes);
   Status := Http_Client.HTTP3.Body_Streams.Mark_End_Stream (H3_Stream);
   Status := Http_Client.HTTP3.Body_Streams.Read_Some (H3_Stream, Buffer, Last);
   Status := Http_Client.HTTP3.Body_Streams.Close (H3_Stream);
   Status := Http_Client.HTTP2.Body_Streams.Read_Some (H2_Stream, Buffer, Last);

   if Http_Client.Errors.Category (Http_Client.Errors.Cancelled) /= Http_Client.Errors.Transport_Category then
      raise Program_Error;
   end if;

   if Status = Http_Client.Errors.Internal_Error and then Response_Bytes'Length = 999_999 then
      raise Program_Error;
   end if;

   if Response_Metadata_Present
     and then Ada.Strings.Unbounded.Length (Response_Header_Text) = 999_999
   then
      raise Program_Error;
   end if;
end API_Stability_Compile;
