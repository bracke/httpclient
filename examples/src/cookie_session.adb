with Http_Client.Clients;
with Http_Client.Cookies;

procedure Cookie_Session is
   Jar    : aliased Http_Client.Cookies.Cookie_Jar :=
     Http_Client.Cookies.Empty_Jar;
   Config : Http_Client.Clients.Client_Configuration :=
     Http_Client.Clients.Default_Client_Configuration;
begin
   Config.Execution.Cookie_Jar := Jar'Unchecked_Access;
   Config.Execution.Strict_Cookies := True;
end Cookie_Session;
