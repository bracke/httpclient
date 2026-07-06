with Ada.Calendar;

with Http_Client.Errors;
with Http_Client.HTTP3;
with Http_Client.Protocol_Discovery;
with Http_Client.Proxies;
with Http_Client.URI;

procedure Protocol_Discovery_Config is
   use type Http_Client.Errors.Result_Status;
   Origin    : Http_Client.URI.URI_Reference;
   Cache     : Http_Client.Protocol_Discovery.Discovery_Cache;
   Options   : Http_Client.Protocol_Discovery.Discovery_Options :=
     Http_Client.Protocol_Discovery.Default_Discovery_Options;
   HTTP3     : Http_Client.HTTP3.HTTP3_Options :=
     Http_Client.HTTP3.Default_HTTP3_Options;
   Selection : Http_Client.Protocol_Discovery.Discovery_Selection;
   Status    : Http_Client.Errors.Result_Status;
begin
   Options.Enable_Alt_Svc := True;
   Options.Allow_HTTP3_Discovery := True;
   HTTP3.Mode := Http_Client.HTTP3.HTTP3_Allowed;

   Http_Client.Protocol_Discovery.Initialize (Cache, Options);
   Status := Http_Client.URI.Parse ("https://example.com/", Origin);

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Protocol_Discovery.Accept_Alt_Svc
        (Cache                        => Cache,
         Origin                       => Origin,
         Header                       => "h3="":443""; ma=60",
         Received_At                  => Ada.Calendar.Clock,
         Options                      => Options,
         From_Verified_HTTPS_Response => True);
   end if;

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Protocol_Discovery.Selection
        (Cache     => Cache,
         Origin    => Origin,
         Options   => Options,
         HTTP3     => HTTP3,
         Proxy     => Http_Client.Proxies.No_Proxy_Config,
         Now       => Ada.Calendar.Clock,
         Selection => Selection);
   end if;
end Protocol_Discovery_Config;
