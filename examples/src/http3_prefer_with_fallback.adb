with Ada.Text_IO;

with Http_Client.Errors;
with Http_Client.HTTP3;
with Http_Client.Proxies;

procedure HTTP3_Prefer_With_Fallback is
   Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   Proxy   : constant Http_Client.Proxies.Proxy_Config :=
     Http_Client.Proxies.HTTP ("proxy.example", 8080);
   Status  : Http_Client.Errors.Result_Status;
begin
   --  Local-only example: prefer HTTP/3 is experimental/backend-dependent.
   --  When the HTTP/3 route is unavailable, fallback is allowed only before
   --  request bytes are sent, preserving the configured HTTP proxy route for
   --  the fallback HTTP/1.1 or HTTP/2 execution path.
   Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
   Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;

   Status := Http_Client.HTTP3.Execution_Status
     (Options          => Options,
      Proxy_Configured => Http_Client.Proxies.Is_Enabled (Proxy));

   Ada.Text_IO.Put_Line
     ("preferred experimental HTTP/3 candidate through HTTP proxy: " &
      Status'Image);

   Status := Http_Client.HTTP3.Fallback_Status
     (Options,
      Request_Bytes_Already_Sent => False);

   Ada.Text_IO.Put_Line
     ("before-send fallback policy status: " & Status'Image);
end HTTP3_Prefer_With_Fallback;
