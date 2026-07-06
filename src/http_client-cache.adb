with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Types; use Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Cache is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Ada.Containers.Count_Type;
   use type Http_Client.Errors.Result_Status;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Trim (Text : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both);
   end Trim;

   function Floor_Seconds (Value : Duration) return Natural is
      As_Float : Long_Long_Float;
      Rounded  : Long_Long_Integer;
   begin
      if Value <= 0.0 then
         return 0;
      end if;

      As_Float := Long_Long_Float (Value);
      if As_Float >= Long_Long_Float (Natural'Last) then
         return Natural'Last;
      end if;

      Rounded := Long_Long_Integer (As_Float - 0.5);
      if Rounded <= 0 then
         return 0;
      else
         return Natural (Rounded);
      end if;
   exception
      when others =>
         return Natural'Last;
   end Floor_Seconds;

   function Contains_Token (Value : String; Token : String) return Boolean is
      Wanted : constant String := Lower (Token);
      Start  : Positive := Value'First;
      Stop   : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      while Start <= Value'Last loop
         Stop := Start;
         while Stop <= Value'Last and then Value (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part  : constant String :=
              Lower (Trim (Value (Start .. Stop - 1)));
            Delim : Natural := Part'First;
         begin
            while Delim <= Part'Last
              and then Part (Delim) /= ';'
              and then Part (Delim) /= '='
            loop
               Delim := Delim + 1;
            end loop;

            if Trim
                 ((if Delim > Part'First
                   then Part (Part'First .. Delim - 1)
                   else Part))
              = Wanted
            then
               return True;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return False;
   end Contains_Token;

   function Directive_Has_Parameter
     (Value : String; Name : String) return Boolean
   is
      Wanted : constant String := Lower (Name);
      Start  : Positive := Value'First;
      Stop   : Natural;
   begin
      if Value'Length = 0 then
         return False;
      end if;

      while Start <= Value'Last loop
         Stop := Start;
         while Stop <= Value'Last and then Value (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part : constant String := Lower (Trim (Value (Start .. Stop - 1)));
            Eq   : Natural := Part'First;
         begin
            while Eq <= Part'Last and then Part (Eq) /= '=' loop
               Eq := Eq + 1;
            end loop;

            if Eq <= Part'Last
              and then Trim (Part (Part'First .. Eq - 1)) = Wanted
            then
               return True;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return False;
   end Directive_Has_Parameter;

   function Directive_Value
     (Value : String; Name : String; Result : out Natural) return Boolean
   is
      Wanted : constant String := Lower (Name);
      Start  : Positive := Value'First;
      Stop   : Natural;
   begin
      Result := 0;
      if Value'Length = 0 then
         return False;
      end if;

      while Start <= Value'Last loop
         Stop := Start;
         while Stop <= Value'Last and then Value (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part : constant String := Trim (Value (Start .. Stop - 1));
            L    : constant String := Lower (Part);
            Eq   : Natural := L'First;
         begin
            while Eq <= L'Last and then L (Eq) /= '=' loop
               Eq := Eq + 1;
            end loop;

            if Eq <= L'Last and then Trim (L (L'First .. Eq - 1)) = Wanted then
               declare
                  Raw0 : constant String := Trim (Part (Eq + 1 .. Part'Last));
                  Raw  : constant String :=
                    (if Raw0'Length >= 2
                       and then Raw0 (Raw0'First) = '"'
                       and then Raw0 (Raw0'Last) = '"'
                     then Raw0 (Raw0'First + 1 .. Raw0'Last - 1)
                     else Raw0);
               begin
                  if Raw'Length = 0 then
                     return False;
                  end if;

                  for C of Raw loop
                     if C not in '0' .. '9' then
                        return False;
                     end if;
                  end loop;

                  Result := Natural'Value (Raw);
                  return True;
               exception
                  when others =>
                     return False;
               end;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return False;
   end Directive_Value;


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

   function Month_Number (Text : String) return Natural is
      M : constant String := Lower (Text);
   begin
      if M = "jan" then
         return 1;
      end if;
      if M = "feb" then
         return 2;
      end if;
      if M = "mar" then
         return 3;
      end if;
      if M = "apr" then
         return 4;
      end if;
      if M = "may" then
         return 5;
      end if;
      if M = "jun" then
         return 6;
      end if;
      if M = "jul" then
         return 7;
      end if;
      if M = "aug" then
         return 8;
      end if;
      if M = "sep" then
         return 9;
      end if;
      if M = "oct" then
         return 10;
      end if;
      if M = "nov" then
         return 11;
      end if;
      if M = "dec" then
         return 12;
      end if;
      return 0;
   end Month_Number;

   function Parse_HTTP_Date
     (Text : String; Value : out Ada.Calendar.Time) return Boolean
   is
      T : constant String := Trim (Text);
   begin
      Value := Ada.Calendar.Time_Of (1970, 1, 1);

      --  IMF-fixdate only: Sun, 06 Nov 1994 08:49:37 GMT.
      if T'Length /= 29
        or else T (T'First + 3) /= ','
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

      declare
         Day    : Natural := 0;
         Month  : constant Natural :=
           Month_Number (T (T'First + 8 .. T'First + 10));
         Year   : Natural := 0;
         Hour   : Natural := 0;
         Minute : Natural := 0;
         Second : Natural := 0;
      begin
         if not Parse_Natural_Digits (T (T'First + 5 .. T'First + 6), Day)
           or else not Parse_Natural_Digits (T (T'First + 12 .. T'First + 15), Year)
           or else not Parse_Natural_Digits (T (T'First + 17 .. T'First + 18), Hour)
           or else not Parse_Natural_Digits (T (T'First + 20 .. T'First + 21), Minute)
           or else not Parse_Natural_Digits (T (T'First + 23 .. T'First + 24), Second)
           or else Month = 0
           or else Day not in 1 .. 31
           or else Hour > 23
           or else Minute > 59
           or else Second > 59
         then
            return False;
         end if;

         Value :=
           Ada.Calendar.Time_Of
             (Year    => Year,
              Month   => Month,
              Day     => Day,
              Seconds => Duration (Hour * 3600 + Minute * 60 + Second));
         return True;
      end;
   exception
      when others =>
         Value := Ada.Calendar.Time_Of (1970, 1, 1);
         return False;
   end Parse_HTTP_Date;

   function Is_Weak_ETag (ETag : String) return Boolean is
   begin
      return ETag'Length >= 2
        and then (ETag (ETag'First) = 'W' or else ETag (ETag'First) = 'w')
        and then ETag (ETag'First + 1) = '/';
   end Is_Weak_ETag;

   function Cache_Control_Has_Directive
     (Value : String;
      Name  : String) return Boolean is
   begin
      return Contains_Token (Value, Name);
   end Cache_Control_Has_Directive;

   function Cache_Control_Directive_Value
     (Value : String;
      Name  : String) return String
   is
      Wanted : constant String := Lower (Name);
      Start  : Positive := Value'First;
      Stop   : Natural;
   begin
      if Value'Length = 0 then
         return "";
      end if;

      while Start <= Value'Last loop
         Stop := Start;
         while Stop <= Value'Last and then Value (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Part : constant String := Trim (Value (Start .. Stop - 1));
            L    : constant String := Lower (Part);
            Eq   : Natural := L'First;
         begin
            while Eq <= L'Last and then L (Eq) /= '=' loop
               Eq := Eq + 1;
            end loop;

            if Eq <= L'Last and then Trim (L (L'First .. Eq - 1)) = Wanted then
               declare
                  Raw0 : constant String := Trim (Part (Eq + 1 .. Part'Last));
               begin
                  if Raw0'Length >= 2
                    and then Raw0 (Raw0'First) = '"'
                    and then Raw0 (Raw0'Last) = '"'
                  then
                     return Raw0 (Raw0'First + 1 .. Raw0'Last - 1);
                  else
                     return Raw0;
                  end if;
               end;
            end if;
         end;

         Start := Stop + 1;
      end loop;

      return "";
   end Cache_Control_Directive_Value;

   function Freshness_Lifetime_MS
     (Cache_Control     : String;
      Expires           : String;
      Stored_Time       : Ada.Calendar.Time;
      Stored_Time_Known : Boolean;
      Lifetime          : out Natural) return Boolean
   is
      Max_Age_Text : constant String := Cache_Control_Directive_Value (Cache_Control, "max-age");
      Max_Age      : Natural := 0;
      Expires_At   : Ada.Calendar.Time;
      Seconds      : Duration;
   begin
      Lifetime := 0;

      if Max_Age_Text /= "" then
         if not Parse_Natural_Digits (Max_Age_Text, Max_Age) then
            return False;
         elsif Max_Age > Natural'Last / 1_000 then
            Lifetime := Natural'Last;
         else
            Lifetime := Max_Age * 1_000;
         end if;
         return True;
      elsif Expires /= "" and then Stored_Time_Known then
         if not Parse_HTTP_Date (Expires, Expires_At) then
            return False;
         elsif Expires_At <= Stored_Time then
            Lifetime := 0;
         else
            Seconds := Expires_At - Stored_Time;
            if Seconds >= Duration (Natural'Last / 1_000) then
               Lifetime := Natural'Last;
            else
               Lifetime := Natural (Seconds * 1_000.0);
            end if;
         end if;
         return True;
      else
         return False;
      end if;
   exception
      when others =>
         Lifetime := 0;
         return False;
   end Freshness_Lifetime_MS;

   function Is_Fresh
     (Cache_Control     : String;
      Expires           : String;
      Stored_Time       : Ada.Calendar.Time;
      Stored_Time_Known : Boolean;
      Max_Stale_MS      : Natural := 0;
      Now               : Ada.Calendar.Time := Ada.Calendar.Clock) return Boolean
   is
      Lifetime_MS : Natural := 0;
      Age_MS      : Natural := 0;
      Age         : Duration;
      Allowed_MS  : Natural;
   begin
      if Cache_Control_Has_Directive (Cache_Control, "no-cache")
        or else Cache_Control_Has_Directive (Cache_Control, "must-revalidate")
        or else Cache_Control_Has_Directive (Cache_Control, "proxy-revalidate")
        or else not Stored_Time_Known
        or else not Freshness_Lifetime_MS
          (Cache_Control, Expires, Stored_Time, Stored_Time_Known, Lifetime_MS)
      then
         return False;
      end if;

      Age := Now - Stored_Time;
      if Age <= 0.0 then
         Age_MS := 0;
      elsif Age >= Duration (Natural'Last / 1_000) then
         Age_MS := Natural'Last;
      else
         Age_MS := Natural (Age * 1_000.0);
      end if;

      if Lifetime_MS >= Natural'Last - Max_Stale_MS then
         Allowed_MS := Natural'Last;
      else
         Allowed_MS := Lifetime_MS + Max_Stale_MS;
      end if;

      return Age_MS < Allowed_MS;
   exception
      when others =>
         return False;
   end Is_Fresh;

   procedure Add_Conditional_Validators
     (Headers       : in out Http_Client.Headers.Header_List;
      ETag          : String;
      Last_Modified : String)
   is
      Ignored : Http_Client.Errors.Result_Status;
   begin
      if ETag /= "" then
         Ignored := Http_Client.Headers.Set (Headers, "If-None-Match", ETag);
      end if;

      if Last_Modified /= "" then
         Ignored := Http_Client.Headers.Set (Headers, "If-Modified-Since", Last_Modified);
      end if;

      pragma Unreferenced (Ignored);
   end Add_Conditional_Validators;


   function Header_Natural
     (Headers : Http_Client.Headers.Header_List;
      Name    : String;
      Value   : out Natural) return Boolean
   is
      Text : constant String := Trim (Http_Client.Headers.Get (Headers, Name));
   begin
      Value := 0;
      if not Http_Client.Headers.Contains (Headers, Name)
        or else Text'Length = 0
      then
         return False;
      end if;

      return Parse_Natural_Digits (Text, Value);
   end Header_Natural;

   function Initial_Age_Seconds
     (Response : Http_Client.Responses.Response; Now : Ada.Calendar.Time)
      return Natural
   is
      Headers      : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Age_Value    : Natural := 0;
      Header_Age   : Natural := 0;
      Apparent_Age : Natural := 0;
      Date_T       : Ada.Calendar.Time;
   begin
      if Header_Natural (Headers, "Age", Header_Age) then
         Age_Value := Header_Age;
      end if;

      if Http_Client.Headers.Contains (Headers, "Date")
        and then
          Parse_HTTP_Date (Http_Client.Headers.Get (Headers, "Date"), Date_T)
        and then Now > Date_T
      then
         Apparent_Age := Floor_Seconds (Now - Date_T);
      end if;

      if Apparent_Age > Age_Value then
         return Apparent_Age;
      else
         return Age_Value;
      end if;
   exception
      when others =>
         return Age_Value;
   end Initial_Age_Seconds;

   function Fresh_Until_For
     (Response : Http_Client.Responses.Response; Now : Ada.Calendar.Time)
      return Ada.Calendar.Time
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      CC      : constant String :=
        Http_Client.Headers.Get (Headers, "Cache-Control");
      Max_Age : Natural := 0;
      Age     : constant Natural := Initial_Age_Seconds (Response, Now);
      Exp_T   : Ada.Calendar.Time;
   begin
      if Contains_Token (CC, "no-cache") then
         return Now;
      end if;

      if Directive_Value (CC, "max-age", Max_Age) then
         if Age >= Max_Age then
            return Now;
         else
            return Now + Duration (Max_Age - Age);
         end if;
      end if;

      if Http_Client.Headers.Contains (Headers, "Expires")
        and then
          Parse_HTTP_Date (Http_Client.Headers.Get (Headers, "Expires"), Exp_T)
      then
         --  Expires is an absolute HTTP-date. Do not extend freshness by
         --  adding the Date/Expires delta to the local store time: a response
         --  stored after its Date header must still expire at the Expires
         --  timestamp, not at Now + (Expires - Date).
         if Exp_T <= Now then
            return Now;
         else
            return Exp_T;
         end if;
      end if;

      return Now;
   end Fresh_Until_For;

   function Current_Age_Seconds
     (Cache_Item : Cache_Entry; Now : Ada.Calendar.Time) return Natural
   is
      Initial : constant Natural :=
        Initial_Age_Seconds
          (Cache_Item.Stored_Response, Cache_Item.Stored_Time);
      Elapsed : Natural := 0;
   begin
      if Now > Cache_Item.Stored_Time then
         Elapsed := Floor_Seconds (Now - Cache_Item.Stored_Time);
      end if;

      if Natural'Last - Initial < Elapsed then
         return Natural'Last;
      else
         return Initial + Elapsed;
      end if;
   exception
      when others =>
         return Initial;
   end Current_Age_Seconds;

   function Origin_Key (Request : Http_Client.Requests.Request) return String
   is
      U : constant Http_Client.URI.URI_Reference :=
        Http_Client.Requests.URI (Request);
   begin
      if not Http_Client.Requests.Is_Valid (Request)
        or else not Http_Client.URI.Is_Parsed (U)
      then
         return "";
      end if;

      return
        Lower (Http_Client.URI.Scheme (U))
        & "://"
        & Lower (Http_Client.URI.Authority_Host (U))
        & ":"
        & Trim
            (Http_Client.URI.TCP_Port'Image
               (Http_Client.URI.Effective_Port (U)))
        & Http_Client.URI.Request_Target (U);
   end Origin_Key;

   function Has_Request_Body
     (Request : Http_Client.Requests.Request) return Boolean
   is
      Body_Data : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Length    : Natural := 0;
   begin
      --  Requests can carry a legacy buffered Payload value or a request-body streaming
      --  Request_Body descriptor. Both forms are request bodies for cache
      --  policy purposes; a GET with a non-empty payload must not be stored
      --  or served from cache.
      if Http_Client.Requests.Has_Payload (Request) then
         return True;
      end if;

      if Http_Client.Request_Bodies.Declared_Length (Body_Data, Length) then
         return Length > 0;
      end if;

      return Http_Client.Request_Bodies.Has_Body (Body_Data);
   end Has_Request_Body;

   function Has_Explicit_Auth_Permission
     (Headers : Http_Client.Headers.Header_List) return Boolean
   is
      CC : constant String :=
        Http_Client.Headers.Get (Headers, "Cache-Control");
      V  : Natural := 0;
   begin
      return
        Contains_Token (CC, "public")
        or else Contains_Token (CC, "must-revalidate")
        or else Directive_Value (CC, "s-maxage", V);
   end Has_Explicit_Auth_Permission;

   function Vary_Header_Includes
     (Headers : Http_Client.Headers.Header_List; Name : String) return Boolean
   is
      Text   : constant String := Http_Client.Headers.Get (Headers, "Vary");
      Wanted : constant String := Lower (Name);
      Start  : Positive := Text'First;
      Stop   : Natural;
   begin
      if not Http_Client.Headers.Contains (Headers, "Vary")
        or else Text'Length = 0
      then
         return False;
      end if;

      while Start <= Text'Last loop
         Stop := Start;
         while Stop <= Text'Last and then Text (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         if Lower (Trim (Text (Start .. Stop - 1))) = Wanted then
            return True;
         end if;

         Start := Stop + 1;
      end loop;

      return False;
   end Vary_Header_Includes;

   function Entry_Varies_On
     (Cache_Item : Cache_Entry; Name : String) return Boolean
   is
      Wanted : constant String := Lower (Name);
   begin
      for Dim of Cache_Item.Vary loop
         if To_String (Dim.Name) = Wanted then
            return True;
         end if;
      end loop;

      return False;
   end Entry_Varies_On;

   function Request_Header_Present
     (Request : Http_Client.Requests.Request; Name : String) return Boolean is
   begin
      return
        Http_Client.Headers.Contains
          (Http_Client.Requests.Headers (Request), Name);
   end Request_Header_Present;

   function Vary_Has_Duplicate_Field_Names (Text : String) return Boolean is
      Outer_Start : Positive := Text'First;
      Outer_Stop  : Natural;
   begin
      if Text'Length = 0 then
         return False;
      end if;

      while Outer_Start <= Text'Last loop
         Outer_Stop := Outer_Start;
         while Outer_Stop <= Text'Last and then Text (Outer_Stop) /= ',' loop
            Outer_Stop := Outer_Stop + 1;
         end loop;

         declare
            Outer_Name  : constant String :=
              Trim (Text (Outer_Start .. Outer_Stop - 1));
            Outer_Key   : constant String := Lower (Outer_Name);
            Inner_Start : Positive := Outer_Stop + 1;
            Inner_Stop  : Natural;
         begin
            while Inner_Start <= Text'Last loop
               Inner_Stop := Inner_Start;
               while Inner_Stop <= Text'Last and then Text (Inner_Stop) /= ','
               loop
                  Inner_Stop := Inner_Stop + 1;
               end loop;

               declare
                  Inner_Name : constant String :=
                    Trim (Text (Inner_Start .. Inner_Stop - 1));
               begin
                  if Outer_Key /= "" and then Lower (Inner_Name) = Outer_Key
                  then
                     return True;
                  end if;
               end;

               Inner_Start := Inner_Stop + 1;
            end loop;
         end;

         Outer_Start := Outer_Stop + 1;
      end loop;

      return False;
   exception
      when others =>
         return True;
   end Vary_Has_Duplicate_Field_Names;

   function Parse_Vary
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Vary     : in out Vary_Vectors.Vector) return Boolean
   is
      Headers         : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Request_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Text            : constant String :=
        Http_Client.Headers.Get (Headers, "Vary");
      Start           : Positive := Text'First;
      Stop            : Natural;
   begin
      Vary.Clear;
      if not Http_Client.Headers.Contains (Headers, "Vary") then
         return True;
      end if;

      if Text'Length = 0 then
         return True;
      end if;

      if Http_Client.Headers.Count (Headers, "Vary") > 1
        or else Vary_Has_Duplicate_Field_Names (Text)
      then
         Vary.Clear;
         return False;
      end if;

      while Start <= Text'Last loop
         Stop := Start;
         while Stop <= Text'Last and then Text (Stop) /= ',' loop
            Stop := Stop + 1;
         end loop;

         declare
            Name    : constant String := Trim (Text (Start .. Stop - 1));
            Key     : constant String := Lower (Name);
            Present : constant Boolean :=
              Http_Client.Headers.Contains (Request_Headers, Name);
            Value   : constant String :=
              (if Present
               then Http_Client.Headers.Get (Request_Headers, Name)
               else "");
         begin
            if Name = ""
              or else Name = "*"
              or else not Http_Client.Headers.Is_Valid_Name (Name)
            then
               Vary.Clear;
               return False;
            end if;

            for Existing of Vary loop
               if To_String (Existing.Name) = Key then
                  Vary.Clear;
                  return False;
               end if;
            end loop;

            Vary.Append
              (Vary_Dimension'(Name    => To_Unbounded_String (Key),
                Present => Present,
                Value   => To_Unbounded_String (Value)));
         end;

         Start := Stop + 1;
      end loop;

      if Vary.Length > 1 then
         for I in Vary.First_Index .. Vary.Last_Index loop
            for J in I + 1 .. Vary.Last_Index loop
               if To_String (Vary (J).Name) < To_String (Vary (I).Name) then
                  declare
                     Temp : constant Vary_Dimension := Vary (I);
                  begin
                     Vary.Replace_Element (I, Vary (J));
                     Vary.Replace_Element (J, Temp);
                  end;
               end if;
            end loop;
         end loop;
      end if;

      return True;
   end Parse_Vary;

   function Vary_Matches
     (Cache_Item : Cache_Entry; Request : Http_Client.Requests.Request)
      return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
   begin
      for Dim of Cache_Item.Vary loop
         declare
            Name    : constant String := To_String (Dim.Name);
            Present : constant Boolean :=
              Http_Client.Headers.Contains (Headers, Name);
         begin
            if Present /= Dim.Present then
               return False;
            end if;

            if Present
              and then
                Http_Client.Headers.Get (Headers, Name)
                /= To_String (Dim.Value)
            then
               return False;
            end if;
         end;
      end loop;

      return True;
   end Vary_Matches;

   function Equivalent_Entry
     (Cache_Item : Cache_Entry; Key : String; Vary : Vary_Vectors.Vector)
      return Boolean is
   begin
      if To_String (Cache_Item.Key) /= Key
        or else Cache_Item.Vary.Length /= Vary.Length
      then
         return False;
      end if;

      for I in 1 .. Natural (Vary.Length) loop
         if To_String (Cache_Item.Vary (I).Name) /= To_String (Vary (I).Name)
           or else Cache_Item.Vary (I).Present /= Vary (I).Present
           or else
             To_String (Cache_Item.Vary (I).Value)
             /= To_String (Vary (I).Value)
         then
            return False;
         end if;
      end loop;

      return True;
   end Equivalent_Entry;

   function Validate
     (Config : Cache_Config) return Http_Client.Errors.Result_Status is
   begin
      if Config.Max_Single_Response_Bytes > Config.Max_Total_Body_Bytes
        and then Config.Max_Total_Body_Bytes > 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      return Http_Client.Errors.Ok;
   end Validate;

   procedure Initialize
     (Cache  : in out Cache_Store;
      Config : Cache_Config := Default_Cache_Config) is
   begin
      Cache.Config := Config;
      Clear (Cache);
   end Initialize;

   procedure Clear (Cache : in out Cache_Store) is
   begin
      Cache.Entries.Clear;
      Cache.Total_Bytes := 0;
   end Clear;

   function Length (Cache : Cache_Store) return Natural is
   begin
      return Natural (Cache.Entries.Length);
   end Length;

   function Stored_Body_Bytes (Cache : Cache_Store) return Natural is
   begin
      return Cache.Total_Bytes;
   end Stored_Body_Bytes;

   procedure Invalidate
     (Cache : in out Cache_Store; Request : Http_Client.Requests.Request)
   is
      Key : constant String := Origin_Key (Request);
      I   : Positive;
   begin
      if Key = "" or else Cache.Entries.Is_Empty then
         return;
      end if;

      I := Cache.Entries.First_Index;
      while I <= Cache.Entries.Last_Index loop
         if To_String (Cache.Entries (I).Key) = Key then
            Cache.Total_Bytes :=
              Cache.Total_Bytes - Cache.Entries (I).Body_Bytes;
            Cache.Entries.Delete (I);
         else
            I := I + 1;
         end if;
      end loop;
   exception
      when others =>
         null;
   end Invalidate;

   function May_Store
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Config   : Cache_Config := Default_Cache_Config) return Boolean
   is
      Req_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Res_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Req_CC      : constant String :=
        Http_Client.Headers.Get (Req_Headers, "Cache-Control");
      Res_CC      : constant String :=
        Http_Client.Headers.Get (Res_Headers, "Cache-Control");
      Ignored_Vary : Vary_Vectors.Vector;
   begin
      if not Config.Enabled or else not Http_Client.Requests.Is_Valid (Request)
      then
         return False;
      end if;

      if Http_Client.Requests.Method (Request) /= Http_Client.Types.GET then
         return False;
      end if;

      if Has_Request_Body (Request) then
         return False;
      end if;

      if Http_Client.Responses.Status_Code (Response) /= 200 then
         --  The cache deliberately stores ordinary complete 200 OK GET
         --  representations only. This avoids incorrect treatment of 206
         --  Partial Content, 204/205 no-body responses, and other successful
         --  status codes whose caching semantics need additional method/status
         --  handling beyond this foundation layer.
         return False;
      end if;

      if Http_Client.Headers.Contains (Res_Headers, "Content-Range") then
         --  A complete cached representation must not be populated from
         --  partial-content metadata.
         return False;
      end if;

      if Contains_Token (Req_CC, "no-store")
        or else Contains_Token (Res_CC, "no-store")
      then
         return False;
      end if;

      if Http_Client.Headers.Contains (Req_Headers, "Authorization") then
         if not Config.Allow_Authenticated_Store
           or else not Has_Explicit_Auth_Permission (Res_Headers)
           or else not Vary_Header_Includes (Res_Headers, "Authorization")
         then
            return False;
         end if;
      end if;

      if Http_Client.Headers.Contains (Req_Headers, "Cookie") then
         return False;
      end if;

      if Http_Client.Headers.Contains (Res_Headers, "Set-Cookie")
        and then not Config.Allow_Set_Cookie_Store
      then
         return False;
      end if;

      if Http_Client.Headers.Contains (Res_Headers, "Content-Encoding") then
         --  The cache avoids storing when callers may have mixed decoded and
         --  encoded representation semantics. A later representation-aware
         --  path can store encoded wire bytes explicitly.
         return False;
      end if;

      return Parse_Vary (Request, Response, Ignored_Vary);
   end May_Store;

   function May_Store_With_Client_Certificate
     (Using_Client_Certificate : Boolean;
      Request                  : Http_Client.Requests.Request;
      Response                 : Http_Client.Responses.Response;
      Config                   : Cache_Config := Default_Cache_Config)
      return Boolean
   is
      Res_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
   begin
      if Using_Client_Certificate then
         if not Config.Allow_Authenticated_Store
           or else not Has_Explicit_Auth_Permission (Res_Headers)
         then
            return False;
         end if;
      end if;

      return May_Store (Request, Response, Config);
   end May_Store_With_Client_Certificate;

   procedure Evict_As_Needed (Cache : in out Cache_Store) is
      Oldest_Index : Positive;
      Oldest_Time  : Ada.Calendar.Time;
   begin
      while Natural (Cache.Entries.Length) > Cache.Config.Max_Entries
        or else Cache.Total_Bytes > Cache.Config.Max_Total_Body_Bytes
      loop
         exit when Cache.Entries.Is_Empty;
         Oldest_Index := Cache.Entries.First_Index;
         Oldest_Time := Cache.Entries (Oldest_Index).Last_Used;

         for I in Cache.Entries.First_Index .. Cache.Entries.Last_Index loop
            if Cache.Entries (I).Last_Used < Oldest_Time then
               Oldest_Index := I;
               Oldest_Time := Cache.Entries (I).Last_Used;
            end if;
         end loop;

         Cache.Total_Bytes :=
           Cache.Total_Bytes - Cache.Entries (Oldest_Index).Body_Bytes;
         Cache.Entries.Delete (Oldest_Index);
      end loop;
   end Evict_As_Needed;

   procedure Configure (Cache : in out Cache_Store; Config : Cache_Config) is
   begin
      Cache.Config := Config;
      Evict_As_Needed (Cache);
   end Configure;

   function Store
     (Cache    : in out Cache_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Key         : constant String := Origin_Key (Request);
      Body_Length : constant Natural :=
        Http_Client.Responses.Response_Body (Response)'Length;
      Vary        : Vary_Vectors.Vector;
      Cache_Item  : Cache_Entry;
   begin
      if not Cache.Config.Enabled
        or else Cache.Config.Max_Entries = 0
        or else Cache.Config.Max_Total_Body_Bytes = 0
      then
         return Http_Client.Errors.Cache_Disabled;
      end if;

      if not May_Store (Request, Response, Cache.Config) then
         return Http_Client.Errors.Cache_Disabled;
      end if;

      if Body_Length > Cache.Config.Max_Single_Response_Bytes
        or else Body_Length > Cache.Config.Max_Total_Body_Bytes
      then
         return Http_Client.Errors.Cache_Entry_Too_Large;
      end if;

      if Key = "" or else not Parse_Vary (Request, Response, Vary) then
         return Http_Client.Errors.Invalid_Cache_Metadata;
      end if;

      if not Cache.Entries.Is_Empty then
         for I in Cache.Entries.First_Index .. Cache.Entries.Last_Index loop
            if Equivalent_Entry (Cache.Entries (I), Key, Vary) then
               Cache.Total_Bytes :=
                 Cache.Total_Bytes - Cache.Entries (I).Body_Bytes;
               Cache.Entries.Delete (I);
               exit;
            end if;
         end loop;
      end if;

      Cache_Item :=
        (Key                => To_Unbounded_String (Key),
         Vary               => Vary,
         Stored_Response    => Response,
         Body_Bytes         => Body_Length,
         Stored_Time        => Now,
         Fresh_Until        => Fresh_Until_For (Response, Now),
         Last_Used          => Now,
         Revalidation_Count => 0);

      Cache.Entries.Append (Cache_Item);
      Cache.Total_Bytes := Cache.Total_Bytes + Body_Length;
      Evict_As_Needed (Cache);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Store;

   function Lookup
     (Cache    : in out Cache_Store;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Metadata : out Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Key : constant String := Origin_Key (Request);
   begin
      Response := Http_Client.Responses.Default_Response;
      Metadata :=
        (Source             => Cache_Bypassed,
         Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
         Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
         Age_Seconds        => 0,
         Revalidation_Count => 0,
         Entry_Count        => Length (Cache),
         Stored_Body_Bytes  => Cache.Total_Bytes);

      if not Cache.Config.Enabled then
         return Http_Client.Errors.Cache_Disabled;
      end if;

      if Key = "" then
         return Http_Client.Errors.Cache_Miss;
      end if;

      if Http_Client.Requests.Method (Request) /= Http_Client.Types.GET
        or else Has_Request_Body (Request)
      then
         return Http_Client.Errors.Cache_Miss;
      end if;

      declare
         Req_Headers : constant Http_Client.Headers.Header_List :=
           Http_Client.Requests.Headers (Request);
         Req_CC      : constant String :=
           Http_Client.Headers.Get (Req_Headers, "Cache-Control");
      begin
         if Contains_Token (Req_CC, "no-store") then
            return Http_Client.Errors.Cache_Disabled;
         end if;

         if Http_Client.Headers.Contains (Req_Headers, "Authorization")
           and then not Cache.Config.Allow_Authenticated_Store
         then
            return Http_Client.Errors.Cache_Miss;
         end if;

         if Http_Client.Headers.Contains (Req_Headers, "Cookie") then
            return Http_Client.Errors.Cache_Miss;
         end if;
      end;

      if not Cache.Entries.Is_Empty then
         for I in Cache.Entries.First_Index .. Cache.Entries.Last_Index loop
            if To_String (Cache.Entries (I).Key) = Key
              and then Vary_Matches (Cache.Entries (I), Request)
              and then
                (not Request_Header_Present (Request, "Authorization")
                 or else Entry_Varies_On (Cache.Entries (I), "Authorization"))
            then
               declare
                  Cache_Item : Cache_Entry := Cache.Entries (I);
                  Age        : Natural := 0;
               begin
                  Age := Current_Age_Seconds (Cache_Item, Now);

                  Cache_Item.Last_Used := Now;
                  Cache.Entries.Replace_Element (I, Cache_Item);
                  Response := Cache_Item.Stored_Response;
                  Metadata :=
                    (Source             =>
                       (if Now < Cache_Item.Fresh_Until
                        then From_Fresh_Cache
                        else From_Stale_Cache),
                     Stored_Time        => Cache_Item.Stored_Time,
                     Fresh_Until        => Cache_Item.Fresh_Until,
                     Age_Seconds        => Age,
                     Revalidation_Count => Cache_Item.Revalidation_Count,
                     Entry_Count        => Length (Cache),
                     Stored_Body_Bytes  => Cache.Total_Bytes);

                  declare
                     Req_Headers            :
                       constant Http_Client.Headers.Header_List :=
                         Http_Client.Requests.Headers (Request);
                     Req_CC                 : constant String :=
                       Http_Client.Headers.Get (Req_Headers, "Cache-Control");
                     Req_Max_Age            : Natural := 0;
                     Req_Min_Fresh          : Natural := 0;
                     Req_Max_Stale          : Natural := 0;
                     Remaining              : Natural := 0;
                     Stale_Delta            : Natural := 0;
                     Request_Requires_Stale : Boolean := False;
                     May_Return_Stale       : Boolean := False;
                  begin
                     if Contains_Token (Req_CC, "no-cache") then
                        Request_Requires_Stale := True;
                     elsif Directive_Value (Req_CC, "max-age", Req_Max_Age)
                     then
                        Request_Requires_Stale :=
                          Req_Max_Age = 0 or else Age > Req_Max_Age;
                     end if;

                     if not Request_Requires_Stale
                       and then
                         Directive_Value (Req_CC, "min-fresh", Req_Min_Fresh)
                     then
                        if Cache_Item.Fresh_Until > Now then
                           Remaining :=
                             Floor_Seconds (Cache_Item.Fresh_Until - Now);
                        else
                           Remaining := 0;
                        end if;

                        Request_Requires_Stale := Remaining < Req_Min_Fresh;
                     end if;

                     if Now < Cache_Item.Fresh_Until
                       and then not Request_Requires_Stale
                     then
                        return Http_Client.Errors.Ok;
                     end if;

                     if Cache_Item.Fresh_Until < Now then
                        Stale_Delta :=
                          Floor_Seconds (Now - Cache_Item.Fresh_Until);
                     else
                        Stale_Delta := 0;
                     end if;

                     if Contains_Token (Req_CC, "max-stale") then
                        declare
                           Res_Headers :
                             constant Http_Client.Headers.Header_List :=
                               Http_Client.Responses.Headers
                                 (Cache_Item.Stored_Response);
                           Res_CC      : constant String :=
                             Http_Client.Headers.Get
                               (Res_Headers, "Cache-Control");
                           Has_Value   : constant Boolean :=
                             Directive_Has_Parameter (Req_CC, "max-stale");
                           Valid_Value : constant Boolean :=
                             Directive_Value
                               (Req_CC, "max-stale", Req_Max_Stale);
                        begin
                           May_Return_Stale :=
                             not Contains_Token (Res_CC, "must-revalidate")
                             and then
                               not Contains_Token (Res_CC, "proxy-revalidate")
                             and then Has_Value
                             and then Valid_Value
                             and then Stale_Delta <= Req_Max_Stale;
                        end;
                     end if;

                     Metadata.Source := From_Stale_Cache;
                     if May_Return_Stale and then not Request_Requires_Stale
                     then
                        return Http_Client.Errors.Ok;
                     else
                        return Http_Client.Errors.Cache_Entry_Stale;
                     end if;
                  end;
               end;
            end if;
         end loop;
      end if;

      return Http_Client.Errors.Cache_Miss;
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         return Http_Client.Errors.Internal_Error;
   end Lookup;

   function Prepare_Conditional_Request
     (Original : Http_Client.Requests.Request;
      Cached   : Http_Client.Responses.Response;
      Result   : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers        : Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Original);
      Cached_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Cached);
      Status         : Http_Client.Errors.Result_Status;
   begin
      Result := Http_Client.Requests.Default_Request;

      if Http_Client.Headers.Contains (Cached_Headers, "ETag") then
         Status :=
           Http_Client.Headers.Set
             (Headers,
              "If-None-Match",
              Http_Client.Headers.Get (Cached_Headers, "ETag"));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if Http_Client.Headers.Contains (Cached_Headers, "Last-Modified") then
         Status :=
           Http_Client.Headers.Set
             (Headers,
              "If-Modified-Since",
              Http_Client.Headers.Get (Cached_Headers, "Last-Modified"));
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      end if;

      if not Http_Client.Headers.Contains (Headers, "If-None-Match")
        and then
          not Http_Client.Headers.Contains (Headers, "If-Modified-Since")
      then
         return Http_Client.Errors.Cache_Entry_Stale;
      end if;

      Status :=
        Http_Client.Requests.Create
          (Method    => Http_Client.Requests.Method (Original),
           URI       => Http_Client.Requests.URI (Original),
           Item      => Result,
           Headers   => Headers,
           Payload   => Http_Client.Requests.Payload (Original),
           Auto_Host => False);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return
        Http_Client.Requests.Set_Body
          (Result, Http_Client.Requests.Request_Body (Original));
   exception
      when others =>
         Result := Http_Client.Requests.Default_Request;
         return Http_Client.Errors.Internal_Error;
   end Prepare_Conditional_Request;

   function Header_Is_304_Metadata (Name : String) return Boolean is
      Key : constant String := Lower (Name);
   begin
      return
        Key = "cache-control"
        or else Key = "expires"
        or else Key = "date"
        or else Key = "etag"
        or else Key = "last-modified"
        or else Key = "vary"
        or else Key = "age";
   end Header_Is_304_Metadata;

   function Malformed_304_Response
     (Response : Http_Client.Responses.Response) return Boolean
   is
      Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      CL_Text : constant String :=
        Trim (Http_Client.Headers.Get (Headers, "Content-Length"));
      CL      : Natural := 0;
   begin
      if Http_Client.Responses.Response_Body (Response)'Length /= 0 then
         return True;
      end if;

      if Http_Client.Headers.Contains (Headers, "Transfer-Encoding") then
         return True;
      end if;

      if Http_Client.Headers.Contains (Headers, "Content-Length") then
         if CL_Text'Length = 0 then
            return True;
         end if;

         for C of CL_Text loop
            if C not in '0' .. '9' then
               return True;
            end if;
         end loop;

         CL := Natural'Value (CL_Text);
         return CL /= 0;
      end if;

      return False;
   exception
      when others =>
         return True;
   end Malformed_304_Response;

   function Merge_304_Metadata
     (Stored       : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response)
      return Http_Client.Responses.Response
   is
      Stored_Headers : Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Stored);
      Update_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Not_Modified);
      Status         : Http_Client.Errors.Result_Status;
   begin
      for I in 1 .. Http_Client.Headers.Length (Update_Headers) loop
         declare
            Name  : constant String :=
              Http_Client.Headers.Name_At (Update_Headers, I);
            Value : constant String :=
              Http_Client.Headers.Value_At (Update_Headers, I);
         begin
            if Header_Is_304_Metadata (Name) then
               Status := Http_Client.Headers.Set (Stored_Headers, Name, Value);
               if Status /= Http_Client.Errors.Ok then
                  return Stored;
               end if;
            end if;
         end;
      end loop;

      return Http_Client.Responses.Copy_With_Headers (Stored, Stored_Headers);
   end Merge_304_Metadata;

   function Update_From_304
     (Cache    : in out Cache_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Metadata : out Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Key : constant String := Origin_Key (Request);
   begin
      Metadata :=
        (Source             => Cache_Bypassed,
         Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
         Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
         Age_Seconds        => 0,
         Revalidation_Count => 0,
         Entry_Count        => Length (Cache),
         Stored_Body_Bytes  => Cache.Total_Bytes);

      if Http_Client.Responses.Status_Code (Response) /= 304
        or else Malformed_304_Response (Response)
      then
         return Http_Client.Errors.Protocol_Error;
      end if;

      if not Cache.Entries.Is_Empty then
         for I in Cache.Entries.First_Index .. Cache.Entries.Last_Index loop
            if To_String (Cache.Entries (I).Key) = Key
              and then Vary_Matches (Cache.Entries (I), Request)
              and then
                (not Request_Header_Present (Request, "Authorization")
                 or else Entry_Varies_On (Cache.Entries (I), "Authorization"))
            then
               declare
                  Cache_Item : Cache_Entry := Cache.Entries (I);
               begin
                  Cache_Item.Stored_Response :=
                    Merge_304_Metadata
                      (Stored       => Cache_Item.Stored_Response,
                       Not_Modified => Response);

                  if not May_Store
                           (Request, Cache_Item.Stored_Response, Cache.Config)
                  then
                     Cache.Total_Bytes :=
                       Cache.Total_Bytes - Cache_Item.Body_Bytes;
                     Cache.Entries.Delete (I);
                     Metadata.Entry_Count := Length (Cache);
                     Metadata.Stored_Body_Bytes := Cache.Total_Bytes;
                     return Http_Client.Errors.Invalid_Cache_Metadata;
                  end if;

                  declare
                     Updated_Vary : Vary_Vectors.Vector;
                  begin
                     if not Parse_Vary
                              (Request,
                               Cache_Item.Stored_Response,
                               Updated_Vary)
                     then
                        Cache.Total_Bytes :=
                          Cache.Total_Bytes - Cache_Item.Body_Bytes;
                        Cache.Entries.Delete (I);
                        Metadata.Entry_Count := Length (Cache);
                        Metadata.Stored_Body_Bytes := Cache.Total_Bytes;
                        return Http_Client.Errors.Invalid_Cache_Metadata;
                     end if;

                     Cache_Item.Vary := Updated_Vary;
                  end;

                  Cache_Item.Stored_Time := Now;
                  Cache_Item.Fresh_Until :=
                    Fresh_Until_For (Cache_Item.Stored_Response, Now);
                  Cache_Item.Last_Used := Now;
                  Cache_Item.Revalidation_Count :=
                    Cache_Item.Revalidation_Count + 1;

                  --  A 304 response is allowed to update Vary metadata. If the
                  --  updated dimensions make this entry equivalent to another
                  --  retained variant, collapse the duplicate deterministically
                  --  and keep the just-revalidated entry. This preserves cache
                  --  key uniqueness after metadata refreshes.
                  declare
                     Target_Index : Positive := I;
                     Scan_Index   : Positive := Cache.Entries.First_Index;
                  begin
                     while Scan_Index <= Cache.Entries.Last_Index loop
                        if Scan_Index /= Target_Index
                          and then
                            Equivalent_Entry
                              (Cache.Entries (Scan_Index),
                               Key,
                               Cache_Item.Vary)
                        then
                           Cache.Total_Bytes :=
                             Cache.Total_Bytes
                             - Cache.Entries (Scan_Index).Body_Bytes;
                           Cache.Entries.Delete (Scan_Index);

                           if Scan_Index < Target_Index then
                              Target_Index := Target_Index - 1;
                           end if;
                        else
                           Scan_Index := Scan_Index + 1;
                        end if;
                     end loop;

                     Cache.Entries.Replace_Element (Target_Index, Cache_Item);
                  end;

                  Metadata :=
                    (Source             => From_Revalidated_Cache,
                     Stored_Time        => Cache_Item.Stored_Time,
                     Fresh_Until        => Cache_Item.Fresh_Until,
                     Age_Seconds        =>
                       Current_Age_Seconds (Cache_Item, Now),
                     Revalidation_Count => Cache_Item.Revalidation_Count,
                     Entry_Count        => Length (Cache),
                     Stored_Body_Bytes  => Cache.Total_Bytes);
                  return Http_Client.Errors.Ok;
               end;
            end if;
         end loop;
      end if;

      return Http_Client.Errors.Cache_Miss;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Update_From_304;

end Http_Client.Cache;
