with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Resources;
with Http_Client.Responses;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Connection_Pools is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Proxies.SOCKS5_Authentication_Method;
   use type Http_Client.Proxies.SOCKS5_DNS_Mode;
   use type Http_Client.URI.TCP_Port;
   use type Http_Client.URI.Host_Kind;
   use type Http_Client.Responses.HTTP_Version;
   use type Http_Client.Types.Method_Name;
   use Http_Client.Errors;

   procedure Adjust_Idle_Counter (Before, After : Natural) is
   begin
      if After > Before then
         Http_Client.Resources.Increment
           (Http_Client.Resources.Pool_Idle_Entries, After - Before);
      elsif Before > After then
         Http_Client.Resources.Decrement
           (Http_Client.Resources.Pool_Idle_Entries, Before - After);
      end if;
   end Adjust_Idle_Counter;

   function Lower (Text : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (Text);
   end Lower;


   function Secret_Fingerprint (Text : Unbounded_String) return Natural is
      --  Bounded rolling fingerprint over the credential text. This is not a security primitive and
      --  must not be printed; it only prevents pooling across different
      --  passwords without retaining the raw password in the key.
      Modulus : constant Long_Long_Integer := 2 ** 30;
      Hash    : Long_Long_Integer := 2166136261 mod Modulus;
      S       : constant String := To_String (Text);
   begin
      for Ch of S loop
         Hash := (Hash + Long_Long_Integer (Character'Pos (Ch))) mod Modulus;
         Hash := (Hash * 16777619) mod Modulus;
      end loop;
      return Natural (Hash);
   end Secret_Fingerprint;

   function Seconds_Elapsed
     (Earlier : Ada.Calendar.Time;
      Later   : Ada.Calendar.Time) return Natural
   is
      Elapsed : constant Duration := Later - Earlier;
   begin
      if Elapsed <= 0.0 then
         return 0;
      elsif Elapsed >= Duration (Natural'Last) then
         return Natural'Last;
      else
         return Natural (Elapsed);
      end if;
   end Seconds_Elapsed;


   function Key_For
     (URI      : Http_Client.URI.URI_Reference;
      Proxy    : Http_Client.Proxies.Proxy_Config :=
        Http_Client.Proxies.No_Proxy_Config;
      TLS      : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      Protocol : Pooled_Protocol := Pool_HTTP_1_1)
      return Pool_Key
   is
      Result : Pool_Key;
   begin
      if not Http_Client.URI.Is_Parsed (URI)
        or else (Http_Client.URI.Scheme (URI) /= "http"
                 and then Http_Client.URI.Scheme (URI) /= "https")
      then
         return Result;
      end if;

      Result.Valid := True;
      Result.Protocol := Protocol;
      Result.Scheme := To_Unbounded_String (Lower (Http_Client.URI.Scheme (URI)));
      Result.Host := To_Unbounded_String (Lower (Http_Client.URI.Host (URI)));
      Result.Host_Class := Http_Client.URI.Kind_Of_Host (URI);
      Result.Port := Http_Client.URI.Effective_Port (URI);
      Result.Proxy_Mode := Http_Client.Proxies.Kind (Proxy);

      if Http_Client.Proxies.Is_Enabled (Proxy) then
         Result.Proxy_Host := To_Unbounded_String (Lower (Http_Client.Proxies.Host (Proxy)));
         Result.Proxy_Port := Http_Client.Proxies.Port (Proxy);
         Result.Proxy_Has_Auth := Http_Client.Proxies.Has_Proxy_Authorization (Proxy);

         if Http_Client.Proxies.Kind (Proxy) = Http_Client.Proxies.SOCKS5_Proxy then
            Result.SOCKS5_Auth := Http_Client.Proxies.SOCKS5_Authentication (Proxy);
            Result.SOCKS5_DNS := Http_Client.Proxies.SOCKS5_DNS_Resolution (Proxy);
            Result.SOCKS5_User_Key :=
              To_Unbounded_String (Http_Client.Proxies.SOCKS5_Username (Proxy));
            Result.SOCKS5_Pass_Present :=
              Http_Client.Proxies.SOCKS5_Password (Proxy)'Length > 0;
            Result.SOCKS5_Pass_Fingerprint :=
              Secret_Fingerprint
                (To_Unbounded_String (Http_Client.Proxies.SOCKS5_Password (Proxy)));
         end if;
      end if;

      if Http_Client.URI.Requires_TLS (URI) then
         Result.TLS_Verify := not TLS.Disable_Certificate_Verification;
         Result.TLS_CA_File := TLS.CA_File;
         Result.TLS_CA_Directory := TLS.CA_Directory;
         Result.TLS_Send_SNI := TLS.Send_SNI;

         if Http_Client.TLS.Client_Certificates.Is_Configured
              (TLS.Client_Certificate)
           and then Http_Client.TLS.Client_Certificates.Matches
              (TLS.Client_Certificate, URI)
         then
            Result.TLS_Client_Cert_ID :=
              Http_Client.TLS.Client_Certificates.Credential_ID
                (TLS.Client_Certificate);
            Result.TLS_Client_Cert_Material_Key :=
              TLS.Client_Certificate.Certificate_File &
              To_Unbounded_String (Character'Val (10) & "key=") &
              TLS.Client_Certificate.Private_Key_File;
         else
            Result.TLS_Client_Cert_ID := 0;
            Result.TLS_Client_Cert_Material_Key := Null_Unbounded_String;
         end if;
      end if;

      return Result;
   exception
      when others =>
         return (others => <>);
   end Key_For;

   function Is_Valid (Key : Pool_Key) return Boolean is
   begin
      return Key.Valid;
   end Is_Valid;

   function Same_Key (Left, Right : Pool_Key) return Boolean is
   begin
      return Left.Valid and then Right.Valid
        and then Left.Protocol = Right.Protocol
        and then Left.Scheme = Right.Scheme
        and then Left.Host = Right.Host
        and then Left.Host_Class = Right.Host_Class
        and then Left.Port = Right.Port
        and then Left.Proxy_Mode = Right.Proxy_Mode
        and then Left.Proxy_Host = Right.Proxy_Host
        and then Left.Proxy_Port = Right.Proxy_Port
        and then Left.Proxy_Has_Auth = Right.Proxy_Has_Auth
        and then Left.SOCKS5_Auth = Right.SOCKS5_Auth
        and then Left.SOCKS5_DNS = Right.SOCKS5_DNS
        and then Left.SOCKS5_User_Key = Right.SOCKS5_User_Key
        and then Left.SOCKS5_Pass_Present = Right.SOCKS5_Pass_Present
        and then Left.SOCKS5_Pass_Fingerprint = Right.SOCKS5_Pass_Fingerprint
        and then Left.TLS_Verify = Right.TLS_Verify
        and then Left.TLS_CA_File = Right.TLS_CA_File
        and then Left.TLS_CA_Directory = Right.TLS_CA_Directory
        and then Left.TLS_Send_SNI = Right.TLS_Send_SNI
        and then Left.TLS_Client_Cert_ID = Right.TLS_Client_Cert_ID
        and then Left.TLS_Client_Cert_Material_Key = Right.TLS_Client_Cert_Material_Key;
   end Same_Key;

   function Port_Image (Port : Http_Client.URI.TCP_Port) return String is
      Image_Value : constant String := Natural'Image (Natural (Port));
   begin
      return Image_Value (Image_Value'First + 1 .. Image_Value'Last);
   end Port_Image;

   function Protocol_Image (Protocol : Pooled_Protocol) return String is
   begin
      case Protocol is
         when Pool_HTTP_1_1 =>
            return "http/1.1";
         when Pool_HTTP_2 =>
            return "h2";
         when Pool_HTTP_3 =>
            return "h3";
      end case;
   end Protocol_Image;

   function Image (Key : Pool_Key) return String is
      Proxy_Text : Unbounded_String := Null_Unbounded_String;
   begin
      if not Key.Valid then
         return "<invalid-pool-key>";
      end if;

      if Key.Proxy_Mode = Http_Client.Proxies.No_Proxy then
         Proxy_Text := To_Unbounded_String ("direct");
      elsif Key.Proxy_Mode = Http_Client.Proxies.SOCKS5_Proxy then
         Proxy_Text :=
           To_Unbounded_String
             ("proxy=socks5://" & To_String (Key.Proxy_Host) & ":" &
              Port_Image (Key.Proxy_Port) &
              ";socks-auth=" &
              (if Key.SOCKS5_Auth = Http_Client.Proxies.SOCKS5_Username_Password
               then "present" else "absent") &
              ";socks-dns=" &
              (if Key.SOCKS5_DNS = Http_Client.Proxies.SOCKS5_Remote_DNS
               then "remote" else "local"));
      else
         Proxy_Text :=
           To_Unbounded_String
             ("proxy=http://" & To_String (Key.Proxy_Host) & ":" &
              Port_Image (Key.Proxy_Port) &
              (if Key.Proxy_Has_Auth then ";proxy-auth=present" else ";proxy-auth=absent"));
      end if;

      return To_String (Key.Scheme) & "://" &
        (if Key.Host_Class = Http_Client.URI.IPv6_Literal then
           "[" & To_String (Key.Host) & "]"
         else
           To_String (Key.Host)) & ":" &
        Port_Image (Key.Port) & ";protocol=" &
        Protocol_Image (Key.Protocol) & ";" & To_String (Proxy_Text) &
        ";tls-verify=" & (if Key.TLS_Verify then "true" else "false") &
        ";tls-sni=" & (if Key.TLS_Send_SNI then "true" else "false") &
        ";tls-client-cert=" &
        (if Key.TLS_Client_Cert_ID = 0 then "absent" else "present");
   end Image;

   function Validate
     (Options : Pooling_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if not Options.Enabled then
         return Http_Client.Errors.Ok;
      elsif Options.Max_Total_Idle_Connections = 0
        or else Options.Max_Idle_Connections_Per_Key = 0
        or else Options.Max_Idle_Connections_Per_Key >
          Options.Max_Total_Idle_Connections
      then
         return Http_Client.Errors.Invalid_Configuration;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Validate;

   function Transport_Attached_Reuse_Available return Boolean is
   begin
      return True;
   end Transport_Attached_Reuse_Available;

   function Header_Value_Has_Token
     (Value : String;
      Token : String) return Boolean
   is
      Lower_Value : constant String := Lower (Value);
      Lower_Token : constant String := Lower (Token);
      Start       : Natural := Value'First;
   begin
      while Start <= Value'Last loop
         while Start <= Value'Last
           and then (Value (Start) = ' ' or else Value (Start) = Character'Val (9)
                     or else Value (Start) = ',')
         loop
            Start := Start + 1;
         end loop;

         exit when Start > Value'Last;

         declare
            Stop : Natural := Start;
         begin
            while Stop <= Value'Last and then Value (Stop) /= ',' loop
               Stop := Stop + 1;
            end loop;

            declare
               Last : Natural := Stop - 1;
            begin
               while Last >= Start
                 and then (Value (Last) = ' ' or else Value (Last) = Character'Val (9))
               loop
                  Last := Last - 1;
               end loop;

               if Last >= Start
                 and then Lower_Value (Start .. Last) = Lower_Token
               then
                  return True;
               end if;
            end;

            Start := Stop + 1;
         end;
      end loop;

      return False;
   exception
      when Constraint_Error =>
         return False;
   end Header_Value_Has_Token;

   function Has_Header_Token
     (Headers : Http_Client.Headers.Header_List;
      Name    : String;
      Token   : String) return Boolean
   is
   begin
      for Index in 1 .. Http_Client.Headers.Length (Headers) loop
         if Lower (Http_Client.Headers.Name_At (Headers, Index)) = Lower (Name)
           and then Header_Value_Has_Token
             (Http_Client.Headers.Value_At (Headers, Index), Token)
         then
            return True;
         end if;
      end loop;

      return False;
   end Has_Header_Token;

   function No_Body_Status
     (Code : Http_Client.Types.Status_Code) return Boolean
   is
   begin
      return (Code >= 100 and then Code <= 199)
        or else Code = 204
        or else Code = 205
        or else Code = 304;
   end No_Body_Status;

   function Request_Permits_Persistent_Reuse
     (Request : Http_Client.Requests.Request) return Boolean
   is
      Request_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
   begin
      if not Http_Client.Requests.Is_Valid (Request) then
         return False;
      end if;

      return not Has_Header_Token (Request_Headers, "Connection", "close")
        and then not Has_Header_Token (Request_Headers, "Connection", "upgrade")
        and then not Http_Client.Headers.Contains (Request_Headers, "Upgrade");
   exception
      when others =>
         return False;
   end Request_Permits_Persistent_Reuse;

   function Response_Permits_Reuse
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response) return Boolean
   is
      Response_Headers : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      Code             : constant Http_Client.Types.Status_Code :=
        Http_Client.Responses.Status_Code (Response);
   begin
      if not Request_Permits_Persistent_Reuse (Request) then
         return False;
      end if;

      if Has_Header_Token (Response_Headers, "Connection", "close")
        or else Has_Header_Token (Response_Headers, "Connection", "upgrade")
        or else Http_Client.Headers.Contains (Response_Headers, "Upgrade")
      then
         return False;
      end if;

      if Http_Client.Responses.Version (Response) /=
        Http_Client.Responses.HTTP_1_1
      then
         return False;
      end if;

      if Code = 101 then
         --  101 switches the protocol on the connection. Even though it is in
         --  the 1xx range, the HTTP/1.1 connection is no longer available for
         --  ordinary request/response reuse.
         return False;
      end if;

      if Http_Client.Headers.Contains (Response_Headers, "Transfer-Encoding") then
         --  The buffered HTTP/1 reader reaches this point only after a final
         --  chunked transfer coding has been completely decoded and its
         --  terminating chunk/trailers have been consumed. Other transfer
         --  codings remain non-reusable.
         return Has_Header_Token (Response_Headers, "Transfer-Encoding", "chunked");
      end if;

      if Http_Client.Headers.Contains (Response_Headers, "Content-Length") then
         return True;
      end if;

      return Http_Client.Requests.Method (Request) = Http_Client.Types.HEAD
        or else No_Body_Status (Code);
   exception
      when others =>
         return False;
   end Response_Permits_Reuse;

   function Is_Valid (Token : Pool_Token) return Boolean is
   begin
      return Token.Valid and then Is_Valid (Token.Key);
   end Is_Valid;

   function Expired
     (Token   : Pool_Token;
      Options : Pooling_Options;
      Now     : Ada.Calendar.Time) return Boolean
   is
   begin
      if not Is_Valid (Token) then
         return True;
      end if;

      if Options.Max_Connection_Age_Seconds > 0
        and then Seconds_Elapsed (Token.Created_At, Now) >=
          Options.Max_Connection_Age_Seconds
      then
         return True;
      end if;

      if Options.Max_Idle_Time_Seconds > 0
        and then Seconds_Elapsed (Token.Last_Used_At, Now) >=
          Options.Max_Idle_Time_Seconds
      then
         return True;
      end if;

      return False;
   end Expired;

   procedure Prune_Expired (Item : in out Connection_Pool) is
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      I   : Positive;
   begin
      if Item.Entries.Is_Empty then
         return;
      end if;

      I := Item.Entries.First_Index;
      while I <= Item.Entries.Last_Index loop
         if Expired (Item.Entries (I), Item.Options, Now) then
            Item.Entries.Delete (I);
            if Item.Entries.Is_Empty then
               exit;
            end if;
         else
            I := I + 1;
         end if;
      end loop;
   end Prune_Expired;

   function Count_For
     (Item : Connection_Pool;
      Key  : Pool_Key) return Natural
   is
      Count : Natural := 0;
   begin
      if Item.Entries.Is_Empty or else not Is_Valid (Key) then
         return 0;
      end if;

      for E of Item.Entries loop
         if Same_Key (E.Key, Key) then
            Count := Count + 1;
         end if;
      end loop;

      return Count;
   end Count_For;

   procedure Enforce_Limits (Item : in out Connection_Pool; Key : Pool_Key) is
      I : Positive;
   begin
      while Natural (Item.Entries.Length) > Item.Options.Max_Total_Idle_Connections loop
         Item.Entries.Delete_First;
      end loop;

      if Item.Entries.Is_Empty or else not Is_Valid (Key) then
         return;
      end if;

      I := Item.Entries.First_Index;
      while I <= Item.Entries.Last_Index
        and then Count_For (Item, Key) > Item.Options.Max_Idle_Connections_Per_Key
      loop
         if Same_Key (Item.Entries (I).Key, Key) then
            Item.Entries.Delete (I);
            if Item.Entries.Is_Empty then
               exit;
            end if;
         else
            I := I + 1;
         end if;
      end loop;
   end Enforce_Limits;

   procedure Initialize
     (Item    : in out Connection_Pool;
      Options : Pooling_Options := Default_Pooling_Options)
   is
   begin
      Adjust_Idle_Counter (Natural (Item.Entries.Length), 0);
      Item.Entries.Clear;
      Item.Options := Options;
      Item.Closed := False;
   end Initialize;

   function Configure
     (Item    : in out Connection_Pool;
      Options : Pooling_Options) return Http_Client.Errors.Result_Status
   is
      Status : constant Http_Client.Errors.Result_Status := Validate (Options);
   begin
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Adjust_Idle_Counter (Natural (Item.Entries.Length), 0);
      Item.Entries.Clear;
      Item.Options := Options;
      Item.Closed := False;
      return Http_Client.Errors.Ok;
   end Configure;

   procedure Close_All (Item : in out Connection_Pool) is
   begin
      Adjust_Idle_Counter (Natural (Item.Entries.Length), 0);
      Item.Entries.Clear;
   end Close_All;

   procedure Shutdown (Item : in out Connection_Pool) is
   begin
      Adjust_Idle_Counter (Natural (Item.Entries.Length), 0);
      Item.Entries.Clear;
      Item.Closed := True;
   end Shutdown;

   function Is_Closed (Item : Connection_Pool) return Boolean is
   begin
      return Item.Closed;
   end Is_Closed;

   function Idle_Count (Item : Connection_Pool) return Natural is
   begin
      return Natural (Item.Entries.Length);
   end Idle_Count;

   function Idle_Count
     (Item : Connection_Pool;
      Key  : Pool_Key) return Natural
   is
   begin
      return Count_For (Item, Key);
   end Idle_Count;

   function Check_Out
     (Item   : in out Connection_Pool;
      Key    : Pool_Key;
      Token  : out Pool_Token;
      Reused : out Boolean) return Http_Client.Errors.Result_Status
   is
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      I   : Positive;
   begin
      Token := (others => <>);
      Reused := False;

      if Item.Closed then
         return Http_Client.Errors.Pool_Closed;
      elsif not Is_Valid (Key) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      if not Item.Options.Enabled then
         return Http_Client.Errors.Ok;
      end if;

      declare
         Before : constant Natural := Natural (Item.Entries.Length);
      begin
         Prune_Expired (Item);
         Adjust_Idle_Counter (Before, Natural (Item.Entries.Length));
      end;

      if Item.Entries.Is_Empty then
         return Http_Client.Errors.Ok;
      end if;

      I := Item.Entries.First_Index;
      while I <= Item.Entries.Last_Index loop
         if Same_Key (Item.Entries (I).Key, Key) then
            Token := Item.Entries (I);
            Token.Valid := True;
            Token.Last_Used_At := Now;
            Token.Request_Count := Token.Request_Count + 1;
            Item.Entries.Delete (I);
            Http_Client.Resources.Decrement
              (Http_Client.Resources.Pool_Idle_Entries);
            Reused := True;
            return Http_Client.Errors.Ok;
         end if;

         I := I + 1;
      end loop;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         Token := (others => <>);
         Reused := False;
         return Http_Client.Errors.Internal_Error;
   end Check_Out;

   function Begin_Fresh
     (Item  : in out Connection_Pool;
      Key   : Pool_Key;
      Token : out Pool_Token) return Http_Client.Errors.Result_Status
   is
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      Token := (others => <>);

      if Item.Closed then
         return Http_Client.Errors.Pool_Closed;
      elsif not Is_Valid (Key) then
         return Http_Client.Errors.Invalid_Request;
      elsif not Item.Options.Enabled then
         return Http_Client.Errors.Ok;
      end if;

      declare
         Before : constant Natural := Natural (Item.Entries.Length);
      begin
         Prune_Expired (Item);
         Adjust_Idle_Counter (Before, Natural (Item.Entries.Length));
      end;

      Token :=
        (Valid         => True,
         Key           => Key,
         Created_At    => Now,
         Last_Used_At  => Now,
         Request_Count => 1);

      return Http_Client.Errors.Ok;
   exception
      when others =>
         Token := (others => <>);
         return Http_Client.Errors.Internal_Error;
   end Begin_Fresh;

   function Check_In
     (Item     : in out Connection_Pool;
      Token    : Pool_Token;
      Reusable : Boolean := True) return Http_Client.Errors.Result_Status
   is
      Returned : Pool_Token := Token;
   begin
      if Item.Closed then
         return Http_Client.Errors.Pool_Closed;
      elsif not Is_Valid (Token) then
         return Http_Client.Errors.Connection_Not_Reusable;
      elsif not Item.Options.Enabled or else not Reusable then
         return Http_Client.Errors.Ok;
      end if;

      Returned.Last_Used_At := Ada.Calendar.Clock;

      if Expired (Returned, Item.Options, Returned.Last_Used_At) then
         return Http_Client.Errors.Ok;
      end if;

      if Item.Options.Max_Requests_Per_Connection = 0
        or else Returned.Request_Count >= Item.Options.Max_Requests_Per_Connection
      then
         return Http_Client.Errors.Ok;
      end if;

      declare
         Before : constant Natural := Natural (Item.Entries.Length);
      begin
         Item.Entries.Append (Returned);
         Enforce_Limits (Item, Returned.Key);
         Adjust_Idle_Counter (Before, Natural (Item.Entries.Length));
      end;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Check_In;

   function Register_Fresh_Idle
     (Item     : in out Connection_Pool;
      Key      : Pool_Key;
      Reusable : Boolean := True) return Http_Client.Errors.Result_Status
   is
      Token  : Pool_Token;
      Status : Http_Client.Errors.Result_Status;
   begin
      if not Reusable then
         if Item.Closed then
            return Http_Client.Errors.Pool_Closed;
         elsif not Is_Valid (Key) then
            return Http_Client.Errors.Invalid_Request;
         else
            return Http_Client.Errors.Ok;
         end if;
      end if;

      Status := Begin_Fresh (Item, Key, Token);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif not Is_Valid (Token) then
         return Http_Client.Errors.Ok;
      end if;

      return Check_In (Item, Token, Reusable => True);
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Register_Fresh_Idle;

   function Stream_Completion_Permits_Check_In
     (Reached_End_Of_Body       : Boolean;
      Closed_Early              : Boolean;
      Failed                    : Boolean;
      Connection_Close_Delimited : Boolean;
      Framing_Permits_Reuse     : Boolean) return Boolean
   is
   begin
      return Reached_End_Of_Body
        and then not Closed_Early
        and then not Failed
        and then not Connection_Close_Delimited
        and then Framing_Permits_Reuse;
   end Stream_Completion_Permits_Check_In;

end Http_Client.Connection_Pools;
