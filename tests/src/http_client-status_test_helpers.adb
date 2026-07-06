with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Auth.Bearer;
with Http_Client.Proxies.SOCKS;
with Http_Client.Responses;

package body Http_Client.Status_Test_Helpers is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;

   procedure Assert_Response_Parse_Status
     (Input    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Response : Http_Client.Responses.Response;
      pragma Warnings (Off, Response);
   begin
      Assert
        (Http_Client.Responses.Parse_Response (Input, Response) = Expected,
         Message);
   end Assert_Response_Parse_Status;

   procedure Assert_Cookie_Parse_Status
     (Header_Value : String;
      Origin_URI   : Http_Client.URI.URI_Reference;
      Expected     : Http_Client.Errors.Result_Status;
      Message      : String)
   is
      Cookie : Http_Client.Cookies.Cookie;
      pragma Warnings (Off, Cookie);
   begin
      Assert
        (Http_Client.Cookies.Parse_Set_Cookie
           (Header_Value, Origin_URI, Cookie) = Expected,
         Message);
   end Assert_Cookie_Parse_Status;

   procedure Assert_Digest_Challenge_Status
     (Header_Value : String;
      Expected     : Http_Client.Errors.Result_Status;
      Message      : String)
   is
      Challenge : Http_Client.Auth.Digest.Challenge;
      pragma Warnings (Off, Challenge);
   begin
      Assert
        (Http_Client.Auth.Digest.Parse_Challenge (Header_Value, Challenge)
         = Expected,
         Message);
   end Assert_Digest_Challenge_Status;

   procedure Assert_Bearer_Proxy_Authorization_Status
     (Config   : Http_Client.Proxies.Proxy_Config;
      Token    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Auth_Proxy : Http_Client.Proxies.Proxy_Config;
      pragma Warnings (Off, Auth_Proxy);
   begin
      Assert
        (Http_Client.Auth.Bearer.Set_Bearer_Proxy_Authorization
           (Config, Token, Auth_Proxy) = Expected,
         Message);
   end Assert_Bearer_Proxy_Authorization_Status;

   procedure Assert_Proxy_Parse_Status
     (URL      : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Proxy : Http_Client.Proxies.Proxy_Config;
      pragma Warnings (Off, Proxy);
   begin
      Assert
        (Http_Client.Proxies.Parse (URL, Proxy) = Expected,
         Message);
   end Assert_Proxy_Parse_Status;

   procedure Assert_SOCKS_Method_Selection_Status
     (Reply    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Config : Http_Client.Proxies.Proxy_Config;
      pragma Warnings (Off, Config);
   begin
      Assert
        (Http_Client.Proxies.SOCKS.Parse_Method_Selection (Reply, Config)
         = Expected,
         Message);
   end Assert_SOCKS_Method_Selection_Status;

   procedure Assert_SOCKS_Connect_Request_Status
     (Target_Host : String;
      Target_Port : Http_Client.URI.TCP_Port;
      DNS_Mode    : Http_Client.Proxies.SOCKS5_DNS_Mode;
      Expected    : Http_Client.Errors.Result_Status;
      Message     : String)
   is
      Output : Ada.Strings.Unbounded.Unbounded_String;
      pragma Warnings (Off, Output);
   begin
      Assert
        (Http_Client.Proxies.SOCKS.Connect_Request
           (Target_Host, Target_Port, DNS_Mode, Output) = Expected,
         Message);
   end Assert_SOCKS_Connect_Request_Status;

   procedure Assert_Retry_After_Status
     (Options  : Http_Client.Retry.Retry_Options;
      Text     : String;
      Expected : Boolean;
      Message  : String)
   is
      Pause : Http_Client.Retry.Delay_Milliseconds;
      pragma Warnings (Off, Pause);
   begin
      Assert
        (Http_Client.Retry.Retry_After_Delay (Text, Options, Pause)
         = Expected,
         Message);
   end Assert_Retry_After_Status;

   procedure Assert_Retry_After_Delay
     (Options        : Http_Client.Retry.Retry_Options;
      Text           : String;
      Expected_Pause : Http_Client.Retry.Delay_Milliseconds;
      Message        : String)
   is
      Pause : Http_Client.Retry.Delay_Milliseconds;
   begin
      Assert
        (Http_Client.Retry.Retry_After_Delay (Text, Options, Pause),
         Message);
      Assert
        (Pause = Expected_Pause,
         Message & " should return expected delay");
   end Assert_Retry_After_Delay;
end Http_Client.Status_Test_Helpers;
