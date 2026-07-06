with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Redirect_Policy is
   use type Http_Client.Errors.Result_Status;

   Client    : Http_Client.Clients.Client := Http_Client.Clients.Create;
   URI       : Http_Client.URI.URI_Reference;
   Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request   : Http_Client.Requests.Request;
   Result    : Http_Client.Clients.Redirect_Result;
   Execution : Http_Client.Clients.Execution_Options := Http_Client.Clients.Default_Execution_Options;
   Redirects : Http_Client.Clients.Redirect_Options := Http_Client.Clients.Default_Redirect_Options;
   Status    : Http_Client.Errors.Result_Status;
begin
   --  Git callers can start from strict configuration when they need
   --  no-follow behavior. This example enables safe GET-only following explicitly.
   Execution.Cookie_Jar := null;
   Redirects.Follow_Redirects := True;
   Redirects.Allow_HTTPS_To_HTTP_Redirects := False;
   Redirects.Allow_Body_Replay := False;
   Redirects.Strip_Credentials_Cross_Origin := True;

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
      Status := Http_Client.Clients.Execute_With_Redirects
        (Item => Client, Request => Request, Result => Result, Execution => Execution, Redirects => Redirects);
   end if;
end Git_Redirect_Policy;
