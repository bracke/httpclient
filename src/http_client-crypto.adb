with Ada.Strings.Unbounded;
with Interfaces.C;
with System;

package body Http_Client.Crypto is
   use Ada.Strings.Unbounded;
   use Interfaces.C;

   function C_Random (Out_Address : System.Address; Out_Len : Interfaces.C.size_t)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_random";

   function C_Encrypt
     (Key_Address   : System.Address; Key_Len   : Interfaces.C.size_t;
      Nonce_Address : System.Address; Nonce_Len : Interfaces.C.size_t;
      AAD_Address   : System.Address; AAD_Len   : Interfaces.C.size_t;
      Plain_Address : System.Address; Plain_Len : Interfaces.C.size_t;
      Cipher_Address : System.Address;
      Tag_Address    : System.Address; Tag_Len : Interfaces.C.size_t)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_aes256gcm_encrypt";

   function C_Decrypt
     (Key_Address   : System.Address; Key_Len   : Interfaces.C.size_t;
      Nonce_Address : System.Address; Nonce_Len : Interfaces.C.size_t;
      AAD_Address   : System.Address; AAD_Len   : Interfaces.C.size_t;
      Cipher_Address : System.Address; Cipher_Len : Interfaces.C.size_t;
      Tag_Address    : System.Address; Tag_Len : Interfaces.C.size_t;
      Plain_Address  : System.Address)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_aes256gcm_decrypt";

   function C_Digest_Hex
     (Algorithm       : Interfaces.C.int;
      Input_Address   : System.Address; Input_Len : Interfaces.C.size_t;
      Output_Address  : System.Address; Output_Len : Interfaces.C.size_t)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_digest_hex";

   function C_Digest_File_Hex
     (Algorithm       : Interfaces.C.int;
      Path_Address    : System.Address; Path_Len : Interfaces.C.size_t;
      Output_Address  : System.Address; Output_Len : Interfaces.C.size_t)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_digest_file_hex";

   function C_PBKDF2
     (Password_Address : System.Address; Password_Len : Interfaces.C.size_t;
      Salt_Address     : System.Address; Salt_Len     : Interfaces.C.size_t;
      Iterations       : Interfaces.C.int;
      Out_Address      : System.Address; Out_Len      : Interfaces.C.size_t)
      return Interfaces.C.int
      with Import, Convention => C, External_Name => "http_client_crypto_pbkdf2_sha256";

   function Random_Bytes
     (Count : Natural;
      Bytes : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      B : aliased String (1 .. Natural'Max (1, Count));
   begin
      Bytes := Null_Unbounded_String;
      if Count = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      if C_Random (B'Address, Interfaces.C.size_t (Count)) /= 1 then
         return Http_Client.Errors.Cache_Random_Failed;
      end if;
      Bytes := To_Unbounded_String (B (B'First .. B'First + Count - 1));
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Bytes := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Random_Failed;
   end Random_Bytes;

   function AES_256_GCM_Encrypt
     (Key        : String;
      Nonce      : String;
      Associated : String;
      Plaintext  : String;
      Ciphertext : out Unbounded_String;
      Tag        : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      K : aliased String := Key;
      N : aliased String := Nonce;
      A : aliased String := Associated;
      P : aliased String := Plaintext;
      C : aliased String (1 .. Natural'Max (1, Plaintext'Length));
      T : aliased String (1 .. AES_256_GCM_Tag_Length);
      A_Address : constant System.Address :=
        (if A'Length = 0 then System.Null_Address else A (A'First)'Address);
      P_Address : constant System.Address :=
        (if P'Length = 0 then System.Null_Address else P (P'First)'Address);
      C_Address : constant System.Address :=
        (if C'Length = 0 then System.Null_Address else C (C'First)'Address);
   begin
      Ciphertext := Null_Unbounded_String;
      Tag := Null_Unbounded_String;
      if Key'Length /= AES_256_GCM_Key_Length or else Nonce'Length /= AES_256_GCM_Nonce_Length then
         return Http_Client.Errors.Cache_Key_Invalid;
      end if;
      if C_Encrypt
        (K'Address, Interfaces.C.size_t (K'Length),
         N'Address, Interfaces.C.size_t (N'Length),
         A_Address, Interfaces.C.size_t (A'Length),
         P_Address, Interfaces.C.size_t (P'Length),
         C_Address, T'Address, Interfaces.C.size_t (T'Length)) /= 1
      then
         return Http_Client.Errors.Cache_Encryption_Failed;
      end if;
      if Plaintext'Length = 0 then
         Ciphertext := Null_Unbounded_String;
      else
         Ciphertext := To_Unbounded_String (C (C'First .. C'First + Plaintext'Length - 1));
      end if;
      Tag := To_Unbounded_String (T);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Ciphertext := Null_Unbounded_String;
         Tag := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Encryption_Failed;
   end AES_256_GCM_Encrypt;

   function AES_256_GCM_Decrypt
     (Key        : String;
      Nonce      : String;
      Associated : String;
      Ciphertext : String;
      Tag        : String;
      Plaintext  : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      K : aliased String := Key;
      N : aliased String := Nonce;
      A : aliased String := Associated;
      C : aliased String := Ciphertext;
      T : aliased String := Tag;
      P : aliased String (1 .. Natural'Max (1, Ciphertext'Length));
      A_Address : constant System.Address :=
        (if A'Length = 0 then System.Null_Address else A (A'First)'Address);
      C_Address : constant System.Address :=
        (if C'Length = 0 then System.Null_Address else C (C'First)'Address);
      P_Address : constant System.Address :=
        (if P'Length = 0 then System.Null_Address else P (P'First)'Address);
   begin
      Plaintext := Null_Unbounded_String;
      if Key'Length /= AES_256_GCM_Key_Length
        or else Nonce'Length /= AES_256_GCM_Nonce_Length
        or else Tag'Length /= AES_256_GCM_Tag_Length
      then
         return Http_Client.Errors.Cache_Key_Invalid;
      end if;
      if C_Decrypt
        (K'Address, Interfaces.C.size_t (K'Length),
         N'Address, Interfaces.C.size_t (N'Length),
         A_Address, Interfaces.C.size_t (A'Length),
         C_Address, Interfaces.C.size_t (C'Length),
         T'Address, Interfaces.C.size_t (T'Length),
         P_Address) /= 1
      then
         return Http_Client.Errors.Cache_Authentication_Failed;
      end if;
      if Ciphertext'Length = 0 then
         Plaintext := Null_Unbounded_String;
      else
         Plaintext := To_Unbounded_String (P (P'First .. P'First + Ciphertext'Length - 1));
      end if;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Plaintext := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Decryption_Failed;
   end AES_256_GCM_Decrypt;

   function Digest_Hex
     (Algorithm : Interfaces.C.int;
      Input     : String;
      Length    : Positive) return String
   is
      I : aliased String := Input;
      O : aliased String (1 .. Length);
      I_Address : constant System.Address :=
        (if I'Length = 0 then System.Null_Address else I (I'First)'Address);
   begin
      if C_Digest_Hex
        (Algorithm, I_Address, Interfaces.C.size_t (I'Length),
         O'Address, Interfaces.C.size_t (O'Length)) /= 1
      then
         return "";
      end if;
      return O;
   exception
      when others =>
         return "";
   end Digest_Hex;

   function Digest_MD5_Hex (Input : String) return String is
   begin
      return Digest_Hex (1, Input, 32);
   end Digest_MD5_Hex;

   function Digest_SHA256_Hex (Input : String) return String is
   begin
      return Digest_Hex (2, Input, 64);
   end Digest_SHA256_Hex;

   function Digest_File_SHA256_Hex (Path : String) return String is
      P : aliased String := Path;
      O : aliased String (1 .. 64);
      P_Address : constant System.Address :=
        (if P'Length = 0 then System.Null_Address else P (P'First)'Address);
   begin
      if C_Digest_File_Hex
        (2, P_Address, Interfaces.C.size_t (P'Length),
         O'Address, Interfaces.C.size_t (O'Length)) /= 1
      then
         return "";
      end if;
      return O;
   exception
      when others =>
         return "";
   end Digest_File_SHA256_Hex;

   function PBKDF2_HMAC_SHA256
     (Password   : String;
      Salt       : String;
      Iterations : Positive;
      Key        : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      P : aliased String := Password;
      S : aliased String := Salt;
      K : aliased String (1 .. AES_256_GCM_Key_Length);
      P_Address : constant System.Address :=
        (if P'Length = 0 then System.Null_Address else P (P'First)'Address);
      S_Address : constant System.Address :=
        (if S'Length = 0 then System.Null_Address else S (S'First)'Address);
   begin
      Key := Null_Unbounded_String;
      if Password'Length = 0 or else Salt'Length < 16 or else Iterations < 10_000 then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      if C_PBKDF2
        (P_Address, Interfaces.C.size_t (P'Length),
         S_Address, Interfaces.C.size_t (S'Length),
         Interfaces.C.int (Iterations),
         K'Address, Interfaces.C.size_t (K'Length)) /= 1
      then
         return Http_Client.Errors.Cache_KDF_Failed;
      end if;
      Key := To_Unbounded_String (K);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Key := Null_Unbounded_String;
         return Http_Client.Errors.Cache_KDF_Failed;
   end PBKDF2_HMAC_SHA256;
end Http_Client.Crypto;
