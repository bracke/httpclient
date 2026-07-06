with Ada.Calendar;
with Ada.Strings.Unbounded;

with Http_Client.Alt_Svc;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.HTTP3;
with Http_Client.Proxies;
with Http_Client.URI;

package Http_Client.Protocol_Discovery is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit, bounded Alt-Svc and HTTPS/SVCB protocol discovery policy.
   --
   --  Discovery is disabled by default and is not browser-like automatic
   --  networking. This package creates no background tasks, performs no public
   --  DNS queries, does not bypass configured HTTP or SOCKS proxies, does not
   --  implement PAC/WPAD, MASQUE, CONNECT-UDP, SOCKS UDP, WebTransport,
   --  service workers, browser preload behavior, OAuth, OS credential stores,
   --  or password-manager integration. Discovery metadata is separate from HTTP
   --  response caches and is never persisted here. TLS authority validation
   --  remains tied to the original origin.

   Max_Cache_Entries           : constant Positive := 64;
   Max_Alternatives_Per_Origin : constant Positive := 4;

   type Selection_Source is
     (Discovery_None,
      Discovery_Alt_Svc,
      Discovery_HTTPS_SVCB);

   type Discovery_Fallback_Policy is
     (Discovery_Fallback_Disallowed,
      Discovery_Fallback_Before_Send);
   --  Fallback after a discovered alternative fails. Before-send fallback is
   --  only a discovery gate; higher layers must still apply retry/replayability
   --  rules before replaying a request.

   type Resolver_Callback is access function
     (Origin_Host : String) return Http_Client.DNS_SVCB.Resolver_Result;
   --  Explicit scripted HTTPS/SVCB resolver hook. Null means unavailable.
   --  Default tests must not depend on public DNS.

   type Discovery_Options is record
      Enable_Alt_Svc                  : Boolean := False;
      Enable_HTTPS_SVCB               : Boolean := False;
      Allow_HTTP3_Discovery           : Boolean := False;
      Maximum_Alt_Svc_Entries         : Positive := Max_Cache_Entries;
      Maximum_Alternatives_Per_Origin : Positive := Max_Alternatives_Per_Origin;
      Maximum_Alt_Svc_Age             : Natural := Http_Client.Alt_Svc.Default_Max_Age_Seconds;
      Fallback                        : Discovery_Fallback_Policy := Discovery_Fallback_Disallowed;
      Resolver                        : Resolver_Callback := null;
   end record;
   --  Caller-owned discovery configuration. Defaults preserve direct behavior:
   --  no Alt-Svc learning, no HTTPS/SVCB lookup, no HTTP/3 discovery attempt,
   --  no proxy bypass, no persistent discovery cache, and no unsafe fallback.

   Default_Discovery_Options : constant Discovery_Options :=
     (Enable_Alt_Svc                  => False,
      Enable_HTTPS_SVCB               => False,
      Allow_HTTP3_Discovery           => False,
      Maximum_Alt_Svc_Entries         => Max_Cache_Entries,
      Maximum_Alternatives_Per_Origin => Max_Alternatives_Per_Origin,
      Maximum_Alt_Svc_Age             => Http_Client.Alt_Svc.Default_Max_Age_Seconds,
      Fallback                        => Discovery_Fallback_Disallowed,
      Resolver                        => null);

   subtype Discovery_Policy is Discovery_Options;
   Default_Discovery_Policy : constant Discovery_Policy := Default_Discovery_Options;

   type Discovery_Selection is record
      Source                        : Selection_Source := Discovery_None;
      Protocol                      : Http_Client.HTTP3.Selected_Protocol := Http_Client.HTTP3.Protocol_None;
      Alternative_Host              : Ada.Strings.Unbounded.Unbounded_String;
      Alternative_Port              : Natural := 0;
      Uses_Origin_Host              : Boolean := False;
      Requires_Origin_TLS_Authority : Boolean := True;
   end record;
   --  Selected alternative endpoint. This is not permission to weaken TLS;
   --  transports must verify the original origin authority.

   type Discovery_Cache is private;
   --  Bounded in-memory Alt-Svc cache. It is caller-owned, unsynchronized, not
   --  an HTTP cache, and not persisted.

   function Validate
     (Options : Discovery_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate resource limits.

   procedure Initialize
     (Cache   : out Discovery_Cache;
      Options : Discovery_Options := Default_Discovery_Options);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  Initialize or clear a discovery cache using bounded options.

   procedure Clear (Cache : in out Discovery_Cache);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  Clear all discovery metadata without touching HTTP response caches.

   function Entry_Count (Cache : Discovery_Cache) return Natural;
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of origin entries currently stored.

   function Accept_Alt_Svc
     (Cache                        : in out Discovery_Cache;
      Origin                       : Http_Client.URI.URI_Reference;
      Header                       : String;
      Received_At                  : Ada.Calendar.Time;
      Options                      : Discovery_Options := Default_Discovery_Options;
      From_Verified_HTTPS_Response : Boolean := False)
      return Http_Client.Errors.Result_Status
   with Pre => Http_Client.URI.Is_Parsed (Origin);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Origin Subprogram parameter.
   --  @param Header Subprogram parameter.
   --  @param Received_At Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param From_Verified_HTTPS_Response Subprogram parameter.
   --  @return Subprogram result.
   --  Accept an Alt-Svc header only when explicitly enabled and received from a
   --  successfully verified HTTPS response. Disabled policy is a no-op.

   function Selection
     (Cache     : in out Discovery_Cache;
      Origin    : Http_Client.URI.URI_Reference;
      Options   : Discovery_Options;
      HTTP3     : Http_Client.HTTP3.HTTP3_Options;
      Proxy     : Http_Client.Proxies.Proxy_Config;
      Now       : Ada.Calendar.Time;
      Selection : out Discovery_Selection) return Http_Client.Errors.Result_Status
   with Pre => Http_Client.URI.Is_Parsed (Origin);
   --  GNATdoc contract.
   --  @param Cache Subprogram parameter.
   --  @param Origin Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param HTTP3 Subprogram parameter.
   --  @param Proxy Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @param Selection Subprogram parameter.
   --  @return Subprogram result.
   --  Select an explicit HTTP/3 alternative from Alt-Svc cache or scripted
   --  HTTPS/SVCB records. Configured proxies suppress discovery; this package
   --  never bypasses them.

   function Fallback_Status
     (Options                    : Discovery_Options;
      Request_Bytes_Already_Sent : Boolean)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @param Request_Bytes_Already_Sent Subprogram parameter.
   --  @return Subprogram result.
   --  Return Ok only when discovery fallback is explicitly allowed before any
   --  request bytes have been sent.

private
   use Ada.Strings.Unbounded;

   type Origin_Key is record
      Scheme : Unbounded_String := Null_Unbounded_String;
      Host   : Unbounded_String := Null_Unbounded_String;
      Port   : Natural := 0;
   end record;

   type Stored_Alternative is record
      In_Use         : Boolean := False;
      Protocol       : Http_Client.Alt_Svc.Alternative_Protocol := Http_Client.Alt_Svc.Alt_Protocol_HTTP3;
      Host           : Unbounded_String := Null_Unbounded_String;
      Host_Is_Origin : Boolean := False;
      Port           : Natural := 0;
      Expires_At     : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
   end record;

   type Stored_Alternative_Array is
     array (Positive range 1 .. Max_Alternatives_Per_Origin) of Stored_Alternative;

   type Cache_Entry is record
      In_Use       : Boolean := False;
      Key          : Origin_Key;
      Alternatives : Stored_Alternative_Array := (others => <>);
      Count        : Natural range 0 .. Max_Alternatives_Per_Origin := 0;
   end record;

   type Cache_Entry_Array is array (Positive range 1 .. Max_Cache_Entries) of Cache_Entry;

   type Discovery_Cache is record
      Entries : Cache_Entry_Array := (others => <>);
      Count   : Natural range 0 .. Max_Cache_Entries := 0;
   end record;
end Http_Client.Protocol_Discovery;
