with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Http_Client.Errors;

package body Http_Client.URI is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;

   package Code_Point_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Natural);

   function Is_Control (C : Character) return Boolean is
   begin
      return Character'Pos (C) < 32 or else Character'Pos (C) = 127;
   end Is_Control;

   function Is_Hex_Digit (C : Character) return Boolean is
   begin
      return
        (C in '0' .. '9') or else
        (C in 'A' .. 'F') or else
        (C in 'a' .. 'f');
   end Is_Hex_Digit;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Lower_ASCII (Text : String) return String is
      Result : String (Text'Range);
   begin
      for Index_Value in Text'Range loop
         if Text (Index_Value) in 'A' .. 'Z' then
            Result (Index_Value) :=
              Character'Val
                (Character'Pos (Text (Index_Value))
                 - Character'Pos ('A') + Character'Pos ('a'));
         else
            Result (Index_Value) := Text (Index_Value);
         end if;
      end loop;

      return Result;
   end Lower_ASCII;

   function Scheme_Syntax_Is_Valid (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return False;
      end if;

      if Text (Text'First) not in 'A' .. 'Z'
        and then Text (Text'First) not in 'a' .. 'z'
      then
         return False;
      end if;

      for I in Text'Range loop
         declare
            C : constant Character := Text (I);
         begin
            if not
              ((C in 'A' .. 'Z')
               or else (C in 'a' .. 'z')
               or else (C in '0' .. '9')
               or else C = '+'
               or else C = '-'
               or else C = '.')
            then
               return False;
            end if;
         end;
      end loop;

      return True;
   end Scheme_Syntax_Is_Valid;

   function Contains_Control (Text : String) return Boolean is
   begin
      for C of Text loop
         if Is_Control (C) then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Control;

   function Hex_Upper (Value : Natural) return Character is
   begin
      if Value < 10 then
         return Character'Val (Character'Pos ('0') + Value);
      else
         return Character'Val (Character'Pos ('A') + Value - 10);
      end if;
   end Hex_Upper;

   function Percent_Encode_Non_ASCII (Text : String) return String is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for C of Text loop
         declare
            Byte_Value : constant Natural := Character'Pos (C);
         begin
            if Byte_Value > 127 then
               Append (Result, '%');
               Append (Result, Hex_Upper (Byte_Value / 16));
               Append (Result, Hex_Upper (Byte_Value mod 16));
            else
               Append (Result, C);
            end if;
         end;
      end loop;

      return To_String (Result);
   end Percent_Encode_Non_ASCII;

   function Contains_Non_ASCII (Text : String) return Boolean is
   begin
      for C of Text loop
         if Character'Pos (C) > 127 then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Non_ASCII;

   function Decode_UTF8_Label
     (Text   : String;
      Points : in out Code_Point_Vectors.Vector) return Boolean
   is
      Index_Value : Natural := Text'First;

      function Is_Continuation (Value : Natural) return Boolean is
        (Value in 16#80# .. 16#BF#);
   begin
      Points.Clear;

      while Index_Value <= Text'Last loop
         declare
            B1         : constant Natural := Character'Pos (Text (Index_Value));
            Code_Point : Natural;
         begin
            if B1 < 16#80# then
               Points.Append (B1);
               Index_Value := Index_Value + 1;
            elsif B1 in 16#C2# .. 16#DF# then
               if Index_Value + 1 > Text'Last then
                  return False;
               end if;

               declare
                  B2 : constant Natural := Character'Pos (Text (Index_Value + 1));
               begin
                  if not Is_Continuation (B2) then
                     return False;
                  end if;

                  Code_Point := (B1 - 16#C0#) * 64 + (B2 - 16#80#);
                  Points.Append (Code_Point);
                  Index_Value := Index_Value + 2;
               end;
            elsif B1 in 16#E0# .. 16#EF# then
               if Index_Value + 2 > Text'Last then
                  return False;
               end if;

               declare
                  B2 : constant Natural := Character'Pos (Text (Index_Value + 1));
                  B3 : constant Natural := Character'Pos (Text (Index_Value + 2));
               begin
                  if not Is_Continuation (B2) or else not Is_Continuation (B3) then
                     return False;
                  elsif B1 = 16#E0# and then B2 < 16#A0# then
                     return False;
                  elsif B1 = 16#ED# and then B2 > 16#9F# then
                     return False;
                  end if;

                  Code_Point :=
                    (B1 - 16#E0#) * 4_096 + (B2 - 16#80#) * 64 + (B3 - 16#80#);
                  Points.Append (Code_Point);
                  Index_Value := Index_Value + 3;
               end;
            elsif B1 in 16#F0# .. 16#F4# then
               if Index_Value + 3 > Text'Last then
                  return False;
               end if;

               declare
                  B2 : constant Natural := Character'Pos (Text (Index_Value + 1));
                  B3 : constant Natural := Character'Pos (Text (Index_Value + 2));
                  B4 : constant Natural := Character'Pos (Text (Index_Value + 3));
               begin
                  if not Is_Continuation (B2) or else not Is_Continuation (B3)
                    or else not Is_Continuation (B4)
                  then
                     return False;
                  elsif B1 = 16#F0# and then B2 < 16#90# then
                     return False;
                  elsif B1 = 16#F4# and then B2 > 16#8F# then
                     return False;
                  end if;

                  Code_Point :=
                    (B1 - 16#F0#) * 262_144 + (B2 - 16#80#) * 4_096
                    + (B3 - 16#80#) * 64 + (B4 - 16#80#);
                  Points.Append (Code_Point);
                  Index_Value := Index_Value + 4;
               end;
            else
               return False;
            end if;
         end;
      end loop;

      return True;
   end Decode_UTF8_Label;

   function Punycode_Digit (Value : Natural) return Character is
   begin
      if Value < 26 then
         return Character'Val (Character'Pos ('a') + Value);
      else
         return Character'Val (Character'Pos ('0') + Value - 26);
      end if;
   end Punycode_Digit;

   function Punycode_Adapt
     (Delta_Value : Natural;
      Num_Points : Positive;
      First_Time : Boolean) return Natural
   is
      Base       : constant Natural := 36;
      T_Min      : constant Natural := 1;
      T_Max      : constant Natural := 26;
      Skew       : constant Natural := 38;
      Damp_Value : constant Natural := 700;
      Work_Delta : Natural := (if First_Time then Delta_Value / Damp_Value else Delta_Value / 2);
      K          : Natural := 0;
   begin
      Work_Delta := Work_Delta + Work_Delta / Num_Points;

      while Work_Delta > ((Base - T_Min) * T_Max) / 2 loop
         Work_Delta := Work_Delta / (Base - T_Min);
         K := K + Base;
      end loop;

      return K + ((Base - T_Min + 1) * Work_Delta) / (Work_Delta + Skew);
   end Punycode_Adapt;

   function Punycode_Encode (Points : Code_Point_Vectors.Vector) return String is
      Base         : constant Natural := 36;
      T_Min        : constant Natural := 1;
      T_Max        : constant Natural := 26;
      Initial_N    : constant Natural := 128;
      Initial_Bias : constant Natural := 72;
      Output       : Unbounded_String := Null_Unbounded_String;
      N            : Natural := Initial_N;
      Delta_Value  : Natural := 0;
      Bias         : Natural := Initial_Bias;
      Handled      : Natural := 0;
      Basic_Count  : Natural := 0;
   begin
      for Point of Points loop
         if Point < 128 then
            Append (Output, Character'Val (Point));
            Basic_Count := Basic_Count + 1;
            Handled := Handled + 1;
         end if;
      end loop;

      if Basic_Count > 0 and then Basic_Count < Natural (Points.Length) then
         Append (Output, '-');
      end if;

      while Handled < Natural (Points.Length) loop
         declare
            M : Natural := Natural'Last;
         begin
            for Point of Points loop
               if Point >= N and then Point < M then
                  M := Point;
               end if;
            end loop;

            if M = Natural'Last then
               return "";
            end if;

            Delta_Value := Delta_Value + (M - N) * (Handled + 1);
            N := M;

            for Point of Points loop
               if Point < N then
                  Delta_Value := Delta_Value + 1;
               elsif Point = N then
                  declare
                     Q : Natural := Delta_Value;
                     K : Natural := Base;
                     T : Natural;
                  begin
                     loop
                        if K <= Bias then
                           T := T_Min;
                        elsif K >= Bias + T_Max then
                           T := T_Max;
                        else
                           T := K - Bias;
                        end if;

                        exit when Q < T;
                        Append (Output, Punycode_Digit (T + ((Q - T) mod (Base - T))));
                        Q := (Q - T) / (Base - T);
                        K := K + Base;
                     end loop;

                     Append (Output, Punycode_Digit (Q));
                     Bias := Punycode_Adapt (Delta_Value, Positive (Handled + 1), Handled = Basic_Count);
                     Delta_Value := 0;
                     Handled := Handled + 1;
                  end;
               end if;
            end loop;

            Delta_Value := Delta_Value + 1;
            N := N + 1;
         end;
      end loop;

      return To_String (Output);
   end Punycode_Encode;

   function Label_To_ASCII (Label : String; OK : out Boolean) return String is
      Points      : Code_Point_Vectors.Vector;
      Encoded     : Unbounded_String;
      Lower_Label : constant String := Lower_ASCII (Label);
   begin
      OK := False;

      if Label = "" then
         return "";
      elsif not Contains_Non_ASCII (Lower_Label) then
         OK := True;
         return Lower_Label;
      elsif not Decode_UTF8_Label (Lower_Label, Points) then
         return "";
      end if;

      Encoded := To_Unbounded_String (Punycode_Encode (Points));
      if Length (Encoded) = 0 then
         return "";
      end if;

      OK := True;
      return "xn--" & To_String (Encoded);
   end Label_To_ASCII;

   function IDNA_To_ASCII (Host : String; OK : out Boolean) return String is
      Result      : Unbounded_String := Null_Unbounded_String;
      Label_First : Positive := Host'First;
      Label_OK    : Boolean;
   begin
      OK := False;

      if Host = "" then
         return "";
      end if;

      for Index_Value in Host'Range loop
         if Host (Index_Value) = '.' then
            if Index_Value = Label_First then
               return "";
            end if;

            declare
               Label : constant String := Label_To_ASCII (Host (Label_First .. Index_Value - 1), Label_OK);
            begin
               if not Label_OK then
                  return "";
               end if;

               if Length (Result) > 0 then
                  Append (Result, '.');
               end if;
               Append (Result, Label);
               Label_First := Index_Value + 1;
            end;
         end if;
      end loop;

      if Label_First > Host'Last then
         return "";
      end if;

      declare
         Label : constant String := Label_To_ASCII (Host (Label_First .. Host'Last), Label_OK);
      begin
         if not Label_OK then
            return "";
         end if;

         if Length (Result) > 0 then
            Append (Result, '.');
         end if;
         Append (Result, Label);
      end;

      OK := True;
      return To_String (Result);
   end IDNA_To_ASCII;

   function Percent_Escapes_Are_Valid (Text : String) return Boolean is
      I : Natural := Text'First;
   begin
      if Text'Length = 0 then
         return True;
      end if;

      while I <= Text'Last loop
         if Text (I) = '%' then
            if I + 2 > Text'Last then
               return False;
            end if;

            if not Is_Hex_Digit (Text (I + 1))
              or else not Is_Hex_Digit (Text (I + 2))
            then
               return False;
            end if;

            I := I + 3;
         else
            I := I + 1;
         end if;
      end loop;

      return True;
   end Percent_Escapes_Are_Valid;

   function Valid_IPv4_Literal (Host : String) return Boolean is
      Octet_Start : Positive := Host'First;
      Octets      : Natural := 0;

      function Octet_Is_Valid
        (First_Index : Positive;
         Last_Index  : Natural) return Boolean
      is
         Value : Natural := 0;
      begin
         if Last_Index < First_Index then
            return False;
         end if;

         for I in First_Index .. Last_Index loop
            if Host (I) not in '0' .. '9' then
               return False;
            end if;

            Value :=
              Value * 10 +
              Character'Pos (Host (I)) - Character'Pos ('0');

            if Value > 255 then
               return False;
            end if;
         end loop;

         return True;
      end Octet_Is_Valid;
   begin
      if Host'Length = 0 then
         return False;
      end if;

      for I in Host'Range loop
         if Host (I) = '.' then
            Octets := Octets + 1;

            if not Octet_Is_Valid (Octet_Start, I - 1) then
               return False;
            end if;

            if I = Host'Last then
               return False;
            end if;

            Octet_Start := I + 1;
         end if;
      end loop;

      Octets := Octets + 1;

      return Octets = 4 and then Octet_Is_Valid (Octet_Start, Host'Last);
   end Valid_IPv4_Literal;

   function Valid_IPv6_Literal (Host : String) return Boolean is
      Double_Colon : Natural := 0;

      function Contains_Dot (Text : String) return Boolean is
      begin
         for C of Text loop
            if C = '.' then
               return True;
            end if;
         end loop;
         return False;
      end Contains_Dot;

      function Hextet_Is_Valid (Text : String) return Boolean is
      begin
         if Text'Length = 0 or else Text'Length > 4 then
            return False;
         end if;

         for C of Text loop
            if not Is_Hex_Digit (C) then
               return False;
            end if;
         end loop;

         return True;
      end Hextet_Is_Valid;

      function Count_Part
        (Text            : String;
         Allow_IPv4_Tail : Boolean;
         Count           : out Natural) return Boolean
      is
         Segment_Start : Natural := Text'First;
         Saw_IPv4_Tail : Boolean := False;
      begin
         Count := 0;

         if Text'Length = 0 then
            return True;
         end if;

         for I in Text'Range loop
            if Text (I) = ':' then
               if I = Segment_Start then
                  return False;
               end if;

               declare
                  Segment : constant String := Text (Segment_Start .. I - 1);
               begin
                  if Contains_Dot (Segment) then
                     return False;
                  end if;

                  if not Hextet_Is_Valid (Segment) then
                     return False;
                  end if;
               end;

               Count := Count + 1;
               Segment_Start := I + 1;
            end if;
         end loop;

         if Segment_Start > Text'Last then
            return False;
         end if;

         declare
            Segment : constant String := Text (Segment_Start .. Text'Last);
         begin
            if Contains_Dot (Segment) then
               if not Allow_IPv4_Tail or else not Valid_IPv4_Literal (Segment) then
                  return False;
               end if;
               Saw_IPv4_Tail := True;
               Count := Count + 2;
            elsif Hextet_Is_Valid (Segment) then
               Count := Count + 1;
            else
               return False;
            end if;
         end;

         return (not Saw_IPv4_Tail) or else Count >= 2;
      end Count_Part;

      Left_Count  : Natural := 0;
      Right_Count : Natural := 0;
   begin
      if Host'Length = 0 then
         return False;
      end if;

      for I in Host'Range loop
         if Host (I) = '%' then
            return False;
         end if;

         if I < Host'Last and then Host (I) = ':' and then Host (I + 1) = ':' then
            if Double_Colon /= 0 then
               return False;
            end if;
            Double_Colon := I;
         end if;
      end loop;

      if Double_Colon = 0 then
         if not Count_Part (Host, True, Left_Count) then
            return False;
         end if;
         return Left_Count = 8;
      end if;

      if Double_Colon > Host'First then
         if not Count_Part (Host (Host'First .. Double_Colon - 1), False, Left_Count) then
            return False;
         end if;
      end if;

      if Double_Colon + 2 <= Host'Last then
         if not Count_Part (Host (Double_Colon + 2 .. Host'Last), True, Right_Count) then
            return False;
         end if;
      end if;

      return Left_Count + Right_Count < 8;
   end Valid_IPv6_Literal;

   function Valid_DNS_Or_IPv4_Host (Host : String) return Boolean is
      Label_Start : Positive := Host'First;
      Dot_Count   : Natural := 0;
      All_IPv4_Characters : Boolean := True;

      function Is_Allowed_Host_Character (C : Character) return Boolean is
      begin
         return
           (C in 'a' .. 'z') or else
           (C in '0' .. '9') or else
           C = '-' or else
           C = '.';
      end Is_Allowed_Host_Character;

      function Label_Is_Well_Formed
        (First_Index : Positive;
         Last_Index  : Natural) return Boolean
      is
      begin
         if Last_Index < First_Index then
            return False;
         end if;

         if Last_Index - First_Index + 1 > 63 then
            return False;
         end if;

         return
           Host (First_Index) /= '-' and then
           Host (Last_Index) /= '-';
      end Label_Is_Well_Formed;

      function IPv4_Literal_Is_Valid return Boolean is
      begin
         return Valid_IPv4_Literal (Host);
      end IPv4_Literal_Is_Valid;

   begin
      if Host'Length = 0 or else Host'Length > 253 then
         return False;
      end if;

      for I in Host'Range loop
         declare
            C : constant Character := Host (I);
         begin
            if not Is_Allowed_Host_Character (C) then
               return False;
            end if;

            if C = '.' then
               Dot_Count := Dot_Count + 1;

               if not Label_Is_Well_Formed (Label_Start, I - 1) then
                  return False;
               end if;

               if I = Host'Last then
                  return False;
               end if;

               Label_Start := I + 1;
            elsif C not in '0' .. '9' then
               All_IPv4_Characters := False;
            end if;
         end;
      end loop;

      if not Label_Is_Well_Formed (Label_Start, Host'Last) then
         return False;
      end if;

      if All_IPv4_Characters and then Dot_Count = 3 then
         return IPv4_Literal_Is_Valid;
      end if;

      return True;
   end Valid_DNS_Or_IPv4_Host;

   function Raw_Authority_Host_Has_Non_ASCII (Text : String) return Boolean is
      Authority_First : Positive := Text'First;
      Authority_Last  : Natural := Text'Last;
      Host_First      : Positive;
      Host_Last       : Natural;
   begin
      if Text = "" then
         return False;
      end if;

      for Index in Text'Range loop
         if Index + 2 <= Text'Last and then Text (Index .. Index + 2) = "://" then
            Authority_First := Index + 3;
            exit;
         end if;
      end loop;

      for Index in Authority_First .. Text'Last loop
         if Text (Index) = '/' or else Text (Index) = '?' or else Text (Index) = '#' then
            Authority_Last := Index - 1;
            exit;
         end if;
      end loop;

      if Authority_Last < Authority_First then
         return False;
      end if;

      Host_First := Authority_First;
      for Index in reverse Authority_First .. Authority_Last loop
         if Text (Index) = '@' then
            Host_First := Index + 1;
            exit;
         end if;
      end loop;

      if Host_First > Authority_Last then
         return False;
      end if;

      if Text (Host_First) = '[' then
         Host_First := Host_First + 1;
         Host_Last := Authority_Last;
         for Index in Host_First .. Authority_Last loop
            if Text (Index) = ']' then
               Host_Last := Index - 1;
               exit;
            end if;
         end loop;
      else
         Host_Last := Authority_Last;
         for Index in Host_First .. Authority_Last loop
            if Text (Index) = ':' then
               Host_Last := Index - 1;
               exit;
            end if;
         end loop;
      end if;

      if Host_Last < Host_First then
         return False;
      end if;

      for Index in Host_First .. Host_Last loop
         if Character'Pos (Text (Index)) > 127 then
            return True;
         end if;
      end loop;

      return False;
   end Raw_Authority_Host_Has_Non_ASCII;

   function Is_Valid_ASCII_Host (Host : String) return Boolean is
   begin
      return Valid_IPv6_Literal (Host) or else Valid_DNS_Or_IPv4_Host (Host);
   end Is_Valid_ASCII_Host;

   function Kind_Of_ASCII_Host (Host : String) return Host_Kind is
   begin
      if Valid_IPv6_Literal (Host) then
         return IPv6_Literal;
      elsif Valid_IPv4_Literal (Host) then
         return IPv4_Literal;
      else
         return DNS_Name;
      end if;
   end Kind_Of_ASCII_Host;

   function Valid_Path_Query_Fragment (Text : String; Is_Path : Boolean)
      return Boolean
   is
   begin
      if Contains_Control (Text) then
         return False;
      end if;

      for C of Text loop
         if C = ' ' then
            return False;
         end if;

         if Is_Path and then (C = '?' or else C = '#') then
            return False;
         end if;
      end loop;

      return Percent_Escapes_Are_Valid (Text);
   end Valid_Path_Query_Fragment;

   function First_Of
     (Text  : String;
      Start : Positive;
      Chars : String) return Natural
   is
   begin
      if Text'Length = 0 or else Start > Text'Last then
         return 0;
      end if;

      for I in Start .. Text'Last loop
         for C of Chars loop
            if Text (I) = C then
               return I;
            end if;
         end loop;
      end loop;

      return 0;
   end First_Of;

   function Default_URI return URI_Reference is
   begin
      return
        (Original          => Null_Unbounded_String,
         Parsed            => False,
         Scheme_Text       => Null_Unbounded_String,
         Host_Text         => Null_Unbounded_String,
         Host_Class        => DNS_Name,
         Port_Present      => False,
         Port_Value        => 0,
         Path_Text         => Null_Unbounded_String,
         Query_Present     => False,
         Query_Text        => Null_Unbounded_String,
         Fragment_Present  => False,
         Fragment_Text     => Null_Unbounded_String);
   end Default_URI;

   function Create_Unchecked (Text : String) return URI_Reference is
      Result : URI_Reference := Default_URI;
   begin
      Result.Original := To_Unbounded_String (Text);
      return Result;
   end Create_Unchecked;

   function Parse
     (Text : String;
      Item : out URI_Reference) return Http_Client.Errors.Result_Status
   is
      Scheme_End : Natural := 0;
      Authority_Start : Natural;
      Authority_End   : Natural;
      Path_Start      : Natural;
      Query_Start     : Natural := 0;
      Fragment_Start  : Natural := 0;
      Raw_Scheme      : Unbounded_String;
      Raw_Authority   : Unbounded_String;
      Raw_Host        : Unbounded_String;
      Raw_Port        : Unbounded_String;
      Raw_Path        : Unbounded_String;
      Raw_Query       : Unbounded_String;
      Raw_Fragment    : Unbounded_String;
      Parsed_Port     : Natural := 0;
      Parsed_Host     : Host_Kind := DNS_Name;
      Has_Port        : Boolean := False;
      Has_Query_Mark  : Boolean := False;
      Has_Frag_Mark   : Boolean := False;
   begin
      Item := Default_URI;

      if Text'Length = 0 or else Contains_Control (Text) then
         return Invalid_URI;
      end if;

      for I in Text'Range loop
         exit when
           Text (I) = '/' or else
           Text (I) = '?' or else
           Text (I) = '#';

         if Text (I) = ':' then
            Scheme_End := I;
            exit;
         end if;
      end loop;

      if Scheme_End = 0 or else Scheme_End = Text'First then
         return Invalid_URI;
      end if;

      if not Scheme_Syntax_Is_Valid (Text (Text'First .. Scheme_End - 1)) then
         return Invalid_URI;
      end if;

      Raw_Scheme :=
        To_Unbounded_String
          (Lower (Text (Text'First .. Scheme_End - 1)));

      if To_String (Raw_Scheme) /= "http"
        and then To_String (Raw_Scheme) /= "https"
      then
         return Unsupported_Feature;
      end if;

      if Scheme_End + 2 > Text'Last
        or else Text (Scheme_End + 1) /= '/'
        or else Text (Scheme_End + 2) /= '/'
      then
         return Invalid_URI;
      end if;

      Authority_Start := Scheme_End + 3;

      if Authority_Start > Text'Last then
         return Invalid_URI;
      end if;

      declare
         Delim : constant Natural := First_Of (Text, Authority_Start, "/?#");
      begin
         if Delim = 0 then
            Authority_End := Text'Last;
            Path_Start := 0;
         else
            Authority_End := Delim - 1;
            Path_Start := Delim;
         end if;
      end;

      if Authority_End < Authority_Start then
         return Invalid_URI;
      end if;

      Raw_Authority :=
        To_Unbounded_String (Text (Authority_Start .. Authority_End));

      for C of To_String (Raw_Authority) loop
         if C = '@' then
            return Unsupported_Feature;
         end if;
      end loop;

      declare
         Authority : constant String := To_String (Raw_Authority);
         Colon_Pos : Natural := 0;
      begin
         if Authority (Authority'First) = '[' then
            declare
               Closing : Natural := 0;
            begin
               for I in Authority'Range loop
                  if Authority (I) = ']' then
                     Closing := I;
                     exit;
                  end if;
               end loop;

               if Closing = 0 or else Closing = Authority'First + 1 then
                  return Invalid_URI;
               end if;

               Raw_Host :=
                 To_Unbounded_String
                   (Authority (Authority'First + 1 .. Closing - 1));
               Parsed_Host := IPv6_Literal;

               if Closing = Authority'Last then
                  null;
               elsif Closing + 1 <= Authority'Last
                 and then Authority (Closing + 1) = ':'
               then
                  if Closing + 1 = Authority'Last then
                     return Invalid_URI;
                  end if;

                  Raw_Port :=
                    To_Unbounded_String
                      (Authority (Closing + 2 .. Authority'Last));
                  Has_Port := True;
               else
                  return Invalid_URI;
               end if;
            end;
         else

         for I in Authority'Range loop
            if Authority (I) = ':' then
               if Colon_Pos /= 0 then
                  return Invalid_URI;
               end if;

               Colon_Pos := I;
            end if;
         end loop;

         if Colon_Pos = 0 then
            Raw_Host := To_Unbounded_String (Authority);
         else
            if Colon_Pos = Authority'First
              or else Colon_Pos = Authority'Last
            then
               return Invalid_URI;
            end if;

            Raw_Host :=
              To_Unbounded_String
                (Authority (Authority'First .. Colon_Pos - 1));
            Raw_Port :=
              To_Unbounded_String
                (Authority (Colon_Pos + 1 .. Authority'Last));
            Has_Port := True;
         end if;
         end if;
      end;

      if Parsed_Host = IPv6_Literal then
         if not Valid_IPv6_Literal (To_String (Raw_Host)) then
            return Invalid_URI;
         end if;
      else
         declare
            IDNA_OK : Boolean;
            ASCII_Host : constant String := IDNA_To_ASCII (To_String (Raw_Host), IDNA_OK);
         begin
            if not IDNA_OK then
               return Invalid_URI;
            end if;

            Raw_Host := To_Unbounded_String (ASCII_Host);
         end;

         if not Valid_DNS_Or_IPv4_Host (To_String (Raw_Host)) then
            return Invalid_URI;
         end if;

         if Valid_IPv4_Literal (To_String (Raw_Host)) then
            Parsed_Host := IPv4_Literal;
         else
            Parsed_Host := DNS_Name;
         end if;
      end if;

      if Has_Port then
         declare
            Port_Text : constant String := To_String (Raw_Port);
         begin
            Parsed_Port := 0;

            for C of Port_Text loop
               if C not in '0' .. '9' then
                  return Invalid_URI;
               end if;

               Parsed_Port :=
                 Parsed_Port * 10 +
                 Character'Pos (C) - Character'Pos ('0');

               if Parsed_Port > TCP_Port'Last then
                  return Invalid_URI;
               end if;
            end loop;

            if Parsed_Port < TCP_Port'First then
               return Invalid_URI;
            end if;
         end;
      end if;

      if Path_Start = 0 then
         Raw_Path := To_Unbounded_String ("/");
      else
         declare
            Remainder_Start : constant Natural := Path_Start;
         begin
            if Text (Remainder_Start) = '/' then
               declare
                  Path_Delim : constant Natural :=
                    First_Of (Text, Remainder_Start, "?#");
               begin
                  if Path_Delim = 0 then
                     Raw_Path :=
                       To_Unbounded_String
                         (Text (Remainder_Start .. Text'Last));
                  else
                     Raw_Path :=
                       To_Unbounded_String
                         (Text (Remainder_Start .. Path_Delim - 1));
                     if Text (Path_Delim) = '?' then
                        Query_Start := Path_Delim;
                     else
                        Fragment_Start := Path_Delim;
                     end if;
                  end if;
               end;
            elsif Text (Remainder_Start) = '?' then
               Raw_Path := To_Unbounded_String ("/");
               Query_Start := Remainder_Start;
            elsif Text (Remainder_Start) = '#' then
               Raw_Path := To_Unbounded_String ("/");
               Fragment_Start := Remainder_Start;
            else
               return Invalid_URI;
            end if;
         end;
      end if;

      if Query_Start /= 0 then
         Has_Query_Mark := True;

         declare
            Query_End : Natural := Text'Last;
         begin
            for I in Query_Start + 1 .. Text'Last loop
               if Text (I) = '#' then
                  Query_End := I - 1;
                  Fragment_Start := I;
                  exit;
               end if;
            end loop;

            if Query_Start + 1 <= Query_End then
               Raw_Query :=
                 To_Unbounded_String (Text (Query_Start + 1 .. Query_End));
            else
               Raw_Query := Null_Unbounded_String;
            end if;
         end;
      end if;

      if Fragment_Start /= 0 then
         Has_Frag_Mark := True;

         if Fragment_Start + 1 <= Text'Last then
            Raw_Fragment :=
              To_Unbounded_String (Text (Fragment_Start + 1 .. Text'Last));
         else
            Raw_Fragment := Null_Unbounded_String;
         end if;
      end if;

      Raw_Path := To_Unbounded_String
        (Percent_Encode_Non_ASCII (To_String (Raw_Path)));
      Raw_Query := To_Unbounded_String
        (Percent_Encode_Non_ASCII (To_String (Raw_Query)));
      Raw_Fragment := To_Unbounded_String
        (Percent_Encode_Non_ASCII (To_String (Raw_Fragment)));

      if not Valid_Path_Query_Fragment
          (To_String (Raw_Path), Is_Path => True)
        or else not Valid_Path_Query_Fragment
          (To_String (Raw_Query), Is_Path => False)
        or else not Valid_Path_Query_Fragment
          (To_String (Raw_Fragment), Is_Path => False)
      then
         return Invalid_URI;
      end if;

      Item :=
        (Original          => To_Unbounded_String (Text),
         Parsed            => True,
         Scheme_Text       => Raw_Scheme,
         Host_Text         => Raw_Host,
         Host_Class        => Parsed_Host,
         Port_Present      => Has_Port,
         Port_Value        => Parsed_Port,
         Path_Text         => Raw_Path,
         Query_Present     => Has_Query_Mark,
         Query_Text        => Raw_Query,
         Fragment_Present  => Has_Frag_Mark,
         Fragment_Text     => Raw_Fragment);

      return Ok;
   end Parse;

   function Image (Item : URI_Reference) return String is
      Port_Value : TCP_Port;
   begin
      if not Item.Parsed then
         return To_String (Item.Original);
      end if;

      Port_Value := Effective_Port (Item);

      declare
         Prefix : constant String :=
           To_String (Item.Scheme_Text) & "://" & Authority_Host (Item);
         Port_Image : constant String := Natural'Image (Natural (Port_Value));
         Tail : constant String := Request_Target (Item) &
           (if Item.Fragment_Present then "#" & To_String (Item.Fragment_Text) else "");
      begin
         if Item.Port_Present
           and then not
             ((To_String (Item.Scheme_Text) = "http" and then Port_Value = 80)
              or else
              (To_String (Item.Scheme_Text) = "https" and then Port_Value = 443))
         then
            return Prefix & ":" & Port_Image (Port_Image'First + 1 .. Port_Image'Last) & Tail;
         else
            return Prefix & Tail;
         end if;
      end;
   end Image;

   function Is_Empty (Item : URI_Reference) return Boolean is
   begin
      return Length (Item.Original) = 0;
   end Is_Empty;

   function Is_Parsed (Item : URI_Reference) return Boolean is
   begin
      return Item.Parsed;
   end Is_Parsed;

   function Scheme (Item : URI_Reference) return String is
   begin
      return To_String (Item.Scheme_Text);
   end Scheme;

   function Host (Item : URI_Reference) return String is
   begin
      return To_String (Item.Host_Text);
   end Host;

   function Kind_Of_Host (Item : URI_Reference) return Host_Kind is
   begin
      return Item.Host_Class;
   end Kind_Of_Host;

   function Authority_Host (Item : URI_Reference) return String is
      Host_Value : constant String := To_String (Item.Host_Text);
   begin
      if Item.Host_Class = IPv6_Literal then
         return "[" & Host_Value & "]";
      else
         return Host_Value;
      end if;
   end Authority_Host;

   function Has_Explicit_Port (Item : URI_Reference) return Boolean is
   begin
      return Item.Port_Present;
   end Has_Explicit_Port;

   function Explicit_Port (Item : URI_Reference) return Natural is
   begin
      return Item.Port_Value;
   end Explicit_Port;

   function Effective_Port (Item : URI_Reference) return TCP_Port is
   begin
      if Item.Port_Present then
         return TCP_Port (Item.Port_Value);
      elsif To_String (Item.Scheme_Text) = "https" then
         return 443;
      else
         return 80;
      end if;
   end Effective_Port;

   function Path (Item : URI_Reference) return String is
   begin
      return To_String (Item.Path_Text);
   end Path;

   function Effective_Path (Item : URI_Reference) return String is
   begin
      return Path (Item);
   end Effective_Path;

   function Has_Query (Item : URI_Reference) return Boolean is
   begin
      return Item.Query_Present;
   end Has_Query;

   function Query (Item : URI_Reference) return String is
   begin
      return To_String (Item.Query_Text);
   end Query;

   function Has_Fragment (Item : URI_Reference) return Boolean is
   begin
      return Item.Fragment_Present;
   end Has_Fragment;

   function Fragment (Item : URI_Reference) return String is
   begin
      return To_String (Item.Fragment_Text);
   end Fragment;

   function Requires_TLS (Item : URI_Reference) return Boolean is
   begin
      return To_String (Item.Scheme_Text) = "https";
   end Requires_TLS;

   function Request_Target (Item : URI_Reference) return String is
   begin
      if Item.Query_Present then
         return To_String (Item.Path_Text) & "?" & To_String (Item.Query_Text);
      else
         return To_String (Item.Path_Text);
      end if;
   end Request_Target;

   function Host_Header_Value (Item : URI_Reference) return String is
      Host_Value : constant String := Authority_Host (Item);
      Port_Value : constant TCP_Port := Effective_Port (Item);
   begin
      if Item.Port_Present
        and then not
          ((To_String (Item.Scheme_Text) = "http" and then Port_Value = 80)
           or else
           (To_String (Item.Scheme_Text) = "https" and then Port_Value = 443))
      then
         declare
            Port_Image : constant String := Natural'Image (Port_Value);
         begin
            return Host_Value & ":" & Port_Image (2 .. Port_Image'Last);
         end;
      else
         return Host_Value;
      end if;
   end Host_Header_Value;

end Http_Client.URI;
