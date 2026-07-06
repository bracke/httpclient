with AUnit; use AUnit;
with AUnit.Test_Suites; use AUnit.Test_Suites;

package All_Suites is

   function Suite return Access_Test_Suite;
   --  GNATdoc contract.
   --  @return Top-level AUnit suite for all test groups.

end All_Suites;