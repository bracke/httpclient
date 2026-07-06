with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.Zlib_Decompression;

package body Http_Client.Decompression is
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;

   function Trim_Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower
        (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));
   end Trim_Lower;

   function Is_Stacked (Encoding : String) return Boolean is
   begin
      for C of Encoding loop
         if C = ',' then
            return True;
         end if;
      end loop;
      return False;
   end Is_Stacked;

   function Inflate_With_Zlib
     (Encoded_Body : String;
      Format       : Http_Client.Zlib_Decompression.Wrapper_Format;
      Decoded_Body : out Unbounded_String;
      Options      : Decompression_Options)
      return Http_Client.Errors.Result_Status is
   begin
      return Http_Client.Zlib_Decompression.Decode_All
        (Input      => Encoded_Body,
         Format     => Format,
         Max_Output => Options.Maximum_Decoded_Body_Size,
         Output     => Decoded_Body);
   exception
      when others =>
         Decoded_Body := Null_Unbounded_String;
         return Http_Client.Errors.Internal_Error;
   end Inflate_With_Zlib;

   function Default_Decoded_Response return Decoded_Response is
   begin
      return
        (Original    => Http_Client.Responses.Default_Response,
         Payload     => Null_Unbounded_String,
         Was_Decoded => False,
         Encoding    => Null_Unbounded_String);
   end Default_Decoded_Response;

   function Original_Response
     (Item : Decoded_Response) return Http_Client.Responses.Response is
   begin
      return Item.Original;
   end Original_Response;

   function Decoded_Body (Item : Decoded_Response) return String is
   begin
      return To_String (Item.Payload);
   end Decoded_Body;

   function Encoded_Body (Item : Decoded_Response) return String is
   begin
      return Http_Client.Responses.Response_Body (Item.Original);
   end Encoded_Body;

   function Decoded (Item : Decoded_Response) return Boolean is
   begin
      return Item.Was_Decoded;
   end Decoded;

   function Original_Content_Encoding (Item : Decoded_Response) return String is
   begin
      return To_String (Item.Encoding);
   end Original_Content_Encoding;

   function Supported_Accept_Encoding return String is
   begin
      return "gzip, deflate";
   end Supported_Accept_Encoding;

   function Decode_Body
     (Encoded_Body : String;
      Encoding     : String;
      Decoded_Body : out Unbounded_String;
      Options      : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status
   is
      Token : constant String := Trim_Lower (Encoding);
   begin
      Decoded_Body := Null_Unbounded_String;

      if Token'Length = 0 or else Token = "identity" then
         if Encoded_Body'Length > Options.Maximum_Decoded_Body_Size then
            return Http_Client.Errors.Decoded_Body_Too_Large;
         end if;
         Decoded_Body := To_Unbounded_String (Encoded_Body);
         return Http_Client.Errors.Ok;
      end if;

      if Is_Stacked (Token) then
         if Options.Unsupported_Policy = Leave_Encoded then
            if Encoded_Body'Length > Options.Maximum_Decoded_Body_Size then
               return Http_Client.Errors.Decoded_Body_Too_Large;
            end if;
            Decoded_Body := To_Unbounded_String (Encoded_Body);
            return Http_Client.Errors.Ok;
         else
            return Http_Client.Errors.Unsupported_Content_Encoding;
         end if;
      end if;

      if Token = "gzip" then
         return Inflate_With_Zlib
           (Encoded_Body => Encoded_Body,
            Format       => Http_Client.Zlib_Decompression.Gzip,
            Decoded_Body => Decoded_Body,
            Options      => Options);
      elsif Token = "deflate" then
         case Options.Deflate_Mode is
            when Zlib_Wrapped_Only =>
               return Inflate_With_Zlib
                 (Encoded_Body => Encoded_Body,
                  Format       => Http_Client.Zlib_Decompression.Zlib_Wrapped_Deflate,
                  Decoded_Body => Decoded_Body,
                  Options      => Options);
            when Raw_Only =>
               return Inflate_With_Zlib
                 (Encoded_Body => Encoded_Body,
                  Format       => Http_Client.Zlib_Decompression.Raw_Deflate,
                  Decoded_Body => Decoded_Body,
                  Options      => Options);
            when Auto_Zlib_Then_Raw =>
               return Inflate_With_Zlib
                 (Encoded_Body => Encoded_Body,
                  Format       =>
                    (if Http_Client.Zlib_Decompression.Looks_Like_Zlib_Header (Encoded_Body) then
                        Http_Client.Zlib_Decompression.Zlib_Wrapped_Deflate
                     else
                        Http_Client.Zlib_Decompression.Raw_Deflate),
                  Decoded_Body => Decoded_Body,
                  Options      => Options);
         end case;
      elsif Options.Unsupported_Policy = Leave_Encoded then
         if Encoded_Body'Length > Options.Maximum_Decoded_Body_Size then
            return Http_Client.Errors.Decoded_Body_Too_Large;
         end if;
         Decoded_Body := To_Unbounded_String (Encoded_Body);
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Errors.Unsupported_Content_Encoding;
      end if;
   exception
      when others =>
         Decoded_Body := Null_Unbounded_String;
         return Http_Client.Errors.Internal_Error;
   end Decode_Body;

   function No_Body_Status
     (Code : Http_Client.Types.Status_Code) return Boolean is
   begin
      return (Code >= 100 and then Code <= 199)
        or else Code = 204
        or else Code = 205
        or else Code = 304;
   end No_Body_Status;

   function Decode_Response
     (Response : Http_Client.Responses.Response;
      Result   : out Decoded_Response;
      Options  : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status is
   begin
      return Decode_Response_With_Context
        (Response         => Response,
         Request_Was_HEAD => False,
         Result           => Result,
         Options          => Options);
   end Decode_Response;

   function Decode_Response_With_Context
     (Response         : Http_Client.Responses.Response;
      Request_Was_HEAD : Boolean;
      Result           : out Decoded_Response;
      Options          : Decompression_Options := Default_Decompression_Options)
      return Http_Client.Errors.Result_Status
   is
      Headers       : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Encoding_Count : constant Natural :=
        Http_Client.Headers.Count (Headers, "Content-Encoding");
      Encoding      : constant String :=
        (if Encoding_Count = 0 then "" else Http_Client.Headers.Get (Headers, "Content-Encoding"));
      Decoded_Text  : Unbounded_String;
      Status        : Http_Client.Errors.Result_Status;
      Token         : constant String := Trim_Lower (Encoding);
   begin
      Result :=
        (Original    => Response,
         Payload     => To_Unbounded_String (Http_Client.Responses.Response_Body (Response)),
         Was_Decoded => False,
         Encoding    => To_Unbounded_String (Encoding));

      if Request_Was_HEAD
        or else No_Body_Status (Http_Client.Responses.Status_Code (Response))
      then
         return Http_Client.Errors.Ok;
      end if;

      if Encoding_Count > 1 then
         if Options.Unsupported_Policy = Leave_Encoded then
            if Http_Client.Responses.Response_Body (Response)'Length >
              Options.Maximum_Decoded_Body_Size
            then
               return Http_Client.Errors.Decoded_Body_Too_Large;
            end if;

            return Http_Client.Errors.Ok;
         else
            return Http_Client.Errors.Unsupported_Content_Encoding;
         end if;
      end if;

      Status := Decode_Body
        (Encoded_Body => Http_Client.Responses.Response_Body (Response),
         Encoding     => Encoding,
         Decoded_Body => Decoded_Text,
         Options      => Options);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Result.Payload := Decoded_Text;
      Result.Was_Decoded :=
        Token = "gzip" or else Token = "deflate";
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Result :=
           (Original    => Http_Client.Responses.Default_Response,
            Payload     => Null_Unbounded_String,
            Was_Decoded => False,
            Encoding    => Null_Unbounded_String);
         return Http_Client.Errors.Internal_Error;
   end Decode_Response_With_Context;

end Http_Client.Decompression;
