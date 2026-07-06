with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Check_Support;
with Project_Tools.AUnit_Checks;

procedure Check_AUnit_Suite is
   use Ada.Strings.Unbounded;
   Root     : constant String := ".";
   Test_Dir : constant String := Root & "/tests/src";
   Errors   : Natural := 0;

   type String_Access is access constant String;
   Required_Section_Files : constant array (Positive range <>) of String_Access :=
     [new String'("http_client-uri-tests.adb"),
      new String'("http_client-requests_headers-tests.adb"),
      new String'("http_client-http1-tests.adb"),
      new String'("http_client-redirects-tests.adb"),
      new String'("http_client-retry-tests.adb"),
      new String'("http_client-cookies-tests.adb"),
      new String'("http_client-decompression-tests.adb"),
      new String'("http_client-proxies-tests.adb"),
      new String'("http_client-proxies-socks-tests.adb"),
      new String'("http_client-auth-tests.adb"),
      new String'("http_client-response_streams-tests.adb"),
      new String'("http_client-request_bodies-tests.adb"),
      new String'("http_client-multipart-tests.adb"),
      new String'("http_client-connection_pools-tests.adb"),
      new String'("http_client-cache-tests.adb"),
      new String'("http_client-cache-persistent-tests.adb"),
      new String'("http_client-diagnostics-tests.adb"),
      new String'("http_client-async-tests.adb"),
      new String'("http_client-http2-tests.adb"),
      new String'("http_client-http3-tests.adb"),
      new String'("http_client-protocol_discovery-tests.adb"),
      new String'("http_client-security_corpus-tests.adb"),
      new String'("http_client-conformance-tests.adb"),
      new String'("http_client-release_core-tests.adb"),
      new String'("http_client-resources-tests.adb")];

   Required_Areas : constant array (Positive range <>) of String_Access :=
     [new String'("Root_Package"),
      new String'("Release_Public_API_Stability_Surface"),
      new String'("URI_Parse"),
      new String'("Header"),
      new String'("Request"),
      new String'("HTTP1_"),
      new String'("TLS"),
      new String'("Redirect"),
      new String'("Cookie"),
      new String'("Decompression"),
      new String'("Proxy_Config"),
      new String'("SOCKS"),
      new String'("Retry"),
      new String'("Auth"),
      new String'("Client_"),
      new String'("Stream"),
      new String'("Upload"),
      new String'("Multipart"),
      new String'("Pool"),
      new String'("Cache_"),
      new String'("Persistent_Cache"),
      new String'("Encrypted_Persistent_Cache"),
      new String'("Diagnostics"),
      new String'("Resource"),
      new String'("Async"),
      new String'("HTTP2"),
      new String'("HTTP3"),
      new String'("Alt_Svc"),
      new String'("SVCB"),
      new String'("Security_Corpus"),
      new String'("Conformance_Fixture")];

   Spec_Tokens : constant Project_Tools.AUnit_Checks.Text_List :=
     [To_Unbounded_String ("with AUnit;"),
      To_Unbounded_String ("with AUnit.Test_Cases;"),
      To_Unbounded_String ("type Section_Test_Case is new AUnit.Test_Cases.Test_Case"),
      To_Unbounded_String ("function Name"),
      To_Unbounded_String ("return AUnit.Message_String"),
      To_Unbounded_String ("procedure Register_Tests"),
      To_Unbounded_String ("type Section_Test_Case is new AUnit.Test_Cases.Test_Case")];

   Body_Tokens : constant Project_Tools.AUnit_Checks.Text_List :=
     [To_Unbounded_String ("Registration"),
      To_Unbounded_String ("function Name"),
      To_Unbounded_String ("procedure Register_Tests")];

   Forbidden_Body_Tokens : constant Project_Tools.AUnit_Checks.Text_List :=
     [To_Unbounded_String ("type Section_Test_Case is new AUnit.Test_Cases.Test_Case"),
      To_Unbounded_String ("Offline_Test_Cases")];

   Live_Endpoints : constant array (Positive range <>) of String_Access :=
     [new String'("httpbin.org"),
      new String'("badssl.com"),
      new String'("nghttp2.org"),
      new String'("cloudflare-quic.com")];

   Metrics : Project_Tools.AUnit_Checks.Suite_Metrics;

   procedure Check_Section (Path : String; Name : String) is
      Spec_Path : constant String := Test_Dir & "/" & Project_Tools.AUnit_Checks.Spec_Name (Name);
   begin
      Project_Tools.AUnit_Checks.Check_Section_Suite
        (Errors,
         Path,
         Spec_Path,
         Name,
         Spec_Tokens,
         Body_Tokens,
         Forbidden_Body_Tokens,
         Max_Registrations => 60,
         Metrics           => Metrics);
   end Check_Section;

begin
   Check_Support.Require_File_Contains
     (Errors, Test_Dir & "/all_suites.ads",
      "function Suite return Access_Test_Suite",
      "all_suites.ads must expose the aggregate AUnit suite");
   Check_Support.Require_File_Contains
     (Errors, Test_Dir & "/tests.adb",
      "AUnit.Run.Test_Runner",
      "tests.adb must run through AUnit.Run.Test_Runner");
   Check_Support.Require_File_Contains
     (Errors, "./tests/alire.toml", "aunit",
      "tests/alire.toml must depend on AUnit");

   for File of Required_Section_Files loop
      if not Check_Support.File_Exists (Test_Dir & "/" & File.all) then
         Check_Support.Error (Errors, "missing required section AUnit suite: " & File.all);
      end if;
   end loop;

   if Check_Support.File_Exists (Test_Dir & "/http_client-offline_test_cases.ads")
     or else Check_Support.File_Exists (Test_Dir & "/http_client-offline_test_cases.adb")
   then
      Check_Support.Error (Errors, "obsolete monolithic test-cases package still exists");
   end if;

   declare
      Search : Ada.Directories.Search_Type;
      E : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Test_Dir,
         Pattern   => "http_client-*-tests.adb",
         Filter    => [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, E);
         Check_Section (Ada.Directories.Full_Name (E), Ada.Directories.Simple_Name (E));
      end loop;
      Ada.Directories.End_Search (Search);
   end;

   if Metrics.Section_Count < 20 then
      Check_Support.Error (Errors, "expected at least 20 section-specific AUnit suites");
   end if;
   if Metrics.Registration_Count < 250 then
      Check_Support.Error (Errors, "expected at least 250 registered AUnit tests");
   end if;
   if Metrics.Assertion_Count < 900 then
      Check_Support.Error (Errors, "expected at least 900 AUnit assertions");
   end if;

   declare
      All_Text : constant String := To_String (Metrics.Registered_Text);
   begin
      for Token of Required_Areas loop
         if not Check_Support.Contains (All_Text, Token.all) then
            Check_Support.Error (Errors, "offline AUnit suite missing required behavior token: " & Token.all);
         end if;
      end loop;
      for Live of Live_Endpoints loop
         if Check_Support.Contains (All_Text, Live.all) then
            Check_Support.Error (Errors, "offline AUnit suite contains live endpoint literal: " & Live.all);
         end if;
      end loop;
   end;

   declare
      Coverage : constant String := To_String (Check_Support.Read_File ("./tools/src/run_aunit_coverage.adb"));
      Doc      : constant String := To_String (Check_Support.Read_File ("./docs/AUNIT_SUITE.md"));
   begin
      if not Check_Support.Contains (Coverage, "--fail-under-line")
        or else not Check_Support.Contains (Coverage, "--fail-under-branch")
        or else not Check_Support.Contains (Coverage, "100")
      then
         Check_Support.Error (Errors, "run_aunit_coverage must enforce 100% line and branch coverage");
      end if;
      if not Check_Support.Contains (Coverage, "./tests/bin/tests") then
         Check_Support.Error (Errors, "run_aunit_coverage must run the AUnit test executable");
      end if;
      if not Check_Support.Contains (Doc, "test bodies live in the component-specific") then
         Check_Support.Error (Errors, "docs/AUNIT_SUITE.md must document real split-suite ownership");
      end if;
   end;

   if Errors = 0 then
      Ada.Text_IO.Put_Line
        ("AUnit suite checks passed:"
         & Natural'Image (Metrics.Section_Count) & " section suites,"
         & Natural'Image (Metrics.Registration_Count) & " registered tests,"
         & Natural'Image (Metrics.Assertion_Count) & " assertions");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Check_AUnit_Suite;
