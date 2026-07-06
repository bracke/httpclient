with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Cancellation;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Proxies;
with Http_Client.Requests;
with Http_Client.Resources;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Clients.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Cookies.Cookie_Jar_Access;
   use type Http_Client.Cancellation.Cancellation_Token_Access;
   use type Http_Client.Cache.Persistent.Persistent_Store_Access;
   use type Http_Client.Clients.Download_File_Mode;
   use type Http_Client.Clients.Resume_Fallback_Action;
   use type Http_Client.URI.TCP_Port;
   use type Ada.Calendar.Time;

   Diagnostic_Callback_Count : Natural := 0;
   Diagnostic_Fail_Next      : Boolean := False;
   Download_Progress_Count   : Natural := 0;
   Download_Progress_Bytes   : Natural := 0;
   Download_Progress_Total   : Natural := 0;
   Download_Progress_Status  : Http_Client.Errors.Result_Status :=
     Http_Client.Errors.Ok;

   function Capture_Download_Progress
     (Bytes_Written : Natural;
      Total_Bytes   : Natural) return Http_Client.Errors.Result_Status
   is
   begin
      Download_Progress_Count := Download_Progress_Count + 1;
      Download_Progress_Bytes := Bytes_Written;
      Download_Progress_Total := Total_Bytes;
      return Download_Progress_Status;
   end Capture_Download_Progress;

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

   procedure Test_High_Level_Client_Configuration_Defaults

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is
      pragma Unreferenced (Case_Context);
      Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Configuration (Client);
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Clients.Validate (Config) = Http_Client.Errors.Ok,
         "default high-level client configuration should validate");

      Assert
        (not Config.Retries.Enable_Retries,
         "high-level retries should be disabled by default");

      Assert
        (not Http_Client.Proxies.Is_Enabled (Config.Execution.Proxy),
         "high-level proxy use should be disabled by default");

      Assert
        (Config.Execution.Cookie_Jar = null,
         "high-level cookie storage should be disabled by default");

      Assert
        (Config.Persistent_Cache_Store = null,
         "high-level persistent cache storage should be disabled by default");

      Assert
        (not Config.Execution.TLS.Disable_Certificate_Verification,
         "high-level TLS verification should be enabled by default");

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Ok,
         "initializing a client with default configuration should succeed");
   end Test_High_Level_Client_Configuration_Defaults;

   procedure Test_High_Level_Client_Invalid_Configuration

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status : Http_Client.Errors.Result_Status;
   begin
      Config.Execution.Max_Response_Size := 0;

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "zero maximum response size should be rejected");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Redirects.Follow_Redirects := True;
      Config.Redirects.Max_Redirects := 0;

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "enabled redirect following with zero redirect limit should be rejected");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Enable_Decompression := True;
      Config.Decompression.Maximum_Decoded_Body_Size := 0;

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "enabled decompression with zero decoded-body limit should be rejected");

      Config := Http_Client.Clients.Default_Client_Configuration;
      Config.Cache := Http_Client.Cache.Default_Enabled_Cache_Config;

      Status := Http_Client.Clients.Validate (Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "enabled high-level cache should require an explicit cache backend");

      declare
         Memory_Store     : aliased Http_Client.Cache.Cache_Store;
         Persistent_Store :
           aliased Http_Client.Cache.Persistent.Persistent_Store;
      begin
         Config := Http_Client.Clients.Default_Client_Configuration;
         Config.Cache := Http_Client.Cache.Default_Enabled_Cache_Config;
         Config.Cache_Store := Memory_Store'Unchecked_Access;
         Config.Persistent_Cache_Store := Persistent_Store'Unchecked_Access;

         Status := Http_Client.Clients.Validate (Config);

         Assert
           (Status = Http_Client.Errors.Invalid_Configuration,
            "high-level client should reject simultaneous memory and persistent cache stores");
      end;

      declare
         Persistent_Store :
           aliased Http_Client.Cache.Persistent.Persistent_Store;
      begin
         Config := Http_Client.Clients.Default_Client_Configuration;
         Config.Cache := Http_Client.Cache.Default_Enabled_Cache_Config;
         Config.Persistent_Cache_Store := Persistent_Store'Unchecked_Access;

         Status := Http_Client.Clients.Validate (Config);

         Assert
           (Status = Http_Client.Errors.Cache_Open_Failed,
            "high-level persistent cache store should be explicitly opened before configuration use");
      end;
   end Test_High_Level_Client_Invalid_Configuration;

   procedure Test_High_Level_Client_Failed_Configure_Preserves_Client

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client     : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Bad_Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Request    : constant Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Result     : Http_Client.Clients.Client_Result;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Bad_Config.Execution.Max_Response_Size := 0;

      Status := Http_Client.Clients.Configure (Client, Bad_Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "invalid reconfiguration should be rejected deterministically");

      Status := Http_Client.Clients.Execute (Client, Request, Result);

      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "failed Configure must preserve the previous initialized client state");

      Assert
        (Result.Status = Http_Client.Errors.Invalid_Request,
         "result status should confirm failed Configure did not make client uninitialized");
   end Test_High_Level_Client_Failed_Configure_Preserves_Client;

   procedure Test_High_Level_Client_Initialization_State_Introspection

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Bad_Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Good_Config : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Clients.Is_Initialized (Client),
         "created high-level client should report initialized state");

      Bad_Config.Execution.Max_Response_Size := 0;

      Status := Http_Client.Clients.Initialize (Client, Bad_Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "invalid Initialize should be rejected for state introspection test");

      Assert
        (not Http_Client.Clients.Is_Initialized (Client),
         "failed Initialize should mark high-level client uninitialized");

      Status := Http_Client.Clients.Configure (Client, Bad_Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "failed Configure on an uninitialized client should still reject invalid settings");

      Assert
        (not Http_Client.Clients.Is_Initialized (Client),
         "failed Configure on an uninitialized client should preserve uninitialized state");

      Status := Http_Client.Clients.Configure (Client, Good_Config);

      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Configure should make an uninitialized high-level client usable again");

      Assert
        (Http_Client.Clients.Is_Initialized (Client),
         "valid Configure should report initialized state");
   end Test_High_Level_Client_Initialization_State_Introspection;

   procedure Test_High_Level_Client_Default_Object_Is_Uninitialized

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client  : Http_Client.Clients.Client;
      Request : constant Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Result  : Http_Client.Clients.Client_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert
        (not Http_Client.Clients.Is_Initialized (Client),
         "default-initialized high-level client should not report initialized state");

      Status := Http_Client.Clients.Execute (Client, Request, Result);

      Assert
        (Status = Http_Client.Errors.Client_Not_Initialized,
         "default-initialized high-level client should reject Execute before request validation or network I/O");

      Assert
        (Result.Status = Http_Client.Errors.Client_Not_Initialized
         and then Result.Redirect_Count = 0
         and then Result.Retry_Attempt_Count = 0
         and then not Result.Retry_Exhausted
         and then not Result.Used_Decoded_View
         and then Http_Client.URI.Image (Result.Final_URI) = "",
         "default-initialized high-level client should return neutral Client_Result metadata");
   end Test_High_Level_Client_Default_Object_Is_Uninitialized;

   procedure Test_High_Level_Client_Default_Object_Can_Be_Configured

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client : Http_Client.Clients.Client;
      Config : constant Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert
        (not Http_Client.Clients.Is_Initialized (Client),
         "default high-level client object should start uninitialized before Configure");

      Status := Http_Client.Clients.Configure (Client, Config);

      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Configure should initialize a default high-level client object");

      Assert
        (Http_Client.Clients.Is_Initialized (Client),
         "default high-level client object should report initialized after valid Configure");
   end Test_High_Level_Client_Default_Object_Can_Be_Configured;

   procedure Test_High_Level_Client_Failed_Configure_Preserves_Configuration

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Good_Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Bad_Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Seen_Config : Http_Client.Clients.Client_Configuration;
      Status      : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Clients.Set_Default_Header
          (Good_Config, "X-Stable", "kept");

      Assert
        (Status = Http_Client.Errors.Ok,
         "stable default header should be configurable before preserve test");

      Status := Http_Client.Clients.Initialize (Client, Good_Config);

      Assert
        (Status = Http_Client.Errors.Ok,
         "client should initialize with stable configuration");

      Bad_Config.Execution.Max_Response_Size := 0;
      Status := Http_Client.Clients.Configure (Client, Bad_Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "invalid Configure should be rejected before configuration preservation check");

      Seen_Config := Http_Client.Clients.Configuration (Client);

      Assert
        (Http_Client.Headers.Contains
           (Seen_Config.Default_Headers, "X-Stable"),
         "failed Configure should preserve previously installed default headers");

      Assert
        (Seen_Config.Execution.Max_Response_Size
         = Good_Config.Execution.Max_Response_Size,
         "failed Configure should preserve previous execution limits");
   end Test_High_Level_Client_Failed_Configure_Preserves_Configuration;

   procedure Test_High_Level_Client_Convenience_Invalid_URL

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Result : Http_Client.Clients.Client_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Clients.Get (Client, "not-a-url", Result);

      Assert
        (Status = Http_Client.Errors.Invalid_URI,
         "high-level GET should reject invalid URL text before network I/O");

      Assert
        (Result.Status = Http_Client.Errors.Invalid_URI,
         "high-level GET result should expose invalid URL status");

      Status := Http_Client.Clients.Head (Client, "not-a-url", Result);

      Assert
        (Status = Http_Client.Errors.Invalid_URI,
         "high-level HEAD should reject invalid URL text before network I/O");

      Assert
        (Result.Status = Http_Client.Errors.Invalid_URI,
         "high-level HEAD result should expose invalid URL status");
   end Test_High_Level_Client_Convenience_Invalid_URL;

   procedure Test_High_Level_Client_Uninitialized_Execute

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      URI     : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Result  : Http_Client.Clients.Client_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Config.Execution.Max_Response_Size := 0;

      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "invalid initialization should fail deterministically");

      Assert_Parse_Ok
        ("http://127.0.0.1:1/no-network",
         URI,
         "valid URI for uninitialized client test");

      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET, URI => URI, Item => Request)
         = Http_Client.Errors.Ok,
         "valid request should construct for uninitialized client test");

      Status := Http_Client.Clients.Execute (Client, Request, Result);

      Assert
        (Status = Http_Client.Errors.Client_Not_Initialized,
         "client left uninitialized by invalid configuration should reject Execute before network I/O");

      Assert
        (Result.Status = Http_Client.Errors.Client_Not_Initialized,
         "high-level result should expose Client_Not_Initialized");
   end Test_High_Level_Client_Uninitialized_Execute;

   procedure Test_High_Level_Client_Uninitialized_Convenience_Methods

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
   begin
      Config.Execution.Max_Response_Size := 0;

      Assert
        (Http_Client.Clients.Initialize (Client, Config)
         = Http_Client.Errors.Invalid_Configuration,
         "invalid initialization should make convenience-method state test meaningful");

      declare
         Result : Http_Client.Clients.Client_Result;
      begin
         Assert
           (Http_Client.Clients.Get (Client, "not-a-url", Result)
            = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level GET should fail before URL parsing");

         Assert
           (Result.Status = Http_Client.Errors.Client_Not_Initialized
            and then Result.Redirect_Count = 0
            and then Result.Retry_Attempt_Count = 0
            and then not Result.Retry_Exhausted
            and then not Result.Used_Decoded_View
            and then Http_Client.URI.Image (Result.Final_URI) = "",
            "uninitialized high-level GET should return neutral result metadata");
      end;

      declare
         Result : Http_Client.Clients.Client_Result;
      begin
         Assert
           (Http_Client.Clients.Head
              (Client, "http://127.0.0.1:1/no-network", Result)
            = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level HEAD should fail before URL parsing");
         Assert
           (Result.Status = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level HEAD should report neutral failure metadata");
      end;

      declare
         Result : Http_Client.Clients.Client_Result;
      begin
         Assert
           (Http_Client.Clients.Post
              (Client,
               "http://127.0.0.1:1/no-network",
               "payload",
               Result,
               "text/plain")
            = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level POST should fail before request construction or network I/O");
         Assert
           (Result.Status = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level POST should report neutral failure metadata");
      end;

      declare
         Result : Http_Client.Clients.Client_Result;
      begin
         Assert
           (Http_Client.Clients.Put
              (Client,
               "http://127.0.0.1:1/no-network",
               "payload",
               Result,
               "text/plain")
            = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level PUT should fail before request construction or network I/O");
         Assert
           (Result.Status = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level PUT should report neutral failure metadata");
      end;

      declare
         Result : Http_Client.Clients.Client_Result;
      begin
         Assert
           (Http_Client.Clients.Delete
              (Client, "http://127.0.0.1:1/no-network", Result)
            = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level DELETE should fail before request construction or network I/O");
         Assert
           (Result.Status = Http_Client.Errors.Client_Not_Initialized,
            "uninitialized high-level DELETE should report neutral failure metadata");
      end;
   end Test_High_Level_Client_Uninitialized_Convenience_Methods;

   procedure Test_High_Level_Client_Head_Convenience

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Type: image/jpeg"
        & CRLF
        & "Content-Length: 12345"
        & CRLF
        & "X-Head-Test: yes"
        & CRLF
        & CRLF
        & "body-that-must-not-be-read";

      task type Head_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Head_Server;

      task body Head_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Request     : Unbounded_String;
         Raw         : Stream_Element_Array (1 .. 4096);
         Last        : Stream_Element_Offset;
         Outgoing    :
           Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
         Sent_Last   : Stream_Element_Offset;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
         if Last >= Raw'First then
            for Index in Raw'First .. Last loop
               Append (Request, Character'Val (Raw (Index)));
            end loop;
         end if;

         for Index in Outgoing'Range loop
            Outgoing (Index) :=
              Stream_Element
                (Character'Pos
                   (Response (Response'First + Natural (Index - Outgoing'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request;
         end Request_Seen;
      end Head_Server;

      Server       : Head_Server;
      Port         : Http_Client.URI.TCP_Port;
      Port_Text    : Unbounded_String;
      Result       : Http_Client.Clients.Client_Result;
      Status       : Http_Client.Errors.Result_Status;
      Request_Text : Unbounded_String;
      URL          : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));
      URL :=
        To_Unbounded_String
          ("http://127.0.0.1:" & To_String (Port_Text) & "/asset.jpg");

      Status :=
        Http_Client.Clients.Head
          (URL           => To_String (URL),
           Result        => Result,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Ok,
         "temporary-client HEAD convenience should complete successfully");

      Assert
        (Http_Client.Responses.Status_Code (Result.Response) = 200,
         "HEAD convenience should return response status metadata");

      Assert
        (Http_Client.Headers.Get
           (Http_Client.Responses.Headers (Result.Response), "X-Head-Test")
         = "yes",
         "HEAD convenience should preserve response headers");

      Assert
        (Http_Client.Clients.Response_Text (Result) = "",
         "HEAD convenience should not expose a response body");

      Server.Request_Seen (Request_Text);

      Assert
        (Index (Request_Text, "HEAD /asset.jpg HTTP/1.1") = 1,
         "HEAD convenience should serialize a HEAD request");
   end Test_High_Level_Client_Head_Convenience;

   procedure Test_Client_Follows_Relative_302_And_Rewrites_Post

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF            : constant String :=
        Character'Val (13) & Character'Val (10);
      First_Response  : constant String :=
        "HTTP/1.1 302 Found"
        & CRLF
        & "Location: ../final?ok=1"
        & CRLF
        & "Content-Length: 0"
        & CRLF
        & CRLF;
      Second_Response : constant String :=
        "HTTP/1.1 200 OK" & CRLF & "Content-Length: 4" & CRLF & CRLF & "Done";

      task type Redirect_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String);
      end Redirect_Server;

      task body Redirect_Server is
         Server         : GNAT.Sockets.Socket_Type;
         Peer           : GNAT.Sockets.Socket_Type;
         Server_Addr    : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr      : GNAT.Sockets.Sock_Addr_Type;
         First_Request  : Unbounded_String;
         Second_Request : Unbounded_String;

         procedure Receive_Request (Text : in out Unbounded_String) is
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end Receive_Request;

         procedure Send_Response (Text : String) is
            Raw  :
              Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
            Last : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Text (Text'First + Natural (Index - Raw'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end Send_Response;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (First_Request);
         Send_Response (First_Response);
         GNAT.Sockets.Close_Socket (Peer);

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         Receive_Request (Second_Request);
         Send_Response (Second_Response);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Requests_Seen
           (First : out Unbounded_String; Second : out Unbounded_String)
         do
            First := First_Request;
            Second := Second_Request;
         end Requests_Seen;
      end Redirect_Server;

      Server      : Redirect_Server;
      Port        : Http_Client.URI.TCP_Port;
      URI         : Http_Client.URI.URI_Reference;
      Request     : Http_Client.Requests.Request;
      Headers     : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Result      : Http_Client.Clients.Redirect_Result;
      Redirects   : Http_Client.Clients.Redirect_Options :=
        Http_Client.Clients.Default_Redirect_Options;
      First_Text  : Unbounded_String;
      Second_Text : Unbounded_String;
      Client      : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
      Port_Text   : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Assert_Parse_Ok
        ("http://127.0.0.1:" & To_String (Port_Text) & "/dir/start",
         URI,
         "relative redirect start URI");

      Assert_Header_Status
        (Http_Client.Headers.Set (Headers, "Authorization", "Bearer secret"),
         "authorization header should be accepted for same-origin redirect");

      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.POST,
            URI     => URI,
            Item    => Request,
            Headers => Headers,
            Payload => "payload")
         = Http_Client.Errors.Ok,
         "redirect POST request should construct");

      Redirects.Follow_Redirects := True;

      Assert
        (Http_Client.Clients.Execute_With_Redirects
           (Item      => Client,
            Request   => Request,
            Result    => Result,
            Redirects => Redirects)
         = Http_Client.Errors.Ok,
         "redirect-aware execution should follow one relative 302");

      Assert
        (Result.Redirect_Count = 1,
         "redirect result should report one followed hop");

      Assert
        (Http_Client.Responses.Status_Code (Result.Final_Response) = 200,
         "redirect-aware execution should return the final 200 response");

      Assert
        (Http_Client.Responses.Response_Body (Result.Final_Response) = "Done",
         "redirect-aware execution should return the final response body");

      Server.Requests_Seen (First_Text, Second_Text);

      Assert
        (Index (First_Text, "POST /dir/start HTTP/1.1") = 1,
         "first redirect hop should send the original POST");

      Assert
        (Index (Second_Text, "GET /final?ok=1 HTTP/1.1") = 1,
         "302 POST redirect should be rewritten to GET with relative dot-segment Location resolved");

      Assert
        (Index (Second_Text, "Content-Length:") = 0,
         "rewritten GET redirect should not reuse stale Content-Length");

      Assert
        (Index (Second_Text, "Authorization: Bearer secret") > 0,
         "same-origin redirect should preserve ordinary caller headers including authorization");
   end Test_Client_Follows_Relative_302_And_Rewrites_Post;

   procedure Test_Download_To_File_Defaults_And_Uninitialized_Guard
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Config  : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Options : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result  : Http_Client.Clients.Download_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Options.Max_Download_Size
         = Http_Client.Clients.Default_Max_Download_Size
         and then Options.Max_Download_Size
                  > Config.Execution.Max_Body_Size
         and then Options.File_Mode = Http_Client.Clients.Replace_Atomically
         and then Options.Durability = Http_Client.Clients.File_Durability_Default
         and then Options.Cancellation = null
         and then Options.Buffer_Size = 64 * 1024,
         "download-to-file default limit should be high and separate");

      Assert
        (Http_Client.Clients.Resume_Validator
           (ETag          => """strong""",
            Last_Modified => "Wed, 21 Oct 2015 07:28:00 GMT",
            ETag_Is_Weak  => False) = To_Unbounded_String ("""strong"""),
         "resume validator should prefer strong ETag");
      Assert
        (Http_Client.Clients.Resume_Validator
           (ETag          => "W/""weak""",
            Last_Modified => "Wed, 21 Oct 2015 07:28:00 GMT",
            ETag_Is_Weak  => True)
         = To_Unbounded_String ("Wed, 21 Oct 2015 07:28:00 GMT"),
         "resume validator should fall back to Last-Modified for weak ETag");
      Assert
        (Length
           (Http_Client.Clients.Resume_Validator
              (ETag => """strong""", Last_Modified => "", ETag_Is_Weak => False, Resume_Safe => False)) = 0,
         "resume validator should reject unsafe partials");

      Http_Client.Clients.Configure_Resumable_Download
        (Options             => Options,
         Resume_Mode         => True,
         Can_Resume          => True,
         Resume_If_Range     => To_Unbounded_String ("""strong"""),
         Partial_Size        => 4,
         Remaining_Max_Bytes => 10);
      Assert
        (Options.File_Mode = Http_Client.Clients.Overwrite
         and then Options.Preserve_Partial_File
         and then Options.Enable_Resume
         and then Options.Resume_If_Range = To_Unbounded_String ("""strong""")
         and then Options.Max_Download_Size = 14,
         "resumable download helper should configure overwrite resume with final-size cap");

      Result.HTTP_Status_Code := 416;
      Assert
        (Http_Client.Clients.Resume_Fallback_For
           (Http_Client.Errors.Incomplete_Message, Result, Resume_Mode => True)
         = Http_Client.Clients.Retry_Without_Resume,
         "416 resume failure should request full retry");
      Http_Client.Clients.Configure_Full_Retry_After_Resume_Failure
        (Options, Remaining_Max_Bytes => 10);
      Assert
        (not Options.Enable_Resume
         and then Length (Options.Resume_If_Range) = 0
         and then Options.Max_Download_Size = 10,
         "full retry helper should disable resume and restore new-transfer cap");

      Config.Execution.Max_Response_Size := 0;
      Status := Http_Client.Clients.Initialize (Client, Config);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "invalid initialization should make download guard test meaningful");

      Status :=
        Http_Client.Clients.Download_To_File
          (Item   => Client,
           URL    => "not-a-url",
           Path   => "download_guard_should_not_exist.tmp",
           Result => Result);

      Assert
        (Status = Http_Client.Errors.Client_Not_Initialized,
         "download-to-file should fail before URL parsing when uninitialized");

      Assert
        (Result.Status = Http_Client.Errors.Client_Not_Initialized
         and then Result.HTTP_Status_Code = 0
         and then Result.Expected_Final_Size = 0
         and then Result.Redirect_Count = 0
         and then Result.Retry_Attempt_Count = 0
         and then not Result.Resumed
         and then Result.Resume_Offset = 0
         and then Result.Bytes_Written = 0
         and then Http_Client.URI.Image (Result.Final_URI) = "",
         "uninitialized download-to-file should return neutral result metadata");
   end Test_Download_To_File_Defaults_And_Uninitialized_Guard;

   procedure Test_Atomic_File_Write_Primitives
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Path        : constant String := "atomic_write_helper_test.tmp";
      Source_Path : constant String := "atomic_write_helper_source.tmp";
      Dir_Path    : constant String := "atomic_write_helper_dir";
      Status      : Http_Client.Errors.Result_Status;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      if Ada.Directories.Exists (Source_Path) then
         Ada.Directories.Delete_File (Source_Path);
      end if;
      if Ada.Directories.Exists (Dir_Path) then
         Ada.Directories.Delete_Directory (Dir_Path);
      end if;

      Status := Http_Client.Clients.Write_Text_File_Atomically
        (Path          => Path,
         Content       => "first",
         Temp_Suffix   => ".tmp",
         Backup_Suffix => ".old",
         Durability    => Http_Client.Clients.File_Durability_Sync_Data_And_Directory);
      Assert (Status = Http_Client.Errors.Ok, "durable atomic text write should create target");
      Assert (File_Contains_Text (Path, "first"), "atomic text write should write content");
      Assert
        (not Ada.Directories.Exists (Path & ".tmp"),
         "atomic text write should remove temp path after install");

      Status := Http_Client.Clients.Write_Text_File_Atomically
        (Path          => Path,
         Content       => "second",
         Temp_Suffix   => ".tmp",
         Backup_Suffix => ".old",
         Durability    => Http_Client.Clients.File_Durability_Default);
      Assert (Status = Http_Client.Errors.Ok, "atomic text write should replace existing target");
      Assert (File_Contains_Text (Path, "second"), "atomic text write should replace content");
      Assert
        (not File_Contains_Text (Path, "first"),
         "atomic text write should not leave old content in target");
      Assert
        (not Ada.Directories.Exists (Path & ".old"),
         "atomic text write should remove backup path after install");

      Status := Http_Client.Clients.Write_Text_File_Atomically
        (Path          => Source_Path,
         Content       => "source",
         Temp_Suffix   => ".tmp",
         Backup_Suffix => ".old",
         Durability    => Http_Client.Clients.File_Durability_Default);
      Assert (Status = Http_Client.Errors.Ok, "test source setup should succeed");
      Ada.Directories.Create_Directory (Dir_Path);
      Status := Http_Client.Clients.Install_File_Atomically
        (Source_Path        => Source_Path,
         Target_Path        => Dir_Path,
         Backup_Suffix      => ".old",
         Create_Parent_Dirs => False,
         Durability         => Http_Client.Clients.File_Durability_Sync_Data_And_Directory);
      Assert
        (Status = Http_Client.Errors.Write_Failed,
         "atomic install should reject directory targets");
      Assert
        (Ada.Directories.Exists (Source_Path),
         "failed atomic install should leave source file for caller cleanup");

      Ada.Directories.Delete_File (Source_Path);
      Ada.Directories.Delete_Directory (Dir_Path);
      Ada.Directories.Delete_File (Path);
   exception
      when others =>
         if Ada.Directories.Exists (Source_Path) then
            begin
               Ada.Directories.Delete_File (Source_Path);
            exception
               when others =>
                  null;
            end;
         end if;
         if Ada.Directories.Exists (Path) then
            begin
               Ada.Directories.Delete_File (Path);
            exception
               when others =>
                  null;
            end;
         end if;
         if Ada.Directories.Exists (Dir_Path) then
            begin
               Ada.Directories.Delete_Directory (Dir_Path);
            exception
               when others =>
                  null;
            end;
         end if;
         raise;
   end Test_Atomic_File_Write_Primitives;

   procedure Test_Download_To_File_Pre_Cancelled_Token
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Path    : constant String := "cancelled_download_test.tmp";
      Token   : aliased Http_Client.Cancellation.Cancellation_Token;
      Options : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result  : Http_Client.Clients.Download_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;

      Http_Client.Cancellation.Cancel (Token);
      Options.Cancellation := Token'Unchecked_Access;

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "pre-cancelled download token should stop before network execution");
      Assert
        (Result.Status = Http_Client.Errors.Cancelled
         and then Result.HTTP_Status_Code = 0
         and then Result.Expected_Final_Size = 0
         and then Result.Redirect_Count = 0
         and then Result.Retry_Attempt_Count = 0
         and then not Result.Resumed
         and then Result.Resume_Offset = 0
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "pre-cancelled download should return neutral result metadata");
      Assert
        (not Ada.Directories.Exists (Path),
         "pre-cancelled download should not create target file");
   end Test_Download_To_File_Pre_Cancelled_Token;

   procedure Test_Download_To_File_Target_Preflight_Before_Network
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Existing_Path : constant String := "download_create_new_existing.tmp";
      Parent        : constant String := "download_preflight_policy_parent";
      Policy_Path   : constant String := Parent & "/file.bin";
      Options       : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result        : Http_Client.Clients.Download_Result;
      Status        : Http_Client.Errors.Result_Status;

      procedure Write_Text (Name : String; Text : String) is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
      begin
         for Index in Data'Range loop
            Data (Index) :=
              Stream_Element
                (Character'Pos
                   (Text (Text'First + Natural (Index - Data'First))));
         end loop;
         Ada.Streams.Stream_IO.Create
           (File => File, Mode => Ada.Streams.Stream_IO.Out_File, Name => Name);
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Text;
   begin
      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => "",
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Invalid_Request
         and then Result.Status = Http_Client.Errors.Invalid_Request
         and then Result.HTTP_Status_Code = 0,
         "empty download target path should fail before opening a stream");

      if Ada.Directories.Exists (Existing_Path) then
         Ada.Directories.Delete_File (Existing_Path);
      end if;
      Write_Text (Existing_Path, "keep");

      Options.File_Mode := Http_Client.Clients.Create_New;
      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => Existing_Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Write_Failed
         and then Result.Status = Http_Client.Errors.Write_Failed
         and then Result.HTTP_Status_Code = 0,
         "Create_New existing target should fail before opening a stream");
      Assert
        (File_Contains_Text (Existing_Path, "keep"),
         "Create_New preflight should preserve existing target file");

      Ada.Directories.Delete_File (Existing_Path);

      if Ada.Directories.Exists (Policy_Path) then
         Ada.Directories.Delete_File (Policy_Path);
      end if;
      if Ada.Directories.Exists (Parent) then
         Ada.Directories.Delete_Directory (Parent);
      end if;

      Options := Http_Client.Clients.Default_Download_Options;
      Options.Create_Parent_Dirs := True;
      Options.Expected_Size := 6;
      Options.Max_Download_Size := 5;

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => Policy_Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Response_Too_Large
         and then Result.Status = Http_Client.Errors.Response_Too_Large
         and then Result.HTTP_Status_Code = 0
         and then Result.Expected_Final_Size = 6
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "Expected_Size over Max_Download_Size should fail before network");
      Assert
        (not Ada.Directories.Exists (Parent),
         "Expected_Size over Max_Download_Size should not create parent dirs");

      Options := Http_Client.Clients.Default_Download_Options;
      Options.Create_Parent_Dirs := True;
      Options.Verify_SHA256 := True;
      Options.Expected_SHA256_Hex (1) := 'x';

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => Policy_Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Invalid_Configuration
         and then Result.Status = Http_Client.Errors.Invalid_Configuration
         and then Result.HTTP_Status_Code = 0
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "malformed expected SHA-256 should fail before network");
      Assert
        (not Ada.Directories.Exists (Parent),
         "malformed expected SHA-256 should not create parent dirs");
   end Test_Download_To_File_Target_Preflight_Before_Network;

   procedure Test_Download_To_File_Connection_Failure_No_Filesystem_Setup
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Parent  : constant String := "download_connect_failure_parent";
      Path    : constant String := Parent & "/file.bin";
      Options : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result  : Http_Client.Clients.Download_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      if Ada.Directories.Exists (Parent) then
         Ada.Directories.Delete_Directory (Parent);
      end if;

      Options.Create_Parent_Dirs := True;
      Options.File_Mode := Http_Client.Clients.Replace_Atomically;

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => "http://127.0.0.1:1/file.bin",
           Path          => Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Connection_Failed,
         "download connection failure should propagate stream-open status");
      Assert
        (Result.Status = Http_Client.Errors.Connection_Failed
         and then Result.HTTP_Status_Code = 0
         and then Result.Expected_Final_Size = 0
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "download connection failure should return neutral result metadata");
      Assert
        (not Ada.Directories.Exists (Parent),
         "download connection failure should not create parent directories");
   end Test_Download_To_File_Connection_Failure_No_Filesystem_Setup;

   procedure Test_Download_To_File_File_Open_Failure_Closes_Stream
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : constant String :=
        "HTTP/1.1 200 OK"
        & CRLF
        & "Content-Length: 6"
        & CRLF
        & CRLF
        & "ABCDEF";
      Target_Dir : constant String := "download_file_open_failure_target";

      task type File_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end File_Server;

      task body File_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw         : Stream_Element_Array (1 .. 1024);
         Last        : Stream_Element_Offset;
         Outgoing    :
           Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
         Sent_Last   : Stream_Element_Offset;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

         for Index in Outgoing'Range loop
            Outgoing (Index) :=
              Stream_Element
                (Character'Pos
                   (Response (Response'First + Natural (Index - Outgoing'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end File_Server;

      Server   : File_Server;
      Port     : Http_Client.URI.TCP_Port;
      URL      : Unbounded_String;
      Options  : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result   : Http_Client.Clients.Download_Result;
      Status   : Http_Client.Errors.Result_Status;
      Baseline : constant Natural :=
        Http_Client.Resources.Value (Http_Client.Resources.Streaming_Responses_Open);
   begin
      if Ada.Directories.Exists (Target_Dir) then
         Ada.Directories.Delete_Directory (Target_Dir);
      end if;
      Ada.Directories.Create_Directory (Target_Dir);

      Server.Ready (Port);
      URL :=
        To_Unbounded_String
          ("http://127.0.0.1:"
           & Decimal_Image (Natural (Port))
           & "/file.bin");

      Options.File_Mode := Http_Client.Clients.Overwrite;

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => To_String (URL),
           Path          => Target_Dir,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Write_Failed
         and then Result.Status = Http_Client.Errors.Write_Failed
         and then Result.HTTP_Status_Code = 200
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "download file-open failure should return write failure with response metadata");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Streaming_Responses_Open)
         = Baseline,
         "download file-open failure should close the opened response stream");

      Ada.Directories.Delete_Directory (Target_Dir);
   exception
      when others =>
         if Ada.Directories.Exists (Target_Dir) then
            Ada.Directories.Delete_Directory (Target_Dir);
         end if;
         raise;
   end Test_Download_To_File_File_Open_Failure_Closes_Stream;

   procedure Test_Download_To_File_Require_Success_Status
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : constant String :=
        "HTTP/1.1 404 Not Found"
        & CRLF
        & "Content-Length: 9"
        & CRLF
        & CRLF
        & "not found";
      Path     : constant String := "status_gated_download_test.tmp";

      task type Not_Found_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
      end Not_Found_Server;

      task body Not_Found_Server is
         Server      : GNAT.Sockets.Socket_Type;
         Peer        : GNAT.Sockets.Socket_Type;
         Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
         Raw         : Stream_Element_Array (1 .. 1024);
         Last        : Stream_Element_Offset;
         Outgoing    :
           Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
         Sent_Last   : Stream_Element_Offset;
      begin
         GNAT.Sockets.Create_Socket (Server);
         Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
         Server_Addr.Port := 0;
         GNAT.Sockets.Bind_Socket (Server, Server_Addr);
         GNAT.Sockets.Listen_Socket (Server);

         declare
            Bound : constant GNAT.Sockets.Sock_Addr_Type :=
              GNAT.Sockets.Get_Socket_Name (Server);
         begin
            accept Ready (Port : out Http_Client.URI.TCP_Port) do
               Port := Http_Client.URI.TCP_Port (Bound.Port);
            end Ready;
         end;

         GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
         GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

         for Index in Outgoing'Range loop
            Outgoing (Index) :=
              Stream_Element
                (Character'Pos
                   (Response (Response'First + Natural (Index - Outgoing'First))));
         end loop;
         GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);
      end Not_Found_Server;

      Server  : Not_Found_Server;
      Port    : Http_Client.URI.TCP_Port;
      URL     : Unbounded_String;
      Options : Http_Client.Clients.Download_Options :=
        Http_Client.Clients.Default_Download_Options;
      Result  : Http_Client.Clients.Download_Result;
      Status  : Http_Client.Errors.Result_Status;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;

      Server.Ready (Port);
      URL :=
        To_Unbounded_String
          ("http://127.0.0.1:"
           & Decimal_Image (Natural (Port))
           & "/missing.bin");

      Options.Require_Success_Status := True;
      Options.File_Mode := Http_Client.Clients.Replace_Atomically;

      Status :=
        Http_Client.Clients.Download_To_File
          (URL           => To_String (URL),
           Path          => Path,
           Result        => Result,
           Options       => Options,
           Configuration => Http_Client.Clients.Strict_Client_Configuration);

      Assert
        (Status = Http_Client.Errors.Protocol_Error,
         "status-gated download should reject non-2xx response");
      Assert
        (Result.Status = Http_Client.Errors.Protocol_Error
         and then Result.HTTP_Status_Code = 404
         and then Result.Expected_Final_Size = 9
         and then Result.Bytes_Written = 0
         and then Result.Final_Size = 0,
         "status-gated download should preserve response metadata without writing");
      Assert
        (not Ada.Directories.Exists (Path),
         "status-gated non-2xx download should not install target file");
   end Test_Download_To_File_Require_Success_Status;

   procedure Test_Download_To_File_Resume_Appends_206
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Path : constant String := "resume_download_test.tmp";

      procedure Write_Text (Name : String; Text : String) is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
      begin
         for Index in Data'Range loop
            Data (Index) :=
              Stream_Element
                (Character'Pos
                   (Text (Text'First + Natural (Index - Data'First))));
         end loop;
         Ada.Streams.Stream_IO.Create
           (File => File, Mode => Ada.Streams.Stream_IO.Out_File, Name => Name);
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Text;

      procedure Write_Sparse_Too_Large (Name : String) is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : constant Stream_Element_Array (1 .. 1) := [others => 0];
      begin
         Ada.Streams.Stream_IO.Create
           (File => File, Mode => Ada.Streams.Stream_IO.Out_File, Name => Name);
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Count (Natural'Last) + 2);
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Sparse_Too_Large;

      procedure Write_Sparse_Natural_Last (Name : String) is
         File : Ada.Streams.Stream_IO.File_Type;
         Data : constant Stream_Element_Array (1 .. 1) := [others => 0];
      begin
         Ada.Streams.Stream_IO.Create
           (File => File, Mode => Ada.Streams.Stream_IO.Out_File, Name => Name);
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Count (Natural'Last));
         Ada.Streams.Stream_IO.Write (File, Data);
         Ada.Streams.Stream_IO.Close (File);
      end Write_Sparse_Natural_Last;

      procedure Run_Case
        (Response                   : String;
         Configured_Size            : Natural;
         Max_Download_Size          : Natural;
         Expected_Status            : Http_Client.Errors.Result_Status;
         Expected_Final_Size        : Natural;
         Message                    : String;
         Expected_Bytes_Written     : Natural := 0;
         Expected_Result_Final_Size : Natural := 2;
         Expected_File_Size         : Natural := 2;
         Expected_File_Text         : String := "AB")
      is
         task type Resume_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
            entry Request_Seen (Text : out Unbounded_String);
         end Resume_Server;

         task body Resume_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Request     : Unbounded_String;
            Raw         : Stream_Element_Array (1 .. 4096);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request, Character'Val (Raw (Index)));
               end loop;
            end if;

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);

            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request;
            end Request_Seen;
         end Resume_Server;

         Server       : Resume_Server;
         Port         : Http_Client.URI.TCP_Port;
         URL          : Unbounded_String;
         Request_Text : Unbounded_String;
         Options      : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result       : Http_Client.Clients.Download_Result;
         Status       : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Text (Path, "AB");
         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/file.bin");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Resume_If_Range := To_Unbounded_String ("""resume-etag""");
         Options.Expected_Size := Configured_Size;
         Options.Max_Download_Size := Max_Download_Size;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert (Status = Expected_Status, Message);
         Assert
           (Result.HTTP_Status_Code = 206,
            Message & " should report final HTTP status code");

         Server.Request_Seen (Request_Text);
         Assert
           (Index (Request_Text, "Range: bytes=2-") > 0,
            Message & " should send a Range request from existing size");
         Assert
           (Index (Request_Text, "If-Range: ""resume-etag""") > 0,
            Message & " should send configured If-Range validator");

         if Expected_Status = Http_Client.Errors.Ok then
            Assert
              (Result.Resumed
               and then Result.Resume_Offset = 2,
               "resumable download should report accepted resume offset");
            Assert
              (Result.Bytes_Written = 4,
               "resumable download should report newly appended bytes");
            Assert
              (Result.Expected_Final_Size = 6,
               "resumable download should report expected final size from Content-Range");
            Assert
              (Result.Final_Size = 6,
               "resumable download should report final file size");
            Assert
              (Natural (Ada.Directories.Size (Path)) = 6
               and then File_Contains_Text (Path, "ABCDEF"),
               "resumable download should append the returned byte range");
            Ada.Directories.Delete_File (Path);
         else
            Assert
              (Result.Status = Expected_Status
               and then Result.Expected_Final_Size = Expected_Final_Size
               and then Result.Bytes_Written = Expected_Bytes_Written
               and then Result.Final_Size = Expected_Result_Final_Size,
               Message & " should report the failed resume state");
            Assert
              (Natural (Ada.Directories.Size (Path)) = Expected_File_Size
               and then File_Contains_Text (Path, Expected_File_Text),
               "failed resume should preserve the selected partial file state");
            Ada.Directories.Delete_File (Path);
         end if;
      end Run_Case;

      procedure Run_Already_Complete_416
        (Extra_Header    : String := "";
         Expected_Status : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
         Message         : String := "already-complete resumed download should accept matching 416")
      is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 416 Range Not Satisfiable"
           & CRLF
           & "Content-Range: bytes */6"
           & CRLF
           & Extra_Header
           & CRLF;

         task type Resume_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
            entry Request_Seen (Text : out Unbounded_String);
         end Resume_Server;

         task body Resume_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Request     : Unbounded_String;
            Raw         : Stream_Element_Array (1 .. 4096);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request, Character'Val (Raw (Index)));
               end loop;
            end if;

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);

            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request;
            end Request_Seen;
         end Resume_Server;

         Server       : Resume_Server;
         Port         : Http_Client.URI.TCP_Port;
         URL          : Unbounded_String;
         Request_Text : Unbounded_String;
         Options      : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result       : Http_Client.Clients.Download_Result;
         Status       : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Text (Path, "ABCDEF");
         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/file.bin");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Resume_If_Range := To_Unbounded_String ("""resume-etag""");
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Server.Request_Seen (Request_Text);

         Assert
           (Status = Expected_Status
            and then Result.Status = Expected_Status,
            Message);

         if Expected_Status = Http_Client.Errors.Ok then
            Assert
              (Result.HTTP_Status_Code = 416
               and then Result.Resumed
               and then Result.Resume_Offset = 6
               and then Result.Expected_Final_Size = 6
               and then Result.Bytes_Written = 0
               and then Result.Final_Size = 6,
               "already-complete resumed download should report existing file state");
         end if;

         Assert
           (Index (Request_Text, "Range: bytes=6-") > 0,
            "already-complete resumed download should request from existing size");
         Assert
           (Natural (Ada.Directories.Size (Path)) = 6
            and then File_Contains_Text (Path, "ABCDEF"),
            "already-complete resumed download should leave local file unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Already_Complete_416;

      procedure Run_Local_Already_Complete_No_Network is
         URL     : constant String := "http://127.0.0.1:1/file.bin";
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Text (Path, "ABCDEF");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Expected_Size := 6;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => URL,
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Ok
            and then Result.Status = Http_Client.Errors.Ok,
            "already-complete resume should succeed without network when expected size matches");
         Assert
           (Result.HTTP_Status_Code = 0
            and then Result.Resumed
            and then Result.Resume_Offset = 6
            and then Result.Expected_Final_Size = 6
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = 6,
            "already-complete local resume should report local file state");
         Assert
           (Natural (Ada.Directories.Size (Path)) = 6
            and then File_Contains_Text (Path, "ABCDEF"),
            "already-complete local resume should leave local file unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Local_Already_Complete_No_Network;

      procedure Run_Local_Too_Large_No_Network is
         URL     : constant String := "http://127.0.0.1:1/file.bin";
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Text (Path, "ABCDEF");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Expected_Size := 5;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => URL,
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Integrity_Check_Failed
            and then Result.Status = Http_Client.Errors.Integrity_Check_Failed,
            "oversized local resume file should fail before network");
         Assert
           (Result.HTTP_Status_Code = 0
            and then Result.Resumed
            and then Result.Resume_Offset = 6
            and then Result.Expected_Final_Size = 5
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = 6,
            "oversized local resume file should report local file state");
         Assert
           (Natural (Ada.Directories.Size (Path)) = 6
            and then File_Contains_Text (Path, "ABCDEF"),
            "oversized local resume file should be left unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Local_Too_Large_No_Network;

      procedure Run_Local_Over_Max_No_Network is
         URL     : constant String := "http://127.0.0.1:1/file.bin";
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Text (Path, "ABCDEF");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Max_Download_Size := 5;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => URL,
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Response_Too_Large
            and then Result.Status = Http_Client.Errors.Response_Too_Large,
            "resume file larger than Max_Download_Size should fail before network");
         Assert
           (Result.HTTP_Status_Code = 0
            and then Result.Resumed
            and then Result.Resume_Offset = 6
            and then Result.Expected_Final_Size = 0
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = 6,
            "resume file larger than Max_Download_Size should report local file state");
         Assert
           (Natural (Ada.Directories.Size (Path)) = 6
            and then File_Contains_Text (Path, "ABCDEF"),
            "resume file larger than Max_Download_Size should be left unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Local_Over_Max_No_Network;

      procedure Run_Local_Over_Natural_No_Network is
         URL     : constant String := "http://127.0.0.1:1/file.bin";
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Sparse_Too_Large (Path);

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => URL,
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Response_Too_Large
            and then Result.Status = Http_Client.Errors.Response_Too_Large,
            "resume file larger than Natural'Last should fail before network");
         Assert
           (Result.HTTP_Status_Code = 0
            and then Result.Resumed
            and then Result.Resume_Offset = Natural'Last
            and then Result.Expected_Final_Size = 0
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = Natural'Last,
            "resume file larger than Natural'Last should report saturated local file state");
         Assert
           (Ada.Directories.Exists (Path),
            "resume file larger than Natural'Last should be left unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Local_Over_Natural_No_Network;

      procedure Run_Resume_Length_Overflow is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Offset   : constant String := Decimal_Image (Natural'Last);
         Response : constant String :=
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Length: 1"
           & CRLF
           & "Content-Range: bytes " & Offset & "-" & Offset & "/*"
           & CRLF
           & CRLF
           & "Z";

         task type Overflow_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
            entry Request_Seen (Text : out Unbounded_String);
         end Overflow_Server;

         task body Overflow_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Request     : Unbounded_String;
            Raw         : Stream_Element_Array (1 .. 4096);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request, Character'Val (Raw (Index)));
               end loop;
            end if;

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);

            accept Request_Seen (Text : out Unbounded_String) do
               Text := Request;
            end Request_Seen;
         end Overflow_Server;

         Server       : Overflow_Server;
         Port         : Http_Client.URI.TCP_Port;
         URL          : Unbounded_String;
         Request_Text : Unbounded_String;
         Options      : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result       : Http_Client.Clients.Download_Result;
         Status       : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Write_Sparse_Natural_Last (Path);
         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/overflow.bin");

         Options.File_Mode := Http_Client.Clients.Overwrite;
         Options.Enable_Resume := True;
         Options.Max_Download_Size := 0;
         Options.Preserve_Partial_File := True;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Server.Request_Seen (Request_Text);

         Assert
           (Status = Http_Client.Errors.Response_Too_Large
            and then Result.Status = Http_Client.Errors.Response_Too_Large,
            "resume offset plus Content-Length overflow should fail as too large");
         Assert
           (Result.HTTP_Status_Code = 206
            and then Result.Resumed
            and then Result.Resume_Offset = Natural'Last
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = Natural'Last,
            "resume offset overflow should report saturated local state");
         Assert
           (Index (Request_Text, "Range: bytes=" & Offset & "-") > 0,
            "resume offset overflow should request from existing size");
         Assert
           (Ada.Directories.Exists (Path)
            and then Ada.Directories.Size (Path) = Ada.Directories.File_Size (Natural'Last),
            "resume offset overflow should leave sparse file unchanged");
         Ada.Directories.Delete_File (Path);
      end Run_Resume_Length_Overflow;

      procedure Run_Resume_Open_Ended_Range_Overflow is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Offset   : constant String := Decimal_Image (Natural'Last);
         Response : constant String :=
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Range: bytes 2-" & Offset & "/*"
           & CRLF
           & CRLF;
      begin
         Run_Case
           (Response                   => Response,
            Configured_Size            => 0,
            Max_Download_Size          => 0,
            Expected_Status            => Http_Client.Errors.Response_Too_Large,
            Expected_Final_Size        => 0,
            Message                    =>
              "resumed open-ended Content-Range overflow should fail as too large",
            Expected_Bytes_Written     => 0,
            Expected_Result_Final_Size => Natural'Last,
            Expected_File_Size         => 2,
            Expected_File_Text         => "AB");
      end Run_Resume_Open_Ended_Range_Overflow;

      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Run_Case
        (Response            =>
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Range: bytes 2-5/6"
           & CRLF
           & CRLF
           & "CDEF",
         Configured_Size     => 0,
         Max_Download_Size   => 0,
         Expected_Status     => Http_Client.Errors.Ok,
         Expected_Final_Size => 6,
         Message             => "resumable download should accept a matching 206 response");

      Run_Case
        (Response                   =>
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Range: bytes 2-5/6"
           & CRLF
           & CRLF
           & "CD",
         Configured_Size            => 0,
         Max_Download_Size          => 0,
         Expected_Status            => Http_Client.Errors.Protocol_Error,
         Expected_Final_Size        => 6,
         Message                    => "resumable download should reject a short 206 body",
         Expected_Bytes_Written     => 2,
         Expected_Result_Final_Size => 4,
         Expected_File_Size         => 4,
         Expected_File_Text         => "ABCD");

      Run_Case
        (Response            =>
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Length: 4"
           & CRLF
           & "Content-Range: bytes 2-6/7"
           & CRLF
           & CRLF
           & "CDEF",
         Configured_Size     => 0,
         Max_Download_Size   => 0,
         Expected_Status     => Http_Client.Errors.Protocol_Error,
         Expected_Final_Size => 7,
         Message             => "resumable download should reject inconsistent 206 length metadata");

      Run_Case
        (Response            =>
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Range: bytes 2-5/6"
           & CRLF
           & CRLF
           & "CDEF",
         Configured_Size     => 5,
         Max_Download_Size   => 0,
         Expected_Status     => Http_Client.Errors.Integrity_Check_Failed,
         Expected_Final_Size => 6,
         Message             => "resumable download should reject expected-size mismatch from Content-Range");

      Run_Case
        (Response            =>
           "HTTP/1.1 206 Partial Content"
           & CRLF
           & "Content-Range: bytes 2-5/6"
           & CRLF
           & CRLF
           & "CDEF",
         Configured_Size     => 0,
         Max_Download_Size   => 5,
         Expected_Status     => Http_Client.Errors.Response_Too_Large,
         Expected_Final_Size => 6,
         Message             => "resumable download should reject Content-Range over max size");

      Run_Already_Complete_416;
      Run_Already_Complete_416
        (Extra_Header    => "Content-Length: nope" & CRLF,
         Expected_Status => Http_Client.Errors.Invalid_Header,
         Message         => "already-complete 416 resume should reject malformed Content-Length");
      Run_Local_Already_Complete_No_Network;
      Run_Local_Too_Large_No_Network;
      Run_Local_Over_Max_No_Network;
      Run_Local_Over_Natural_No_Network;
      Run_Resume_Length_Overflow;
      Run_Resume_Open_Ended_Range_Overflow;
   end Test_Download_To_File_Resume_Appends_206;

   procedure Test_Download_To_File_Integrity_Checks
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Path         : constant String := "integrity_download_test.tmp";
      Good_SHA256  : constant String :=
        "e9c0f8b575cbfcb42ab3b78ecc87efa3b011d9a5d10b09fa4e96f240bf6a82f5";
      Bad_SHA256   : constant String :=
        "0000000000000000000000000000000000000000000000000000000000000000";

      procedure Run_Case
        (Expected_SHA256 : String;
         Expected_Size   : Natural;
         Expected_Status : Http_Client.Errors.Result_Status;
         Message         : String)
      is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 6"
           & CRLF
           & CRLF
           & "ABCDEF";

         task type File_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
         end File_Server;

         task body File_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Raw         : Stream_Element_Array (1 .. 1024);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);
         end File_Server;

         Server    : File_Server;
         Port      : Http_Client.URI.TCP_Port;
         URL       : Unbounded_String;
         Options   : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result    : Http_Client.Clients.Download_Result;
         Status    : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/file.bin");

         Options.File_Mode := Http_Client.Clients.Replace_Atomically;
         Options.Expected_Size := Expected_Size;
         Options.Verify_SHA256 := True;
         Options.Expected_SHA256_Hex := Expected_SHA256;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert (Status = Expected_Status, Message);
         Assert (Result.Status = Expected_Status, Message & " should update result status");

         if Expected_Status = Http_Client.Errors.Ok then
            Assert
              (Result.HTTP_Status_Code = 200
               and then Result.Expected_Final_Size = 6
               and then Result.Redirect_Count = 0
               and then Result.Retry_Attempt_Count = 1
               and then not Result.Resumed
               and then Result.Resume_Offset = 0
               and then Result.Bytes_Written = 6
               and then Result.Final_Size = 6
               and then File_Contains_Text (Path, "ABCDEF"),
               "successful integrity verification should install downloaded file");
            Ada.Directories.Delete_File (Path);
         else
            Assert
              (not Ada.Directories.Exists (Path),
               "failed integrity verification should not install final target");
            if Expected_Size /= 6 then
               Assert
                 (Result.HTTP_Status_Code = 200
                  and then Result.Expected_Final_Size = 6
                  and then Result.Bytes_Written = 0
                  and then Result.Final_Size = 0,
                  "declared size mismatch should fail before writing bytes");
            end if;
         end if;
      end Run_Case;

      procedure Run_Truncated_Content_Length is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 6"
           & CRLF
           & CRLF
           & "ABC";

         task type File_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
         end File_Server;

         task body File_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Raw         : Stream_Element_Array (1 .. 1024);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);
         end File_Server;

         Server  : File_Server;
         Port    : Http_Client.URI.TCP_Port;
         URL     : Unbounded_String;
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/truncated.bin");

         Options.File_Mode := Http_Client.Clients.Replace_Atomically;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Incomplete_Message
            and then Result.Status = Http_Client.Errors.Incomplete_Message,
            "truncated fixed-length download should fail as incomplete");
         Assert
           (Result.HTTP_Status_Code = 200
            and then Result.Expected_Final_Size = 6
            and then Result.Bytes_Written <= 3
            and then Result.Final_Size <= 3,
            "truncated fixed-length download should report partial progress only");
         Assert
           (not Ada.Directories.Exists (Path),
            "truncated fixed-length download should not install final target");
      end Run_Truncated_Content_Length;

      procedure Run_Invalid_Content_Length
        (Header  : String;
         Message : String)
      is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & Header
           & CRLF
           & CRLF
           & "ABCDEF";

         task type File_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
         end File_Server;

         task body File_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Raw         : Stream_Element_Array (1 .. 1024);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);
         end File_Server;

         Server  : File_Server;
         Port    : Http_Client.URI.TCP_Port;
         URL     : Unbounded_String;
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/invalid-length.bin");

         Options.File_Mode := Http_Client.Clients.Replace_Atomically;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Invalid_Header
            and then Result.Status = Http_Client.Errors.Invalid_Header,
            Message & " should fail as invalid header");
         Assert
           (Result.Bytes_Written = 0
            and then Result.Final_Size = 0,
            Message & " should not write bytes");
         Assert
           (not Ada.Directories.Exists (Path),
            Message & " should not install final target");
      end Run_Invalid_Content_Length;

   begin
      Run_Case
        (Expected_SHA256 => Good_SHA256,
         Expected_Size   => 6,
         Expected_Status => Http_Client.Errors.Ok,
         Message         => "matching size and SHA-256 should accept download");

      Run_Case
        (Expected_SHA256 => Bad_SHA256,
         Expected_Size   => 6,
         Expected_Status => Http_Client.Errors.Integrity_Check_Failed,
         Message         => "mismatched SHA-256 should fail download integrity check");

      Run_Case
        (Expected_SHA256 => Good_SHA256,
         Expected_Size   => 5,
         Expected_Status => Http_Client.Errors.Integrity_Check_Failed,
         Message         => "declared size mismatch should fail before writing");

      Run_Truncated_Content_Length;
      Run_Invalid_Content_Length
        (Header  => "Content-Length: nope",
         Message => "download with non-numeric Content-Length");
      Run_Invalid_Content_Length
        (Header  => "Content-Length:",
         Message => "download with empty Content-Length");
   end Test_Download_To_File_Integrity_Checks;

   procedure Test_Download_To_File_Progress_Callback
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);

      Path : constant String := "progress_download_test.tmp";

      procedure Run_Case
        (Callback_Status : Http_Client.Errors.Result_Status;
         Expected_Status : Http_Client.Errors.Result_Status;
         Interval        : Natural;
         Expected_Count  : Natural;
         Message         : String)
      is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 6"
           & CRLF
           & CRLF
           & "ABCDEF";

         task type File_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
         end File_Server;

         task body File_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Raw         : Stream_Element_Array (1 .. 1024);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);
         end File_Server;

         Server  : File_Server;
         Port    : Http_Client.URI.TCP_Port;
         URL     : Unbounded_String;
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Download_Progress_Count := 0;
         Download_Progress_Bytes := 0;
         Download_Progress_Total := 0;
         Download_Progress_Status := Callback_Status;

         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/file.bin");

         Options.File_Mode := Http_Client.Clients.Replace_Atomically;
         Options.Buffer_Size := 2;
         Options.Progress_Callback := Capture_Download_Progress'Access;
         Options.Progress_Interval_Bytes := Interval;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert (Status = Expected_Status, Message);
         Assert (Result.Status = Expected_Status, Message & " should update result status");
         Assert
           (Download_Progress_Count = Expected_Count,
            Message & " should invoke callback expected number of times");
         Assert (Download_Progress_Total = 6, Message & " should report known total size");

         if Expected_Status = Http_Client.Errors.Ok then
            Assert
              (Download_Progress_Bytes = 6
               and then Result.HTTP_Status_Code = 200
               and then Result.Expected_Final_Size = 6
               and then Result.Redirect_Count = 0
               and then Result.Retry_Attempt_Count = 1
               and then not Result.Resumed
               and then Result.Resume_Offset = 0
               and then Result.Bytes_Written = 6
               and then Result.Final_Size = 6
               and then File_Contains_Text (Path, "ABCDEF"),
               "successful progress callback should preserve completed download");
            Ada.Directories.Delete_File (Path);
         else
            Assert
              (not Ada.Directories.Exists (Path),
               "aborted progress callback should not install final target");
         end if;
      end Run_Case;

      procedure Run_Empty_Case is
         CRLF     : constant String := Character'Val (13) & Character'Val (10);
         Response : constant String :=
           "HTTP/1.1 200 OK"
           & CRLF
           & "Content-Length: 0"
           & CRLF
           & CRLF;

         task type Empty_Server is
            entry Ready (Port : out Http_Client.URI.TCP_Port);
         end Empty_Server;

         task body Empty_Server is
            Server      : GNAT.Sockets.Socket_Type;
            Peer        : GNAT.Sockets.Socket_Type;
            Server_Addr : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
            Peer_Addr   : GNAT.Sockets.Sock_Addr_Type;
            Raw         : Stream_Element_Array (1 .. 1024);
            Last        : Stream_Element_Offset;
            Outgoing    :
              Stream_Element_Array (1 .. Stream_Element_Offset (Response'Length));
            Sent_Last   : Stream_Element_Offset;
         begin
            GNAT.Sockets.Create_Socket (Server);
            Server_Addr.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
            Server_Addr.Port := 0;
            GNAT.Sockets.Bind_Socket (Server, Server_Addr);
            GNAT.Sockets.Listen_Socket (Server);

            declare
               Bound : constant GNAT.Sockets.Sock_Addr_Type :=
                 GNAT.Sockets.Get_Socket_Name (Server);
            begin
               accept Ready (Port : out Http_Client.URI.TCP_Port) do
                  Port := Http_Client.URI.TCP_Port (Bound.Port);
               end Ready;
            end;

            GNAT.Sockets.Accept_Socket (Server, Peer, Peer_Addr);
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);

            for Index in Outgoing'Range loop
               Outgoing (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response (Response'First + Natural (Index - Outgoing'First))));
            end loop;
            GNAT.Sockets.Send_Socket (Peer, Outgoing, Sent_Last);
            GNAT.Sockets.Close_Socket (Peer);
            GNAT.Sockets.Close_Socket (Server);
         end Empty_Server;

         Server  : Empty_Server;
         Port    : Http_Client.URI.TCP_Port;
         URL     : Unbounded_String;
         Options : Http_Client.Clients.Download_Options :=
           Http_Client.Clients.Default_Download_Options;
         Result  : Http_Client.Clients.Download_Result;
         Status  : Http_Client.Errors.Result_Status;
      begin
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;

         Download_Progress_Count := 0;
         Download_Progress_Bytes := 0;
         Download_Progress_Total := 99;
         Download_Progress_Status := Http_Client.Errors.Ok;

         Server.Ready (Port);
         URL :=
           To_Unbounded_String
             ("http://127.0.0.1:"
              & Decimal_Image (Natural (Port))
              & "/empty.bin");

         Options.File_Mode := Http_Client.Clients.Replace_Atomically;
         Options.Progress_Callback := Capture_Download_Progress'Access;

         Status :=
           Http_Client.Clients.Download_To_File
             (URL           => To_String (URL),
              Path          => Path,
              Result        => Result,
              Options       => Options,
              Configuration => Http_Client.Clients.Strict_Client_Configuration);

         Assert
           (Status = Http_Client.Errors.Ok
            and then Result.Status = Http_Client.Errors.Ok,
            "empty download with progress callback should succeed");
         Assert
           (Download_Progress_Count = 1
            and then Download_Progress_Bytes = 0
            and then Download_Progress_Total = 0,
            "empty download should emit final zero-byte progress callback");
         Assert
           (Result.HTTP_Status_Code = 200
            and then Result.Expected_Final_Size = 0
            and then Result.Bytes_Written = 0
            and then Result.Final_Size = 0
            and then Ada.Directories.Exists (Path),
            "empty download should install an empty target and neutral sizes");

         Ada.Directories.Delete_File (Path);
      end Run_Empty_Case;

   begin
      Run_Case
        (Callback_Status => Http_Client.Errors.Ok,
         Expected_Status => Http_Client.Errors.Ok,
         Interval        => 0,
         Expected_Count  => 3,
         Message         => "progress callback returning Ok should continue");

      Run_Case
        (Callback_Status => Http_Client.Errors.Ok,
         Expected_Status => Http_Client.Errors.Ok,
         Interval        => 5,
         Expected_Count  => 1,
         Message         => "progress interval should throttle intermediate callbacks");

      Run_Case
        (Callback_Status => Http_Client.Errors.Cancelled,
         Expected_Status => Http_Client.Errors.Cancelled,
         Interval        => 0,
         Expected_Count  => 1,
         Message         => "progress callback returning Cancelled should abort");

      Run_Empty_Case;
   end Test_Download_To_File_Progress_Callback;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Clients");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_High_Level_Client_Configuration_Defaults'Access,
         "Test_High_Level_Client_Configuration_Defaults");
      Register_Routine
        (T,
         Test_High_Level_Client_Invalid_Configuration'Access,
         "Test_High_Level_Client_Invalid_Configuration");
      Register_Routine
        (T,
         Test_High_Level_Client_Failed_Configure_Preserves_Client'Access,
         "Test_High_Level_Client_Failed_Configure_Preserves_Client");
      Register_Routine
        (T,
         Test_High_Level_Client_Initialization_State_Introspection'Access,
         "Test_High_Level_Client_Initialization_State_Introspection");
      Register_Routine
        (T,
         Test_High_Level_Client_Default_Object_Is_Uninitialized'Access,
         "Test_High_Level_Client_Default_Object_Is_Uninitialized");
      Register_Routine
        (T,
         Test_High_Level_Client_Default_Object_Can_Be_Configured'Access,
         "Test_High_Level_Client_Default_Object_Can_Be_Configured");
      Register_Routine
        (T,
         Test_High_Level_Client_Failed_Configure_Preserves_Configuration'Access,
         "Test_High_Level_Client_Failed_Configure_Preserves_Configuration");
      Register_Routine
        (T,
         Test_High_Level_Client_Convenience_Invalid_URL'Access,
         "Test_High_Level_Client_Convenience_Invalid_URL");
      Register_Routine
        (T,
         Test_High_Level_Client_Uninitialized_Execute'Access,
         "Test_High_Level_Client_Uninitialized_Execute");
      Register_Routine
        (T,
         Test_High_Level_Client_Uninitialized_Convenience_Methods'Access,
         "Test_High_Level_Client_Uninitialized_Convenience_Methods");
      Register_Routine
        (T,
         Test_High_Level_Client_Head_Convenience'Access,
         "Test_High_Level_Client_Head_Convenience");
      Register_Routine
        (T,
         Test_Client_Follows_Relative_302_And_Rewrites_Post'Access,
         "Test_Client_Follows_Relative_302_And_Rewrites_Post");
      Register_Routine
        (T,
         Test_Download_To_File_Defaults_And_Uninitialized_Guard'Access,
         "Test_Download_To_File_Defaults_And_Uninitialized_Guard");
      Register_Routine
        (T,
         Test_Atomic_File_Write_Primitives'Access,
         "Test_Atomic_File_Write_Primitives");
      Register_Routine
        (T,
         Test_Download_To_File_Pre_Cancelled_Token'Access,
         "Test_Download_To_File_Pre_Cancelled_Token");
      Register_Routine
        (T,
         Test_Download_To_File_Target_Preflight_Before_Network'Access,
         "Test_Download_To_File_Target_Preflight_Before_Network");
      Register_Routine
        (T,
         Test_Download_To_File_Connection_Failure_No_Filesystem_Setup'Access,
         "Test_Download_To_File_Connection_Failure_No_Filesystem_Setup");
      Register_Routine
        (T,
         Test_Download_To_File_File_Open_Failure_Closes_Stream'Access,
         "Test_Download_To_File_File_Open_Failure_Closes_Stream");
      Register_Routine
        (T,
         Test_Download_To_File_Require_Success_Status'Access,
         "Test_Download_To_File_Require_Success_Status");
      Register_Routine
        (T,
         Test_Download_To_File_Resume_Appends_206'Access,
         "Test_Download_To_File_Resume_Appends_206");
      Register_Routine
        (T,
         Test_Download_To_File_Integrity_Checks'Access,
         "Test_Download_To_File_Integrity_Checks");
      Register_Routine
        (T,
         Test_Download_To_File_Progress_Callback'Access,
         "Test_Download_To_File_Progress_Callback");
   end Register_Tests;

end Http_Client.Clients.Tests;
