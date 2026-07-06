with Ada.Strings.Unbounded;

with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.Proxy_Discovery;
with Http_Client.URI;

procedure PAC_WPAD_Config is
   use type Http_Client.Errors.Result_Status;
   Target  : Http_Client.URI.URI_Reference;
   Options : Http_Client.Proxy_Discovery.Discovery_Options :=
     Http_Client.Proxy_Discovery.Default_Discovery_Options;
   Config  : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
   Proxy   : Http_Client.Proxies.Proxy_Config;
   Status  : Http_Client.Errors.Result_Status;
   Script  : constant String :=
     "function FindProxyForURL(url, host) { return ""PROXY proxy.example:8080; DIRECT""; }";
begin
   Options.Enabled := True;
   Options.Failure := Http_Client.Proxy_Discovery.Fail_Closed;
   Options.Precedence := Http_Client.Proxy_Discovery.Explicit_Proxy_Wins;

   Config.Proxy_Discovery := Options;
   Config.Proxy_PAC_Script := Ada.Strings.Unbounded.To_Unbounded_String (Script);

   Status := Http_Client.Clients.Validate (Config);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.URI.Parse ("http://example.com/resource", Target);
   end if;

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Proxy_Discovery.Resolve_PAC_Script
        (Script, Target, Options, Proxy);
   end if;
end PAC_WPAD_Config;
