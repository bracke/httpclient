with Http_Client.Clients;
with Http_Client.Errors;
with Http_Client.Responses;
with Http_Client.URI;
with Http_Client.Types;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;

procedure Simple_Get is
   use type Http_Client.Errors.Result_Status;
   Result : Http_Client.Clients.Client_Result;
   Status : Http_Client.Errors.Result_Status;
begin
   if Argument_Count >= 1 then

      Status := Http_Client.Clients.Get (Argument(1), Result);
      if Status = Http_Client.Errors.Ok then

         --  Ada.Text_IO.Put_Line
         --     ("Redirects followed:" & Natural'Image (Result.Redirect_Count));

         --  Ada.Text_IO.Put_Line
         --     ("HTTP status:"
         --        & Http_Client.Types.Status_Code'Image
         --           (Http_Client.Responses.Status_Code (Result.Response)));

         if Http_Client.Responses.Has_Content_Type (Result.Response) then
            Ada.Text_IO.Put_Line
              ("Content-Type: "
               & Http_Client.Responses.Content_Type (Result.Response));
            Ada.Text_IO.Put_Line
              ("Media type: "
               & Http_Client.Responses.Media_Type (Result.Response));
            if Http_Client.Responses.Has_Charset (Result.Response) then
               Ada.Text_IO.Put_Line
                 ("Charset: "
                  & Http_Client.Responses.Charset (Result.Response));
            end if;
         end if;

         Ada.Text_IO.Put_Line (Http_Client.Clients.Response_Text (Result));
      else
         Ada.Text_IO.Put_Line (Status'Image);
      end if;
   else
      Ada.Text_IO.Put_Line ("simple_get <url>");
   end if;
end Simple_Get;
