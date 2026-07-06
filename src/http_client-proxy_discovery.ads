with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Proxies;
with Http_Client.URI;

package Http_Client.Proxy_Discovery is
   --  Explicit bounded PAC/WPAD proxy-discovery helpers.
   --
   --  This package is opt-in. It does not read operating-system proxy settings,
   --  environment variables, browser profiles, credential stores, DHCP WPAD,
   --  DNS search domains, or PAC URLs unless a caller explicitly supplies the
   --  relevant inputs to these subprograms. It owns only discovery and route
   --  decision modeling; Http_Client.Proxies still owns HTTP and SOCKS routing.
   --
   --  Phase 40 implements a conservative PAC subset: strict return-string
   --  parsing plus simple FindProxyForURL scripts using literal return values
   --  and bounded conditionals around dnsDomainIs, shExpMatch, and
   --  isPlainHostName. Full browser JavaScript PAC compatibility is not
   --  claimed. Unsupported constructs fail deterministically unless the caller
   --  explicitly selects fail-open policy.

   Max_Proxy_Candidates : constant Positive := 8;
   --  Hard upper bound for one PAC route decision.

   type PAC_Source_Kind is
     (PAC_Source_String,
      PAC_Source_File,
      PAC_Source_URL,
      WPAD_DNS_Source);
   --  Describes where a PAC script came from for caller policy/diagnostics.
   --  URL fetching and WPAD DNS are not performed implicitly by this package.

   type Failure_Policy is (Fail_Closed, Fail_Open_Direct);
   --  Fail_Closed returns the parsing/evaluation error. Fail_Open_Direct
   --  converts PAC failure into a single DIRECT route candidate.

   type Unsupported_Directive_Policy is
     (Reject_Unsupported_Directive,
      Skip_Unsupported_Directive,
      Surface_Unsupported_Directive);
   --  Policy for PAC directives this library cannot route.

   type Proxy_Precedence is
     (Explicit_Proxy_Wins,
      Discovery_Wins_When_Enabled);
   --  Documents integration policy for callers combining explicit proxy config
   --  and discovery. Default high-level client behavior remains explicit proxy
   --  only unless discovery is deliberately selected by caller configuration.

   type Discovery_Limits is record
      Max_Script_Size       : Natural := 64 * 1024;
      Max_Return_Length     : Natural := 4 * 1024;
      Max_Token_Length      : Natural := 512;
      Max_Candidates        : Positive := Max_Proxy_Candidates;
      Max_Evaluation_Steps  : Natural := 1_000;
      Max_WPAD_Attempts     : Natural := 4;
   end record;
   --  Deterministic resource bounds for PAC/WPAD discovery.

   Default_Discovery_Limits : constant Discovery_Limits :=
     (Max_Script_Size      => 64 * 1024,
      Max_Return_Length    => 4 * 1024,
      Max_Token_Length     => 512,
      Max_Candidates       => Max_Proxy_Candidates,
      Max_Evaluation_Steps => 1_000,
      Max_WPAD_Attempts    => 4);

   type Discovery_Options is record
      Enabled                      : Boolean := False;
      Enable_WPAD_DNS              : Boolean := False;
      Allow_Insecure_HTTP_PAC_URL  : Boolean := False;
      Allow_PAC_Fetch_Redirects    : Boolean := False;
      Allow_PAC_Fetch_Decompression : Boolean := False;
      Failure                      : Failure_Policy := Fail_Closed;
      Unsupported_Directives       : Unsupported_Directive_Policy :=
        Reject_Unsupported_Directive;
      Precedence                   : Proxy_Precedence := Explicit_Proxy_Wins;
      Limits                       : Discovery_Limits := Default_Discovery_Limits;
   end record;
   --  Explicit proxy-discovery policy.
   --
   --  @field Enabled Master switch. False preserves Phase 0 through Phase 39
   --         behavior and no PAC/WPAD operation is performed.
   --  @field Enable_WPAD_DNS Enables only explicit, caller-driven DNS WPAD
   --         helpers. This package still does not use system search domains.
   --  @field Allow_Insecure_HTTP_PAC_URL Whether caller-supplied HTTP PAC URLs
   --         are acceptable to a PAC fetcher. HTTPS verification remains the
   --         safe default for fetchers using the main HTTP stack.
   --  @field Failure Controls fail-closed versus explicit direct fallback.
   --  @field Unsupported_Directives Controls unknown PAC tokens.
   --  @field Precedence Documents whether an explicit configured proxy or
   --         discovery decision should win in an integrated caller.
   --  @field Limits Bounds script size, return text, candidates, and steps.

   function Validate
     (Options : Discovery_Options) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate PAC/WPAD discovery limits and policy combinations. Disabled
   --  options are accepted when their limits are still internally consistent.

   Default_Discovery_Options : constant Discovery_Options :=
     (Enabled                       => False,
      Enable_WPAD_DNS               => False,
      Allow_Insecure_HTTP_PAC_URL   => False,
      Allow_PAC_Fetch_Redirects     => False,
      Allow_PAC_Fetch_Decompression => False,
      Failure                       => Fail_Closed,
      Unsupported_Directives        => Reject_Unsupported_Directive,
      Precedence                    => Explicit_Proxy_Wins,
      Limits                        => Default_Discovery_Limits);

   type Proxy_Candidate_Kind is
     (Candidate_Direct,
      Candidate_HTTP_Proxy,
      Candidate_HTTPS_Proxy,
      Candidate_SOCKS_Proxy,
      Candidate_SOCKS5_Proxy,
      Candidate_Unsupported);
   --  One parsed PAC route candidate.

   type Proxy_Candidate is private;
   type Route_Decision is private;
   --  Ordered PAC route candidates. Candidate order is preserved exactly as
   --  returned by PAC, subject to configured bounds and unsupported-token policy.

   function Empty_Decision return Route_Decision;
   --  GNATdoc contract.
   --  @return Subprogram result.
   function Direct_Decision return Route_Decision;
   --  GNATdoc contract.
   --  @return Subprogram result.

   function Candidate_Count (Decision : Route_Decision) return Natural;
   --  GNATdoc contract.
   --  @param Decision Subprogram parameter.
   --  @return Subprogram result.
   function Candidate
     (Decision : Route_Decision;
      Index    : Positive) return Proxy_Candidate;
   --  GNATdoc contract.
   --  @param Decision Subprogram parameter.
   --  @param Index Subprogram parameter.
   --  @return Subprogram result.

   function Kind (Item : Proxy_Candidate) return Proxy_Candidate_Kind;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Host (Item : Proxy_Candidate) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Port (Item : Proxy_Candidate) return Http_Client.URI.TCP_Port;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Raw_Directive (Item : Proxy_Candidate) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.

   function Parse_PAC_Return
     (Text     : String;
      Options  : Discovery_Options;
      Decision : out Route_Decision) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Text Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Decision Subprogram parameter.
   --  @return Subprogram result.
   --  Strictly parse a PAC return string such as
   --  "PROXY proxy.example:8080; SOCKS5 socks.example:1080; DIRECT".
   --
   --  Credentials, URI userinfo, CR/LF injection, invalid hosts, invalid ports,
   --  empty endpoints, overlong tokens, SOCKS4, and malformed whitespace are
   --  rejected. HTTPS proxy directives are surfaced as candidates but conversion
   --  to an executable proxy config returns Proxy_Unsupported unless a later
   --  phase implements HTTPS proxy routing.

   function Evaluate_PAC
     (Script   : String;
      Target   : Http_Client.URI.URI_Reference;
      Options  : Discovery_Options;
      Decision : out Route_Decision) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Script Subprogram parameter.
   --  @param Target Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Decision Subprogram parameter.
   --  @return Subprogram result.
   --  Evaluate the supported bounded PAC subset for Target.
   --
   --  Supported constructs are literal return strings and simple if blocks for
   --  dnsDomainIs(host, "suffix"), shExpMatch(url, "pattern"), and
   --  isPlainHostName(host). DNS-dependent helpers such as dnsResolve, isInNet,
   --  and myIpAddress are deliberately unsupported in this Ada-only phase unless
   --  a later resolver hook implements them explicitly.


   function Resolve_PAC_Script
     (Script : String;
      Target : Http_Client.URI.URI_Reference;
      Options : Discovery_Options;
      Config : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Script Subprogram parameter.
   --  @param Target Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Evaluate Script for Target and convert the ordered PAC decision into the
   --  first executable proxy configuration for the current routing stack. This
   --  is the single helper used by integrated callers so PAC parsing, candidate
   --  ordering, fail-open/fail-closed policy, and unsupported-candidate handling
   --  remain identical to the standalone Evaluate_PAC plus
   --  Select_First_Executable path.

   function Load_PAC_File
     (Path     : String;
      Options  : Discovery_Options;
      Script   : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Path Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param Script Subprogram parameter.
   --  @return Subprogram result.
   --  Explicitly load a local PAC file within configured size limits. No browser
   --  profile or standard OS PAC location is searched.

   function To_Proxy_Config
     (Item   : Proxy_Candidate;
      Config : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Convert a DIRECT, PROXY, or SOCKS/SOCKS5 candidate into the existing proxy
   --  configuration model. HTTPS proxy and unsupported candidates return
   --  Proxy_Unsupported. PAC never supplies credentials.

   function Select_First_Executable
     (Decision : Route_Decision;
      Config   : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Decision Subprogram parameter.
   --  @param Config Subprogram parameter.
   --  @return Subprogram result.
   --  Select the first candidate in PAC order that can be executed by the
   --  current routing stack. Unsupported HTTPS-proxy or surfaced-unsupported
   --  candidates are skipped only while a later supported candidate exists.
   --  If none can execute, returns the first deterministic failure status.

   function Build_WPAD_URL
     (Base_Domain : String;
      Options     : Discovery_Options;
      URL         : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Base_Domain Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @param URL Subprogram parameter.
   --  @return Subprogram result.
   --  Build http://wpad.<Base_Domain>/wpad.dat for explicit DNS WPAD tests or
   --  caller-provided resolvers. This does not query DNS, use DHCP, or inspect
   --  system search domains.

private
   use Ada.Strings.Unbounded;

   type Proxy_Candidate is record
      Candidate_Type : Proxy_Candidate_Kind := Candidate_Direct;
      Candidate_Host : Unbounded_String := Null_Unbounded_String;
      Candidate_Port : Http_Client.URI.TCP_Port := 1;
      Raw            : Unbounded_String := Null_Unbounded_String;
   end record;

   type Candidate_Array is array (Positive range 1 .. Max_Proxy_Candidates)
     of Proxy_Candidate;

   type Route_Decision is record
      Count : Natural range 0 .. Max_Proxy_Candidates := 0;
      Items : Candidate_Array := (others => (others => <>));
   end record;
end Http_Client.Proxy_Discovery;
