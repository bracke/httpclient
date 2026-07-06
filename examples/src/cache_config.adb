with Http_Client.Cache;
with Http_Client.Clients;
with Http_Client.Errors;

procedure Cache_Config is
   use type Http_Client.Errors.Result_Status;
   Store  : aliased Http_Client.Cache.Cache_Store;
   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Status : Http_Client.Errors.Result_Status;
begin
   Http_Client.Cache.Initialize
     (Store, Http_Client.Cache.Default_Enabled_Cache_Config);
   Config.Cache := Http_Client.Cache.Default_Enabled_Cache_Config;
   Config.Cache_Store := Store'Unchecked_Access;
   Status := Http_Client.Clients.Validate (Config);
end Cache_Config;
