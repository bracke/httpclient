with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Http_Client.HTTPS_Records is
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

   function Is_Name_Char (C : Character) return Boolean is
   begin
      return (C in 'a' .. 'z') or else (C in 'A' .. 'Z')
        or else (C in '0' .. '9') or else C = '-' or else C = '.';
   end Is_Name_Char;

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

   function ALPN_Image (Value : ALPN_ID) return String is
   begin
      case Value is
         when ALPN_H2 => return "h2";
         when ALPN_H3 => return "h3";
         when ALPN_H3_29 => return "h3-29";
         when ALPN_Unsupported => return "unsupported";
      end case;
   end ALPN_Image;

   function Parse_ALPN (Value : String; Result : out ALPN_ID) return Boolean is
      V : constant String := Lower (Trim (Value));
   begin
      if V = "h2" then
         Result := ALPN_H2;
      elsif V = "h3" then
         Result := ALPN_H3;
      elsif V = "h3-29" then
         Result := ALPN_H3_29;
      elsif V'Length > 0 then
         Result := ALPN_Unsupported;
      else
         return False;
      end if;
      return True;
   end Parse_ALPN;

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

   function Parse_Target (Value : String; Target : out Unbounded_String) return Boolean is
      T           : constant String := Lower (Value);
      Last_Index  : Natural := T'Last;
      Label_Start : Natural := T'First;
      Dot_Count   : Natural := 0;
      Numeric     : Boolean := True;
   begin
      if T'Length = 0 then
         return False;
      end if;
      if T = "." then
         Target := To_Unbounded_String (T);
         return True;
      end if;
      if T (T'First) = '.' then
         return False;
      end if;
      if T (T'Last) = '.' then
         if T'Length = 1 then
            return False;
         end if;
         Last_Index := T'Last - 1;
      end if;
      if Last_Index - T'First + 1 > 253 then
         return False;
      end if;
      for I in T'First .. Last_Index loop
         if not Is_Name_Char (T (I)) then
            return False;
         end if;
         if T (I) = '.' then
            Dot_Count := Dot_Count + 1;
            if I = Label_Start
              or else I - Label_Start > 63
              or else T (I - 1) = '-'
              or else (I + 1 <= Last_Index and then T (I + 1) = '-')
            then
               return False;
            end if;
            Label_Start := I + 1;
         elsif T (I) not in '0' .. '9' then
            Numeric := False;
         end if;
      end loop;
      if T (Label_Start) = '-'
        or else T (Last_Index) = '-'
        or else Last_Index - Label_Start + 1 > 63
        or else (Numeric
                 and then Dot_Count = 3
                 and then not Valid_IPv4_Literal (T (T'First .. Last_Index)))
      then
         return False;
      end if;
      Target := To_Unbounded_String (T (T'First .. Last_Index));
      return True;
   end Parse_Target;

   function Parse_ALPN_List
     (Value : String;
      Item  : in out HTTPS_Record) return Http_Client.Errors.Result_Status
   is
      A_Start : Natural := Value'First;
   begin
      if Value'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      end if;
      while A_Start <= Value'Last loop
         declare
            A_Stop : Natural := Value'Last;
            A      : ALPN_ID;
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
            if not Parse_ALPN (Value (A_Start .. A_Stop), A) then
               return Http_Client.Errors.Invalid_Header;
            end if;
            for I in 1 .. Item.ALPN_Count loop
               if Item.ALPNs (I) = A then
                  return Http_Client.Errors.Invalid_Header;
               end if;
            end loop;
            if Item.ALPN_Count = Max_ALPN_Per_Record then
               return Http_Client.Errors.Header_Too_Large;
            end if;
            Item.ALPN_Count := Item.ALPN_Count + 1;
            Item.ALPNs (Item.ALPN_Count) := A;
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

   function Parse_Text_Record
     (Text   : String;
      Item : out HTTPS_Record) return Http_Client.Errors.Result_Status
   is
      Clean : constant String := Trim (Text);
      I     : Natural;
      Stop  : Natural;
      N     : Natural := 0;
      Seen_ALPN : Boolean := False;
      Seen_Port : Boolean := False;
      Seen_IPv4 : Boolean := False;
      Seen_IPv6 : Boolean := False;
      Seen_ECH  : Boolean := False;
   begin
      Item := (Priority => 0,
                 Target_Name => Null_Unbounded_String,
                 Port => Default_HTTPS_Port,
                 ALPN_Count => 0,
                 ALPNs => (others => ALPN_Unsupported),
                 Has_ECH => False,
                 Has_IPv4_Hint => False,
                 Has_IPv6_Hint => False);
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
      Stop := Next_Token_End (Clean, I);
      if not Parse_Natural (Clean (I .. Stop), N) then
         return Http_Client.Errors.Invalid_Header;
      end if;
      if N = 0 then
         return Http_Client.Errors.Unsupported_Feature;
      end if;
      Item.Priority := N;
      I := Skip_WS (Clean, Stop + 1);
      if I > Clean'Last then
         return Http_Client.Errors.Invalid_Header;
      end if;
      Stop := Next_Token_End (Clean, I);
      if not Parse_Target (Clean (I .. Stop), Item.Target_Name) then
         return Http_Client.Errors.Invalid_Header;
      end if;
      I := Skip_WS (Clean, Stop + 1);
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
               if Key = "alpn" then
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
               else
                  null;
               end if;
            end;
         end;
         I := Skip_WS (Clean, Stop + 1);
      end loop;
      return Http_Client.Errors.Ok;
   end Parse_Text_Record;

   function Append
     (List   : in out HTTPS_Record_List;
      Item : HTTPS_Record) return Http_Client.Errors.Result_Status
   is
      Stored            : HTTPS_Record := Item;
      Normalized_Target : Unbounded_String;
   begin
      if List.Count = Max_Records then
         return Http_Client.Errors.Header_Too_Large;
      end if;
      if Length (Stored.Target_Name) > 0
        and then Parse_Target (To_String (Stored.Target_Name), Normalized_Target)
      then
         Stored.Target_Name := Normalized_Target;
      end if;
      declare
         Unique_Count : Natural := 0;
         Duplicate    : Boolean;
      begin
         for I in 1 .. Stored.ALPN_Count loop
            Duplicate := False;
            for J in 1 .. Unique_Count loop
               if Stored.ALPNs (J) = Stored.ALPNs (I) then
                  Duplicate := True;
               end if;
            end loop;
            if not Duplicate then
               Unique_Count := Unique_Count + 1;
               Stored.ALPNs (Unique_Count) := Stored.ALPNs (I);
            end if;
         end loop;
         for I in Unique_Count + 1 .. Max_ALPN_Per_Record loop
            Stored.ALPNs (I) := ALPN_Unsupported;
         end loop;
         Stored.ALPN_Count := Unique_Count;
      end;
      List.Count := List.Count + 1;
      List.Items (List.Count) := Stored;
      return Http_Client.Errors.Ok;
   end Append;

   function Is_Selectable_HTTP3_Record
     (Item              : HTTPS_Record;
      Normalized_Target : out Unbounded_String) return Boolean
   is
   begin
      Normalized_Target := Null_Unbounded_String;
      return Item.Priority > 0
        and then Item.Port in 1 .. 65_535
        and then Length (Item.Target_Name) > 0
        and then Parse_Target (To_String (Item.Target_Name), Normalized_Target);
   end Is_Selectable_HTTP3_Record;

   function Select_HTTP3
     (List : HTTPS_Record_List) return Selected_HTTPS_Service
   is
      Best_Index  : Natural := 0;
      Best_ALPN   : ALPN_ID := ALPN_Unsupported;
      Best_Target : Unbounded_String := Null_Unbounded_String;
   begin
      for I in 1 .. List.Count loop
         declare
            Normalized_Target : Unbounded_String;
         begin
            if Is_Selectable_HTTP3_Record (List.Items (I), Normalized_Target) then
               for A in 1 .. List.Items (I).ALPN_Count loop
                  if List.Items (I).ALPNs (A) = ALPN_H3 then
                     if Best_Index = 0
                       or else List.Items (I).Priority < List.Items (Best_Index).Priority
                     then
                        Best_Index := I;
                        Best_ALPN := List.Items (I).ALPNs (A);
                        Best_Target := Normalized_Target;
                     end if;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      if Best_Index = 0 then
         return (Available => False,
                 Target_Name => Null_Unbounded_String,
                 Port => Default_HTTPS_Port,
                 ALPN => ALPN_Unsupported);
      end if;
      return (Available => True,
              Target_Name => Best_Target,
              Port => List.Items (Best_Index).Port,
              ALPN => Best_ALPN);
   end Select_HTTP3;
end Http_Client.HTTPS_Records;
