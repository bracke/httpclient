with Ada.Calendar;

with Http_Client.Alt_Svc;
with Http_Client.Errors;

procedure Alt_Svc_Parse is
   use type Http_Client.Errors.Result_Status;
   Parsed : Http_Client.Alt_Svc.Parse_Result;
   Status : Http_Client.Errors.Result_Status;
   Index  : Natural;
begin
   Status := Http_Client.Alt_Svc.Parse_Header
     (Header      => "h3="":443""; ma=60",
      Received_At => Ada.Calendar.Clock,
      Result      => Parsed);

   if Status = Http_Client.Errors.Ok then
      Index := Http_Client.Alt_Svc.Select_First_HTTP3 (Parsed);
      if Index /= 0 then
         null;
      end if;
   end if;
end Alt_Svc_Parse;
