with Ada.Streams;
with Ada.Text_IO;

with Http_Client.Errors; use Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Info_Refs_HTTP3_Stream is
   URI     : Http_Client.URI.URI_Reference;
   Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request : Http_Client.Requests.Request;
   Stream  : Http_Client.Response_Streams.Streaming_Response;
   Options : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Status  : Http_Client.Errors.Result_Status;
   Buffer  : Ada.Streams.Stream_Element_Array (1 .. 8192);
   Last    : Ada.Streams.Stream_Element_Offset;
begin
   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("invalid URI");
      return;
   end if;

   Status := Http_Client.Headers.Set (Headers, "Accept", "*/*");
   Status := Http_Client.Headers.Set (Headers, "Git-Protocol", "version=2");
   Status := Http_Client.Headers.Set (Headers, "Accept-Encoding", "identity");

   Status := Http_Client.Requests.Create
     (Method  => Http_Client.Types.GET,
      URI     => URI,
      Item    => Request,
      Headers => Headers);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("request build failed");
      return;
   end if;

   Options.Protocol_Policy := Http_Client.Response_Streams.Streaming_Prefer_HTTP_3;
   Options.HTTP3.Mode := Http_Client.HTTP3.HTTP3_Allowed;
   Options.HTTP3.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
   Options.Enable_Decompression := False;

   Status := Http_Client.Response_Streams.Open (Request, Stream, Options);
   if Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("stream open failed or no QUIC backend available");
      return;
   end if;

   loop
      Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
      exit when Status = Http_Client.Errors.End_Of_Stream;
      exit when Status /= Http_Client.Errors.Ok;
      --  Feed Buffer (Buffer'First .. Last) into the Git pkt-line parser.
   end loop;

   Status := Http_Client.Response_Streams.Close (Stream);
end Git_Info_Refs_HTTP3_Stream;
