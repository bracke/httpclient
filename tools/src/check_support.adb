with Ada.Text_IO;
with Project_Tools.Files;
with Project_Tools.Text;

package body Check_Support is
   use Ada.Strings.Unbounded;

   function Read_File (Path : String) return Unbounded_String is
   begin
      return Project_Tools.Text.Read_Text_File (Path);
   end Read_File;

   function Contains (Text : String; Pattern : String) return Boolean is
   begin
      return Project_Tools.Text.Contains (Text, Pattern);
   end Contains;

   function Count (Text : String; Pattern : String) return Natural is
   begin
      return Project_Tools.Text.Count (Text, Pattern);
   end Count;

   function Exists (Path : String) return Boolean is
   begin
      return Project_Tools.Files.Exists (Path);
   end Exists;

   function File_Exists (Path : String) return Boolean is
   begin
      return Project_Tools.Files.File_Exists (Path);
   end File_Exists;

   function Directory_Exists (Path : String) return Boolean is
   begin
      return Project_Tools.Files.Directory_Exists (Path);
   end Directory_Exists;

   procedure Error (Errors : in out Natural; Message : String) is
   begin
      Errors := Errors + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "error: " & Message);
   end Error;

   procedure Require_File_Contains
     (Errors  : in out Natural;
      Path    : String;
      Pattern : String;
      Message : String) is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         Error (Errors, "missing or unreadable file: " & Path);
      elsif not Project_Tools.Files.File_Contains (Path, Pattern) then
         Error (Errors, Message);
      end if;
   end Require_File_Contains;
end Check_Support;
