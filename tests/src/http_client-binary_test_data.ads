with Ada.Streams;

package Http_Client.Binary_Test_Data is
   --  Shared byte corpus for final header/body binary-safety tests.
   --
   --  Every function returns explicit octets.  High-byte values are produced
   --  numerically so test behavior is independent of source-file encoding.

   function Empty return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Empty byte array fixture.
   function One_NUL return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Single-NUL byte fixture.
   function All_Bytes return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Fixture containing all byte values.
   function CRLF_Heavy return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Fixture containing CR/LF-heavy data.
   function Git_Pkt_Line_Like return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Git pkt-line-like binary fixture.
   function Git_Packfile_Like return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Git packfile-like binary fixture.
   function Compressed_Looking return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Compression-signature-like binary fixture.
   function Long_Buffer_Boundary return Ada.Streams.Stream_Element_Array;
   --  GNATdoc contract.
   --  @return Long binary fixture crossing buffer boundaries.

   function To_String (Data : Ada.Streams.Stream_Element_Array) return String;
   --  GNATdoc contract.
   --  @param Data Byte array to convert without text interpretation.
   --  @return String with the same byte values as Data.
end Http_Client.Binary_Test_Data;
