with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.URI;

procedure Manual_Request is
   use type Http_Client.Errors.Result_Status;
   URI     : Http_Client.URI.URI_Reference;
   Request : Http_Client.Requests.Request;
   Status  : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.URI.Parse ("http://example.com/index.html", URI);

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Http_Client.Types.GET, URI, Request);
   end if;

   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Manual_Request;
