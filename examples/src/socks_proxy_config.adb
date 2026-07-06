with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Proxies;

procedure SOCKS_Proxy_Config is
   use type Http_Client.Errors.Result_Status;
   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Proxy  : Http_Client.Proxies.Proxy_Config;
   Status : Http_Client.Errors.Result_Status;
begin
   Proxy := Http_Client.Proxies.SOCKS5 ("127.0.0.1", 1080);
   Status := Http_Client.Proxies.With_SOCKS5_Username_Password
     (Proxy, "user", "password", Proxy);
   if Status = Http_Client.Errors.Ok then
      Config.Execution.Proxy := Proxy;
      Status := Http_Client.Clients.Validate (Config);
   end if;
end SOCKS_Proxy_Config;
