with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.URI;

package body Http_Client.Cookies is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Http_Client.Errors.Result_Status;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Trim (Text : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both);
   end Trim;

   function Starts_With (Text : String; Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Empty_Jar
     (Limits : Cookie_Limits := Default_Limits) return Cookie_Jar
   is
   begin
      return (Items => Cookie_Vectors.Empty_Vector,
              Limits => Limits,
              Next_Creation => 1);
   end Empty_Jar;

   function Is_Token_Character (C : Character) return Boolean is
   begin
      return
        (C in 'A' .. 'Z') or else
        (C in 'a' .. 'z') or else
        (C in '0' .. '9') or else
        C = '!' or else C = '#' or else C = '$' or else C = '%' or else
        C = '&' or else Character'Pos (C) = 39 or else C = '*' or else
        C = '+' or else C = '-' or else C = '.' or else C = '^' or else
        C = '_' or else C = '`' or else C = '|' or else C = '~';
   end Is_Token_Character;

   function Is_Valid_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0 then
         return False;
      end if;

      for C of Name loop
         if not Is_Token_Character (C) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Name;

   function Is_Valid_Value (Value : String) return Boolean is
   begin
      for C of Value loop
         if Character'Pos (C) < 32
           or else Character'Pos (C) = 127
           or else (Character'Pos (C) >= 128 and then Character'Pos (C) <= 159)
           or else C = ';'
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Value;

   function Name (Item : Cookie) return String is
   begin
      return To_String (Item.Name_Value);
   end Name;

   function Value (Item : Cookie) return String is
   begin
      return To_String (Item.Cookie_Value);
   end Value;

   function Domain (Item : Cookie) return String is
   begin
      return To_String (Item.Domain_Value);
   end Domain;

   function Path (Item : Cookie) return String is
   begin
      return To_String (Item.Path_Value);
   end Path;

   function Host_Only (Item : Cookie) return Boolean is
   begin
      return Item.Host_Only_Value;
   end Host_Only;

   function Secure (Item : Cookie) return Boolean is
   begin
      return Item.Secure_Value;
   end Secure;

   function Http_Only (Item : Cookie) return Boolean is
   begin
      return Item.Http_Only_Value;
   end Http_Only;

   function SameSite (Item : Cookie) return SameSite_Policy is
   begin
      return Item.SameSite_Value;
   end SameSite;

   function Is_Persistent (Item : Cookie) return Boolean is
   begin
      return Item.Persistent;
   end Is_Persistent;

   function Is_Expired
     (Item : Cookie;
      Now  : Ada.Calendar.Time := Ada.Calendar.Clock) return Boolean
   is
   begin
      return Item.Persistent and then Item.Expires_At <= Now;
   end Is_Expired;

   function Default_Path (Request_Path : String) return String is
      Slash_Count : Natural := 0;
   begin
      if Request_Path'Length = 0 or else Request_Path (Request_Path'First) /= '/' then
         return "/";
      end if;

      for C of Request_Path loop
         if C = '/' then
            Slash_Count := Slash_Count + 1;
         end if;
      end loop;

      if Slash_Count <= 1 then
         return "/";
      end if;

      for I in reverse Request_Path'Range loop
         if Request_Path (I) = '/' then
            if I = Request_Path'First then
               return "/";
            else
               return Request_Path (Request_Path'First .. I - 1);
            end if;
         end if;
      end loop;

      return "/";
   end Default_Path;

   function Path_Matches
     (Cookie_Path  : String;
      Request_Path : String) return Boolean
   is
      Req : constant String := (if Request_Path'Length = 0 then "/" else Request_Path);
      Normalized_Cookie_Path : constant String :=
        (if Cookie_Path'Length = 0 then "/" else Cookie_Path);
   begin
      if Normalized_Cookie_Path (Normalized_Cookie_Path'First) /= '/' then
         return False;
      end if;

      if Normalized_Cookie_Path = "/" then
         return Req'Length >= 1 and then Req (Req'First) = '/';
      end if;

      if Req'Length < Normalized_Cookie_Path'Length then
         return False;
      end if;

      if Req (Req'First .. Req'First + Normalized_Cookie_Path'Length - 1)
        /= Normalized_Cookie_Path
      then
         return False;
      end if;

      if Req'Length = Normalized_Cookie_Path'Length then
         return True;
      end if;

      return Normalized_Cookie_Path (Normalized_Cookie_Path'Last) = '/'
        or else Req (Req'First + Normalized_Cookie_Path'Length) = '/';
   end Path_Matches;

   function Is_IPv4_Literal (Host : String) return Boolean is
      Dots     : Natural := 0;
      In_Part  : Boolean := False;
   begin
      if Host'Length = 0 then
         return False;
      end if;

      for C of Host loop
         if C = '.' then
            if not In_Part then
               return False;
            end if;
            Dots := Dots + 1;
            In_Part := False;
         elsif C in '0' .. '9' then
            In_Part := True;
         else
            return False;
         end if;
      end loop;

      return Dots = 3 and then In_Part;
   end Is_IPv4_Literal;

   function Valid_Domain_Text (Domain : String) return Boolean is
      Label_Start : Natural := Domain'First;
      Label_Len   : Natural := 0;
      Dot_Count   : Natural := 0;
   begin
      if Domain'Length = 0 or else Domain (Domain'First) = '.'
        or else Domain (Domain'Last) = '.'
      then
         return False;
      end if;

      --  Conservative no-PSL policy: do not accept single-label Domain
      --  attributes such as "com" or "localhost". Host-only cookies still
      --  work for single-label origins when no Domain attribute is present.
      for I in Domain'Range loop
         declare
            C : constant Character := Domain (I);
         begin
            if C = '.' then
               Dot_Count := Dot_Count + 1;
               if Label_Len = 0
                 or else Label_Len > 63
                 or else Domain (Label_Start) = '-'
                 or else Domain (I - 1) = '-'
               then
                  return False;
               end if;

               Label_Start := I + 1;
               Label_Len := 0;
            elsif (C in 'a' .. 'z') or else (C in '0' .. '9') or else C = '-' then
               Label_Len := Label_Len + 1;
            else
               return False;
            end if;
         end;
      end loop;

      return Dot_Count > 0
        and then Label_Len > 0
        and then Label_Len <= 63
        and then Domain (Label_Start) /= '-'
        and then Domain (Domain'Last) /= '-';
   end Valid_Domain_Text;

   function Domain_Matches
     (Cookie_Domain : String;
      Request_Host  : String;
      Host_Only     : Boolean) return Boolean
   is
      C_Domain : constant String := Lower (Cookie_Domain);
      R_Host   : constant String := Lower (Request_Host);
      Suffix_Start : Natural;
   begin
      if C_Domain'Length = 0 or else R_Host'Length = 0 then
         return False;
      end if;

      if Host_Only then
         return R_Host = C_Domain;
      end if;

      if Is_IPv4_Literal (R_Host) then
         return False;
      end if;

      if R_Host = C_Domain then
         return True;
      end if;

      if R_Host'Length <= C_Domain'Length then
         return False;
      end if;

      Suffix_Start := R_Host'Last - C_Domain'Length + 1;

      return Suffix_Start > R_Host'First
        and then R_Host (Suffix_Start - 1) = '.'
        and then R_Host (Suffix_Start .. R_Host'Last) = C_Domain;
   end Domain_Matches;

   function Month_Number (Text : String) return Natural is
      M : constant String := Lower (Text);
   begin
      if M = "jan" then return 1; elsif M = "feb" then return 2;
      elsif M = "mar" then return 3; elsif M = "apr" then return 4;
      elsif M = "may" then return 5; elsif M = "jun" then return 6;
      elsif M = "jul" then return 7; elsif M = "aug" then return 8;
      elsif M = "sep" then return 9; elsif M = "oct" then return 10;
      elsif M = "nov" then return 11; elsif M = "dec" then return 12;
      else return 0;
      end if;
   end Month_Number;

   function Parse_Natural_Digits (Text : String; Value : out Natural) return Boolean is
      Acc : Natural := 0;
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;

      for C of Text loop
         if C not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Natural := Character'Pos (C) - Character'Pos ('0');
         begin
            if Acc > (Natural'Last - Digit) / 10 then
               return False;
            end if;
            Acc := Acc * 10 + Digit;
         end;
      end loop;

      Value := Acc;
      return True;
   end Parse_Natural_Digits;

   function Parse_Two (Text : String; Value : out Natural) return Boolean is
   begin
      if Text'Length /= 2 then
         Value := 0;
         return False;
      end if;

      return Parse_Natural_Digits (Text, Value);
   end Parse_Two;

   function Parse_HTTP_Date (Text : String; Result : out Ada.Calendar.Time) return Boolean is
      T : constant String := Trim (Text);
      Day    : Natural := 0;
      Month  : Natural := 0;
      Year   : Natural := 0;
      Hour   : Natural := 0;
      Minute : Natural := 0;
      Second : Natural := 0;
   begin
      Result := Ada.Calendar.Time_Of (1970, 1, 1);

      --  Conservative IMF-fixdate subset: Wdy, DD Mon YYYY HH:MM:SS GMT
      if T'Length /= 29 or else T (T'First + 3) /= ','
        or else T (T'First + 4) /= ' '
        or else T (T'First + 7) /= ' '
        or else T (T'First + 11) /= ' '
        or else T (T'First + 16) /= ' '
        or else T (T'First + 19) /= ':'
        or else T (T'First + 22) /= ':'
        or else T (T'First + 25) /= ' '
        or else T (T'First + 26 .. T'First + 28) /= "GMT"
      then
         return False;
      end if;

      Month := Month_Number (T (T'First + 8 .. T'First + 10));
      if not Parse_Two (T (T'First + 5 .. T'First + 6), Day)
        or else not Parse_Natural_Digits (T (T'First + 12 .. T'First + 15), Year)
        or else not Parse_Two (T (T'First + 17 .. T'First + 18), Hour)
        or else not Parse_Two (T (T'First + 20 .. T'First + 21), Minute)
        or else not Parse_Two (T (T'First + 23 .. T'First + 24), Second)
        or else Month = 0
        or else Day < 1 or else Day > 31 or else Hour > 23 or else Minute > 59
        or else Second > 59
      then
         return False;
      end if;

      Result := Ada.Calendar.Time_Of
        (Year    => Ada.Calendar.Year_Number (Year),
         Month   => Ada.Calendar.Month_Number (Month),
         Day     => Ada.Calendar.Day_Number (Day),
         Seconds      => Ada.Calendar.Day_Duration
           (Hour * 3600 + Minute * 60 + Second));
      return True;
   exception
      when others =>
         Result := Ada.Calendar.Time_Of (1970, 1, 1);
         return False;
   end Parse_HTTP_Date;

   function Signed_Integer (Text : String; Value : out Integer) return Boolean is
      T        : constant String := Trim (Text);
      First    : Natural;
      Negative : Boolean := False;
      Limit    : Long_Long_Integer;
      Acc      : Long_Long_Integer := 0;
   begin
      Value := 0;

      if T'Length = 0 then
         return False;
      end if;

      if T (T'First) = '-' then
         if T'Length = 1 then
            return False;
         end if;

         Negative := True;
         First := T'First + 1;
         Limit := Long_Long_Integer (Integer'Last) + 1;
      else
         First := T'First;
         Limit := Long_Long_Integer (Integer'Last);
      end if;

      for I in First .. T'Last loop
         if T (I) not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Long_Long_Integer :=
              Long_Long_Integer (Character'Pos (T (I)) - Character'Pos ('0'));
         begin
            if Acc > (Limit - Digit) / 10 then
               return False;
            end if;
            Acc := Acc * 10 + Digit;
         end;
      end loop;

      if Negative then
         if Acc = Limit then
            Value := Integer'First;
         else
            Value := -Integer (Acc);
         end if;
      else
         Value := Integer (Acc);
      end if;

      return True;
   end Signed_Integer;

   procedure Split_Attribute
     (Text  : String;
      Name  : out Unbounded_String;
      Value : out Unbounded_String;
      Has_Value : out Boolean)
   is
   begin
      Has_Value := False;
      Name := To_Unbounded_String (Trim (Text));
      Value := Null_Unbounded_String;

      for I in Text'Range loop
         if Text (I) = '=' then
            Has_Value := True;
            Name := To_Unbounded_String (Trim (Text (Text'First .. I - 1)));
            Value := To_Unbounded_String (Trim (Text (I + 1 .. Text'Last)));
            return;
         end if;
      end loop;
   end Split_Attribute;

   function Unquote_Value (Text : String; Ok : out Boolean) return String is
   begin
      Ok := True;
      if Text'Length >= 2 and then Text (Text'First) = '"'
        and then Text (Text'Last) = '"'
      then
         return Text (Text'First + 1 .. Text'Last - 1);
      elsif Text'Length > 0 and then (Text (Text'First) = '"' or else Text (Text'Last) = '"') then
         Ok := False;
         return "";
      else
         return Text;
      end if;
   end Unquote_Value;

   function Parse_Set_Cookie
     (Header_Value : String;
      Origin_URI   : Http_Client.URI.URI_Reference;
      Item         : out Cookie;
      Now          : Ada.Calendar.Time := Ada.Calendar.Clock;
      Limits       : Cookie_Limits := Default_Limits)
      return Http_Client.Errors.Result_Status
   is
      use Http_Client.Errors;
      Origin_Host_Value : Unbounded_String := Null_Unbounded_String;
      Origin_Path_Value : Unbounded_String := Null_Unbounded_String;

      function Origin_Host return String is
        (To_String (Origin_Host_Value));

      function Origin_Path return String is
        (To_String (Origin_Path_Value));

      First_End   : Natural := Header_Value'Last + 1;
      C           : Cookie;
      Max_Age_Seen : Boolean := False;
      Path_Attribute_Seen : Boolean := False;
   begin
      Item := C;

      if Header_Value'Length = 0 or else Trim (Header_Value)'Length = 0 then
         return Invalid_Cookie;
      end if;

      if not Http_Client.URI.Is_Parsed (Origin_URI) then
         return Invalid_URI;
      end if;

      Origin_Host_Value :=
        To_Unbounded_String (Lower (Http_Client.URI.Host (Origin_URI)));
      Origin_Path_Value :=
        To_Unbounded_String (Http_Client.URI.Path (Origin_URI));

      for I in Header_Value'Range loop
         if Header_Value (I) = ';' then
            First_End := I;
            exit;
         end if;
      end loop;

      declare
         Pair : constant String := Trim
           (Header_Value (Header_Value'First .. First_End - 1));
         Eq   : Natural := 0;
      begin
         if Pair'Length = 0 then
            return Invalid_Cookie;
         end if;

         for I in Pair'Range loop
            if Pair (I) = '=' then
               Eq := I;
               exit;
            end if;
         end loop;

         if Eq = 0 then
            return Invalid_Cookie;
         end if;

         declare
            Raw_Name  : constant String := Trim (Pair (Pair'First .. Eq - 1));
            Raw_Value : constant String := Trim (Pair (Eq + 1 .. Pair'Last));
            Value_Ok  : Boolean;
            Clean_Value : constant String := Unquote_Value (Raw_Value, Value_Ok);
         begin
            if not Value_Ok or else not Is_Valid_Name (Raw_Name)
              or else not Is_Valid_Value (Clean_Value)
            then
               return Invalid_Cookie;
            end if;

            if Raw_Name'Length > Limits.Max_Name_Length
              or else Clean_Value'Length > Limits.Max_Value_Length
            then
               return Cookie_Too_Large;
            end if;

            C.Name_Value := To_Unbounded_String (Raw_Name);
            C.Cookie_Value := To_Unbounded_String (Clean_Value);
            C.Domain_Value := To_Unbounded_String (Origin_Host);
            C.Path_Value := To_Unbounded_String (Default_Path (Origin_Path));
            C.Host_Only_Value := True;
         end;
      end;

      if First_End <= Header_Value'Last then
         declare
            Pos : Natural := First_End + 1;
         begin
            while Pos <= Header_Value'Last loop
               declare
                  Start : constant Natural := Pos;
                  Stop  : Natural := Header_Value'Last + 1;
               begin
                  while Pos <= Header_Value'Last loop
                     if Header_Value (Pos) = ';' then
                        Stop := Pos;
                        exit;
                     end if;
                     Pos := Pos + 1;
                  end loop;

                  declare
                     Raw_Attr : constant String := Header_Value (Start .. Stop - 1);
                     A_Name   : Unbounded_String;
                     A_Value  : Unbounded_String;
                     Has_Val  : Boolean;
                  begin
                     Split_Attribute (Raw_Attr, A_Name, A_Value, Has_Val);

                     declare
                        Attr_Name : constant String := Lower (To_String (A_Name));
                        Attr_Val  : constant String := To_String (A_Value);
                     begin
                        if Attr_Name = "secure" and then not Has_Val then
                           C.Secure_Value := True;
                        elsif Attr_Name = "httponly" and then not Has_Val then
                           C.Http_Only_Value := True;
                        elsif Attr_Name = "samesite" and then Has_Val then
                           declare
                              S : constant String := Lower (Attr_Val);
                           begin
                              if S = "strict" then
                                 C.SameSite_Value := SameSite_Strict;
                              elsif S = "lax" then
                                 C.SameSite_Value := SameSite_Lax;
                              elsif S = "none" then
                                 C.SameSite_Value := SameSite_None;
                              else
                                 C.SameSite_Value := SameSite_Unknown;
                              end if;
                           end;
                        elsif Attr_Name = "path" and then Has_Val then
                           if Attr_Val'Length > 0 and then Attr_Val (Attr_Val'First) = '/'
                             and then Is_Valid_Value (Attr_Val)
                           then
                              C.Path_Value := To_Unbounded_String (Attr_Val);
                              Path_Attribute_Seen := True;
                           end if;
                        elsif Attr_Name = "domain" and then Has_Val then
                           declare
                              D0 : constant String := Lower (Trim (Attr_Val));
                              D  : constant String :=
                                (if D0'Length > 0 and then D0 (D0'First) = '.'
                                 then D0 (D0'First + 1 .. D0'Last) else D0);
                           begin
                              if not Valid_Domain_Text (D) or else Is_IPv4_Literal (Origin_Host)
                                or else Is_IPv4_Literal (D)
                              then
                                 return Cookie_Rejected;
                              end if;

                              if not Domain_Matches (D, Origin_Host, False) then
                                 return Cookie_Rejected;
                              end if;

                              C.Domain_Value := To_Unbounded_String (D);
                              C.Host_Only_Value := False;
                           end;
                        elsif Attr_Name = "max-age" and then Has_Val then
                           declare
                              Age : Integer;
                           begin
                              if not Signed_Integer (Attr_Val, Age) then
                                 return Invalid_Cookie;
                              end if;

                              Max_Age_Seen := True;
                              C.Persistent := True;
                              if Age <= 0 then
                                 C.Expires_At := Now;
                              else
                                 C.Expires_At := Now + Duration (Age);
                              end if;
                           end;
                        elsif Attr_Name = "expires" and then Has_Val and then not Max_Age_Seen then
                           declare
                              Expiry : Ada.Calendar.Time;
                           begin
                              if Parse_HTTP_Date (Attr_Val, Expiry) then
                                 C.Persistent := True;
                                 C.Expires_At := Expiry;
                              else
                                 return Invalid_Cookie;
                              end if;
                           end;
                        else
                           null;
                        end if;
                     end;
                  end;

                  Pos := Stop + 1;
               end;
            end loop;
         end;
      end if;

      if Starts_With (Name (C), "__Secure-") then
         if not C.Secure_Value or else not Http_Client.URI.Requires_TLS (Origin_URI) then
            return Cookie_Rejected;
         end if;
      end if;

      if Starts_With (Name (C), "__Host-") then
         if not C.Secure_Value
           or else not Http_Client.URI.Requires_TLS (Origin_URI)
           or else not C.Host_Only_Value
           or else not Path_Attribute_Seen
           or else Path (C) /= "/"
         then
            return Cookie_Rejected;
         end if;
      end if;

      Item := C;
      return Ok;
   exception
      when others =>
         Item := (others => <>);
         return Http_Client.Errors.Invalid_Cookie;
   end Parse_Set_Cookie;

   function Same_Key (A, B : Cookie) return Boolean is
   begin
      return Name (A) = Name (B)
        and then Domain (A) = Domain (B)
        and then Host_Only (A) = Host_Only (B)
        and then Path (A) = Path (B);
   end Same_Key;

   function Domain_Count (Jar : Cookie_Jar; Domain_Text : String) return Natural is
      Count : Natural := 0;
   begin
      for C of Jar.Items loop
         if Domain (C) = Domain_Text then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Domain_Count;

   procedure Delete_Oldest (Jar : in out Cookie_Jar; Domain_Only : String := "") is
      Found : Boolean := False;
      Pos   : Positive := 1;
      Oldest : Natural := Natural'Last;
   begin
      if Jar.Items.Is_Empty then
         return;
      end if;

      for I in Jar.Items.First_Index .. Jar.Items.Last_Index loop
         if (Domain_Only = "" or else Domain (Jar.Items (I)) = Domain_Only)
           and then Jar.Items (I).Creation_Order < Oldest
         then
            Found := True;
            Pos := I;
            Oldest := Jar.Items (I).Creation_Order;
         end if;
      end loop;

      if Found then
         Jar.Items.Delete (Pos);
      end if;
   end Delete_Oldest;

   function Add_At
     (Jar  : in out Cookie_Jar;
      Item : Cookie;
      Now  : Ada.Calendar.Time) return Http_Client.Errors.Result_Status
   is
      New_Item : Cookie := Item;
   begin
      if Is_Expired (New_Item, Now) then
         if not Jar.Items.Is_Empty then
            declare
               I : Positive := Jar.Items.First_Index;
            begin
               while I <= Jar.Items.Last_Index loop
                  if Same_Key (Jar.Items (I), New_Item) then
                     Jar.Items.Delete (I);
                  else
                     I := I + 1;
                  end if;
               end loop;
            end;
         end if;
         return Http_Client.Errors.Ok;
      end if;

      if not Jar.Items.Is_Empty then
         for I in Jar.Items.First_Index .. Jar.Items.Last_Index loop
            if Same_Key (Jar.Items (I), New_Item) then
               New_Item.Creation_Order := Jar.Items (I).Creation_Order;
               Jar.Items.Replace_Element (I, New_Item);
               return Http_Client.Errors.Ok;
            end if;
         end loop;
      end if;

      while Natural (Jar.Items.Length) >= Jar.Limits.Max_Cookies
        and then Jar.Limits.Max_Cookies > 0
      loop
         Delete_Oldest (Jar);
      end loop;

      while Domain_Count (Jar, Domain (New_Item)) >= Jar.Limits.Max_Cookies_Per_Domain
        and then Jar.Limits.Max_Cookies_Per_Domain > 0
      loop
         Delete_Oldest (Jar, Domain (New_Item));
      end loop;

      if Jar.Limits.Max_Cookies = 0 or else Jar.Limits.Max_Cookies_Per_Domain = 0 then
         return Http_Client.Errors.Cookie_Rejected;
      end if;

      New_Item.Creation_Order := Jar.Next_Creation;
      Jar.Next_Creation := Jar.Next_Creation + 1;
      Jar.Items.Append (New_Item);
      return Http_Client.Errors.Ok;
   end Add_At;

   function Add
     (Jar  : in out Cookie_Jar;
      Item : Cookie) return Http_Client.Errors.Result_Status
   is
   begin
      return Add_At (Jar, Item, Ada.Calendar.Clock);
   end Add;

   procedure Clear (Jar : in out Cookie_Jar) is
   begin
      Jar.Items.Clear;
      Jar.Next_Creation := 1;
   end Clear;

   function Length (Jar : Cookie_Jar) return Natural is
   begin
      return Natural (Jar.Items.Length);
   end Length;

   function Cookie_At
     (Jar   : Cookie_Jar;
      Index : Positive) return Cookie
   is
   begin
      return Jar.Items (Index);
   end Cookie_At;

   procedure Remove_Expired
     (Jar : in out Cookie_Jar;
      Now : Ada.Calendar.Time := Ada.Calendar.Clock)
   is
   begin
      if Jar.Items.Is_Empty then
         return;
      end if;

      declare
         I : Positive := Jar.Items.First_Index;
      begin
         while I <= Jar.Items.Last_Index loop
            if Is_Expired (Jar.Items (I), Now) then
               Jar.Items.Delete (I);
            else
               I := I + 1;
            end if;
         end loop;
      end;
   end Remove_Expired;

   procedure Store_From_Response
     (Jar        : in out Cookie_Jar;
      Origin_URI : Http_Client.URI.URI_Reference;
      Headers    : Http_Client.Headers.Header_List;
      Now        : Ada.Calendar.Time := Ada.Calendar.Clock;
      Strict     : Boolean := False;
      Status     : out Http_Client.Errors.Result_Status)
   is
      Parsed : Cookie;
      S      : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Errors.Ok;

      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         if Lower (Http_Client.Headers.Name_At (Headers, I)) = "set-cookie" then
            S := Parse_Set_Cookie
              (Header_Value => Http_Client.Headers.Value_At (Headers, I),
               Origin_URI   => Origin_URI,
               Item         => Parsed,
               Now          => Now,
               Limits       => Jar.Limits);

            if S = Http_Client.Errors.Ok then
               S := Add_At (Jar, Parsed, Now);
            end if;

            if S /= Http_Client.Errors.Ok then
               Status := S;
               if Strict then
                  return;
               end if;
            end if;
         end if;
      end loop;

      if not Strict then
         Status := Http_Client.Errors.Ok;
      end if;
   end Store_From_Response;

   function Get_Cookie_Header
     (Jar        : Cookie_Jar;
      Target_URI : Http_Client.URI.URI_Reference;
      Now        : Ada.Calendar.Time := Ada.Calendar.Clock)
      return String
   is
      type Match is record
         C : Cookie;
      end record;
      package Match_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive,
         Element_Type => Match);
      Matches : Match_Vectors.Vector;
      Result  : Unbounded_String := Null_Unbounded_String;
   begin
      if not Http_Client.URI.Is_Parsed (Target_URI) then
         return "";
      end if;

      declare
         Host   : constant String := Http_Client.URI.Host (Target_URI);
         Path_T : constant String := Http_Client.URI.Path (Target_URI);
         HTTPS  : constant Boolean := Http_Client.URI.Requires_TLS (Target_URI);
      begin
         for C of Jar.Items loop
            if not Is_Expired (C, Now)
              and then (not Secure (C) or else HTTPS)
              and then Domain_Matches (Domain (C), Host, Host_Only (C))
              and then Path_Matches (Path (C), Path_T)
            then
               Matches.Append (Match'(C => C));
            end if;
         end loop;
      end;

      if not Matches.Is_Empty then
         --  Small deterministic insertion sort by longer path, then creation.
         for I in Matches.First_Index + 1 .. Matches.Last_Index loop
            declare
               Key : constant Match := Matches (I);
               J   : Positive := I;
            begin
               while J > Matches.First_Index loop
                  declare
                     Prev : constant Match := Matches (J - 1);
                     Swap : constant Boolean :=
                       Path (Key.C)'Length > Path (Prev.C)'Length
                       or else (Path (Key.C)'Length = Path (Prev.C)'Length
                                and then Key.C.Creation_Order < Prev.C.Creation_Order);
                  begin
                     exit when not Swap;
                     Matches.Replace_Element (J, Prev);
                     J := J - 1;
                  end;
               end loop;
               Matches.Replace_Element (J, Key);
            end;
         end loop;

         for M of Matches loop
            if Length (Result) > 0 then
               Append (Result, "; ");
            end if;
            Append (Result, Name (M.C));
            Append (Result, "=");
            Append (Result, Value (M.C));
         end loop;
      end if;

      if Length (Result) > Jar.Limits.Max_Cookie_Header_Length then
         return "";
      else
         return To_String (Result);
      end if;
   end Get_Cookie_Header;

end Http_Client.Cookies;
