with Ada.Streams;

with Http_Client.Errors;
with Http_Client.Request_Bodies;

package Example_Helpers is
   type Static_Body_Producer is limited new Http_Client.Request_Bodies.Body_Producer with private;

   procedure Initialize
     (Item    : in out Static_Body_Producer;
      Payload : Ada.Streams.Stream_Element_Array);
   --  GNATdoc contract.
   --  @param Item Static body producer initialized by this procedure.
   --  @param Payload Byte payload that the producer will replay.

   overriding function Read_Some
     (Item   : in out Static_Body_Producer;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Static body producer to read from.
   --  @param Buffer Output buffer receiving body bytes.
   --  @param Count Number of characters written to Buffer.
   --  @return Ok, End_Of_Stream, or a deterministic failure status.

   overriding function Reset
     (Item : in out Static_Body_Producer) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Static body producer to rewind.
   --  @return Ok when the producer is reset.

   procedure Feed_Git_Pkt_Line_Parser
     (Bytes : Ada.Streams.Stream_Element_Array);
   --  GNATdoc contract.
   --  @param Bytes Git pkt-line-like bytes to feed to the example parser.

private
   type Byte_Buffer is array (Positive range <>) of Character;
   type Byte_Buffer_Access is access Byte_Buffer;

   type Static_Body_Producer is limited new Http_Client.Request_Bodies.Body_Producer with record
      Data     : Byte_Buffer_Access := null;
      Position : Natural := 0;
   end record;
end Example_Helpers;
