with Http_Client.Errors;
with Http_Client.Multipart;

procedure Multipart_Upload is
   use type Http_Client.Errors.Result_Status;
   Form   : Http_Client.Multipart.Multipart_Form := Http_Client.Multipart.Create;
   Length : Natural;
   Status : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Multipart.Add_Field (Form, "name", "value");
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Multipart.Content_Length (Form, Length);
   end if;
end Multipart_Upload;
