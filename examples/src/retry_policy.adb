with Http_Client.Errors;
with Http_Client.Retry;
with Http_Client.Types;

procedure Retry_Policy is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Retry.Delay_Milliseconds;
   Options : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options;
   D : Http_Client.Retry.Delay_Milliseconds;
   Retry   : Boolean;
begin
   Options.Enable_Retries := True;
   Options.Maximum_Attempts := 3;
   Options.Base_Delay := 100;
   Options.Maximum_Delay := 1_000;
   Options.Backoff := Http_Client.Retry.Exponential_Delay;

   Retry := Http_Client.Retry.Is_Retryable_Method
     (Http_Client.Types.GET, Options)
     and then Http_Client.Retry.Is_Retryable_Failure
       (Http_Client.Errors.Connection_Failed, Options);

   D := Http_Client.Retry.Delay_For_Attempt (1, Options);

   if Retry and then D > 0 then
      null;
   end if;
end Retry_Policy;
