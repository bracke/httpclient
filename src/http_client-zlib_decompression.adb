with Ada.Streams;
with Ada.Strings.Unbounded;

with Zlib;

package body Http_Client.Zlib_Decompression is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Errors.Result_Status;

   Output_Chunk_Size : constant Ada.Streams.Stream_Element_Offset := 16_384;

   function Header_For (Format : Wrapper_Format) return Zlib.Header_Type is
   begin
      case Format is
         when Gzip =>
            return Zlib.GZip;
         when Zlib_Wrapped_Deflate =>
            return Zlib.Zlib_Header;
         when Raw_Deflate =>
            return Zlib.Raw_Deflate;
      end case;
   end Header_For;

   function Looks_Like_Zlib_Header (Input : String) return Boolean is
   begin
      if Input'Length < 2 then
         return False;
      end if;

      return Zlib.Looks_Like_Zlib_Header
        ([1 => Zlib.Byte (Character'Pos (Input (Input'First))),
          2 => Zlib.Byte (Character'Pos (Input (Input'First + 1)))]);
   end Looks_Like_Zlib_Header;

   function Looks_Like_GZip_Header (Input : String) return Boolean is
   begin
      if Input'Length < 4 then
         return False;
      end if;

      return Zlib.Looks_Like_GZip_Header
        ([1 => Zlib.Byte (Character'Pos (Input (Input'First))),
          2 => Zlib.Byte (Character'Pos (Input (Input'First + 1))),
          3 => Zlib.Byte (Character'Pos (Input (Input'First + 2))),
          4 => Zlib.Byte (Character'Pos (Input (Input'First + 3)))]);
   end Looks_Like_GZip_Header;

   function To_Bytes (Input : String) return Ada.Streams.Stream_Element_Array is
   begin
      if Input'Length = 0 then
         return (1 .. 0 => 0);
      end if;

      declare
         Bytes : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      begin
         for Offset in 0 .. Input'Length - 1 loop
            Bytes (Bytes'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
              Ada.Streams.Stream_Element
                (Character'Pos (Input (Input'First + Offset)));
         end loop;
         return Bytes;
      end;
   end To_Bytes;

   procedure Append_Bytes
     (Target : in out Unbounded_String;
      Bytes  : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset) is
   begin
      if Last < Bytes'First then
         return;
      end if;

      declare
         Text : String (1 .. Natural (Last - Bytes'First + 1));
      begin
         for Offset in Text'Range loop
            Text (Offset) := Character'Val
              (Ada.Streams.Stream_Element'Pos
                 (Bytes (Bytes'First +
                    Ada.Streams.Stream_Element_Offset (Offset - Text'First))));
         end loop;
         Append (Target, Text);
      end;
   end Append_Bytes;

   procedure Close (Item : in out Decoder) is
   begin
      if Item.Opened or else Zlib.Is_Open (Item.Filter) then
         Zlib.Close (Item.Filter, Ignore_Error => True);
      end if;
      Item.Opened := False;
   exception
      when others =>
         Item.Opened := False;
   end Close;

   function Initialize
     (Item   : in out Decoder;
      Format : Wrapper_Format) return Http_Client.Errors.Result_Status is
   begin
      Close (Item);
      Zlib.Inflate_Init
        (Filter => Item.Filter,
         Header => Header_For (Format));
      Item.Opened := True;
      return Http_Client.Errors.Ok;
   exception
      when Zlib.Zlib_Error | Zlib.Status_Error =>
         Item.Opened := False;
         return Http_Client.Errors.Decompression_Failed;
      when others =>
         Item.Opened := False;
         return Http_Client.Errors.Internal_Error;
   end Initialize;

   function Decode_Some
     (Item         : in out Decoder;
      Input        : String;
      Finish       : Boolean;
      Max_Output   : Natural;
      Output       : out Unbounded_String;
      Stream_End   : out Boolean)
      return Http_Client.Errors.Result_Status
   is
      Encoded    : constant Ada.Streams.Stream_Element_Array := To_Bytes (Input);
      In_First   : Ada.Streams.Stream_Element_Offset := Encoded'First;
      In_Last    : Ada.Streams.Stream_Element_Offset := Encoded'First - 1;
      Out_Buffer : Ada.Streams.Stream_Element_Array (1 .. Output_Chunk_Size);
      Out_Last   : Ada.Streams.Stream_Element_Offset := Out_Buffer'First - 1;
      Produced   : Natural := 0;

      procedure Fail_Close is
      begin
         if Item.Opened or else Zlib.Is_Open (Item.Filter) then
            Zlib.Close (Item.Filter, Ignore_Error => True);
         end if;
         Item.Opened := False;
      exception
         when others =>
            Item.Opened := False;
      end Fail_Close;

      procedure Success_Close is
      begin
         if Item.Opened or else Zlib.Is_Open (Item.Filter) then
            Zlib.Close (Item.Filter, Ignore_Error => False);
         end if;
         Item.Opened := False;
      end Success_Close;

      function Append_Produced return Http_Client.Errors.Result_Status is
         Count : Natural;
      begin
         if Out_Last < Out_Buffer'First then
            return Http_Client.Errors.Ok;
         end if;

         Count := Natural (Out_Last - Out_Buffer'First + 1);
         if Count > Max_Output - Produced then
            Fail_Close;
            return Http_Client.Errors.Decoded_Body_Too_Large;
         end if;

         Produced := Produced + Count;
         Append_Bytes (Output, Out_Buffer, Out_Last);
         return Http_Client.Errors.Ok;
      end Append_Produced;

      function Drain_Output
        (Mode : Zlib.Flush_Mode) return Http_Client.Errors.Result_Status
      is
         Status : Http_Client.Errors.Result_Status;
      begin
         loop
            Out_Last := Out_Buffer'First - 1;
            Zlib.Flush
              (Filter   => Item.Filter,
               Out_Data => Out_Buffer,
               Out_Last => Out_Last,
               Flush    => Mode);

            Status := Append_Produced;
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;

            Stream_End := Zlib.Stream_End (Item.Filter);
            exit when Stream_End;
            exit when Out_Last < Out_Buffer'Last;
         end loop;

         return Http_Client.Errors.Ok;
      end Drain_Output;

      Status      : Http_Client.Errors.Result_Status;
      Made_Output : Boolean;
      Made_Input  : Boolean;
   begin
      Output := Null_Unbounded_String;
      Stream_End := False;

      if not Item.Opened or else not Zlib.Is_Open (Item.Filter) then
         return Http_Client.Errors.Decompression_Failed;
      end if;

      while In_First <= Encoded'Last loop
         Out_Last := Out_Buffer'First - 1;
         Zlib.Translate
           (Filter   => Item.Filter,
            In_Data  => Encoded (In_First .. Encoded'Last),
            In_Last  => In_Last,
            Out_Data => Out_Buffer,
            Out_Last => Out_Last,
            Flush    => Zlib.No_Flush);

         Status := Append_Produced;
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;

         Stream_End := Zlib.Stream_End (Item.Filter);
         if Stream_End then
            if In_Last < Encoded'Last then
               Fail_Close;
               return Http_Client.Errors.Decompression_Failed;
            end if;
            exit;
         end if;

         Made_Output := Out_Last >= Out_Buffer'First;
         Made_Input  := In_Last >= In_First;

         if Made_Input then
            In_First := In_Last + 1;
         elsif not Made_Output then
            Fail_Close;
            return Http_Client.Errors.Decompression_Failed;
         end if;
      end loop;

      if not Stream_End then
         Status := Drain_Output
           (if Finish then Zlib.Finish else Zlib.No_Flush);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      Stream_End := Zlib.Stream_End (Item.Filter);
      if Finish then
         if Stream_End then
            Success_Close;
         else
            Fail_Close;
            return Http_Client.Errors.Decompression_Failed;
         end if;
      end if;

      return Http_Client.Errors.Ok;
   exception
      when Zlib.Zlib_Error | Zlib.Status_Error =>
         Fail_Close;
         return Http_Client.Errors.Decompression_Failed;
      when others =>
         Fail_Close;
         return Http_Client.Errors.Internal_Error;
   end Decode_Some;

   function Decode_All
     (Input      : String;
      Format     : Wrapper_Format;
      Max_Output : Natural;
      Output     : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Local      : Decoder;
      End_Seen   : Boolean := False;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Output := Null_Unbounded_String;
      Status := Initialize (Local, Format);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Decode_Some
        (Item       => Local,
         Input      => Input,
         Finish     => True,
         Max_Output => Max_Output,
         Output     => Output,
         Stream_End => End_Seen);

      Close (Local);
      return Status;
   exception
      when others =>
         Close (Local);
         Output := Null_Unbounded_String;
         return Http_Client.Errors.Internal_Error;
   end Decode_All;
end Http_Client.Zlib_Decompression;
