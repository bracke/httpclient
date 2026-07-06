with Http_Client.Errors;
with Http_Client.HTTP2;

procedure Enable_HTTP2 is
   use type Http_Client.Errors.Result_Status;
   Options : Http_Client.HTTP2.HTTP2_Options :=
     Http_Client.HTTP2.Default_HTTP2_Options;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
   Options.Enable_Multiplexing := True;
   Status := Http_Client.HTTP2.Validate (Options);
end Enable_HTTP2;
