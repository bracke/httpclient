with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Streams; use Http_Client.HTTP2.Streams;

with Ada.Streams; use Ada.Streams;

package body Http_Client.HTTP2.Body_Streams is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP2.Streams.Stream_State;

   function Terminal_Error
     (Status : Http_Client.Errors.Result_Status) return Boolean is
   begin
      return Status /= Http_Client.Errors.Ok
        and then Status /= Http_Client.Errors.End_Of_Stream;
   end Terminal_Error;

   function Open
     (Connection  : Connection_Access;
      Stream      : Http_Client.HTTP2.Frames.Stream_ID;
      B           : out Body_Stream) return Http_Client.Errors.Result_Status
   is
      State  : Http_Client.HTTP2.Streams.Stream_State;
      Status : Http_Client.Errors.Result_Status;
   begin
      B := (Conn        => null,
               Stream      => 0,
               Offset      => 0,
               Opened      => False,
               Finished    => True,
               Last_Result => Http_Client.Errors.Ok);

      if Connection = null then
         B.Last_Result := Http_Client.Errors.Not_Connected;
         return B.Last_Result;
      end if;

      Status := Http_Client.HTTP2.Connection.Begin_Public_Response_Stream
        (Connection.all, Stream);
      if Status /= Http_Client.Errors.Ok then
         B.Last_Result := Status;
         return Status;
      end if;

      State := Http_Client.HTTP2.Connection.Stream_State_Of (Connection.all, Stream);
      Status := Http_Client.HTTP2.Connection.Stream_Status_Of (Connection.all, Stream);

      if Status /= Http_Client.Errors.Ok then
         B.Last_Result := Status;
         return Status;
      elsif State = Http_Client.HTTP2.Streams.Idle
        or else State = Http_Client.HTTP2.Streams.Reset
      then
         B.Last_Result := Http_Client.Errors.HTTP2_Stream_State_Error;
         return B.Last_Result;
      end if;

      B.Conn := Connection;
      B.Stream := Stream;
      B.Offset := 0;
      B.Opened := True;
      B.Finished := False;
      B.Last_Result := Http_Client.Errors.Ok;
      return Http_Client.Errors.Ok;
   end Open;

   function Is_Open (B : Body_Stream) return Boolean is
   begin
      return B.Opened and then not B.Finished and then B.Conn /= null;
   end Is_Open;

   function Last_Status (B : Body_Stream) return Http_Client.Errors.Result_Status is
   begin
      return B.Last_Result;
   end Last_Status;

   function Read_Some
     (B   : in out Body_Stream;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      State  : Http_Client.HTTP2.Streams.Stream_State;
      Status : Http_Client.Errors.Result_Status;
   begin
      Last := 0;

      if not Is_Open (B) then
         if B.Finished and then B.Last_Result = Http_Client.Errors.End_Of_Stream then
            return Http_Client.Errors.End_Of_Stream;
         end if;
         B.Last_Result := Http_Client.Errors.Not_Connected;
         return B.Last_Result;
      end if;

      Status := Http_Client.HTTP2.Connection.Stream_Status_Of (B.Conn.all, B.Stream);
      if Terminal_Error (Status) then
         State := Http_Client.HTTP2.Connection.Stream_State_Of
           (B.Conn.all, B.Stream);

         --  A deterministic stream failure reported through the public body
         --  stream is also the caller's final observation point for that
         --  stream.  Preserve the original status for the caller, but release
         --  queued DATA, public-stream slots, and the tracked stream slot where
         --  the synchronous in-memory model can do so safely.  This covers
         --  unsupported trailers, content-length mismatch, body-size limits,
         --  bodyless-DATA errors, GOAWAY-failed streams, and peer resets.
         declare
            Cleanup_Status : Http_Client.Errors.Result_Status :=
              Http_Client.Errors.Ok;
            Remaining : Natural := 0;
         begin
            if State = Http_Client.HTTP2.Streams.Reset then
               Cleanup_Status := Http_Client.HTTP2.Connection.Release_Stream
                 (B.Conn.all, B.Stream);
            elsif State = Http_Client.HTTP2.Streams.Closed then
               Remaining := Http_Client.HTTP2.Connection.Buffered_Response_Bytes
                 (B.Conn.all, B.Stream);
               if Remaining > 0 then
                  Cleanup_Status := Http_Client.HTTP2.Connection.Consume_Response_Bytes
                    (B.Conn.all, B.Stream, Remaining);
               end if;
               if Cleanup_Status = Http_Client.Errors.Ok then
                  Cleanup_Status := Http_Client.HTTP2.Connection.Release_Stream
                    (B.Conn.all, B.Stream);
               end if;
            else
               Cleanup_Status := Http_Client.HTTP2.Connection.Cancel_Stream
                 (B.Conn.all, B.Stream);
               if Cleanup_Status = Http_Client.Errors.Ok then
                  Cleanup_Status := Http_Client.HTTP2.Connection.Release_Stream
                    (B.Conn.all, B.Stream);
               end if;
            end if;

            B.Opened := False;
            B.Finished := True;
            B.Last_Result :=
              (if Cleanup_Status = Http_Client.Errors.Ok then Status
               else Cleanup_Status);
            return B.Last_Result;
         end;
      end if;

      declare
         Data      : constant String :=
           Http_Client.HTTP2.Connection.Response_Body_Of (B.Conn.all, B.Stream);
         Available : Natural;
         Count     : Natural;
      begin
         if Data'Length > 0 then
            Available := Data'Length;
            Count := Natural'Min (Available, Buffer'Length);
            if Count > 0 then
               Buffer (Buffer'First .. Buffer'First + Count - 1) :=
                 Data (Data'First .. Data'First + Integer (Count) - 1);
               Status := Http_Client.HTTP2.Connection.Consume_Response_Bytes
                 (B.Conn.all, B.Stream, Count);
               if Status /= Http_Client.Errors.Ok then
                  B.Opened := False;
                  B.Finished := True;
                  B.Last_Result := Status;
                  return Status;
               end if;
               B.Offset := 0;
               Last := Count;
               B.Last_Result := Http_Client.Errors.Ok;
               return Http_Client.Errors.Ok;
            end if;
         end if;
      end;

      State := Http_Client.HTTP2.Connection.Stream_State_Of (B.Conn.all, B.Stream);
      if State = Http_Client.HTTP2.Streams.Closed then
         Status := Http_Client.HTTP2.Connection.Release_Stream (B.Conn.all, B.Stream);
         B.Opened := False;
         B.Finished := True;
         B.Last_Result := (if Status = Http_Client.Errors.Ok then
                                Http_Client.Errors.End_Of_Stream
                              else Status);
         return B.Last_Result;
      elsif State = Http_Client.HTTP2.Streams.Half_Closed_Remote then
         Status := Http_Client.HTTP2.Connection.End_Public_Response_Stream
           (B.Conn.all, B.Stream);
         B.Opened := False;
         B.Finished := True;
         B.Last_Result := (if Status = Http_Client.Errors.Ok then
                                Http_Client.Errors.End_Of_Stream
                              else Status);
         return B.Last_Result;
      elsif State = Http_Client.HTTP2.Streams.Reset then
         declare
            Reset_Status : constant Http_Client.Errors.Result_Status :=
              Http_Client.HTTP2.Connection.Stream_Status_Of (B.Conn.all, B.Stream);
         begin
            Status := Http_Client.HTTP2.Connection.Release_Stream (B.Conn.all, B.Stream);
            B.Opened := False;
            B.Finished := True;
            if Reset_Status /= Http_Client.Errors.Ok then
               B.Last_Result := Reset_Status;
            elsif Status /= Http_Client.Errors.Ok then
               B.Last_Result := Status;
            else
               B.Last_Result := Http_Client.Errors.HTTP2_Stream_Reset;
            end if;
            return B.Last_Result;
         end;
      else
         --  Synchronous scripted model: no queued DATA is available yet, but
         --  END_STREAM has not been observed. A production transport would block
         --  or poll for more frames; this deterministic adapter reports Timeout
         --  rather than a false EOF.
         B.Last_Result := Http_Client.Errors.Timeout;
         return B.Last_Result;
      end if;
   end Read_Some;



   function Read_Some
     (B      : in out Body_Stream;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status
   is
      Text_Last : Natural := 0;
      Status    : Http_Client.Errors.Result_Status;
   begin
      if Buffer'Length = 0 then
         Last := Buffer'First;
         B.Last_Result := Http_Client.Errors.Invalid_Request;
         return B.Last_Result;
      end if;

      declare
         Temp : String (1 .. Natural (Buffer'Length));
      begin
         Status := Read_Some (B, Temp, Text_Last);
         if Text_Last = 0 then
            Last := Buffer'First - 1;
         else
            for I in 0 .. Text_Last - 1 loop
               Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (I)) :=
                 Ada.Streams.Stream_Element
                   (Character'Pos (Temp (Temp'First + I)));
            end loop;
            Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Text_Last) - 1;
         end if;
         return Status;
      end;
   exception
      when others =>
         B.Opened := False;
         B.Finished := True;
         B.Last_Result := Http_Client.Errors.Internal_Error;
         Last := Buffer'First;
         return B.Last_Result;
   end Read_Some;

   function Close (B : in out Body_Stream) return Http_Client.Errors.Result_Status is
      State  : Http_Client.HTTP2.Streams.Stream_State;
      Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   begin
      if B.Conn = null or else not B.Opened then
         B.Opened := False;
         B.Finished := True;
         B.Last_Result := Http_Client.Errors.Ok;
         return Http_Client.Errors.Ok;
      end if;

      State := Http_Client.HTTP2.Connection.Stream_State_Of (B.Conn.all, B.Stream);
      if State = Http_Client.HTTP2.Streams.Half_Closed_Remote then
         declare
            Remaining : constant Natural :=
              Http_Client.HTTP2.Connection.Buffered_Response_Bytes
                (B.Conn.all, B.Stream);
         begin
            if Remaining > 0 then
               Status := Http_Client.HTTP2.Connection.Consume_Response_Bytes
                 (B.Conn.all, B.Stream, Remaining);
            end if;
            if Status = Http_Client.Errors.Ok then
               Status := Http_Client.HTTP2.Connection.End_Public_Response_Stream
                 (B.Conn.all, B.Stream);
            end if;
         end;
      elsif State /= Http_Client.HTTP2.Streams.Closed
        and then State /= Http_Client.HTTP2.Streams.Reset
      then
         Status := Http_Client.HTTP2.Connection.Cancel_Stream (B.Conn.all, B.Stream);
         if Status = Http_Client.Errors.Ok then
            Status := Http_Client.HTTP2.Connection.Release_Stream (B.Conn.all, B.Stream);
         end if;
      elsif State = Http_Client.HTTP2.Streams.Reset then
         Status := Http_Client.HTTP2.Connection.Release_Stream (B.Conn.all, B.Stream);
      elsif State = Http_Client.HTTP2.Streams.Closed then
         declare
            Remaining : constant Natural :=
              Http_Client.HTTP2.Connection.Buffered_Response_Bytes
                (B.Conn.all, B.Stream);
         begin
            --  END_STREAM has already arrived. Closing before the caller reads
            --  every queued byte discards the unread tail, credits the receive
            --  windows, and releases the tracking slot without resetting the
            --  already-finished stream.
            if Remaining > 0 then
               Status := Http_Client.HTTP2.Connection.Consume_Response_Bytes
                 (B.Conn.all, B.Stream, Remaining);
            end if;
            if Status = Http_Client.Errors.Ok then
               Status := Http_Client.HTTP2.Connection.Release_Stream (B.Conn.all, B.Stream);
            end if;
         end;
      end if;

      B.Opened := False;
      B.Finished := True;
      B.Last_Result := Status;
      return Status;
   end Close;
end Http_Client.HTTP2.Body_Streams;
