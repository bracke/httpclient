with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Decompression;

procedure Git_Streaming_Decompression is
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
   --  Git callers usually prefer identity. This shows explicit opt-in only.
   Options.Enable_Decompression := True;
   Options.Decompression.Deflate_Mode := Http_Client.Decompression.Auto_Zlib_Then_Raw;
   Options.Decompression.Maximum_Decoded_Body_Size := 64 * 1024 * 1024;

   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Headers.Set
        (Headers, "Accept-Encoding", Http_Client.Decompression.Supported_Accept_Encoding);
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
end Git_Streaming_Decompression;
