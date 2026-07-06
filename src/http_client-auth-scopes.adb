with Ada.Strings.Unbounded;
with Http_Client.Errors;
with Http_Client.URI;

package body Http_Client.Auth.Scopes is
   use Ada.Strings.Unbounded;

   function Create_Origin
     (URI   : Http_Client.URI.URI_Reference;
      Scope : out Origin_Scope) return Http_Client.Errors.Result_Status
   is
   begin
      Scope := (Valid => False,
                Scheme_Text => Null_Unbounded_String,
                Host_Text => Null_Unbounded_String,
                Port_Value => 1);
      if not Http_Client.URI.Is_Parsed (URI) then
         return Http_Client.Errors.Invalid_URI;
      end if;

      Scope.Valid := True;
      Scope.Scheme_Text := To_Unbounded_String (Http_Client.URI.Scheme (URI));
      Scope.Host_Text := To_Unbounded_String (Http_Client.URI.Host (URI));
      Scope.Port_Value := Http_Client.URI.Effective_Port (URI);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Scope := (Valid => False,
                   Scheme_Text => Null_Unbounded_String,
                   Host_Text => Null_Unbounded_String,
                   Port_Value => 1);
         return Http_Client.Errors.Invalid_URI;
   end Create_Origin;

   function Matches
     (Scope : Origin_Scope;
      URI   : Http_Client.URI.URI_Reference) return Boolean
   is
   begin
      return Scope.Valid
        and then Http_Client.URI.Is_Parsed (URI)
        and then To_String (Scope.Scheme_Text) = Http_Client.URI.Scheme (URI)
        and then To_String (Scope.Host_Text) = Http_Client.URI.Host (URI)
        and then Scope.Port_Value = Http_Client.URI.Effective_Port (URI);
   exception
      when others =>
         return False;
   end Matches;

   function Scheme (Scope : Origin_Scope) return String is
   begin
      return To_String (Scope.Scheme_Text);
   end Scheme;

   function Host (Scope : Origin_Scope) return String is
   begin
      return To_String (Scope.Host_Text);
   end Host;

   function Port (Scope : Origin_Scope) return Http_Client.URI.TCP_Port is
   begin
      return Scope.Port_Value;
   end Port;
end Http_Client.Auth.Scopes;
