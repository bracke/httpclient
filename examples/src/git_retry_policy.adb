with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Retry;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Retry_Policy is
   use type Http_Client.Errors.Result_Status;

   Client    : Http_Client.Clients.Client := Http_Client.Clients.Create;
   URI       : Http_Client.URI.URI_Reference;
   Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request   : Http_Client.Requests.Request;
   Result    : Http_Client.Clients.Retry_Result;
   Execution : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
   Retries   : Http_Client.Retry.Retry_Options := Http_Client.Retry.Default_Retry_Options;
   Status    : Http_Client.Errors.Result_Status;
begin
   --  Retries are disabled by default. Enable only bounded safe GET retry.
   Execution.Cookie_Jar := null;
   Retries.Enable_Retries := True;
   Retries.Maximum_Attempts := 2;
   Retries.Retry_Timeouts := True;
   Retries.Allow_Non_Idempotent_Retry := False;

   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.GET, URI => URI, Item => Request, Headers => Headers);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Clients.Execute_With_Retry
        (Item => Client, Request => Request, Result => Result, Execution => Execution, Retries => Retries);
   end if;
end Git_Retry_Policy;
