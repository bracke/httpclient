with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Http_Client.Protocol_Discovery is
   use Ada.Strings.Unbounded;
   use Ada.Calendar;
   use Http_Client.Errors;
   use Http_Client.HTTP3;
   use type Http_Client.Alt_Svc.Alternative_Protocol;

   function Key_For (URI : Http_Client.URI.URI_Reference) return Origin_Key is
   begin
      return (Scheme => To_Unbounded_String (Http_Client.URI.Scheme (URI)),
              Host   => To_Unbounded_String (Http_Client.URI.Host (URI)),
              Port   => Natural (Http_Client.URI.Effective_Port (URI)));
   end Key_For;

   function Same_Key (Left, Right : Origin_Key) return Boolean is
   begin
      return To_String (Left.Scheme) = To_String (Right.Scheme)
        and then To_String (Left.Host) = To_String (Right.Host)
        and then Left.Port = Right.Port;
   end Same_Key;

   function Normalize_SVCB_Target (Target : Unbounded_String) return Unbounded_String is
      Value : constant String := To_String (Target);
      Lower : String := Value;
   begin
      for I in Lower'Range loop
         Lower (I) := Ada.Characters.Handling.To_Lower (Lower (I));
      end loop;
      if Lower = "." or else Lower'Length = 0 or else Lower (Lower'Last) /= '.' then
         return To_Unbounded_String (Lower);
      end if;
      return To_Unbounded_String (Lower (Lower'First .. Lower'Last - 1));
   end Normalize_SVCB_Target;

   function Validate
     (Options : Discovery_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if Options.Maximum_Alt_Svc_Entries = 0
        or else Options.Maximum_Alt_Svc_Entries > Max_Cache_Entries
        or else Options.Maximum_Alternatives_Per_Origin = 0
        or else Options.Maximum_Alternatives_Per_Origin > Max_Alternatives_Per_Origin
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      return Http_Client.Errors.Ok;
   end Validate;

   procedure Initialize
     (Cache   : out Discovery_Cache;
      Options : Discovery_Options := Default_Discovery_Options)
   is
      pragma Unreferenced (Options);
   begin
      Cache := (Entries => (others => <>), Count => 0);
   end Initialize;

   procedure Clear (Cache : in out Discovery_Cache) is
   begin
      Cache := (Entries => (others => <>), Count => 0);
   end Clear;

   function Entry_Count (Cache : Discovery_Cache) return Natural is
   begin
      return Cache.Count;
   end Entry_Count;

   function Find_Entry
     (Cache : Discovery_Cache;
      Key   : Origin_Key) return Natural
   is
   begin
      for I in 1 .. Max_Cache_Entries loop
         if Cache.Entries (I).In_Use and then Same_Key (Cache.Entries (I).Key, Key) then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Entry;

   function First_Free (Cache : Discovery_Cache) return Natural is
   begin
      for I in 1 .. Max_Cache_Entries loop
         if not Cache.Entries (I).In_Use then
            return I;
         end if;
      end loop;
      return 0;
   end First_Free;

   function Accept_Alt_Svc
     (Cache                        : in out Discovery_Cache;
      Origin                       : Http_Client.URI.URI_Reference;
      Header                       : String;
      Received_At                  : Ada.Calendar.Time;
      Options                      : Discovery_Options := Default_Discovery_Options;
      From_Verified_HTTPS_Response : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
      Parsed : Http_Client.Alt_Svc.Parse_Result;
      Status : Http_Client.Errors.Result_Status;
      Key            : constant Origin_Key := Key_For (Origin);
      Index          : Natural;
      Has_Selectable : Boolean := False;
   begin
      Status := Validate (Options);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if not Options.Enable_Alt_Svc or else not Options.Allow_HTTP3_Discovery then
         return Http_Client.Errors.Ok;
      end if;
      if not From_Verified_HTTPS_Response
        or else Http_Client.URI.Scheme (Origin) /= "https"
      then
         return Http_Client.Errors.Invalid_Request;
      end if;
      Status := Http_Client.Alt_Svc.Parse_Header
        (Header, Received_At, Parsed, Options.Maximum_Alt_Svc_Age);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Index := Find_Entry (Cache, Key);
      if Parsed.Clear then
         if Index /= 0 then
            Cache.Entries (Index) := (others => <>);
            if Cache.Count > 0 then
               Cache.Count := Cache.Count - 1;
            end if;
         end if;
         return Http_Client.Errors.Ok;
      end if;
      for I in 1 .. Parsed.Count loop
         if Parsed.Alternatives (I).Protocol =
              Http_Client.Alt_Svc.Alt_Protocol_HTTP3
           and then Parsed.Alternatives (I).Expires_At > Received_At
         then
            Has_Selectable := True;
            exit;
         end if;
      end loop;
      if not Has_Selectable then
         if Index /= 0 then
            Cache.Entries (Index) := (others => <>);
            if Cache.Count > 0 then
               Cache.Count := Cache.Count - 1;
            end if;
         end if;
         return Http_Client.Errors.Ok;
      end if;
      if Index = 0 then
         if Cache.Count >= Options.Maximum_Alt_Svc_Entries then
            return Http_Client.Errors.Cache_Limit_Exceeded;
         end if;
         Index := First_Free (Cache);
         if Index = 0 then
            return Http_Client.Errors.Cache_Limit_Exceeded;
         end if;
         Cache.Entries (Index).In_Use := True;
         Cache.Entries (Index).Key := Key;
         Cache.Count := Cache.Count + 1;
      else
         Cache.Entries (Index).Alternatives := (others => <>);
         Cache.Entries (Index).Count := 0;
      end if;
      for I in 1 .. Parsed.Count loop
         declare
            Alt : constant Http_Client.Alt_Svc.Alternative := Parsed.Alternatives (I);
         begin
            if Alt.Protocol = Http_Client.Alt_Svc.Alt_Protocol_HTTP3
              and then Alt.Expires_At > Received_At
            then
               exit when Cache.Entries (Index).Count >=
                 Options.Maximum_Alternatives_Per_Origin;
               Cache.Entries (Index).Count := Cache.Entries (Index).Count + 1;
               declare
                  Slot : constant Positive := Cache.Entries (Index).Count;
               begin
                  Cache.Entries (Index).Alternatives (Slot) :=
                    (In_Use         => True,
                     Protocol       => Alt.Protocol,
                     Host           => (if Alt.Host_Is_Origin then Key.Host else Alt.Host),
                     Host_Is_Origin => Alt.Host_Is_Origin,
                     Port           => Alt.Port,
                     Expires_At     => Alt.Expires_At);
               end;
            end if;
         end;
      end loop;
      if Cache.Entries (Index).Count = 0 then
         Cache.Entries (Index) := (others => <>);
         if Cache.Count > 0 then
            Cache.Count := Cache.Count - 1;
         end if;
      end if;
      return Http_Client.Errors.Ok;
   end Accept_Alt_Svc;

   function Empty_Selection return Discovery_Selection is
   begin
      return (Source => Discovery_None,
              Protocol => Http_Client.HTTP3.Protocol_None,
              Alternative_Host => Null_Unbounded_String,
              Alternative_Port => 0,
              Uses_Origin_Host => False,
              Requires_Origin_TLS_Authority => True);
   end Empty_Selection;

   function Selection
     (Cache     : in out Discovery_Cache;
      Origin    : Http_Client.URI.URI_Reference;
      Options   : Discovery_Options;
      HTTP3     : Http_Client.HTTP3.HTTP3_Options;
      Proxy     : Http_Client.Proxies.Proxy_Config;
      Now       : Ada.Calendar.Time;
      Selection : out Discovery_Selection) return Http_Client.Errors.Result_Status
   is
      Key    : constant Origin_Key := Key_For (Origin);
      Index  : Natural;
      Status : Http_Client.Errors.Result_Status;
   begin
      Selection := Empty_Selection;
      Status := Validate (Options);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Status := Http_Client.HTTP3.Validate (HTTP3);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if not Options.Allow_HTTP3_Discovery
        or else HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled
      then
         return Http_Client.Errors.Ok;
      end if;
      if Http_Client.Proxies.Is_Enabled (Proxy) then
         return Http_Client.Errors.Ok;
      end if;
      if Options.Enable_Alt_Svc then
         Index := Find_Entry (Cache, Key);
         if Index /= 0 then
            for I in 1 .. Cache.Entries (Index).Count loop
               if Cache.Entries (Index).Alternatives (I).In_Use then
                  if Cache.Entries (Index).Alternatives (I).Protocol
                    /= Http_Client.Alt_Svc.Alt_Protocol_HTTP3
                    or else Cache.Entries (Index).Alternatives (I).Expires_At <= Now
                  then
                     Cache.Entries (Index).Alternatives (I).In_Use := False;
                  else
                     Selection :=
                       (Source => Discovery_Alt_Svc,
                        Protocol => Http_Client.HTTP3.Protocol_HTTP_3,
                        Alternative_Host => Cache.Entries (Index).Alternatives (I).Host,
                        Alternative_Port => Cache.Entries (Index).Alternatives (I).Port,
                        Uses_Origin_Host => Cache.Entries (Index).Alternatives (I).Host_Is_Origin,
                        Requires_Origin_TLS_Authority => True);
                     return Http_Client.Errors.Ok;
                  end if;
               end if;
            end loop;
            Cache.Entries (Index) := (others => <>);
            if Cache.Count > 0 then
               Cache.Count := Cache.Count - 1;
            end if;
         end if;
      end if;
      if Options.Enable_HTTPS_SVCB
        and then Options.Resolver /= null
        and then Http_Client.URI.Scheme (Origin) = "https"
      then
         declare
            RR : constant Http_Client.DNS_SVCB.Resolver_Result :=
              Options.Resolver.all (Http_Client.URI.Host (Origin));
            R_Index : Natural;
         begin
            if RR.Status /= Http_Client.Errors.Ok then
               if RR.Status = Http_Client.Errors.Unsupported_Feature then
                  return Http_Client.Errors.Ok;
               end if;
               return RR.Status;
            end if;
            R_Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (RR.Records);
            if R_Index /= 0 then
               declare
                  Rec : constant Http_Client.DNS_SVCB.SVCB_Record := RR.Records.Items (R_Index);
                  Normalized_Target : constant Unbounded_String :=
                    Normalize_SVCB_Target (Rec.Target);
                  Target_Is_Origin : constant Boolean := To_String (Normalized_Target) = ".";
               begin
                  Selection :=
                    (Source => Discovery_HTTPS_SVCB,
                     Protocol => Http_Client.HTTP3.Protocol_HTTP_3,
                     Alternative_Host => (if Target_Is_Origin
                                          then To_Unbounded_String (Http_Client.URI.Host (Origin))
                                          else Normalized_Target),
                     Alternative_Port => Rec.Port,
                     Uses_Origin_Host => Target_Is_Origin,
                     Requires_Origin_TLS_Authority => True);
                  return Http_Client.Errors.Ok;
               end;
            end if;
         end;
      end if;
      return Http_Client.Errors.Ok;
   end Selection;

   function Fallback_Status
     (Options                    : Discovery_Options;
      Request_Bytes_Already_Sent : Boolean)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Options.Fallback = Discovery_Fallback_Before_Send
        and then not Request_Bytes_Already_Sent
      then
         return Http_Client.Errors.Ok;
      end if;
      return Http_Client.Errors.HTTP3_Fallback_Disallowed;
   end Fallback_Status;
end Http_Client.Protocol_Discovery;
