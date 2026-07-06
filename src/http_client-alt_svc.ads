with Ada.Calendar;
with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.Alt_Svc is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Conservative HTTP Alt-Svc header parser.
   --
   --  This package owns only Alt-Svc header syntax and bounded metadata. It
   --  performs no DNS lookup, no network I/O, no TLS verification, no HTTP/3
   --  execution, and no persistence. Higher layers must explicitly enable
   --  discovery and must still verify TLS authority for the original origin
   --  name before sending credentials, cookies, or request bytes through an
   --  alternative service.

   Max_Alternatives_Per_Header : constant Positive := 8;
   Default_Max_Header_Length   : constant Positive := 8_192;
   Default_Max_Age_Seconds     : constant Natural := 86_400;

   type Alternative_Protocol is
     (Alt_Protocol_HTTP3,
      Alt_Protocol_HTTP3_29);
   --  Supported Alt-Svc protocol identifiers for this phase.
   --  Unsupported identifiers are rejected rather than treated as opaque.

   type Alternative is record
      Protocol        : Alternative_Protocol := Alt_Protocol_HTTP3;
      Host            : Ada.Strings.Unbounded.Unbounded_String;
      Host_Is_Origin  : Boolean := False;
      Port            : Natural := 0;
      Max_Age_Seconds : Natural := 0;
      Expires_At      : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Persist         : Boolean := False;
   end record;
   --  Parsed alternative service metadata.
   --
   --  @field Host_Is_Origin True for authorities such as `:443`, meaning the
   --         original origin host is used. This does not alter TLS authority
   --         validation: verification remains for the original origin.

   type Alternative_Array is
     array (Positive range 1 .. Max_Alternatives_Per_Header) of Alternative;

   type Parse_Result is record
      Clear        : Boolean := False;
      Count        : Natural range 0 .. Max_Alternatives_Per_Header := 0;
      Alternatives : Alternative_Array := (others => <>);
   end record;
   --  Parsed Alt-Svc result. Clear represents the exact `clear` directive.

   function Parse_Header
     (Header          : String;
      Received_At     : Ada.Calendar.Time;
      Result          : out Parse_Result;
      Maximum_Max_Age : Natural := Default_Max_Age_Seconds)
      return Http_Client.Errors.Result_Status;
   --  Parse one Alt-Svc header field value.
   --
   --  @param Header Header value without the field name.
   --  @param Received_At Deterministic receipt time used for expiration.
   --  @param Result Parsed clear directive or bounded alternatives.
   --  @param Maximum_Max_Age Upper bound for accepted `ma` lifetimes.
   --  @return Ok on success, Invalid_Header for malformed or ambiguous syntax,
   --          Header_Too_Large for overlong input, or Unsupported_Feature for
   --          unsupported protocol identifiers.

   function Select_First_HTTP3 (Result : Parse_Result) return Natural;
   --  GNATdoc contract.
   --  @param Result Subprogram parameter.
   --  @return Subprogram result.
   --  Return the first final-h3 alternative index, or 0 if none exists.

   function Is_Expired
     (Item : Alternative;
      Now  : Ada.Calendar.Time) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Now Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item is expired at Now.

   function Protocol_Image (Protocol : Alternative_Protocol) return String;
   --  GNATdoc contract.
   --  @param Protocol Subprogram parameter.
   --  @return Subprogram result.
   --  Return the wire protocol identifier.
end Http_Client.Alt_Svc;
