with Ada.Streams;

with Http_Client.Cancellation;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Streaming_Get_With_Cancellation is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Token   : aliased Http_Client.Cancellation.Cancellation_Token;
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
   Options.Timeouts :=
     (Connect => 5_000,
      Read    => 30_000,
      Write   => 30_000);
   Options.Cancellation := Token'Unchecked_Access;

   Status := Http_Client.URI.Parse ("https://example.com/large.bin", URI);
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
      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Stream  => Stream,
         Options => Options);
   end if;

   while Status = Http_Client.Errors.Ok loop
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      if Status = Http_Client.Errors.Ok and then Last >= Buffer'First then
         --  Consume Buffer (Buffer'First .. Last) as bytes.
         null;
      end if;

      --  Another task may also call Cancel on the same token. This example keeps
      --  the hook visible without cancelling unconditionally.
      if False then
         Http_Client.Cancellation.Cancel (Token);
      end if;
   end loop;

   Status := Http_Client.Response_Streams.Close (Stream);
end Streaming_Get_With_Cancellation;
