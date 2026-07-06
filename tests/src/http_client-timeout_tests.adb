with AUnit;
with AUnit.Assertions;

with Http_Client.Errors;
with Http_Client.Transports.TCP;
with Http_Client.Retry;

package body Http_Client.Timeout_Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Category;
   use type Http_Client.Transports.TCP.Timeout_Milliseconds;

   procedure Test_Default_Timeouts_Are_Disabled

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Timeouts : constant Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
   begin
      Assert (Timeouts.Connect = 0, "default connect timeout should be disabled");
      Assert (Timeouts.Read = 0, "default read timeout should be disabled");
      Assert (Timeouts.Write = 0, "default write timeout should be disabled");
   end Test_Default_Timeouts_Are_Disabled;

   procedure Test_Timeout_Status_Category
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
   begin
      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.Timeout) =
         Http_Client.Errors.Transport_Category,
         "Timeout should remain a transport-category ordinary failure");
   end Test_Timeout_Status_Category;

   procedure Test_Timeout_Retry_Classification_Obeys_Policy
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;
      Options.Retry_Timeouts := True;

      Assert
        (Http_Client.Retry.Is_Retryable_Failure
           (Status  => Http_Client.Errors.Timeout,
            Options => Options),
         "Timeout should be retryable when timeout retry is explicitly enabled");

      Options.Retry_Timeouts := False;

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
           (Status  => Http_Client.Errors.Timeout,
            Options => Options),
         "Timeout should not be retryable when timeout retry is disabled");
   end Test_Timeout_Retry_Classification_Obeys_Policy;

   overriding function Name
     (T : Section_Test_Case) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Http_Client.Timeout_Tests");
   end Name;

   overriding procedure Register_Tests
     (T : in out Section_Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Default_Timeouts_Are_Disabled'Access,
         "Test_Default_Timeouts_Are_Disabled");
      Register_Routine
        (T,
         Test_Timeout_Retry_Classification_Obeys_Policy'Access,
         "Test_Timeout_Retry_Classification_Obeys_Policy");
      Register_Routine
        (T,
         Test_Timeout_Status_Category'Access,
         "Test_Timeout_Status_Category");
   end Register_Tests;
end Http_Client.Timeout_Tests;
