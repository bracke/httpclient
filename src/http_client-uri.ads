with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.URI is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  URI parsing and validation for absolute HTTP and HTTPS URIs.
   --
   --  This parser accepts only absolute http:// and https:// URIs. It parses the
   --  scheme, host, optional port, path, optional query, and optional
   --  fragment.
   --  It does not perform DNS lookup, network I/O, TLS setup, redirects,
   --  cookies, HTTP/2, HPACK, compression, or request execution.

   subtype TCP_Port is Natural range 1 .. 65_535;
   --  Valid TCP port number range accepted in URI authorities.

   type Host_Kind is (DNS_Name, IPv4_Literal, IPv6_Literal);
   --  Parsed host classification. IPv6 literals are stored without URI
   --  square brackets and are emitted with brackets where URI authority
   --  syntax requires them.

   function Raw_Authority_Host_Has_Non_ASCII (Text : String) return Boolean;
   --  Return True when Text contains raw non-ASCII bytes in the authority host
   --  component. Text may be an absolute URI or authority-like host text. This
   --  helper does not perform IDNA conversion; callers can use it when they
   --  need to reject raw Unicode host input before Parse normalizes it.

   function Is_Valid_ASCII_Host (Host : String) return Boolean;
   --  Return True when Host is valid normalized ASCII host text accepted by the
   --  URI layer: a DNS name, IPv4 literal, or IPv6 literal without URI square
   --  brackets. This helper does not accept raw Unicode host text.

   function Kind_Of_ASCII_Host (Host : String) return Host_Kind
   with
      Pre => Is_Valid_ASCII_Host (Host);
   --  Return the host kind for valid normalized ASCII host text. IPv6 literals
   --  are expected without URI square brackets, matching Host output from Parse.

   type URI_Reference is private;
   --  Parsed or unchecked URI holder.
   --
   --  Values returned by Parse expose validated structured components. Values
   --  returned by Create_Unchecked only preserve text for compatibility.

   function Create_Unchecked (Text : String) return URI_Reference;
   --  GNATdoc contract.
   --  @param Text Subprogram parameter.
   --  @return Subprogram result.
   --  Store Text as a URI reference without validation.
   --
   --  This compatibility helper should not be used for request construction in
   --  future protocol or application layers.

   function Parse
     (Text : String;
      Item : out URI_Reference) return Http_Client.Errors.Result_Status;
   --  Parse and validate an absolute HTTP or HTTPS URI.
   --
   --  @param Text URI text to parse.
   --  @param Item Parsed URI value when the return status is Ok.
   --  @return Ok on success, Invalid_URI for malformed text, or
   --          Unsupported_Feature for syntactically recognized but unsupported
   --          URI forms such as non-http schemes, userinfo, and other
   --          intentionally unsupported authority forms.

   function Image (Item : URI_Reference) return String;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the stored URI text for unchecked values, or normalized absolute
   --  URI text for parsed values. IPv6 literal authorities are emitted in
   --  bracketed form.

   function Is_Empty (Item : URI_Reference) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when no URI text is stored.

   function Is_Parsed (Item : URI_Reference) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item was produced by a successful Parse call.

   function Scheme (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized URI scheme, either "http" or "https".

   function Host (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized host. DNS-style names are lower-cased.

   function Kind_Of_Host (Item : URI_Reference) return Host_Kind
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the parsed host kind.

   function Authority_Host (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the host in URI authority form. IPv6 literals are bracketed.

   function Has_Explicit_Port (Item : URI_Reference) return Boolean
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when the authority explicitly contains a port.

   function Explicit_Port (Item : URI_Reference) return Natural
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the explicit port, or 0 when no port was present.

   function Effective_Port (Item : URI_Reference) return TCP_Port
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the explicit port, or the default port for the parsed scheme.

   function Path (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized path. An empty absolute-URI path is stored as "/".

   function Effective_Path (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the request path. This is identical to Path.

   function Has_Query (Item : URI_Reference) return Boolean
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when a query marker was present, including an empty query.

   function Query (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the raw query string without the leading question mark.

   function Has_Fragment (Item : URI_Reference) return Boolean
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when a fragment marker was present, including an empty one.

   function Fragment (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the raw fragment string without the leading hash mark.

   function Requires_TLS (Item : URI_Reference) return Boolean
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True for https URIs and False for http URIs.

   function Request_Target (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the origin-form request target: path plus optional query.
   --
   --  The fragment is intentionally excluded because HTTP clients must not
   --  send
   --  fragments in request targets.

   function Host_Header_Value (Item : URI_Reference) return String
   with
      Pre => Is_Parsed (Item);
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return the value suitable for a Host header.
   --
   --  Default ports are omitted. Non-default explicit ports are appended.

private
   use Ada.Strings.Unbounded;

   type URI_Reference is record
      Original          : Unbounded_String;
      Parsed            : Boolean := False;
      Scheme_Text       : Unbounded_String;
      Host_Text         : Unbounded_String;
      Host_Class        : Host_Kind := DNS_Name;
      Port_Present      : Boolean := False;
      Port_Value        : Natural := 0;
      Path_Text         : Unbounded_String;
      Query_Present     : Boolean := False;
      Query_Text        : Unbounded_String;
      Fragment_Present  : Boolean := False;
      Fragment_Text     : Unbounded_String;
   end record;
end Http_Client.URI;
