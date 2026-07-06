with Http_Client.Headers;

package body Http_Client.Auth.Bearer is
   use type Http_Client.Errors.Result_Status;

   Max_Token_Length : constant Natural := 8_186;

   function Is_Control (C : Character) return Boolean is
      Code : constant Natural := Character'Pos (C);
   begin
      return Code < 32 or else Code = 127 or else (Code >= 128 and then Code <= 159);
   end Is_Control;

   function Is_Valid_Token (Token : String) return Boolean is
   begin
      if Token'Length = 0 or else Token'Length > Max_Token_Length then
         return False;
      end if;

      for C of Token loop
         if Is_Control (C) then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Token;

   function Authorization_Value (Token : String) return String is
   begin
      return "Bearer " & Token;
   end Authorization_Value;

   function Proxy_Authorization_Value (Token : String) return String is
   begin
      return Authorization_Value (Token);
   end Proxy_Authorization_Value;

   function Bearer_Authorization
     (Token : String;
      Value : out String) return Http_Client.Errors.Result_Status
   is
   begin
      if not Is_Valid_Token (Token) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      declare
         Generated : constant String := Authorization_Value (Token);
      begin
         if Value'Length < Generated'Length then
            return Http_Client.Errors.Invalid_Header;
         end if;
         Value (Value'First .. Value'First + Generated'Length - 1) := Generated;
         if Value'Length > Generated'Length then
            Value (Value'First + Generated'Length .. Value'Last) := (others => ' ');
         end if;
      end;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Bearer_Authorization;

   function Set_Bearer_Authorization
     (Request : Http_Client.Requests.Request;
      Token   : String;
      Result  : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Result := Http_Client.Requests.Default_Request;
      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;
      if not Is_Valid_Token (Token) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      Headers := Http_Client.Requests.Headers (Request);
      Status := Http_Client.Headers.Set (Headers, "Authorization", Authorization_Value (Token));
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Create
        (Method    => Http_Client.Requests.Method (Request),
         URI       => Http_Client.Requests.URI (Request),
         Item      => Result,
         Headers   => Headers,
         Payload   => Http_Client.Requests.Payload (Request),
         Auto_Host => False);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Requests.Set_Body (Result, Http_Client.Requests.Request_Body (Request));
   end Set_Bearer_Authorization;

   function Clear_Authorization
     (Request : Http_Client.Requests.Request;
      Result  : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
   begin
      return Http_Client.Auth.Clear_Authorization (Request, Result);
   end Clear_Authorization;

   function Set_Bearer_Proxy_Authorization
     (Config : Http_Client.Proxies.Proxy_Config;
      Token  : String;
      Result : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
   begin
      Result := Config;
      if not Is_Valid_Token (Token) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;
      return Http_Client.Proxies.With_Proxy_Authorization
        (Config, Proxy_Authorization_Value (Token), Result);
   end Set_Bearer_Proxy_Authorization;
end Http_Client.Auth.Bearer;
