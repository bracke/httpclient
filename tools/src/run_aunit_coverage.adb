with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Directories;
with Ada.Text_IO;

with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Release_Checks;

procedure Run_AUnit_Coverage is
   use Ada.Text_IO;

   function Current_Root return String is
      Here : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists ("httpclient.gpr") then
         return Here;
      elsif Ada.Directories.Exists ("tests.gpr")
        and then Ada.Directories.Exists ("../httpclient.gpr")
      then
         return Ada.Directories.Full_Name ("..");
      else
         Put_Line
           (Standard_Error,
            "run_aunit_coverage must be run from the HttpClient root or tests crate");
         raise Program_Error;
      end if;
   end Current_Root;

   Root : constant String := Current_Root;
begin
   Ada.Directories.Set_Directory (Root);
   Project_Tools.Processes.Require_Command
     ("alr", "alr is required to select the GNAT 15 toolchain for the coverage gate");
   Project_Tools.Processes.Require_Command
     ("gcovr", "gcovr is required to enforce the 100% release coverage gate");

   Project_Tools.Files.Delete_Tree ("tests/obj");
   Project_Tools.Files.Delete_Tree ("tests/bin");
   Project_Tools.Files.Delete_Tree ("coverage");
   Ada.Directories.Create_Directory ("coverage");

   Project_Tools.Release_Checks.Run
     ("coverage build", Root, Project_Tools.Processes.Locate_Command ("alr"),
      [new String'("exec"),
       new String'("--"),
       new String'("gprbuild"),
       new String'("-f"),
       new String'("-P"),
       new String'("tests/tests.gpr"),
       new String'("-cargs:Ada"),
       new String'("-fprofile-arcs"),
       new String'("-ftest-coverage"),
       new String'("-cargs:C"),
       new String'("-fprofile-arcs"),
       new String'("-ftest-coverage"),
       new String'("-largs"),
       new String'("-fprofile-arcs")]);

   Project_Tools.Release_Checks.Run ("coverage tests", Root, "./tests/bin/tests", []);

   Project_Tools.Release_Checks.Run
     ("coverage report", Root, "gcovr",
      [new String'("--root"),
       new String'("."),
       new String'("--filter"),
       new String'("src/.*"),
       new String'("--html"),
       new String'("--html-details"),
       new String'("coverage/index.html"),
       new String'("--xml"),
       new String'("coverage/coverage.xml"),
       new String'("--txt"),
       new String'("coverage/coverage.txt"),
       new String'("--fail-under-line"),
       new String'("100"),
       new String'("--fail-under-branch"),
       new String'("100")]);

   Put_Line ("AUnit coverage gate passed");
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
exception
   when Program_Error =>
      null;
   when E : others =>
      Put_Line
        (Standard_Error,
         "run_aunit_coverage failed: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Run_AUnit_Coverage;
