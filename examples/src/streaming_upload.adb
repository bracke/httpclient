with Http_Client.Request_Bodies;

procedure Streaming_Upload is
   B : constant Http_Client.Request_Bodies.Request_Body :=
     Http_Client.Request_Bodies.From_String ("payload");
begin
   if Http_Client.Request_Bodies.Is_Replayable (B) then
      null;
   end if;
end Streaming_Upload;
