with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Responses;

package Http_Client.Cache is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit bounded in-memory HTTP cache foundation.
   --
   --  This package stores complete buffered response representations only. It
   --  is not a browser cache, persistent cache, service worker cache, shared
   --  process cache, credential store, or offline application database. Callers
   --  must pass a cache object explicitly or use a cache-aware client API;
   --  ordinary execution APIs do not consult or mutate cache state.
   --
   --  Cache keys are normalized origin URI keys plus supported Vary
   --  request-header dimensions. URI fragments are excluded; scheme and host
   --  are normalized to lowercase; effective ports are explicit. Vary: * and
   --  duplicate Vary names are rejected. Header-name matching is
   --  case-insensitive. Responses to non-GET methods,
   --  non-200 responses including partial content, any request body including legacy
   --  buffered payloads and streaming body producers, Authorization, Cookie,
   --  response Set-Cookie, no-store, ambiguous
   --  representation semantics, and over-limit bodies are bypassed by the
   --  default conservative policy. Authenticated response storage, when
   --  deliberately enabled, additionally requires explicit Vary: Authorization
   --  so credentials remain part of the cache match.
   --
   --  Stored entries are not task-safe. Callers sharing one cache between Ada
   --  tasks must serialize access externally. Eviction is deterministic LRU:
   --  lookup and store refresh an entry's last-used timestamp, and the least
   --  recently used entries are evicted first until configured limits hold.
   --  Cache-aware network replacements that are non-storeable may invalidate
   --  retained entries for the same origin key to avoid serving stale data.

   type Cache_Store is tagged private;
   --  Mutable in-memory cache. Not synchronized.

   type Cache_Store_Access is access all Cache_Store;
   --  Optional caller-owned cache reference for configuration records.

   type Cache_Config is record
      Enabled                   : Boolean := False;
      Max_Entries               : Natural := 64;
      Max_Total_Body_Bytes      : Natural := 8 * 1_024 * 1_024;
      Max_Single_Response_Bytes : Natural := 1 * 1_024 * 1_024;
      Allow_Authenticated_Store : Boolean := False;
      Allow_Set_Cookie_Store    : Boolean := False;
      Allow_Heuristic_Freshness : Boolean := False;
   end record;
   --  Bounded cache policy.
   --
   --  @field Enabled Enables cache-aware execution when a cache object is also
   --         supplied. Disabled means bypass lookup and storage.
   --  @field Max_Entries Maximum number of entries retained. Zero disables
   --         storage while still permitting deterministic Cache_Disabled.
   --  @field Max_Total_Body_Bytes Maximum stored response-body bytes across all
   --         entries.
   --  @field Max_Single_Response_Bytes Maximum body bytes for one response.
   --  @field Allow_Authenticated_Store Permit carefully documented storage of
   --         Authorization responses only when response directives explicitly
   --         allow it. False bypasses such requests.
   --  @field Allow_Set_Cookie_Store Permit storage of Set-Cookie responses only
   --         under explicit caller policy. False bypasses them.
   --  @field Allow_Heuristic_Freshness Reserved for later bounded heuristic
   --         freshness. Default policy to no heuristic freshness.

   Default_Cache_Config : constant Cache_Config :=
     (Enabled                   => False,
      Max_Entries               => 64,
      Max_Total_Body_Bytes      => 8 * 1_024 * 1_024,
      Max_Single_Response_Bytes => 1 * 1_024 * 1_024,
      Allow_Authenticated_Store => False,
      Allow_Set_Cookie_Store    => False,
      Allow_Heuristic_Freshness => False);
   --  Conservative cache defaults. Caching remains disabled until opted in.

   Default_Enabled_Cache_Config : constant Cache_Config :=
     (Enabled                   => True,
      Max_Entries               => 64,
      Max_Total_Body_Bytes      => 8 * 1_024 * 1_024,
      Max_Single_Response_Bytes => 1 * 1_024 * 1_024,
      Allow_Authenticated_Store => False,
      Allow_Set_Cookie_Store    => False,
      Allow_Heuristic_Freshness => False);
   --  Conservative enabled policy for callers that explicitly use
   --  cache-aware execution.

   type Cache_Source is
     (From_Network,
      From_Fresh_Cache,
      From_Stale_Cache,
      From_Revalidated_Cache,
      Cache_Bypassed);
   --  Source classification for cache-aware execution results.

   type Cache_Metadata is record
      Source             : Cache_Source := Cache_Bypassed;
      Stored_Time        : Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1);
      Fresh_Until        : Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1);
      Age_Seconds        : Natural := 0;
      Revalidation_Count : Natural := 0;
      Entry_Count        : Natural := 0;
      Stored_Body_Bytes  : Natural := 0;
   end record;
   --  Small testable cache metadata result.
   --
   --  @field Source Whether the result came from network, fresh cache, stale
   --         cache, revalidated cache, or bypass.
   --  @field Stored_Time Time the matching entry was stored.
   --  @field Fresh_Until Conservative freshness deadline. Expires-based freshness
   --  uses the absolute Expires timestamp and is not extended by local store time.
   --  @field Age_Seconds Conservative current response age including any
   --         valid Age header and Date apparent-age contribution with whole-second flooring, plus time
   --         resident in the cache.
   --  @field Revalidation_Count Number of successful 304 revalidations.
   --  @field Entry_Count Current cache entry count.
   --  @field Stored_Body_Bytes Current total stored body bytes.

   function Validate
     (Config : Cache_Config) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Validate cache bounds and policy.

   procedure Initialize
     (Cache  : in out Cache_Store;
      Config : Cache_Config := Default_Cache_Config);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  Reset Cache and install Config.

   procedure Configure (Cache : in out Cache_Store; Config : Cache_Config);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  Replace cache bounds and policy without clearing entries. Existing
   --  entries are evicted deterministically if the new limits require it.

   procedure Clear (Cache : in out Cache_Store);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  Remove all entries and stored bodies.

   function Length (Cache : Cache_Store) return Natural;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of retained entries.

   function Stored_Body_Bytes (Cache : Cache_Store) return Natural;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @return Subprogram result.
   --  Return total body bytes currently retained.

   procedure Invalidate
     (Cache : in out Cache_Store; Request : Http_Client.Requests.Request);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  Remove all entries for Request's normalized origin URI. This is used by
   --  cache-aware execution when a successful network response replaces a
   --  cached representation but is itself non-storeable, for example because
   --  it carries Cache-Control: no-store or exceeds configured limits.

   function Origin_Key (Request : Http_Client.Requests.Request) return String;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized cache origin key: lowercase scheme, lowercase host,
   --  effective port, path and query, with URI fragment excluded.

   function May_Store
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Config   : Cache_Config := Default_Cache_Config) return Boolean;
   --  GNATdoc contract.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the conservative cache policy permits storing a complete
   --  buffered 200 OK response. Partial content and other non-200 responses
   --  are bypassed. This function does not inspect cache size limits.

   function May_Store_With_Client_Certificate
     (Using_Client_Certificate : Boolean;
      Request                  : Http_Client.Requests.Request;
      Response                 : Http_Client.Responses.Response;
      Config                   : Cache_Config := Default_Cache_Config)
      return Boolean;
   --  GNATdoc contract.
   --  @param Using_Client_Certificate Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only when the ordinary cache policy permits storage and the
   --  mutual-TLS sensitivity policy also permits it. By default, responses
   --  obtained over a client-certificate-authenticated TLS connection are
   --  treated like authenticated responses and bypassed because they may be
   --  personalized even without an HTTP Authorization header or cookies.
   --  Callers that deliberately enable Allow_Authenticated_Store must still
   --  satisfy the ordinary explicit response-directive rules. Cache storage
   --  never stores private keys, passphrases, raw PEM
   --  material, or client-certificate credential identifiers.

   function Store
     (Cache    : in out Cache_Store;
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
   --  Store Response if cacheable and within limits, replacing an equivalent
   --  origin/Vary entry and evicting deterministically as needed.

   function Lookup
     (Cache    : in out Cache_Store;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Metadata : out Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Look up Request. Returns Ok for a fresh hit, Cache_Entry_Stale for a
   --  stale matching entry or request-directed revalidation, Cache_Miss for no
   --  entry or conservative credential/cookie bypass, or Cache_Disabled when
   --  the installed config is disabled. Request Cache-Control no-cache,
   --  max-age, min-fresh, and numeric bounded max-stale is honored; bare
   --  max-stale is treated as stale/revalidation-required to avoid unbounded
   --  stale reuse. A numeric bounded max-stale hit returns Ok with Source =
   --  From_Stale_Cache unless response directives such
   --  as must-revalidate forbid stale reuse. On stale matches Response contains
   --  the cached body so callers may perform conditional revalidation.

   function Prepare_Conditional_Request
     (Original : Http_Client.Requests.Request;
      Cached   : Http_Client.Responses.Response;
      Result   : out Http_Client.Requests.Request)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Original Subprogram parameter.
   --  @param Cached Subprogram parameter.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Create a request for conditional revalidation. ETag produces
   --  If-None-Match and Last-Modified produces If-Modified-Since. When both
   --  validators exist, ETag is preferred but Last-Modified is also retained as
   --  a secondary validator.

   function Update_From_304
     (Cache    : in out Cache_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Metadata : out Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Response Subprogram parameter.
   --  @param Metadata Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Mark a matching cached entry as revalidated after a 304 Not Modified.
   --  Malformed 304 responses with body framing are rejected. The cached body
   --  is retained for valid 304 responses. If updated Vary metadata makes
   --  this entry equivalent to another retained variant, the duplicate is
   --  collapsed deterministically and the revalidated body/metadata are kept.
   --  If merged metadata makes the entry
   --  non-storeable, such as Cache-Control: no-store, or invalid Vary metadata,
   --  the entry is invalidated deterministically instead of being served.


   function Is_Weak_ETag (ETag : String) return Boolean;
   --  Return True when ETag uses the HTTP weak validator prefix W/.

   function Cache_Control_Has_Directive
     (Value : String;
      Name  : String) return Boolean;
   --  Return True when Cache-Control Value contains directive Name. Matching
   --  is case-insensitive and token-boundary aware.

   function Cache_Control_Directive_Value
     (Value : String;
      Name  : String) return String;
   --  Return the unquoted value of Cache-Control directive Name, or an empty
   --  string when the directive is absent or valueless.

   function Freshness_Lifetime_MS
     (Cache_Control     : String;
      Expires           : String;
      Stored_Time       : Ada.Calendar.Time;
      Stored_Time_Known : Boolean;
      Lifetime          : out Natural) return Boolean;
   --  Compute a conservative freshness lifetime in milliseconds from
   --  Cache-Control max-age or Expires. Returns False when no usable explicit
   --  freshness information is present.

   function Is_Fresh
     (Cache_Control     : String;
      Expires           : String;
      Stored_Time       : Ada.Calendar.Time;
      Stored_Time_Known : Boolean;
      Max_Stale_MS      : Natural := 0;
      Now               : Ada.Calendar.Time := Ada.Calendar.Clock) return Boolean;
   --  Return True when explicit freshness metadata is still fresh at Now,
   --  including the caller supplied bounded Max_Stale_MS. no-cache,
   --  must-revalidate, and proxy-revalidate force False.

   procedure Add_Conditional_Validators
     (Headers       : in out Http_Client.Headers.Header_List;
      ETag          : String;
      Last_Modified : String);
   --  Add If-None-Match and/or If-Modified-Since validators to Headers. ETag
   --  is preferred, but Last-Modified is retained when present.

private
   use Ada.Strings.Unbounded;

   type Vary_Dimension is record
      Name    : Unbounded_String;
      Present : Boolean := False;
      Value   : Unbounded_String;
   end record;

   package Vary_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Vary_Dimension);

   type Cache_Entry is record
      Key                : Unbounded_String;
      Vary               : Vary_Vectors.Vector;
      Stored_Response    : Http_Client.Responses.Response :=
        Http_Client.Responses.Default_Response;
      Body_Bytes         : Natural := 0;
      Stored_Time        : Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1);
      Fresh_Until        : Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1);
      Last_Used          : Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (1970, 1, 1);
      Revalidation_Count : Natural := 0;
   end record;

   package Entry_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Cache_Entry);

   type Cache_Store is tagged record
      Config      : Cache_Config := Default_Cache_Config;
      Entries     : Entry_Vectors.Vector;
      Total_Bytes : Natural := 0;
   end record;
end Http_Client.Cache;
