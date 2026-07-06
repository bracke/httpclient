with AUnit;
with AUnit.Test_Cases;

package Http_Client.Timeout_Tests is
   type Section_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Section_Test_Case) return AUnit.Message_String;
   --  GNATdoc contract.
   --  @param T Test case instance.
   --  @return Display name for this AUnit test case.

   overriding procedure Register_Tests
     (T : in out Section_Test_Case);
   --  GNATdoc contract.
   --  @param T Test case instance receiving registered routines.
end Http_Client.Timeout_Tests;
