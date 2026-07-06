with Http_Client.Clients;
with Http_Client.Errors;

procedure Redirect_Client is
   use type Http_Client.Errors.Result_Status;
   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Status : Http_Client.Errors.Result_Status;
begin
   --  Safe redirects are already enabled by Default_Client_Configuration.
   --  This example tightens the hop limit while keeping downgrade blocking and
   --  cross-origin credential stripping enabled.
   Config.Redirects.Max_Redirects := 3;
   Config.Redirects.Allow_HTTPS_To_HTTP_Redirects := False;
   Config.Redirects.Strip_Credentials_Cross_Origin := True;

   Status := Http_Client.Clients.Validate (Config);
   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Redirect_Client;
