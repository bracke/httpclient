with Ada.Streams;

package body Http_Client.Binary_Test_Data is
   use type Ada.Streams.Stream_Element_Offset;

   function Empty return Ada.Streams.Stream_Element_Array is
   begin
      return Result : Ada.Streams.Stream_Element_Array (1 .. 0) do
         null;
      end return;
   end Empty;

   function One_NUL return Ada.Streams.Stream_Element_Array is
   begin
      return Result : Ada.Streams.Stream_Element_Array (1 .. 1) do
         Result (1) := 0;
      end return;
   end One_NUL;

   function All_Bytes return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 256);
   begin
      for I in Result'Range loop
         Result (I) := Ada.Streams.Stream_Element (I - Result'First);
      end loop;
      return Result;
   end All_Bytes;

   function CRLF_Heavy return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 25);
   begin
      Result :=
        [1 => 16#41#, 2 => 16#0D#, 3 => 16#0A#, 4 => 16#42#,
         5 => 16#0D#, 6 => 16#0A#, 7 => 16#0D#, 8 => 16#0A#,
         9 => 16#48#, 10 => 16#65#, 11 => 16#61#, 12 => 16#64#,
         13 => 16#65#, 14 => 16#72#, 15 => 16#3A#, 16 => 16#20#,
         17 => 16#76#, 18 => 16#61#, 19 => 16#6C#, 20 => 16#75#,
         21 => 16#65#, 22 => 16#0D#, 23 => 16#0A#, 24 => 16#00#,
         25 => 16#FF#];
      return Result;
   end CRLF_Heavy;

   function Git_Pkt_Line_Like return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 28);
   begin
      Result :=
        [1 => 16#30#, 2 => 16#30#, 3 => 16#30#, 4 => 16#38#,
         5 => 16#4E#, 6 => 16#41#, 7 => 16#4B#, 8 => 16#0A#,
         9 => 16#30#, 10 => 16#30#, 11 => 16#30#, 12 => 16#30#,
         13 => 16#30#, 14 => 16#30#, 15 => 16#31#, 16 => 16#65#,
         17 => 16#77#, 18 => 16#61#, 19 => 16#6E#, 20 => 16#74#,
         21 => 16#20#, 22 => 16#61#, 23 => 16#62#, 24 => 16#63#,
         25 => 16#64#, 26 => 16#65#, 27 => 16#66#, 28 => 16#0A#];
      return Result;
   end Git_Pkt_Line_Like;

   function Git_Packfile_Like return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 30);
   begin
      Result :=
        [1 => 16#50#, 2 => 16#41#, 3 => 16#43#, 4 => 16#4B#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#02#,
         9 => 16#00#, 10 => 16#00#, 11 => 16#00#, 12 => 16#01#,
         13 => 16#78#, 14 => 16#9C#, 15 => 16#63#, 16 => 16#60#,
         17 => 16#60#, 18 => 16#60#, 19 => 16#00#, 20 => 16#00#,
         21 => 16#00#, 22 => 16#04#, 23 => 16#00#, 24 => 16#01#,
         25 => 16#FF#, 26 => 16#00#, 27 => 16#80#, 28 => 16#7F#,
         29 => 16#0D#, 30 => 16#0A#];
      return Result;
   end Git_Packfile_Like;

   function Compressed_Looking return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 24);
   begin
      Result :=
        [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
         5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
         9 => 16#02#, 10 => 16#03#, 11 => 16#78#, 12 => 16#9C#,
         13 => 16#ED#, 14 => 16#C3#, 15 => 16#01#, 16 => 16#0D#,
         17 => 16#00#, 18 => 16#00#, 19 => 16#00#, 20 => 16#C2#,
         21 => 16#A0#, 22 => 16#F7#, 23 => 16#4F#, 24 => 16#6D#];
      return Result;
   end Compressed_Looking;

   function Long_Buffer_Boundary return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. 4099);
   begin
      for I in Result'Range loop
         Result (I) := Ada.Streams.Stream_Element ((I - Result'First) mod 256);
      end loop;
      Result (2048) := 16#0D#;
      Result (2049) := 16#0A#;
      Result (2050) := 16#0D#;
      Result (2051) := 16#0A#;
      return Result;
   end Long_Buffer_Boundary;

   function To_String (Data : Ada.Streams.Stream_Element_Array) return String is
   begin
      if Data'Length = 0 then
         return "";
      end if;

      return Result : String (1 .. Natural (Data'Length)) do
         declare
            Cursor : Natural := Result'First;
         begin
            for B of Data loop
               Result (Cursor) := Character'Val (Natural (B));
               Cursor := Cursor + 1;
            end loop;
         end;
      end return;
   end To_String;
end Http_Client.Binary_Test_Data;
