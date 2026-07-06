with Http_Client.Errors;
with Http_Client.TLS.Client_Certificates;

procedure Client_Certificate_Config is
   use type Http_Client.Errors.Result_Status;
   Credential : Http_Client.TLS.Client_Certificates.Client_Certificate :=
     Http_Client.TLS.Client_Certificates.From_PEM_Files
       ("client.pem", "client-key.pem", Allow_Any_Origin => True);
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.TLS.Client_Certificates.Validate (Credential);
   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Client_Certificate_Config;
