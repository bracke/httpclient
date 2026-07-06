with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.URI;

package body Http_Client.Alt_Svc is
   use Ada.Calendar;
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;
   use type Http_Client.URI.Host_Kind;
   function Trim (Value : String) return String is
      First : Natural := Value'First;
      Last  : Natural := Value'Last;

      function Is_OWS (C : Character) return Boolean is
        (C = ' ' or else C = Character'Val (9));
   begin
      while First <= Value'Last and then Is_OWS (Value (First)) loop
         First := First + 1;
      end loop;
      if First > Value'Last then
         return "";
      end if;
      while Last >= First and then Is_OWS (Value (Last)) loop
         Last := Last - 1;
      end loop;
      return Value (First .. Last);
   end Trim;

   function Lower (Value : String) return String is
      Result : String := Value;
   begin
      for I in Result'Range loop
         Result (I) := Ada.Characters.Handling.To_Lower (Result (I));
      end loop;
      return Result;
   end Lower;

   function Has_CTL (Value : String) return Boolean is
   begin
      for C of Value loop
         if (Character'Pos (C) < 32 and then C /= Character'Val (9))
           or else Character'Pos (C) = 127
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_CTL;

   function Is_Token_Char (C : Character) return Boolean is
   begin
      return (C in 'a' .. 'z') or else (C in 'A' .. 'Z')
        or else (C in '0' .. '9') or else C = '-' or else C = '_';
   end Is_Token_Char;

   function Is_Host_Char (C : Character) return Boolean is
   begin
      return (C in 'a' .. 'z') or else (C in 'A' .. 'Z')
        or else (C in '0' .. '9') or else C = '-' or else C = '.';
   end Is_Host_Char;

   function Parse_Natural (Value : String; Number : out Natural) return Boolean is
      Acc : Natural := 0;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for C of Value loop
         if C not in '0' .. '9' then
            return False;
         end if;
         if Acc > (Natural'Last - (Character'Pos (C) - Character'Pos ('0'))) / 10 then
            return False;
         end if;
         Acc := Acc * 10 + (Character'Pos (C) - Character'Pos ('0'));
      end loop;
      Number := Acc;
      return True;
   end Parse_Natural;

   function Parameter_Value
     (Value  : String;
      Result : out Unbounded_String) return Boolean
   is
   begin
      Result := Null_Unbounded_String;
      if Value'Length >= 2 and then Value (Value'First) = '"' then
         if Value (Value'Last) /= '"' then
            return False;
         end if;
         for I in Value'First + 1 .. Value'Last - 1 loop
            if Value (I) = '"' or else Value (I) = Character'Val (16#5C#) then
               return False;
            end if;
         end loop;
         Result := To_Unbounded_String
           (Value (Value'First + 1 .. Value'Last - 1));
         return True;
      elsif Value'Length > 0 and then Value (Value'First) = '"' then
         return False;
      end if;
      Result := To_Unbounded_String (Value);
      return True;
   end Parameter_Value;

   function Valid_IPv4_Literal (Host : String) return Boolean is
      Octets      : Natural := 0;
      Octet_Start : Positive := Host'First;

      function Octet_Is_Valid (First, Last : Natural) return Boolean is
         Value : Natural := 0;
      begin
         if Last < First then
            return False;
         end if;
         for I in First .. Last loop
            if Host (I) not in '0' .. '9' then
               return False;
            end if;
            Value := Value * 10 +
              (Character'Pos (Host (I)) - Character'Pos ('0'));
            if Value > 255 then
               return False;
            end if;
         end loop;
         return True;
      end Octet_Is_Valid;
   begin
      for I in Host'Range loop
         if Host (I) = '.' then
            if not Octet_Is_Valid (Octet_Start, I - 1) then
               return False;
            end if;
            Octets := Octets + 1;
            if I = Host'Last then
               return False;
            end if;
            Octet_Start := I + 1;
         elsif Host (I) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return Octets = 3 and then Octet_Is_Valid (Octet_Start, Host'Last);
   end Valid_IPv4_Literal;

   function Valid_IPv6_Literal (Host : String) return Boolean is
      URI_Value : Http_Client.URI.URI_Reference;
   begin
      return Http_Client.URI.Parse
          ("https://[" & Host & "]/", URI_Value) = Http_Client.Errors.Ok
        and then Http_Client.URI.Kind_Of_Host (URI_Value) =
          Http_Client.URI.IPv6_Literal;
   end Valid_IPv6_Literal;

   function Protocol_Image (Protocol : Alternative_Protocol) return String is
   begin
      case Protocol is
         when Alt_Protocol_HTTP3 => return "h3";
         when Alt_Protocol_HTTP3_29 => return "h3-29";
      end case;
   end Protocol_Image;

   function Is_Expired
     (Item : Alternative;
      Now  : Ada.Calendar.Time) return Boolean is
   begin
      return Now >= Item.Expires_At;
   end Is_Expired;

   function Select_First_HTTP3 (Result : Parse_Result) return Natural is
   begin
      for I in 1 .. Result.Count loop
         if Result.Alternatives (I).Protocol = Alt_Protocol_HTTP3 then
            return I;
         end if;
      end loop;
      return 0;
   end Select_First_HTTP3;

   function Parse_Protocol
     (Text     : String;
      Protocol : out Alternative_Protocol) return Http_Client.Errors.Result_Status
   is
      L : constant String := Lower (Text);
   begin
      if L'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      for C of L loop
         if not Is_Token_Char (C) then
            return Http_Client.Errors.Invalid_Header;
         end if;
      end loop;
      if L = "h3" then
         Protocol := Alt_Protocol_HTTP3;
      elsif L = "h3-29" then
         Protocol := Alt_Protocol_HTTP3_29;
      else
         return Http_Client.Errors.Unsupported_Feature;
      end if;
      return Http_Client.Errors.Ok;
   end Parse_Protocol;

   function Parse_Authority
     (Text : String;
      Host : out Unbounded_String;
      Host_Is_Origin : out Boolean;
      Port : out Natural) return Http_Client.Errors.Result_Status
   is
      Colon       : Natural := 0;
      P           : Natural := 0;
      Label_Start : Natural := Text'First;
      Dot_Count   : Natural := 0;
      Numeric     : Boolean := True;
   begin
      if Text'Length < 2 then
         return Http_Client.Errors.Invalid_Header;
      end if;

      if Text (Text'First) = '[' then
         declare
            Close : Natural := 0;
         begin
            for I in Text'First + 1 .. Text'Last loop
               if Text (I) = ']' then
                  Close := I;
                  exit;
               end if;
            end loop;
            if Close = 0
              or else Close = Text'First + 1
              or else Close + 1 > Text'Last
              or else Text (Close + 1) /= ':'
            then
               return Http_Client.Errors.Invalid_Header;
            end if;
            if not Valid_IPv6_Literal (Text (Text'First + 1 .. Close - 1))
              or else not Parse_Natural (Text (Close + 2 .. Text'Last), P)
              or else P = 0 or else P > 65_535
            then
               return Http_Client.Errors.Invalid_Header;
            end if;
            Host_Is_Origin := False;
            Host := To_Unbounded_String
              (Lower (Text (Text'First + 1 .. Close - 1)));
            Port := P;
            return Http_Client.Errors.Ok;
         end;
      end if;

      for I in reverse Text'Range loop
         if Text (I) = ':' then
            Colon := I;
            exit;
         end if;
      end loop;
      if Colon = 0 or else Colon = Text'Last then
         return Http_Client.Errors.Invalid_Header;
      end if;
      Host_Is_Origin := Colon = Text'First;
      if not Host_Is_Origin then
         declare
            Host_Last : Natural := Colon - 1;
         begin
            if Text (Host_Last) = '.' then
               if Host_Last = Text'First then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               Host_Last := Host_Last - 1;
            end if;
            if Host_Last - Text'First + 1 > 253 then
               return Http_Client.Errors.Invalid_Header;
            end if;
            for I in Text'First .. Host_Last loop
               if not Is_Host_Char (Text (I)) then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               if Text (I) = '.' then
                  Dot_Count := Dot_Count + 1;
                  if I = Text'First
                    or else I = Host_Last
                    or else I - Label_Start > 63
                    or else Text (I - 1) = '-'
                    or else Text (I + 1) = '-'
                    or else Text (I + 1) = '.'
                  then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Label_Start := I + 1;
               elsif Text (I) not in '0' .. '9' then
                  Numeric := False;
               end if;
            end loop;
            if Text (Text'First) = '-'
              or else Text (Host_Last) = '-'
              or else Host_Last - Label_Start + 1 > 63
              or else (Numeric
                       and then Dot_Count = 3
                       and then not Valid_IPv4_Literal
                         (Text (Text'First .. Host_Last)))
            then
               return Http_Client.Errors.Invalid_Header;
            end if;
            Host := To_Unbounded_String
              (Lower (Text (Text'First .. Host_Last)));
         end;
      else
         Host := Null_Unbounded_String;
      end if;
      if not Parse_Natural (Text (Colon + 1 .. Text'Last), P)
        or else P = 0 or else P > 65_535
      then
         return Http_Client.Errors.Invalid_Header;
      end if;
      Port := P;
      return Http_Client.Errors.Ok;
   end Parse_Authority;

   function Split_End
     (Value : String;
      Start : Positive;
      Stop_Char : Character) return Natural
   is
      In_Quote : Boolean := False;
   begin
      for I in Start .. Value'Last loop
         if Value (I) = '"' then
            In_Quote := not In_Quote;
         elsif not In_Quote and then Value (I) = Stop_Char then
            return I - 1;
         end if;
      end loop;
      if In_Quote then
         return 0;
      end if;
      return Value'Last;
   end Split_End;

   function Parse_One
     (Segment         : String;
      Received_At     : Ada.Calendar.Time;
      Maximum_Max_Age : Natural;
      Item            : out Alternative) return Http_Client.Errors.Result_Status
   is
      S       : constant String := Trim (Segment);
      Eq      : Natural := 0;
      Cursor  : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
      Ma_Seen : Boolean := False;
      Persist_Seen : Boolean := False;
      Age     : Natural := Maximum_Max_Age;
   begin
      Item := (Protocol => Alt_Protocol_HTTP3,
               Host => Null_Unbounded_String,
               Host_Is_Origin => False,
               Port => 0,
               Max_Age_Seconds => 0,
               Expires_At => Ada.Calendar.Time_Of (1970, 1, 1),
               Persist => False);
      if S'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      for I in S'Range loop
         if S (I) = '=' then
            Eq := I;
            exit;
         end if;
      end loop;
      if Eq = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      Status := Parse_Protocol (Trim (S (S'First .. Eq - 1)), Item.Protocol);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Eq + 1 > S'Last or else S (Eq + 1) /= '"' then
         return Http_Client.Errors.Invalid_Header;
      end if;
      declare
         Close : Natural := 0;
      begin
         for I in Eq + 2 .. S'Last loop
            if S (I) = '"' then
               Close := I;
               exit;
            elsif Character'Pos (S (I)) < 32 or else S (I) = Character'Val (16#5C#) then
               return Http_Client.Errors.Invalid_Header;
            end if;
         end loop;
         if Close = 0 then
            return Http_Client.Errors.Invalid_Header;
         end if;
         Status := Parse_Authority
           (S (Eq + 2 .. Close - 1), Item.Host, Item.Host_Is_Origin, Item.Port);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         Cursor := Close + 1;
      end;
      while Cursor <= S'Last loop
         if S (Cursor) = ' ' or else S (Cursor) = Character'Val (9) then
            Cursor := Cursor + 1;
         elsif S (Cursor) = ';' then
            declare
               Param_Start : constant Positive := Cursor + 1;
               Param_End   : Natural := Split_End (S, Param_Start, ';');
            begin
               if Param_End = 0 or else Param_Start > S'Last then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               declare
                  P : constant String := Trim (S (Param_Start .. Param_End));
                  PEq : Natural := 0;
               begin
                  if P'Length = 0 then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  for I in P'Range loop
                     if P (I) = '=' then
                        PEq := I;
                        exit;
                     end if;
                  end loop;
                  declare
                     Name : constant String := (if PEq = 0 then Lower (P) else Lower (Trim (P (P'First .. PEq - 1))));
                     Raw_Val : constant String :=
                       (if PEq = 0 then "" else Trim (P (PEq + 1 .. P'Last)));
                     Val     : Unbounded_String;
                     N       : Natural := 0;
                  begin
                     if Name = "ma" then
                        if Ma_Seen
                          or else PEq = 0
                          or else not Parameter_Value (Raw_Val, Val)
                          or else not Parse_Natural (To_String (Val), N)
                        then
                           return Http_Client.Errors.Invalid_Header;
                        end if;
                        Ma_Seen := True;
                        Age := (if N > Maximum_Max_Age then Maximum_Max_Age else N);
                     elsif Name = "persist" then
                        if Persist_Seen
                          or else not Parameter_Value (Raw_Val, Val)
                        then
                           return Http_Client.Errors.Invalid_Header;
                        end if;
                        Persist_Seen := True;
                        if PEq = 0 or else To_String (Val) = "1" then
                           Item.Persist := True;
                        elsif To_String (Val) = "0" then
                           Item.Persist := False;
                        else
                           return Http_Client.Errors.Invalid_Header;
                        end if;
                     elsif Name = "" then
                        return Http_Client.Errors.Invalid_Header;
                     else
                        null;
                     end if;
                  end;
               end;
               Cursor := Param_End + 1;
            end;
         else
            return Http_Client.Errors.Invalid_Header;
         end if;
      end loop;
      declare
         Expires : Ada.Calendar.Time;
      begin
         Expires := Received_At + Duration (Age);
         Item.Max_Age_Seconds := Age;
         Item.Expires_At := Expires;
      exception
         when Constraint_Error | Ada.Calendar.Time_Error =>
            return Http_Client.Errors.Invalid_Header;
      end;
      return Http_Client.Errors.Ok;
   end Parse_One;

   function Parse_Header
     (Header          : String;
      Received_At     : Ada.Calendar.Time;
      Result          : out Parse_Result;
      Maximum_Max_Age : Natural := Default_Max_Age_Seconds)
      return Http_Client.Errors.Result_Status
   is
      Start  : Positive := Header'First;
      Status : Http_Client.Errors.Result_Status;
   begin
      Result := (Clear => False, Count => 0, Alternatives => (others => <>));
      if Header'Length > Default_Max_Header_Length then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      if Has_CTL (Header) then
         return Http_Client.Errors.Invalid_Header;
      end if;
      declare
         T : constant String := Trim (Header);
      begin
         if T'Length = 0 then
            return Http_Client.Errors.Invalid_Header;
         elsif Lower (T) = "clear" then
            Result.Clear := True;
            return Http_Client.Errors.Ok;
         end if;
      end;
      while Start <= Header'Last loop
         declare
            Stop : Natural := Split_End (Header, Start, ',');
         begin
            if Stop = 0 then
               return Http_Client.Errors.Invalid_Header;
            end if;
            if Result.Count = Max_Alternatives_Per_Header then
               return Http_Client.Errors.Header_Too_Large;
            end if;
            declare
               Item : Alternative;
            begin
               Status := Parse_One (Header (Start .. Stop), Received_At, Maximum_Max_Age, Item);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Result.Count := Result.Count + 1;
               Result.Alternatives (Result.Count) := Item;
            end;
            if Stop < Header'Last and then Header (Stop + 1) = ','
              and then Stop + 1 = Header'Last
            then
               return Http_Client.Errors.Invalid_Header;
            end if;
            Start := Stop + 2;
         end;
      end loop;
      return Http_Client.Errors.Ok;
   end Parse_Header;
end Http_Client.Alt_Svc;
