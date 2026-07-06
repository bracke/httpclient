with Http_Client.HTTP2.Connection;
with Http_Client.Request_Bodies;

package body Http_Client.HTTP2.Uploads is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Request_Bodies.Body_Kind;

   function Send_Chunk
     (Connection : in out Http_Client.HTTP2.Connection.Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      Length     : Natural;
      Last       : Boolean;
      Result     : in out Upload_Result) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.HTTP2.Connection.Send_Data
        (Connection, Stream, Length, Last);
      if Status = Http_Client.Errors.Ok then
         Result.Bytes_Sent := Result.Bytes_Sent + Length;
         Result.Data_Frames := Result.Data_Frames + 1;
         Result.End_Stream_Sent := Last;
      end if;
      return Status;
   end Send_Chunk;

   function Send_Body
     (Connection : in out Http_Client.HTTP2.Connection.Connection_State;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      B       : Http_Client.Request_Bodies.Request_Body;
      Result     : out Upload_Result) return Http_Client.Errors.Result_Status
   is
      Kind            : constant Http_Client.Request_Bodies.Body_Kind :=
        Http_Client.Request_Bodies.Kind (B);
      Declared_Length : Natural := 0;
      Has_Length      : constant Boolean :=
        Http_Client.Request_Bodies.Declared_Length (B, Declared_Length);
      Sent            : Natural := 0;
      Max_Frame       : Natural;
      Window          : Natural;
      Quantum         : Natural;
      Count           : Natural;
      Status          : Http_Client.Errors.Result_Status;

      function Finish
        (Value : Http_Client.Errors.Result_Status)
         return Http_Client.Errors.Result_Status
      is
         Release_Status : Http_Client.Errors.Result_Status;
      begin
         Release_Status := Http_Client.HTTP2.Connection.End_Upload_Stream
           (Connection, Stream);
         if Value = Http_Client.Errors.Ok then
            return Release_Status;
         else
            return Value;
         end if;
      end Finish;

      function Send_Trailers_And_Finish return Http_Client.Errors.Result_Status is
         Trailer_Status : Http_Client.Errors.Result_Status;
      begin
         Trailer_Status := Http_Client.HTTP2.Connection.Send_Trailers
           (Connection, Stream, Http_Client.Request_Bodies.Trailers (B));
         if Trailer_Status = Http_Client.Errors.Ok then
            Result.End_Stream_Sent := True;
            Result.Trailer_Headers := 1;
         end if;
         return Finish (Trailer_Status);
      end Send_Trailers_And_Finish;
   begin
      Result :=
        (Bytes_Sent => 0,
         Data_Frames => 0,
         End_Stream_Sent => False,
         Trailer_Headers => 0);

      Status := Http_Client.HTTP2.Connection.Begin_Upload_Stream (Connection, Stream);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      if Kind = Http_Client.Request_Bodies.Unknown_Length_Stream
        and then not Http_Client.HTTP2.Connection.Allow_Unknown_Length_HTTP2_Bodies (Connection)
      then
         return Finish (Http_Client.Errors.Unsupported_Feature);
      end if;

      if Kind = Http_Client.Request_Bodies.Empty_Body then
         if Http_Client.Request_Bodies.Has_Trailers (B) then
            return Send_Trailers_And_Finish;
         else
            Status := Http_Client.HTTP2.Connection.End_Local_Stream (Connection, Stream);
            if Status = Http_Client.Errors.Ok then
               Result.End_Stream_Sent := True;
            end if;
            return Finish (Status);
         end if;
      end if;

      Max_Frame := Http_Client.HTTP2.Connection.Peer_Max_Data_Frame_Size (Connection);
      if Max_Frame = 0 then
         return Finish (Http_Client.Errors.Invalid_Configuration);
      end if;

      if Kind = Http_Client.Request_Bodies.Buffered_Body then
         declare
            Payload : constant String := Http_Client.Request_Bodies.Buffered_Payload (B);
            Pos     : Natural := 0;
         begin
            if Has_Length and then Payload'Length /= Declared_Length then
               return Finish (Http_Client.Errors.Body_Length_Mismatch);
            end if;

            if Payload'Length = 0 then
               if Http_Client.Request_Bodies.Has_Trailers (B) then
                  return Send_Trailers_And_Finish;
               else
                  Status := Http_Client.HTTP2.Connection.End_Local_Stream (Connection, Stream);
                  if Status = Http_Client.Errors.Ok then
                     Result.End_Stream_Sent := True;
                  end if;
                  return Finish (Status);
               end if;
            end if;

            while Pos < Payload'Length loop
               Window := Natural'Min
                 (Http_Client.HTTP2.Connection.Connection_Send_Window (Connection),
                  Http_Client.HTTP2.Connection.Stream_Send_Window (Connection, Stream));
               if Window = 0 then
                  return Finish (Http_Client.Errors.Timeout);
               end if;
               Quantum := Natural'Min (Natural'Min (Max_Frame, Window), Payload'Length - Pos);
               Status := Send_Chunk
                 (Connection,
                  Stream,
                  Quantum,
                  Pos + Quantum = Payload'Length
                    and then not Http_Client.Request_Bodies.Has_Trailers (B),
                  Result);
               if Status /= Http_Client.Errors.Ok then
                  return Finish (Status);
               end if;
               Pos := Pos + Quantum;
            end loop;
            if Http_Client.Request_Bodies.Has_Trailers (B) then
               return Send_Trailers_And_Finish;
            else
               return Finish (Http_Client.Errors.Ok);
            end if;
         end;
      end if;

      if not Http_Client.Request_Bodies.Has_Producer (B) then
         return Finish (Http_Client.Errors.Body_Producer_Failed);
      end if;

      loop
         Window := Natural'Min
           (Http_Client.HTTP2.Connection.Connection_Send_Window (Connection),
            Http_Client.HTTP2.Connection.Stream_Send_Window (Connection, Stream));
         if Window = 0 then
            return Finish (Http_Client.Errors.Timeout);
         end if;

         if Has_Length and then Sent >= Declared_Length then
            if Http_Client.Request_Bodies.Has_Trailers (B) then
               return Send_Trailers_And_Finish;
            else
               Status := Http_Client.HTTP2.Connection.End_Local_Stream (Connection, Stream);
               if Status = Http_Client.Errors.Ok then
                  Result.End_Stream_Sent := True;
               end if;
               return Finish (Status);
            end if;
         end if;

         Quantum := Natural'Min (Max_Frame, Window);
         if Has_Length then
            Quantum := Natural'Min (Quantum, Declared_Length - Sent);
         end if;

         declare
            Buffer : String (1 .. Positive'Max (1, Quantum));
         begin
            Status := Http_Client.Request_Bodies.Read_Next (B, Buffer, Count);
            if Status /= Http_Client.Errors.Ok then
               return Finish (Status);
            end if;
         end;

         if Count = 0 then
            if Has_Length and then Sent /= Declared_Length then
               return Finish (Http_Client.Errors.Body_Length_Mismatch);
            end if;
            if Http_Client.Request_Bodies.Has_Trailers (B) then
               return Send_Trailers_And_Finish;
            else
               Status := Http_Client.HTTP2.Connection.End_Local_Stream (Connection, Stream);
               if Status = Http_Client.Errors.Ok then
                  Result.End_Stream_Sent := True;
               end if;
               return Finish (Status);
            end if;
         end if;

         if Count > Quantum then
            return Finish (Http_Client.Errors.Body_Length_Mismatch);
         end if;

         if Has_Length and then Sent + Count = Declared_Length then
            declare
               Extra_Buffer : String (1 .. 1);
               Extra_Count  : Natural;
            begin
               Status := Http_Client.Request_Bodies.Read_Next
                 (B, Extra_Buffer, Extra_Count);
               if Status /= Http_Client.Errors.Ok then
                  return Finish (Status);
               elsif Extra_Count /= 0 then
                  return Finish (Http_Client.Errors.Body_Length_Mismatch);
               end if;
            end;
         end if;

         Sent := Sent + Count;
         if Has_Length and then Sent > Declared_Length then
            return Finish (Http_Client.Errors.Body_Length_Mismatch);
         end if;

         Status := Send_Chunk
           (Connection,
            Stream,
            Count,
            Has_Length and then Sent = Declared_Length
              and then not Http_Client.Request_Bodies.Has_Trailers (B),
            Result);
         if Status /= Http_Client.Errors.Ok then
            return Finish (Status);
         end if;

         if Has_Length and then Sent = Declared_Length then
            if Http_Client.Request_Bodies.Has_Trailers (B) then
               return Send_Trailers_And_Finish;
            else
               return Finish (Http_Client.Errors.Ok);
            end if;
         end if;
      end loop;
   end Send_Body;
end Http_Client.HTTP2.Uploads;
