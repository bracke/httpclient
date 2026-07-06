with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Proxies;

procedure Git_SOCKS5_HTTPS is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   URI     : Http_Client.URI.URI_Reference;
   Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Proxy   : Http_Client.Proxies.Proxy_Config;
   Request : Http_Client.Requests.Request;
   Stream  : Http_Client.Response_Streams.Streaming_Response;
   Options : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Buffer  : Ada.Streams.Stream_Element_Array (1 .. 4096);
   Last    : Ada.Streams.Stream_Element_Offset;
   Status  : Http_Client.Errors.Result_Status;
begin
   Proxy := Http_Client.Proxies.SOCKS5 ("socks.example.invalid", 1080);
   Status := Http_Client.Proxies.With_SOCKS5_Username_Password (Proxy, "user", "password", Proxy);
   if Status = Http_Client.Errors.Ok then
      Options.Proxy := Proxy;
   end if;
   Options.Cookie_Jar := null;
   Options.TLS.Disable_Certificate_Verification := False;

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.URI.Parse
        ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
   end if;
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
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
   end if;

   while Status = Http_Client.Errors.Ok loop
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      if Status = Http_Client.Errors.Ok and then Last >= Buffer'First then
         Example_Helpers.Feed_Git_Pkt_Line_Parser (Buffer (Buffer'First .. Last));
      end if;
   end loop;

   declare
      Close_Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.Response_Streams.Close (Stream);
      pragma Unreferenced (Close_Status);
   begin
      null;
   end;
end Git_SOCKS5_HTTPS;
