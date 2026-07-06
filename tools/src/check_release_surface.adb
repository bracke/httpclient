with Ada.Command_Line;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Check_Support;
with Project_Tools.Tree_Checks;

procedure Check_Release_Surface is
   use Ada.Strings.Unbounded;
   Root   : constant String := ".";
   Src    : constant String := Root & "/src";
   Docs   : constant String := Root & "/docs";
   Errors : Natural := 0;

   type String_Access is access constant String;

   Stable_Or_Low_Level : constant array (Positive range <>) of String_Access :=
     [new String'("Http_Client"), new String'("Http_Client.Alt_Svc"),
      new String'("Http_Client.Auth"), new String'("Http_Client.Auth.Bearer"),
      new String'("Http_Client.Auth.Digest"), new String'("Http_Client.Auth.Scopes"),
      new String'("Http_Client.Async"), new String'("Http_Client.Cache"),
      new String'("Http_Client.Cache.Persistent"), new String'("Http_Client.Cancellation"),
      new String'("Http_Client.Clients"),
      new String'("Http_Client.Connection_Pools"), new String'("Http_Client.Cookies"),
      new String'("Http_Client.Decompression"), new String'("Http_Client.Diagnostics"),
      new String'("Http_Client.DNS_SVCB"), new String'("Http_Client.Errors"),
      new String'("Http_Client.Headers"), new String'("Http_Client.HTTPS_Records"),
      new String'("Http_Client.HTTP1"), new String'("Http_Client.HTTP1.Reader"),
      new String'("Http_Client.HTTP2"), new String'("Http_Client.HTTP2.Body_Streams"),
      new String'("Http_Client.HTTP2.Connection"), new String'("Http_Client.HTTP2.Frames"),
      new String'("Http_Client.HTTP2.HPACK"), new String'("Http_Client.HTTP2.Mapping"),
      new String'("Http_Client.HTTP2.Settings"), new String'("Http_Client.HTTP2.Single_Stream"),
      new String'("Http_Client.HTTP2.Streams"), new String'("Http_Client.HTTP2.Uploads"),
      new String'("Http_Client.Multipart"), new String'("Http_Client.Protocol_Discovery"),
      new String'("Http_Client.Proxy_Discovery"), new String'("Http_Client.Proxies"),
      new String'("Http_Client.Proxies.SOCKS"),
      new String'("Http_Client.Request_Bodies"), new String'("Http_Client.Requests"),
      new String'("Http_Client.Resources"), new String'("Http_Client.Response_Streams"),
      new String'("Http_Client.Responses"), new String'("Http_Client.Retry"),
      new String'("Http_Client.TLS.Client_Certificates"), new String'("Http_Client.Transports"),
      new String'("Http_Client.Transports.SOCKS"), new String'("Http_Client.Transports.TCP"),
      new String'("Http_Client.Transports.TLS"), new String'("Http_Client.Types"),
      new String'("Http_Client.URI")];

   Experimental : constant array (Positive range <>) of String_Access :=
     [new String'("Http_Client.HTTP3"), new String'("Http_Client.HTTP3.Body_Streams"), new String'("Http_Client.HTTP3.Frames"),
      new String'("Http_Client.HTTP3.Mapping"), new String'("Http_Client.HTTP3.QPACK"),
      new String'("Http_Client.HTTP3.Settings"), new String'("Http_Client.HTTP3.Streams"),
      new String'("Http_Client.HTTP3.Execution"), new String'("Http_Client.QUIC")];

   Implementation : constant array (Positive range <>) of String_Access :=
     [new String'("Http_Client.Crypto"),
      new String'("Http_Client.HTTP2_Execution_Common"),
      new String'("Http_Client.Response_Streams.HTTP2_IO"),
      new String'("Http_Client.TLS"),
      new String'("Http_Client.Zlib_Decompression")];

   Required_Docs : constant array (Positive range <>) of String_Access :=
     [new String'("QUICKSTART.md"), new String'("api-overview.md"), new String'("configuration.md"),
      new String'("security.md"), new String'("testing.md"),
      new String'("proxies.md"), new String'("caching.md"),
      new String'("streaming-and-uploads.md"), new String'("http2.md"),
      new String'("http3.md"), new String'("diagnostics.md"),
      new String'("async.md"), new String'("release-policy.md"),
      new String'("compatibility.md"), new String'("STABLE_API_CONTRACT.md"),
      new String'("DEFAULT_LIMITS.md"), new String'("INTEROPERABILITY_SECURITY_REVIEW.md"),
      new String'("RELEASE_NOTES_1_0_0.md"),
      new String'("POST_RELEASE_BASELINE.md"), new String'("COVERAGE.md"),
      new String'("AUNIT_SUITE.md"), new String'("SPARK.md")];

   Forbidden_Docs : constant array (Positive range <>) of String_Access :=
     [new String'("RELEASE_NOTES_1_0_PRE.md"),
      new String'("SECURITY_REVIEW_PHASE35.md")];

   Documentation_Index_Required : constant array (Positive range <>) of String_Access :=
     [new String'("QUICKSTART.md"), new String'("STABLE_API_CONTRACT.md"),
      new String'("DEFAULT_LIMITS.md"),
      new String'("INTEROPERABILITY_SECURITY_REVIEW.md"),
      new String'("COVERAGE.md"),
      new String'("AUNIT_SUITE.md"), new String'("SPARK.md")];

   Hygiene_Ignore_Patterns : constant array (Positive range <>) of String_Access :=
     [new String'("obj/"), new String'("bin/"), new String'("alire/"),
      new String'("coverage/"), new String'("obj/gnatprove/"),
      new String'("*.bak"), new String'("*.tmp"), new String'("*.swp"),
      new String'("*.kate-swp")];

   function Classified (Name : String) return Boolean is
   begin
      for P of Stable_Or_Low_Level loop
         if Name = P.all then
            return True;
         end if;
      end loop;
      for P of Experimental loop
         if Name = P.all then
            return True;
         end if;
      end loop;
      for P of Implementation loop
         if Name = P.all then
            return True;
         end if;
      end loop;
      return False;
   end Classified;

   function Package_Name (Text : String) return String is
      Marker : constant String := "package ";
      Pos    : constant Natural := Ada.Strings.Fixed.Index (Text, Marker);
      Start  : Natural;
      Stop   : Natural;
   begin
      if Pos = 0 then
         return "";
      end if;
      Start := Pos + Marker'Length;
      Stop := Start;
      while Stop <= Text'Last
        and then Text (Stop) not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
      loop
         Stop := Stop + 1;
      end loop;
      if Stop <= Start then
         return "";
      end if;
      return Text (Start .. Stop - 1);
   end Package_Name;

begin
   declare
      Manifest : constant String := To_String (Check_Support.Read_File (Docs & "/RELEASE_SURFACE_MANIFEST.md"));
      Readme   : constant String := To_String (Check_Support.Read_File (Root & "/README.md"));
      Alire         : constant String := To_String (Check_Support.Read_File (Root & "/alire.toml"));
      Release_Alire : constant String := To_String (Check_Support.Read_File (Root & "/httpclient.alire.release.toml"));
      Tests_Alire   : constant String := To_String (Check_Support.Read_File (Root & "/tests/alire.toml"));
      Examples_Alire : constant String := To_String (Check_Support.Read_File (Root & "/examples/alire.toml"));
      Root_Ads      : constant String := To_String (Check_Support.Read_File (Src & "/http_client.ads"));
   begin
      if not Check_Support.Contains (Root_Ads, "Version : constant String := ""1.0.0""") then
         Check_Support.Error (Errors, "root package version is not 1.0.0");
      end if;
      if not Check_Support.Contains (Alire, "version = ""1.0.0""") then
         Check_Support.Error (Errors, "alire.toml version is not 1.0.0");
      end if;
      if not Check_Support.Contains (Alire, "gnat_native = ""=15.2.1""")
        or else not Check_Support.Contains (Release_Alire, "gnat_native = ""=15.2.1""")
        or else not Check_Support.Contains (Tests_Alire, "gnat_native = ""=15.2.1""")
        or else not Check_Support.Contains (Examples_Alire, "gnat_native = ""=15.2.1""")
      then
         Check_Support.Error
           (Errors, "all active HttpClient manifests must pin gnat_native = ""=15.2.1""");
      end if;

      if Check_Support.Contains (Release_Alire, "[[pins]]")
        or else Check_Support.Contains (Release_Alire, "path='")
        or else Check_Support.Contains (Release_Alire, "path =")
      then
         Check_Support.Error
           (Errors, "httpclient.alire.release.toml must not contain local pins for release");
      end if;
      if not Check_Support.Contains (Release_Alire, "version = ""1.0.0""")
        or else not Check_Support.Contains (Release_Alire, "zlib = ""*""")
      then
         Check_Support.Error
           (Errors, "httpclient.alire.release.toml must preserve release metadata and zlib dependency");
      end if;

      if not Check_Support.Contains (Alire, "[[actions]]")
        or else not Check_Support.Contains (Alire, "type = ""test""")
        or else not Check_Support.Contains (Alire, "cd tests && alr build && ./bin/tests")
      then
         Check_Support.Error (Errors, "alire.toml must define the root alr test release action");
      end if;

      for P of Stable_Or_Low_Level loop
         if not Check_Support.Contains (Manifest, "`" & P.all & "`") then
            Check_Support.Error (Errors, P.all & " missing from RELEASE_SURFACE_MANIFEST.md");
         end if;
      end loop;
      for P of Experimental loop
         if not Check_Support.Contains (Manifest, "`" & P.all & "`") then
            Check_Support.Error (Errors, P.all & " missing from RELEASE_SURFACE_MANIFEST.md");
         end if;
      end loop;
      for P of Implementation loop
         if not Check_Support.Contains (Manifest, "`" & P.all & "`") then
            Check_Support.Error (Errors, P.all & " missing from RELEASE_SURFACE_MANIFEST.md");
         end if;
      end loop;

      if not Check_Support.Contains (Readme, "does not provide production HTTP/3 execution") then
         Check_Support.Error (Errors, "README must clearly deny production HTTP/3 execution");
      end if;
      if not Check_Support.Contains (Readme, "PAC") or else not Check_Support.Contains (Readme, "WPAD") then
         Check_Support.Error (Errors, "README must clearly deny PAC/WPAD/browser proxy discovery");
      end if;
      if not Check_Support.Contains (Readme, "docs/QUICKSTART.md") then
         Check_Support.Error (Errors, "README must link quickstart doc");
      end if;
      if not Check_Support.Contains (Readme, "STABLE_API_CONTRACT.md")
        or else not Check_Support.Contains (Readme, "DEFAULT_LIMITS.md")
      then
         Check_Support.Error (Errors, "README must link stable API and default limit docs");
      end if;

      if not Check_Support.Contains (Readme, "docs/SPARK.md")
        or else not Check_Support.Contains
          (Readme, "alr exec -- gnatprove -P httpclient.gpr --level=4")
        or else not Check_Support.Contains (Readme, "alr exec -- gnatls --version")
        or else not Check_Support.Contains (Readme, "Do not run plain system GNAT")
        or else not Check_Support.Contains (Readme, "tools/bin/check_all")
      then
         Check_Support.Error (Errors, "README must document SPARK, GNATprove, and aggregate release checks");
      end if;
   end;

   declare
      Search : Ada.Directories.Search_Type;
      E : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Src,
         Pattern   => "*.ads",
         Filter    => [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, E);
         declare
            Name : constant String := Package_Name (To_String (Check_Support.Read_File (Ada.Directories.Full_Name (E))));
         begin
            if Name = "" then
               Check_Support.Error (Errors, "cannot find package declaration in " & Ada.Directories.Full_Name (E));
            elsif not Classified (Name) then
               Check_Support.Error (Errors, Name & " has no release-surface classification");
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   end;

   for Doc of Required_Docs loop
      if not Check_Support.File_Exists (Docs & "/" & Doc.all) then
         Check_Support.Error (Errors, "required release doc missing: docs/" & Doc.all);
      end if;
   end loop;

   Check_Support.Require_File_Contains
     (Errors, Docs & "/SPARK.md",
      "alr exec -- gnatprove -P httpclient.gpr --level=4",
      "SPARK documentation must include the release GNATprove command");
   Check_Support.Require_File_Contains
     (Errors, Docs & "/SPARK.md", "Http_Client.Errors",
      "SPARK documentation must name an enabled public package");
   Check_Support.Require_File_Contains
     (Errors, Root & "/docs/RELEASE_CHECKLIST.md",
      "alr exec -- gnatprove -P httpclient.gpr --level=4",
      "release checklist must require GNATprove");
   Check_Support.Require_File_Contains
     (Errors, Root & "/docs/RELEASE_CHECKLIST.md", "alr test",
      "release checklist must require root alr test");
   Check_Support.Require_File_Contains
     (Errors, Root & "/docs/RELEASE_VERIFICATION.md", "./tools/bin/check_all",
      "release verification must require aggregate check_all");
   Check_Support.Require_File_Contains
     (Errors, Root & "/.github/workflows/ci.yml", "gnatprove",
      "CI must run the GNATprove release gate");

   declare
      Ignore : constant String := To_String (Check_Support.Read_File (Root & "/.gitignore"));
   begin
      for Pattern of Hygiene_Ignore_Patterns loop
         if not Check_Support.Contains (Ignore, Pattern.all) then
            Check_Support.Error (Errors, ".gitignore must ignore " & Pattern.all);
         end if;
      end loop;
   end;

   for Forbidden of Forbidden_Docs loop
      if Check_Support.Exists (Docs & "/" & Forbidden.all) then
         Check_Support.Error (Errors, "obsolete release document remains: docs/" & Forbidden.all);
      end if;
   end loop;

   Project_Tools.Tree_Checks.Check_No_Generated_Python (Errors, Root);

   declare
      Docs_Index : constant String := To_String (Check_Support.Read_File (Docs & "/DOCUMENTATION_INDEX.md"));
   begin
      for Needed of Documentation_Index_Required loop
         if not Check_Support.Contains (Docs_Index, Needed.all) then
            Check_Support.Error (Errors, "documentation index does not mention " & Needed.all);
         end if;
      end loop;
   end;

   if not Check_Support.File_Exists (Root & "/tests/api_stability/api_stability.gpr") then
      Check_Support.Error (Errors, "API-stability compile project is missing");
   end if;
   Check_Support.Require_File_Contains
     (Errors, Root & "/tests/api_stability/src/api_stability_compile.adb",
      "with Http_Client.URI;", "API-stability compile source must import stable packages");

   declare
      Aggregate_Body : constant String := To_String (Check_Support.Read_File (Root & "/tests/src/http_suite.adb"));
      Runner       : constant String := To_String (Check_Support.Read_File (Root & "/tests/src/tests.adb"));
      Coverage     : constant String := To_String (Check_Support.Read_File (Root & "/tools/src/run_aunit_coverage.adb"));
      Reg_Count    : Natural := 0;
      Search       : Ada.Directories.Search_Type;
      E        : Ada.Directories.Directory_Entry_Type;
   begin
      if Check_Support.Contains (Aggregate_Body, "Register_Routine") then
         Check_Support.Error (Errors, "aggregate offline suite must not contain direct registrations; use section suites");
      end if;
      if not Check_Support.Contains (Aggregate_Body, "Http_Client.URI.Tests.Section_Test_Case")
        or else not Check_Support.Contains (Aggregate_Body, "Http_Client.HTTP3.Tests.Section_Test_Case")
      then
         Check_Support.Error (Errors, "aggregate offline suite must include section suites");
      end if;
      if not Check_Support.Contains (Runner, "AUnit.Run.Test_Runner") then
         Check_Support.Error (Errors, "test runner must execute the AUnit suite");
      end if;
      if not Check_Support.Contains (Coverage, "--fail-under-line")
        or else not Check_Support.Contains (Coverage, "--fail-under-branch")
        or else not Check_Support.Contains (Coverage, "100")
      then
         Check_Support.Error (Errors, "coverage gate must enforce 100% line and branch coverage");
      end if;

      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Root & "/tests/src",
         Pattern   => "http_client-*-tests.adb",
         Filter    => [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, E);
         Reg_Count := Reg_Count + Check_Support.Count
           (To_String (Check_Support.Read_File (Ada.Directories.Full_Name (E))), "Register_Routine");
      end loop;
      Ada.Directories.End_Search (Search);
      if Reg_Count < 200 then
         Check_Support.Error (Errors, "offline AUnit suite must keep broad package-level coverage");
      end if;
   end;

   if not Check_Support.File_Exists (Root & "/tools/src/check_aunit_suite.adb") then
      Check_Support.Error (Errors, "Ada AUnit suite integrity checker is missing");
   end if;
   if Check_Support.File_Exists (Root & "/tools/check_aunit_suite.py")
     or else Check_Support.File_Exists (Root & "/tools/check_release_surface.py")
     or else Check_Support.File_Exists (Root & "/tools/check_security_corpus.py")
   then
      Check_Support.Error (Errors, "Python check scripts must not remain in release tooling");
   end if;

   if Errors = 0 then
      Ada.Text_IO.Put_Line ("release surface checks passed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Check_Release_Surface;
