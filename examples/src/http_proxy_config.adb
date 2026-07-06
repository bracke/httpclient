with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Proxies;

procedure HTTP_Proxy_Config is
   use type Http_Client.Errors.Result_Status;
   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Proxy  : Http_Client.Proxies.Proxy_Config;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Proxies.Parse ("http://proxy.example:8080", Proxy);
   if Status = Http_Client.Errors.Ok then
      Config.Execution.Proxy := Proxy;
      Status := Http_Client.Clients.Validate (Config);
   end if;
end HTTP_Proxy_Config;
