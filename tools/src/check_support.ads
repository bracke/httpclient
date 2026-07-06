with Ada.Strings.Unbounded;

package Check_Support is
   function Read_File (Path : String) return Ada.Strings.Unbounded.Unbounded_String;
   --  GNATdoc contract.
   --  @param Path Filesystem path to read.
   --  @return Entire file contents as an unbounded string.
   function Contains (Text : String; Pattern : String) return Boolean;
   --  GNATdoc contract.
   --  @param Text Text to search.
   --  @param Pattern Pattern to find.
   --  @return True when Text contains Pattern.
   function Count (Text : String; Pattern : String) return Natural;
   --  GNATdoc contract.
   --  @param Text Text to search.
   --  @param Pattern Pattern to count.
   --  @return Number of non-overlapping Pattern occurrences.
   function Exists (Path : String) return Boolean;
   --  GNATdoc contract.
   --  @param Path Filesystem path to test.
   --  @return True when Path exists.
   function File_Exists (Path : String) return Boolean;
   --  GNATdoc contract.
   --  @param Path Filesystem path to test.
   --  @return True when Path names an existing ordinary file.
   function Directory_Exists (Path : String) return Boolean;
   --  GNATdoc contract.
   --  @param Path Filesystem path to test.
   --  @return True when Path names an existing directory.
   procedure Error (Errors : in out Natural; Message : String);
   --  GNATdoc contract.
   --  @param Errors Error counter incremented by the procedure.
   --  @param Message Diagnostic message to emit.
   procedure Require_File_Contains
     (Errors  : in out Natural;
      Path    : String;
      Pattern : String;
      Message : String);
   --  GNATdoc contract.
   --  @param Errors Error counter incremented on failure.
   --  @param Path File to inspect.
   --  @param Pattern Required substring.
   --  @param Message Diagnostic message to emit if Pattern is absent.
end Check_Support;
