with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Proxies;
with Http_Client.Request_Bodies;
with Http_Client.Requests;
package body Http_Client.Auth is
   use type Http_Client.Errors.Result_Status;

   Alphabet : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   function Is_Control (C : Character) return Boolean is
      Code : constant Natural := Character'Pos (C);
   begin
      return Code < 32 or else Code = 127 or else (Code >= 128 and then Code <= 159);
   end Is_Control;

   function Contains_Control (Text : String) return Boolean is
   begin
      for C of Text loop
         if Is_Control (C) then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Control;

   function Is_Valid_Basic_Credentials
     (Username : String;
      Password : String) return Boolean
   is
   begin
      if Username'Length = 0 then
         return False;
      end if;

      for C of Username loop
         if C = ':' or else Is_Control (C) then
            return False;
         end if;
      end loop;

      return not Contains_Control (Password);
   end Is_Valid_Basic_Credentials;

   function Base64_Encode (Input : String) return String is
   begin
      if Input'Length = 0 then
         return "";
      end if;

      declare
         Output_Length : constant Positive := ((Input'Length + 2) / 3) * 4;
         Result        : String (1 .. Output_Length);
         Input_Index   : Natural := Input'First;
         Output_Index  : Natural := Result'First;
      begin
         while Input_Index <= Input'Last loop
            declare
               Remaining : constant Natural := Input'Last - Input_Index + 1;
               B1        : constant Natural := Character'Pos (Input (Input_Index));
               B2        : constant Natural :=
                 (if Remaining >= 2 then Character'Pos (Input (Input_Index + 1)) else 0);
               B3        : constant Natural :=
                 (if Remaining >= 3 then Character'Pos (Input (Input_Index + 2)) else 0);
               Twenty_Four : constant Natural := B1 * 65_536 + B2 * 256 + B3;
            begin
               Result (Output_Index) :=
                 Alphabet ((Twenty_Four / 262_144) mod 64 + Alphabet'First);
               Result (Output_Index + 1) :=
                 Alphabet ((Twenty_Four / 4_096) mod 64 + Alphabet'First);

               if Remaining >= 2 then
                  Result (Output_Index + 2) :=
                    Alphabet ((Twenty_Four / 64) mod 64 + Alphabet'First);
               else
                  Result (Output_Index + 2) := '=';
               end if;

               if Remaining >= 3 then
                  Result (Output_Index + 3) :=
                    Alphabet (Twenty_Four mod 64 + Alphabet'First);
               else
                  Result (Output_Index + 3) := '=';
               end if;

               Input_Index := Input_Index + 3;
               Output_Index := Output_Index + 4;
            end;
         end loop;

         return Result;
      end;
   end Base64_Encode;

   function Basic_Authorization
     (Username : String;
      Password : String;
      Value    : out String) return Http_Client.Errors.Result_Status
   is
   begin
      if not Is_Valid_Basic_Credentials (Username, Password) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      declare
         Generated : constant String :=
           Basic_Authorization_Value (Username, Password);
      begin
         if Value'Length < Generated'Length then
            return Http_Client.Errors.Invalid_Header;
         end if;

         Value (Value'First .. Value'First + Generated'Length - 1) :=
           Generated;

         if Value'Length > Generated'Length then
            Value (Value'First + Generated'Length .. Value'Last) :=
              (others => ' ');
         end if;
      end;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Basic_Authorization;

   function Basic_Authorization_Value
     (Username : String;
      Password : String) return String
   is
   begin
      return "Basic " & Base64_Encode (Username & ":" & Password);
   end Basic_Authorization_Value;

   function Basic_Proxy_Authorization_Value
     (Username : String;
      Password : String) return String
   is
   begin
      return Basic_Authorization_Value (Username, Password);
   end Basic_Proxy_Authorization_Value;

   function Set_Basic_Authorization
     (Request  : Http_Client.Requests.Request;
      Username : String;
      Password : String;
      Result   : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Result := Http_Client.Requests.Default_Request;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if not Is_Valid_Basic_Credentials (Username, Password) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      Headers := Http_Client.Requests.Headers (Request);
      Status := Http_Client.Headers.Set
        (Headers,
         "Authorization",
         Basic_Authorization_Value (Username, Password));

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

      return Http_Client.Requests.Set_Body
        (Result,
         Http_Client.Requests.Request_Body (Request));
   end Set_Basic_Authorization;

   function Clear_Authorization
     (Request : Http_Client.Requests.Request;
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

      Headers := Http_Client.Requests.Headers (Request);
      Status := Http_Client.Headers.Remove (Headers, "Authorization");

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

      return Http_Client.Requests.Set_Body
        (Result,
         Http_Client.Requests.Request_Body (Request));
   end Clear_Authorization;

   function Set_Basic_Proxy_Authorization
     (Config   : Http_Client.Proxies.Proxy_Config;
      Username : String;
      Password : String;
      Result   : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
   begin
      Result := Config;

      if not Is_Valid_Basic_Credentials (Username, Password) then
         return Http_Client.Errors.Invalid_Credentials;
      end if;

      return Http_Client.Proxies.With_Proxy_Authorization
        (Config,
         Basic_Proxy_Authorization_Value (Username, Password),
         Result);
   end Set_Basic_Proxy_Authorization;

end Http_Client.Auth;
