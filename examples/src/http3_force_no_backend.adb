with Ada.Text_IO;

with Http_Client.Errors;
with Http_Client.HTTP3;

procedure HTTP3_Force_No_Backend is
   use type Http_Client.Errors.Result_Status;

   Options : Http_Client.HTTP3.HTTP3_Options := Http_Client.HTTP3.Default_HTTP3_Options;
   Status  : Http_Client.Errors.Result_Status;
begin
   --  HTTP/3 is experimental/backend-dependent; default QUIC backend is unavailable.
   Options.Mode := Http_Client.HTTP3.HTTP3_Required;
   Options.Fallback := Http_Client.HTTP3.Fallback_Disallowed;

   Status := Http_Client.HTTP3.Execution_Status (Options);
   if Status = Http_Client.Errors.HTTP3_Unsupported
     or else Status = Http_Client.Errors.QUIC_Unsupported
   then
      Ada.Text_IO.Put_Line ("forced HTTP/3 failed deterministically without fallback");
   elsif Status /= Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line ("forced HTTP/3 failed with deterministic status");
   else
      Ada.Text_IO.Put_Line ("HTTP/3 backend is available in this build");
   end if;
end HTTP3_Force_No_Backend;
