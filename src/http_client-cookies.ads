with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.URI;

package Http_Client.Cookies is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Conservative HTTP cookie parsing and explicit in-memory cookie jars.
   --
   --  This package interprets Set-Cookie header values but remains separate
   --  from the generic response parser and header collection. Cookie use is
   --  opt-in: callers must pass a jar through client execution options or call
   --  the jar operations directly. The jar is in-memory only and is not
   --  browser-grade storage. In particular, This package does not implement a
   --  public suffix list, persistent cookie files, CHIPS/partitioning,
   --  SameParty, JavaScript behavior, or browser privacy policy. Because no
   --  public suffix list is present, Domain attributes are conservatively
   --  limited to multi-label DNS-style domains; host-only cookies remain valid
   --  for single-label origins.
   --
   --  Cookie_Jar is not synchronized. Callers sharing a jar between tasks must
   --  serialize access externally.

   type SameSite_Policy is
     (SameSite_Unspecified,
      SameSite_Strict,
      SameSite_Lax,
      SameSite_None,
      SameSite_Unknown);
   --  Parsed SameSite metadata.
   --
   --  SameSite is exposed but not enforced by this package because this library
   --  does not model browser navigation or same-site context.

   type Cookie_Limits is record
      Max_Cookies              : Natural := 300;
      Max_Cookies_Per_Domain   : Natural := 50;
      Max_Name_Length          : Natural := 256;
      Max_Value_Length         : Natural := 4_096;
      Max_Cookie_Header_Length : Natural := 16_384;
   end record;
   --  Deterministic in-memory jar limits.
   --
   --  @field Max_Cookies Maximum total cookies retained by a jar.
   --  @field Max_Cookies_Per_Domain Maximum cookies sharing one domain string.
   --  @field Max_Name_Length Maximum accepted cookie-name length.
   --  @field Max_Value_Length Maximum accepted cookie-value length.
   --  @field Max_Cookie_Header_Length Maximum generated Cookie request header.

   Default_Limits : constant Cookie_Limits :=
     (Max_Cookies              => 300,
      Max_Cookies_Per_Domain   => 50,
      Max_Name_Length          => 256,
      Max_Value_Length         => 4_096,
      Max_Cookie_Header_Length => 16_384);

   type Cookie is private;
   --  Parsed cookie record.
   --
   --  Host-only cookies are sent only to the exact origin host that set them.
   --  Domain cookies are sent to hosts that domain-match the stored domain.
   --  Secure cookies are never generated for plain HTTP requests. This package
   --  accepts Secure cookies set by HTTP responses for possible future HTTPS use
   --  on the same matching host/path rather than rejecting them at parse
   --  time. Case-sensitive __Secure- and __Host- prefixes are enforced
   --  conservatively: prefixed cookies must be set over HTTPS, __Secure- must
   --  include Secure, and __Host- must include Secure, omit Domain, and use an
   --  explicit Path=/. HttpOnly is retained as metadata. SameSite is parsed but
   --  not enforced.

   type Cookie_Jar is private;
   --  Explicit in-memory cookie jar.
   --
   --  Storage replacement uses the tuple name, domain, host-only flag, and path.
   --  Cookie names are case-sensitive. Cookie header generation orders matching
   --  cookies by longer path first and
   --  then earlier creation order.

   type Cookie_Jar_Access is access all Cookie_Jar;
   --  Explicit nullable jar reference used by client execution options.

   function Empty_Jar
     (Limits : Cookie_Limits := Default_Limits) return Cookie_Jar;
   --  GNATdoc contract.
   --  @param Limits Subprogram parameter.
   --  @return Subprogram result.
   --  Return an empty in-memory jar with the supplied limits.

   function Is_Valid_Name (Name : String) return Boolean;
   --  GNATdoc contract.
   --  @param Name Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Name is a non-empty conservative cookie-name token.

   function Is_Valid_Value (Value : String) return Boolean;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Value contains no CR, LF, NUL, semicolon, or control
   --  characters. A surrounding quoted-string is accepted after validation.

   function Name (Item : Cookie) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Value (Item : Cookie) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Domain (Item : Cookie) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Path (Item : Cookie) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Host_Only (Item : Cookie) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Secure (Item : Cookie) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Http_Only (Item : Cookie) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function SameSite (Item : Cookie) return SameSite_Policy;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Is_Persistent (Item : Cookie) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   function Is_Expired
     (Item : Cookie;
      Now  : Ada.Calendar.Time := Ada.Calendar.Clock) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Accessors for parsed cookie metadata.

   function Default_Path (Request_Path : String) return String;
   --  GNATdoc contract.
   --  @param Request_Path Subprogram parameter.
   --  @return Subprogram result.
   --  Derive the default cookie path from a request path.

   function Path_Matches
     (Cookie_Path  : String;
      Request_Path : String) return Boolean;
   --  GNATdoc contract.
   --  @param Cookie_Path Subprogram parameter.
   --  @param Request_Path Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Request_Path path-matches Cookie_Path.

   function Domain_Matches
     (Cookie_Domain : String;
      Request_Host  : String;
      Host_Only     : Boolean) return Boolean;
   --  GNATdoc contract.
   --  @param Cookie_Domain Subprogram parameter.
   --  @param Request_Host Subprogram parameter.
   --  @param Host_Only Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Request_Host matches the host-only or domain policy.
   --  This function performs matching only; Parse_Set_Cookie applies the
   --  stricter Domain-attribute acceptance policy.

   function Parse_Set_Cookie
     (Header_Value : String;
      Origin_URI   : Http_Client.URI.URI_Reference;
      Item         : out Cookie;
      Now          : Ada.Calendar.Time := Ada.Calendar.Clock;
      Limits       : Cookie_Limits := Default_Limits)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header_Value Subprogram parameter.
   --  @param Origin_URI Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @param Limits Subprogram parameter.
   --  Parse one Set-Cookie header value in the context of Origin_URI.
   --
   --  Empty or blank Set-Cookie values and values without an initial
   --  name=value pair are rejected explicitly as Invalid_Cookie.
   --  Origin_URI must be a parsed URI. Unchecked/unparsed URI values are
   --  rejected with Invalid_URI before component accessors are used.
   --
   --  @return Ok when a cookie was parsed; Invalid_Cookie for malformed syntax;
   --          Cookie_Rejected for security-policy rejection such as unrelated
   --          Domain or violated __Secure-/__Host- prefix constraints;
   --          Cookie_Too_Large when configured size limits are exceeded.

   function Add
     (Jar  : in out Cookie_Jar;
      Item : Cookie) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Add or replace a cookie. Expired cookies remove the matching tuple.

   procedure Clear (Jar : in out Cookie_Jar);
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  Remove all cookies from the jar and reset deterministic creation ordering.

   function Length (Jar : Cookie_Jar) return Natural;
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @return Subprogram result.
   --  Return the number of retained cookies.

   function Cookie_At
     (Jar   : Cookie_Jar;
      Index : Positive) return Cookie
   with
      Pre => Index <= Length (Jar);
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @param Index Subprogram parameter.
   --  @return Subprogram result.
   --  Return a cookie by deterministic storage order for tests/diagnostics.

   procedure Remove_Expired
     (Jar : in out Cookie_Jar;
      Now : Ada.Calendar.Time := Ada.Calendar.Clock);
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  Remove all expired cookies.

   procedure Store_From_Response
     (Jar        : in out Cookie_Jar;
      Origin_URI : Http_Client.URI.URI_Reference;
      Headers    : Http_Client.Headers.Header_List;
      Now        : Ada.Calendar.Time := Ada.Calendar.Clock;
      Strict     : Boolean := False;
      Status     : out Http_Client.Errors.Result_Status);
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @param Origin_URI Subprogram parameter.
   --  @param Headers Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @param Strict Subprogram parameter.
   --  @param Status Subprogram parameter.
   --  Parse and store every Set-Cookie field from Headers.
   --
   --  Malformed cookies are ignored by default so HTTP execution can still
   --  return the response and later Set-Cookie fields can still be processed.
   --  When Strict is True, the first rejected cookie status is returned after
   --  processing stops.

   function Get_Cookie_Header
     (Jar        : Cookie_Jar;
      Target_URI : Http_Client.URI.URI_Reference;
      Now        : Ada.Calendar.Time := Ada.Calendar.Clock)
      return String;
   --  GNATdoc contract.
   --  @param Jar Subprogram parameter.
   --  @param Target_URI Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Generate the outbound Cookie header value for Target_URI.
   --
   --  Unchecked/unparsed target URI values return the empty string. The value
   --  contains only name=value pairs separated by semicolon-space;
   --  attributes such as Domain, Path, Secure, HttpOnly, Expires, Max-Age, and
   --  SameSite are never included. An empty string means no matching cookie.

private
   use Ada.Strings.Unbounded;

   type Cookie is record
      Name_Value      : Unbounded_String;
      Cookie_Value    : Unbounded_String;
      Domain_Value    : Unbounded_String;
      Path_Value      : Unbounded_String;
      Host_Only_Value : Boolean := True;
      Secure_Value    : Boolean := False;
      Http_Only_Value : Boolean := False;
      SameSite_Value  : SameSite_Policy := SameSite_Unspecified;
      Persistent      : Boolean := False;
      Expires_At      : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Creation_Order  : Natural := 0;
   end record;

   package Cookie_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Cookie);

   type Cookie_Jar is record
      Items          : Cookie_Vectors.Vector;
      Limits         : Cookie_Limits := Default_Limits;
      Next_Creation  : Natural := 1;
   end record;
end Http_Client.Cookies;
