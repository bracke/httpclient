with Http_Client.Response_Streams;

procedure Streaming_Download is
   Options : Http_Client.Response_Streams.Streaming_Options :=
     Http_Client.Response_Streams.Default_Streaming_Options;
begin
   Options.Max_Header_Size := 65_536;
   Options.Max_Body_Size := 1_048_576;
end Streaming_Download;
