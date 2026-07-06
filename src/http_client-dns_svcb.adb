with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Http_Client.DNS_SVCB is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;
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

   function Valid_Target (Value : String) return Boolean is
      Last_Label_Start : Natural := Value'First;
      Last_Index       : Natural := Value'Last;
      Dot_Count        : Natural := 0;
      Numeric          : Boolean := True;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      if Value = "." then
         return True;
      end if;

      --  DNS presentation names may be absolute and therefore end in one dot.
      --  Internally we still reject empty labels, leading dots, repeated dots,
      --  and labels beginning or ending with a hyphen.
      if Value (Value'First) = '.' then
         return False;
      end if;
      if Value (Value'Last) = '.' then
         if Value'Length = 1 then
            return False;
         end if;
         Last_Index := Value'Last - 1;
      end if;
      if Last_Index - Value'First + 1 > 253 then
         return False;
      end if;

      for I in Value'First .. Last_Index loop
         declare
            C : constant Character := Value (I);
         begin
            if not ((C in 'a' .. 'z') or else (C in 'A' .. 'Z')
                    or else (C in '0' .. '9') or else C = '-' or else C = '.')
            then
               return False;
            end if;
            if C = '.' then
               Dot_Count := Dot_Count + 1;
               if I = Last_Label_Start
                 or else I - Last_Label_Start > 63
                 or else Value (I - 1) = '-'
                 or else (I + 1 <= Last_Index and then Value (I + 1) = '-')
               then
                  return False;
               end if;
               Last_Label_Start := I + 1;
            elsif C not in '0' .. '9' then
               Numeric := False;
            end if;
         end;
      end loop;
      return Value (Last_Label_Start) /= '-'
        and then Value (Last_Index) /= '-'
        and then Last_Index - Last_Label_Start + 1 <= 63
        and then (not Numeric
                  or else Dot_Count /= 3
                  or else Valid_IPv4_Literal
                    (Value (Value'First .. Last_Index)));
   end Valid_Target;

   function Normalize_Target (Value : String) return String is
      L : constant String := Lower (Value);
   begin
      if L = "." or else L (L'Last) /= '.' then
         return L;
      else
         return L (L'First .. L'Last - 1);
      end if;
   end Normalize_Target;

   function Parse_ALPN_List
     (Value : String;
      Item  : in out SVCB_Record) return Http_Client.Errors.Result_Status
   is
      A_Start : Natural := Value'First;
   begin
      if Value'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      while A_Start <= Value'Last loop
         declare
            A_Stop : Natural := Value'Last;
         begin
            for K in A_Start .. Value'Last loop
               if Value (K) = ',' then
                  if K = A_Start then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  A_Stop := K - 1;
                  exit;
               end if;
            end loop;
            if A_Stop < A_Start then
               return Http_Client.Errors.Invalid_Header;
            end if;
            declare
               A : constant String := Lower (Trim (Value (A_Start .. A_Stop)));
            begin
               if A'Length = 0 then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               if Has_ALPN (Item, A) then
                  return Http_Client.Errors.Invalid_Header;
               end if;
               if Item.ALPN_Count = Max_ALPN_Per_Record then
                  return Http_Client.Errors.Header_Too_Large;
               end if;
               Item.ALPN_Count := Item.ALPN_Count + 1;
               Item.ALPNs (Item.ALPN_Count) := To_Unbounded_String (A);
            end;
            if A_Stop = Value'Last then
               return Http_Client.Errors.Ok;
            end if;
            if A_Stop + 1 > Value'Last or else Value (A_Stop + 1) /= ',' then
               return Http_Client.Errors.Invalid_Header;
            end if;
            if A_Stop + 1 = Value'Last then
               return Http_Client.Errors.Invalid_Header;
            end if;
            A_Start := A_Stop + 2;
         end;
      end loop;
      return Http_Client.Errors.Ok;
   end Parse_ALPN_List;

   function Next_Token_End (Text : String; Start : Positive) return Natural is
   begin
      for I in Start .. Text'Last loop
         if Text (I) = ' ' or else Text (I) = Character'Val (9) then
            return I - 1;
         end if;
      end loop;
      return Text'Last;
   end Next_Token_End;

   function Skip_WS (Text : String; Start : Natural) return Natural is
      I : Natural := Start;
   begin
      while I <= Text'Last
        and then (Text (I) = ' ' or else Text (I) = Character'Val (9))
      loop
         I := I + 1;
      end loop;
      return I;
   end Skip_WS;

   function Has_ALPN
     (Item : SVCB_Record;
      ALPN   : String) return Boolean
   is
      L : constant String := Lower (Trim (ALPN));
   begin
      for I in 1 .. Item.ALPN_Count loop
         if Lower (Trim (To_String (Item.ALPNs (I)))) = L then
            return True;
         end if;
      end loop;
      return False;
   end Has_ALPN;

   function Parse_Record
     (Text   : String;
      Item : out SVCB_Record) return Http_Client.Errors.Result_Status
   is
      Clean : constant String := Trim (Text);
      I     : Natural;
      Stop  : Natural;
      Seen_Priority : Boolean := False;
      Seen_Target   : Boolean := False;
      Seen_ALPN     : Boolean := False;
      Seen_Port     : Boolean := False;
      Seen_IPv4     : Boolean := False;
      Seen_IPv6     : Boolean := False;
      Seen_ECH      : Boolean := False;
      Seen_TTL      : Boolean := False;
      N             : Natural := 0;
   begin
      Item := (Priority => 1,
                 Target => Null_Unbounded_String,
                 Port => 443,
                 ALPN_Count => 0,
                 ALPNs => (others => Null_Unbounded_String),
                 Has_ECH => False,
                 Has_IPv4_Hint => False,
                 Has_IPv6_Hint => False,
                 TTL_Seconds => 0);
      if Clean'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      for C of Clean loop
         if (Character'Pos (C) < 32 and then C /= Character'Val (9))
           or else Character'Pos (C) = 127
         then
            return Http_Client.Errors.Invalid_Header;
         end if;
      end loop;
      I := Clean'First;
      while I <= Clean'Last loop
         Stop := Next_Token_End (Clean, I);
         declare
            Token : constant String := Clean (I .. Stop);
            Eq    : Natural := 0;
         begin
            for J in Token'Range loop
               if Token (J) = '=' then
                  Eq := J;
                  exit;
               end if;
            end loop;
            if Eq = 0 or else Eq = Token'First or else Eq = Token'Last then
               return Http_Client.Errors.Invalid_Header;
            end if;
            declare
               Key : constant String := Lower (Token (Token'First .. Eq - 1));
               Val : constant String := Token (Eq + 1 .. Token'Last);
            begin
               if Key = "priority" then
                  if Seen_Priority or else not Parse_Natural (Val, N) then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_Priority := True;
                  if N = 0 then
                     return Http_Client.Errors.Unsupported_Feature;
                  end if;
                  Item.Priority := N;
               elsif Key = "target" then
                  if Seen_Target or else not Valid_Target (Val) then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_Target := True;
                  Item.Target := To_Unbounded_String (Normalize_Target (Val));
               elsif Key = "alpn" then
                  if Seen_ALPN then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_ALPN := True;
                  declare
                     ALPN_Status : constant Http_Client.Errors.Result_Status :=
                       Parse_ALPN_List (Val, Item);
                  begin
                     if ALPN_Status /= Http_Client.Errors.Ok then
                        return ALPN_Status;
                     end if;
                  end;
               elsif Key = "port" then
                  if Seen_Port or else not Parse_Natural (Val, N) or else N = 0 or else N > 65_535 then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_Port := True;
                  Item.Port := N;
               elsif Key = "ipv4hint" then
                  if Seen_IPv4 then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_IPv4 := True;
                  Item.Has_IPv4_Hint := True;
               elsif Key = "ipv6hint" then
                  if Seen_IPv6 then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_IPv6 := True;
                  Item.Has_IPv6_Hint := True;
               elsif Key = "ech" then
                  if Seen_ECH then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_ECH := True;
                  Item.Has_ECH := True;
               elsif Key = "ttl" then
                  if Seen_TTL or else not Parse_Natural (Val, N) then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
                  Seen_TTL := True;
                  Item.TTL_Seconds := N;
               else
                  null;
               end if;
            end;
         end;
         I := Skip_WS (Clean, Stop + 1);
      end loop;
      if not Seen_Priority or else not Seen_Target then
         return Http_Client.Errors.Invalid_Header;
      end if;
      return Http_Client.Errors.Ok;
   end Parse_Record;

   function Append
     (Set    : in out Record_Set;
      Item : SVCB_Record) return Http_Client.Errors.Result_Status
   is
      Stored : SVCB_Record := Item;
   begin
      if Set.Count = Max_Records then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      if Length (Stored.Target) > 0
        and then Valid_Target (To_String (Stored.Target))
      then
         Stored.Target :=
           To_Unbounded_String (Normalize_Target (To_String (Stored.Target)));
      end if;
      declare
         Unique_Count : Natural := 0;
         Canonical    : Unbounded_String;
         Duplicate    : Boolean;
      begin
         for I in 1 .. Stored.ALPN_Count loop
            Canonical :=
              To_Unbounded_String
                (Lower (Trim (To_String (Stored.ALPNs (I)))));
            Duplicate := Length (Canonical) = 0;
            for J in 1 .. Unique_Count loop
               if To_String (Stored.ALPNs (J)) = To_String (Canonical) then
                  Duplicate := True;
               end if;
            end loop;
            if not Duplicate then
               Unique_Count := Unique_Count + 1;
               Stored.ALPNs (Unique_Count) := Canonical;
            end if;
         end loop;
         for I in Unique_Count + 1 .. Max_ALPN_Per_Record loop
            Stored.ALPNs (I) := Null_Unbounded_String;
         end loop;
         Stored.ALPN_Count := Unique_Count;
      end;
      Set.Count := Set.Count + 1;
      Set.Items (Set.Count) := Stored;
      return Http_Client.Errors.Ok;
   end Append;

   function Is_Selectable_HTTP3_Record (Item : SVCB_Record) return Boolean is
   begin
      return Item.Priority > 0
        and then Item.Port in 1 .. 65_535
        and then Length (Item.Target) > 0
        and then Valid_Target (To_String (Item.Target))
        and then Has_ALPN (Item, "h3");
   end Is_Selectable_HTTP3_Record;

   function Select_HTTP3_Record (Set : Record_Set) return Natural is
      Best : Natural := 0;
   begin
      for I in 1 .. Set.Count loop
         if Is_Selectable_HTTP3_Record (Set.Items (I)) then
            if Best = 0 or else Set.Items (I).Priority < Set.Items (Best).Priority then
               Best := I;
            end if;
         end if;
      end loop;
      return Best;
   end Select_HTTP3_Record;
end Http_Client.DNS_SVCB;
