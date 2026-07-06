with Ada.Calendar;
with Ada.Directories; use Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AUnit.Assertions;

with Http_Client.Crypto;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Cache.Persistent.Tests is

   use AUnit.Assertions;
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

   procedure Test_Persistent_Cache_Open_Store_Reopen

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_a");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/persist?x=1", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""v1"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 7"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "payload",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should create explicit directory");
      Assert
        (Http_Client.Cache.Persistent.Is_Open (Store),
         "persistent cache should report open state");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should store cacheable response");
      Assert
        (Http_Client.Cache.Persistent.Entry_Count (Store) = 1,
         "persistent store should expose entry count");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should reopen existing directory");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 10.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should serve fresh hit after reopen");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "payload",
         "persistent hit should preserve body bytes");
      Assert
        (Meta.Source = Http_Client.Cache.From_Fresh_Cache,
         "persistent hit should use cache metadata");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Open_Store_Reopen;

   procedure Test_Persistent_Cache_No_Store_And_Corrupt_Skip

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_b");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      F      : Ada.Text_IO.File_Type;
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/private", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: no-store"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 6"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "secret",
         Res);
      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent cache should open for no-store test");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res);
      Assert
        (Status /= Http_Client.Errors.Ok,
         "persistent cache must reuse no-store bypass");
      Status := Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "no-store response should not be available as persistent hit");
      Http_Client.Cache.Persistent.Close (Store);

      Ada.Text_IO.Create
        (F,
         Ada.Text_IO.Out_File,
         Ada.Directories.Compose (Dir, "corrupt.meta"));
      Ada.Text_IO.Put_Line (F, "HCPCACHE 999");
      Ada.Text_IO.Close (F);
      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "corrupt persistent entry should be skipped without failing open");
      Assert
        (Http_Client.Cache.Persistent.Entry_Count (Store) = 0,
         "corrupt persistent entry should not be loaded");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_No_Store_And_Corrupt_Skip;

   procedure Test_Persistent_Cache_Vary_Survives_Reopen

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir        : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_c");
      Store      : Http_Client.Cache.Persistent.Persistent_Store;
      Config     : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Headers_En : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Headers_Da : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Req_En     : Http_Client.Requests.Request;
      Req_Da     : Http_Client.Requests.Request;
      Res        : Http_Client.Responses.Response;
      Hit        : Http_Client.Responses.Response;
      Meta       : Http_Client.Cache.Cache_Metadata;
      T0         : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status     : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Status := Http_Client.Headers.Add (Headers_En, "Accept-Language", "en");
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary test request header should be accepted");
      Status := Http_Client.Headers.Add (Headers_Da, "Accept-Language", "da");
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary mismatch request header should be accepted");
      Build_Cache_Request ("http://example.com/vary", Req_En, Headers_En);
      Build_Cache_Request ("http://example.com/vary", Req_Da, Headers_Da);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 2"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "en",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent vary test cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req_En, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok, "persistent vary entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent vary test cache should reopen");
      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_En, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent vary hit should survive reopen with matching request header");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "en",
         "persistent vary hit should preserve selected variant body");
      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_Da, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "persistent vary mismatch must not cross-serve after reopen");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Vary_Survives_Reopen;

   procedure Test_Persistent_Cache_Stored_Time_Survives_Reopen

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_e");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/short-lived", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=10"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""short"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 5"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "short",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "stored-time persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "short-lived persistent entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "stored-time persistent cache should reopen");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 20.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "persistent reload must preserve original stored time and stale deadline");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "short",
         "stale persistent hit should still expose cached body for revalidation");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Stored_Time_Survives_Reopen;

   procedure Test_Persistent_Cache_Update_From_304_Rewrites_Disk

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir          : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_f");
      Store        : Http_Client.Cache.Persistent.Persistent_Store;
      Config       : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req          : Http_Client.Requests.Request;
      Res          : Http_Client.Responses.Response;
      Not_Modified : Http_Client.Responses.Response;
      Hit          : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      T0           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status       : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/revalidate", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=0"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""rv1"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 9"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "old-body!",
         Res);
      Build_Cache_Response
        ("HTTP/1.1 304 Not Modified"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""rv1"""
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF,
         Not_Modified);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok, "304 persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "stale persistent entry should store");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Entry_Stale,
         "entry should be stale before 304 update");
      Status :=
        Http_Client.Cache.Persistent.Update_From_304
          (Store, Req, Not_Modified, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent 304 update should succeed");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "304-updated persistent cache should reopen");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 10.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "304-updated persistent entry should be fresh after reopen");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "old-body!",
         "304 update should preserve cached body on disk");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Update_From_304_Rewrites_Disk;

   procedure Test_Persistent_Cache_Remove_Expired_Persists

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_h");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/remove-expired", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=1"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 7"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "expired",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "remove-expired persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "short persistent entry should store before removal");
      Status := Http_Client.Cache.Persistent.Remove_Expired (Store, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "remove-expired should complete deterministically");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "expired persistent entry should be removed from memory front");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "remove-expired cache should reopen after maintenance");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "expired persistent entry should stay removed after reopen");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 0,
         "remove-expired should delete durable metadata");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Remove_Expired_Persists;

   procedure Test_Persistent_Cache_Invalidate_Removes_Durable_Entry

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_i");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/invalidate", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "old",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent invalidate cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent invalidate entry should store");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 1,
         "persistent invalidate setup should publish metadata");

      Http_Client.Cache.Persistent.Invalidate (Store, Req);
      Assert
        (Http_Client.Cache.Persistent.Entry_Count (Store) = 0,
         "persistent invalidate should reset disk stats");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "invalidated persistent entry should miss before reopen");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "persistent invalidate cache should reopen");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "invalidated persistent entry should not survive reopen");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 0,
         "persistent invalidate should remove durable metadata");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Invalidate_Removes_Durable_Entry;

   procedure Test_Persistent_Cache_Open_Removes_Safe_Corrupt_Metadata

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_j");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      F      : Ada.Text_IO.File_Type;
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Ada.Directories.Create_Path (Dir);
      Ada.Text_IO.Create
        (F,
         Ada.Text_IO.Out_File,
         Ada.Directories.Compose (Dir, "0000000000000001.meta"));
      Ada.Text_IO.Put_Line (F, "HCPCACHE 999");
      Ada.Text_IO.Close (F);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "safe corrupt metadata should not fail persistent open");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 0,
         "safe corrupt metadata should be removed during open cleanup");
      Assert
        (Http_Client.Cache.Persistent.Entry_Count (Store) = 0,
         "safe corrupt metadata should not affect entry count");
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Open_Removes_Safe_Corrupt_Metadata;

   procedure Test_Persistent_Cache_Restores_Staged_Metadata

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir       : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_k");
      Store     : Http_Client.Cache.Persistent.Persistent_Store;
      Config    : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Req       : Http_Client.Requests.Request;
      Res       : Http_Client.Responses.Response;
      Hit       : Http_Client.Responses.Response;
      Meta      : Http_Client.Cache.Cache_Metadata;
      T0        : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status    : Http_Client.Errors.Result_Status;
      Meta_Name : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/staged-restore", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 8"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "restored",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "staged-restore persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok, "staged-restore entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Meta_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (First_Test_File (Dir, "*.meta"));
      Assert
        (Ada.Strings.Unbounded.Length (Meta_Name) > 0,
         "staged-restore setup should publish metadata");
      Ada.Directories.Rename
        (Ada.Directories.Compose
           (Dir, Ada.Strings.Unbounded.To_String (Meta_Name)),
         Ada.Directories.Compose
           (Dir, Ada.Strings.Unbounded.To_String (Meta_Name) & ".2.tmp"));

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "staged metadata recovery should not fail persistent open");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "staged old metadata should be restored as a valid persistent hit");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "restored",
         "staged metadata recovery should preserve the old cached body");
      Assert
        (Count_Test_Files (Dir, "*.meta.2.tmp") = 0,
         "staged metadata recovery should not leave backup metadata files active");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Restores_Staged_Metadata;

   procedure Test_Persistent_Cache_Vary_Miss_Does_Not_Read_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir        : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_l");
      Store      : Http_Client.Cache.Persistent.Persistent_Store;
      Config     : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      Headers_En : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Headers_Da : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Req_En     : Http_Client.Requests.Request;
      Req_Da     : Http_Client.Requests.Request;
      Res        : Http_Client.Responses.Response;
      Hit        : Http_Client.Responses.Response;
      Meta       : Http_Client.Cache.Cache_Metadata;
      T0         : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status     : Http_Client.Errors.Result_Status;
      Body_File  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Remove_Test_Directory (Dir);
      Status := Http_Client.Headers.Add (Headers_En, "Accept-Language", "en");
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary prefilter setup should accept matching header");
      Status := Http_Client.Headers.Add (Headers_Da, "Accept-Language", "da");
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary prefilter setup should accept mismatching header");
      Build_Cache_Request
        ("http://example.com/vary-prefilter", Req_En, Headers_En);
      Build_Cache_Request
        ("http://example.com/vary-prefilter", Req_Da, Headers_Da);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Vary: Accept-Language"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 2"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "en",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary prefilter persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req_En, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok, "vary prefilter entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "vary prefilter persistent cache should reopen");
      Body_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (First_Test_File (Dir, "*.body"));
      Assert
        (Ada.Strings.Unbounded.Length (Body_File) > 0,
         "vary prefilter setup should have a body file");
      Ada.Directories.Delete_File
        (Ada.Directories.Compose
           (Dir, Ada.Strings.Unbounded.To_String (Body_File)));

      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_Da, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "vary mismatch should be decided from metadata without reading the missing body");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 1,
         "vary mismatch should not delete metadata for an otherwise valid different variant");

      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_En, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "matching variant with a missing body should be rejected as a miss");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 0,
         "matching corrupt body should remove the unusable metadata deterministically");

      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Vary_Miss_Does_Not_Read_Body;

   procedure Test_Persistent_Cache_Method_Miss_Does_Not_Read_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir       : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_persistent_cache_m");
      Store     : Http_Client.Cache.Persistent.Persistent_Store;
      Config    : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir, Create_If_Missing => True);
      URI       : Http_Client.URI.URI_Reference;
      Req_Get   : Http_Client.Requests.Request;
      Req_Head  : Http_Client.Requests.Request;
      Res       : Http_Client.Responses.Response;
      Hit       : Http_Client.Responses.Response;
      Meta      : Http_Client.Cache.Cache_Metadata;
      T0        : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 13, 0.0);
      Status    : Http_Client.Errors.Result_Status;
      Body_File : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Remove_Test_Directory (Dir);
      Status :=
        Http_Client.URI.Parse ("http://example.com/method-prefilter", URI);
      Assert
        (Status = Http_Client.Errors.Ok, "method prefilter URI should parse");
      Status :=
        Http_Client.Requests.Create
          (Method => Http_Client.Types.GET, URI => URI, Item => Req_Get);
      Assert
        (Status = Http_Client.Errors.Ok, "method prefilter GET should build");
      Status :=
        Http_Client.Requests.Create
          (Method => Http_Client.Types.HEAD, URI => URI, Item => Req_Head);
      Assert
        (Status = Http_Client.Errors.Ok, "method prefilter HEAD should build");
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 3"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "get",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "method prefilter persistent cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req_Get, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "method prefilter entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "method prefilter persistent cache should reopen");
      Body_File :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (First_Test_File (Dir, "*.body"));
      Assert
        (Ada.Strings.Unbounded.Length (Body_File) > 0,
         "method prefilter setup should have a body file");
      Ada.Directories.Delete_File
        (Ada.Directories.Compose
           (Dir, Ada.Strings.Unbounded.To_String (Body_File)));

      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_Head, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "method mismatch should be decided from metadata without reading the missing body");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 1,
         "method mismatch should not delete metadata for a different request method");

      Status :=
        Http_Client.Cache.Persistent.Lookup
          (Store, Req_Get, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "matching method with a missing body should be rejected as a miss");
      Assert
        (Count_Test_Files (Dir, "*.meta") = 0,
         "matching method corrupt body should remove unusable metadata deterministically");

      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Persistent_Cache_Method_Miss_Does_Not_Read_Body;

   procedure Test_Crypto_AES_GCM_Round_Trip_And_Tamper

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Key     : constant String := Test_Raw_Key;
      Nonce   : Ada.Strings.Unbounded.Unbounded_String;
      Cipher  : Ada.Strings.Unbounded.Unbounded_String;
      Tag     : Ada.Strings.Unbounded.Unbounded_String;
      Plain   : Ada.Strings.Unbounded.Unbounded_String;
      Status  : Http_Client.Errors.Result_Status;
      Bad_Tag : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Status :=
        Http_Client.Crypto.Random_Bytes
          (Http_Client.Crypto.AES_256_GCM_Nonce_Length, Nonce);
      Assert
        (Status = Http_Client.Errors.Ok,
         "crypto random nonce generation should succeed");
      Status :=
        Http_Client.Crypto.AES_256_GCM_Encrypt
          (Key,
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:a",
           "secret-payload",
           Cipher,
           Tag);
      Assert
        (Status = Http_Client.Errors.Ok,
         "AES-256-GCM encryption should accept a 32-byte raw key");
      Status :=
        Http_Client.Crypto.AES_256_GCM_Decrypt
          (Key,
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:a",
           Ada.Strings.Unbounded.To_String (Cipher),
           Ada.Strings.Unbounded.To_String (Tag),
           Plain);
      Assert
        (Status = Http_Client.Errors.Ok,
         "AES-256-GCM decryption should authenticate correct associated data");
      Assert
        (Ada.Strings.Unbounded.To_String (Plain) = "secret-payload",
         "decrypted plaintext should round-trip exactly");
      Bad_Tag := Tag;
      Ada.Strings.Unbounded.Replace_Element
        (Bad_Tag,
         1,
         Character'Val
           ((Character'Pos (Ada.Strings.Unbounded.Element (Bad_Tag, 1)) + 1)
            mod 256));
      Status :=
        Http_Client.Crypto.AES_256_GCM_Decrypt
          (Key,
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:a",
           Ada.Strings.Unbounded.To_String (Cipher),
           Ada.Strings.Unbounded.To_String (Bad_Tag),
           Plain);
      Assert
        (Status = Http_Client.Errors.Cache_Authentication_Failed,
         "tag corruption must be detected deterministically");

      Status :=
        Http_Client.Crypto.AES_256_GCM_Encrypt
          (Key,
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:empty",
           "",
           Cipher,
           Tag);
      Assert
        (Status = Http_Client.Errors.Ok,
         "AES-256-GCM should support empty cache metadata/body payloads");
      Assert
        (Ada.Strings.Unbounded.Length (Cipher) = 0,
         "empty plaintext should produce empty GCM ciphertext plus authentication tag");
      Status :=
        Http_Client.Crypto.AES_256_GCM_Decrypt
          (Key,
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:empty",
           Ada.Strings.Unbounded.To_String (Cipher),
           Ada.Strings.Unbounded.To_String (Tag),
           Plain);
      Assert
        (Status = Http_Client.Errors.Ok,
         "AES-256-GCM should authenticate empty ciphertext");
      Assert
        (Ada.Strings.Unbounded.Length (Plain) = 0,
         "empty encrypted payload should round-trip as empty plaintext");

      Status := Http_Client.Crypto.Random_Bytes (0, Nonce);
      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "zero-length random byte requests should be rejected without raising");

      Status :=
        Http_Client.Crypto.AES_256_GCM_Encrypt
          ("short-key",
           Ada.Strings.Unbounded.To_String (Nonce),
           "cache-entry:a",
           "x",
           Cipher,
           Tag);
      Assert
        (Status = Http_Client.Errors.Cache_Key_Invalid,
         "raw AES-256-GCM keys must be exactly 32 bytes");
   end Test_Crypto_AES_GCM_Round_Trip_And_Tamper;

   procedure Test_Crypto_PBKDF2_Validation_And_Determinism

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Key_A  : Ada.Strings.Unbounded.Unbounded_String;
      Key_B  : Ada.Strings.Unbounded.Unbounded_String;
      Key_C  : Ada.Strings.Unbounded.Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Crypto.PBKDF2_HMAC_SHA256
          ("cache-password", "1234567890abcdef", 10_000, Key_A);
      Assert
        (Status = Http_Client.Errors.Ok,
         "PBKDF2 should accept documented minimum iterations and 16-byte salt");
      Assert
        (Ada.Strings.Unbounded.Length (Key_A)
         = Http_Client.Crypto.AES_256_GCM_Key_Length,
         "PBKDF2 should derive a 32-byte AES-256 key");

      Status :=
        Http_Client.Crypto.PBKDF2_HMAC_SHA256
          ("cache-password", "1234567890abcdef", 10_000, Key_B);
      Assert
        (Status = Http_Client.Errors.Ok,
         "PBKDF2 repeated derivation with fixed parameters should succeed");
      Assert
        (Ada.Strings.Unbounded.To_String (Key_A)
         = Ada.Strings.Unbounded.To_String (Key_B),
         "PBKDF2 should be deterministic for identical password, salt, and iteration parameters");

      Status :=
        Http_Client.Crypto.PBKDF2_HMAC_SHA256
          ("cache-password", "abcdef1234567890", 10_000, Key_C);
      Assert
        (Status = Http_Client.Errors.Ok,
         "PBKDF2 should accept a different valid salt");
      Assert
        (Ada.Strings.Unbounded.To_String (Key_A)
         /= Ada.Strings.Unbounded.To_String (Key_C),
         "PBKDF2 should produce different keys for different salts");

      Status :=
        Http_Client.Crypto.PBKDF2_HMAC_SHA256
          ("cache-password", "1234567890abcdef", 9_999, Key_C);
      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "PBKDF2 should reject iteration counts below the documented minimum");

      Status :=
        Http_Client.Crypto.PBKDF2_HMAC_SHA256
          ("", "1234567890abcdef", 10_000, Key_C);
      Assert
        (Status = Http_Client.Errors.Invalid_Configuration,
         "PBKDF2 should reject empty passwords");
   end Test_Crypto_PBKDF2_Validation_And_Determinism;

   procedure Test_Encrypted_Persistent_Cache_Reopen_And_Confidentiality

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir    : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_encrypted_cache_a");
      Store  : Http_Client.Cache.Persistent.Persistent_Store;
      Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir,
           Create_If_Missing  => True,
           Encrypt_At_Rest    => True,
           Raw_Encryption_Key => Test_Raw_Key);
      Req    : Http_Client.Requests.Request;
      Res    : Http_Client.Responses.Response;
      Hit    : Http_Client.Responses.Response;
      Meta   : Http_Client.Cache.Cache_Metadata;
      T0     : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 14, 0.0);
      Status : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request
        ("http://example.com/private-cache?token=VISIBLE", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""enc-v1"""
         & ASCII.CR
         & ASCII.LF
         & "X-Secret-Marker: hidden-header-value"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 18"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "hidden-body-marker",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent cache should open with explicit raw key");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent cache should store cacheable response");
      Http_Client.Cache.Persistent.Close (Store);

      Assert
        (Count_Test_Files (Dir, "*.meta") = 1,
         "encrypted cache should still use opaque metadata file names");
      Assert
        (Any_Cache_File_Contains (Dir, "HCPCACHE-ENC 1"),
         "encrypted files should carry the encrypted envelope marker");
      Assert
        (not Any_Cache_File_Contains (Dir, "VISIBLE"),
         "encrypted cache files must not expose raw query strings");
      Assert
        (not Any_Cache_File_Contains (Dir, "hidden-header-value"),
         "encrypted cache files must not expose response header values");
      Assert
        (not Any_Cache_File_Contains (Dir, "hidden-body-marker"),
         "encrypted cache files must not expose response bodies");

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent cache should reopen with the same key");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 1.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent cache should serve fresh hit after reopen");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "hidden-body-marker",
         "encrypted persistent hit should decrypt body bytes exactly");

      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "ETag: ""enc-v2"""
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 7"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body-v2",
         Res);
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res, T0 + 2.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent replacement store should publish a new encrypted body");
      Http_Client.Cache.Persistent.Close (Store);
      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent cache should reopen after replacement store");
      Status :=
        Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta, T0 + 3.0);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted persistent replacement should be a fresh hit after restart");
      Assert
        (Http_Client.Responses.Response_Body (Hit) = "body-v2",
         "encrypted persistent replacement should not keep the old body file");
      Assert
        (not Any_Cache_File_Contains (Dir, "body-v2"),
         "encrypted replacement body must not appear as cleartext on disk");

      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Encrypted_Persistent_Cache_Reopen_And_Confidentiality;

   procedure Test_Encrypted_Persistent_Cache_Key_And_Tamper_Failures

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Dir          : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Current_Directory,
           "tmp_http_client_encrypted_cache_b");
      Store        : Http_Client.Cache.Persistent.Persistent_Store;
      Config       : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir,
           Create_If_Missing  => True,
           Encrypt_At_Rest    => True,
           Raw_Encryption_Key => Test_Raw_Key);
      Bad_Config   : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir,
           Create_If_Missing  => True,
           Encrypt_At_Rest    => True,
           Raw_Encryption_Key => "abcdefghijklmnopqrstuvwxyzabcdef");
      Short_Config : Http_Client.Cache.Persistent.Persistent_Config :=
        Http_Client.Cache.Persistent.Make_Config
          (Dir,
           Create_If_Missing  => True,
           Encrypt_At_Rest    => True,
           Raw_Encryption_Key => "short");
      Req          : Http_Client.Requests.Request;
      Res          : Http_Client.Responses.Response;
      Hit          : Http_Client.Responses.Response;
      Meta         : Http_Client.Cache.Cache_Metadata;
      Meta_Name    : Ada.Strings.Unbounded.Unbounded_String;
      F            : Ada.Streams.Stream_IO.File_Type;
      Status       : Http_Client.Errors.Result_Status;
   begin
      Remove_Test_Directory (Dir);
      Build_Cache_Request ("http://example.com/encrypted-wrong-key", Req);
      Build_Cache_Response
        ("HTTP/1.1 200 OK"
         & ASCII.CR
         & ASCII.LF
         & "Cache-Control: max-age=600"
         & ASCII.CR
         & ASCII.LF
         & "Content-Length: 4"
         & ASCII.CR
         & ASCII.LF
         & ASCII.CR
         & ASCII.LF
         & "body",
         Res);

      Status := Http_Client.Cache.Persistent.Open (Store, Short_Config);
      Assert
        (Status = Http_Client.Errors.Cache_Key_Invalid,
         "encrypted persistent cache should reject malformed raw keys on open");

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted wrong-key setup cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted wrong-key setup entry should store");
      Http_Client.Cache.Persistent.Close (Store);

      Status := Http_Client.Cache.Persistent.Open (Store, Bad_Config);
      Assert
        (Status = Http_Client.Errors.Cache_Wrong_Key,
         "wrong key should fail encrypted store open through the store verifier");
      Http_Client.Cache.Persistent.Close (Store);

      declare
         Plain_Config : Http_Client.Cache.Persistent.Persistent_Config :=
           Http_Client.Cache.Persistent.Make_Config
             (Dir, Create_If_Missing => False);
      begin
         Status := Http_Client.Cache.Persistent.Open (Store, Plain_Config);
         Assert
           (Status = Http_Client.Errors.Cache_Format_Unsupported,
            "opening an encrypted persistent store as plaintext should fail deterministically");
         Http_Client.Cache.Persistent.Close (Store);
      end;

      Remove_Test_Directory (Dir);

      Remove_Test_Directory (Dir);
      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted tamper setup cache should open");
      Status := Http_Client.Cache.Persistent.Store (Store, Req, Res);
      Assert
        (Status = Http_Client.Errors.Ok,
         "encrypted tamper setup entry should store");
      Http_Client.Cache.Persistent.Close (Store);
      Meta_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String
          (First_Test_File (Dir, "*.meta"));
      Ada.Streams.Stream_IO.Open
        (F,
         Ada.Streams.Stream_IO.Append_File,
         Ada.Directories.Compose
           (Dir, Ada.Strings.Unbounded.To_String (Meta_Name)));
      declare
         Junk : constant Ada.Streams.Stream_Element_Array (1 .. 1) :=
           [1 => 16#41#];
      begin
         Ada.Streams.Stream_IO.Write (F, Junk);
      end;
      Ada.Streams.Stream_IO.Close (F);

      Status := Http_Client.Cache.Persistent.Open (Store, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "tampered encrypted cache should not fail the whole store open");
      Status := Http_Client.Cache.Persistent.Lookup (Store, Req, Hit, Meta);
      Assert
        (Status = Http_Client.Errors.Cache_Miss,
         "tampered encrypted entry must not be served");
      Http_Client.Cache.Persistent.Clear (Store);
      Http_Client.Cache.Persistent.Close (Store);
      Remove_Test_Directory (Dir);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         Http_Client.Cache.Persistent.Close (Store);
         Remove_Test_Directory (Dir);
         raise;
   end Test_Encrypted_Persistent_Cache_Key_And_Tamper_Failures;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Persistent_Cache");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Persistent_Cache_Open_Store_Reopen'Access,
         "Test_Persistent_Cache_Open_Store_Reopen");
      Register_Routine
        (T,
         Test_Persistent_Cache_No_Store_And_Corrupt_Skip'Access,
         "Test_Persistent_Cache_No_Store_And_Corrupt_Skip");
      Register_Routine
        (T,
         Test_Persistent_Cache_Vary_Survives_Reopen'Access,
         "Test_Persistent_Cache_Vary_Survives_Reopen");
      Register_Routine
        (T,
         Test_Persistent_Cache_Stored_Time_Survives_Reopen'Access,
         "Test_Persistent_Cache_Stored_Time_Survives_Reopen");
      Register_Routine
        (T,
         Test_Persistent_Cache_Update_From_304_Rewrites_Disk'Access,
         "Test_Persistent_Cache_Update_From_304_Rewrites_Disk");
      Register_Routine
        (T,
         Test_Persistent_Cache_Remove_Expired_Persists'Access,
         "Test_Persistent_Cache_Remove_Expired_Persists");
      Register_Routine
        (T,
         Test_Persistent_Cache_Invalidate_Removes_Durable_Entry'Access,
         "Test_Persistent_Cache_Invalidate_Removes_Durable_Entry");
      Register_Routine
        (T,
         Test_Persistent_Cache_Open_Removes_Safe_Corrupt_Metadata'Access,
         "Test_Persistent_Cache_Open_Removes_Safe_Corrupt_Metadata");
      Register_Routine
        (T,
         Test_Persistent_Cache_Restores_Staged_Metadata'Access,
         "Test_Persistent_Cache_Restores_Staged_Metadata");
      Register_Routine
        (T,
         Test_Persistent_Cache_Vary_Miss_Does_Not_Read_Body'Access,
         "Test_Persistent_Cache_Vary_Miss_Does_Not_Read_Body");
      Register_Routine
        (T,
         Test_Persistent_Cache_Method_Miss_Does_Not_Read_Body'Access,
         "Test_Persistent_Cache_Method_Miss_Does_Not_Read_Body");
      Register_Routine
        (T,
         Test_Crypto_AES_GCM_Round_Trip_And_Tamper'Access,
         "Test_Crypto_AES_GCM_Round_Trip_And_Tamper");
      Register_Routine
        (T,
         Test_Crypto_PBKDF2_Validation_And_Determinism'Access,
         "Test_Crypto_PBKDF2_Validation_And_Determinism");
      Register_Routine
        (T,
         Test_Encrypted_Persistent_Cache_Reopen_And_Confidentiality'Access,
         "Test_Encrypted_Persistent_Cache_Reopen_And_Confidentiality");
      Register_Routine
        (T,
         Test_Encrypted_Persistent_Cache_Key_And_Tamper_Failures'Access,
         "Test_Encrypted_Persistent_Cache_Key_And_Tamper_Failures");
   end Register_Tests;

end Http_Client.Cache.Persistent.Tests;
