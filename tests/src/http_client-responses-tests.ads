with AUnit;
with AUnit.Test_Cases;

package Http_Client.Responses.Tests is
   type Section_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name
     (T : Section_Test_Case)
      return AUnit.Message_String;

   overriding procedure Register_Tests
     (T : in out Section_Test_Case);
end Http_Client.Responses.Tests;
