with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.HTTPS_Records is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Deterministic HTTPS/SVCB record parsing and selection helpers.
   --
   --  This package models scripted HTTPS/SVCB DNS results for tests and
   --  resolver backends. It does not perform public DNS queries, does not
   --  validate DNSSEC, does not implement ECH, and does not treat address hints
   --  as authoritative. Parsed records may help select an HTTP/3-capable
   --  alternative endpoint only when higher-level protocol discovery policy is
   --  explicitly enabled and TLS/QUIC verification still validates the
   --  original origin name.

   Max_Records          : constant Positive := 8;
   Max_ALPN_Per_Record  : constant Positive := 4;
   Default_HTTPS_Port   : constant Natural := 443;

   type ALPN_ID is (ALPN_H2, ALPN_H3, ALPN_H3_29, ALPN_Unsupported);

   type ALPN_Array is array (Positive range 1 .. Max_ALPN_Per_Record) of ALPN_ID;

   type HTTPS_Record is record
      Priority       : Natural := 0;
      Target_Name    : Ada.Strings.Unbounded.Unbounded_String;
      Port           : Natural := Default_HTTPS_Port;
      ALPN_Count     : Natural range 0 .. Max_ALPN_Per_Record := 0;
      ALPNs          : ALPN_Array := (others => ALPN_Unsupported);
      Has_ECH        : Boolean := False;
      Has_IPv4_Hint  : Boolean := False;
      Has_IPv6_Hint  : Boolean := False;
   end record;
   --  Parsed HTTPS/SVCB service-form record.
   --
   --  ECH and address hints are retained only as structural metadata. This
   --  release does not implement ECH or authoritative use of hints.

   type HTTPS_Record_Array is array (Positive range 1 .. Max_Records) of HTTPS_Record;

   type HTTPS_Record_List is record
      Count : Natural range 0 .. Max_Records := 0;
      Items : HTTPS_Record_Array := (others => <>);
   end record;

   type Selected_HTTPS_Service is record
      Available   : Boolean := False;
      Target_Name : Ada.Strings.Unbounded.Unbounded_String;
      Port        : Natural := Default_HTTPS_Port;
      ALPN        : ALPN_ID := ALPN_Unsupported;
   end record;
   --  Deterministic supported service selected from records.

   function Parse_Text_Record
     (Text   : String;
      Item : out HTTPS_Record) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Text Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Parse a scripted textual HTTPS/SVCB record.
   --
   --  The accepted deterministic test format is:
   --  `priority target key=value key=value`, with recognized keys `alpn`,
   --  `port`, `ipv4hint`, `ipv6hint`, and `ech`. Duplicate parameters and
   --  malformed values are rejected. Unsupported ALPN values are retained as
   --  unsupported and ignored by selection.

   function Append
     (List   : in out HTTPS_Record_List;
      Item : HTTPS_Record) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Append Item to a bounded scripted resolver result.

   function Select_HTTP3
     (List : HTTPS_Record_List) return Selected_HTTPS_Service;
   --  GNATdoc contract.
   --  @param List Subprogram parameter.
   --  @return Subprogram result.
   --  Select the lowest-priority record advertising final h3.
   --  Records advertising only unsupported ALPN values or only h2 are ignored.

   function ALPN_Image (Value : ALPN_ID) return String;
   --  GNATdoc contract.
   --  @param Value Subprogram parameter.
   --  @return Subprogram result.
end Http_Client.HTTPS_Records;
