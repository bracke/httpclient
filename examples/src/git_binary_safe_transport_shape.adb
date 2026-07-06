with Ada.Streams;

with Example_Helpers;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Response_Streams;
with Http_Client.Types;
with Http_Client.URI;

procedure Git_Binary_Safe_Transport_Shape is
   use type Http_Client.Errors.Result_Status;
   use type Ada.Streams.Stream_Element_Offset;

   Pkt_Line_Like : constant Ada.Streams.Stream_Element_Array :=
     (16#30#, 16#30#, 16#30#, 16#38#, 16#00#, 16#0D#, 16#0A#, 16#FF#, 16#80#);
   URI     : Http_Client.URI.URI_Reference;
   Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Request : Http_Client.Requests.Request;
   Stream  : Http_Client.Response_Streams.Streaming_Response;
   Options : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
   Buffer  : Ada.Streams.Stream_Element_Array (1 .. 1);
   Last    : Ada.Streams.Stream_Element_Offset;
   Status  : Http_Client.Errors.Result_Status;
begin
   Example_Helpers.Feed_Git_Pkt_Line_Parser (Pkt_Line_Like);
   Options.Cookie_Jar := null;
   Options.Enable_Decompression := False;

   Status := Http_Client.URI.Parse
     ("https://example.invalid/repo.git/info/refs?service=git-upload-pack", URI);
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

   --  Deliberately read bytes as bytes. Do not use string body convenience paths for Git data.
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
end Git_Binary_Safe_Transport_Shape;
