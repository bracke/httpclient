with Http_Client.DNS_SVCB;
with Http_Client.Errors;

procedure HTTPS_SVCB_Record is
   use type Http_Client.Errors.Result_Status;
   R : Http_Client.DNS_SVCB.SVCB_Record;
   Set    : Http_Client.DNS_SVCB.Record_Set;
   Status : Http_Client.Errors.Result_Status;
   Index  : Natural;
begin
   Status := Http_Client.DNS_SVCB.Parse_Record
     ("priority=1 target=. alpn=h3,h2 port=443 ttl=60", R);

   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.DNS_SVCB.Append (Set, R);
   end if;

   if Status = Http_Client.Errors.Ok then
      Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (Set);
      if Index /= 0 then
         null;
      end if;
   end if;
end HTTPS_SVCB_Record;
