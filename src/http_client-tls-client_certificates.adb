with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Http_Client.TLS.Client_Certificates is
   use Ada.Strings.Unbounded;
   use type Http_Client.URI.TCP_Port;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Contains_NUL (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Ch = Character'Val (0) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_NUL;

   function Has_NUL (Value : Unbounded_String) return Boolean is
   begin
      return Contains_NUL (To_String (Value));
   end Has_NUL;

   function Make_ID
     (Certificate_File : String;
      Private_Key_File : String) return Natural
   is
      Text : constant String := Certificate_File & Character'Val (10) & Private_Key_File;
      Hash : Long_Long_Integer := 2_166_136_261 mod Long_Long_Integer (Natural'Last);
   begin
      for Ch of Text loop
         Hash := (Hash * 131 + Long_Long_Integer (Character'Pos (Ch))) mod Long_Long_Integer (Natural'Last);
      end loop;

      if Hash = 0 then
         return 1;
      else
         return Natural (Hash);
      end if;
   end Make_ID;

   function From_PEM_Files
     (Certificate_File : String;
      Private_Key_File : String;
      Passphrase       : String := "";
      Has_Passphrase   : Boolean := False;
      Allow_Any_Origin : Boolean := False) return Client_Certificate
   is
   begin
      return
        (Enabled          => True,
         Certificate_File => To_Unbounded_String (Certificate_File),
         Private_Key_File => To_Unbounded_String (Private_Key_File),
         Passphrase       => To_Unbounded_String (Passphrase),
         Has_Passphrase   => Has_Passphrase or else Passphrase'Length > 0,
         Allow_Any_Origin => Allow_Any_Origin,
         Scope            => (others => <>),
         Identifier       => Make_ID (Certificate_File, Private_Key_File));
   end From_PEM_Files;

   function For_Origin
     (Credential : Client_Certificate;
      URI        : Http_Client.URI.URI_Reference) return Client_Certificate
   is
      Result : Client_Certificate := Credential;
   begin
      if not Credential.Enabled
        or else not Http_Client.URI.Is_Parsed (URI)
        or else not Http_Client.URI.Requires_TLS (URI)
      then
         return No_Client_Certificate;
      end if;

      Result.Allow_Any_Origin := False;
      Result.Scope :=
        (Scheme => To_Unbounded_String (Lower (Http_Client.URI.Scheme (URI))),
         Host   => To_Unbounded_String (Lower (Http_Client.URI.Host (URI))),
         Port   => Http_Client.URI.Effective_Port (URI));
      return Result;
   exception
      when others =>
         return No_Client_Certificate;
   end For_Origin;

   function Is_Configured (Credential : Client_Certificate) return Boolean is
   begin
      return Credential.Enabled;
   end Is_Configured;

   function Matches_Origin
     (Credential : Client_Certificate;
      Scheme     : String;
      Host       : String;
      Port       : Http_Client.URI.TCP_Port) return Boolean
   is
   begin
      if not Credential.Enabled then
         return False;
      elsif Credential.Allow_Any_Origin then
         return Lower (Scheme) = "https";
      else
         return To_String (Credential.Scope.Scheme) = Lower (Scheme)
           and then To_String (Credential.Scope.Host) = Lower (Host)
           and then Credential.Scope.Port = Port;
      end if;
   end Matches_Origin;

   function Matches
     (Credential : Client_Certificate;
      URI        : Http_Client.URI.URI_Reference) return Boolean
   is
   begin
      return Http_Client.URI.Is_Parsed (URI)
        and then Matches_Origin
          (Credential,
           Http_Client.URI.Scheme (URI),
           Http_Client.URI.Host (URI),
           Http_Client.URI.Effective_Port (URI));
   exception
      when others =>
         return False;
   end Matches;

   function Credential_ID (Credential : Client_Certificate) return Natural is
   begin
      if Credential.Enabled then
         return Credential.Identifier;
      else
         return 0;
      end if;
   end Credential_ID;

   function Validate
     (Credential : Client_Certificate) return Http_Client.Errors.Result_Status
   is
      Has_Cert : constant Boolean := Length (Credential.Certificate_File) > 0;
      Has_Key  : constant Boolean := Length (Credential.Private_Key_File) > 0;
   begin
      if not Credential.Enabled then
         return Http_Client.Errors.Ok;
      end if;

      if Has_NUL (Credential.Certificate_File)
        or else Has_NUL (Credential.Private_Key_File)
        or else Has_NUL (Credential.Passphrase)
        or else Has_NUL (Credential.Scope.Scheme)
        or else Has_NUL (Credential.Scope.Host)
      then
         return Http_Client.Errors.TLS_Client_Certificate_Configuration_Invalid;
      end if;

      if not Has_Cert or else not Has_Key then
         return Http_Client.Errors.TLS_Client_Certificate_Configuration_Invalid;
      end if;

      if not Credential.Allow_Any_Origin then
         if To_String (Credential.Scope.Scheme) /= "https"
           or else Length (Credential.Scope.Host) = 0
         then
            return Http_Client.Errors.TLS_Client_Certificate_Scope_Mismatch;
         end if;
      end if;

      return Http_Client.Errors.Ok;
   end Validate;

end Http_Client.TLS.Client_Certificates;
