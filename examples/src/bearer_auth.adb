with Http_Client.Auth.Bearer;
with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Bearer_Auth is
   use type Http_Client.Errors.Result_Status;
   URI      : Http_Client.URI.URI_Reference;
   Request  : Http_Client.Requests.Request;
   Secured  : Http_Client.Requests.Request;
   Status   : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.URI.Parse ("https://example.com/api", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Http_Client.Types.GET, URI, Request);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Auth.Bearer.Set_Bearer_Authorization
        (Request, "caller-supplied-token", Secured);
   end if;
end Bearer_Auth;
