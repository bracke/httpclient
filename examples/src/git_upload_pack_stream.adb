with Ada.Streams;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Upload_Pack_Stream is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Upload_Body : constant Ada.Streams.Stream_Element_Array :=
     (16#30#, 16#30#, 16#30#, 16#38#, 16#77#, 16#61#, 16#6E#, 16#74#);
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
   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/git-upload-pack", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Content-Type", "application/x-git-upload-pack-request");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Accept", "application/x-git-upload-pack-result");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI => URI,
         Item => Request,
         Headers => Headers,
         Auto_Host => True);
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Requests.Set_Body
        (Request, Http_Client.Request_Bodies.From_Bytes (Upload_Body));
   end if;
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
   end if;

   while Status = Http_Client.Errors.Ok loop
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      if Status = Http_Client.Errors.Ok and then Last >= Buffer'First then
         null;
      end if;
   end loop;

   Status := Http_Client.Response_Streams.Close (Stream);
end Git_Upload_Pack_Stream;
