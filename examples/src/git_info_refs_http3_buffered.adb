with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.QUIC;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Info_Refs_HTTP3_Buffered is
   use type Http_Client.Errors.Result_Status;

   Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
   Config  : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Strict_Client_Configuration;
   URI     : Http_Client.URI.URI_Reference;
   Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request : Http_Client.Requests.Request;
   Result  : Http_Client.Clients.Client_Result;
   Status  : Http_Client.Errors.Result_Status;
begin
   Config.Execution.Protocol_Policy := Http_Client.Clients.Prefer_HTTP_3;
   Config.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Allowed;
   Config.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
   Config.HTTP3.QUIC.Backend := Http_Client.QUIC.Backend_Available;
   Config.Execution.Cookie_Jar := null;
   Status := Http_Client.Clients.Configure (Client, Config);

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.URI.Parse
        ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept", "*/*");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Method  => Http_Client.Types.GET,
         URI     => URI,
         Item    => Request,
         Headers => Headers);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Clients.Execute (Client, Request, Result);
   end if;

   if Status = Http_Client.Errors.Ok then
      --  For Git packet bytes, prefer the streaming byte-array examples.
      --  HTTP/3 support depends on a configured QUIC backend in this release.
      null;
   end if;
end Git_Info_Refs_HTTP3_Buffered;
