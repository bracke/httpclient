with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.URI;

package Http_Client.Auth.Scopes is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Explicit authentication scope helpers.
   --
   --  Advanced authentication credentials should be bound to a precise origin
   --  tuple or to explicit proxy configuration owned by Http_Client.Proxies.
   --  This package provides small Ada-native helpers for caller policies that
   --  want to verify origin credential applicability before attaching
   --  Authorization. It does not store credentials and does not apply headers.

   type Origin_Scope is private;
   --  Origin authentication scope: scheme, normalized host, and effective port.

   function Create_Origin
     (URI   : Http_Client.URI.URI_Reference;
      Scope : out Origin_Scope) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param URI Subprogram parameter.
   --  @param Scope Subprogram parameter.
   --  Create a scope from a parsed HTTP/HTTPS origin URI.
   --
   --  @return Ok on success, Invalid_URI when URI was not parsed.

   function Matches
     (Scope : Origin_Scope;
      URI   : Http_Client.URI.URI_Reference) return Boolean;
   --  GNATdoc contract.
   --  @param Scope Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only when URI has the same scheme, host, and effective port.
   --
   --  Path, query, and fragment are intentionally ignored because HTTP
   --  authentication scope is origin-bound here; callers that require narrower
   --  protection spaces can layer their own realm/path checks on top.

   function Scheme (Scope : Origin_Scope) return String;
   --  GNATdoc contract.
   --  @param Scope Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized scheme for diagnostics or policy checks.

   function Host (Scope : Origin_Scope) return String;
   --  GNATdoc contract.
   --  @param Scope Subprogram parameter.
   --  @return Subprogram result.
   --  Return the normalized host for diagnostics or policy checks.

   function Port (Scope : Origin_Scope) return Http_Client.URI.TCP_Port;
   --  GNATdoc contract.
   --  @param Scope Subprogram parameter.
   --  @return Subprogram result.
   --  Return the effective TCP port for diagnostics or policy checks.

private
   use Ada.Strings.Unbounded;

   type Origin_Scope is record
      Valid       : Boolean := False;
      Scheme_Text : Unbounded_String;
      Host_Text   : Unbounded_String;
      Port_Value  : Http_Client.URI.TCP_Port := 1;
   end record;
end Http_Client.Auth.Scopes;
