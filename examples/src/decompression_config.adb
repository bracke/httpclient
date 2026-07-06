with Ada.Strings.Unbounded;

with Http_Client.Decompression;
with Http_Client.Errors;

procedure Decompression_Config is
   use type Http_Client.Errors.Result_Status;
   Options : Http_Client.Decompression.Decompression_Options :=
     Http_Client.Decompression.Default_Decompression_Options;
   B : Ada.Strings.Unbounded.Unbounded_String;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Maximum_Decoded_Body_Size := 1_048_576;
   Options.Unsupported_Policy := Http_Client.Decompression.Leave_Encoded;

   Status := Http_Client.Decompression.Decode_Body
     (Encoded_Body => "already decoded payload",
      Encoding     => "identity",
      Decoded_Body => B,
      Options      => Options);

   if Status /= Http_Client.Errors.Ok then
      null;
   end if;
end Decompression_Config;
