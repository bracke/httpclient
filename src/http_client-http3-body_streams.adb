with Ada.Streams; use Ada.Streams;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Http_Client.HTTP3.Body_Streams is

   function Open
     (B              : out Body_Stream;
      Max_Body_Size  : Natural := 1_048_576)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Max_Body_Size = 0 then
         B.Last_Result := Http_Client.Errors.Invalid_Configuration;
         return B.Last_Result;
      end if;

      B.Opened := True;
      B.Finished := False;
      B.Failed := False;
      B.Buffer := Null_Unbounded_String;
      B.Read_Offset := 1;
      B.Total := 0;
      B.Max_Body := Max_Body_Size;
      B.Last_Result := Http_Client.Errors.Ok;
      return Http_Client.Errors.Ok;
   end Open;

   function Append_Data
     (B    : in out Body_Stream;
      Data : String) return Http_Client.Errors.Result_Status
   is
   begin
      if not B.Opened or else B.Finished or else B.Failed then
         B.Last_Result := Http_Client.Errors.Not_Connected;
         return B.Last_Result;
      elsif Data'Length > B.Max_Body or else B.Total > B.Max_Body - Data'Length then
         B.Failed := True;
         B.Last_Result := Http_Client.Errors.Decoded_Body_Too_Large;
         return B.Last_Result;
      end if;

      Append (B.Buffer, Data);
      B.Total := B.Total + Data'Length;
      B.Last_Result := Http_Client.Errors.Ok;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         B.Failed := True;
         B.Last_Result := Http_Client.Errors.Internal_Error;
         return B.Last_Result;
   end Append_Data;

   function Append_Data
     (B    : in out Body_Stream;
      Data : Ada.Streams.Stream_Element_Array)
      return Http_Client.Errors.Result_Status
   is
      Text : String (1 .. Natural (Data'Length));
      Pos  : Natural := Text'First;
   begin
      for I in Data'Range loop
         Text (Pos) := Character'Val (Integer (Data (I)));
         Pos := Pos + 1;
      end loop;
      return Append_Data (B, Text);
   exception
      when others =>
         B.Failed := True;
         B.Last_Result := Http_Client.Errors.Internal_Error;
         return B.Last_Result;
   end Append_Data;

   function Mark_End_Stream
     (B : in out Body_Stream) return Http_Client.Errors.Result_Status
   is
   begin
      if not B.Opened or else B.Failed then
         B.Last_Result := Http_Client.Errors.Not_Connected;
      else
         B.Finished := True;
         B.Last_Result := Http_Client.Errors.Ok;
      end if;
      return B.Last_Result;
   end Mark_End_Stream;

   function Is_Open (B : Body_Stream) return Boolean is
   begin
      return B.Opened and then not B.Failed;
   end Is_Open;

   function Last_Status (B : Body_Stream) return Http_Client.Errors.Result_Status is
   begin
      return B.Last_Result;
   end Last_Status;

   function Read_Some
     (B      : in out Body_Stream;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status
   is
      Data      : constant String := To_String (B.Buffer);
      Available : Natural;
      Take      : Natural;
   begin
      Last := 0;

      if Buffer'Length = 0 then
         B.Last_Result := Http_Client.Errors.Invalid_Request;
         return B.Last_Result;
      elsif not B.Opened then
         B.Last_Result := Http_Client.Errors.Not_Connected;
         return B.Last_Result;
      elsif B.Failed then
         return B.Last_Result;
      end if;

      if B.Read_Offset <= Data'Last then
         Available := Natural (Data'Last - B.Read_Offset + 1);
         Take := Natural'Min (Available, Buffer'Length);
         Buffer (Buffer'First .. Buffer'First + Take - 1) :=
           Data (B.Read_Offset .. B.Read_Offset + Take - 1);
         B.Read_Offset := B.Read_Offset + Take;
         Last := Take;
         B.Last_Result := Http_Client.Errors.Ok;
         return Http_Client.Errors.Ok;
      elsif B.Finished then
         B.Opened := False;
         B.Last_Result := Http_Client.Errors.End_Of_Stream;
         return B.Last_Result;
      else
         B.Last_Result := Http_Client.Errors.Timeout;
         return B.Last_Result;
      end if;
   exception
      when others =>
         B.Failed := True;
         B.Last_Result := Http_Client.Errors.Internal_Error;
         Last := 0;
         return B.Last_Result;
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
         B.Failed := True;
         B.Last_Result := Http_Client.Errors.Internal_Error;
         Last := Buffer'First;
         return B.Last_Result;
   end Read_Some;

   function Close (B : in out Body_Stream) return Http_Client.Errors.Result_Status is
   begin
      B.Opened := False;
      B.Finished := True;
      B.Failed := False;
      B.Buffer := Null_Unbounded_String;
      B.Read_Offset := 1;
      B.Last_Result := Http_Client.Errors.Ok;
      return Http_Client.Errors.Ok;
   end Close;

end Http_Client.HTTP3.Body_Streams;
