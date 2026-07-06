with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Check_Support;
with Project_Tools.Tree_Checks;

procedure Check_Git_Smart_HTTP_Release is
   Root     : constant String := ".";
   Docs     : constant String := Root & "/docs";
   Src      : constant String := Root & "/src";
   Tests    : constant String := Root & "/tests/src";
   API_Tests : constant String := Root & "/tests/api_stability";
   Examples : constant String := Root & "/examples/src";
   Errors   : Natural := 0;

   type String_Access is access constant String;

   Required_Docs : constant array (Positive range <>) of String_Access :=
     [new String'("GIT_SMART_HTTP_PUBLIC_API_INVENTORY.md"),
      new String'("DOWNLOAD_TO_FILE.md"),
      new String'("GIT_SMART_HTTP_INTEGRATION_CONTRACT.md"),
      new String'("GIT_SMART_HTTP_FINAL_AUDIT_PASS.md"),
      new String'("GIT_SMART_HTTP_FINAL_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_RELEASE_TOOLING_PASS.md"),
      new String'("GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_STREAMING_DECOMPRESSION_PASS.md"),
      new String'("GIT_SMART_HTTP_STREAMING_RAW_DEFLATE_PASS.md"),
      new String'("GIT_SMART_HTTP_ADA_ZLIB_DECOMPRESSION_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTPS_CONNECT_STREAMING_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTPS_SOCKS_STREAMING_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP1_PROTOCOL_POLICY_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP2_HTTP3_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP2_HTTP3_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP2_STREAM_BYTE_ARRAY_PASS.md"),
      new String'("GIT_SMART_HTTP_REQUEST_TRAILERS_PASS.md"),
      new String'("GIT_SMART_HTTP_REQUEST_TRAILERS_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_PASS.md"),
      new String'("GIT_SMART_HTTP_HTTP2_HTTP3_STREAMING_PARITY_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE4_DIRECT_TLS_FIXTURE_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE5_HTTP_CONNECT_TLS_FIXTURE_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE5_HTTP_CONNECT_TLS_FIXTURE_COMPLETENESS_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE6_HTTPS_SOCKS5_TLS_FIXTURE_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE9_HTTP2_MULTIPLEXING_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE10_HTTP2_TRAILERS_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE11_HTTP3_BOUNDARY_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md"),
      new String'("GIT_SMART_HTTP_PHASE14_COMPILE_TARGETED_EXAMPLES_PASS.md"),
      new String'("INCOMPLETE_CONTENT_AUDIT.md")];

   Required_All_Examples : constant array (Positive range <>) of String_Access :=
     [new String'("alt_svc_parse.adb"),
      new String'("async_submit.adb"),
      new String'("basic_auth.adb"),
      new String'("bearer_auth.adb"),
      new String'("cache_config.adb"),
      new String'("client_certificate_config.adb"),
      new String'("connection_pool_policy.adb"),
      new String'("cookie_session.adb"),
      new String'("decompression_config.adb"),
      new String'("diagnostics_observer.adb"),
      new String'("download_to_file.adb"),
      new String'("digest_auth.adb"),
      new String'("enable_http2.adb"),
      new String'("enable_http3_experimental.adb"),
      new String'("http3_force_no_backend.adb"),
      new String'("http3_prefer_with_fallback.adb"),
      new String'("encrypted_cache_config.adb"),
      new String'("http_proxy_config.adb"),
      new String'("https_svcb_record.adb"),
      new String'("manual_request.adb"),
      new String'("multipart_upload.adb"),
      new String'("pac_wpad_config.adb"),
      new String'("persistent_cache_config.adb"),
      new String'("protocol_discovery_config.adb"),
      new String'("redirect_client.adb"),
      new String'("retry_policy.adb"),
      new String'("simple_get.adb"),
      new String'("socks_proxy_config.adb"),
      new String'("stabilized_defaults.adb"),
      new String'("status_categories.adb"),
      new String'("git_info_refs_stream.adb"),
      new String'("git_info_refs_https_proxy_stream.adb"),
      new String'("git_info_refs_https_socks_stream.adb"),
      new String'("git_info_refs_http3_buffered.adb"),
      new String'("git_info_refs_http2_buffered.adb"),
      new String'("git_upload_pack_http2_stream.adb"),
      new String'("git_upload_pack_stream.adb"),
      new String'("git_receive_pack_fixed_upload.adb"),
      new String'("git_receive_pack_chunked_upload.adb"),
      new String'("git_receive_pack_chunked_upload_trailers.adb"),
      new String'("git_info_refs_http3_stream.adb"),
      new String'("streaming_download.adb"),
      new String'("streaming_upload.adb"),
      new String'("streaming_get_with_cancellation.adb"),
      new String'("git_info_refs_streaming_get.adb"),
      new String'("git_upload_pack_post_buffered.adb"),
      new String'("git_chunked_upload_with_trailers.adb"),
      new String'("git_receive_pack_expect_continue.adb"),
      new String'("git_https_custom_ca.adb"),
      new String'("git_https_proxy_connect.adb"),
      new String'("git_socks5_https.adb"),
      new String'("git_streaming_decompression.adb"),
      new String'("git_http2_streaming_fetch_shape.adb"),
      new String'("git_redirect_policy.adb"),
      new String'("git_retry_policy.adb"),
      new String'("git_streaming_with_timeout_and_cancellation.adb"),
      new String'("git_binary_safe_transport_shape.adb")];

   Required_Examples : constant array (Positive range <>) of String_Access :=
     [new String'("git_info_refs_stream.adb"),
      new String'("git_upload_pack_stream.adb"),
      new String'("git_receive_pack_fixed_upload.adb"),
      new String'("git_receive_pack_chunked_upload.adb"),
      new String'("git_receive_pack_chunked_upload_trailers.adb"),
      new String'("git_info_refs_https_proxy_stream.adb"),
      new String'("git_info_refs_https_socks_stream.adb"),
      new String'("git_info_refs_http2_buffered.adb"),
      new String'("git_info_refs_http3_buffered.adb"),
      new String'("git_upload_pack_http2_stream.adb"),
      new String'("git_info_refs_http3_stream.adb"),
      new String'("http3_force_no_backend.adb"),
      new String'("http3_prefer_with_fallback.adb"),
      new String'("git_info_refs_streaming_get.adb"),
      new String'("git_upload_pack_post_buffered.adb"),
      new String'("git_chunked_upload_with_trailers.adb"),
      new String'("git_receive_pack_expect_continue.adb"),
      new String'("git_https_custom_ca.adb"),
      new String'("git_https_proxy_connect.adb"),
      new String'("git_socks5_https.adb"),
      new String'("git_streaming_decompression.adb"),
      new String'("git_http2_streaming_fetch_shape.adb"),
      new String'("git_redirect_policy.adb"),
      new String'("git_retry_policy.adb"),
      new String'("git_streaming_with_timeout_and_cancellation.adb"),
      new String'("git_binary_safe_transport_shape.adb")];

   Required_Source_Tokens : constant array (Positive range <>) of String_Access :=
     [new String'("type Protocol_Selection_Policy"),
      new String'("Force_HTTP_1_1"),
      new String'("Prefer_HTTP_2"),
      new String'("Force_HTTP_2"),
      new String'("Prefer_HTTP_3"),
      new String'("Force_HTTP_3"),
      new String'("type Streaming_Protocol_Policy"),
      new String'("Streaming_HTTP_1_1_Only"),
      new String'("Streaming_Prefer_HTTP_2"),
      new String'("Streaming_Force_HTTP_2"),
      new String'("Streaming_Prefer_HTTP_3"),
      new String'("Streaming_Force_HTTP_3"),
      new String'("Enable_Decompression"),
      new String'("Open_Through_HTTP_Proxy"),
      new String'("Open_Through_SOCKS_Proxy"),
      new String'("Transfer-Encoding"),
      new String'("100-continue"),
      new String'("From_Unknown_Length_Stream_With_Trailers"),
      new String'("Declared_Trailers_Cover_All"),
      new String'("Trailer_Fields_Are_Valid"),
      new String'("Stream_Element_Array"),
      new String'("Http_Client.HTTP3.Body_Streams"),
      new String'("Raw_Deflate"),
      new String'("Auto_Zlib_Then_Raw"),
      new String'("Transport_Attached_Reuse_Available"),
      new String'("Pool_Request_Count"),
      new String'("Secret_Fingerprint"),
      new String'("Http_Client.Cancellation"),
      new String'("Cancellation_Token_Access"),
      new String'("Cancelled"),
      new String'("Max_Total_Queued_Body_Bytes"),
      new String'("Total_Buffered_Response_Bytes"),
      new String'("Send_Trailers"),
      new String'("Response_Trailers_Received"),
      new String'("HTTP3_Proxy_Unsupported"),
      new String'("QUIC_Unsupported"),
      new String'("Redirect_Body_Replay_Disallowed"),
      new String'("Redirect_Downgrade_Blocked"),
      new String'("Retry_Body_Not_Replayable"),
      new String'("Git-Protocol"),
      new String'("Download_To_File"),
      new String'("Max_Download_Size"),
      new String'("Default_Max_Download_Size"),
      new String'("Replace_Atomically")];

   Required_Test_Tokens : constant array (Positive range <>) of String_Access :=
     [new String'("Git_Pkt_Line"),
      new String'("Chunked"),
      new String'("Expect_Chunked"),
      new String'("HTTPS_Proxy_CONNECT"),
      new String'("HTTPS_SOCKS"),
      new String'("Decompression"),
      new String'("Force_HTTP1"),
      new String'("HTTP2_Git"),
      new String'("HTTP3_Git"),
      new String'("X-Git-SHA256"),
      new String'("explicit Trailer declaration must cover all attached trailer fields"),
      new String'("Trailer header without attached request trailers must be rejected"),
      new String'("Force_HTTP2_Rejects_Plain_HTTP"),
      new String'("HTTP2_Body_Stream_Byte_Array"),
      new String'("HTTP3_Body_Stream_Byte_Array"),
      new String'("Response_Stream_Protocol_Policy_Force_HTTP2"),
      new String'("Response_Stream_Protocol_Policy_Force_HTTP3"),
      new String'("Test_Decompression_Raw_Deflate_Policy"),
      new String'("Raw_Only"),
      new String'("Auto_Zlib_Then_Raw"),
      new String'("Test_Response_Stream_Split_Chunk_Metadata_Tiny_Buffer"),
      new String'("Test_Response_Stream_Chunked_Trailer_Line_Limit"),
      new String'("Test_Response_Stream_Chunked_Trailer_Total_Limit"),
      new String'("Content_Length_Zero"),
      new String'("Close_Delimited"),
      new String'("Git_Pkt_Line_Chunked_Binary"),
      new String'("Transport_Attached_Reuse_Available"),
      new String'("Test_Connection_Pool_Response_Reuse_Predicate"),
      new String'("Test_Connection_Pool_Key_Security_Boundaries"),
      new String'("Test_Buffered_Pre_Cancelled_Execute"),
      new String'("Test_Streaming_Pre_Cancelled_Open"),
      new String'("Test_Cancelled_Status_Category"),
      new String'("Test_Cancellation_Is_Not_Retryable"),
      new String'("Test_Default_Cancellation_Fields_Are_Null"),
      new String'("Test_Default_Timeouts_Are_Disabled"),
      new String'("Test_Timeout_Retry_Classification_Obeys_Policy"),
      new String'("Test_HTTP2_Multiplexed_Interleaved_Data_And_Reset"),
      new String'("Test_HTTP2_Multiplexed_Flow_Control_And_Settings"),
      new String'("Test_HTTP2_Multiplexed_Goaway_Allows_Accepted_Stream_Completion"),
      new String'("Test_HTTP2_Total_Queued_Body_Limit_Is_Connection_Wide"),
      new String'("Test_HTTP2_Upload_Body_Streaming"),
      new String'("Test_HTTP2_Body_Stream_Byte_Array_Read_Preserves_Git_Bytes"),
      new String'("Force_HTTP2_Rejects_Plain_HTTP"),
      new String'("Test_Request_Trailers_Empty_Body"),
      new String'("Test_Request_Trailers_Buffered_Body"),
      new String'("Test_Request_Trailer_Forbidden_Names"),
      new String'("Test_Response_Trailers_After_Data"),
      new String'("Test_Response_Trailer_Pseudo_Rejected"),
      new String'("Test_Response_Trailer_Content_Length_Rejected"),
      new String'("Test_Data_After_Response_Trailers_Rejected"),
      new String'("Test_Response_Trailers_Interleaved_With_Other_Stream"),
      new String'("Test_HTTP3_Force_No_Backend_Fails_Deterministically"),
      new String'("Test_HTTP3_Force_No_Fallback_To_HTTP2"),
      new String'("Test_HTTP3_Force_No_Fallback_To_HTTP1"),
      new String'("Test_HTTP3_Streaming_Force_No_Backend_Fails_Deterministically"),
      new String'("Test_HTTP3_Buffered_Force_No_Backend_Fails_Deterministically"),
      new String'("Test_HTTP3_Execute_Once_Force_No_Backend_Fails_Deterministically"),
      new String'("Test_HTTP3_Force_With_HTTP_Proxy_Does_Not_Bypass_Proxy"),
      new String'("Test_HTTP3_Force_With_SOCKS5_Proxy_Does_Not_Bypass_Proxy"),
      new String'("Test_HTTP3_Prefer_Fallback_Uses_Configured_HTTP_Proxy"),
      new String'("Test_HTTP3_Prefer_Fallback_Uses_Configured_SOCKS5_Proxy"),
      new String'("Test_HTTP3_Prefer_Fallback_Disabled_Fails_Deterministically"),
      new String'("Test_HTTP3_Fallback_After_Request_Bytes_Disallowed"),
      new String'("Test_HTTP3_Experimental_Unsafe_Features_Rejected"),
      new String'("Test_HTTP3_No_Backend_Not_Retried_As_HTTP1"),
      new String'("Test_HTTP3_Redirect_Keeps_Forced_Policy"),
      new String'("Test_HTTP3_Body_Stream_Byte_Array_API_Compiles"),
      new String'("Test_HTTP3_Body_Stream_No_Backend_Read_Fails_Deterministically"),
      new String'("Test_HTTP3_QPACK_Unsupported_Dynamic_Feature_Fails_Deterministically"),
      new String'("Test_Client_Redirect_Disabled_Returns_302"),
      new String'("Test_Client_Redirect_Missing_Location_Is_Invalid"),
      new String'("Test_Client_Redirect_307_Body_Replay_Disallowed"),
      new String'("Test_Client_Redirect_303_Preserves_HEAD"),
      new String'("Test_Client_Redirect_303_Post_Drops_Body_Headers"),
      new String'("Test_Client_Redirect_308_Replays_Body_When_Allowed"),
      new String'("Test_Client_Cross_Origin_Redirect_Strips_Credentials"),
      new String'("Test_Download_To_File_Defaults_And_Uninitialized_Guard"),
      new String'("Test_Client_Redirect_Max_Count"),
      new String'("Test_Client_Retry_Disabled_Remains_One_Attempt"),
      new String'("Test_Retry_Failure_Classification"),
      new String'("Test_Retry_Response_Status_Classification"),
      new String'("Test_Retry_Non_Retryable_Security_And_Protocol_Failures"),
      new String'("Test_Client_Retry_Post_503_Not_Retried_By_Default"),
      new String'("Test_Cancellation_Is_Not_Retryable"),
      new String'("Test_HTTP3_No_Backend_Not_Retried_As_HTTP1"),
      new String'("Http_Client.Binary_Safety_Tests"),
      new String'("All_Bytes"),
      new String'("Test_Request_Response_NUL_High_Byte_Preservation"),
      new String'("Test_CRLFCRLF_Body_Boundary_Preservation"),
      new String'("Test_Duplicate_Content_Length_And_TE_CL_Rejection"),
      new String'("Test_Header_CRLF_Injection_Rejection"),
      new String'("Test_HTTP2_Header_Validation_Rejects_Transfer_Framing"),
      new String'("Transfer-Encoding plus Content-Length rejected"),
      new String'("duplicate conflicting Content-Length rejected"),
      new String'("Git packfile-like")];


   Required_API_Stability_Tokens : constant array (Positive range <>) of String_Access :=
     [new String'("Execute"),
      new String'("Execute_With_Retry"),
      new String'("Execute_Stream"),
      new String'("Response_Streams.Read_Some"),
      new String'("From_Fixed_Length_Stream"),
      new String'("From_Unknown_Length_Stream_With_Trailers"),
      new String'("X-Git-SHA256"),
      new String'("TLS_Options"),
      new String'("Proxies.HTTP"),
      new String'("Proxies.SOCKS5"),
      new String'("Decompression_Options"),
      new String'("Deflate_Decoding_Mode"),
      new String'("Auto_Zlib_Then_Raw"),
      new String'("HTTP2_Options"),
      new String'("HTTP3_Options"),
      new String'("Cancellation_Token"),
      new String'("Cancelled"),
      new String'("Max_Total_Queued_Body_Bytes"),
      new String'("Total_Buffered_Response_Bytes"),
      new String'("Response_Trailers_Received"),
      new String'("Responses.Trailers"),
      new String'("Force_HTTP_3"),
      new String'("Streaming_Force_HTTP_3"),
      new String'("HTTP3.Execution_Status"),
      new String'("HTTP3.Fallback_Status"),
      new String'("HTTP3.Execution.Execute_Buffered"),
      new String'("HTTP3.Body_Streams.Append_Data"),
      new String'("HTTP3.QPACK.Decode_Literal_Field_Line")];

   C_Zlib_Forbidden_Tokens : constant Project_Tools.Tree_Checks.Text_List :=
     [To_Unbounded_String ("http_client_zlib_bridge.c"),
      To_Unbounded_String ("-lz"),
      To_Unbounded_String ("http_client_zlib_stream_create"),
      To_Unbounded_String ("http_client_zlib_stream_decode")];

   procedure Require_File (Path : String; Purpose : String) is
   begin
      if not Check_Support.File_Exists (Path) then
         Check_Support.Error (Errors, "missing " & Purpose & ": " & Path);
      end if;
   end Require_File;

   procedure Require_Text
     (Path    : String;
      Pattern : String;
      Purpose : String) is
   begin
      Check_Support.Require_File_Contains
        (Errors  => Errors,
         Path    => Path,
         Pattern => Pattern,
         Message => Purpose & " missing token '" & Pattern & "' in " & Path);
   end Require_Text;

   procedure Require_No_Text
     (Text    : String;
      Pattern : String;
      Purpose : String) is
   begin
      if Check_Support.Contains (Text, Pattern) then
         Check_Support.Error (Errors, Purpose & " must not contain '" & Pattern & "'");
      end if;
   end Require_No_Text;

   procedure Require_No_Downstream_Adapter_Scope
     (Directory : String;
      Purpose   : String) is
      Search : Ada.Directories.Search_Type;
      E      : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Directory,
         Pattern   => "*",
         Filter    => [Ada.Directories.Directory => True,
                       Ada.Directories.Ordinary_File => True,
                       others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, E);
         declare
            Name : constant String := Ada.Directories.Simple_Name (E);
            Full : constant String := Ada.Directories.Full_Name (E);
         begin
            if Name /= "." and then Name /= ".." then
               if Ada.Directories.Kind (E) = Ada.Directories.Directory then
                  if Name /= "obj" and then Name /= "bin" and then Name /= ".git" then
                     Require_No_Downstream_Adapter_Scope (Full, Purpose);
                  end if;
               else
                  declare
                     Text : constant String := To_String (Check_Support.Read_File (Full));
                  begin
                     if Check_Support.Contains (Text, "Version.Transport.Http")
                       and then not Check_Support.Contains (Full, "GIT_SMART_HTTP")
                       and then not Check_Support.Contains (Full, "check_git_smart_http_release.adb")
                     then
                        Check_Support.Error
                          (Errors, Purpose & " contains downstream adapter scope wording outside Git docs: " & Full);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         Check_Support.Error (Errors, "could not scan " & Purpose & ": " & Directory);
   end Require_No_Downstream_Adapter_Scope;

   function Read (Path : String) return String is
   begin
      return To_String (Check_Support.Read_File (Path));
   end Read;

begin
   for Doc of Required_Docs loop
      Require_File (Docs & "/" & Doc.all, "Git smart HTTP release document");
      Require_Text
        (Docs & "/DOCUMENTATION_INDEX.md", Doc.all,
         "documentation index must link every Git smart HTTP release document");
   end loop;

   for Example of Required_All_Examples loop
      Require_File (Examples & "/" & Example.all, "compile-checked example");
      Require_Text
        (Root & "/examples/examples.gpr", Example.all,
         "examples project must compile every documented example");
      Require_Text
        (Docs & "/EXAMPLES.md", Example.all,
         "examples documentation must mention every compile-checked example");
   end loop;

   for Example of Required_Examples loop
      Require_File (Examples & "/" & Example.all, "Git smart HTTP example");
      Require_Text
        (Root & "/examples/examples.gpr", Example.all,
         "examples project must compile every Git smart HTTP example");
      Require_Text
        (Docs & "/EXAMPLES.md", Example.all,
         "examples documentation must mention every Git smart HTTP example");
      Require_Text
        (Root & "/README.md", Example.all,
         "README must mention every Git smart HTTP example");

      declare
         Example_Text : constant String := Read (Examples & "/" & Example.all);
      begin
         Require_No_Text
           (Example_Text, "Response_Body",
            "Git smart HTTP examples must use byte-array streaming, not string response helpers");
         Require_No_Text
           (Example_Text, "Disable_Certificate_Verification := True",
            "positive HTTPS Git examples must not disable TLS verification");
         Require_No_Text
           (Example_Text, "Disable_Certificate_Verification=>True",
            "positive HTTPS Git examples must not disable TLS verification");
         Require_No_Text
           (Example_Text, "https://example.com",
            "compile-targeted Git examples must avoid public example.com origins");
      end;
   end loop;


   Require_Text
     (Examples & "/git_info_refs_streaming_get.adb",
      "Read_Some",
      "Phase 14 info/refs example must use byte-array Read_Some");
   Require_Text
     (Examples & "/git_upload_pack_post_buffered.adb",
      "Request_Bodies.From_Bytes",
      "Phase 14 upload-pack example must use From_Bytes");
   Require_Text
     (Examples & "/git_receive_pack_fixed_upload.adb",
      "From_Fixed_Length_Stream",
      "Phase 14 fixed upload example must use fixed-length stream body");
   Require_Text
     (Examples & "/git_receive_pack_chunked_upload.adb",
      "From_Unknown_Length_Stream",
      "Phase 14 chunked upload example must use unknown-length stream body");
   Require_Text
     (Examples & "/git_chunked_upload_with_trailers.adb",
      "From_Unknown_Length_Stream_With_Trailers",
      "Phase 14 trailers example must use request trailers API");
   Require_Text
     (Examples & "/git_receive_pack_expect_continue.adb",
      "100-continue",
      "Phase 14 Expect example must show explicit Expect header");
   Require_Text
     (Examples & "/git_https_custom_ca.adb",
      "CA_File",
      "Phase 14 custom CA example must configure CA_File");
   Require_Text
     (Examples & "/git_https_proxy_connect.adb",
      "Proxies.HTTP",
      "Phase 14 CONNECT example must configure HTTP proxy");
   Require_Text
     (Examples & "/git_socks5_https.adb",
      "With_SOCKS5_Username_Password",
      "Phase 14 SOCKS example must keep SOCKS credentials in proxy config");
   Require_Text
     (Examples & "/git_streaming_decompression.adb",
      "Enable_Decompression := True",
      "Phase 14 decompression example must opt in explicitly");
   Require_Text
     (Examples & "/git_http2_streaming_fetch_shape.adb",
      "Streaming_Force_HTTP_2",
      "Phase 14 HTTP/2 example must opt in explicitly");
   Require_Text
     (Examples & "/http3_force_no_backend.adb",
      "experimental/backend-dependent",
      "Phase 14 HTTP/3 example must label backend-dependent behavior");
   Require_Text
     (Examples & "/git_redirect_policy.adb",
      "Allow_HTTPS_To_HTTP_Redirects := False",
      "Phase 14 redirect example must block HTTPS downgrade");
   Require_Text
     (Examples & "/git_retry_policy.adb",
      "Enable_Retries := True",
      "Phase 14 retry example must show explicit retry opt-in");
   Require_Text
     (Examples & "/git_streaming_with_timeout_and_cancellation.adb",
      "Cancellation",
      "Phase 14 timeout/cancellation example must use cancellation field");
   Require_Text
     (Examples & "/git_binary_safe_transport_shape.adb",
      "16#FF#",
      "Phase 14 binary-safe example must include high-byte data");
   Require_Text
     (Docs & "/RELEASE_VERIFICATION.md",
      "examples/examples.gpr",
      "release verification must include examples project build instruction");

   declare
      Client_Spec  : constant String := Read (Src & "/http_client-clients.ads");
      Stream_Spec  : constant String := Read (Src & "/http_client-response_streams.ads");
      TLS_Spec     : constant String := Read (Src & "/http_client-transports-tls.ads");
      Bodies_Spec  : constant String := Read (Src & "/http_client-request_bodies.ads");
      HTTP2_Spec   : constant String :=
        Read (Src & "/http_client-http2.ads") &
        Read (Src & "/http_client-http2-connection.ads");
      Reader_Body  : constant String := Read (Src & "/http_client-http1-reader.adb");
      HTTP1_Body    : constant String := Read (Src & "/http_client-http1.adb");
      Pools_Source  : constant String :=
        Read (Src & "/http_client-connection_pools.ads") &
        Read (Src & "/http_client-connection_pools.adb");
      Clients_Body : constant String := Read (Src & "/http_client-clients.adb");
      Streams_Body : constant String := Read (Src & "/http_client-response_streams.adb") &
        Read (Src & "/http_client-http3-body_streams.ads") &
        Read (Src & "/http_client-http3-body_streams.adb") &
        Read (Src & "/http_client-http3.ads") &
        Read (Src & "/http_client-http3.adb") &
        Read (Src & "/http_client-http3-execution.adb") &
        Read (Src & "/http_client-quic.ads") &
        Read (Src & "/http_client-quic.adb");
      All_Source   : constant String :=
        Client_Spec & Stream_Spec & TLS_Spec & Bodies_Spec & HTTP2_Spec &
        Reader_Body & HTTP1_Body & Pools_Source & Clients_Body & Streams_Body;
   begin
      for Token of Required_Source_Tokens loop
         if not Check_Support.Contains (All_Source, Token.all) then
            Check_Support.Error (Errors, "Git smart HTTP source surface missing token: " & Token.all);
         end if;
      end loop;

      Require_No_Text (All_Source, "Unsupported_Feature, -- chunked", "source contract");
      Require_No_Text (All_Source, "chunked request upload remains unsupported", "source contract");
   end;

   declare
      Test_Text : constant String :=
        Read (Tests & "/http_client-http1-tests.adb") &
        Read (Tests & "/http_client-http2-tests.adb") &
        Read (Tests & "/http_client-http2-trailers_tests.adb") &
        Read (Tests & "/http_client-connection_pools-tests.adb") &
        Read (Tests & "/http_client-http3-tests.adb") &
        Read (Tests & "/http_client-http3-boundary_tests.adb") &
        Read (Tests & "/http_client-requests_headers-tests.adb") &
        Read (Tests & "/http_client-response_streams-tests.adb") &
        Read (Tests & "/http_client-decompression-tests.adb") &
        Read (Tests & "/http_client-clients-tests.adb") &
        Read (Tests & "/http_client-cancellation_tests.adb") &
        Read (Tests & "/http_client-timeout_tests.adb") &
        Read (Tests & "/http_client-redirects-tests.adb") &
        Read (Tests & "/http_client-retry-tests.adb") &
        Read (Tests & "/http_client-binary_safety_tests.adb") &
        Read (Tests & "/http_client-binary_test_data.adb");
   begin
      for Token of Required_Test_Tokens loop
         if not Check_Support.Contains (Test_Text, Token.all) then
            Check_Support.Error (Errors, "Git smart HTTP AUnit coverage missing token: " & Token.all);
         end if;
      end loop;
   end;

   Require_File
     (Src & "/http_client-cancellation.ads",
      "Phase 8 cancellation package");
   Require_File
     (Tests & "/http_client-cancellation_tests.adb",
      "Phase 8 cancellation AUnit tests");
   Require_File
     (Tests & "/http_client-timeout_tests.adb",
      "Phase 8 timeout AUnit tests");

   Require_File
     (API_Tests & "/api_stability.gpr",
      "API stability compile project");
   Require_File
     (API_Tests & "/src/api_stability_compile.adb",
      "API stability compile source");
   Require_Text
     (Docs & "/RELEASE_VERIFICATION.md",
      "tests/api_stability/api_stability.gpr",
      "release verification must include API stability project");

   declare
      API_Text : constant String := Read (API_Tests & "/src/api_stability_compile.adb");
   begin
      for Token of Required_API_Stability_Tokens loop
         if not Check_Support.Contains (API_Text, Token.all) then
            Check_Support.Error (Errors, "API stability source missing token: " & Token.all);
         end if;
      end loop;
   end;

   Require_Text (Root & "/alire.toml", "zlib =", "crate must depend on Ada Zlib");
   Require_Text (Root & "/httpclient.gpr", "with ""zlib"";", "root project must use Ada Zlib project");
   Require_Text
     (Docs & "/RELEASE_VERIFICATION.md",
      "Git smart HTTP release checks",
      "release verification must include Git smart HTTP checks");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_FINAL_COMPLETENESS_PASS.md",
      "Version.Transport.Http",
      "final completeness doc must explicitly keep downstream adapter out of scope");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_RELEASE_TOOLING_COMPLETENESS_PASS.md",
      "check_git_smart_http_release",
      "release tooling completeness doc must describe the Git smart HTTP release guard");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_INTEGRATION_CONTRACT.md",
      "Force_HTTP_1_1",
      "Git contract must recommend HTTP/1.1 protocol policy");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_INTEGRATION_CONTRACT.md",
      "Accept-Encoding: identity",
      "Git contract must document identity encoding recommendation");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE11_HTTP3_BOUNDARY_PASS.md",
      "Force_HTTP_3",
      "Phase 11 document must describe forced HTTP/3 no-fallback behavior");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE11_HTTP3_BOUNDARY_PASS.md",
      "HTTP3_Proxy_Unsupported",
      "Phase 11 document must describe proxy no-bypass status");
   Require_Text
     (Docs & "/HTTP3_EXPERIMENTAL.md",
      "no production QUIC backend",
      "HTTP/3 docs must clearly state backend-dependent/no-backend status");
   Require_Text
     (Tests & "/http_suite.adb",
      "Http_Client.HTTP3.Boundary_Tests.Section_Test_Case",
      "Phase 11 HTTP/3 boundary test suite must be registered");
   Require_Text
     (Examples & "/http3_force_no_backend.adb",
      "experimental/backend-dependent",
      "forced HTTP/3 example must label HTTP/3 as experimental/backend-dependent");
   Require_Text
     (Examples & "/http3_prefer_with_fallback.adb",
      "preserving the configured HTTP proxy route",
      "prefer HTTP/3 fallback example must document proxy-preserving fallback");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md",
      "Redirects are disabled by default",
      "Phase 12 docs must describe redirect default safety");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md",
      "Retries are disabled by default",
      "Phase 12 docs must describe retry default safety");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md",
      "HTTPS-to-HTTP redirects are blocked by default",
      "Phase 12 docs must describe downgrade blocking");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE12_REDIRECT_RETRY_SAFETY_PASS.md",
      "Git-Protocol",
      "Phase 12 docs must describe Git-Protocol cross-origin stripping");

   Require_File
     (Tests & "/http_client-binary_safety_tests.adb",
      "Phase 13 binary safety AUnit tests");
   Require_File
     (Tests & "/http_client-binary_test_data.adb",
      "Phase 13 all-byte binary corpus helper");
   Require_Text
     (Tests & "/http_suite.adb",
      "Http_Client.Binary_Safety_Tests.Section_Test_Case",
      "Phase 13 binary safety test suite must be registered");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md",
      "byte-array APIs are the Git-safe body APIs",
      "Phase 13 document must identify byte-array APIs as Git-safe");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md",
      "CRLFCRLF",
      "Phase 13 document must describe header/body boundary coverage");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE13_HEADER_BINARY_SAFETY_PASS.md",
      "Diagnostics must not log request or response body bytes by default",
      "Phase 13 document must describe diagnostics body redaction policy");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_INTEGRATION_CONTRACT.md",
      "Ada.Streams.Stream_Element_Array request and response APIs as authoritative",
      "Git contract must document authoritative byte-array APIs");
   Require_Text
     (Docs & "/streaming-and-uploads.md",
      "Body bytes are opaque",
      "streaming docs must document body byte opacity");
   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "HTTP/2 DATA payloads are the only response/request body bytes",
      "HTTP/2 guide must document DATA/body separation");

   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "HPACK decoding accepts both raw and RFC 7541 static-Huffman",
      "HTTP/2 guide must document HPACK Huffman decoding support");
   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "Malformed Huffman payloads",
      "HTTP/2 guide must document malformed Huffman error handling");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "RFC 7541 C.6.1 Huffman response example should decode",
      "HTTP/2 tests must cover RFC response Huffman examples");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "scripted HTTP/2 response with Huffman HPACK headers should execute successfully",
      "HTTP/2 tests must cover Huffman HPACK through the response execution path");

   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "RST_STREAM handling preserves retry-safe REFUSED_STREAM semantics",
      "HTTP/2 guide must document REFUSED_STREAM reset handling");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "RST_STREAM REFUSED_STREAM should produce retry-safe HTTP2_Stream_Refused",
      "HTTP/2 tests must cover REFUSED_STREAM reset mapping");

   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "single-stream HTTP/2 should ignore RST_STREAM for unrelated stream IDs",
      "HTTP/2 tests must preserve unrelated RST_STREAM isolation");

   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "RST_STREAM frames are mapped to the most specific existing result status",
      "HTTP/2 guide must document specific RST_STREAM status mapping");
   Require_Text
     (Src & "/http_client-http2-frames.adb",
      "function RST_Stream_Status",
      "HTTP/2 frame layer must preserve RST_STREAM error-code semantics");

   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "HTTP/2 TLS reads and writes now honor configured TLS/TCP read and write timeout intent",
      "HTTP/2 guide must document TLS timeout-bound stalled peer behavior");
   Require_Text
     (Src & "/c/http_client_tls_bridge.c",
      "HC_TLS_TIMEOUT",
      "TLS bridge must expose timeout returns for stalled TLS I/O");

   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "HTTP/2 request HPACK should use RFC-style static indexed pseudo-header order before authority literal",
      "HTTP/2 tests must cover static-table request HPACK encoding");
   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "static-table indexes for common request pseudo-header names",
      "HTTP/2 guide must document static-table request HPACK encoding");
   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "Expect: 100-continue is not forwarded on HTTP/2 requests",
      "HTTP/2 guide must document Expect normalization");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "HTTP/2 request mapping must not forward Expect: 100-continue",
      "HTTP/2 tests must cover Expect normalization");

   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "single-stream HTTP/2 serializes fixed-length producer request bodies as DATA before END_STREAM",
      "HTTP/2 guide must document producer request body DATA serialization");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "single-stream HTTP/2 should serialize producer request bodies as DATA before END_STREAM",
      "HTTP/2 tests must cover producer request body DATA serialization");

   Require_Text
     (Src & "/http_client-http2-connection.ads",
      "function Credit_Response_Data",
      "HTTP/2 connection model must expose response DATA WINDOW_UPDATE crediting");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "consuming already-credited DATA must not grow the connection window",
      "HTTP/2 tests must prevent DATA WINDOW_UPDATE double-credit regressions");
   Require_Text
     (Docs & "/http2.md",
      "explicit response-DATA crediting",
      "HTTP/2 docs must describe response DATA crediting for WINDOW_UPDATE transports");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE9_HTTP2_MULTIPLEXING_PASS.md",
      "Max_Total_Queued_Body_Bytes",
      "Phase 9 document must describe aggregate HTTP/2 queued-body bounding");
   Require_Text
     (Docs & "/HTTP2_GUIDE.md",
      "Max_Total_Queued_Body_Bytes",
      "HTTP/2 guide must describe aggregate queued-body limit");
   Require_Text
     (Docs & "/RELEASE_VERIFICATION.md",
      "Phase 9 HTTP/2 multiplexing verification",
      "release verification must include Phase 9 HTTP/2 multiplexing gate");
   Require_Text
     (Tests & "/http_client-http2-tests.adb",
      "Test_HTTP2_Multiplexed_Headers_Metadata_Not_Counted",
      "Phase 9 tests must cover padded/priority HEADERS metadata accounting");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE9_HTTP2_MULTIPLEXING_PASS.md",
      "padded/priority HEADERS metadata",
      "Phase 9 document must describe padded/priority HEADERS metadata accounting");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE10_HTTP2_TRAILERS_PASS.md",
      "trailing HEADERS",
      "Phase 10 document must describe HTTP/2 trailers as trailing HEADERS");
   Require_Text
     (Tests & "/http_client-http2-trailers_tests.adb",
      "Test_Request_Trailers_Empty_Body",
      "Phase 10 tests must cover HTTP/2 request trailers");
   Require_Text
     (Tests & "/http_client-http2-trailers_tests.adb",
      "Test_Response_Trailers_After_Data",
      "Phase 10 tests must cover response trailers not exposed as body");
   Require_Text
     (Tests & "/http_client-http2-trailers_tests.adb",
      "Test_Response_Trailers_Interleaved_With_Other_Stream",
      "Phase 10 tests must cover multiplexed trailer isolation");
   Require_Text
     (Src & "/http_client-http2-connection.ads",
      "Send_Trailers",
      "Phase 10 source must expose HTTP/2 trailing HEADERS accounting");
   Require_Text
     (Src & "/http_client-headers.ads",
      "Validate_HTTP2_Trailers",
      "Phase 10 source must validate HTTP/2 trailer names");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md",
      "split chunk-size metadata",
      "Phase 3 document must describe split chunk metadata coverage");
   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE3_STREAMING_CORRECTNESS_PASS.md",
      "Header_Too_Large",
      "Phase 3 document must include deterministic trailer-size wording or marker");


   -- Phase 16 packaging policy: project-owned C test fixtures are not
   -- included.  The production OpenSSL bridge remains allowed.  Local
   -- TLS/CONNECT/SOCKS coverage is restored through Ada task-based fixtures.
   if Check_Support.File_Exists (Root & "/tests/src/http_client_tls_fixture.c") then
      Check_Support.Error (Errors, "C TLS test fixture must not be packaged");
   end if;
   if Check_Support.File_Exists (Root & "/tests/src/http_client_connect_proxy_fixture.c") then
      Check_Support.Error (Errors, "C CONNECT proxy test fixture must not be packaged");
   end if;
   if Check_Support.File_Exists (Root & "/tests/src/http_client_socks5_proxy_fixture.c") then
      Check_Support.Error (Errors, "C SOCKS5 proxy test fixture must not be packaged");
   end if;
   Require_No_Text (Read (Root & "/tests/tests.gpr"), "-pthread", "tests project");
   Require_No_Text
     (Read (Root & "/tests/src/http_client-tls-tests.adb"),
      "External_Name => ""hctls_",
      "direct TLS tests must call Ada fixture APIs, not C fixture symbols");
   Require_No_Text
     (Read (Root & "/tests/src/http_client-connect_tls_tests.adb"),
      "External_Name => ""hcp_",
      "CONNECT TLS tests must call Ada fixture APIs, not C fixture symbols");
   Require_No_Text
     (Read (Root & "/tests/src/http_client-socks5_tls_tests.adb"),
      "External_Name => ""hcs5_",
      "SOCKS5 TLS tests must call Ada fixture APIs, not C fixture symbols");
   Require_Text
     (Root & "/tests/src/http_client-ada_test_fixtures.ads",
      "function Start_TLS",
      "Ada fixture spec must expose direct Ada fixture-control APIs");
   Require_Text
     (Root & "/tests/src/http_client-ada_test_fixtures.adb",
      "task type TLS_Server",
      "Ada TLS fixture must use an Ada task");
   Require_Text
     (Root & "/tests/src/http_client-ada_test_fixtures.adb",
      "task type Proxy_Server",
      "Ada CONNECT proxy fixture must use an Ada task");
   Require_Text
     (Root & "/tests/src/http_client-ada_test_fixtures.adb",
      "task type SOCKS_Server",
      "Ada SOCKS5 fixture must use an Ada task");
   Require_Text (Root & "/tests/src/http_suite.adb", "Connect_TLS_Tests", "AUnit suite");
   Require_Text (Root & "/tests/src/http_suite.adb", "SOCKS5_TLS_Tests", "AUnit suite");
   Require_Text (Root & "/tests/src/http_suite.adb", "TLS.Tests", "AUnit suite");
   Require_Text
     (Docs & "/PHASE16_ADA_ONLY_TEST_FIXTURE_BASELINE.md",
      "Ada task-based fixtures",
      "Phase 16 Ada-only fixture baseline must document restored fixture policy");

   Require_Text
     (Docs & "/GIT_SMART_HTTP_PHASE7_CONNECTION_POOLING_PASS.md",
      "transport-attached connection reuse",
      "Phase 7 docs must state real transport-attached reuse");
   Require_Text
     (Src & "/http_client-clients.adb",
      "Release_TCP",
      "Phase 7 client must release TCP handles through the real pool path");
   Require_Text
     (Src & "/http_client-clients.adb",
      "Pool_Request_Count",
      "Phase 7 client must preserve per-connection request counts");
   Require_Text
     (Src & "/http_client-connection_pools.adb",
      "Secret_Fingerprint",
      "Phase 7 pool key must avoid storing raw SOCKS passwords");

   if Check_Support.File_Exists (Src & "/c/http_client_zlib_bridge.c") then
      Check_Support.Error (Errors, "C zlib bridge source must not be packaged");
   end if;

   Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
     (Errors, Src, C_Zlib_Forbidden_Tokens, "production source");
   Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
     (Errors, Tests, C_Zlib_Forbidden_Tokens, "test source");
   Project_Tools.Tree_Checks.Check_No_Forbidden_Tokens
     (Errors, Examples, C_Zlib_Forbidden_Tokens, "example source");
   Require_No_Downstream_Adapter_Scope (Src, "production source");
   Require_No_Downstream_Adapter_Scope (Tests, "test source");
   Require_No_Downstream_Adapter_Scope (Examples, "example source");
   Require_No_Text (Read (Root & "/httpclient.gpr"), "-lz", "root project");
   Require_No_Text (Read (Root & "/tests/tests.gpr"), "-lz", "tests project");
   Require_No_Text (Read (Root & "/examples/examples.gpr"), "-lz", "examples project");
   Require_No_Text (Read (Root & "/benchmarks/http_client_benchmarks.gpr"), "-lz", "benchmark project");

   if Errors = 0 then
      Ada.Text_IO.Put_Line ("Git smart HTTP release checks passed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "Git smart HTTP release checks failed:" & Natural'Image (Errors) & " error(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Check_Git_Smart_HTTP_Release;
-- release guard token: HTTP/2 request HPACK should use RFC-style static indexed pseudo-header order before authority literal
