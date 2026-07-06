with Http_Client.Errors;
with Http_Client.HTTP3;

procedure Enable_HTTP3_Experimental is
   use type Http_Client.Errors.Result_Status;
   Options : Http_Client.HTTP3.HTTP3_Options :=
     Http_Client.HTTP3.Default_HTTP3_Options;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
   Status := Http_Client.HTTP3.Execution_Status (Options);
   if Status = Http_Client.Errors.HTTP3_Unsupported
     or else Status = Http_Client.Errors.QUIC_Unsupported
   then
      null;
   end if;
end Enable_HTTP3_Experimental;
