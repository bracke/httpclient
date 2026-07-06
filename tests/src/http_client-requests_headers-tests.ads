with AUnit;
with AUnit.Test_Cases;

package Http_Client.Requests_Headers.Tests is
   --  AUnit test-case package for Requests_Headers.
   --
   --  The section test case owns the tests for this component area.  The
   --  aggregate offline runner composes these concrete AUnit test cases
   --  through Suite rather than calling ad-hoc procedural tests.

   type Section_Test_Case is new AUnit.Test_Cases.Test_Case with null record;
   --  AUnit test case containing the registered Requests_Headers tests.

   overriding function Name
     (T : Section_Test_Case)
      return AUnit.Message_String;
   --  GNATdoc contract.
   --  @param T Test case instance.
   --  @return Display name for this AUnit test case.
   --  Return the display name for this AUnit test case.

   overriding procedure Register_Tests
     (T : in out Section_Test_Case);
   --  GNATdoc contract.
   --  @param T Test case instance receiving registered routines.
   --  Register all AUnit routines owned by this component test package.

end Http_Client.Requests_Headers.Tests;
