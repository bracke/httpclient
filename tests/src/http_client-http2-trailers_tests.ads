with AUnit;
with AUnit.Test_Cases;

package Http_Client.HTTP2.Trailers_Tests is
   --  AUnit coverage for HTTP/2 request and response trailers.

   type Section_Test_Case is new AUnit.Test_Cases.Test_Case with null record;
   --  HTTP/2 trailers test case.

   overriding function Name
     (T : Section_Test_Case)
      return AUnit.Message_String;
   --  GNATdoc contract.
   --  @param T Test case instance.
   --  @return Display name for this AUnit test case.
   --  Return the display name for this test case.

   overriding procedure Register_Tests
     (T : in out Section_Test_Case);
   --  GNATdoc contract.
   --  @param T Test case instance receiving registered routines.
   --  Register HTTP/2 trailer tests.
end Http_Client.HTTP2.Trailers_Tests;
