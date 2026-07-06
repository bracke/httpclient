with Http_Client.Async;
with Http_Client.Clients;
with Http_Client.Errors;

procedure Async_Submit is
   use type Http_Client.Errors.Result_Status;
   Client : constant Http_Client.Clients.Client := Http_Client.Clients.Create;
   Async  : Http_Client.Async.Async_Client;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Async.Initialize (Async, Client);
   if Status = Http_Client.Errors.Ok then
      Http_Client.Async.Shutdown (Async, Cancel_Pending => True);
   end if;
end Async_Submit;
