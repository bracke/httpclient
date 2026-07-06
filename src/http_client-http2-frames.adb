with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Http_Client.HTTP2.Frames is
   use type Http_Client.Errors.Result_Status;

   function B (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end B;

   function U8 (C : Character) return Natural is
   begin
      return Character'Pos (C);
   end U8;

   function Type_Code (Kind : Frame_Type; Raw_Type : Byte_Value := 0)
      return Byte_Value
   is
   begin
      case Kind is
         when DATA          => return 16#00#;
         when HEADERS       => return 16#01#;
         when PRIORITY      => return 16#02#;
         when RST_STREAM    => return 16#03#;
         when SETTINGS      => return 16#04#;
         when PUSH_PROMISE  => return 16#05#;
         when PING          => return 16#06#;
         when GOAWAY        => return 16#07#;
         when WINDOW_UPDATE => return 16#08#;
         when CONTINUATION  => return 16#09#;
         when UNKNOWN       => return Raw_Type;
      end case;
   end Type_Code;

   function Kind_From_Code (Code : Byte_Value) return Frame_Type is
   begin
      case Code is
         when 16#00# => return DATA;
         when 16#01# => return HEADERS;
         when 16#02# => return PRIORITY;
         when 16#03# => return RST_STREAM;
         when 16#04# => return SETTINGS;
         when 16#05# => return PUSH_PROMISE;
         when 16#06# => return PING;
         when 16#07# => return GOAWAY;
         when 16#08# => return WINDOW_UPDATE;
         when 16#09# => return CONTINUATION;
         when others => return UNKNOWN;
      end case;
   end Kind_From_Code;

   function Has_Flag (Flags : Byte_Value; Mask : Byte_Value) return Boolean is
   begin
      return (Flags / Mask) mod 2 = 1;
   end Has_Flag;

   function RST_Stream_Error_Code (Payload : String) return Natural is
   begin
      if Payload'Length /= 4 then
         return Natural'Last;
      end if;

      return U8 (Payload (Payload'First)) * 16#0100_0000#
        + U8 (Payload (Payload'First + 1)) * 16#0001_0000#
        + U8 (Payload (Payload'First + 2)) * 16#0000_0100#
        + U8 (Payload (Payload'First + 3));
   end RST_Stream_Error_Code;

   function RST_Stream_Status (Payload : String)
      return Http_Client.Errors.Result_Status
   is
      Code : constant Natural := RST_Stream_Error_Code (Payload);
   begin
      case Code is
         when 16#01# =>
            return Http_Client.Errors.HTTP2_Protocol_Error;
         when 16#03# =>
            return Http_Client.Errors.HTTP2_Flow_Control_Error;
         when 16#05# =>
            return Http_Client.Errors.HTTP2_Stream_State_Error;
         when 16#06# =>
            return Http_Client.Errors.HTTP2_Frame_Error;
         when 16#07# =>
            return Http_Client.Errors.HTTP2_Stream_Refused;
         when 16#09# =>
            return Http_Client.Errors.HTTP2_Compression_Error;
         when 16#0D# =>
            return Http_Client.Errors.HTTP2_Unsupported_Feature;
         when others =>
            return Http_Client.Errors.HTTP2_Stream_Reset;
      end case;
   end RST_Stream_Status;

   function Serialize_Header
     (Header : Frame_Header) return String
   is
      SID : Natural := Header.Stream;
      B1  : Natural := SID / 16#0100_0000#;
   begin
      if Header.Reserved_Bit then
         B1 := B1 + 128;
      end if;

      return String'
        (1 => B (Header.Length / 16#1_0000#),
         2 => B (Header.Length / 16#100#),
         3 => B (Header.Length),
         4 => B (Type_Code (Header.Kind, Header.Raw_Type)),
         5 => B (Header.Flags),
         6 => B (B1),
         7 => B (SID / 16#0001_0000#),
         8 => B (SID / 16#0000_0100#),
         9 => B (SID));
   end Serialize_Header;

   function Parse_Header
     (Data   : String;
      Header : out Frame_Header) return Http_Client.Errors.Result_Status
   is
      P      : constant Integer := Data'First;
      Raw    : Natural;
      Stream : Natural;
   begin
      if Data'Length < 9 then
         Header := (others => <>);
         return Http_Client.Errors.Incomplete_Message;
      end if;

      Raw := U8 (Data (P + 3));
      Stream :=
        (U8 (Data (P + 5)) mod 128) * 16#0100_0000# +
        U8 (Data (P + 6)) * 16#0001_0000# +
        U8 (Data (P + 7)) * 16#0000_0100# +
        U8 (Data (P + 8));

      Header.Length :=
        U8 (Data (P)) * 16#1_0000# +
        U8 (Data (P + 1)) * 16#100# +
        U8 (Data (P + 2));
      Header.Raw_Type := Raw;
      Header.Kind := Kind_From_Code (Raw);
      Header.Flags := U8 (Data (P + 4));
      Header.Reserved_Bit := U8 (Data (P + 5)) >= 128;
      Header.Stream := Stream;
      return Http_Client.Errors.Ok;
   end Parse_Header;

   function Validate_Header
     (Header         : Frame_Header;
      Max_Frame_Size : Natural := 16_384) return Http_Client.Errors.Result_Status
   is
   begin
      if Max_Frame_Size < 16_384 or else Max_Frame_Size > 16#00FF_FFFF# then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Header.Length > Max_Frame_Size then
         return Http_Client.Errors.Response_Too_Large;
      end if;

      if Header.Reserved_Bit then
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      case Header.Kind is
         when SETTINGS | PING | GOAWAY =>
            if Header.Kind = SETTINGS and then Header.Stream /= 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif Header.Kind = PING and then Header.Stream /= 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            elsif Header.Kind = GOAWAY and then Header.Stream /= 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         when DATA | HEADERS | PRIORITY | RST_STREAM | PUSH_PROMISE |
              CONTINUATION =>
            if Header.Stream = 0 then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;

         when WINDOW_UPDATE =>
            --  WINDOW_UPDATE is valid on stream 0 for the connection window
            --  and on a nonzero stream for the stream window. Payload
            --  validation below rejects zero increments.
            null;

         when UNKNOWN =>
            null;
      end case;

      return Http_Client.Errors.Ok;
   end Validate_Header;

   function Validate_Payload
     (Header  : Frame_Header;
      Payload : String) return Http_Client.Errors.Result_Status
   is
      function U32_31 (Offset : Natural) return Natural is
         P : constant Integer := Payload'First + Integer (Offset);
         V : Natural;
      begin
         V := (U8 (Payload (P)) mod 128) * 16#0100_0000# +
              U8 (Payload (P + 1)) * 16#0001_0000# +
              U8 (Payload (P + 2)) * 16#0000_0100# +
              U8 (Payload (P + 3));
         return V;
      end U32_31;

      Increment : Natural;
   begin
      if Payload'Length /= Header.Length then
         return Http_Client.Errors.Incomplete_Message;
      end if;

      case Header.Kind is
         when SETTINGS =>
            if Has_Flag (Header.Flags, 16#01#) then
               if Payload'Length /= 0 then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;
            elsif Payload'Length mod 6 /= 0 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

         when PING =>
            if Payload'Length /= 8 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

         when WINDOW_UPDATE =>
            if Payload'Length /= 4 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;
            Increment := U32_31 (0);
            if Increment = 0 then
               return Http_Client.Errors.HTTP2_Flow_Control_Error;
            end if;

         when RST_STREAM =>
            if Payload'Length /= 4 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

         when GOAWAY =>
            if Payload'Length < 8 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

            if U8 (Payload (Payload'First)) >= 128 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

         when PRIORITY =>
            if Payload'Length /= 5 then
               return Http_Client.Errors.HTTP2_Frame_Error;
            end if;

         when DATA =>
            if Has_Flag (Header.Flags, 16#08#) then
               if Payload'Length = 0 then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               elsif Natural (U8 (Payload (Payload'First))) >= Payload'Length then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;
            end if;

         when HEADERS =>
            declare
               Prefix_Length : Natural := 0;
               Priority_Length : constant Natural :=
                 (if Has_Flag (Header.Flags, 16#20#) then 5 else 0);
               Pad_Length : Natural := 0;
            begin
               if Has_Flag (Header.Flags, 16#08#) then
                  if Payload'Length = 0 then
                     return Http_Client.Errors.HTTP2_Frame_Error;
                  end if;

                  Pad_Length := U8 (Payload (Payload'First));
                  Prefix_Length := 1;
               end if;

               if Payload'Length < Prefix_Length + Priority_Length then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;

               if Pad_Length > Payload'Length - Prefix_Length - Priority_Length then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;
            end;

         when PUSH_PROMISE =>
            declare
               Prefix_Length : Natural := 0;
               Pad_Length    : Natural := 0;
               Promise_First : Integer;
               Promised_ID   : Natural;
            begin
               if Has_Flag (Header.Flags, 16#08#) then
                  if Payload'Length = 0 then
                     return Http_Client.Errors.HTTP2_Frame_Error;
                  end if;

                  Pad_Length := U8 (Payload (Payload'First));
                  Prefix_Length := 1;
               end if;

               if Payload'Length < Prefix_Length + 4 then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;

               if Pad_Length > Payload'Length - Prefix_Length - 4 then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;

               Promise_First := Payload'First + Integer (Prefix_Length);
               if U8 (Payload (Promise_First)) >= 128 then
                  return Http_Client.Errors.HTTP2_Frame_Error;
               end if;

               Promised_ID :=
                 U8 (Payload (Promise_First)) * 16#0100_0000# +
                 U8 (Payload (Promise_First + 1)) * 16#0001_0000# +
                 U8 (Payload (Promise_First + 2)) * 16#0000_0100# +
                 U8 (Payload (Promise_First + 3));

               if Promised_ID = 0 then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
            end;

         when CONTINUATION | UNKNOWN =>
            null;
      end case;

      return Http_Client.Errors.Ok;
   end Validate_Payload;

   function Apply_Continuation_Rule
     (State  : in out Continuation_State;
      Header : Frame_Header) return Http_Client.Errors.Result_Status
   is
      End_Headers : constant Boolean := Has_Flag (Header.Flags, 16#04#);
   begin
      if State.Expecting_Continuation then
         if Header.Kind /= CONTINUATION or else Header.Stream /= State.Stream then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;

         if End_Headers then
            State.Expecting_Continuation := False;
            State.Stream := 0;
         end if;

         return Http_Client.Errors.Ok;
      end if;

      if Header.Kind = CONTINUATION then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      if (Header.Kind = HEADERS or else Header.Kind = PUSH_PROMISE)
        and then not End_Headers
      then
         State.Expecting_Continuation := True;
         State.Stream := Header.Stream;
      end if;

      return Http_Client.Errors.Ok;
   end Apply_Continuation_Rule;

   function Serialize_Frame
     (Header  : Frame_Header;
      Payload : String;
      Output  : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      H      : Frame_Header := Header;
      Status : Http_Client.Errors.Result_Status;
   begin
      if Payload'Length > 16#00FF_FFFF# then
         Output := Null_Unbounded_String;
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      H.Length := Payload'Length;
      Status := Validate_Header (H, 16#00FF_FFFF#);
      if Status /= Http_Client.Errors.Ok then
         Output := Null_Unbounded_String;
         return Status;
      end if;

      Status := Validate_Payload (H, Payload);
      if Status /= Http_Client.Errors.Ok then
         Output := Null_Unbounded_String;
         return Status;
      end if;

      Output := To_Unbounded_String (Serialize_Header (H) & Payload);
      return Http_Client.Errors.Ok;
   end Serialize_Frame;

   function Parse_Frame
     (Data           : String;
      Max_Frame_Size : Natural;
      Item           : out Frame) return Http_Client.Errors.Result_Status
   is
      Header : Frame_Header;
      Status : Http_Client.Errors.Result_Status;
      First  : Integer;
      Last   : Integer;
   begin
      Status := Parse_Header (Data, Header);
      if Status /= Http_Client.Errors.Ok then
         Item := (others => <>);
         return Status;
      end if;

      Status := Validate_Header (Header, Max_Frame_Size);
      if Status /= Http_Client.Errors.Ok then
         Item := (others => <>);
         return Status;
      end if;

      if Data'Length < 9 + Header.Length then
         Item := (others => <>);
         return Http_Client.Errors.Incomplete_Message;
      elsif Data'Length > 9 + Header.Length then
         Item := (others => <>);
         return Http_Client.Errors.HTTP2_Frame_Error;
      end if;

      First := Data'First + 9;
      Last := Data'Last;
      if Header.Length = 0 then
         Status := Validate_Payload (Header, "");
         Item.Header := Header;
         Item.Payload := Null_Unbounded_String;
      else
         Status := Validate_Payload (Header, Data (First .. Last));
         Item.Header := Header;
         Item.Payload := To_Unbounded_String (Data (First .. Last));
      end if;

      if Status /= Http_Client.Errors.Ok then
         Item := (others => <>);
      end if;
      return Status;
   end Parse_Frame;
end Http_Client.HTTP2.Frames;
