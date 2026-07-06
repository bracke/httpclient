with Http_Client.Auth;
with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Basic_Auth is
   use type Http_Client.Errors.Result_Status;
   URI      : Http_Client.URI.URI_Reference;
   Request  : Http_Client.Requests.Request;
   Secured  : Http_Client.Requests.Request;
   Status   : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.URI.Parse ("https://example.com/private", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Http_Client.Types.GET, URI, Request);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Auth.Set_Basic_Authorization
        (Request, "user", "password", Secured);
   end if;
end Basic_Auth;
