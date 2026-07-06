with Ada.Calendar;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Clients;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Requests;
with Http_Client.Resources;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Async.Tests is

   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   use AUnit.Assertions;
   use AUnit.Test_Cases.Registration;

   use type Http_Client.Errors.Result_Status;
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

   procedure AUnit_Test_Async_Client_Initialization_And_Invalid_Submit
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Sync_Client  : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Async_Client : Http_Client.Async.Async_Client;
      Handle       : Http_Client.Async.Request_Handle;
      Request      : Http_Client.Requests.Request :=
        Http_Client.Requests.Default_Request;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Async.Submit (Async_Client, Request, Handle);
      Assert
        (Status = Http_Client.Errors.Client_Not_Initialized,
         "submit before async initialization should be rejected deterministically");

      Http_Client.Resources.Reset_All;
      Status :=
        Http_Client.Async.Initialize
          (Async_Client,
           Sync_Client,
           (Max_Workers => 1, Max_Queued => 2, Cancel_On_Finalize => True));
      Assert
        (Status = Http_Client.Errors.Ok,
         "async initialization around an initialized high-level client should succeed");
      Assert
        (Http_Client.Async.Is_Initialized (Async_Client),
         "async client should report initialized after successful Initialize");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Async_Clients_Open)
         = 1
         and then
           Http_Client.Resources.Value
             (Http_Client.Resources.Async_Workers_Configured)
           = 1,
         "async initialization should expose one client and one configured worker");

      Status := Http_Client.Async.Submit (Async_Client, Request, Handle);
      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "invalid default request should be rejected before queueing");

      Status :=
        Http_Client.Async.Submit_Get
          (Async_Client, "ftp://example.invalid/", Handle);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature
         or else Status = Http_Client.Errors.Invalid_URI,
         "unsupported async convenience URL should be rejected before queueing");

      Http_Client.Async.Shutdown (Async_Client, Cancel_Pending => True);
      Assert
        (not Http_Client.Async.Is_Initialized (Async_Client),
         "async shutdown should leave the client uninitialized");
      Assert
        (Http_Client.Resources.Value (Http_Client.Resources.Async_Clients_Open)
         = 0
         and then
           Http_Client.Resources.Value
             (Http_Client.Resources.Async_Workers_Configured)
           = 0,
         "async shutdown should release client and worker resource counters");

      Status := Http_Client.Async.Submit (Async_Client, Request, Handle);
      Assert
        (Status = Http_Client.Errors.Async_Shutdown,
         "submit after explicit async shutdown should be rejected as shutdown, not as hidden reinitialization");
   end AUnit_Test_Async_Client_Initialization_And_Invalid_Submit;

   procedure Test_Async_Invalid_Handle_Lifecycle
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (Case_Context);
      Handle : Http_Client.Async.Request_Handle;
      Value  : Http_Client.Clients.Client_Result;
   begin
      Assert
        (Http_Client.Async.Poll (Handle)
         = Http_Client.Errors.Async_Handle_Invalid,
         "polling an invalid async handle should be deterministic");
      Assert
        (Http_Client.Async.Cancel (Handle)
         = Http_Client.Errors.Async_Handle_Invalid,
         "cancelling an invalid async handle should be deterministic");
      Assert
        (Http_Client.Async.Result (Handle, Value)
         = Http_Client.Errors.Async_Handle_Invalid,
         "consuming an invalid async handle should be deterministic");
      Assert
        (Value.Status = Http_Client.Errors.Async_Handle_Invalid,
         "invalid handle result output should carry the invalid-handle status");
   end Test_Async_Invalid_Handle_Lifecycle;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Async");
   end Name;
   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
   begin
      Register_Routine
        (T,
         AUnit_Test_Async_Client_Initialization_And_Invalid_Submit'Access,
         "Test_Async_Client_Initialization_And_Invalid_Submit");
      Register_Routine
        (T,
         Test_Async_Invalid_Handle_Lifecycle'Access,
         "Test_Async_Invalid_Handle_Lifecycle");
   end Register_Tests;

end Http_Client.Async.Tests;
