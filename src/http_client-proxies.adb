with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.URI;

package body Http_Client.Proxies is
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;

   function Contains_Userinfo (Text : String) return Boolean is
      Scheme_End : Natural := 0;
      Authority_Start : Natural := 0;
   begin
      for I in Text'Range loop
         if Text (I) = ':' then
            Scheme_End := I;
            exit;
         elsif Text (I) = '/' or else Text (I) = '?' or else Text (I) = '#' then
            return False;
         end if;
      end loop;

      if Scheme_End = 0 or else Scheme_End + 2 > Text'Last then
         return False;
      end if;

      if Text (Scheme_End + 1) /= '/' or else Text (Scheme_End + 2) /= '/' then
         return False;
      end if;

      Authority_Start := Scheme_End + 3;

      for I in Authority_Start .. Text'Last loop
         exit when Text (I) = '/' or else Text (I) = '?' or else Text (I) = '#';
         if Text (I) = '@' then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Userinfo;

   function Credential_Is_Valid (Text : String) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > 255 then
         return False;
      end if;

      for Ch of Text loop
         if Character'Pos (Ch) < 32 or else Character'Pos (Ch) = 127 then
            return False;
         end if;
      end loop;

      return True;
   end Credential_Is_Valid;

   function Extract_Scheme (Text : String) return String is
   begin
      for I in Text'Range loop
         if Text (I) = ':' then
            return Text (Text'First .. I - 1);
         elsif Text (I) = '/' or else Text (I) = '?' or else Text (I) = '#' then
            return "";
         end if;
      end loop;
      return "";
   end Extract_Scheme;

   function Parse_SOCKS5
     (Text     : String;
      DNS_Mode : SOCKS5_DNS_Mode;
      Item     : out Proxy_Config) return Http_Client.Errors.Result_Status
   is
      Scheme_End : Natural := 0;
      Authority_First : Natural := 0;
      Authority_Last  : Natural := 0;
      Host_First      : Natural := 0;
      Host_Last       : Natural := 0;
      Port_Value      : Natural := 1080;
      Has_Port        : Boolean := False;
      Parsed          : Http_Client.URI.URI_Reference;
      Status          : Http_Client.Errors.Result_Status;
   begin
      Item := No_Proxy_Config;

      if Contains_Userinfo (Text) then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      for I in Text'Range loop
         if Text (I) = ':' then
            Scheme_End := I;
            exit;
         end if;
      end loop;

      if Scheme_End = 0
        or else Scheme_End + 2 > Text'Last
        or else Text (Scheme_End + 1) /= '/'
        or else Text (Scheme_End + 2) /= '/'
      then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      Authority_First := Scheme_End + 3;
      Authority_Last := Text'Last;

      for I in Authority_First .. Text'Last loop
         if Text (I) = '/' then
            Authority_Last := I - 1;
            if I /= Text'Last then
               return Http_Client.Errors.Invalid_SOCKS_Proxy;
            end if;
            exit;
         elsif Text (I) = '?' or else Text (I) = '#' then
            return Http_Client.Errors.Invalid_SOCKS_Proxy;
         end if;
      end loop;

      if Authority_Last < Authority_First then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      Host_First := Authority_First;
      Host_Last := Authority_Last;

      for I in reverse Authority_First .. Authority_Last loop
         if Text (I) = ':' then
            Host_Last := I - 1;
            Has_Port := True;
            if I = Authority_Last then
               return Http_Client.Errors.Invalid_SOCKS_Proxy;
            end if;

            Port_Value := 0;
            for J in I + 1 .. Authority_Last loop
               if Text (J) not in '0' .. '9' then
                  return Http_Client.Errors.Invalid_SOCKS_Proxy;
               end if;
               Port_Value := Port_Value * 10 +
                 Character'Pos (Text (J)) - Character'Pos ('0');
               if Port_Value > 65_535 then
                  return Http_Client.Errors.Invalid_SOCKS_Proxy;
               end if;
            end loop;
            exit;
         end if;
      end loop;

      if Host_Last < Host_First or else Port_Value = 0 then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      declare
         Port_Image : constant String := Natural'Image (Port_Value);
         Fixed      : constant String :=
           "http://" & Text (Host_First .. Host_Last) & ":" &
           Port_Image (Port_Image'First + 1 .. Port_Image'Last);
      begin
         Status := Http_Client.URI.Parse (Fixed, Parsed);
      end;

      if Status /= Http_Client.Errors.Ok then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      Item :=
        (Mode       => SOCKS5_Proxy,
         Proxy_Host => To_Unbounded_String (Http_Client.URI.Host (Parsed)),
         Proxy_Port => Http_Client.URI.TCP_Port (Port_Value),
         Has_Auth   => False,
         Auth_Value => Null_Unbounded_String,
         SOCKS_Auth => SOCKS5_No_Authentication,
         SOCKS_DNS  => DNS_Mode,
         SOCKS_User => Null_Unbounded_String,
         SOCKS_Pass => Null_Unbounded_String);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Item := No_Proxy_Config;
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
   end Parse_SOCKS5;

   function Parse
     (Text : String;
      Item : out Proxy_Config) return Http_Client.Errors.Result_Status
   is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
      Scheme : constant String := Ada.Characters.Handling.To_Lower (Extract_Scheme (Text));
   begin
      Item := No_Proxy_Config;

      if Scheme = "socks5" then
         return Parse_SOCKS5 (Text, SOCKS5_Remote_DNS, Item);
      elsif Scheme = "socks5h" then
         return Parse_SOCKS5 (Text, SOCKS5_Remote_DNS, Item);
      elsif Scheme = "socks4" or else Scheme = "socks4a" then
         return Http_Client.Errors.Proxy_Unsupported;
      end if;

      if Contains_Userinfo (Text) then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      Status := Http_Client.URI.Parse (Text, URI);

      if Status = Http_Client.Errors.Unsupported_Feature then
         return Http_Client.Errors.Proxy_Unsupported;
      elsif Status /= Http_Client.Errors.Ok then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      if Http_Client.URI.Scheme (URI) /= "http" then
         return Http_Client.Errors.Proxy_Unsupported;
      end if;

      if Http_Client.URI.Has_Query (URI)
        or else Http_Client.URI.Has_Fragment (URI)
        or else Http_Client.URI.Path (URI) /= "/"
      then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      Item :=
        (Mode       => HTTP_Proxy,
         Proxy_Host => To_Unbounded_String (Http_Client.URI.Host (URI)),
         Proxy_Port => Http_Client.URI.Effective_Port (URI),
         Has_Auth   => False,
         Auth_Value => Null_Unbounded_String,
         SOCKS_Auth => SOCKS5_No_Authentication,
         SOCKS_DNS  => SOCKS5_Remote_DNS,
         SOCKS_User => Null_Unbounded_String,
         SOCKS_Pass => Null_Unbounded_String);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Item := No_Proxy_Config;
         return Http_Client.Errors.Invalid_Proxy;
   end Parse;

   function HTTP
     (Host : String;
      Port : Http_Client.URI.TCP_Port := 80)
      return Proxy_Config
   is
      Item   : Proxy_Config;
      Status : Http_Client.Errors.Result_Status;
      Port_Image : constant String := Natural'Image (Natural (Port));
   begin
      Status := Parse
        ("http://" & Host & ":" &
         Port_Image (Port_Image'First + 1 .. Port_Image'Last),
         Item);

      if Status = Http_Client.Errors.Ok then
         return Item;
      else
         return No_Proxy_Config;
      end if;
   end HTTP;

   function SOCKS5
     (Host      : String;
      Port      : Http_Client.URI.TCP_Port := 1080;
      DNS_Mode  : SOCKS5_DNS_Mode := SOCKS5_Remote_DNS)
      return Proxy_Config
   is
      Item   : Proxy_Config;
      Status : Http_Client.Errors.Result_Status;
      Port_Image : constant String := Natural'Image (Natural (Port));
   begin
      Status := Parse_SOCKS5
        ("socks5://" & Host & ":" &
         Port_Image (Port_Image'First + 1 .. Port_Image'Last),
         DNS_Mode,
         Item);

      if Status = Http_Client.Errors.Ok then
         return Item;
      else
         return No_Proxy_Config;
      end if;
   end SOCKS5;

   function With_Proxy_Authorization
     (Config : Proxy_Config;
      Value  : String;
      Item   : out Proxy_Config) return Http_Client.Errors.Result_Status
   is
   begin
      Item := Config;

      if Config.Mode /= HTTP_Proxy then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      if Value'Length = 0
        or else not Http_Client.Headers.Is_Valid_Value (Value)
      then
         return Http_Client.Errors.Invalid_Header;
      end if;

      Item.Has_Auth := True;
      Item.Auth_Value := To_Unbounded_String (Value);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Item := Config;
         return Http_Client.Errors.Internal_Error;
   end With_Proxy_Authorization;

   function With_SOCKS5_Username_Password
     (Config   : Proxy_Config;
      Username : String;
      Password : String;
      Item     : out Proxy_Config) return Http_Client.Errors.Result_Status
   is
   begin
      Item := Config;

      if Config.Mode /= SOCKS5_Proxy then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      if not Credential_Is_Valid (Username)
        or else not Credential_Is_Valid (Password)
      then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      Item.SOCKS_Auth := SOCKS5_Username_Password;
      Item.SOCKS_User := To_Unbounded_String (Username);
      Item.SOCKS_Pass := To_Unbounded_String (Password);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Item := Config;
         return Http_Client.Errors.Internal_Error;
   end With_SOCKS5_Username_Password;

   function Kind (Item : Proxy_Config) return Proxy_Kind is
   begin
      return Item.Mode;
   end Kind;

   function Is_Enabled (Item : Proxy_Config) return Boolean is
   begin
      return Item.Mode /= No_Proxy;
   end Is_Enabled;

   function Host (Item : Proxy_Config) return String is
   begin
      return To_String (Item.Proxy_Host);
   end Host;

   function Port (Item : Proxy_Config) return Http_Client.URI.TCP_Port is
   begin
      return Item.Proxy_Port;
   end Port;

   function Has_Proxy_Authorization (Item : Proxy_Config) return Boolean is
   begin
      return Item.Has_Auth;
   end Has_Proxy_Authorization;

   function Proxy_Authorization (Item : Proxy_Config) return String is
   begin
      if Item.Has_Auth then
         return To_String (Item.Auth_Value);
      else
         return "";
      end if;
   end Proxy_Authorization;

   function SOCKS5_Authentication
     (Item : Proxy_Config) return SOCKS5_Authentication_Method is
   begin
      return Item.SOCKS_Auth;
   end SOCKS5_Authentication;

   function SOCKS5_DNS_Resolution
     (Item : Proxy_Config) return SOCKS5_DNS_Mode is
   begin
      return Item.SOCKS_DNS;
   end SOCKS5_DNS_Resolution;

   function SOCKS5_Username (Item : Proxy_Config) return String is
   begin
      return To_String (Item.SOCKS_User);
   end SOCKS5_Username;

   function SOCKS5_Password (Item : Proxy_Config) return String is
   begin
      return To_String (Item.SOCKS_Pass);
   end SOCKS5_Password;

end Http_Client.Proxies;
