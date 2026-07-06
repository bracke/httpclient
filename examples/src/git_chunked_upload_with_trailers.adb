with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Request_Bodies;

procedure Git_Chunked_Upload_With_Trailers is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Body_Bytes : constant Ada.Streams.Stream_Element_Array :=
     (16#30#, 16#30#, 16#30#, 16#38#, 16#70#, 16#75#, 16#73#, 16#68#);
   Producer : aliased Example_Helpers.Static_Body_Producer;
   URI      : Http_Client.URI.URI_Reference;
   Headers  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request  : Http_Client.Requests.Request;
   Stream   : Http_Client.Response_Streams.Streaming_Response;
   Options  : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Buffer   : Ada.Streams.Stream_Element_Array (1 .. 4096);
   Last     : Ada.Streams.Stream_Element_Offset;
   Status   : Http_Client.Errors.Result_Status;
begin
   --  Request trailers are API-completeness only; ordinary Git does not require them.
   Example_Helpers.Initialize (Producer, Body_Bytes);

   Status := Http_Client.Headers.Set (Trailers, "X-Git-SHA256", "0123456789abcdef");
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.URI.Parse ("https://example.invalid/repo.git/git-receive-pack", URI);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Content-Type", "application/x-git-receive-pack-request");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST, URI => URI, Item => Request, Headers => Headers);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Set_Body
        (Request, Http_Client.Request_Bodies.From_Unknown_Length_Stream_With_Trailers
          (Producer => Producer'Unchecked_Access, Trailers => Trailers, Replayable => False));
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

   if Status = Http_Client.Errors.End_Of_Stream then
      Status := Http_Client.Response_Streams.Close (Stream);
   else
      declare
         Close_Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.Response_Streams.Close (Stream);
         pragma Unreferenced (Close_Status);
      begin
         null;
      end;
   end if;
end Git_Chunked_Upload_With_Trailers;
