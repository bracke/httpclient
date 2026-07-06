with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Auth;
with Http_Client.Alt_Svc;
with Http_Client.Cache;
with Http_Client.Cache.Persistent;
with Http_Client.Cookies;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTPS_Records;
with Http_Client.HTTP1;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Streams;
with Http_Client.HTTP3;
with Http_Client.HTTP3.Frames;
with Http_Client.HTTP3.Streams;
with Http_Client.QUIC;
with Http_Client.Proxies;
with Http_Client.Protocol_Discovery;
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Multipart.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Request_Bodies.Body_Kind;
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

   procedure Test_Multipart_Boundary_Validation

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Form         : Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Default_Form : Http_Client.Multipart.Multipart_Form;
   begin
      Assert
        (Http_Client.Multipart.Is_Valid_Boundary
           (Http_Client.Multipart.Boundary (Default_Form)),
         "default-initialized multipart form should have a valid boundary");
      Assert
        (Http_Client.Multipart.Is_Valid_Boundary ("abc-XYZ_123.9"),
         "multipart boundary should allow conservative token characters");
      Assert
        (not Http_Client.Multipart.Is_Valid_Boundary (""),
         "multipart boundary should reject empty values");
      Assert
        (not Http_Client.Multipart.Is_Valid_Boundary ("bad boundary"),
         "multipart boundary should reject spaces");
      Assert
        (not Http_Client.Multipart.Is_Valid_Boundary
               ("bad" & Character'Val (13) & "boundary"),
         "multipart boundary should reject CR injection");
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "Aa-_.09")
         = Http_Client.Errors.Ok,
         "valid deterministic boundary should be accepted");
      Assert
        (Http_Client.Multipart.Boundary (Form) = "Aa-_.09",
         "stored deterministic boundary should be returned exactly");
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "bad;boundary")
         = Http_Client.Errors.Invalid_Multipart_Boundary,
         "delimiter-breaking boundary punctuation should be rejected");
   end Test_Multipart_Boundary_Validation;

   procedure Test_Multipart_Exact_Text_Output

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Form      : Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Body_Data : Ada.Strings.Unbounded.Unbounded_String;
      Length    : Natural := 0;
      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Expected  : constant String :=
        "--test-boundary"
        & CRLF
        & "Content-Disposition: form-data; name=""alpha"""
        & CRLF
        & CRLF
        & "one"
        & CRLF
        & "--test-boundary"
        & CRLF
        & "Content-Disposition: form-data; name=""beta"""
        & CRLF
        & CRLF
        & "two"
        & CRLF
        & "--test-boundary--"
        & CRLF;
   begin
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "test-boundary")
         = Http_Client.Errors.Ok,
         "test boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field (Form, "alpha", "one")
         = Http_Client.Errors.Ok,
         "first text field should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field (Form, "beta", "two")
         = Http_Client.Errors.Ok,
         "second text field should be accepted");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Body_Data)
         = Http_Client.Errors.Ok,
         "deterministic multipart body should render");
      Assert
        (Ada.Strings.Unbounded.To_String (Body_Data) = Expected,
         "multipart body should match exact CRLF wire format");
      Assert
        (Http_Client.Multipart.Content_Length (Form, Length)
         = Http_Client.Errors.Ok
         and then Length = Expected'Length,
         "multipart content length should match exact encoded output");
   end Test_Multipart_Exact_Text_Output;

   procedure Test_Multipart_Attach_Request

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Attached : Http_Client.Requests.Request;
      Form     : aliased Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Headers  : Http_Client.Headers.Header_List;
      Wire     : Ada.Strings.Unbounded.Unbounded_String;
      CRLF     : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert_Parse_Ok
        ("http://example.com/upload",
         URI,
         "multipart upload URI should parse");
      Assert
        (Http_Client.Requests.Create (Http_Client.Types.POST, URI, Request)
         = Http_Client.Errors.Ok,
         "multipart base request should be created");
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "attach-boundary")
         = Http_Client.Errors.Ok,
         "attach boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field (Form, "field", "value")
         = Http_Client.Errors.Ok,
         "attach form field should be accepted");
      Assert
        (Http_Client.Multipart.Attach (Form, Request, Attached)
         = Http_Client.Errors.Ok,
         "multipart form should attach to request");

      Headers := Http_Client.Requests.Headers (Attached);
      Assert
        (Http_Client.Headers.Get (Headers, "Content-Type")
         = "multipart/form-data; boundary=attach-boundary",
         "outer Content-Type should include exact multipart boundary");
      Assert
        (Http_Client.Request_Bodies.Kind
           (Http_Client.Requests.Request_Body (Attached))
         = Http_Client.Request_Bodies.Fixed_Length_Stream,
         "attached multipart body should be a fixed-length stream");
      Assert
        (Http_Client.HTTP1.Serialize_Headers (Attached, Wire)
         = Http_Client.Errors.Ok,
         "multipart request headers should serialize");
      Assert
        (Ada.Strings.Unbounded.To_String (Wire)'Length > 0
         and then Http_Client.Headers.Contains (Headers, "Content-Type"),
         "serialized multipart request should retain caller-visible Content-Type");
      declare
         Wire_Text : constant String := Ada.Strings.Unbounded.To_String (Wire);
      begin
         Assert
           (Wire_Text (Wire_Text'Last - 3 .. Wire_Text'Last) = CRLF & CRLF,
            "serialized multipart headers should end at CRLF CRLF");
      end;
   end Test_Multipart_Attach_Request;

   procedure Test_Multipart_Stream_Producer_Incremental_Read

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Form              : aliased Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Body_Data         : Http_Client.Request_Bodies.Request_Body;
      Buffer            : String (1 .. 5);
      Count             : Natural := 0;
      Accumulated       : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Buffered : Ada.Strings.Unbounded.Unbounded_String;
      Status            : Http_Client.Errors.Result_Status;
   begin
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "stream-boundary")
         = Http_Client.Errors.Ok,
         "stream boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_Field (Form, "a", "123456789")
         = Http_Client.Errors.Ok,
         "stream field should be accepted");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Expected_Buffered)
         = Http_Client.Errors.Ok,
         "stream expected body should render for comparison");

      Status := Http_Client.Multipart.To_Request_Body (Form, Body_Data);
      Assert
        (Status = Http_Client.Errors.Ok,
         "checked multipart request-body construction should succeed");
      loop
         Status :=
           Http_Client.Request_Bodies.Read_Next (Body_Data, Buffer, Count);
         Assert
           (Status = Http_Client.Errors.Ok,
            "multipart producer read should succeed");
         exit when Count = 0;
         Ada.Strings.Unbounded.Append
           (Accumulated, Buffer (Buffer'First .. Buffer'First + Count - 1));
      end loop;

      Assert
        (Ada.Strings.Unbounded.To_String (Accumulated)
         = Ada.Strings.Unbounded.To_String (Expected_Buffered),
         "multipart producer should emit the same bytes incrementally");
      Assert
        (Http_Client.Request_Bodies.Reset_Body (Body_Data)
         = Http_Client.Errors.Ok,
         "multipart producer should reset for replay");
      Status :=
        Http_Client.Request_Bodies.Read_Next (Body_Data, Buffer, Count);
      Assert
        (Status = Http_Client.Errors.Ok and then Count > 0,
         "multipart producer should read again after reset");
   end Test_Multipart_Stream_Producer_Incremental_Read;

   procedure Test_Multipart_Empty_Form_And_Content_Type_Conflict

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI       : Http_Client.URI.URI_Reference;
      Request   : Http_Client.Requests.Request;
      Attached  : Http_Client.Requests.Request;
      Form      : aliased Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Body_Data : Ada.Strings.Unbounded.Unbounded_String;
      Length    : Natural := 0;
      CRLF      : constant String := Character'Val (13) & Character'Val (10);
   begin
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "empty-boundary")
         = Http_Client.Errors.Ok,
         "empty-form boundary should be accepted");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Body_Data)
         = Http_Client.Errors.Ok,
         "empty multipart form should render final delimiter only");
      Assert
        (Ada.Strings.Unbounded.To_String (Body_Data)
         = "--empty-boundary--" & CRLF,
         "empty multipart form should emit only the closing delimiter");
      Assert
        (Http_Client.Multipart.Content_Length (Form, Length)
         = Http_Client.Errors.Ok
         and then Length = Ada.Strings.Unbounded.Length (Body_Data),
         "empty multipart length should match exact closing delimiter length");

      Assert_Parse_Ok
        ("http://example.com/upload",
         URI,
         "multipart conflict URI should parse");
      Assert
        (Http_Client.Headers.Set (Headers, "Content-Type", "text/plain")
         = Http_Client.Errors.Ok,
         "test request should accept existing Content-Type");
      Assert
        (Http_Client.Headers.Set (Headers, "Content-Length", "1")
         = Http_Client.Errors.Ok,
         "test request should accept stale Content-Length before attachment");
      Assert
        (Http_Client.Headers.Set (Headers, "Transfer-Encoding", "chunked")
         = Http_Client.Errors.Ok,
         "test request should accept stale Transfer-Encoding before attachment");
      Assert
        (Http_Client.Requests.Create
           (Http_Client.Types.POST, URI, Request, Headers)
         = Http_Client.Errors.Ok,
         "request with existing Content-Type should be created");
      Assert
        (Http_Client.Multipart.Attach (Form, Request, Attached)
         = Http_Client.Errors.Invalid_Header,
         "multipart attach should reject existing Content-Type by default");
      Assert
        (Http_Client.Multipart.Attach
           (Form, Request, Attached, Replace_Content_Type => True)
         = Http_Client.Errors.Ok,
         "multipart attach should replace Content-Type only when requested");
      Assert
        (Http_Client.Headers.Get
           (Http_Client.Requests.Headers (Attached), "Content-Type")
         = "multipart/form-data; boundary=empty-boundary",
         "explicit replacement should install matching multipart Content-Type");
      Assert
        (not Http_Client.Headers.Contains
               (Http_Client.Requests.Headers (Attached), "Content-Length"),
         "multipart attach should remove stale Content-Length");
      Assert
        (not Http_Client.Headers.Contains
               (Http_Client.Requests.Headers (Attached), "Transfer-Encoding"),
         "multipart attach should remove stale Transfer-Encoding");
   end Test_Multipart_Empty_Form_And_Content_Type_Conflict;

   procedure Test_Multipart_File_Part_And_Size_Mismatch

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      procedure Write_File (Path : String; Data : String) is
         File     : Ada.Streams.Stream_IO.File_Type;
         Elements :
           Ada.Streams.Stream_Element_Array
             (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
      begin
         for Offset in 0 .. Data'Length - 1 loop
            Elements (Ada.Streams.Stream_Element_Offset (Offset + 1)) :=
              Ada.Streams.Stream_Element
                (Character'Pos (Data (Data'First + Offset)));
         end loop;

         Ada.Streams.Stream_IO.Create
           (File, Ada.Streams.Stream_IO.Out_File, Path);
         Ada.Streams.Stream_IO.Write (File, Elements);
         Ada.Streams.Stream_IO.Close (File);
      exception
         when others =>
            if Ada.Streams.Stream_IO.Is_Open (File) then
               Ada.Streams.Stream_IO.Close (File);
            end if;
            raise;
      end Write_File;

      Path      : constant String := "multipart_phase19_file_part_test.bin";
      Data      : constant String := "file" & Character'Val (0) & "bytes";
      Form      : aliased Http_Client.Multipart.Multipart_Form :=
        Http_Client.Multipart.Create;
      Rendered  : Ada.Strings.Unbounded.Unbounded_String;
      Body_Data : Http_Client.Request_Bodies.Request_Body;
      Buffer    : String (1 .. 16);
      Count     : Natural := 0;
      Status    : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      CRLF      : constant String := Character'Val (13) & Character'Val (10);
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;

      Write_File (Path, Data);
      Assert
        (Http_Client.Multipart.Set_Boundary (Form, "file-boundary")
         = Http_Client.Errors.Ok,
         "file-part boundary should be accepted");
      Assert
        (Http_Client.Multipart.Add_File
           (Form, "upload", Path, "sample.bin", "application/octet-stream")
         = Http_Client.Errors.Ok,
         "ordinary file part should be accepted and sized");
      Assert
        (Http_Client.Multipart.Is_Replayable (Form),
         "unchanged file-backed multipart form should report replayable");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Rendered)
         = Http_Client.Errors.Ok,
         "file-backed multipart form should render for deterministic verification");
      Assert
        (Ada.Strings.Unbounded.To_String (Rendered)
         = "--file-boundary"
           & CRLF
           & "Content-Disposition: form-data; name=""upload""; filename=""sample.bin"""
           & CRLF
           & "Content-Type: application/octet-stream"
           & CRLF
           & CRLF
           & Data
           & CRLF
           & "--file-boundary--"
           & CRLF,
         "file-backed part should preserve file bytes and generated headers");

      Write_File (Path, Data & "changed");
      Assert
        (not Http_Client.Multipart.Is_Replayable (Form),
         "changed file-backed multipart form should report not replayable");
      Assert
        (Http_Client.Multipart.Render_Body (Form, Rendered)
         = Http_Client.Errors.Body_Length_Mismatch,
         "changed file size should be rejected during buffered rendering");

      Body_Data := Http_Client.Multipart.To_Request_Body (Form);
      Assert
        (Http_Client.Request_Bodies.Reset_Body (Body_Data)
         = Http_Client.Errors.Body_Length_Mismatch,
         "changed file size should be rejected during replay reset");
      loop
         Status :=
           Http_Client.Request_Bodies.Read_Next (Body_Data, Buffer, Count);
         exit when Status /= Http_Client.Errors.Ok or else Count = 0;
      end loop;
      Assert
        (Status = Http_Client.Errors.Body_Length_Mismatch,
         "changed file size should be rejected during streaming production");

      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         if Ada.Directories.Exists (Path) then
            Ada.Directories.Delete_File (Path);
         end if;
         raise;
   end Test_Multipart_File_Part_And_Size_Mismatch;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Multipart");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Multipart_Boundary_Validation'Access,
         "Test_Multipart_Boundary_Validation");
      Register_Routine
        (T,
         Test_Multipart_Exact_Text_Output'Access,
         "Test_Multipart_Exact_Text_Output");
      Register_Routine
        (T,
         Test_Multipart_Attach_Request'Access,
         "Test_Multipart_Attach_Request");
      Register_Routine
        (T,
         Test_Multipart_Stream_Producer_Incremental_Read'Access,
         "Test_Multipart_Stream_Producer_Incremental_Read");
      Register_Routine
        (T,
         Test_Multipart_Empty_Form_And_Content_Type_Conflict'Access,
         "Test_Multipart_Empty_Form_And_Content_Type_Conflict");
      Register_Routine
        (T,
         Test_Multipart_File_Part_And_Size_Mismatch'Access,
         "Test_Multipart_File_Part_And_Size_Mismatch");
   end Register_Tests;

end Http_Client.Multipart.Tests;
