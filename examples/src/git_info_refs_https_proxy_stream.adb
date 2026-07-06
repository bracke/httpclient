with Ada.Streams;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Info_Refs_HTTPS_Proxy_Stream is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   URI     : Http_Client.URI.URI_Reference;
   Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request : Http_Client.Requests.Request;
   Stream  : Http_Client.Response_Streams.Streaming_Response;
   Options : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Buffer  : Ada.Streams.Stream_Element_Array (1 .. 4096);
   Last    : Ada.Streams.Stream_Element_Offset;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Cookie_Jar := null;
   Options.Proxy := Http_Client.Proxies.HTTP ("proxy.example", 8080);

   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
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
      --  The streaming transport sends CONNECT to the proxy, performs TLS
      --  verification against example.invalid inside the tunnel, then sends these
      --  Git headers only in the TLS stream.
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
   end if;

   while Status = Http_Client.Errors.Ok loop
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      if Status = Http_Client.Errors.Ok and then Last >= Buffer'First then
         --  Feed Buffer (Buffer'First .. Last) to a Git pkt-line parser.
         null;
      end if;
   end loop;

   Status := Http_Client.Response_Streams.Close (Stream);
end Git_Info_Refs_HTTPS_Proxy_Stream;
