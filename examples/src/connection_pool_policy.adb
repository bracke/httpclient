with Http_Client.Connection_Pools;
with Http_Client.Errors;
with Http_Client.URI;

procedure Connection_Pool_Policy is
   use type Http_Client.Errors.Result_Status;
   URI     : Http_Client.URI.URI_Reference;
   Options : Http_Client.Connection_Pools.Pooling_Options :=
     Http_Client.Connection_Pools.Default_Pooling_Options;
   Pool    : Http_Client.Connection_Pools.Connection_Pool;
   Key     : Http_Client.Connection_Pools.Pool_Key;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Enabled := True;
   Options.Max_Total_Idle_Connections := 4;
   Options.Max_Idle_Connections_Per_Key := 2;

   Status := Http_Client.Connection_Pools.Validate (Options);
   if Status = Http_Client.Errors.Ok then
      Http_Client.Connection_Pools.Initialize (Pool, Options);
      Status := Http_Client.URI.Parse ("https://example.com/", URI);
   end if;

   if Status = Http_Client.Errors.Ok then
      Key := Http_Client.Connection_Pools.Key_For (URI);
      if Http_Client.Connection_Pools.Is_Valid (Key) then
         null;
      end if;
   end if;
end Connection_Pool_Policy;
