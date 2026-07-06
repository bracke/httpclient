with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.Errors;

package body Http_Client.Headers is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Is_Token_Character (C : Character) return Boolean is
   begin
      return
        (C in 'A' .. 'Z') or else
        (C in 'a' .. 'z') or else
        (C in '0' .. '9') or else
        C = '!' or else
        C = '#' or else
        C = '$' or else
        C = '%' or else
        C = '&' or else
        Character'Pos (C) = 39 or else
        C = '*' or else
        C = '+' or else
        C = '-' or else
        C = '.' or else
        C = '^' or else
        C = '_' or else
        C = '`' or else
        C = '|' or else
        C = '~';
   end Is_Token_Character;

   function Empty return Header_List is
      Result : Header_List;
   begin
      return Result;
   end Empty;

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
           or else (Character'Pos (C) >= 128
                    and then Character'Pos (C) <= 159)
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Value;

   function Add
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status
   is
   begin
      if not Is_Valid_Name (Name) or else not Is_Valid_Value (Value) then
         return Invalid_Header;
      end if;

      List.Items.Append
        (Header_Field'(Name  => To_Unbounded_String (Name),
          Key   => To_Unbounded_String (Lower (Name)),
          Value => To_Unbounded_String (Value)));

      return Ok;
   end Add;


   function Is_HTTP2_Pseudo_Name (Name : String) return Boolean is
   begin
      if Name'Length < 2 or else Name (Name'First) /= ':' then
         return False;
      end if;

      for I in Name'First + 1 .. Name'Last loop
         if not Is_Token_Character (Name (I))
           or else Name (I) in 'A' .. 'Z'
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_HTTP2_Pseudo_Name;

   function Add_HTTP2_Pseudo
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status
   is
   begin
      if not Is_HTTP2_Pseudo_Name (Name)
        or else not Is_Valid_Value (Value)
      then
         return Invalid_Header;
      end if;

      List.Items.Append
        (Header_Field'(Name  => To_Unbounded_String (Name),
          Key   => To_Unbounded_String (Lower (Name)),
          Value => To_Unbounded_String (Value)));

      return Ok;
   end Add_HTTP2_Pseudo;


   function Is_Forbidden_HTTP2_Trailer_Name
     (Name : String;
      Response : Boolean := False) return Boolean
   is
      Key : constant String := Lower (Name);
      pragma Unreferenced (Response);
   begin
      if Is_HTTP2_Pseudo_Name (Name)
        or else (Name'Length > 0 and then Name (Name'First) = ':')
      then
         return True;
      end if;

      return Key = "connection"
        or else Key = "keep-alive"
        or else Key = "proxy-connection"
        or else Key = "transfer-encoding"
        or else Key = "upgrade"
        or else Key = "host"
        or else Key = "content-length"
        or else Key = "authorization"
        or else Key = "proxy-authorization"
        or else Key = "cookie"
        or else Key = "set-cookie"
        or else Key = "trailer";
   end Is_Forbidden_HTTP2_Trailer_Name;

   function Validate_HTTP2_Trailers
     (List     : Header_List;
      Response : Boolean := False) return Http_Client.Errors.Result_Status
   is
   begin
      for I in 1 .. Length (List) loop
         declare
            Name  : constant String := Name_At (List, I);
            Value : constant String := Value_At (List, I);
         begin
            if not Is_Valid_Name (Name)
              or else not Is_Valid_Value (Value)
              or else Is_Forbidden_HTTP2_Trailer_Name (Name, Response)
            then
               return Invalid_Header;
            end if;
         end;
      end loop;

      return Ok;
   end Validate_HTTP2_Trailers;

   function Set
     (List  : in out Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status
   is
      New_Field : Header_Field;
      Key       : Unbounded_String;
      Inserted  : Boolean := False;
      I         : Positive;
   begin
      if not Is_Valid_Name (Name) or else not Is_Valid_Value (Value) then
         return Invalid_Header;
      end if;

      Key := To_Unbounded_String (Lower (Name));
      New_Field :=
        (Name  => To_Unbounded_String (Name),
         Key   => Key,
         Value => To_Unbounded_String (Value));

      if List.Items.Is_Empty then
         List.Items.Append (New_Field);
         return Ok;
      end if;

      I := List.Items.First_Index;
      while I <= List.Items.Last_Index loop
         if List.Items (I).Key = Key then
            if not Inserted then
               List.Items.Replace_Element (I, New_Field);
               Inserted := True;
               I := I + 1;
            else
               List.Items.Delete (I);
            end if;
         else
            I := I + 1;
         end if;
      end loop;

      if not Inserted then
         List.Items.Append (New_Field);
      end if;

      return Ok;
   end Set;

   procedure Append
     (List  : in out Header_List;
      Name  : String;
      Value : String)
   is
      Status : constant Result_Status := Add (List, Name, Value);
   begin
      pragma Assert (Status = Ok, "Append precondition should ensure success");
   end Append;

   function Contains
     (List : Header_List;
      Name : String) return Boolean
   is
   begin
      if not Is_Valid_Name (Name)
        and then not Is_HTTP2_Pseudo_Name (Name)
      then
         return False;
      end if;

      declare
         Key : constant Unbounded_String := To_Unbounded_String (Lower (Name));
      begin
         for Field of List.Items loop
            if Field.Key = Key then
               return True;
            end if;
         end loop;
      end;

      return False;
   end Contains;

   function Get
     (List : Header_List;
      Name : String) return String
   is
   begin
      if not Is_Valid_Name (Name)
        and then not Is_HTTP2_Pseudo_Name (Name)
      then
         return "";
      end if;

      declare
         Key : constant Unbounded_String := To_Unbounded_String (Lower (Name));
      begin
         for Field of List.Items loop
            if Field.Key = Key then
               return To_String (Field.Value);
            end if;
         end loop;
      end;

      return "";
   end Get;

   function Count
     (List : Header_List;
      Name : String) return Natural
   is
      Result : Natural := 0;
   begin
      if not Is_Valid_Name (Name)
        and then not Is_HTTP2_Pseudo_Name (Name)
      then
         return 0;
      end if;

      declare
         Key : constant Unbounded_String := To_Unbounded_String (Lower (Name));
      begin
         for Field of List.Items loop
            if Field.Key = Key then
               Result := Result + 1;
            end if;
         end loop;
      end;

      return Result;
   end Count;

   function Remove
     (List : in out Header_List;
      Name : String) return Http_Client.Errors.Result_Status
   is
      I : Positive;
   begin
      if not Is_Valid_Name (Name) then
         return Invalid_Header;
      end if;

      if List.Items.Is_Empty then
         return Ok;
      end if;

      declare
         Key : constant Unbounded_String := To_Unbounded_String (Lower (Name));
      begin
         I := List.Items.First_Index;
         while I <= List.Items.Last_Index loop
            if List.Items (I).Key = Key then
               List.Items.Delete (I);
            else
               I := I + 1;
            end if;
         end loop;
      end;

      return Ok;
   end Remove;

   function Length (List : Header_List) return Natural is
   begin
      return Natural (List.Items.Length);
   end Length;

   procedure Clear (List : in out Header_List) is
   begin
      List.Items.Clear;
   end Clear;

   function Name_At
     (List  : Header_List;
      Index : Positive) return String
   is
   begin
      return To_String (List.Items (Index).Name);
   end Name_At;

   function Value_At
     (List  : Header_List;
      Index : Positive) return String
   is
   begin
      return To_String (List.Items (Index).Value);
   end Value_At;

end Http_Client.Headers;
