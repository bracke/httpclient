with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;

package body Http_Client.Request_Bodies is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use Http_Client.Errors;

   function Empty return Request_Body is
   begin
      return
        (Body_Type       => Empty_Body,
         Payload_Text    => Null_Unbounded_String,
         Stream_Producer    => null,
         Stream_Length      => 0,
         Replayable_Flag    => True,
         Trailer_Fields     => Http_Client.Headers.Empty,
         Has_Trailer_Fields => False);
   end Empty;

   function From_String (Payload : String) return Request_Body is
   begin
      if Payload'Length = 0 then
         return Empty;
      else
         return
           (Body_Type       => Buffered_Body,
            Payload_Text    => To_Unbounded_String (Payload),
            Stream_Producer    => null,
            Stream_Length      => Payload'Length,
            Replayable_Flag    => True,
            Trailer_Fields     => Http_Client.Headers.Empty,
            Has_Trailer_Fields => False);
      end if;
   end From_String;

   function From_Bytes
     (Payload : Ada.Streams.Stream_Element_Array) return Request_Body
   is
      Text : String (1 .. Natural (Payload'Length));
   begin
      if Payload'Length = 0 then
         return Empty;
      end if;
      for I in Payload'Range loop
         Text (1 + Natural (I - Payload'First)) :=
           Character'Val (Integer (Payload (I)));
      end loop;
      return From_String (Text);
   end From_Bytes;

   function From_Fixed_Length_Stream
     (Producer   : Body_Producer_Access;
      Length     : Natural;
      Replayable : Boolean := False) return Request_Body is
   begin
      return
        (Body_Type       => Fixed_Length_Stream,
         Payload_Text    => Null_Unbounded_String,
         Stream_Producer    => Producer,
         Stream_Length      => Length,
         Replayable_Flag    => Replayable,
         Trailer_Fields     => Http_Client.Headers.Empty,
         Has_Trailer_Fields => False);
   end From_Fixed_Length_Stream;

   function From_Unknown_Length_Stream
     (Producer   : Body_Producer_Access;
      Replayable : Boolean := False) return Request_Body is
   begin
      return
        (Body_Type       => Unknown_Length_Stream,
         Payload_Text    => Null_Unbounded_String,
         Stream_Producer    => Producer,
         Stream_Length      => 0,
         Replayable_Flag    => Replayable,
         Trailer_Fields     => Http_Client.Headers.Empty,
         Has_Trailer_Fields => False);
   end From_Unknown_Length_Stream;

   function From_Unknown_Length_Stream_With_Trailers
     (Producer   : Body_Producer_Access;
      Trailers   : Http_Client.Headers.Header_List;
      Replayable : Boolean := False) return Request_Body
   is
      Result : Request_Body :=
        From_Unknown_Length_Stream (Producer, Replayable);
   begin
      return With_Trailers (Result, Trailers);
   end From_Unknown_Length_Stream_With_Trailers;

   function With_Trailers
     (Item     : Request_Body;
      Trailers : Http_Client.Headers.Header_List) return Request_Body
   is
      Result : Request_Body := Item;
   begin
      Result.Trailer_Fields := Trailers;
      Result.Has_Trailer_Fields := Http_Client.Headers.Length (Trailers) > 0;
      return Result;
   end With_Trailers;

   function Has_Trailers (Item : Request_Body) return Boolean is
   begin
      return Item.Has_Trailer_Fields
        and then Http_Client.Headers.Length (Item.Trailer_Fields) > 0;
   end Has_Trailers;

   function Trailers
     (Item : Request_Body) return Http_Client.Headers.Header_List is
   begin
      return Item.Trailer_Fields;
   end Trailers;

   function Kind (Item : Request_Body) return Body_Kind is
   begin
      return Item.Body_Type;
   end Kind;

   function Has_Body (Item : Request_Body) return Boolean is
   begin
      case Item.Body_Type is
         when Empty_Body =>
            return False;
         when Buffered_Body =>
            return Length (Item.Payload_Text) > 0;
         when Fixed_Length_Stream =>
            return Item.Stream_Length > 0;
         when Unknown_Length_Stream =>
            return True;
      end case;
   end Has_Body;

   function Is_Replayable (Item : Request_Body) return Boolean is
   begin
      return Item.Replayable_Flag;
   end Is_Replayable;

   function Has_Producer (Item : Request_Body) return Boolean is
   begin
      case Item.Body_Type is
         when Empty_Body | Buffered_Body =>
            return True;
         when Fixed_Length_Stream | Unknown_Length_Stream =>
            return Item.Stream_Producer /= null;
      end case;
   end Has_Producer;

   function Declared_Length (Item : Request_Body; Length : out Natural)
      return Boolean is
   begin
      case Item.Body_Type is
         when Empty_Body =>
            Length := 0;
            return True;
         when Buffered_Body =>
            Length := Ada.Strings.Unbounded.Length (Item.Payload_Text);
            return True;
         when Fixed_Length_Stream =>
            Length := Item.Stream_Length;
            return True;
         when Unknown_Length_Stream =>
            Length := 0;
            return False;
      end case;
   end Declared_Length;

   function Buffered_Payload (Item : Request_Body) return String is
   begin
      if Item.Body_Type = Buffered_Body then
         return To_String (Item.Payload_Text);
      else
         return "";
      end if;
   end Buffered_Payload;

   function Buffered_Bytes
     (Item : Request_Body) return Ada.Streams.Stream_Element_Array
   is
      Text : constant String := Buffered_Payload (Item);
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for I in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (I - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (I)));
      end loop;
      return Data;
   end Buffered_Bytes;

   function Read_Next
     (Item   : Request_Body;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status is
   begin
      Count := 0;

      if Item.Stream_Producer = null then
         return Invalid_Request;
      end if;

      return Read_Some (Item.Stream_Producer.all, Buffer, Count);
   exception
      when others =>
         Count := 0;
         return Body_Producer_Failed;
   end Read_Next;

   function Read_Next
     (Item   : Request_Body;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status
   is
      Count  : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      if Buffer'Length = 0 then
         Last := Buffer'First;
         return Invalid_Request;
      end if;
      declare
         Temp : String (1 .. Natural (Buffer'Length));
      begin
         Status := Read_Next (Item, Temp, Count);
         if Count = 0 then
            Last := Buffer'First - 1;
         else
            for I in 0 .. Count - 1 loop
               Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (I)) :=
                 Ada.Streams.Stream_Element (Character'Pos (Temp (Temp'First + I)));
            end loop;
            Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
         end if;
         return Status;
      end;
   exception
      when others =>
         Last := Buffer'First;
         return Body_Producer_Failed;
   end Read_Next;

   function Reset_Body
     (Item : Request_Body) return Http_Client.Errors.Result_Status is
   begin
      if Item.Body_Type = Empty_Body or else Item.Body_Type = Buffered_Body then
         return Ok;
      end if;

      if not Item.Replayable_Flag then
         return Body_Not_Replayable;
      end if;

      if Item.Stream_Producer = null then
         return Invalid_Request;
      end if;

      return Reset (Item.Stream_Producer.all);
   exception
      when others =>
         return Body_Producer_Failed;
   end Reset_Body;

end Http_Client.Request_Bodies;
