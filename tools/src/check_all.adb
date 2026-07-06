with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.OS_Lib;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;
with Project_Tools.Text;
with Project_Tools.Tree_Checks;

procedure Check_All is
   use Ada.Text_IO;

   Root   : constant String := Ada.Directories.Current_Directory;
   Alr    : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Checks : constant Project_Tools.Release_Checks.Checker :=
     Project_Tools.Release_Checks.Create (Root);

   procedure Require_Alire is
   begin
      Project_Tools.Processes.Require_Command
        ("alr", "alr is required for the HttpClient release checklist");
   end Require_Alire;

   procedure Require_Alire_GNAT_15 is
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Status : Integer;
   begin
      Status :=
        Project_Tools.Processes.Run_Status
          ("verify Alire-selected GNAT 15 toolchain",
           Root,
           Alr,
           [new String'("exec"), new String'("--"), new String'("gnatls"), new String'("--version")],
           Output,
           Quiet => False);

      if Status /= 0 then
         Put_Line (Standard_Error, "alr exec -- gnatls --version failed");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      elsif Project_Tools.Text.Contains (Ada.Strings.Unbounded.To_String (Output), "GNATLS 15.") = False then
         Put_Line
           (Standard_Error,
            "HttpClient must build with Alire-selected GNAT 15, got: "
            & Ada.Strings.Unbounded.To_String (Output));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Alire_GNAT_15;

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List;
      Quiet   : Boolean := False) renames Project_Tools.Release_Checks.Run;

begin
   if not Ada.Directories.Exists (Root & "/httpclient.gpr") then
      Put_Line (Standard_Error, "check_all must be run from the HttpClient root");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Require_Alire;
   Require_Alire_GNAT_15;

   Project_Tools.Release_Checks.Require_File (Checks, "httpclient.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tests/tests.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tests/api_stability/api_stability.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "examples/examples.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/tools.gpr");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/src/check_release_surface.adb");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/src/check_aunit_suite.adb");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/src/check_security_corpus.adb");
   Project_Tools.Release_Checks.Require_File (Checks, "tools/src/check_git_smart_http_release.adb");

   Run ("alr build", Root, Alr, [new String'("build")]);
   Run
     ("HttpClient GNATprove", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gnatprove"),
       new String'("-P"), new String'("httpclient.gpr"),
       new String'("--level=4")]);
   Run
     ("tests.gpr", Root & "/tests", Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tests.gpr")]);
   Run ("offline AUnit tests", Root & "/tests", "./bin/tests", []);
   Run ("alr test", Root, Alr, [new String'("test")]);
   Run
     ("api stability", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tests/api_stability/api_stability.gpr")]);
   Run
     ("examples.gpr", Root & "/examples", Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("examples.gpr")]);
   Run
     ("tools.gpr", Root, Alr,
      [new String'("exec"), new String'("--"), new String'("gprbuild"),
       new String'("-P"), new String'("tools/tools.gpr")]);
   Run ("release surface", Root, "./tools/bin/check_release_surface", []);
   Run ("AUnit suite guard", Root, "./tools/bin/check_aunit_suite", []);
   Run ("security corpus guard", Root, "./tools/bin/check_security_corpus", []);
   Run ("Git smart HTTP release guard", Root, "./tools/bin/check_git_smart_http_release", []);

   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tests/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tests/api_stability/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/examples/obj");
   Project_Tools.Tree_Checks.Require_No_Nonempty_Stderr (Root & "/tools/obj");

   Put_Line ("HttpClient release checklist passed");
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
exception
   when Program_Error =>
      null;
   when E : others =>
      Put_Line
        (Standard_Error,
         "HttpClient release checklist failed: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Check_All;
