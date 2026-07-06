with Http_Client.Auth.Digest;
with Http_Client.Cookies;
with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Retry;
with Http_Client.URI;

package Http_Client.Status_Test_Helpers is
   procedure Assert_Response_Parse_Status
     (Input    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_Cookie_Parse_Status
     (Header_Value : String;
      Origin_URI   : Http_Client.URI.URI_Reference;
      Expected     : Http_Client.Errors.Result_Status;
      Message      : String);

   procedure Assert_Digest_Challenge_Status
     (Header_Value : String;
      Expected     : Http_Client.Errors.Result_Status;
      Message      : String);

   procedure Assert_Bearer_Proxy_Authorization_Status
     (Config   : Http_Client.Proxies.Proxy_Config;
      Token    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_Proxy_Parse_Status
     (URL      : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_SOCKS_Method_Selection_Status
     (Reply    : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_SOCKS_Connect_Request_Status
     (Target_Host : String;
      Target_Port : Http_Client.URI.TCP_Port;
      DNS_Mode    : Http_Client.Proxies.SOCKS5_DNS_Mode;
      Expected    : Http_Client.Errors.Result_Status;
      Message     : String);

   procedure Assert_Retry_After_Status
     (Options  : Http_Client.Retry.Retry_Options;
      Text     : String;
      Expected : Boolean;
      Message  : String);

   procedure Assert_Retry_After_Delay
     (Options        : Http_Client.Retry.Retry_Options;
      Text           : String;
      Expected_Pause : Http_Client.Retry.Delay_Milliseconds;
      Message        : String);
end Http_Client.Status_Test_Helpers;
