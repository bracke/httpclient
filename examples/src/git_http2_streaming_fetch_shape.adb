with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.HTTP2;

procedure Git_HTTP2_Streaming_Fetch_Shape is
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
   --  HTTP/1.1 remains the conservative Git default; HTTP/2 is explicit.
   Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_Force_HTTP_2;
   Options.TLS.HTTP2.Mode := Http_Client.HTTP2.HTTP2_Required;
   Options.TLS.HTTP2.Enable_Public_Streaming := True;
   Options.TLS.HTTP2.Enable_Upload_Streaming := True;

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
end Git_HTTP2_Streaming_Fetch_Shape;
