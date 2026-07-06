with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.HTTP3;
with Http_Client.Transports.TLS;

procedure Stabilized_Defaults is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP3.HTTP3_Mode;
   Config : constant Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Strict : constant Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Strict_Client_Configuration;
   TLS    : constant Http_Client.Transports.TLS.TLS_Options :=
     Http_Client.Transports.TLS.Default_TLS_Options;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Clients.Validate (Config);

   if Status = Http_Client.Errors.Ok
     and then not TLS.Disable_Certificate_Verification
     and then Config.Redirects.Follow_Redirects
     and then Config.Enable_Decompression
     and then not Strict.Redirects.Follow_Redirects
     and then not Strict.Enable_Decompression
     and then Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled
   then
      null;
   else
      null;
   end if;
end Stabilized_Defaults;
