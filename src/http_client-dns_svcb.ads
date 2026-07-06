with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.DNS_SVCB is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Scripted HTTPS/SVCB record model for explicit protocol discovery.
   --
   --  This package is deliberately offline and deterministic. It parses test
   --  records supplied by a caller or resolver backend; it does not perform
   --  public DNS queries, DNSSEC validation, privacy-preserving DNS, ECH, or
   --  authoritative address-hint use. ECH and ipv4hint/ipv6hint are structural
   --  metadata only.

   Max_Records         : constant Positive := 8;
   Max_ALPN_Per_Record : constant Positive := 4;

   type ALPN_Array is array (Positive range 1 .. Max_ALPN_Per_Record)
     of Ada.Strings.Unbounded.Unbounded_String;

   type SVCB_Record is record
      Priority       : Natural := 1;
      Target         : Ada.Strings.Unbounded.Unbounded_String;
      Port           : Natural := 443;
      ALPN_Count     : Natural range 0 .. Max_ALPN_Per_Record := 0;
      ALPNs          : ALPN_Array := (others => Ada.Strings.Unbounded.Null_Unbounded_String);
      Has_ECH        : Boolean := False;
      Has_IPv4_Hint  : Boolean := False;
      Has_IPv6_Hint  : Boolean := False;
      TTL_Seconds    : Natural := 0;
   end record;
   --  Parsed scripted HTTPS/SVCB service-form record.

   type Record_Array is array (Positive range 1 .. Max_Records) of SVCB_Record;

   type Record_Set is record
      Count : Natural range 0 .. Max_Records := 0;
      Items : Record_Array := (others => <>);
   end record;

   type Resolver_Result is record
      Status  : Http_Client.Errors.Result_Status := Http_Client.Errors.Unsupported_Feature;
      Records : Record_Set;
   end record;
   --  Result returned by explicit resolver callbacks.

   function Parse_Record
     (Text   : String;
      Item : out SVCB_Record) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Text Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Parse deterministic `key=value` HTTPS/SVCB test-record text.
   --
   --  Recognized keys are priority, target, alpn, port, ipv4hint, ipv6hint,
   --  ech, and ttl. Alias-form priority 0 is rejected as Unsupported_Feature in
   --  this phase. Duplicate or malformed parameters are rejected.

   function Append
     (Set    : in out Record_Set;
      Item : SVCB_Record) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Set Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Append a record to a bounded set.

   function Has_ALPN
     (Item : SVCB_Record;
      ALPN   : String) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param ALPN Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Record advertises ALPN exactly, case-insensitively.

   function Select_HTTP3_Record (Set : Record_Set) return Natural;
   --  GNATdoc contract.
   --  @param Set Subprogram parameter.
   --  @return Subprogram result.
   --  Return the one-based index of the lowest-priority final-h3 record, or
   --  0 when no supported HTTP/3 record exists.
end Http_Client.DNS_SVCB;
