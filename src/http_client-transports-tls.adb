with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Http_Client.Errors;
with Http_Client.HTTP2;
with Http_Client.Proxies; use Http_Client.Proxies;
with Http_Client.Transports.TCP;
with Http_Client.TLS.Client_Certificates;
with Http_Client.URI;

package body Http_Client.Transports.TLS is
   use type System.Address;
   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;
   use type Http_Client.Errors.Result_Status;

   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;

   C_OK                 : constant C.int := 0;
   C_CONNECTION_FAILED  : constant C.int := 1;
   C_CA_STORE_FAILED    : constant C.int := 2;
   C_HANDSHAKE_FAILED   : constant C.int := 3;
   C_CERTIFICATE_FAILED : constant C.int := 4;
   C_HOSTNAME_FAILED    : constant C.int := 5;
   C_WRITE_FAILED       : constant C.int := 6;
   C_READ_FAILED        : constant C.int := 7;
   C_END_OF_STREAM      : constant C.int := 8;
   C_INTERNAL_ERROR     : constant C.int := 9;
   C_CLIENT_CERT_LOAD_FAILED : constant C.int := 10;
   C_CLIENT_KEY_LOAD_FAILED  : constant C.int := 11;
   C_CLIENT_KEY_MISMATCH     : constant C.int := 12;
   C_CLIENT_CERT_REJECTED    : constant C.int := 13;
   C_CLIENT_KEY_PASSPHRASE_REQUIRED : constant C.int := 14;
   C_CLIENT_KEY_PASSPHRASE_INVALID  : constant C.int := 15;
   C_PROXY_TUNNEL_FAILED            : constant C.int := 16;
   C_PROXY_AUTHENTICATION_REQUIRED  : constant C.int := 17;
   C_SOCKS_UNSUPPORTED_VERSION : constant C.int := 18;
   C_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD : constant C.int := 19;
   C_SOCKS_AUTHENTICATION_FAILED : constant C.int := 20;
   C_SOCKS_CONNECT_FAILED : constant C.int := 21;
   C_SOCKS_GENERAL_SERVER_FAILURE : constant C.int := 22;
   C_SOCKS_CONNECTION_NOT_ALLOWED : constant C.int := 23;
   C_SOCKS_TTL_EXPIRED : constant C.int := 24;
   C_SOCKS_COMMAND_UNSUPPORTED : constant C.int := 25;
   C_SOCKS_MALFORMED_REPLY : constant C.int := 26;
   C_SOCKS_ADDRESS_TYPE_UNSUPPORTED : constant C.int := 27;
   C_SOCKS_REPLY_CONNECTION_REFUSED : constant C.int := 28;
   C_SOCKS_REPLY_NETWORK_UNREACHABLE : constant C.int := 29;
   C_SOCKS_REPLY_HOST_UNREACHABLE : constant C.int := 30;
   C_TIMEOUT : constant C.int := 31;
   Max_Bridge_IO        : constant Natural := 32_768;

   function Bridge_Open
     (Handle               : out System.Address;
      Host                 : C_Strings.chars_ptr;
      Port                 : C.int;
      Disable_Verification : C.int;
      CA_File              : C_Strings.chars_ptr;
      CA_Directory         : C_Strings.chars_ptr;
      Send_SNI             : C.int;
      ALPN_Protocols       : C_Strings.chars_ptr;
      Read_Timeout_MS      : C.int;
      Write_Timeout_MS     : C.int;
      Client_Cert_File     : C_Strings.chars_ptr;
      Client_Key_File      : C_Strings.chars_ptr;
      Client_Key_Passphrase : C_Strings.chars_ptr) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_open";

   function Bridge_Open_Through_HTTP_Proxy
     (Handle                : out System.Address;
      Host                  : C_Strings.chars_ptr;
      Port                  : C.int;
      Proxy_Host            : C_Strings.chars_ptr;
      Proxy_Port            : C.int;
      Proxy_Authorization   : C_Strings.chars_ptr;
      Disable_Verification  : C.int;
      CA_File               : C_Strings.chars_ptr;
      CA_Directory          : C_Strings.chars_ptr;
      Send_SNI              : C.int;
      ALPN_Protocols        : C_Strings.chars_ptr;
      Read_Timeout_MS       : C.int;
      Write_Timeout_MS      : C.int;
      Client_Cert_File      : C_Strings.chars_ptr;
      Client_Key_File       : C_Strings.chars_ptr;
      Client_Key_Passphrase : C_Strings.chars_ptr) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_open_through_http_proxy";

   function Bridge_Open_Through_SOCKS_Proxy
     (Handle                : out System.Address;
      Host                  : C_Strings.chars_ptr;
      Port                  : C.int;
      Proxy_Host            : C_Strings.chars_ptr;
      Proxy_Port            : C.int;
      SOCKS_Auth_Method     : C.int;
      SOCKS_Username        : C_Strings.chars_ptr;
      SOCKS_Password        : C_Strings.chars_ptr;
      SOCKS_DNS_Mode        : C.int;
      Disable_Verification  : C.int;
      CA_File               : C_Strings.chars_ptr;
      CA_Directory          : C_Strings.chars_ptr;
      Send_SNI              : C.int;
      ALPN_Protocols        : C_Strings.chars_ptr;
      Read_Timeout_MS       : C.int;
      Write_Timeout_MS      : C.int;
      Client_Cert_File      : C_Strings.chars_ptr;
      Client_Key_File       : C_Strings.chars_ptr;
      Client_Key_Passphrase : C_Strings.chars_ptr) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_open_through_socks_proxy";

   function Bridge_Write_All
     (Handle : System.Address;
      Data   : System.Address;
      Length : C.int) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_write_all";

   function Bridge_Read_Some
     (Handle : System.Address;
      Buffer : System.Address;
      Length : C.int;
      Count  : out C.int) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_read_some";

   function Bridge_Read_Some_With_Timeout
     (Handle     : System.Address;
      Buffer     : System.Address;
      Length     : C.int;
      Count      : out C.int;
      Timeout_MS : C.int) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_read_some_with_timeout";

   function Bridge_Close (Handle : System.Address) return C.int
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_close";

   function Bridge_Selected_ALPN
     (Handle : System.Address) return C_Strings.chars_ptr
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_selected_alpn";

   function Bridge_TLS_Version
     (Handle : System.Address) return C_Strings.chars_ptr
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_version";

   function Bridge_Cipher_Name
     (Handle : System.Address) return C_Strings.chars_ptr
   with
      Import,
      Convention    => C,
      External_Name => "hc_tls_cipher_name";

   function C_Bool (Value : Boolean) return C.int is
   begin
      if Value then
         return 1;
      else
         return 0;
      end if;
   end C_Bool;

   function Contains_NUL (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Ch = Character'Val (0) then
            return True;
         end if;
      end loop;

      return False;
   end Contains_NUL;

   function Unbounded_Contains_NUL
     (Value : Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
   begin
      return Contains_NUL (Ada.Strings.Unbounded.To_String (Value));
   end Unbounded_Contains_NUL;


   function Unbounded_Is_Nonempty
     (Value : Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
   begin
      return Ada.Strings.Unbounded.Length (Value) > 0;
   end Unbounded_Is_Nonempty;

   function Validate_Options
     (Options : TLS_Options) return Http_Client.Errors.Result_Status
   is
      Has_Explicit_CA : constant Boolean :=
        Unbounded_Is_Nonempty (Options.CA_File)
        or else Unbounded_Is_Nonempty (Options.CA_Directory);
   begin
      if Unbounded_Contains_NUL (Options.CA_File)
        or else Unbounded_Contains_NUL (Options.CA_Directory)
      then
         return Http_Client.Errors.CA_Store_Failed;
      end if;

      if Options.Disable_Certificate_Verification and then Has_Explicit_CA then
         return Http_Client.Errors.Invalid_Request;
      end if;

      declare
         Credential_Status : constant Http_Client.Errors.Result_Status :=
           Http_Client.TLS.Client_Certificates.Validate
             (Options.Client_Certificate);
      begin
         if Credential_Status /= Http_Client.Errors.Ok then
            return Credential_Status;
         end if;
      end;

      return Http_Client.HTTP2.Validate (Options.HTTP2);
   end Validate_Options;

   function Host_Syntax_Is_Valid (Host : String) return Boolean is
      Label_Start         : Positive := Host'First;
      Dot_Count           : Natural := 0;
      All_IPv4_Characters : Boolean := True;

      function Is_Hex_Digit (Ch : Character) return Boolean is
      begin
         return
           (Ch in '0' .. '9') or else
           (Ch in 'a' .. 'f') or else
           (Ch in 'A' .. 'F');
      end Is_Hex_Digit;

      function Contains_Colon (Text : String) return Boolean is
      begin
         for Ch of Text loop
            if Ch = ':' then
               return True;
            end if;
         end loop;

         return False;
      end Contains_Colon;

      function Is_Allowed_Host_Character (Ch : Character) return Boolean is
      begin
         return
           (Ch in 'a' .. 'z') or else
           (Ch in 'A' .. 'Z') or else
           (Ch in '0' .. '9') or else
           Ch = '-' or else
           Ch = '.';
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

         return
           Octets = 4 and then
           Octet_Is_Valid (Octet_Start, Host'Last);
      end IPv4_Literal_Is_Valid;

      function IPv6_Literal_Is_Valid return Boolean is
         Double_Colon : Natural := 0;

         function Contains_Dot (Text : String) return Boolean is
         begin
            for Ch of Text loop
               if Ch = '.' then
                  return True;
               end if;
            end loop;

            return False;
         end Contains_Dot;

         function IPv4_Tail_Is_Valid (Text : String) return Boolean is
            Octet_Start : Positive := Text'First;
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
                  if Text (I) not in '0' .. '9' then
                     return False;
                  end if;

                  Value :=
                    Value * 10 +
                    Character'Pos (Text (I)) - Character'Pos ('0');

                  if Value > 255 then
                     return False;
                  end if;
               end loop;

               return True;
            end Octet_Is_Valid;
         begin
            if Text'Length = 0 then
               return False;
            end if;

            for I in Text'Range loop
               if Text (I) = '.' then
                  Octets := Octets + 1;

                  if not Octet_Is_Valid (Octet_Start, I - 1) then
                     return False;
                  end if;

                  if I = Text'Last then
                     return False;
                  end if;

                  Octet_Start := I + 1;
               end if;
            end loop;

            Octets := Octets + 1;

            return Octets = 4 and then Octet_Is_Valid (Octet_Start, Text'Last);
         end IPv4_Tail_Is_Valid;

         function Hextet_Is_Valid (Text : String) return Boolean is
         begin
            if Text'Length = 0 or else Text'Length > 4 then
               return False;
            end if;

            for Ch of Text loop
               if not Is_Hex_Digit (Ch) then
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
                  if not Allow_IPv4_Tail or else not IPv4_Tail_Is_Valid (Segment) then
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
      end IPv6_Literal_Is_Valid;
   begin
      if Host'Length = 0 or else Host'Length > 253 then
         return False;
      end if;

      if Contains_Colon (Host) then
         return IPv6_Literal_Is_Valid;
      end if;

      for I in Host'Range loop
         declare
            Ch : constant Character := Host (I);
         begin
            if not Is_Allowed_Host_Character (Ch) then
               return False;
            end if;

            if Ch = '.' then
               Dot_Count := Dot_Count + 1;

               if not Label_Is_Well_Formed (Label_Start, I - 1) then
                  return False;
               end if;

               if I = Host'Last then
                  return False;
               end if;

               Label_Start := I + 1;
            elsif Ch not in '0' .. '9' then
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
   end Host_Syntax_Is_Valid;

   function Map_Open_Status (Value : C.int) return Http_Client.Errors.Result_Status is
   begin
      if Value = C_OK then
         return Http_Client.Errors.Ok;
      elsif Value = C_CONNECTION_FAILED then
         return Http_Client.Errors.Connection_Failed;
      elsif Value = C_CA_STORE_FAILED then
         return Http_Client.Errors.CA_Store_Failed;
      elsif Value = C_HANDSHAKE_FAILED then
         return Http_Client.Errors.TLS_Handshake_Failed;
      elsif Value = C_CERTIFICATE_FAILED then
         return Http_Client.Errors.Certificate_Verification_Failed;
      elsif Value = C_HOSTNAME_FAILED then
         return Http_Client.Errors.Hostname_Verification_Failed;
      elsif Value = C_CLIENT_CERT_LOAD_FAILED then
         return Http_Client.Errors.TLS_Client_Certificate_Load_Failed;
      elsif Value = C_CLIENT_KEY_LOAD_FAILED then
         return Http_Client.Errors.TLS_Client_Key_Load_Failed;
      elsif Value = C_CLIENT_KEY_MISMATCH then
         return Http_Client.Errors.TLS_Client_Key_Mismatch;
      elsif Value = C_CLIENT_KEY_PASSPHRASE_REQUIRED then
         return Http_Client.Errors.TLS_Client_Key_Passphrase_Required;
      elsif Value = C_CLIENT_KEY_PASSPHRASE_INVALID then
         return Http_Client.Errors.TLS_Client_Key_Passphrase_Invalid;
      elsif Value = C_CLIENT_CERT_REJECTED then
         return Http_Client.Errors.TLS_Client_Certificate_Rejected;
      elsif Value = C_PROXY_TUNNEL_FAILED then
         return Http_Client.Errors.Proxy_Tunnel_Failed;
      elsif Value = C_PROXY_AUTHENTICATION_REQUIRED then
         return Http_Client.Errors.Proxy_Authentication_Required;
      elsif Value = C_SOCKS_UNSUPPORTED_VERSION then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      elsif Value = C_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD then
         return Http_Client.Errors.SOCKS_Unsupported_Authentication_Method;
      elsif Value = C_SOCKS_AUTHENTICATION_FAILED then
         return Http_Client.Errors.SOCKS_Authentication_Failed;
      elsif Value = C_SOCKS_CONNECT_FAILED then
         return Http_Client.Errors.SOCKS_Connect_Failed;
      elsif Value = C_SOCKS_GENERAL_SERVER_FAILURE then
         return Http_Client.Errors.SOCKS_General_Server_Failure;
      elsif Value = C_SOCKS_CONNECTION_NOT_ALLOWED then
         return Http_Client.Errors.SOCKS_Connection_Not_Allowed;
      elsif Value = C_SOCKS_TTL_EXPIRED then
         return Http_Client.Errors.SOCKS_TTL_Expired;
      elsif Value = C_SOCKS_COMMAND_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Command_Unsupported;
      elsif Value = C_SOCKS_MALFORMED_REPLY then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      elsif Value = C_SOCKS_ADDRESS_TYPE_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      elsif Value = C_SOCKS_REPLY_CONNECTION_REFUSED then
         return Http_Client.Errors.SOCKS_Reply_Connection_Refused;
      elsif Value = C_SOCKS_REPLY_NETWORK_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Network_Unreachable;
      elsif Value = C_SOCKS_REPLY_HOST_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Host_Unreachable;
      elsif Value = C_TIMEOUT then
         return Http_Client.Errors.Timeout;
      elsif Value = C_INTERNAL_ERROR then
         return Http_Client.Errors.Internal_Error;
      else
         return Http_Client.Errors.TLS_Failed;
      end if;
   end Map_Open_Status;

   function Map_Write_Status (Value : C.int) return Http_Client.Errors.Result_Status is
   begin
      if Value = C_OK then
         return Http_Client.Errors.Ok;
      elsif Value = C_WRITE_FAILED then
         return Http_Client.Errors.Write_Failed;
      elsif Value = C_CLIENT_CERT_REJECTED then
         return Http_Client.Errors.TLS_Client_Certificate_Rejected;
      elsif Value = C_PROXY_TUNNEL_FAILED then
         return Http_Client.Errors.Proxy_Tunnel_Failed;
      elsif Value = C_PROXY_AUTHENTICATION_REQUIRED then
         return Http_Client.Errors.Proxy_Authentication_Required;
      elsif Value = C_SOCKS_UNSUPPORTED_VERSION then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      elsif Value = C_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD then
         return Http_Client.Errors.SOCKS_Unsupported_Authentication_Method;
      elsif Value = C_SOCKS_AUTHENTICATION_FAILED then
         return Http_Client.Errors.SOCKS_Authentication_Failed;
      elsif Value = C_SOCKS_CONNECT_FAILED then
         return Http_Client.Errors.SOCKS_Connect_Failed;
      elsif Value = C_SOCKS_GENERAL_SERVER_FAILURE then
         return Http_Client.Errors.SOCKS_General_Server_Failure;
      elsif Value = C_SOCKS_CONNECTION_NOT_ALLOWED then
         return Http_Client.Errors.SOCKS_Connection_Not_Allowed;
      elsif Value = C_SOCKS_TTL_EXPIRED then
         return Http_Client.Errors.SOCKS_TTL_Expired;
      elsif Value = C_SOCKS_COMMAND_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Command_Unsupported;
      elsif Value = C_SOCKS_MALFORMED_REPLY then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      elsif Value = C_SOCKS_ADDRESS_TYPE_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      elsif Value = C_SOCKS_REPLY_CONNECTION_REFUSED then
         return Http_Client.Errors.SOCKS_Reply_Connection_Refused;
      elsif Value = C_SOCKS_REPLY_NETWORK_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Network_Unreachable;
      elsif Value = C_SOCKS_REPLY_HOST_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Host_Unreachable;
      elsif Value = C_TIMEOUT then
         return Http_Client.Errors.Timeout;
      elsif Value = C_INTERNAL_ERROR then
         return Http_Client.Errors.Internal_Error;
      else
         return Http_Client.Errors.TLS_Failed;
      end if;
   end Map_Write_Status;

   function Map_Read_Status (Value : C.int) return Http_Client.Errors.Result_Status is
   begin
      if Value = C_OK then
         return Http_Client.Errors.Ok;
      elsif Value = C_END_OF_STREAM then
         return Http_Client.Errors.End_Of_Stream;
      elsif Value = C_READ_FAILED then
         return Http_Client.Errors.Read_Failed;
      elsif Value = C_CLIENT_CERT_REJECTED then
         return Http_Client.Errors.TLS_Client_Certificate_Rejected;
      elsif Value = C_PROXY_TUNNEL_FAILED then
         return Http_Client.Errors.Proxy_Tunnel_Failed;
      elsif Value = C_PROXY_AUTHENTICATION_REQUIRED then
         return Http_Client.Errors.Proxy_Authentication_Required;
      elsif Value = C_SOCKS_UNSUPPORTED_VERSION then
         return Http_Client.Errors.SOCKS_Unsupported_Version;
      elsif Value = C_SOCKS_UNSUPPORTED_AUTHENTICATION_METHOD then
         return Http_Client.Errors.SOCKS_Unsupported_Authentication_Method;
      elsif Value = C_SOCKS_AUTHENTICATION_FAILED then
         return Http_Client.Errors.SOCKS_Authentication_Failed;
      elsif Value = C_SOCKS_CONNECT_FAILED then
         return Http_Client.Errors.SOCKS_Connect_Failed;
      elsif Value = C_SOCKS_GENERAL_SERVER_FAILURE then
         return Http_Client.Errors.SOCKS_General_Server_Failure;
      elsif Value = C_SOCKS_CONNECTION_NOT_ALLOWED then
         return Http_Client.Errors.SOCKS_Connection_Not_Allowed;
      elsif Value = C_SOCKS_TTL_EXPIRED then
         return Http_Client.Errors.SOCKS_TTL_Expired;
      elsif Value = C_SOCKS_COMMAND_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Command_Unsupported;
      elsif Value = C_SOCKS_MALFORMED_REPLY then
         return Http_Client.Errors.SOCKS_Malformed_Reply;
      elsif Value = C_SOCKS_ADDRESS_TYPE_UNSUPPORTED then
         return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      elsif Value = C_SOCKS_REPLY_CONNECTION_REFUSED then
         return Http_Client.Errors.SOCKS_Reply_Connection_Refused;
      elsif Value = C_SOCKS_REPLY_NETWORK_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Network_Unreachable;
      elsif Value = C_SOCKS_REPLY_HOST_UNREACHABLE then
         return Http_Client.Errors.SOCKS_Reply_Host_Unreachable;
      elsif Value = C_TIMEOUT then
         return Http_Client.Errors.Timeout;
      elsif Value = C_INTERNAL_ERROR then
         return Http_Client.Errors.Internal_Error;
      else
         return Http_Client.Errors.TLS_Failed;
      end if;
   end Map_Read_Status;


   function SOCKS_Auth_Method_C
     (Proxy : Http_Client.Proxies.Proxy_Config) return C.int
   is
   begin
      if Http_Client.Proxies.SOCKS5_Authentication (Proxy) =
        Http_Client.Proxies.SOCKS5_Username_Password
      then
         return 1;
      else
         return 0;
      end if;
   end SOCKS_Auth_Method_C;

   function SOCKS_DNS_Mode_C
     (Proxy : Http_Client.Proxies.Proxy_Config) return C.int
   is
   begin
      if Http_Client.Proxies.SOCKS5_DNS_Resolution (Proxy) =
        Http_Client.Proxies.SOCKS5_Local_DNS
      then
         return 1;
      else
         return 0;
      end if;
   end SOCKS_DNS_Mode_C;


   function To_C_String_Or_Null
     (Value : Ada.Strings.Unbounded.Unbounded_String)
      return C_Strings.chars_ptr
   is
      Text : constant String := Ada.Strings.Unbounded.To_String (Value);
   begin
      if Text'Length = 0 then
         return C_Strings.Null_Ptr;
      else
         return C_Strings.New_String (Text);
      end if;
   end To_C_String_Or_Null;


   function To_C_String_Preserving_Empty
     (Value : Ada.Strings.Unbounded.Unbounded_String)
      return C_Strings.chars_ptr
   is
   begin
      return C_Strings.New_String (Ada.Strings.Unbounded.To_String (Value));
   end To_C_String_Preserving_Empty;

   procedure Free_If_Not_Null (Value : in out C_Strings.chars_ptr) is
   begin
      if Value /= C_Strings.Null_Ptr then
         C_Strings.Free (Value);
      end if;
   end Free_If_Not_Null;

   procedure Force_Close (Item : in out Connection) is
   begin
      if Item.Handle /= System.Null_Address then
         if Bridge_Close (Item.Handle) /= C_OK then
            null;
         end if;
      end if;

      Item.Handle := System.Null_Address;
      Item.Opened := False;
   exception
      when others =>
         Item.Handle := System.Null_Address;
         Item.Opened := False;
   end Force_Close;

   overriding procedure Finalize (Item : in out Connection) is
   begin
      Force_Close (Item);
   end Finalize;

   function Verification_Enabled_By_Default return Boolean is
   begin
      return not Default_TLS_Options.Disable_Certificate_Verification;
   end Verification_Enabled_By_Default;

   function Is_Open (Item : Connection) return Boolean is
   begin
      return Item.Opened and then Item.Handle /= System.Null_Address;
   end Is_Open;

   function Selected_ALPN (Item : Connection) return Http_Client.HTTP2.Selected_Protocol is
      Raw : C_Strings.chars_ptr;
   begin
      if not Is_Open (Item) then
         return Http_Client.HTTP2.Protocol_None;
      end if;

      Raw := Bridge_Selected_ALPN (Item.Handle);
      if Raw = C_Strings.Null_Ptr then
         return Http_Client.HTTP2.Protocol_None;
      end if;

      return Http_Client.HTTP2.Normalize_ALPN_Selected
        (C_Strings.Value (Raw));
   exception
      when others =>
         return Http_Client.HTTP2.Protocol_None;
   end Selected_ALPN;

   function TLS_Version (Item : Connection) return String is
      Raw : C_Strings.chars_ptr;
   begin
      if not Is_Open (Item) then
         return "";
      end if;

      Raw := Bridge_TLS_Version (Item.Handle);
      if Raw = C_Strings.Null_Ptr then
         return "";
      end if;

      return C_Strings.Value (Raw);
   exception
      when others =>
         return "";
   end TLS_Version;

   function Cipher_Name (Item : Connection) return String is
      Raw : C_Strings.chars_ptr;
   begin
      if not Is_Open (Item) then
         return "";
      end if;

      Raw := Bridge_Cipher_Name (Item.Handle);
      if Raw = C_Strings.Null_Ptr then
         return "";
      end if;

      return C_Strings.Value (Raw);
   exception
      when others =>
         return "";
   end Cipher_Name;

   function Open
     (Item    : in out Connection;
      Host    : String;
      Port    : Http_Client.URI.TCP_Port;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status
   is
      Handle       : System.Address := System.Null_Address;
      Host_C       : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_File_C    : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_Dir_C     : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      ALPN_C       : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Cert_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Key_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Pass_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Raw_Status   : C.int;
      Final_Status : Http_Client.Errors.Result_Status;
   begin
      Force_Close (Item);

      if Host'Length = 0 then
         return Http_Client.Errors.Invalid_URI;
      end if;

      if Contains_NUL (Host) or else not Host_Syntax_Is_Valid (Host) then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Final_Status := Validate_Options (Options);
      if Final_Status /= Http_Client.Errors.Ok then
         return Final_Status;
      end if;

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
        and then not Http_Client.TLS.Client_Certificates.Matches_Origin
          (Credential => Options.Client_Certificate,
           Scheme     => "https",
           Host       => Host,
           Port       => Port)
      then
         return Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch;
      end if;

      Host_C := C_Strings.New_String (Host);
      CA_File_C := To_C_String_Or_Null (Options.CA_File);
      CA_Dir_C := To_C_String_Or_Null (Options.CA_Directory);
      ALPN_C := C_Strings.New_String
        (Http_Client.HTTP2.ALPN_Advertisement (Options.HTTP2));

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
      then
         Client_Cert_C := To_C_String_Or_Null
           (Options.Client_Certificate.Certificate_File);
         Client_Key_C := To_C_String_Or_Null
           (Options.Client_Certificate.Private_Key_File);
         if Options.Client_Certificate.Has_Passphrase then
            Client_Pass_C := To_C_String_Preserving_Empty
              (Options.Client_Certificate.Passphrase);
         end if;
      end if;

      Raw_Status := Bridge_Open
        (Handle               => Handle,
         Host                 => Host_C,
         Port                 => C.int (Port),
         Disable_Verification => C_Bool (Options.Disable_Certificate_Verification),
         CA_File              => CA_File_C,
         CA_Directory         => CA_Dir_C,
         Send_SNI             => C_Bool (Options.Send_SNI),
         ALPN_Protocols       => ALPN_C,
         Read_Timeout_MS      => C.int (Options.Timeouts.Read),
         Write_Timeout_MS     => C.int (Options.Timeouts.Write),
         Client_Cert_File     => Client_Cert_C,
         Client_Key_File      => Client_Key_C,
         Client_Key_Passphrase => Client_Pass_C);

      Final_Status := Map_Open_Status (Raw_Status);

      if Final_Status = Http_Client.Errors.Ok then
         if Handle = System.Null_Address then
            Final_Status := Http_Client.Errors.Internal_Error;
            Item.Handle := System.Null_Address;
            Item.Opened := False;
         else
            Item.Handle := Handle;
            Item.Opened := True;

            Final_Status := Http_Client.HTTP2.Selected_Status
              (Options  => Options.HTTP2,
               Selected => Selected_ALPN (Item));

            if Final_Status /= Http_Client.Errors.Ok then
               Force_Close (Item);
            end if;
         end if;
      else
         Item.Handle := System.Null_Address;
         Item.Opened := False;
      end if;

      Free_If_Not_Null (Host_C);
      Free_If_Not_Null (CA_File_C);
      Free_If_Not_Null (CA_Dir_C);
      Free_If_Not_Null (ALPN_C);
      Free_If_Not_Null (Client_Cert_C);
      Free_If_Not_Null (Client_Key_C);
      Free_If_Not_Null (Client_Pass_C);

      return Final_Status;
   exception
      when others =>
         Free_If_Not_Null (Host_C);
         Free_If_Not_Null (CA_File_C);
         Free_If_Not_Null (CA_Dir_C);
         Free_If_Not_Null (ALPN_C);
         Free_If_Not_Null (Client_Cert_C);
         Free_If_Not_Null (Client_Key_C);
         Free_If_Not_Null (Client_Pass_C);
         Force_Close (Item);
         return Http_Client.Errors.Internal_Error;
   end Open;


   function Open_Through_HTTP_Proxy
     (Item                : in out Connection;
      Host                : String;
      Port                : Http_Client.URI.TCP_Port;
      Proxy_Host          : String;
      Proxy_Port          : Http_Client.URI.TCP_Port;
      Proxy_Authorization : String := "";
      Options             : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status
   is
      Handle        : System.Address := System.Null_Address;
      Host_C        : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Proxy_Host_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Proxy_Auth_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_File_C     : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_Dir_C      : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      ALPN_C        : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Cert_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Key_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Pass_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Raw_Status    : C.int;
      Final_Status  : Http_Client.Errors.Result_Status;
   begin
      Force_Close (Item);

      if Host'Length = 0 or else Proxy_Host'Length = 0 then
         return Http_Client.Errors.Invalid_URI;
      end if;

      if Contains_NUL (Host)
        or else Contains_NUL (Proxy_Host)
        or else Contains_NUL (Proxy_Authorization)
        or else not Host_Syntax_Is_Valid (Host)
        or else not Host_Syntax_Is_Valid (Proxy_Host)
      then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Final_Status := Validate_Options (Options);
      if Final_Status /= Http_Client.Errors.Ok then
         return Final_Status;
      end if;

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
        and then not Http_Client.TLS.Client_Certificates.Matches_Origin
          (Credential => Options.Client_Certificate,
           Scheme     => "https",
           Host       => Host,
           Port       => Port)
      then
         return Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch;
      end if;

      Host_C := C_Strings.New_String (Host);
      Proxy_Host_C := C_Strings.New_String (Proxy_Host);
      Proxy_Auth_C := To_C_String_Or_Null (Ada.Strings.Unbounded.To_Unbounded_String (Proxy_Authorization));
      CA_File_C := To_C_String_Or_Null (Options.CA_File);
      CA_Dir_C := To_C_String_Or_Null (Options.CA_Directory);
      ALPN_C := C_Strings.New_String
        (Http_Client.HTTP2.ALPN_Advertisement (Options.HTTP2));

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
      then
         Client_Cert_C := To_C_String_Or_Null
           (Options.Client_Certificate.Certificate_File);
         Client_Key_C := To_C_String_Or_Null
           (Options.Client_Certificate.Private_Key_File);
         if Options.Client_Certificate.Has_Passphrase then
            Client_Pass_C := To_C_String_Preserving_Empty
              (Options.Client_Certificate.Passphrase);
         end if;
      end if;

      Raw_Status := Bridge_Open_Through_HTTP_Proxy
        (Handle                => Handle,
         Host                  => Host_C,
         Port                  => C.int (Port),
         Proxy_Host            => Proxy_Host_C,
         Proxy_Port            => C.int (Proxy_Port),
         Proxy_Authorization   => Proxy_Auth_C,
         Disable_Verification  => C_Bool (Options.Disable_Certificate_Verification),
         CA_File               => CA_File_C,
         CA_Directory          => CA_Dir_C,
         Send_SNI              => C_Bool (Options.Send_SNI),
         ALPN_Protocols        => ALPN_C,
         Read_Timeout_MS       => C.int (Options.Timeouts.Read),
         Write_Timeout_MS      => C.int (Options.Timeouts.Write),
         Client_Cert_File      => Client_Cert_C,
         Client_Key_File       => Client_Key_C,
         Client_Key_Passphrase => Client_Pass_C);

      Final_Status := Map_Open_Status (Raw_Status);

      if Final_Status = Http_Client.Errors.Connection_Failed then
         Final_Status := Http_Client.Errors.Proxy_Connection_Failed;
      end if;

      if Final_Status = Http_Client.Errors.Ok then
         if Handle = System.Null_Address then
            Final_Status := Http_Client.Errors.Internal_Error;
            Item.Handle := System.Null_Address;
            Item.Opened := False;
         else
            Item.Handle := Handle;
            Item.Opened := True;

            Final_Status := Http_Client.HTTP2.Selected_Status
              (Options  => Options.HTTP2,
               Selected => Selected_ALPN (Item));

            if Final_Status /= Http_Client.Errors.Ok then
               Force_Close (Item);
            end if;
         end if;
      else
         Item.Handle := System.Null_Address;
         Item.Opened := False;
      end if;

      Free_If_Not_Null (Host_C);
      Free_If_Not_Null (Proxy_Host_C);
      Free_If_Not_Null (Proxy_Auth_C);
      Free_If_Not_Null (CA_File_C);
      Free_If_Not_Null (CA_Dir_C);
      Free_If_Not_Null (ALPN_C);
      Free_If_Not_Null (Client_Cert_C);
      Free_If_Not_Null (Client_Key_C);
      Free_If_Not_Null (Client_Pass_C);

      return Final_Status;
   exception
      when others =>
         Free_If_Not_Null (Host_C);
         Free_If_Not_Null (Proxy_Host_C);
         Free_If_Not_Null (Proxy_Auth_C);
         Free_If_Not_Null (CA_File_C);
         Free_If_Not_Null (CA_Dir_C);
         Free_If_Not_Null (ALPN_C);
         Free_If_Not_Null (Client_Cert_C);
         Free_If_Not_Null (Client_Key_C);
         Free_If_Not_Null (Client_Pass_C);
         Force_Close (Item);
         return Http_Client.Errors.Internal_Error;
   end Open_Through_HTTP_Proxy;

   function Open_Through_SOCKS_Proxy
     (Item    : in out Connection;
      Host    : String;
      Port    : Http_Client.URI.TCP_Port;
      Proxy   : Http_Client.Proxies.Proxy_Config;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status
   is
      Handle        : System.Address := System.Null_Address;
      Host_C        : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Proxy_Host_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      SOCKS_User_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      SOCKS_Pass_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_File_C     : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      CA_Dir_C      : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      ALPN_C        : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Cert_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Key_C  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Client_Pass_C : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Raw_Status    : C.int;
      Final_Status  : Http_Client.Errors.Result_Status;
   begin
      Force_Close (Item);

      if Http_Client.Proxies.Kind (Proxy) /= Http_Client.Proxies.SOCKS5_Proxy then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      if Host'Length = 0 or else Http_Client.Proxies.Host (Proxy)'Length = 0 then
         return Http_Client.Errors.Invalid_URI;
      end if;

      if Contains_NUL (Host)
        or else Contains_NUL (Http_Client.Proxies.Host (Proxy))
        or else Contains_NUL (Http_Client.Proxies.SOCKS5_Username (Proxy))
        or else Contains_NUL (Http_Client.Proxies.SOCKS5_Password (Proxy))
        or else not Host_Syntax_Is_Valid (Host)
        or else not Host_Syntax_Is_Valid (Http_Client.Proxies.Host (Proxy))
      then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Final_Status := Validate_Options (Options);
      if Final_Status /= Http_Client.Errors.Ok then
         return Final_Status;
      end if;

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
        and then not Http_Client.TLS.Client_Certificates.Matches_Origin
          (Credential => Options.Client_Certificate,
           Scheme     => "https",
           Host       => Host,
           Port       => Port)
      then
         return Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch;
      end if;

      Host_C := C_Strings.New_String (Host);
      Proxy_Host_C := C_Strings.New_String (Http_Client.Proxies.Host (Proxy));
      if Http_Client.Proxies.SOCKS5_Authentication (Proxy) =
        Http_Client.Proxies.SOCKS5_Username_Password
      then
         SOCKS_User_C := C_Strings.New_String
           (Http_Client.Proxies.SOCKS5_Username (Proxy));
         SOCKS_Pass_C := C_Strings.New_String
           (Http_Client.Proxies.SOCKS5_Password (Proxy));
      end if;
      CA_File_C := To_C_String_Or_Null (Options.CA_File);
      CA_Dir_C := To_C_String_Or_Null (Options.CA_Directory);
      ALPN_C := C_Strings.New_String
        (Http_Client.HTTP2.ALPN_Advertisement (Options.HTTP2));

      if Http_Client.TLS.Client_Certificates.Is_Configured
        (Options.Client_Certificate)
      then
         Client_Cert_C := To_C_String_Or_Null
           (Options.Client_Certificate.Certificate_File);
         Client_Key_C := To_C_String_Or_Null
           (Options.Client_Certificate.Private_Key_File);
         if Options.Client_Certificate.Has_Passphrase then
            Client_Pass_C := To_C_String_Preserving_Empty
              (Options.Client_Certificate.Passphrase);
         end if;
      end if;

      Raw_Status := Bridge_Open_Through_SOCKS_Proxy
        (Handle                => Handle,
         Host                  => Host_C,
         Port                  => C.int (Port),
         Proxy_Host            => Proxy_Host_C,
         Proxy_Port            => C.int (Http_Client.Proxies.Port (Proxy)),
         SOCKS_Auth_Method     => SOCKS_Auth_Method_C (Proxy),
         SOCKS_Username        => SOCKS_User_C,
         SOCKS_Password        => SOCKS_Pass_C,
         SOCKS_DNS_Mode        => SOCKS_DNS_Mode_C (Proxy),
         Disable_Verification  => C_Bool (Options.Disable_Certificate_Verification),
         CA_File               => CA_File_C,
         CA_Directory          => CA_Dir_C,
         Send_SNI              => C_Bool (Options.Send_SNI),
         ALPN_Protocols        => ALPN_C,
         Read_Timeout_MS       => C.int (Options.Timeouts.Read),
         Write_Timeout_MS      => C.int (Options.Timeouts.Write),
         Client_Cert_File      => Client_Cert_C,
         Client_Key_File       => Client_Key_C,
         Client_Key_Passphrase => Client_Pass_C);

      Final_Status := Map_Open_Status (Raw_Status);

      if Final_Status = Http_Client.Errors.Connection_Failed then
         Final_Status := Http_Client.Errors.Proxy_Connection_Failed;
      end if;

      if Final_Status = Http_Client.Errors.Ok then
         if Handle = System.Null_Address then
            Final_Status := Http_Client.Errors.Internal_Error;
            Item.Handle := System.Null_Address;
            Item.Opened := False;
         else
            Item.Handle := Handle;
            Item.Opened := True;

            Final_Status := Http_Client.HTTP2.Selected_Status
              (Options  => Options.HTTP2,
               Selected => Selected_ALPN (Item));

            if Final_Status /= Http_Client.Errors.Ok then
               Force_Close (Item);
            end if;
         end if;
      else
         Item.Handle := System.Null_Address;
         Item.Opened := False;
      end if;

      Free_If_Not_Null (Host_C);
      Free_If_Not_Null (Proxy_Host_C);
      Free_If_Not_Null (SOCKS_User_C);
      Free_If_Not_Null (SOCKS_Pass_C);
      Free_If_Not_Null (CA_File_C);
      Free_If_Not_Null (CA_Dir_C);
      Free_If_Not_Null (ALPN_C);
      Free_If_Not_Null (Client_Cert_C);
      Free_If_Not_Null (Client_Key_C);
      Free_If_Not_Null (Client_Pass_C);

      return Final_Status;
   exception
      when others =>
         Free_If_Not_Null (Host_C);
         Free_If_Not_Null (Proxy_Host_C);
         Free_If_Not_Null (SOCKS_User_C);
         Free_If_Not_Null (SOCKS_Pass_C);
         Free_If_Not_Null (CA_File_C);
         Free_If_Not_Null (CA_Dir_C);
         Free_If_Not_Null (ALPN_C);
         Free_If_Not_Null (Client_Cert_C);
         Free_If_Not_Null (Client_Key_C);
         Free_If_Not_Null (Client_Pass_C);
         Force_Close (Item);
         return Http_Client.Errors.Internal_Error;
   end Open_Through_SOCKS_Proxy;

   function Open_URI
     (Item    : in out Connection;
      URI     : Http_Client.URI.URI_Reference;
      Options : TLS_Options := Default_TLS_Options)
      return Http_Client.Errors.Result_Status is
   begin
      if not Http_Client.URI.Is_Parsed (URI) then
         Force_Close (Item);
         return Http_Client.Errors.Invalid_URI;
      end if;

      if not Http_Client.URI.Requires_TLS (URI) then
         Force_Close (Item);
         return Http_Client.Errors.Unsupported_Feature;
      end if;

      return Open
        (Item    => Item,
         Host    => Http_Client.URI.Host (URI),
         Port    => Http_Client.URI.Effective_Port (URI),
         Options => Options);
   end Open_URI;

   function Write_All
     (Item : in out Connection;
      Data : String) return Http_Client.Errors.Result_Status
   is
      First  : Natural := Data'First;
      Status : C.int := C_OK;
   begin
      if not Is_Open (Item) then
         return Http_Client.Errors.Not_Connected;
      end if;

      if Data'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      while First <= Data'Last loop
         declare
            Amount : constant Natural :=
              Natural'Min (Data'Last - First + 1, Max_Bridge_IO);
         begin
            Status := Bridge_Write_All
              (Handle => Item.Handle,
               Data   => Data (First)'Address,
               Length => C.int (Amount));

            if Status /= C_OK then
               Force_Close (Item);
               return Map_Write_Status (Status);
            end if;

            First := First + Amount;
         end;
      end loop;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         Force_Close (Item);
         return Http_Client.Errors.Write_Failed;
   end Write_All;

   function Read_Some
     (Item   : in out Connection;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status
   is
      C_Count : C.int := 0;
      Status  : C.int;
   begin
      Count := 0;

      if not Is_Open (Item) then
         return Http_Client.Errors.Not_Connected;
      end if;

      if Buffer'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      Status := Bridge_Read_Some
        (Handle => Item.Handle,
         Buffer => Buffer (Buffer'First)'Address,
         Length => C.int (Natural'Min (Buffer'Length, Max_Bridge_IO)),
         Count  => C_Count);

      if Status = C_OK then
         if C_Count < 0
           or else Natural (C_Count) > Natural'Min (Buffer'Length, Max_Bridge_IO)
         then
            Force_Close (Item);
            return Http_Client.Errors.Internal_Error;
         end if;

         Count := Natural (C_Count);
      elsif Status /= C_END_OF_STREAM then
         Force_Close (Item);
      end if;

      return Map_Read_Status (Status);
   exception
      when others =>
         Force_Close (Item);
         Count := 0;
         return Http_Client.Errors.Read_Failed;
   end Read_Some;


   function Read_Some_With_Timeout
     (Item       : in out Connection;
      Buffer     : out String;
      Count      : out Natural;
      Timeout_MS : Http_Client.Transports.TCP.Timeout_Milliseconds)
      return Http_Client.Errors.Result_Status
   is
      C_Count : C.int := 0;
      Status  : C.int;
   begin
      Count := 0;

      if not Is_Open (Item) then
         return Http_Client.Errors.Not_Connected;
      end if;

      if Buffer'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      Status := Bridge_Read_Some_With_Timeout
        (Handle     => Item.Handle,
         Buffer     => Buffer (Buffer'First)'Address,
         Length     => C.int (Natural'Min (Buffer'Length, Max_Bridge_IO)),
         Count      => C_Count,
         Timeout_MS => C.int (Timeout_MS));

      if Status = C_OK then
         if C_Count < 0
           or else Natural (C_Count) > Natural'Min (Buffer'Length, Max_Bridge_IO)
         then
            Force_Close (Item);
            return Http_Client.Errors.Internal_Error;
         end if;

         Count := Natural (C_Count);
      elsif Status /= C_END_OF_STREAM and then Status /= C_TIMEOUT then
         Force_Close (Item);
      end if;

      return Map_Read_Status (Status);
   exception
      when others =>
         Force_Close (Item);
         Count := 0;
         return Http_Client.Errors.Read_Failed;
   end Read_Some_With_Timeout;

   function Close
     (Item : in out Connection) return Http_Client.Errors.Result_Status is
   begin
      Force_Close (Item);
      return Http_Client.Errors.Ok;
   end Close;

end Http_Client.Transports.TLS;
