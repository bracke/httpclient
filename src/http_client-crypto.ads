with Ada.Strings.Unbounded;
with Http_Client.Errors;

package Http_Client.Crypto is
   --  Release surface: implementation detail.
   --  This package is visible to other Ada units in this source tree but
   --  is not part of the stable application compatibility contract.
   --  Narrow internal cryptographic helper layer backed by OpenSSL EVP.
   --  The public cache API never exposes OpenSSL contexts or pointers.

   AES_256_GCM_Key_Length   : constant Natural := 32;
   AES_256_GCM_Nonce_Length : constant Natural := 12;
   AES_256_GCM_Tag_Length   : constant Natural := 16;

   function Random_Bytes
     (Count : Natural;
      Bytes : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Count Subprogram parameter.
   --  @param Bytes Subprogram parameter.
   --  @return Subprogram result.
   --  Fill Bytes with Count cryptographically random octets from OpenSSL.

   function AES_256_GCM_Encrypt
     (Key        : String;
      Nonce      : String;
      Associated : String;
      Plaintext  : String;
      Ciphertext : out Ada.Strings.Unbounded.Unbounded_String;
      Tag        : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Key Subprogram parameter.
   --  @param Nonce Subprogram parameter.
   --  @param Associated Subprogram parameter.
   --  @param Plaintext Subprogram parameter.
   --  @param Ciphertext Subprogram parameter.
   --  @param Tag Subprogram parameter.
   --  @return Subprogram result.
   --  Encrypt Plaintext with AES-256-GCM. Key must be exactly 32 bytes and
   --  Nonce exactly 12 bytes. Associated data is authenticated but not stored.

   function AES_256_GCM_Decrypt
     (Key        : String;
      Nonce      : String;
      Associated : String;
      Ciphertext : String;
      Tag        : String;
      Plaintext  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Key Subprogram parameter.
   --  @param Nonce Subprogram parameter.
   --  @param Associated Subprogram parameter.
   --  @param Ciphertext Subprogram parameter.
   --  @param Tag Subprogram parameter.
   --  @param Plaintext Subprogram parameter.
   --  @return Subprogram result.
   --  Decrypt and authenticate Ciphertext. Authentication failure returns
   --  Cache_Authentication_Failed and never exposes plaintext.

   function Digest_MD5_Hex (Input : String) return String;
   --  GNATdoc contract.
   --  @param Input Subprogram parameter.
   --  @return Subprogram result.
   --  Return lowercase hexadecimal MD5(Input) using OpenSSL EVP.

   function Digest_SHA256_Hex (Input : String) return String;
   --  GNATdoc contract.
   --  @param Input Subprogram parameter.
   --  @return Subprogram result.
   --  Return lowercase hexadecimal SHA-256(Input) using OpenSSL EVP.

   function Digest_File_SHA256_Hex (Path : String) return String;
   --  GNATdoc contract.
   --  @param Path Subprogram parameter.
   --  @return Subprogram result.
   --  Return lowercase hexadecimal SHA-256(file bytes) using bounded reads.

   function PBKDF2_HMAC_SHA256
     (Password   : String;
      Salt       : String;
      Iterations : Positive;
      Key        : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Password Subprogram parameter.
   --  @param Salt Subprogram parameter.
   --  @param Iterations Subprogram parameter.
   --  @param Key Subprogram parameter.
   --  @return Subprogram result.
   --  Derive a 32-byte AES-256 key using OpenSSL PBKDF2-HMAC-SHA256.
end Http_Client.Crypto;
