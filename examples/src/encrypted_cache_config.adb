with Http_Client.Cache.Persistent;
with Http_Client.Errors;

procedure Encrypted_Cache_Config is
   use type Http_Client.Errors.Result_Status;
   Key    : constant String := "0123456789abcdef0123456789abcdef";
   Config : constant Http_Client.Cache.Persistent.Persistent_Config :=
     Http_Client.Cache.Persistent.Make_Config
       (Directory => "./.http-cache-encrypted",
        Enabled => True,
        Create_If_Missing => False,
        Encrypt_At_Rest => True,
        Raw_Encryption_Key => Key);
   Store  : Http_Client.Cache.Persistent.Persistent_Store;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Cache.Persistent.Open (Store, Config);
   if Status /= Http_Client.Errors.Ok then
      Http_Client.Cache.Persistent.Close (Store);
   end if;
end Encrypted_Cache_Config;
