with Ada.Streams;
with Http_Client.Errors;

with Ada.Unchecked_Deallocation;

package body Example_Helpers is
   procedure Free is new Ada.Unchecked_Deallocation (Byte_Buffer, Byte_Buffer_Access);

   procedure Initialize
     (Item    : in out Static_Body_Producer;
      Payload : Ada.Streams.Stream_Element_Array) is
      Index : Positive := 1;
   begin
      if Item.Data /= null then
         Free (Item.Data);
      end if;

      if Payload'Length = 0 then
         Item.Data := null;
      else
         Item.Data := new Byte_Buffer (1 .. Natural (Payload'Length));
         for I in Payload'Range loop
            Item.Data (Index) := Character'Val (Integer (Payload (I)));
            Index := Index + 1;
         end loop;
      end if;
      Item.Position := 0;
   end Initialize;

   overriding function Read_Some
     (Item   : in out Static_Body_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status is
      Remaining : Natural;
      To_Copy   : Natural;
   begin
      if Item.Data = null then
         Count := 0;
         return Http_Client.Errors.Ok;
      end if;

      Remaining := Item.Data'Length - Item.Position;
      To_Copy := Natural'Min (Buffer'Length, Remaining);

      if To_Copy > 0 then
         for Offset in 0 .. To_Copy - 1 loop
            Buffer (Buffer'First + Offset) := Item.Data (Item.Data'First + Item.Position + Offset);
         end loop;
      end if;

      Item.Position := Item.Position + To_Copy;
      Count := To_Copy;
      return Http_Client.Errors.Ok;
   end Read_Some;

   overriding function Reset
     (Item : in out Static_Body_Producer) return Http_Client.Errors.Result_Status is
   begin
      Item.Position := 0;
      return Http_Client.Errors.Body_Not_Replayable;
   end Reset;

   procedure Feed_Git_Pkt_Line_Parser
     (Bytes : Ada.Streams.Stream_Element_Array) is
      pragma Unreferenced (Bytes);
   begin
      null;
   end Feed_Git_Pkt_Line_Parser;
end Example_Helpers;
