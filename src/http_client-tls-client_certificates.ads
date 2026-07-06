with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.URI;

package Http_Client.TLS.Client_Certificates is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit client-certificate credential configuration for mutual TLS.
   --
   --  This package supports PEM certificate and PEM private-key files supplied by
   --  the caller. The library does not search the filesystem, inspect OS
   --  keychains, use hardware tokens, prompt for passwords, discover browser
   --  identities, or send any client certificate unless a credential is
   --  configured explicitly. PKCS#12, automatic certificate selection,
   --  renegotiation-based client authentication, OS credential stores, and
   --  hardware-token integrations are unsupported in this release.
   --
   --  Encrypted private keys may be attempted only when a passphrase is
   --  supplied explicitly in this record. A non-empty Passphrase value marks
   --  the passphrase as supplied automatically; Has_Passphrase is used only
   --  to express an explicitly supplied empty passphrase. No interactive callback is installed;
   --  OpenSSL key-load failures caused by missing or wrong passphrases are
   --  mapped to deterministic passphrase statuses where OpenSSL exposes a
   --  recognizable reason.
   --  Temporary passphrase handling is best-effort only; Ada strings and
   --  OpenSSL internals may retain copies, so this release does not claim
   --  hardened process-memory secret isolation.

   type Origin_Scope is record
      Scheme : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Host   : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Port   : Http_Client.URI.TCP_Port := 443;
   end record;
   --  Normalized origin scope for a client certificate.
   --
   --  @field Scheme Usually https. Empty means no concrete origin.
   --  @field Host Lowercase origin host.
   --  @field Port Effective origin port.

   type Client_Certificate is record
      Enabled          : Boolean := False;
      Certificate_File : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Private_Key_File : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Passphrase       : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Has_Passphrase   : Boolean := False;
      Allow_Any_Origin : Boolean := False;
      Scope            : Origin_Scope;
      Identifier       : Natural := 0;
   end record;
   --  Caller-supplied mutual-TLS credential configuration.
   --
   --  @field Enabled True only for an explicit client certificate.
   --  @field Certificate_File PEM client certificate path. The file may
   --         contain the leaf certificate followed by intermediate certificates
   --         in PEM order accepted by OpenSSL; This package does not expose a
   --         separate PKCS#12 or certificate-selection API.
   --  @field Private_Key_File PEM private-key path matching Certificate_File.
   --  @field Passphrase Optional explicit private-key passphrase. It is never
   --         obtained from the terminal, environment, keychain, or password
   --         manager.
   --  @field Has_Passphrase Distinguishes an explicit empty passphrase from no
   --         passphrase. Constructors also set it automatically for any
   --         non-empty Passphrase.
   --  @field Allow_Any_Origin Broad scope flag. False is preferred; True means
   --         the caller explicitly allows this credential on any HTTPS origin
   --         using the associated TLS options.
   --  @field Scope Concrete origin scope used when Allow_Any_Origin is False.
   --  @field Identifier Stable non-secret identity assigned by constructors for
   --         connection-pool and HTTP/2 compatibility checks. It is not a
   --         fingerprint and must not be treated as certificate metadata.

   No_Client_Certificate : constant Client_Certificate := (others => <>);
   --  Disabled client-certificate configuration.

   function From_PEM_Files
     (Certificate_File : String;
      Private_Key_File : String;
      Passphrase       : String := "";
      Has_Passphrase   : Boolean := False;
      Allow_Any_Origin : Boolean := False) return Client_Certificate;
   --  GNATdoc contract.
   --  @param Certificate_File Subprogram parameter.
   --  @param Private_Key_File Subprogram parameter.
   --  @param Passphrase Subprogram parameter.
   --  @param Has_Passphrase Subprogram parameter.
   --  @param Allow_Any_Origin Subprogram parameter.
   --  @return Subprogram result.
   --  Build an explicit PEM-file credential configuration.
   --
   --  This function records caller-provided paths and assigns a non-secret
   --  stable identifier. A non-empty Passphrase automatically enables
   --  passphrase mode; pass Has_Passphrase => True to deliberately supply an
   --  empty passphrase. It does not perform network I/O or send credentials.

   function For_Origin
     (Credential : Client_Certificate;
      URI        : Http_Client.URI.URI_Reference) return Client_Certificate;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @return Subprogram result.
   --  Return Credential restricted to URI's https origin.
   --
   --  Invalid or non-HTTPS URIs return a disabled credential. Redirect handling
   --  must recompute this match for every hop.

   function Is_Configured (Credential : Client_Certificate) return Boolean;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only when a client certificate is explicitly enabled.

   function Matches
     (Credential : Client_Certificate;
      URI        : Http_Client.URI.URI_Reference) return Boolean;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Credential may be used for URI.

   function Matches_Origin
     (Credential : Client_Certificate;
      Scheme     : String;
      Host       : String;
      Port       : Http_Client.URI.TCP_Port) return Boolean;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @param Scheme Subprogram parameter.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Credential may be used for the normalized origin.

   function Credential_ID (Credential : Client_Certificate) return Natural;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @return Subprogram result.
   --  Return the non-secret stable identity used for transport compatibility.

   function Validate
     (Credential : Client_Certificate) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Credential Subprogram parameter.
   --  @return Subprogram result.
   --  Validate local credential configuration without opening a connection.
   --
   --  Embedded NULs, missing certificate/key pairing, missing scope for
   --  non-broad credentials, and non-HTTPS scoped credentials fail
   --  deterministically. PEM syntax, encrypted-key passphrase validity,
   --  certificate/private-key consistency, and unsupported key formats are
   --  checked by the TLS transport when OpenSSL loads the credential before
   --  the HTTP request bytes are sent. Missing and invalid private-key
   --  passphrases are reported separately when OpenSSL exposes a recognizable
   --  reason; otherwise the failure remains TLS_Client_Key_Load_Failed.

end Http_Client.TLS.Client_Certificates;
