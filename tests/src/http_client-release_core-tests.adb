with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Auth.Bearer;
with Http_Client.Auth.Digest;
with Http_Client.Auth.Scopes;
with Http_Client.Alt_Svc;
with Http_Client.Async;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Clients;
with Http_Client.Connection_Pools;
with Http_Client.Cookies;
with Http_Client.Crypto;
with Http_Client.Decompression;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTPS_Records;
with Http_Client.HTTP1;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Body_Streams;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.HTTP2.Uploads;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Mapping;
with Http_Client.HTTP2.Settings;
with Http_Client.HTTP2.Single_Stream;
with Http_Client.HTTP2.Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Execution;
with Http_Client.HTTP3.Frames;
with Http_Client.HTTP3.Mapping;
with Http_Client.HTTP3.QPACK;
with Http_Client.HTTP3.Settings;
with Http_Client.HTTP3.Streams;
with Http_Client.QUIC;
with Http_Client.Multipart;
with Http_Client.HTTP1.Reader;
with Http_Client.Proxies;
with Http_Client.Protocol_Discovery;
with Http_Client.Proxies.SOCKS;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Resources;
with Http_Client.Retry;
with Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Transports.TLS;
with Http_Client.TLS.Client_Certificates;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Release_Core.Tests is

   use AUnit.Assertions;
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Errors.Result_Category;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;
   use type Http_Client.URI.TCP_Port;
   use type Http_Client.Transports.TCP.Timeout_Milliseconds;
   use type Http_Client.Responses.HTTP_Version;
   use type Http_Client.Cookies.SameSite_Policy;
   use type Http_Client.Cookies.Cookie_Jar_Access;
   use type Http_Client.Request_Bodies.Body_Kind;
   use type Http_Client.Cache.Cache_Source;
   use type Http_Client.Cache.Cache_Store_Access;
   use type Http_Client.Cache.Persistent.Persistent_Store_Access;
   use type Http_Client.Diagnostics.Event_Kind;
   use type Http_Client.Diagnostics.Cache_Result;
   use type Http_Client.Diagnostics.Diagnostic_ID;
   use type Http_Client.Diagnostics.Context_Access;
   use type Http_Client.Proxies.Proxy_Kind;
   use type Http_Client.Alt_Svc.Alternative_Protocol;
   use type Http_Client.Protocol_Discovery.Selection_Source;
   use type Http_Client.HTTPS_Records.ALPN_ID;
   use type Http_Client.HTTP2.HTTP2_Mode;
   use type Http_Client.HTTP2.Selected_Protocol;
   use type Http_Client.HTTP2.Frames.Frame_Type;
   use type Http_Client.HTTP2.Frames.Frame_Length;
   use type Http_Client.HTTP2.Frames.Stream_ID;
   use type Http_Client.HTTP2.Streams.Stream_State;
   use type Http_Client.HTTP3.HTTP3_Mode;
   use type Http_Client.HTTP3.Selected_Protocol;
   use type Http_Client.HTTP3.Frames.Frame_Type;
   use type Http_Client.HTTP3.Streams.Stream_Kind;
   use type Http_Client.QUIC.Backend_Availability;
   use type Ada.Calendar.Time;

   Diagnostic_Callback_Count : Natural := 0;
   Diagnostic_Fail_Next      : Boolean := False;

   procedure Capture_Diagnostic
     (Event  : Http_Client.Diagnostics.Diagnostic_Event;
      Status : out Http_Client.Errors.Result_Status) is
      pragma Unreferenced (Event);
   begin
      Diagnostic_Callback_Count := Diagnostic_Callback_Count + 1;

      if Diagnostic_Fail_Next then
         Diagnostic_Fail_Next := False;
         Status := Http_Client.Errors.Internal_Error;
      else
         Status := Http_Client.Errors.Ok;
      end if;
   end Capture_Diagnostic;

   function Diagnostic_Test_Time return Ada.Calendar.Time is
   begin
      return Ada.Calendar.Time_Of (2026, 5, 13, 12.0);
   end Diagnostic_Test_Time;

   procedure Assert_Parse_Ok
     (Text    : String;
      Item    : out Http_Client.URI.URI_Reference;
      Message : String);

   procedure Assert_Parse_Status
     (Text     : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String);

   procedure Assert_Header_Status
     (Actual : Http_Client.Errors.Result_Status; Message : String) is
   begin
      Assert (Actual = Http_Client.Errors.Ok, Message);
   end Assert_Header_Status;

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   procedure Assert_Serialize_Status
     (Request  : Http_Client.Requests.Request;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String;
      Output   : out Ada.Strings.Unbounded.Unbounded_String)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.HTTP1.Serialize_Request (Request, Output);
   begin
      Assert
        (Status = Expected,
         Message & " should return expected serialization status");
   end Assert_Serialize_Status;

   procedure Assert_Serialize_Ok
     (Request  : Http_Client.Requests.Request;
      Expected : String;
      Message  : String)
   is

      Output : Unbounded_String;
   begin
      Assert_Serialize_Status
        (Request  => Request,
         Expected => Http_Client.Errors.Ok,
         Message  => Message,
         Output   => Output);

      Assert
        (To_String (Output) = Expected,
         Message & " exact serialized output mismatch");
   end Assert_Serialize_Ok;

   procedure Assert_Parse_Ok
     (Text    : String;
      Item    : out Http_Client.URI.URI_Reference;
      Message : String)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.URI.Parse (Text, Item);
   begin
      Assert
        (Status = Http_Client.Errors.Ok,
         Message & " should parse successfully");

      Assert
        (Http_Client.URI.Is_Parsed (Item),
         Message & " should produce a parsed URI value");
   end Assert_Parse_Ok;

   procedure Assert_Parse_Status
     (Text     : String;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String)
   is
      Item   : Http_Client.URI.URI_Reference;
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.URI.Parse (Text, Item);
   begin
      Assert
        (Status = Expected,
         Message & " should return expected URI parse status");
   end Assert_Parse_Status;

   procedure Build_Cache_Request
     (URL           : String;
      Request       : out Http_Client.Requests.Request;
      Extra_Headers : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty)
   is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse (URL, URI);
      Assert (Status = Http_Client.Errors.Ok, "cache test URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method  => Http_Client.Types.GET,
           URI     => URI,
           Item    => Request,
           Headers => Extra_Headers);
      Assert
        (Status = Http_Client.Errors.Ok, "cache test request should build");
   end Build_Cache_Request;

   procedure Build_Cache_Response
     (Raw : String; Response : out Http_Client.Responses.Response)
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.Responses.Parse_Response (Raw, Response);
   begin
      Assert
        (Status = Http_Client.Errors.Ok,
         "cache test response should parse: "
         & Http_Client.Errors.Result_Status'Image (Status));
   end Build_Cache_Response;

   procedure Remove_Test_Directory (Path : String) is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Start_Search (Search, Path, "*");
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
               Ada.Directories.Delete_File (Ada.Directories.Full_Name (Ent));
            end if;
         end loop;
         Ada.Directories.End_Search (Search);
         Ada.Directories.Delete_Directory (Path);
      end if;
   exception
      when others =>
         null;
   end Remove_Test_Directory;

   function Count_Test_Files (Path : String; Pattern : String) return Natural
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Count  : Natural := 0;
   begin
      if not Ada.Directories.Exists (Path) then
         return 0;
      end if;

      Ada.Directories.Start_Search (Search, Path, Pattern);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
            Count := Count + 1;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return Count;
   exception
      when others =>
         return 0;
   end Count_Test_Files;

   function First_Test_File (Path : String; Pattern : String) return String is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return "";
      end if;

      Ada.Directories.Start_Search (Search, Path, Pattern);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File then
            declare
               Name : constant String := Ada.Directories.Simple_Name (Ent);
            begin
               Ada.Directories.End_Search (Search);
               return Name;
            end;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return "";
   exception
      when others =>
         return "";
   end First_Test_File;

   function Test_Raw_Key return String is
   begin
      return "0123456789abcdef0123456789abcdef";
   end Test_Raw_Key;

   function File_Contains_Text (Path : String; Marker : String) return Boolean
   is
      F    : Ada.Streams.Stream_IO.File_Type;
      Size : Ada.Streams.Stream_IO.Count;
   begin
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (F);
      if Size = 0 then
         Ada.Streams.Stream_IO.Close (F);
         return Marker'Length = 0;
      end if;
      declare
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         Text : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Streams.Stream_IO.Read (F, Data, Last);
         Ada.Streams.Stream_IO.Close (F);
         for I in Data'First .. Last loop
            Ada.Strings.Unbounded.Append
              (Text, Character'Val (Natural (Data (I))));
         end loop;
         return
           Ada.Strings.Fixed.Index
             (Ada.Strings.Unbounded.To_String (Text), Marker)
           /= 0;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         return False;
   end File_Contains_Text;

   function Any_Cache_File_Contains
     (Path : String; Marker : String) return Boolean
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return False;
      end if;
      Ada.Directories.Start_Search (Search, Path, "*");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         if Ada.Directories.Kind (Ent) = Ada.Directories.Ordinary_File
           and then
             File_Contains_Text (Ada.Directories.Full_Name (Ent), Marker)
         then
            Ada.Directories.End_Search (Search);
            return True;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return False;
   exception
      when others =>
         return False;
   end Any_Cache_File_Contains;

   function Phase38_Scripted_Resolver
     (Origin_Host : String) return Http_Client.DNS_SVCB.Resolver_Result
   is
      pragma Unreferenced (Origin_Host);
      R      : Http_Client.DNS_SVCB.SVCB_Record;
      Result : Http_Client.DNS_SVCB.Resolver_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example alpn=h3 port=9443 ttl=30", R);
      Result.Status := Status;
      if Status = Http_Client.Errors.Ok then
         Status := Http_Client.DNS_SVCB.Append (Result.Records, R);
         Result.Status := Status;
      end if;
      return Result;
   end Phase38_Scripted_Resolver;

   procedure Test_Root_Package

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
   begin
      Assert
        (Http_Client.Version'Length > 0,
         "root package should expose a non-empty version string");
   end Test_Root_Package;

   procedure Test_Release_Public_API_Stability_Surface

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client          : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Config          : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      TLS_Options     : constant Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      HTTP3_Options   : constant Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      QUIC_Options    : constant Http_Client.QUIC.QUIC_Options :=
        Http_Client.QUIC.Default_QUIC_Options;
      QUIC_Connection : Http_Client.QUIC.Connection;
      H2_Internal     : constant Http_Client.HTTP2_Execution_Common.Peer_Settings :=
        (Header_Table_Size    => 4_096,
         Initial_Window_Size  => 65_535,
         Max_Frame_Size       => 16_384,
         Max_Header_List_Size => 65_536);
   begin
      Assert
        (Http_Client.Version = "1.0.0",
         "The stabilized API should expose the stabilized 1.0 release version string");

      Assert
        (Http_Client.Clients.Is_Initialized (Client),
         "Create should return an initialized high-level client");

      Assert
        (Http_Client.Clients.Validate (Config) = Http_Client.Errors.Ok,
         "default high-level client configuration should validate");

      Assert
        (Http_Client.Transports.TLS.Validate_Options (TLS_Options)
         = Http_Client.Errors.Ok,
         "default TLS options should validate");

      Assert
        (Http_Client.HTTP3.Validate (HTTP3_Options) = Http_Client.Errors.Ok,
         "default experimental HTTP/3 options should validate without enabling execution");

      Assert
        (Http_Client.QUIC.Validate (QUIC_Options) = Http_Client.Errors.Ok,
         "default QUIC boundary options should validate as unavailable backend intent");

      Assert
        (H2_Internal.Max_Frame_Size = 16_384,
         "HTTP/2 execution common should remain compile-visible but classified as implementation boundary");

      Http_Client.QUIC.Close (QUIC_Connection);
      Assert
        (not Http_Client.QUIC.Is_Open (QUIC_Connection),
         "closing an unopened QUIC backend connection should be idempotent");

      Assert
        (Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled,
         "HTTP/3 should remain disabled in the high-level client by default");

      Assert
        (Config.Cache.Enabled = False
         and then Config.Cache_Store = null
         and then Config.Persistent_Cache_Store = null,
         "high-level cache stores should remain explicit and disabled by default");

      Assert
        (not TLS_Options.Disable_Certificate_Verification
         and then TLS_Options.Send_SNI,
         "TLS verification and SNI should remain secure by default");
   end Test_Release_Public_API_Stability_Surface;

   procedure Test_Release_Conservative_Default_Composition

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config    : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Exec      : constant Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Redirects : constant Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      Retries   : constant Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
      Pooling   : constant Http_Client.Connection_Pools.Pooling_Options :=
        Http_Client.Connection_Pools.Default_Pooling_Options;
      Cache     : constant Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Cache_Config;
   begin
      Assert
        (Exec.Cookie_Jar = null
         and then not Http_Client.Proxies.Is_Enabled (Exec.Proxy)
         and then Exec.Diagnostics = null,
         "execution defaults should be stateless, direct, and silent");

      Assert
        (Retries.Enable_Retries = False
         and then Retries.Maximum_Attempts = 1
         and then Retries.Allow_Non_Idempotent_Retry = False,
         "retry defaults should preserve single-attempt behavior");

      Assert
        (Pooling.Enabled = False
         and then Cache.Enabled = False
         and then Config.HTTP3.Mode = Http_Client.HTTP3.HTTP3_Disabled,
         "pooling, cache, and HTTP/3 should be disabled until configured");

      Assert
        (Http_Client.HTTP3.Execution_Status (Config.HTTP3)
         = Http_Client.Errors.HTTP3_Unsupported,
         "disabled HTTP/3 should report deterministic unsupported execution");

      Assert
        (Http_Client.HTTP3.Fallback_Status
           (Config.HTTP3, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "HTTP/3 fallback should be explicit and disabled by default");
   end Test_Release_Conservative_Default_Composition;

   procedure Test_Release_Status_Category_Model

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
   begin
      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.Ok)
         = Http_Client.Errors.Success_Category,
         "Ok should be the only success-category status");

      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.Invalid_URI)
         = Http_Client.Errors.Validation_Category
         and then
           Http_Client.Errors.Category (Http_Client.Errors.Invalid_Header)
           = Http_Client.Errors.Validation_Category,
         "ordinary invalid user input should stay in the validation category");

      Assert
        (Http_Client.Errors.Category
           (Http_Client.Errors.Certificate_Verification_Failed)
         = Http_Client.Errors.TLS_Category
         and then
           Http_Client.Errors.Category
             (Http_Client.Errors.SOCKS_Connect_Failed)
           = Http_Client.Errors.Proxy_Category,
         "TLS and proxy failures should remain distinguishable");

      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.HTTP2_Frame_Error)
         = Http_Client.Errors.HTTP2_Category
         and then
           Http_Client.Errors.Category (Http_Client.Errors.HTTP3_Unsupported)
           = Http_Client.Errors.HTTP3_Category,
         "HTTP/2 and HTTP/3 failures should remain separate categories");

      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.Async_Cancelled)
         = Http_Client.Errors.Async_Category
         and then
           Http_Client.Errors.Category (Http_Client.Errors.Internal_Error)
           = Http_Client.Errors.Internal_Category,
         "async and internal failures should have explicit categories");
   end Test_Release_Status_Category_Model;

   procedure Test_Release_Security_And_Experimental_Boundaries

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      TLS_Options   : Http_Client.Transports.TLS.TLS_Options :=
        Http_Client.Transports.TLS.Default_TLS_Options;
      HTTP3_Options : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      QUIC_Options  : Http_Client.QUIC.QUIC_Options :=
        Http_Client.QUIC.Default_QUIC_Options;
      Policy        : Http_Client.Diagnostics.Redaction_Policy :=
        Http_Client.Diagnostics.Default_Redaction_Policy;
      Status        : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Diagnostics.Safe_Header_Value
           (Policy, "Authorization", "Bearer secret")
         = "<redacted>"
         and then
           Http_Client.Diagnostics.Safe_Header_Value
             (Policy, "Proxy-Authorization", "Basic secret")
           = "<redacted>"
         and then
           Http_Client.Diagnostics.Safe_Header_Value
             (Policy, "Cookie", "sid=secret")
           = "<redacted>"
         and then
           Http_Client.Diagnostics.Safe_Header_Value
             (Policy, "Set-Cookie", "sid=secret")
           = "<redacted>",
         "default diagnostics redaction should cover origin, proxy, and cookie credentials");

      Status :=
        Http_Client.Headers.Add
          (Config.Default_Headers, "Authorization", "Bearer secret");
      Assert
        (Status = Http_Client.Errors.Ok,
         "test setup should be able to build a forbidden default header list");
      Assert
        (Http_Client.Clients.Validate (Config) /= Http_Client.Errors.Ok,
         "high-level configuration should reject credential-bearing default headers");

      TLS_Options.Disable_Certificate_Verification := True;
      Assert
        (Http_Client.Transports.TLS.Validate_Options (TLS_Options)
         = Http_Client.Errors.Ok,
         "unsafe verification disablement remains explicit and internally valid by itself");

      HTTP3_Options.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      HTTP3_Options.Fallback := Http_Client.HTTP3.Fallback_Before_Send;
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (HTTP3_Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.Ok,
         "experimental HTTP/3 fallback is allowed only by explicit before-send policy");
      Assert
        (Http_Client.HTTP3.Fallback_Status
           (HTTP3_Options, Request_Bytes_Already_Sent => True)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "experimental HTTP/3 fallback must not occur after request bytes are sent");

      QUIC_Options.Enable_Zero_RTT := True;
      Assert
        (Http_Client.QUIC.Validate (QUIC_Options) /= Http_Client.Errors.Ok,
         "QUIC 0-RTT should remain rejected while no production backend exists");

      HTTP3_Options.Enable_Server_Push := True;
      Assert
        (Http_Client.HTTP3.Validate (HTTP3_Options) /= Http_Client.Errors.Ok,
         "HTTP/3 server push should remain outside the experimental 1.0 boundary");
   end Test_Release_Security_And_Experimental_Boundaries;

   procedure Test_Release_Configuration_Composition_Failures

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Store  : aliased Http_Client.Cache.Cache_Store;
      Status : Http_Client.Errors.Result_Status;
   begin
      Config.Cache := Http_Client.Cache.Default_Enabled_Cache_Config;
      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "enabled cache should require exactly one explicit cache store");

      Http_Client.Cache.Initialize
        (Store, Http_Client.Cache.Default_Enabled_Cache_Config);
      Config.Cache_Store := Store'Unchecked_Access;
      Assert
        (Http_Client.Clients.Validate (Config) = Http_Client.Errors.Ok,
         "enabled in-memory cache should validate only when a caller-owned store is supplied");

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "Proxy-Connection", "keep-alive");
      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "non-standard proxy connection headers should be rejected as broad defaults");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Redirects.Follow_Redirects := True;
      Config.Redirects.Max_Redirects := 0;
      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "redirect following should require an explicit nonzero hop bound");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Enable_Decompression := True;
      Config.Decompression.Maximum_Decoded_Body_Size := 0;
      Assert
        (Http_Client.Clients.Validate (Config)
         = Http_Client.Errors.Invalid_Configuration,
         "decoded-body limits should remain bounded when decompression is enabled");
   end Test_Release_Configuration_Composition_Failures;

   procedure Test_Release_Status_Category_Total_Coverage

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
   begin
      for Status in Http_Client.Errors.Result_Status loop
         declare
            Category : constant Http_Client.Errors.Result_Category :=
              Http_Client.Errors.Category (Status);
         begin
            if Status = Http_Client.Errors.Ok then
               Assert
                 (Category = Http_Client.Errors.Success_Category,
                  "Ok should stay in the success category");
            else
               Assert
                 (Category /= Http_Client.Errors.Success_Category,
                  "non-Ok statuses must not be classified as success");
            end if;
         end;
      end loop;
   end Test_Release_Status_Category_Total_Coverage;

   procedure Test_Result_Status

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      use Http_Client.Errors;
   begin
      Assert (Ok = Ok, "Ok result status should compare equal to itself");

      Assert (Is_Success (Ok), "Ok should be recognized as success");

      Assert
        (not Is_Success (Invalid_URI),
         "Invalid_URI should not be recognized as success");
   end Test_Result_Status;

   procedure Test_Method_And_Status_Code_Types

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      use Http_Client.Types;

      Method : Method_Name := GET;
      Code   : Status_Code := 200;
   begin
      Assert (Method = GET, "GET method literal should be visible");

      Method := DELETE;

      Assert (Method = DELETE, "DELETE method literal should be usable");

      Assert (Code = 200, "HTTP status code subtype should accept 200");

      Code := 599;

      Assert
        (Code = 599, "HTTP status code subtype should accept upper bound 599");
   end Test_Method_And_Status_Code_Types;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Release_Core");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, Test_Root_Package'Access, "Test_Root_Package");
      Register_Routine
        (T,
         Test_Release_Public_API_Stability_Surface'Access,
         "Test_Release_Public_API_Stability_Surface");
      Register_Routine
        (T,
         Test_Release_Conservative_Default_Composition'Access,
         "Test_Release_Conservative_Default_Composition");
      Register_Routine
        (T,
         Test_Release_Status_Category_Model'Access,
         "Test_Release_Status_Category_Model");
      Register_Routine
        (T,
         Test_Release_Security_And_Experimental_Boundaries'Access,
         "Test_Release_Security_And_Experimental_Boundaries");
      Register_Routine
        (T,
         Test_Release_Configuration_Composition_Failures'Access,
         "Test_Release_Configuration_Composition_Failures");
      Register_Routine
        (T,
         Test_Release_Status_Category_Total_Coverage'Access,
         "Test_Release_Status_Category_Total_Coverage");
      Register_Routine
        (T, Test_Result_Status'Access, "Test_Result_Status");
      Register_Routine
        (T,
         Test_Method_And_Status_Code_Types'Access,
         "Test_Method_And_Status_Code_Types");
   end Register_Tests;

end Http_Client.Release_Core.Tests;
