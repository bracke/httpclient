with Http_Client.Errors;
with Http_Client.QUIC;

package body Http_Client.HTTP3
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.QUIC.Backend_Availability;

   function Validate (Options : HTTP3_Options)
      return Http_Client.Errors.Result_Status is
      QS : constant Http_Client.Errors.Result_Status :=
        Http_Client.QUIC.Validate (Options.QUIC);
   begin
      if QS /= Http_Client.Errors.Ok then
         return QS;
      elsif Options.Max_Frame_Size = 0
        or else Options.Max_Frame_Size > 16#3FFF_FFFF#
        or else Options.Max_Header_List_Size = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Enable_Server_Push then
         return Http_Client.Errors.HTTP3_Unsupported;
      elsif Options.Enable_Zero_RTT then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.QUIC.Enable_Zero_RTT then
         return Http_Client.Errors.Invalid_Configuration;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Validate;

   function ALPN_Token (Options : HTTP3_Options) return String is
   begin
      if Options.Mode = HTTP3_Disabled then
         return "";
      else
         return "h3";
      end if;
   end ALPN_Token;

   function Normalize_ALPN_Selected (Token : String) return Selected_Protocol is
   begin
      if Token = "h3" then
         return Protocol_HTTP_3;
      elsif Token = "h2" then
         return Protocol_HTTP_2;
      elsif Token = "http/1.1" then
         return Protocol_HTTP_1_1;
      elsif Token'Length = 0 then
         return Protocol_None;
      else
         return Protocol_Unknown;
      end if;
   end Normalize_ALPN_Selected;

   function Execution_Status
     (Options                : HTTP3_Options;
      Proxy_Configured       : Boolean := False;
      SOCKS_Configured       : Boolean := False;
      Client_Certificate_Configured : Boolean := False)
      return Http_Client.Errors.Result_Status is
      VS : constant Http_Client.Errors.Result_Status := Validate (Options);
   begin
      if VS /= Http_Client.Errors.Ok then
         return VS;
      elsif Options.Mode = HTTP3_Disabled then
         return Http_Client.Errors.HTTP3_Unsupported;
      elsif Proxy_Configured or else SOCKS_Configured then
         return Http_Client.Errors.HTTP3_Proxy_Unsupported;
      elsif Client_Certificate_Configured then
         return Http_Client.Errors.TLS_Client_Certificate_Unsupported;
      elsif Options.QUIC.Backend = Http_Client.QUIC.Backend_Unavailable then
         return Http_Client.Errors.QUIC_Unsupported;
      else
         --  A selected backend makes HTTP/3 a valid execution candidate.
         --  Backend-specific open/handshake failures are mapped by
         --  Http_Client.QUIC.Open and the HTTP/3 execution package.
         return Http_Client.Errors.Ok;
      end if;
   end Execution_Status;

   function Fallback_Status
     (Options                  : HTTP3_Options;
      Request_Bytes_Already_Sent : Boolean)
      return Http_Client.Errors.Result_Status is
   begin
      if Options.Fallback = Fallback_Before_Send
        and then not Request_Bytes_Already_Sent
      then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Errors.HTTP3_Fallback_Disallowed;
      end if;
   end Fallback_Status;

end Http_Client.HTTP3;
