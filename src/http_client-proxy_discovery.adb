with Ada.Characters.Handling;
with Ada.Directories; use Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with Http_Client.URI;

package body Http_Client.Proxy_Discovery is
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;

   function Trim (Text : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both);
   end Trim;

   function Has_Control (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Character'Pos (Ch) < 32 or else Character'Pos (Ch) = 127 then
            return True;
         end if;
      end loop;
      return False;
   end Has_Control;

   function Has_PAC_Return_Control (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Ch = Character'Val (9) then
            null;
         elsif Character'Pos (Ch) < 32 or else Character'Pos (Ch) = 127 then
            return True;
         end if;
      end loop;
      return False;
   end Has_PAC_Return_Control;

   function Has_Non_Text_Control (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if (Character'Pos (Ch) < 32
             and then Ch /= Character'Val (9)
             and then Ch /= Character'Val (10)
             and then Ch /= Character'Val (13))
           or else Character'Pos (Ch) = 127
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Non_Text_Control;

   function Is_WSpace (Ch : Character) return Boolean is
   begin
      return Ch = ' ' or else Ch = Character'Val (9);
   end Is_WSpace;

   function Is_Domain_Label_Char (Ch : Character) return Boolean is
   begin
      return Ch in 'a' .. 'z'
        or else Ch in 'A' .. 'Z'
        or else Ch in '0' .. '9'
        or else Ch = '-';
   end Is_Domain_Label_Char;

   function Host_Is_Valid (Host : String) return Boolean is
      Label_Length : Natural := 0;
      Last_Was_Dot : Boolean := False;
      Label_First   : Natural := 0;
      Previous      : Character := Character'Val (0);
   begin
      if Host'Length = 0 or else Host'Length > 253 then
         return False;
      end if;

      for I in Host'Range loop
         if Host (I) = '.' then
            if Label_Length = 0
              or else Last_Was_Dot
              or else Host (Label_First) = '-'
              or else Previous = '-'
            then
               return False;
            end if;
            Label_Length := 0;
            Label_First := 0;
            Last_Was_Dot := True;
         elsif Is_Domain_Label_Char (Host (I)) then
            if Label_Length = 0 then
               Label_First := I;
            end if;
            Label_Length := Label_Length + 1;
            if Label_Length > 63 then
               return False;
            end if;
            Last_Was_Dot := False;
         else
            return False;
         end if;
         Previous := Host (I);
      end loop;

      return Label_Length > 0
        and then not Last_Was_Dot
        and then Host (Label_First) /= '-'
        and then Previous /= '-';
   end Host_Is_Valid;

   function Endpoint_To_Config
     (Scheme : String;
      Host   : String;
      Port   : Natural;
      Config : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
      Port_Image : constant String := Natural'Image (Port);
   begin
      Config := Http_Client.Proxies.No_Proxy_Config;
      if not Host_Is_Valid (Host) or else Port = 0 or else Port > 65_535 then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      if Scheme = "http" then
         return Http_Client.Proxies.Parse
           ("http://" & Host & ":" &
            Port_Image (Port_Image'First + 1 .. Port_Image'Last),
            Config);
      elsif Scheme = "socks5" then
         return Http_Client.Proxies.Parse
           ("socks5://" & Host & ":" &
            Port_Image (Port_Image'First + 1 .. Port_Image'Last),
            Config);
      else
         return Http_Client.Errors.Proxy_Unsupported;
      end if;
   end Endpoint_To_Config;

   procedure Add_Candidate
     (Decision : in out Route_Decision;
      Item     : Proxy_Candidate;
      Options  : Discovery_Options;
      Status   : in out Http_Client.Errors.Result_Status)
   is
   begin
      if Status /= Http_Client.Errors.Ok then
         return;
      end if;

      if Decision.Count >= Max_Proxy_Candidates
        or else Decision.Count >= Options.Limits.Max_Candidates
      then
         Status := Http_Client.Errors.Cache_Limit_Exceeded;
         return;
      end if;

      Decision.Count := Decision.Count + 1;
      Decision.Items (Decision.Count) := Item;
   end Add_Candidate;

   function Parse_Port (Text : String; Value : out Natural) return Boolean is
   begin
      Value := 0;
      if Text'Length = 0 then
         return False;
      end if;
      for Ch of Text loop
         if Ch not in '0' .. '9' then
            return False;
         end if;
         Value := Value * 10 + Character'Pos (Ch) - Character'Pos ('0');
         if Value > 65_535 then
            return False;
         end if;
      end loop;
      return Value in 1 .. 65_535;
   end Parse_Port;

   function Contains_Credential_Syntax (Text : String) return Boolean is
   begin
      for Ch of Text loop
         if Ch = '@' then
            return True;
         end if;
      end loop;
      return Ada.Strings.Fixed.Index (Lower (Text), "://") /= 0;
   end Contains_Credential_Syntax;

   function Parse_Endpoint
     (Rest     : String;
      Kind     : Proxy_Candidate_Kind;
      Raw      : String;
      Item     : out Proxy_Candidate)
      return Http_Client.Errors.Result_Status
   is
      Host_Last : Natural := 0;
      Port      : Natural := 0;
   begin
      Item := (Candidate_Type => Kind,
               Candidate_Host => Null_Unbounded_String,
               Candidate_Port => 1,
               Raw            => To_Unbounded_String (Raw));

      if Rest'Length = 0 or else Contains_Credential_Syntax (Rest) then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      for I in reverse Rest'Range loop
         if Rest (I) = ':' then
            Host_Last := I - 1;
            if Host_Last < Rest'First then
               return Http_Client.Errors.Invalid_Proxy;
            end if;
            if not Parse_Port (Rest (I + 1 .. Rest'Last), Port) then
               return Http_Client.Errors.Invalid_Proxy;
            end if;
            exit;
         end if;
      end loop;

      if Host_Last = 0 then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      declare
         Host_Text : constant String := Rest (Rest'First .. Host_Last);
      begin
         if not Host_Is_Valid (Host_Text) then
            return Http_Client.Errors.Invalid_Proxy;
         end if;
         Item.Candidate_Host := To_Unbounded_String (Lower (Host_Text));
         Item.Candidate_Port := Http_Client.URI.TCP_Port (Port);
      end;

      return Http_Client.Errors.Ok;
   end Parse_Endpoint;

   function First_Return_String (Text : String; Start : Positive := 1) return String is
      R : Natural := Ada.Strings.Fixed.Index (Text, "return", From => Start);
      Q1 : Natural := 0;
      Q2 : Natural := 0;
   begin
      if R = 0 then
         return "";
      end if;
      for I in R + 6 .. Text'Last loop
         if Text (I) = '"' then
            Q1 := I;
            exit;
         elsif not Is_WSpace (Text (I)) then
            null;
         end if;
      end loop;
      if Q1 = 0 then
         return "";
      end if;
      for I in Q1 + 1 .. Text'Last loop
         if Text (I) = '"' then
            Q2 := I;
            exit;
         end if;
      end loop;
      if Q2 = 0 then
         return "";
      end if;
      return Text (Q1 + 1 .. Q2 - 1);
   end First_Return_String;

   function Extract_Quoted_Argument
     (Call_Text : String;
      Argument  : Positive) return String
   is
      Current : Positive := 1;
      Q1      : Natural := 0;
      Q2      : Natural := 0;
   begin
      for I in Call_Text'Range loop
         if Call_Text (I) = '"' then
            Q1 := I;
            for J in I + 1 .. Call_Text'Last loop
               if Call_Text (J) = '"' then
                  Q2 := J;
                  exit;
               end if;
            end loop;
            if Q2 = 0 then
               return "";
            end if;
            if Current = Argument then
               return Call_Text (Q1 + 1 .. Q2 - 1);
            end if;
            Current := Current + 1;
         end if;
      end loop;
      return "";
   end Extract_Quoted_Argument;

   function Ends_With (Text : String; Suffix : String) return Boolean is
   begin
      return Text'Length >= Suffix'Length
        and then Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix;
   end Ends_With;

   function Match_Sh_Expression (Text : String; Pattern : String) return Boolean is
      function Match_At (T : Natural; P : Natural) return Boolean is
      begin
         if P > Pattern'Last then
            return T > Text'Last;
         elsif Pattern (P) = '*' then
            for I in T .. Text'Last + 1 loop
               if Match_At (I, P + 1) then
                  return True;
               end if;
            end loop;
            return False;
         elsif Pattern (P) = '?' then
            return T <= Text'Last and then Match_At (T + 1, P + 1);
         else
            return T <= Text'Last
              and then Pattern (P) = Text (T)
              and then Match_At (T + 1, P + 1);
         end if;
      end Match_At;
   begin
      if Pattern'Length = 0 then
         return Text'Length = 0;
      end if;
      return Match_At (Text'First, Pattern'First);
   end Match_Sh_Expression;


   function Validate
     (Options : Discovery_Options) return Http_Client.Errors.Result_Status is
   begin
      if Options.Limits.Max_Script_Size = 0
        or else Options.Limits.Max_Return_Length = 0
        or else Options.Limits.Max_Token_Length = 0
        or else Options.Limits.Max_Candidates = 0
        or else Options.Limits.Max_Candidates > Max_Proxy_Candidates
        or else Options.Limits.Max_Evaluation_Steps = 0
        or else Options.Limits.Max_WPAD_Attempts = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Enable_WPAD_DNS and then not Options.Enabled then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      return Http_Client.Errors.Ok;
   end Validate;

   function Empty_Decision return Route_Decision is
   begin
      return (Count => 0, Items => (others => (others => <>)));
   end Empty_Decision;

   function Direct_Decision return Route_Decision is
      D : Route_Decision := Empty_Decision;
   begin
      D.Count := 1;
      D.Items (1) :=
        (Candidate_Type => Candidate_Direct,
         Candidate_Host => Null_Unbounded_String,
         Candidate_Port => 1,
         Raw            => To_Unbounded_String ("DIRECT"));
      return D;
   end Direct_Decision;

   function Candidate_Count (Decision : Route_Decision) return Natural is
   begin
      return Decision.Count;
   end Candidate_Count;

   function Candidate
     (Decision : Route_Decision;
      Index    : Positive) return Proxy_Candidate is
   begin
      if Index > Decision.Count then
         return (Candidate_Type => Candidate_Unsupported,
                 Candidate_Host => Null_Unbounded_String,
                 Candidate_Port => 1,
                 Raw            => Null_Unbounded_String);
      end if;
      return Decision.Items (Index);
   end Candidate;

   function Kind (Item : Proxy_Candidate) return Proxy_Candidate_Kind is
   begin
      return Item.Candidate_Type;
   end Kind;

   function Host (Item : Proxy_Candidate) return String is
   begin
      return To_String (Item.Candidate_Host);
   end Host;

   function Port (Item : Proxy_Candidate) return Http_Client.URI.TCP_Port is
   begin
      return Item.Candidate_Port;
   end Port;

   function Raw_Directive (Item : Proxy_Candidate) return String is
   begin
      return To_String (Item.Raw);
   end Raw_Directive;

   function Parse_PAC_Return
     (Text     : String;
      Options  : Discovery_Options;
      Decision : out Route_Decision) return Http_Client.Errors.Result_Status
   is
      Start  : Positive := Text'First;
      Stop   : Natural;
      Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   begin
      Decision := Empty_Decision;

      if Text'Length = 0
        or else Text'Length > Options.Limits.Max_Return_Length
        or else Has_PAC_Return_Control (Text)
      then
         if Options.Failure = Fail_Open_Direct then
            Decision := Direct_Decision;
            return Http_Client.Errors.Ok;
         end if;
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      while Start <= Text'Last loop
         Stop := Start;
         while Stop <= Text'Last and then Text (Stop) /= ';' loop
            Stop := Stop + 1;
         end loop;

         declare
            Token : constant String := Trim (Text (Start .. Stop - 1));
         begin
            if Token'Length = 0 or else Token'Length > Options.Limits.Max_Token_Length then
               Status := Http_Client.Errors.Invalid_Proxy;
            elsif Lower (Token) = "direct" then
               Add_Candidate
                 (Decision,
                  (Candidate_Type => Candidate_Direct,
                   Candidate_Host => Null_Unbounded_String,
                   Candidate_Port => 1,
                   Raw            => To_Unbounded_String (Token)),
                  Options,
                  Status);
            else
               declare
                  Space : Natural := 0;
               begin
                  for I in Token'Range loop
                     if Is_WSpace (Token (I)) then
                        Space := I;
                        exit;
                     end if;
                  end loop;

                  if Space = 0 then
                     case Options.Unsupported_Directives is
                        when Reject_Unsupported_Directive =>
                           Status := Http_Client.Errors.Proxy_Unsupported;
                        when Skip_Unsupported_Directive =>
                           null;
                        when Surface_Unsupported_Directive =>
                           Add_Candidate
                             (Decision,
                              (Candidate_Type => Candidate_Unsupported,
                               Candidate_Host => Null_Unbounded_String,
                               Candidate_Port => 1,
                               Raw            => To_Unbounded_String (Token)),
                              Options,
                              Status);
                     end case;
                  else
                     declare
                        Name : constant String := Lower (Token (Token'First .. Space - 1));
                        Rest : constant String := Trim (Token (Space + 1 .. Token'Last));
                        Item : Proxy_Candidate;
                        K    : Proxy_Candidate_Kind := Candidate_Unsupported;
                     begin
                        if Name = "proxy" then
                           K := Candidate_HTTP_Proxy;
                        elsif Name = "https" then
                           K := Candidate_HTTPS_Proxy;
                        elsif Name = "socks" then
                           K := Candidate_SOCKS_Proxy;
                        elsif Name = "socks5" then
                           K := Candidate_SOCKS5_Proxy;
                        else
                           K := Candidate_Unsupported;
                        end if;

                        if K = Candidate_Unsupported then
                           case Options.Unsupported_Directives is
                              when Reject_Unsupported_Directive =>
                                 Status := Http_Client.Errors.Proxy_Unsupported;
                              when Skip_Unsupported_Directive =>
                                 null;
                              when Surface_Unsupported_Directive =>
                                 Add_Candidate
                                   (Decision,
                                    (Candidate_Type => Candidate_Unsupported,
                                     Candidate_Host => Null_Unbounded_String,
                                     Candidate_Port => 1,
                                     Raw            => To_Unbounded_String (Token)),
                                    Options,
                                    Status);
                           end case;
                        else
                           Status := Parse_Endpoint (Rest, K, Token, Item);
                           Add_Candidate (Decision, Item, Options, Status);
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;

         exit when Status /= Http_Client.Errors.Ok;
         Start := Stop + 1;
      end loop;

      if Status = Http_Client.Errors.Ok and then Decision.Count = 0 then
         Status := Http_Client.Errors.Invalid_Proxy;
      end if;

      if Status /= Http_Client.Errors.Ok and then Options.Failure = Fail_Open_Direct then
         Decision := Direct_Decision;
         return Http_Client.Errors.Ok;
      end if;

      return Status;
   exception
      when others =>
         Decision := Empty_Decision;
         if Options.Failure = Fail_Open_Direct then
            Decision := Direct_Decision;
            return Http_Client.Errors.Ok;
         end if;
         return Http_Client.Errors.Invalid_Proxy;
   end Parse_PAC_Return;

   function Evaluate_PAC
     (Script   : String;
      Target   : Http_Client.URI.URI_Reference;
      Options  : Discovery_Options;
      Decision : out Route_Decision) return Http_Client.Errors.Result_Status
   is
      Script_Lower : constant String := Lower (Script);
      Steps        : Natural := 0;

      function Fail (Status : Http_Client.Errors.Result_Status)
        return Http_Client.Errors.Result_Status is
      begin
         if Options.Failure = Fail_Open_Direct then
            Decision := Direct_Decision;
            return Http_Client.Errors.Ok;
         else
            Decision := Empty_Decision;
            return Status;
         end if;
      end Fail;

      function Next_Return_After (From : Positive) return String is
      begin
         Steps := Steps + 1;
         if Steps > Options.Limits.Max_Evaluation_Steps then
            return "";
         end if;
         return First_Return_String (Script, From);
      end Next_Return_After;
   begin
      Decision := Empty_Decision;
      if not Options.Enabled then
         return Http_Client.Errors.Proxy_Unsupported;
      end if;
      if not Http_Client.URI.Is_Parsed (Target) then
         return Http_Client.Errors.Invalid_URI;
      end if;
      if Script'Length = 0 or else Script'Length > Options.Limits.Max_Script_Size then
         return Fail (Http_Client.Errors.Invalid_Proxy);
      end if;
      if Has_Non_Text_Control (Script) then
         return Fail (Http_Client.Errors.Invalid_Proxy);
      end if;

      if Ada.Strings.Fixed.Index (Script_Lower, "dnsresolve") /= 0
        or else Ada.Strings.Fixed.Index (Script_Lower, "isinnet") /= 0
        or else Ada.Strings.Fixed.Index (Script_Lower, "myipaddress") /= 0
        or else Ada.Strings.Fixed.Index (Script_Lower, "while") /= 0
        or else Ada.Strings.Fixed.Index (Script_Lower, "for (") /= 0
        or else Ada.Strings.Fixed.Index (Script_Lower, "function ", From => 2) /= 0
      then
         return Fail (Http_Client.Errors.Unsupported_Feature);
      end if;

      declare
         Host       : constant String := Http_Client.URI.Host (Target);
         URL        : constant String := Http_Client.URI.Image (Target);
         Cond_Index : Natural := Ada.Strings.Fixed.Index (Script_Lower, "if");
         Ret        : Unbounded_String := Null_Unbounded_String;
      begin
         if Cond_Index /= 0 then
            if Ada.Strings.Fixed.Index (Script_Lower, "dnsdomainis", From => Cond_Index) /= 0 then
               declare
                  Suffix : constant String := Lower (Extract_Quoted_Argument (Script, 1));
               begin
                  if Suffix'Length > 0 and then Ends_With (Lower (Host), Suffix) then
                     Ret := To_Unbounded_String (Next_Return_After (Cond_Index));
                  end if;
               end;
            elsif Ada.Strings.Fixed.Index (Script_Lower, "shexpmatch", From => Cond_Index) /= 0 then
               declare
                  Pattern : constant String := Extract_Quoted_Argument (Script, 1);
               begin
                  if Pattern'Length > 0 and then Match_Sh_Expression (URL, Pattern) then
                     Ret := To_Unbounded_String (Next_Return_After (Cond_Index));
                  end if;
               end;
            elsif Ada.Strings.Fixed.Index (Script_Lower, "isplainhostname", From => Cond_Index) /= 0 then
               if Ada.Strings.Fixed.Index (Host, ".") = 0 then
                  Ret := To_Unbounded_String (Next_Return_After (Cond_Index));
               end if;
            else
               return Fail (Http_Client.Errors.Unsupported_Feature);
            end if;
         end if;

         if Length (Ret) = 0 then
            Ret := To_Unbounded_String (First_Return_String (Script));
            if Cond_Index /= 0 and then Length (Ret) /= 0 then
               declare
                  First_Ret_Pos : constant Natural := Ada.Strings.Fixed.Index (Script_Lower, "return");
                  Second_Ret    : constant String :=
                    (if First_Ret_Pos = 0 then "" else First_Return_String (Script, First_Ret_Pos + 6));
               begin
                  if First_Ret_Pos > Cond_Index and then Second_Ret'Length > 0 then
                     Ret := To_Unbounded_String (Second_Ret);
                  end if;
               end;
            end if;
         end if;

         if Length (Ret) = 0 then
            return Fail (Http_Client.Errors.Invalid_Proxy);
         end if;

         return Parse_PAC_Return (To_String (Ret), Options, Decision);
      end;
   exception
      when others =>
         return Fail (Http_Client.Errors.Invalid_Proxy);
   end Evaluate_PAC;


   function Resolve_PAC_Script
     (Script  : String;
      Target  : Http_Client.URI.URI_Reference;
      Options : Discovery_Options;
      Config  : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
      Decision : Route_Decision;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Config := Http_Client.Proxies.No_Proxy_Config;
      Status := Evaluate_PAC
        (Script   => Script,
         Target   => Target,
         Options  => Options,
         Decision => Decision);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Select_First_Executable (Decision, Config);
   end Resolve_PAC_Script;

   function Load_PAC_File
     (Path     : String;
      Options  : Discovery_Options;
      Script   : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      use Ada.Streams;
      File : Ada.Streams.Stream_IO.File_Type;
   begin
      Script := Null_Unbounded_String;
      if Path'Length = 0 or else Has_Control (Path) then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      if not Ada.Directories.Exists (Path)
        or else Ada.Directories.Size (Path) = 0
        or else Ada.Directories.Size (Path) >
          Ada.Directories.File_Size (Options.Limits.Max_Script_Size)
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      declare
         Size : constant Natural := Natural (Ada.Streams.Stream_IO.Size (File));
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         Text : String (1 .. Size);
      begin
         Ada.Streams.Stream_IO.Read (File, Data, Last);
         Ada.Streams.Stream_IO.Close (File);
         if Last /= Data'Last then
            return Http_Client.Errors.Read_Failed;
         end if;
         for I in Text'Range loop
            Text (I) := Character'Val (Data (Stream_Element_Offset (I)));
         end loop;
         if Has_Non_Text_Control (Text) then
            return Http_Client.Errors.Invalid_Proxy;
         end if;
         Script := To_Unbounded_String (Text);
      end;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Script := Null_Unbounded_String;
         return Http_Client.Errors.Invalid_Configuration;
   end Load_PAC_File;

   function To_Proxy_Config
     (Item   : Proxy_Candidate;
      Config : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
   begin
      Config := Http_Client.Proxies.No_Proxy_Config;
      case Item.Candidate_Type is
         when Candidate_Direct =>
            return Http_Client.Errors.Ok;
         when Candidate_HTTP_Proxy =>
            return Endpoint_To_Config
              ("http", To_String (Item.Candidate_Host), Natural (Item.Candidate_Port), Config);
         when Candidate_SOCKS_Proxy | Candidate_SOCKS5_Proxy =>
            return Endpoint_To_Config
              ("socks5", To_String (Item.Candidate_Host), Natural (Item.Candidate_Port), Config);
         when Candidate_HTTPS_Proxy | Candidate_Unsupported =>
            return Http_Client.Errors.Proxy_Unsupported;
      end case;
   end To_Proxy_Config;

   function Select_First_Executable
     (Decision : Route_Decision;
      Config   : out Http_Client.Proxies.Proxy_Config)
      return Http_Client.Errors.Result_Status
   is
      Candidate_Status : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Proxy_Unsupported;
      First_Failure    : Http_Client.Errors.Result_Status :=
        Http_Client.Errors.Proxy_Unsupported;
   begin
      Config := Http_Client.Proxies.No_Proxy_Config;

      if Decision.Count = 0 then
         return Http_Client.Errors.Invalid_Proxy;
      end if;

      for Index in 1 .. Decision.Count loop
         Candidate_Status := To_Proxy_Config (Decision.Items (Index), Config);
         if Candidate_Status = Http_Client.Errors.Ok then
            return Http_Client.Errors.Ok;
         elsif Index = 1 then
            First_Failure := Candidate_Status;
         end if;
      end loop;

      Config := Http_Client.Proxies.No_Proxy_Config;
      return First_Failure;
   end Select_First_Executable;

   function Build_WPAD_URL
     (Base_Domain : String;
      Options     : Discovery_Options;
      URL         : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Domain : constant String := Lower (Trim (Base_Domain));
   begin
      URL := Null_Unbounded_String;
      if not Options.Enabled or else not Options.Enable_WPAD_DNS then
         return Http_Client.Errors.Proxy_Unsupported;
      end if;
      if Domain'Length = 0
        or else Domain'Length > Options.Limits.Max_Token_Length
        or else not Host_Is_Valid (Domain)
        or else Ada.Strings.Fixed.Index (Domain, ".") = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      URL := To_Unbounded_String ("http://wpad." & Domain & "/wpad.dat");
      return Http_Client.Errors.Ok;
   end Build_WPAD_URL;
end Http_Client.Proxy_Discovery;
