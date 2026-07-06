with AUnit;
with AUnit.Test_Cases;

package Http_Client.Connect_TLS_Tests is
   --  AUnit tests for HTTPS over an explicit HTTP CONNECT proxy.

   type Section_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Section_Test_Case)
      return AUnit.Message_String;
   --  GNATdoc contract.
   --  @param T Test case instance.
   --  @return Display name for this AUnit test case.

   overriding procedure Register_Tests
     (T : in out Section_Test_Case);
   --  GNATdoc contract.
   --  @param T Test case instance receiving registered routines.

   overriding procedure Set_Up
     (T : in out Section_Test_Case);
   --  Ensure no stale proxy/TLS fixtures from a previous routine survive.

   overriding procedure Tear_Down
     (T : in out Section_Test_Case);
   --  Ensure proxy/TLS fixtures are stopped after every routine.

end Http_Client.Connect_TLS_Tests;
