with Ada.Calendar;
with Ada.Strings.Unbounded;

with Http_Client.Cache;
with Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Responses;

package Http_Client.Cache.Persistent is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit opt-in file-backed persistent HTTP cache storage.
   --
   --  This package is a durability backend for the stable cache policy. It
   --  does not define independent HTTP cacheability semantics: callers store
   --  and look up complete buffered responses through the same conservative
   --  rules used by Http_Client.Cache. Persistent files are ordinary local
   --  files. Unless Encrypt_At_Rest is explicitly configured, files may contain
   --  response headers, persisted Vary request-header dimensions, and bodies.
   --  When Encrypt_At_Rest is enabled, metadata and body payloads are stored in
   --  versioned AES-256-GCM envelopes with OpenSSL-generated random nonces and
   --  authenticated associated data covering envelope version, algorithm, file
   --  kind, and opaque file name. At-rest encryption protects cache files only
   --  within the limits of caller-controlled keys and process memory; it does
   --  not protect network traffic beyond TLS, diagnostics that callers make
   --  unsafe, or user-managed key material.
   --
   --  Cache directories are caller supplied. No directory or cache file is
   --  created unless Open is called with Create_If_Missing set to True or a
   --  later Store succeeds on an opened cache. Encrypted stores write a small
   --  encrypted verifier file so wrong raw keys fail deterministically during
   --  Open when the verifier is present; old encrypted directories without a
   --  verifier authenticate an existing metadata envelope before the verifier
   --  is created. The implementation uses safe
   --  hash-derived filenames based on the origin key and active Vary dimensions,
   --  bounded metadata/body sizes, temporary files in
   --  the configured directory, and same-directory rename replacement. Open
   --  performs bounded cleanup of temporary files and orphan body files, and
   --  restores staged old metadata when replacement was interrupted before new
   --  metadata publication. Corrupt or unsupported entries, including entries
   --  with malformed method, status, required body-length, body filename, or
   --  declared body-size fields, are skipped during Open and never served.
   --
   --  Objects are single-process, single-client, and not task-safe. Callers
   --  sharing one object between tasks must serialize access externally. No
   --  password prompting, environment key loading, credential-store integration,
   --  automatic migration, background refresh, browser profile integration,
   --  service worker behavior, production-grade HTTP/3 execution, available QUIC
   --  backends, or server-push cache behavior is implemented.

   Format_Version : constant Natural := 1;
   Encrypted_Format_Version : constant Natural := 1;

   type Persistent_Encryption_Algorithm is (AES_256_GCM);
   --  Supported encrypted-cache algorithm identifiers. This release supports only
   --  AES-256-GCM through the private OpenSSL EVP bridge. Unsupported future
   --  algorithms are rejected rather than interpreted as plaintext.

   type Persistent_Config is record
      Enabled                   : Boolean := False;
      Cache_Directory           : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Create_If_Missing         : Boolean := False;
      Strict_Writes             : Boolean := False;
      Max_Entries               : Natural := 64;
      Max_Total_Stored_Bytes    : Natural := 8 * 1_024 * 1_024;
      Max_Body_Bytes_Per_Entry  : Natural := 1 * 1_024 * 1_024;
      Max_Metadata_Bytes        : Natural := 64 * 1_024;
      Max_Directory_Scan_Count  : Natural := 512;
      Memory_Config             : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config;
      Encrypt_At_Rest           : Boolean := False;
      Encryption_Algorithm      : Persistent_Encryption_Algorithm := AES_256_GCM;
      Raw_Encryption_Key        : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;
   --  Bounded persistent cache configuration.
   --
   --  @field Enabled Enables this persistent store. False makes Open return
   --         Cache_Disabled and Lookup/Store act as disabled cache operations.
   --  @field Cache_Directory Caller-provided cache directory path. Use
   --         Make_Config to construct records with arbitrary path lengths.
   --  @field Create_If_Missing Allows Open to create the directory.
   --  @field Strict_Writes Turns persistent write failures into Store failures;
   --         otherwise the in-memory cache may still be updated and the HTTP
   --         response should remain usable by higher layers.
   --  @field Max_Entries Maximum retained persistent entries.
   --  @field Max_Total_Stored_Bytes Maximum metadata plus body bytes on disk.
   --  @field Max_Body_Bytes_Per_Entry Maximum stored body bytes for one entry.
   --  @field Max_Metadata_Bytes Maximum metadata file size accepted on load.
   --  @field Max_Directory_Scan_Count Maximum directory entries inspected on
   --         Open to keep loading bounded.
   --  @field Memory_Config stable cache policy used after loading metadata.
   --  @field Encrypt_At_Rest Enables encrypted persistent files. Disabled by
   --         default and never selected implicitly.
   --  @field Encryption_Algorithm AEAD algorithm identifier written to the
   --         encrypted entry envelope. Only AES_256_GCM is currently accepted.
   --  @field Raw_Encryption_Key Caller-supplied raw key bytes. AES_256_GCM
   --         requires exactly 32 bytes. The key is held in process memory for
   --         the store lifetime and is never written to disk.

   type Persistent_Store is tagged private;
   --  Mutable persistent cache handle. Not synchronized.

   type Persistent_Store_Access is access all Persistent_Store;
   --  Optional caller-owned persistent cache reference for high-level client
   --  configuration. The referenced store must already be explicitly opened.

   function Make_Config
     (Directory                 : String;
      Enabled                   : Boolean := True;
      Create_If_Missing         : Boolean := False;
      Strict_Writes             : Boolean := False;
      Max_Entries               : Natural := 64;
      Max_Total_Stored_Bytes    : Natural := 8 * 1_024 * 1_024;
      Max_Body_Bytes_Per_Entry  : Natural := 1 * 1_024 * 1_024;
      Max_Metadata_Bytes        : Natural := 64 * 1_024;
      Max_Directory_Scan_Count  : Natural := 512;
      Memory_Config             : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config;
      Encrypt_At_Rest           : Boolean := False;
      Raw_Encryption_Key        : String := "")
      return Persistent_Config;
   --  GNATdoc contract.
   --  @param Directory Subprogram parameter.
   --  @param Enabled Subprogram parameter.
   --  @param Create_If_Missing Subprogram parameter.
   --  @param Strict_Writes Subprogram parameter.
   --  @param Max_Entries Subprogram parameter.
   --  @param Max_Total_Stored_Bytes Subprogram parameter.
   --  @param Max_Body_Bytes_Per_Entry Subprogram parameter.
   --  @param Max_Metadata_Bytes Subprogram parameter.
   --  @param Max_Directory_Scan_Count Subprogram parameter.
   --  @param Memory_Config Subprogram parameter.
   --  @param Encrypt_At_Rest Subprogram parameter.
   --  @param Raw_Encryption_Key Subprogram parameter.
   --  @return Subprogram result.
   --  Construct a persistent-cache configuration for Directory. When
   --  Encrypt_At_Rest is True, Raw_Encryption_Key must contain exactly 32
   --  octets for AES-256-GCM. Empty or malformed keys are rejected during Open.

   function Open
     (Store  : in out Persistent_Store;
      Config : Persistent_Config) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Open and boundedly scan metadata/statistics from the configured directory
   --  without eagerly reading every cached body into memory. Body files are
   --  read lazily during Lookup only after metadata-only origin, method, and Vary
   --  prefiltering identifies a plausible matching entry, or immediately after
   --  Store/Update_From_304 for the affected entry, and are rejected when they exceed
   --  Max_Body_Bytes_Per_Entry or their declared stored length does not match
   --  the bytes on disk.

   procedure Close (Store : in out Persistent_Store);
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  Close the store object. No files are removed.

   procedure Clear (Store : in out Persistent_Store);
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  Remove known persistent entries and clear the in-memory front cache.

   procedure Invalidate
     (Store   : in out Persistent_Store;
      Request : Http_Client.Requests.Request);
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  Remove all durable entries for Request's normalized origin cache key and
   --  clear the corresponding in-memory front state. Cache-aware execution uses
   --  this when a successful network response replaces an old representation
   --  but is itself not persistently storeable.

   function Is_Open (Store : Persistent_Store) return Boolean;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @return Subprogram result.
   function Encrypts_At_Rest (Store : Persistent_Store) return Boolean;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only for an open persistent store configured for encrypted
   --  metadata/body files. This exposes structural state for diagnostics without
   --  exposing keys, passwords, nonces, tags, URLs, headers, or bodies.

   function Entry_Count (Store : Persistent_Store) return Natural;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @return Subprogram result.
   function Stored_Bytes (Store : Persistent_Store) return Natural;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @return Subprogram result.

   function Lookup
     (Store    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Metadata : out Http_Client.Cache.Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Look up Request using stable cache semantics. Fresh and stale hits can be
   --  used by callers exactly like in-memory cache hits, including conditional
   --  revalidation preparation. Metadata-only origin, method, and Vary checks avoid
   --  reading unrelated body files during a bounded disk scan.

   function Store
     (Cache    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Persist Response if cache policy permits storing it. A replacement is written
   --  to temporary metadata/body files first; the old metadata is staged
   --  aside while publishing the new metadata so a failed publish can restore
   --  the previous entry where the filesystem permits same-directory rename.
   --  If a process stops after staging old metadata but before publishing the
   --  replacement, a later Open restores the staged old metadata when the final
   --  metadata file is absent.

   function Update_From_304
     (Store    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Metadata : out Http_Client.Cache.Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Apply a successful 304 Not Modified response to the persistent entry,
   --  preserving the cached body and rewriting the durable metadata/body pair
   --  atomically enough for the file backend.

   function Remove_Expired
     (Store : in out Persistent_Store;
      Now   : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Store Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Deterministically remove persisted entries whose bounded metadata proves
   --  expiration under max-age freshness. The operation also reloads the
   --  in-memory front from disk afterward. Broader freshness and revalidation
   --  semantics remain owned by Http_Client.Cache.

private
   use Ada.Strings.Unbounded;

   type Persistent_Config_Holder is record
      Enabled                   : Boolean := False;
      Cache_Directory           : Unbounded_String := Null_Unbounded_String;
      Create_If_Missing         : Boolean := False;
      Strict_Writes             : Boolean := False;
      Max_Entries               : Natural := 64;
      Max_Total_Stored_Bytes    : Natural := 8 * 1_024 * 1_024;
      Max_Body_Bytes_Per_Entry  : Natural := 1 * 1_024 * 1_024;
      Max_Metadata_Bytes        : Natural := 64 * 1_024;
      Max_Directory_Scan_Count  : Natural := 512;
      Memory_Config             : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config;
      Encrypt_At_Rest           : Boolean := False;
      Encryption_Algorithm      : Persistent_Encryption_Algorithm := AES_256_GCM;
      Raw_Encryption_Key        : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   type Persistent_Store is tagged record
      Opened       : Boolean := False;
      Config       : Persistent_Config_Holder;
      Memory       : Http_Client.Cache.Cache_Store;
      Entry_Count_Value : Natural := 0;
      Stored_Bytes_Value : Natural := 0;
   end record;
end Http_Client.Cache.Persistent;
