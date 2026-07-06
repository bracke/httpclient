with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Http_Client.Crypto;
with Http_Client.Headers;
with Http_Client.Proxies;
with Http_Client.Requests;

package body Http_Client.Auth.Digest is
   use Ada.Characters.Handling;
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;

   Max_Challenge_Length : constant Natural := 8192;
   Max_Parameter_Value_Length : constant Natural := 2048;
   Max_Generated_Header_Length : constant Natural := 8192;

   function Is_Control (C : Character) return Boolean is
      Code : constant Natural := Character'Pos (C);
   begin
      return Code < 32 or else Code = 127 or else (Code >= 128 and then Code <= 159);
   end Is_Control;

   function Header_Safe (Text : String) return Boolean is
   begin
      for C of Text loop
         if Is_Control (C) then
            return False;
         end if;
      end loop;
      return True;
   end Header_Safe;

   function Lower (Text : String) return String is
      Result : String := Text;
   begin
      for I in Result'Range loop
         Result (I) := To_Lower (Result (I));
      end loop;
      return Result;
   end Lower;

   function Trim (Text : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both);
   end Trim;

   function Starts_With_CI (Text, Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Lower (Text (Text'First .. Text'First + Prefix'Length - 1)) = Lower (Prefix);
   end Starts_With_CI;

   function Is_Token_Char (C : Character) return Boolean is
   begin
      return (C in 'A' .. 'Z') or else (C in 'a' .. 'z') or else (C in '0' .. '9')
        or else C = '!' or else C = '#' or else C = '$' or else C = '%'
        or else C = '&' or else C = Character'Val (39) or else C = '*' or else C = '+'
        or else C = '-' or else C = '.' or else C = '^' or else C = '_'
        or else C = '`' or else C = '|' or else C = '~';
   end Is_Token_Char;

   function Parse_Algorithm (Text : String; Algorithm : out Digest_Algorithm)
      return Boolean
   is
      L : constant String := Lower (Text);
   begin
      if L = "md5" then
         Algorithm := Algorithm_MD5;
      elsif L = "md5-sess" then
         Algorithm := Algorithm_MD5_Sess;
      elsif L = "sha-256" then
         Algorithm := Algorithm_SHA_256;
      elsif L = "sha-256-sess" then
         Algorithm := Algorithm_SHA_256_Sess;
      else
         return False;
      end if;
      return True;
   end Parse_Algorithm;

   procedure Mark_QOP (Text : String; Parsed : in out Challenge) is
      Pos   : Natural := Text'First;
      Start : Natural;
      Last  : Natural;
   begin
      while Pos <= Text'Last loop
         while Pos <= Text'Last and then (Text (Pos) = ' ' or else Text (Pos) = ',') loop
            Pos := Pos + 1;
         end loop;
         exit when Pos > Text'Last;
         Start := Pos;
         while Pos <= Text'Last and then Text (Pos) /= ',' loop
            Pos := Pos + 1;
         end loop;
         Last := Pos - 1;
         declare
            Item : constant String := Lower (Trim (Text (Start .. Last)));
         begin
            if Item = "auth" then
               Parsed.Offers_Auth := True;
            elsif Item = "auth-int" then
               Parsed.Offers_Auth_Int := True;
            end if;
         end;
      end loop;
   end Mark_QOP;

   function Parse_Challenge
     (Header_Value : String;
      Parsed       : out Challenge) return Http_Client.Errors.Result_Status
   is
      Text : constant String := Trim (Header_Value);
      Pos  : Natural;
      Seen_Realm     : Boolean := False;
      Seen_Nonce     : Boolean := False;
      Seen_Opaque    : Boolean := False;
      Seen_Algorithm : Boolean := False;
      Seen_QOP       : Boolean := False;
      Seen_Stale     : Boolean := False;
   begin
      Parsed :=
        (Valid           => False,
         Realm           => Null_Unbounded_String,
         Nonce           => Null_Unbounded_String,
         Opaque          => Null_Unbounded_String,
         Algorithm       => Algorithm_MD5,
         Has_Algorithm   => False,
         Offers_Auth     => False,
         Offers_Auth_Int => False,
         Stale           => False);
      if Text'Length = 0 or else Text'Length > Max_Challenge_Length or else not Header_Safe (Text) then
         return Http_Client.Errors.Authentication_Challenge_Malformed;
      end if;
      if Text (Text'Last) = ',' then
         return Http_Client.Errors.Authentication_Challenge_Malformed;
      end if;

      if Starts_With_CI (Text, "Digest") then
         if Text'Length = 6 then
            return Http_Client.Errors.Authentication_Challenge_Malformed;
         end if;
         Pos := Text'First + 6;
         if Text (Pos) /= ' ' then
            return Http_Client.Errors.Authentication_Challenge_Malformed;
         end if;
         while Pos <= Text'Last and then Text (Pos) = ' ' loop
            Pos := Pos + 1;
         end loop;
      else
         Pos := Text'First;
      end if;

      while Pos <= Text'Last loop
         while Pos <= Text'Last and then (Text (Pos) = ' ' or else Text (Pos) = ',') loop
            Pos := Pos + 1;
         end loop;
         exit when Pos > Text'Last;

         declare
            Name_Start : constant Natural := Pos;
         begin
            while Pos <= Text'Last and then Is_Token_Char (Text (Pos)) loop
               Pos := Pos + 1;
            end loop;
            if Pos = Name_Start or else Pos > Text'Last or else Text (Pos) /= '=' then
               return Http_Client.Errors.Authentication_Challenge_Malformed;
            end if;
            declare
               Name : constant String := Lower (Text (Name_Start .. Pos - 1));
               Value : Unbounded_String := Null_Unbounded_String;
            begin
               Pos := Pos + 1;
               if Pos > Text'Last then
                  return Http_Client.Errors.Authentication_Challenge_Malformed;
               end if;

               if Text (Pos) = '"' then
                  declare
                     Closed : Boolean := False;
                  begin
                     Pos := Pos + 1;
                     while Pos <= Text'Last loop
                        if Text (Pos) = '"' then
                           Pos := Pos + 1;
                           Closed := True;
                           exit;
                        elsif Text (Pos) = '\' then
                           Pos := Pos + 1;
                           if Pos > Text'Last or else Is_Control (Text (Pos)) then
                              return Http_Client.Errors.Authentication_Challenge_Malformed;
                           end if;
                           Append (Value, Text (Pos));
                           Pos := Pos + 1;
                        elsif Is_Control (Text (Pos)) then
                           return Http_Client.Errors.Authentication_Challenge_Malformed;
                        else
                           Append (Value, Text (Pos));
                           Pos := Pos + 1;
                        end if;
                     end loop;
                     if not Closed then
                        return Http_Client.Errors.Authentication_Challenge_Malformed;
                     end if;
                  end;
               else
                  declare
                     Start : constant Natural := Pos;
                  begin
                     while Pos <= Text'Last and then Text (Pos) /= ',' and then Text (Pos) /= ' ' loop
                        if not Is_Token_Char (Text (Pos)) then
                           return Http_Client.Errors.Authentication_Challenge_Malformed;
                        end if;
                        Pos := Pos + 1;
                     end loop;
                     if Pos = Start then
                        return Http_Client.Errors.Authentication_Challenge_Malformed;
                     end if;
                     Value := To_Unbounded_String (Text (Start .. Pos - 1));
                  end;
               end if;

               declare
                  V : constant String := To_String (Value);
               begin
                  if V'Length > Max_Parameter_Value_Length then
                     return Http_Client.Errors.Authentication_Challenge_Malformed;
                  end if;

                  if Name = "realm" then
                     if Seen_Realm then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     Parsed.Realm := Value; Seen_Realm := True;
                  elsif Name = "nonce" then
                     if Seen_Nonce then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     Parsed.Nonce := Value; Seen_Nonce := True;
                  elsif Name = "opaque" then
                     if Seen_Opaque then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     Parsed.Opaque := Value; Seen_Opaque := True;
                  elsif Name = "algorithm" then
                     if Seen_Algorithm then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     if not Parse_Algorithm (V, Parsed.Algorithm) then
                        return Http_Client.Errors.Digest_Algorithm_Unsupported;
                     end if;
                     Parsed.Has_Algorithm := True; Seen_Algorithm := True;
                  elsif Name = "qop" then
                     if Seen_QOP then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     Mark_QOP (V, Parsed); Seen_QOP := True;
                  elsif Name = "stale" then
                     if Seen_Stale then return Http_Client.Errors.Authentication_Challenge_Malformed; end if;
                     if Lower (V) = "true" then
                        Parsed.Stale := True;
                     elsif Lower (V) = "false" then
                        Parsed.Stale := False;
                     else
                        return Http_Client.Errors.Authentication_Challenge_Malformed;
                     end if;
                     Seen_Stale := True;
                  end if;
               end;

               while Pos <= Text'Last and then Text (Pos) = ' ' loop
                  Pos := Pos + 1;
               end loop;
               if Pos <= Text'Last then
                  if Text (Pos) /= ',' then
                     return Http_Client.Errors.Authentication_Challenge_Malformed;
                  end if;
                  Pos := Pos + 1;
               end if;
            end;
         end;
      end loop;

      if not Seen_Realm or else not Seen_Nonce then
         return Http_Client.Errors.Authentication_Challenge_Malformed;
      end if;
      if Length (Parsed.Realm) = 0 or else Length (Parsed.Nonce) = 0 then
         return Http_Client.Errors.Authentication_Challenge_Malformed;
      end if;
      if Seen_QOP and then not Parsed.Offers_Auth and then Parsed.Offers_Auth_Int then
         return Http_Client.Errors.Digest_QOP_Unsupported;
      end if;
      if Seen_QOP and then not Parsed.Offers_Auth and then not Parsed.Offers_Auth_Int then
         return Http_Client.Errors.Digest_QOP_Unsupported;
      end if;

      Parsed.Valid := True;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Parsed :=
           (Valid           => False,
            Realm           => Null_Unbounded_String,
            Nonce           => Null_Unbounded_String,
            Opaque          => Null_Unbounded_String,
            Algorithm       => Algorithm_MD5,
            Has_Algorithm   => False,
            Offers_Auth     => False,
            Offers_Auth_Int => False,
            Stale           => False);
         return Http_Client.Errors.Authentication_Challenge_Malformed;
   end Parse_Challenge;

   function Nonce_Count_Text (Value : Positive) return String is
      Hex : constant String := "0123456789abcdef";
      N   : Natural := Value;
      R   : String (1 .. 8) := (others => '0');
   begin
      for I in reverse R'Range loop
         R (I) := Hex ((N mod 16) + 1);
         N := N / 16;
      end loop;
      return R;
   end Nonce_Count_Text;

   function CNonce_From_Octets (Octets : String) return String is
      Hex : constant String := "0123456789abcdef";
   begin
      if Octets'Length = 0 then
         return "";
      end if;

      declare
         R   : String (1 .. Octets'Length * 2);
         P   : Natural := R'First;
         V   : Natural;
      begin
         for C of Octets loop
         V := Character'Pos (C);
         R (P) := Hex ((V / 16) + 1);
         R (P + 1) := Hex ((V mod 16) + 1);
         P := P + 2;
         end loop;
         return R;
      end;
   end CNonce_From_Octets;

   function Generate_CNonce
     (Value       : out Unbounded_String;
      Octet_Count : Positive := 16) return Http_Client.Errors.Result_Status
   is
      Bytes  : Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
   begin
      Value := Null_Unbounded_String;
      Status := Http_Client.Crypto.Random_Bytes (Natural (Octet_Count), Bytes);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Value := To_Unbounded_String (CNonce_From_Octets (To_String (Bytes)));
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Value := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Random_Failed;
   end Generate_CNonce;

   function Hash (Algorithm : Digest_Algorithm; Text : String) return String is
   begin
      case Algorithm is
         when Algorithm_MD5 | Algorithm_MD5_Sess =>
            return Http_Client.Crypto.Digest_MD5_Hex (Text);
         when Algorithm_SHA_256 | Algorithm_SHA_256_Sess =>
            return Http_Client.Crypto.Digest_SHA256_Hex (Text);
      end case;
   end Hash;

   function Algorithm_Name (Algorithm : Digest_Algorithm) return String is
   begin
      case Algorithm is
         when Algorithm_MD5 => return "MD5";
         when Algorithm_MD5_Sess => return "MD5-sess";
         when Algorithm_SHA_256 => return "SHA-256";
         when Algorithm_SHA_256_Sess => return "SHA-256-sess";
      end case;
   end Algorithm_Name;

   function Quote (Text : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
   begin
      for C of Text loop
         if Is_Control (C) then
            return "";
         elsif C = '"' or else C = '\' then
            Append (Result, '\'); Append (Result, C);
         else
            Append (Result, C);
         end if;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Quote;

   function Generate_Response
     (Parsed           : Challenge;
      Username         : String;
      Password         : String;
      Method           : String;
      URI              : String;
      Nonce_Count      : Positive;
      CNonce           : String;
      Header_Value     : out Unbounded_String;
      Allow_Legacy_MD5 : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
      Algorithm    : constant Digest_Algorithm := Parsed.Algorithm;
      Use_QOP      : constant Boolean := Parsed.Offers_Auth;
      Needs_CNonce : constant Boolean := Use_QOP
        or else Algorithm = Algorithm_MD5_Sess
        or else Algorithm = Algorithm_SHA_256_Sess;
      NC           : constant String := Nonce_Count_Text (Nonce_Count);
      HA1_Base  : Unbounded_String;
      HA1       : Unbounded_String;
      HA2       : Unbounded_String;
      Response  : Unbounded_String;
   begin
      Header_Value := Null_Unbounded_String;
      if not Parsed.Valid or else Length (Parsed.Realm) = 0 or else Length (Parsed.Nonce) = 0 then
         return Http_Client.Errors.Authentication_Challenge_Malformed;
      end if;
      if (Algorithm = Algorithm_MD5 or else Algorithm = Algorithm_MD5_Sess) and then not Allow_Legacy_MD5 then
         return Http_Client.Errors.Digest_Algorithm_Unsupported;
      end if;
      if Parsed.Offers_Auth_Int and then not Parsed.Offers_Auth then
         return Http_Client.Errors.Digest_QOP_Unsupported;
      end if;
      if Username'Length = 0 or else URI'Length = 0
        or else (Needs_CNonce and then CNonce'Length = 0)
        or else not Header_Safe (Username) or else not Header_Safe (Password)
        or else not Header_Safe (Method) or else not Header_Safe (URI)
        or else (CNonce'Length > 0 and then not Header_Safe (CNonce))
      then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      HA1_Base := To_Unbounded_String
        (Hash (Algorithm, Username & ":" & To_String (Parsed.Realm) & ":" & Password));
      if Length (HA1_Base) = 0 then
         return Http_Client.Errors.Internal_Error;
      end if;

      if Algorithm = Algorithm_MD5_Sess or else Algorithm = Algorithm_SHA_256_Sess then
         HA1 := To_Unbounded_String
           (Hash (Algorithm, To_String (HA1_Base) & ":" & To_String (Parsed.Nonce) & ":" & CNonce));
      else
         HA1 := HA1_Base;
      end if;
      HA2 := To_Unbounded_String (Hash (Algorithm, Method & ":" & URI));
      if Length (HA1) = 0 or else Length (HA2) = 0 then
         return Http_Client.Errors.Internal_Error;
      end if;

      if Use_QOP then
         Response := To_Unbounded_String
           (Hash (Algorithm,
              To_String (HA1) & ":" & To_String (Parsed.Nonce) & ":" & NC & ":" &
              CNonce & ":auth:" & To_String (HA2)));
      else
         Response := To_Unbounded_String
           (Hash (Algorithm, To_String (HA1) & ":" & To_String (Parsed.Nonce) & ":" & To_String (HA2)));
      end if;
      if Length (Response) = 0 then
         return Http_Client.Errors.Internal_Error;
      end if;

      declare
         U : constant String := Quote (Username);
         R : constant String := Quote (To_String (Parsed.Realm));
         N : constant String := Quote (To_String (Parsed.Nonce));
         P : constant String := Quote (URI);
         C : constant String := (if Needs_CNonce then Quote (CNonce) else "");
      begin
         if U = "" or else R = "" or else N = "" or else P = ""
           or else (Needs_CNonce and then C = "")
         then
            return Http_Client.Errors.Invalid_Credentials;
         end if;
         Header_Value := To_Unbounded_String
           ("Digest username=" & U & ", realm=" & R & ", nonce=" & N &
            ", uri=" & P & ", algorithm=" & Algorithm_Name (Algorithm) &
            ", response=" & Quote (To_String (Response)));
         if Use_QOP then
            Append (Header_Value, ", qop=auth, nc=" & NC & ", cnonce=" & C);
         elsif Needs_CNonce then
            Append (Header_Value, ", cnonce=" & C);
         end if;
         if Length (Parsed.Opaque) > 0 then
            declare
               Opaque_Text : constant String := Quote (To_String (Parsed.Opaque));
            begin
               if Opaque_Text = "" then
                  Header_Value := Null_Unbounded_String;
                  return Http_Client.Errors.Invalid_Credentials;
               end if;
               Append (Header_Value, ", opaque=" & Opaque_Text);
            end;
         end if;
      end;

      if Length (Header_Value) > Max_Generated_Header_Length then
         Header_Value := Null_Unbounded_String;
         return Http_Client.Errors.Invalid_Header;
      end if;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         Header_Value := Null_Unbounded_String;
         return Http_Client.Errors.Internal_Error;
   end Generate_Response;

   function Is_Digest_Value (Value : String) return Boolean is
   begin
      return Value'Length > 7
        and then Starts_With_CI (Value, "Digest ")
        and then Header_Safe (Value);
   end Is_Digest_Value;

   function Generate_Response_For_Request
     (Parsed           : Challenge;
      Request          : Http_Client.Requests.Request;
      Username         : String;
      Password         : String;
      Nonce_Count      : Positive;
      CNonce           : String;
      Header_Value     : out Unbounded_String;
      Allow_Legacy_MD5 : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
   begin
      Header_Value := Null_Unbounded_String;
      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      return Generate_Response
        (Parsed           => Parsed,
         Username         => Username,
         Password         => Password,
         Method           => Http_Client.Requests.Method_Image
                               (Http_Client.Requests.Method (Request)),
         URI              => Http_Client.Requests.Request_Target (Request),
         Nonce_Count      => Nonce_Count,
         CNonce           => CNonce,
         Header_Value     => Header_Value,
         Allow_Legacy_MD5 => Allow_Legacy_MD5);
   exception
      when others =>
         Header_Value := Null_Unbounded_String;
         return Http_Client.Errors.Invalid_Request;
   end Generate_Response_For_Request;

   function Set_Digest_Authorization
     (Request      : Http_Client.Requests.Request;
      Header_Value : String;
      Result       : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Result := Http_Client.Requests.Default_Request;
      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;
      if not Is_Digest_Value (Header_Value) then
         return Http_Client.Errors.Invalid_Header;
      end if;

      Headers := Http_Client.Requests.Headers (Request);
      Status := Http_Client.Headers.Set (Headers, "Authorization", Header_Value);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Create
        (Method    => Http_Client.Requests.Method (Request),
         URI       => Http_Client.Requests.URI (Request),
         Item      => Result,
         Headers   => Headers,
         Payload   => Http_Client.Requests.Payload (Request),
         Auto_Host => False);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Requests.Set_Body (Result, Http_Client.Requests.Request_Body (Request));
   exception
      when others =>
         Result := Http_Client.Requests.Default_Request;
         return Http_Client.Errors.Internal_Error;
   end Set_Digest_Authorization;

   function Set_Digest_Proxy_Authorization
     (Config       : Http_Client.Proxies.Proxy_Config;
      Header_Value : String;
      Result       : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
   begin
      Result := Config;
      if not Is_Digest_Value (Header_Value) then
         return Http_Client.Errors.Invalid_Header;
      end if;
      return Http_Client.Proxies.With_Proxy_Authorization (Config, Header_Value, Result);
   exception
      when others =>
         Result := Config;
         return Http_Client.Errors.Internal_Error;
   end Set_Digest_Proxy_Authorization;

end Http_Client.Auth.Digest;
