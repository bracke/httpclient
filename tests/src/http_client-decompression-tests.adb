with Ada.Calendar;
with Ada.Directories;       use Ada.Directories;
with Ada.Streams;           use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with GNAT.Sockets;

with AUnit.Assertions;

with Http_Client.Clients;
with Http_Client.Diagnostics;
with Http_Client.DNS_SVCB;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;
with Http_Client.Zlib_Decompression;

package body Http_Client.Decompression.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;

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

   procedure Test_Decompression_Identity_Gzip_Deflate

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      Gzip_Body    : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (227)
        & Character'Val (61)
        & Character'Val (4)
        & Character'Val (106)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (207)
        & Character'Val (45)
        & Character'Val (40)
        & Character'Val (74)
        & Character'Val (45)
        & Character'Val (46)
        & Character'Val (78)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (148)
        & Character'Val (158)
        & Character'Val (94)
        & Character'Val (158)
        & Character'Val (18)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);
      Deflate_Body : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (203)
        & Character'Val (73)
        & Character'Val (44)
        & Character'Val (73)
        & Character'Val (5)
        & Character'Val (0)
        & Character'Val (35)
        & Character'Val (12)
        & Character'Val (5)
        & Character'Val (10);
      Decoded      : Unbounded_String;
      Options      : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
   begin
      Assert
        (Http_Client.Decompression.Supported_Accept_Encoding = "gzip, deflate",
         "supported Accept-Encoding should advertise exactly implemented encodings");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "plain",
            Encoding     => "identity",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "identity content encoding should decode successfully");
      Assert
        (To_String (Decoded) = "plain",
         "identity content encoding should preserve body bytes");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Gzip_Body,
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "valid gzip content should decode successfully");
      Assert
        (To_String (Decoded) = "hello decompressed",
         "gzip content should produce decoded payload");

      Options.Maximum_Decoded_Body_Size := 18;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Gzip_Body,
            Encoding     => "gzip",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Ok,
         "gzip decoded body exactly equal to limit should succeed");
      Assert
        (To_String (Decoded) = "hello decompressed",
         "exact-limit gzip decoded body should remain intact");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "zlib-wrapped deflate content should decode successfully");
      Assert
        (To_String (Decoded) = "hello deflate",
         "deflate content should produce decoded payload");
   end Test_Decompression_Identity_Gzip_Deflate;

   procedure Test_Decompression_Errors_And_Decoded_View

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF     : constant String := Character'Val (13) & Character'Val (10);
      Response : Http_Client.Responses.Response;
      View     : Http_Client.Decompression.Decoded_Response;
      Decoded  : Unbounded_String;
      Options  : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
   begin
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "not gzip",
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "malformed gzip data should fail deterministically");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "",
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "empty gzip data should fail as decompression failure, not internal error");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "abc", Encoding => "br", Decoded_Body => Decoded)
         = Http_Client.Errors.Unsupported_Content_Encoding,
         "unsupported encoding should be rejected by default");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "abc",
            Encoding     => "gzip, deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Unsupported_Content_Encoding,
         "stacked content encoding should be rejected unless explicitly supported");

      Options.Maximum_Decoded_Body_Size := 2;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "abc",
            Encoding     => "identity",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Decoded_Body_Too_Large,
         "decoded size limit should apply to identity bodies too");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: identity"
            & CRLF
            & "Content-Length: 3"
            & CRLF
            & CRLF
            & "abc",
            Response)
         = Http_Client.Errors.Ok,
         "response with identity encoding should parse");
      Assert
        (Http_Client.Decompression.Decode_Response
           (Response => Response, Result => View)
         = Http_Client.Errors.Ok,
         "decoded response view should be constructed");
      Assert
        (not Http_Client.Decompression.Decoded (View),
         "identity decoded view should not report transformation");
      Assert
        (Http_Client.Decompression.Decoded_Body (View) = "abc",
         "identity decoded view should expose body bytes");
      Assert
        (Http_Client.Decompression.Encoded_Body (View) = "abc",
         "decoded view should expose original encoded body explicitly");
      Assert
        (Http_Client.Headers.Contains
           (Http_Client.Responses.Headers
              (Http_Client.Decompression.Original_Response (View)),
            "Content-Encoding"),
         "decoded view should preserve original response headers");
   end Test_Decompression_Errors_And_Decoded_View;

   procedure Test_Decompression_Additional_Edges

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF         : constant String :=
        Character'Val (13) & Character'Val (10);
      Empty_Gzip   : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (3)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);
      Corrupt_Gzip : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (3)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (1);
      Truncated_Gzip : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (207)
        & Character'Val (45)
        & Character'Val (40)
        & Character'Val (74)
        & Character'Val (45)
        & Character'Val (46)
        & Character'Val (78)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (148)
        & Character'Val (158)
        & Character'Val (94)
        & Character'Val (158);
      Truncated_Deflate : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (203)
        & Character'Val (73)
        & Character'Val (44)
        & Character'Val (73)
        & Character'Val (5)
        & Character'Val (0)
        & Character'Val (35)
        & Character'Val (12);
      Bad_Adler_Deflate : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (203)
        & Character'Val (73)
        & Character'Val (44)
        & Character'Val (73)
        & Character'Val (5)
        & Character'Val (0)
        & Character'Val (35)
        & Character'Val (12)
        & Character'Val (5)
        & Character'Val (11);
      Binary_Expected : constant String :=
        Character'Val (0)
        & Character'Val (1)
        & Character'Val (127)
        & Character'Val (128)
        & Character'Val (255)
        & Character'Val (10)
        & Character'Val (13)
        & "A";
      Binary_Gzip : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (99)
        & Character'Val (96)
        & Character'Val (172)
        & Character'Val (111)
        & Character'Val (248)
        & Character'Val (207)
        & Character'Val (197)
        & Character'Val (235)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (55)
        & Character'Val (87)
        & Character'Val (32)
        & Character'Val (239)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);
      Binary_Deflate : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (99)
        & Character'Val (96)
        & Character'Val (172)
        & Character'Val (111)
        & Character'Val (248)
        & Character'Val (207)
        & Character'Val (197)
        & Character'Val (235)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (9)
        & Character'Val (254)
        & Character'Val (2)
        & Character'Val (88);
      Response     : Http_Client.Responses.Response;
      View         : Http_Client.Decompression.Decoded_Response;
      Decoded      : Unbounded_String;
      Options      : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
   begin
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Empty_Gzip,
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "valid empty gzip stream should decode successfully");
      Assert
        (Length (Decoded) = 0,
         "valid empty gzip stream should produce empty decoded body");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Corrupt_Gzip,
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "gzip checksum corruption should fail deterministically");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Truncated_Gzip,
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "truncated gzip body should fail deterministically");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Truncated_Deflate,
            Encoding     => "deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "truncated zlib-wrapped deflate body should fail deterministically");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Bad_Adler_Deflate,
            Encoding     => "deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "bad zlib Adler checksum should fail deterministically");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Binary_Gzip,
            Encoding     => "gzip",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "gzip binary payload should decode successfully");
      Assert
        (To_String (Decoded) = Binary_Expected,
         "gzip binary payload should preserve NUL and high-bit bytes");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Binary_Deflate,
            Encoding     => "deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Ok,
         "deflate binary payload should decode successfully");
      Assert
        (To_String (Decoded) = Binary_Expected,
         "deflate binary payload should preserve NUL and high-bit bytes");

      Options.Unsupported_Policy := Http_Client.Decompression.Leave_Encoded;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "encoded",
            Encoding     => "br",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Ok,
         "leave-encoded policy should permit unsupported encodings");
      Assert
        (To_String (Decoded) = "encoded",
         "leave-encoded policy should return original bytes");

      Options.Maximum_Decoded_Body_Size := 3;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => "encoded",
            Encoding     => "br",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Decoded_Body_Too_Large,
         "leave-encoded policy should still bound the returned body bytes");
      Options.Maximum_Decoded_Body_Size :=
        Http_Client
          .Decompression
          .Default_Decompression_Options
          .Maximum_Decoded_Body_Size;
      Options.Unsupported_Policy :=
        Http_Client.Decompression.Reject_Unsupported;

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body =>
              Character'Val (75)
              & Character'Val (203)
              & Character'Val (204)
              & Character'Val (75),
            Encoding     => "deflate",
            Decoded_Body => Decoded)
         = Http_Client.Errors.Decompression_Failed,
         "raw deflate without zlib wrapper should be rejected deterministically");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Encoding: deflate"
            & CRLF
            & "Content-Length: 3"
            & CRLF
            & CRLF
            & "abc",
            Response)
         = Http_Client.Errors.Ok,
         "response with duplicate Content-Encoding fields should parse");
      Assert
        (Http_Client.Decompression.Decode_Response
           (Response => Response, Result => View)
         = Http_Client.Errors.Unsupported_Content_Encoding,
         "duplicate Content-Encoding fields should be rejected by decoded view");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 204 No Content"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF,
            Response)
         = Http_Client.Errors.Ok,
         "bodyless response carrying Content-Encoding metadata should parse");
      Assert
        (Http_Client.Decompression.Decode_Response
           (Response => Response, Result => View)
         = Http_Client.Errors.Ok,
         "bodyless response should not invoke decompression");
      Assert
        (not Http_Client.Decompression.Decoded (View),
         "bodyless response should not be marked decoded");

      Assert
        (Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 0"
            & CRLF
            & CRLF,
            Response,
            Context => (Request_Was_HEAD => True))
         = Http_Client.Errors.Ok,
         "HEAD response with Content-Encoding metadata should parse without body");
      Assert
        (Http_Client.Decompression.Decode_Response_With_Context
           (Response => Response, Request_Was_HEAD => True, Result => View)
         = Http_Client.Errors.Ok,
         "HEAD response should not invoke decompression for metadata encoding");
      Assert
        (not Http_Client.Decompression.Decoded (View),
         "HEAD response should not be marked decoded");
   end Test_Decompression_Additional_Edges;

   procedure Test_Client_Decompression_Accept_Encoding_Contracts

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF      : constant String := Character'Val (13) & Character'Val (10);
      Gzip_Body : constant String :=
        Character'Val (31)
        & Character'Val (139)
        & Character'Val (8)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (2)
        & Character'Val (255)
        & Character'Val (75)
        & Character'Val (203)
        & Character'Val (204)
        & Character'Val (75)
        & Character'Val (204)
        & Character'Val (81)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (206)
        & Character'Val (79)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (1)
        & Character'Val (0)
        & Character'Val (134)
        & Character'Val (146)
        & Character'Val (163)
        & Character'Val (236)
        & Character'Val (13)
        & Character'Val (0)
        & Character'Val (0)
        & Character'Val (0);

      task type Gzip_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Gzip_Server;

      task body Gzip_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;

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
         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end;

         Send_Response
           ("HTTP/1.1 200 OK"
            & CRLF
            & "Content-Encoding: gzip"
            & CRLF
            & "Content-Length: 33"
            & CRLF
            & CRLF
            & Gzip_Body);
         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Gzip_Server;

      Raw_Server      : Gzip_Server;
      Decoded_Server  : Gzip_Server;
      Raw_Port        : Http_Client.URI.TCP_Port;
      Decoded_Port    : Http_Client.URI.TCP_Port;
      Raw_URI         : Http_Client.URI.URI_Reference;
      Decoded_URI     : Http_Client.URI.URI_Reference;
      Raw_Request     : Http_Client.Requests.Request;
      Decoded_Request : Http_Client.Requests.Request;
      Decoded_Headers : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Raw_Response    : Http_Client.Responses.Response;
      Decoded_Result  : Http_Client.Decompression.Decoded_Response;
      Raw_Execution   : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Raw_Text        : Unbounded_String;
      Decoded_Text    : Unbounded_String;
      Client          : constant Http_Client.Clients.Client :=
        Http_Client.Clients.Create;
   begin
      Raw_Server.Ready (Raw_Port);
      Raw_Execution.Advertise_Accept_Encoding := True;
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Raw_Port))
         & "/raw-gzip",
         Raw_URI,
         "raw advertised execution URI should parse");
      Assert
        (Http_Client.Requests.Create
           (Method => Http_Client.Types.GET,
            URI    => Raw_URI,
            Item   => Raw_Request)
         = Http_Client.Errors.Ok,
         "raw advertised execution request should construct");

      Assert
        (Http_Client.Clients.Execute
           (Item     => Client,
            Request  => Raw_Request,
            Response => Raw_Response,
            Options  => Raw_Execution)
         = Http_Client.Errors.Ok,
         "raw execution with advertised Accept-Encoding should succeed");
      Assert
        (Http_Client.Responses.Response_Body (Raw_Response) = Gzip_Body,
         "raw execution must preserve encoded gzip bytes even when advertising support");
      Raw_Server.Request_Seen (Raw_Text);
      Assert
        (Index (Raw_Text, "Accept-Encoding: gzip, deflate") > 0,
         "raw execution may advertise supported encodings when explicitly requested");

      Decoded_Server.Ready (Decoded_Port);
      Assert_Parse_Ok
        ("http://127.0.0.1:"
         & Decimal_Image (Natural (Decoded_Port))
         & "/caller-accept-encoding",
         Decoded_URI,
         "decoded caller Accept-Encoding URI should parse");
      Assert
        (Http_Client.Headers.Set
           (Decoded_Headers, "Accept-Encoding", "identity")
         = Http_Client.Errors.Ok,
         "caller supplied Accept-Encoding header should be prepared");
      Assert
        (Http_Client.Requests.Create
           (Method  => Http_Client.Types.GET,
            URI     => Decoded_URI,
            Item    => Decoded_Request,
            Headers => Decoded_Headers)
         = Http_Client.Errors.Ok,
         "decoded caller Accept-Encoding request should construct");

      Assert
        (Http_Client.Clients.Execute_Decoded
           (Item    => Client,
            Request => Decoded_Request,
            Result  => Decoded_Result)
         = Http_Client.Errors.Ok,
         "decoded execution should respect caller Accept-Encoding and still decode supported response encoding");
      Assert
        (Http_Client.Decompression.Decoded_Body (Decoded_Result)
         = "final decoded",
         "decoded execution should decode supported response encoding even when caller supplied the request header");
      Decoded_Server.Request_Seen (Decoded_Text);
      Assert
        (Index (Decoded_Text, "Accept-Encoding: identity") > 0,
         "decoded execution must not overwrite caller supplied Accept-Encoding");
      Assert
        (Index (Decoded_Text, "Accept-Encoding: gzip, deflate") = 0,
         "decoded execution must not append a second library Accept-Encoding header");
   end Test_Client_Decompression_Accept_Encoding_Contracts;

   procedure Test_High_Level_Client_Decompression_Respects_Default_Accept_Encoding

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      CRLF : constant String := Character'Val (13) & Character'Val (10);

      task type Loopback_Server is
         entry Ready (Port : out Http_Client.URI.TCP_Port);
         entry Request_Seen (Text : out Unbounded_String);
      end Loopback_Server;

      task body Loopback_Server is
         Server       : GNAT.Sockets.Socket_Type;
         Peer         : GNAT.Sockets.Socket_Type;
         Server_Addr  : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet);
         Peer_Addr    : GNAT.Sockets.Sock_Addr_Type;
         Request_Text : Unbounded_String;
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

         declare
            Raw  : Stream_Element_Array (1 .. 4096);
            Last : Stream_Element_Offset;
         begin
            GNAT.Sockets.Receive_Socket (Peer, Raw, Last);
            if Last >= Raw'First then
               for Index in Raw'First .. Last loop
                  Append (Request_Text, Character'Val (Raw (Index)));
               end loop;
            end if;
         end;

         declare
            Response : constant String :=
              "HTTP/1.1 200 OK"
              & CRLF
              & "Content-Length: 2"
              & CRLF
              & CRLF
              & "OK";
            Raw      :
              Stream_Element_Array
                (1 .. Stream_Element_Offset (Response'Length));
            Last     : Stream_Element_Offset;
         begin
            for Index in Raw'Range loop
               Raw (Index) :=
                 Stream_Element
                   (Character'Pos
                      (Response
                         (Response'First + Natural (Index - Raw'First))));
            end loop;

            GNAT.Sockets.Send_Socket (Peer, Raw, Last);
         end;

         GNAT.Sockets.Close_Socket (Peer);
         GNAT.Sockets.Close_Socket (Server);

         accept Request_Seen (Text : out Unbounded_String) do
            Text := Request_Text;
         end Request_Seen;
      end Loopback_Server;

      Server        : Loopback_Server;
      Port          : Http_Client.URI.TCP_Port;
      Port_Text     : Unbounded_String;
      Config        : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client        : Http_Client.Clients.Client;
      Result        : Http_Client.Clients.Client_Result;
      Status        : Http_Client.Errors.Result_Status;
      Captured_Text : Unbounded_String;
   begin
      Server.Ready (Port);
      Port_Text := To_Unbounded_String (Decimal_Image (Natural (Port)));

      Config.Enable_Decompression := True;

      Status :=
        Http_Client.Clients.Set_Default_Header
          (Config, "Accept-Encoding", "identity");
      Assert
        (Status = Http_Client.Errors.Ok,
         "Accept-Encoding should remain an allowed caller-configured default header");

      Status := Http_Client.Clients.Initialize (Client, Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "decompression with caller default Accept-Encoding should initialize");

      Status :=
        Http_Client.Clients.Get
          (Client,
           "http://127.0.0.1:" & To_String (Port_Text) & "/identity",
           Result);

      Assert
        (Status = Http_Client.Errors.Ok,
         "high-level identity response should succeed with decompression enabled");

      Server.Request_Seen (Captured_Text);

      Assert
        (Index (Captured_Text, "Accept-Encoding: identity" & CRLF) > 0,
         "caller-configured default Accept-Encoding should be preserved");

      Assert
        (Index (Captured_Text, "Accept-Encoding: gzip, deflate") = 0,
         "decompression advertisement must not overwrite caller default Accept-Encoding");
   end Test_High_Level_Client_Decompression_Respects_Default_Accept_Encoding;

   procedure Test_Decompression_Raw_Deflate_Policy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      Zlib_Deflate_Body : constant String :=
        Character'Val (120)
        & Character'Val (156)
        & Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (203)
        & Character'Val (73)
        & Character'Val (44)
        & Character'Val (73)
        & Character'Val (5)
        & Character'Val (0)
        & Character'Val (35)
        & Character'Val (12)
        & Character'Val (5)
        & Character'Val (10);
      Raw_Deflate_Body : constant String :=
        Character'Val (203)
        & Character'Val (72)
        & Character'Val (205)
        & Character'Val (201)
        & Character'Val (201)
        & Character'Val (87)
        & Character'Val (72)
        & Character'Val (73)
        & Character'Val (77)
        & Character'Val (203)
        & Character'Val (73)
        & Character'Val (44)
        & Character'Val (73)
        & Character'Val (5)
        & Character'Val (0);
      Decoded : Unbounded_String;
      Options : Http_Client.Decompression.Decompression_Options :=
        Http_Client.Decompression.Default_Decompression_Options;
   begin
      Assert
        (Options.Deflate_Mode = Http_Client.Decompression.Zlib_Wrapped_Only,
         "default deflate policy should be zlib-wrapped only");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Raw_Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Decompression_Failed,
         "raw deflate should fail under zlib-wrapped-only policy");

      Options.Deflate_Mode := Http_Client.Decompression.Raw_Only;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Raw_Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Ok,
         "raw deflate should decode under raw-only policy");
      Assert
        (To_String (Decoded) = "hello deflate",
         "raw deflate policy should preserve decoded bytes");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Zlib_Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Decompression_Failed,
         "zlib-wrapped deflate should fail under raw-only policy");

      Options.Deflate_Mode := Http_Client.Decompression.Auto_Zlib_Then_Raw;
      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Zlib_Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Ok,
         "auto deflate policy should accept zlib-wrapped deflate");
      Assert
        (To_String (Decoded) = "hello deflate",
         "auto zlib path should preserve decoded bytes");

      Assert
        (Http_Client.Decompression.Decode_Body
           (Encoded_Body => Raw_Deflate_Body,
            Encoding     => "deflate",
            Decoded_Body => Decoded,
            Options      => Options)
         = Http_Client.Errors.Ok,
         "auto deflate policy should accept raw deflate");
      Assert
        (To_String (Decoded) = "hello deflate",
         "auto raw path should preserve decoded bytes");
   end Test_Decompression_Raw_Deflate_Policy;

   procedure Test_Zlib_Adapter_Header_Predicates

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);

      GZip_Minimal : constant String :=
        Character'Val (16#1F#) & Character'Val (16#8B#)
        & Character'Val (16#08#) & Character'Val (16#00#);
      GZip_Optional_Flags : constant String :=
        Character'Val (16#1F#) & Character'Val (16#8B#)
        & Character'Val (16#08#) & Character'Val (16#1F#);
      GZip_Truncated : constant String :=
        Character'Val (16#1F#) & Character'Val (16#8B#)
        & Character'Val (16#08#);
      GZip_Bad_Method : constant String :=
        Character'Val (16#1F#) & Character'Val (16#8B#)
        & Character'Val (16#00#) & Character'Val (16#00#);
      GZip_Reserved_Flag : constant String :=
        Character'Val (16#1F#) & Character'Val (16#8B#)
        & Character'Val (16#08#) & Character'Val (16#20#);
   begin
      Assert
        (Http_Client.Zlib_Decompression.Looks_Like_Zlib_Header
           (Character'Val (16#78#) & Character'Val (16#9C#)),
         "zlib adapter should recognize a valid zlib header");

      Assert
        (Http_Client.Zlib_Decompression.Looks_Like_GZip_Header
           (GZip_Minimal),
         "gzip adapter should recognize a valid gzip prefix");
      Assert
        (Http_Client.Zlib_Decompression.Looks_Like_GZip_Header
           (GZip_Optional_Flags),
         "gzip adapter should accept optional gzip header flags");
      Assert
        (not Http_Client.Zlib_Decompression.Looks_Like_GZip_Header (""),
         "gzip adapter should reject empty input");
      Assert
        (not Http_Client.Zlib_Decompression.Looks_Like_GZip_Header
           (GZip_Truncated),
         "gzip adapter should reject truncated prefixes");
      Assert
        (not Http_Client.Zlib_Decompression.Looks_Like_GZip_Header
           (GZip_Bad_Method),
         "gzip adapter should reject non-deflate gzip method");
      Assert
        (not Http_Client.Zlib_Decompression.Looks_Like_GZip_Header
           (GZip_Reserved_Flag),
         "gzip adapter should reject reserved gzip flags");
   end Test_Zlib_Adapter_Header_Predicates;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Decompression");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Decompression_Identity_Gzip_Deflate'Access,
         "Test_Decompression_Identity_Gzip_Deflate");
      Register_Routine
        (T,
         Test_Decompression_Errors_And_Decoded_View'Access,
         "Test_Decompression_Errors_And_Decoded_View");
      Register_Routine
        (T,
         Test_Decompression_Additional_Edges'Access,
         "Test_Decompression_Additional_Edges");
      Register_Routine
        (T,
         Test_Decompression_Raw_Deflate_Policy'Access,
         "Test_Decompression_Raw_Deflate_Policy");
      Register_Routine
        (T,
         Test_Zlib_Adapter_Header_Predicates'Access,
         "Test_Zlib_Adapter_Header_Predicates");
      Register_Routine
        (T,
         Test_Client_Decompression_Accept_Encoding_Contracts'Access,
         "Test_Client_Decompression_Accept_Encoding_Contracts");
      Register_Routine
        (T,
         Test_High_Level_Client_Decompression_Respects_Default_Accept_Encoding'Access,
         "Test_High_Level_Client_Decompression_Respects_Default_Accept_Encoding");
   end Register_Tests;

end Http_Client.Decompression.Tests;
