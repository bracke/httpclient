with Http_Client.Cache.Persistent;
with Http_Client.Errors;

procedure Persistent_Cache_Config is
   use type Http_Client.Errors.Result_Status;
   Config : constant Http_Client.Cache.Persistent.Persistent_Config :=
     Http_Client.Cache.Persistent.Make_Config
       (Directory => "./.http-cache",
        Enabled => True,
        Create_If_Missing => False);
   Store  : Http_Client.Cache.Persistent.Persistent_Store;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Cache.Persistent.Open (Store, Config);
   if Status /= Http_Client.Errors.Ok then
      Http_Client.Cache.Persistent.Close (Store);
   end if;
end Persistent_Cache_Config;
