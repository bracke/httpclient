with Ada.Strings.Unbounded;

with Http_Client.Diagnostics;
with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Proxies.SOCKS;
with Http_Client.Transports.TCP;
with Http_Client.URI;

package body Http_Client.Transports.SOCKS is
   use Ada.Strings.Unbounded;
   use Http_Client.Diagnostics;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Proxies.SOCKS5_Authentication_Method;
   use type Http_Client.Proxies.SOCKS5_DNS_Mode;
   use type Http_Client.Errors.Result_Status;

   function Read_Exact
     (Connection : in out Http_Client.Transports.TCP.Connection;
      Count      : Positive;
      Output     : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Buffer : String (1 .. 1);
      Got    : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      Output := Null_Unbounded_String;

      for I in 1 .. Count loop
         Status := Http_Client.Transports.TCP.Read_Some (Connection, Buffer, Got);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Got /= 1 then
            return Http_Client.Errors.SOCKS_Malformed_Reply;
         end if;
         Append (Output, Buffer (Buffer'First));
      end loop;

      return Http_Client.Errors.Ok;
   end Read_Exact;

   function Read_Connect_Reply
     (Connection : in out Http_Client.Transports.TCP.Connection;
      Reply      : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Prefix : Unbounded_String;
      Rest   : Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
      ATYP   : Natural;
      Extra  : Natural;
   begin
      Reply := Null_Unbounded_String;
      Status := Read_Exact (Connection, 4, Prefix);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      ATYP := Character'Pos (Element (Prefix, 4));
      case ATYP is
         when 1 => Extra := 6;
         when 3 =>
            Status := Read_Exact (Connection, 1, Rest);
            if Status /= Http_Client.Errors.Ok then
               return Status;
            end if;
            Append (Prefix, To_String (Rest));
            Extra := Character'Pos (Element (Rest, 1)) + 2;
         when 4 => Extra := 18;
         when others =>
            Reply := Prefix;
            return Http_Client.Errors.SOCKS_Address_Type_Unsupported;
      end case;

      Status := Read_Exact (Connection, Extra, Rest);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Append (Prefix, To_String (Rest));
      Reply := Prefix;
      return Http_Client.Errors.Ok;
   end Read_Connect_Reply;

   function Open_Tunnel
     (Connection  : in out Http_Client.Transports.TCP.Connection;
      Proxy       : Http_Client.Proxies.Proxy_Config;
      Target_Host   : String;
      Target_Port   : Http_Client.URI.TCP_Port;
      Timeouts      : Http_Client.Transports.TCP.Timeout_Config :=
        Http_Client.Transports.TCP.Default_Timeouts;
      Diagnostics   : Http_Client.Diagnostics.Context_Access := null;
      Request_ID    : Http_Client.Diagnostics.Diagnostic_ID := 0;
      Connection_ID : Http_Client.Diagnostics.Diagnostic_ID := 0)
      return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
      Bytes  : Unbounded_String;
      Reply  : Unbounded_String;

      function Auth_Method_Image return String is
      begin
         if Http_Client.Proxies.SOCKS5_Authentication (Proxy) =
           Http_Client.Proxies.SOCKS5_Username_Password
         then
            return "username-password";
         else
            return "no-authentication";
         end if;
      end Auth_Method_Image;

      function Target_Type_Image return String is
      begin
         for Ch of Target_Host loop
            if Ch = '.' then
               return "ipv4-or-domain";
            elsif Ch = ':' then
               return "ipv6-text-unsupported";
            end if;
         end loop;

         return "domain";
      end Target_Type_Image;

      function Emit_SOCKS
        (Kind    : Http_Client.Diagnostics.Event_Kind;
         Result  : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
         Message : String := "") return Http_Client.Errors.Result_Status
      is
      begin
         if Diagnostics = null then
            return Http_Client.Errors.Ok;
         end if;

         return Http_Client.Diagnostics.Emit
           (Diagnostics.all,
            (Kind          => Kind,
             Request_ID    => Request_ID,
             Connection_ID => Connection_ID,
             Result        => Result,
             Protocol      => Http_Client.Diagnostics.Protocol_HTTP_1_1,
             Message       => Http_Client.Diagnostics.To_Text (Message),
             others        => <>));
      end Emit_SOCKS;

      function Close_And_Return
        (Failure : Http_Client.Errors.Result_Status)
         return Http_Client.Errors.Result_Status
      is
         Ignored : constant Http_Client.Errors.Result_Status :=
           Http_Client.Transports.TCP.Close (Connection);
         pragma Unreferenced (Ignored);
      begin
         return Failure;
      end Close_And_Return;
   begin
      if Http_Client.Proxies.Kind (Proxy) /= Http_Client.Proxies.SOCKS5_Proxy then
         return Http_Client.Errors.Invalid_SOCKS_Proxy;
      end if;

      Status := Http_Client.Transports.TCP.Open
        (Item     => Connection,
         Host     => Http_Client.Proxies.Host (Proxy),
         Port     => Http_Client.Proxies.Port (Proxy),
         Timeouts => Timeouts);
      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status :=
              Http_Client.Transports.TCP.Close (Connection);
            pragma Unreferenced (Ignored);
         begin
            if Status = Http_Client.Errors.Connection_Failed
              or else Status = Http_Client.Errors.DNS_Failed
              or else Status = Http_Client.Errors.Timeout
            then
               return Http_Client.Errors.Proxy_Connection_Failed;
            else
               return Status;
            end if;
         end;
      end if;

      Status := Http_Client.Proxies.SOCKS.Greeting (Proxy, Bytes);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Http_Client.Transports.TCP.Write_All (Connection, To_String (Bytes));
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Emit_SOCKS
        (Http_Client.Diagnostics.SOCKS_Greeting_Sent,
         Message => "method=" & Auth_Method_Image);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Read_Exact (Connection, 2, Reply);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Http_Client.Proxies.SOCKS.Parse_Method_Selection
        (To_String (Reply), Proxy);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Emit_SOCKS
        (Http_Client.Diagnostics.SOCKS_Method_Selected,
         Message => "method=" & Auth_Method_Image);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      if Http_Client.Proxies.SOCKS5_Authentication (Proxy) =
        Http_Client.Proxies.SOCKS5_Username_Password
      then
         Status := Http_Client.Proxies.SOCKS.Username_Password_Request
           (Proxy, Bytes);
         if Status /= Http_Client.Errors.Ok then
            return Close_And_Return (Status);
         end if;

         Status := Http_Client.Transports.TCP.Write_All (Connection, To_String (Bytes));
         if Status /= Http_Client.Errors.Ok then
            return Close_And_Return (Status);
         end if;

         Status := Read_Exact (Connection, 2, Reply);
         if Status /= Http_Client.Errors.Ok then
            return Close_And_Return (Status);
         end if;

         Status := Http_Client.Proxies.SOCKS.Parse_Username_Password_Reply
           (To_String (Reply));
         declare
            Emit_Status : constant Http_Client.Errors.Result_Status :=
              Emit_SOCKS
                (Http_Client.Diagnostics.SOCKS_Authentication_Finished,
                 Result => Status,
                 Message => "method=username-password");
         begin
            if Emit_Status /= Http_Client.Errors.Ok then
               return Close_And_Return (Emit_Status);
            end if;
         end;
         if Status /= Http_Client.Errors.Ok then
            return Close_And_Return (Status);
         end if;
      end if;

      Status := Http_Client.Proxies.SOCKS.Connect_Request
        (Target_Host => Target_Host,
         Target_Port => Target_Port,
         DNS_Mode    => Http_Client.Proxies.SOCKS5_DNS_Resolution (Proxy),
         Output      => Bytes);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Http_Client.Transports.TCP.Write_All (Connection, To_String (Bytes));
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Emit_SOCKS
        (Http_Client.Diagnostics.SOCKS_CONNECT_Sent,
         Message => "target-type=" & Target_Type_Image);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Read_Connect_Reply (Connection, Reply);
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      Status := Http_Client.Proxies.SOCKS.Parse_Connect_Reply (To_String (Reply));
      declare
         Emit_Status : constant Http_Client.Errors.Result_Status :=
           Emit_SOCKS
             (Http_Client.Diagnostics.SOCKS_Reply_Received,
              Result => Status);
      begin
         if Emit_Status /= Http_Client.Errors.Ok then
            return Close_And_Return (Emit_Status);
         end if;
      end;
      if Status /= Http_Client.Errors.Ok then
         return Close_And_Return (Status);
      end if;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         declare
            Ignored : constant Http_Client.Errors.Result_Status :=
              Http_Client.Transports.TCP.Close (Connection);
            pragma Unreferenced (Ignored);
         begin
            return Http_Client.Errors.Internal_Error;
         end;
   end Open_Tunnel;

end Http_Client.Transports.SOCKS;
