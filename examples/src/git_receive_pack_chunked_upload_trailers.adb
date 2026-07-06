with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Receive_Pack_Chunked_Upload_Trailers is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Body_Bytes : constant Ada.Streams.Stream_Element_Array :=
     (16#50#, 16#41#, 16#43#, 16#4B#, 16#00#, 16#FF#, 16#41#, 16#42#);
   Producer : aliased Example_Helpers.Static_Body_Producer;
   URI      : Http_Client.URI.URI_Reference;
   Headers  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request  : Http_Client.Requests.Request;
   Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Stream   : Http_Client.Response_Streams.Streaming_Response;
   Options  : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Buffer   : Ada.Streams.Stream_Element_Array (1 .. 4096);
   Last     : Ada.Streams.Stream_Element_Offset;
   Status   : Http_Client.Errors.Result_Status;
begin
   Example_Helpers.Initialize (Producer, Body_Bytes);

   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/git-receive-pack", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Content-Type", "application/x-git-receive-pack-request");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Accept", "application/x-git-receive-pack-result");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI => URI,
         Item => Request,
         Headers => Headers);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Trailers, "X-Git-Upload-Complete", "true");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Set_Body
        (Request,
         Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
           (Producer => Producer'Unchecked_Access,
            Trailers => Trailers,
            Replayable => False));
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

   Status := Http_Client.Response_Streams.Close (Stream);
end Git_Receive_Pack_Chunked_Upload_Trailers;
