with Http_Client.Errors;

procedure Status_Categories is
   use type Http_Client.Errors.Result_Category;
   Category : constant Http_Client.Errors.Result_Category :=
     Http_Client.Errors.Category (Http_Client.Errors.HTTP3_Unsupported);
begin
   if Category = Http_Client.Errors.HTTP3_Category then
      null;
   end if;
end Status_Categories;
