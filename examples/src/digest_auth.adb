with Ada.Strings.Unbounded;
with Http_Client.Auth.Digest;
with Http_Client.Errors;

procedure Digest_Auth is
   use type Http_Client.Errors.Result_Status;
   Challenge : Http_Client.Auth.Digest.Challenge;
   Header    : Ada.Strings.Unbounded.Unbounded_String;
   Status    : Http_Client.Errors.Result_Status;
begin
   Status := Http_Client.Auth.Digest.Parse_Challenge
     ("Digest realm=""example"", nonce=""abcdef"", algorithm=SHA-256, qop=""auth""",
      Challenge);
   if Status = Http_Client.Errors.Ok then
      Status := Http_Client.Auth.Digest.Generate_Response
        (Challenge, "user", "password", "GET", "/resource", 1,
         Http_Client.Auth.Digest.CNonce_From_Octets ("12345678"), Header);
   end if;
end Digest_Auth;
