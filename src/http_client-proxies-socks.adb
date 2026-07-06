with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.URI;

package body Http_Client.Proxies.SOCKS is
   use Ada.Strings.Unbounded;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Proxies.SOCKS5_Authentication_Method;
   use type Http_Client.Proxies.SOCKS5_DNS_Mode;

   SOCKS_V5      : constant Character := Character'Val (16#05#);
   METHOD_NONE   : constant Character := Character'Val (16#00#);
   METHOD_USERPW : constant Character := Character'Val (16#02#);
   METHOD_NONE_ACCEPTABLE : constant Character := Character'Val (16#FF#);

   function Octet (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end Octet;

   function Is_IPv4_Literal (Host : String) return Boolean is
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
            Value := Value * 10 + Character'Pos (Host (I)) - Character'Pos ('0');
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
   end Is_IPv4_Literal;


   function Looks_Like_IPv6_Literal (Host : String) return Boolean is
   begin
      for Ch of Host loop
         if Ch = ':' then
            return True;
         end if;
      end loop;

      return False;
   end Looks_Like_IPv6_Literal;

   function Hostname_Is_Encodable (Host : String) return Boolean is
   begin
      if Host'Length = 0 or else Host'Length > 255 then
         return False;
      end if;

      for Ch of Host loop
         if Character'Pos (Ch) < 33
           or else Character'Pos (Ch) = 127
           or else Ch = '/'
           or else Ch = '\'
           or else Ch = '@'
           or else Ch = ':'
           or else Ch = '['
           or else Ch = ']'
         then
            return False;
         end if;
      end loop;

      return True;
   end Hostname_Is_Encodable;

   function Append_IPv4
     (Host : String;
      Output : in out Unbounded_String) return Boolean
   is
      Octet_Start : Positive := Host'First;
      Value       : Natural := 0;
   begin
      for I in Host'Range loop
         if Host (I) = '.' then
            Append (Output, Octet (Value));
            Value := 0;
            Octet_Start := I + 1;
         else
            Value := Value * 10 + Character'Pos (Host (I)) - Character'Pos ('0');
         end if;
      end loop;

      if Octet_Start <= Host'Last then
         Append (Output, Octet (Value));
      end if;

      return True;
   exception
      when others =>
         return False;
   end Append_IPv4;

   function Expected_Method
     (Config : Http_Client.Proxies.Proxy_Config) return Character is
   begin
      if Http_Client.Proxies.SOCKS5_Authentication (Config) =
        Http_Client.Proxies.SOCKS5_Username_Password
      then
         return METHOD_USERPW;
      else
         return METHOD_NONE;
      end if;
   end Expected_Method;

   function Greeting
     (Config : Http_Client.Proxies.Proxy_Config;
      Output : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
   begin
      Output := Null_Unbounded_String;

      if Http_Client.Proxies.Kind (Config) /= Http_Client.Proxies.SOCKS5_Proxy then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      Append (Output, SOCKS_V5);
      Append (Output, Character'Val (1));
      Append (Output, Expected_Method (Config));
      return Http_Client.Errors.Ok;
   end Greeting;

   function Parse_Method_Selection
     (Reply  : String;
      Config : Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Reply'Length /= 2 then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      end if;

      if Reply (Reply'First) /= SOCKS_V5 then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      end if;

      if Reply (Reply'First + 1) = METHOD_NONE_ACCEPTABLE then
         return Http_Client.Errors.SOCKS_Unsupported_Authentication_Method;
      end if;

      if Reply (Reply'First + 1) /= Expected_Method (Config) then
         return Http_Client.Errors.SOCKS_Unsupported_Authentication_Method;
      end if;

      return Http_Client.Errors.Ok;
   end Parse_Method_Selection;

   function Username_Password_Request
     (Config : Http_Client.Proxies.Proxy_Config;
      Output : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      User : constant String := Http_Client.Proxies.SOCKS5_Username (Config);
      Pass : constant String := Http_Client.Proxies.SOCKS5_Password (Config);
   begin
      Output := Null_Unbounded_String;

      if Http_Client.Proxies.Kind (Config) /= Http_Client.Proxies.SOCKS5_Proxy
        or else Http_Client.Proxies.SOCKS5_Authentication (Config) /=
          Http_Client.Proxies.SOCKS5_Username_Password
      then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      if User'Length = 0 or else User'Length > 255
        or else Pass'Length = 0 or else Pass'Length > 255
      then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      Append (Output, Character'Val (1));
      Append (Output, Octet (User'Length));
      Append (Output, User);
      Append (Output, Octet (Pass'Length));
      Append (Output, Pass);
      return Http_Client.Errors.Ok;
   end Username_Password_Request;

   function Parse_Username_Password_Reply
     (Reply : String) return Http_Client.Errors.Result_Status
   is
   begin
      if Reply'Length /= 2 then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      end if;

      if Reply (Reply'First) /= Character'Val (1) then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      end if;

      if Reply (Reply'First + 1) /= Character'Val (0) then
         return Http_Client.Errors.SOCKS_Authentication_Failed;
      end if;

      return Http_Client.Errors.Ok;
   end Parse_Username_Password_Reply;

   function Connect_Request
     (Target_Host : String;
      Target_Port : Http_Client.URI.TCP_Port;
      DNS_Mode    : Http_Client.Proxies.SOCKS5_DNS_Mode;
      Output      : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Is_IPv4 : constant Boolean := Is_IPv4_Literal (Target_Host);
   begin
      Output := Null_Unbounded_String;

      if Target_Host'Length = 0 then
         return Http_Client.Errors.Invalid_URI;
      end if;

      if not Is_IPv4 and then Looks_Like_IPv6_Literal (Target_Host) then
         return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      end if;

      if not Is_IPv4 and then not Hostname_Is_Encodable (Target_Host) then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Append (Output, SOCKS_V5);
      Append (Output, Character'Val (1)); -- CONNECT
      Append (Output, Character'Val (0)); -- RSV

      if DNS_Mode = Http_Client.Proxies.SOCKS5_Local_DNS and then not Is_IPv4 then
         return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      end if;

      if Is_IPv4 then
         Append (Output, Character'Val (1));
         if not Append_IPv4 (Target_Host, Output) then
            return Http_Client.Errors.Invalid_URI;
         end if;
      else
         Append (Output, Character'Val (3));
         Append (Output, Octet (Target_Host'Length));
         Append (Output, Target_Host);
      end if;

      Append (Output, Octet (Natural (Target_Port) / 256));
      Append (Output, Octet (Natural (Target_Port) mod 256));
      return Http_Client.Errors.Ok;
   end Connect_Request;

   function Parse_Connect_Reply
     (Reply : String) return Http_Client.Errors.Result_Status
   is
      ATYP : Natural;
      Need : Natural;
      Code : Natural;
   begin
      if Reply'Length < 7 then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      end if;

      if Reply (Reply'First) /= SOCKS_V5 then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      end if;

      if Reply (Reply'First + 2) /= Character'Val (0) then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      end if;

      Code := Character'Pos (Reply (Reply'First + 1));
      ATYP := Character'Pos (Reply (Reply'First + 3));

      case ATYP is
         when 1 => Need := 10;
         when 3 =>
            if Reply'Length < 5 then
               return Http_Client.Errors.SOCKS_Malformed_Reply;
            end if;
            if Character'Pos (Reply (Reply'First + 4)) = 0 then
               return Http_Client.Errors.SOCKS_Malformed_Reply;
            end if;
            Need := 7 + Character'Pos (Reply (Reply'First + 4));
         when 4 => Need := 22;
         when others => return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      end case;

      if Reply'Length /= Need then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      end if;

      case Code is
         when 0 => return Http_Client.Errors.Ok;
         when 1 => return Http_Client.Errors.SOCKS_General_Server_Failure;
         when 2 => return Http_Client.Errors.SOCKS_Connection_Not_Allowed;
         when 3 => return Http_Client.Errors.SOCKS_Reply_Network_Unreachable;
         when 4 => return Http_Client.Errors.SOCKS_Reply_Host_Unreachable;
         when 5 => return Http_Client.Errors.SOCKS_Reply_Connection_Refused;
         when 6 => return Http_Client.Errors.SOCKS_TTL_Expired;
         when 7 => return Http_Client.Errors.SOCKS_Command_Unsupported;
         when 8 => return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
         when others => return Http_Client.Errors.SOCKS_Connect_Failed;
      end case;
   end Parse_Connect_Reply;

end Http_Client.Proxies.SOCKS;
