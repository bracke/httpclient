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
with Http_Client.Clients;
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
with Http_Client.Requests;
with Http_Client.Request_Bodies;
with Http_Client.Responses;
with Http_Client.Transports;
with Http_Client.Transports.TCP;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Protocol_Discovery.Tests is

   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Alt_Svc.Alternative_Protocol;
   use type Http_Client.HTTPS_Records.ALPN_ID;
   use type Http_Client.HTTP3.HTTP3_Mode;
   use type Http_Client.HTTP3.Selected_Protocol;
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

   function Phase38_Manual_Absolute_Resolver
     (Origin_Host : String) return Http_Client.DNS_SVCB.Resolver_Result
   is
      pragma Unreferenced (Origin_Host);
      R      : Http_Client.DNS_SVCB.SVCB_Record;
      Result : Http_Client.DNS_SVCB.Resolver_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      R.Priority := 1;
      R.Target := To_Unbounded_String ("SVC.EXAMPLE.");
      R.Port := 9444;
      R.ALPN_Count := 1;
      R.ALPNs (1) := To_Unbounded_String ("H3");
      Status := Http_Client.DNS_SVCB.Append (Result.Records, R);
      Result.Status := Status;
      return Result;
   end Phase38_Manual_Absolute_Resolver;

   function Phase38_Unsupported_Resolver
     (Origin_Host : String) return Http_Client.DNS_SVCB.Resolver_Result
   is
      pragma Unreferenced (Origin_Host);
      Result : Http_Client.DNS_SVCB.Resolver_Result;
   begin
      Result.Status := Http_Client.Errors.Unsupported_Feature;
      return Result;
   end Phase38_Unsupported_Resolver;

   procedure Test_Phase38_Alt_Svc_Parser_Conservative

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Now    : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 14, 12.0);
      Parsed : Http_Client.Alt_Svc.Parse_Result;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3="":443""; ma=60; persist=1, h3=""alt.example:8443""; ma=120; foo=bar",
           Now,
           Parsed,
           Maximum_Max_Age => 90);
      Assert
        (Status = Http_Client.Errors.Ok,
         "valid bounded Alt-Svc header should parse");
      Assert (Parsed.Count = 2, "two alternatives should be retained");
      Assert
        (Parsed.Alternatives (1).Protocol
         = Http_Client.Alt_Svc.Alt_Protocol_HTTP3,
         "h3 should be recognized as supported HTTP/3");
      Assert
        (Parsed.Alternatives (1).Host_Is_Origin,
         ":443 authority should reuse the origin host");
      Assert
        (Parsed.Alternatives (1).Port = 443,
         "origin-host alternative should retain advertised port");
      Assert
        (Parsed.Alternatives (1).Max_Age_Seconds = 60,
         "ma should be parsed without clamping when in bounds");
      Assert
        (Parsed.Alternatives (1).Persist,
         "persist=1 should be retained as policy metadata only");
      Assert
        (Http_Client.Alt_Svc.Select_First_HTTP3 (Parsed) = 1,
         "first supported HTTP/3 alternative should be selected deterministically");
      Assert
        (Http_Client.Alt_Svc.Is_Expired (Parsed.Alternatives (1), Now + 61.0),
         "expiration should be deterministic");
      Assert
        (Parsed.Alternatives (2).Max_Age_Seconds = 90,
         "ma should be clamped to configured maximum age");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3-29=""draft.example:443""; ma=60, " &
           "h3=""final.example:443""; ma=60",
           Now,
           Parsed);
      Assert
        (Status = Http_Client.Errors.Ok,
         "draft and final HTTP/3 Alt-Svc tokens should parse");
      Assert
        (Http_Client.Alt_Svc.Select_First_HTTP3 (Parsed) = 2,
         "Alt-Svc selection should ignore draft HTTP/3 tokens");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3="":443"";" & Character'Val (9) &
           "ma=60," & Character'Val (9) &
           "h3=""tab.example:443""; ma=120",
           Now,
           Parsed);
      Assert
        (Status = Http_Client.Errors.Ok and then Parsed.Count = 2,
         "Alt-Svc parser should accept HTAB as optional whitespace");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""quoted.example:443""; ma=""120""; persist=""0""",
           Now,
           Parsed,
           Maximum_Max_Age => 90);
      Assert
        (Status = Http_Client.Errors.Ok,
         "quoted Alt-Svc known parameter values should parse");
      Assert
        (Parsed.Alternatives (1).Max_Age_Seconds = 90
         and then not Parsed.Alternatives (1).Persist,
         "quoted Alt-Svc parameter values should keep normal semantics");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""quoted.example:443""; ma=""60", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "unterminated quoted Alt-Svc ma values should be rejected");

      declare
         Late : Ada.Calendar.Time;
      begin
         Late := Ada.Calendar.Time_Of (2399, 12, 31, 0.0);
         Status :=
           Http_Client.Alt_Svc.Parse_Header
             ("h3=""huge.example:443""; ma=" &
              Decimal_Image (Natural'Last),
              Late,
              Parsed,
              Maximum_Max_Age => Natural'Last);
         Assert
           (Status = Http_Client.Errors.Invalid_Header,
            "Alt-Svc ma values that overflow expiration time should be rejected");
      exception
         when Constraint_Error =>
            null;
      end;

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""alt.example:443""" & Character'Val (10), Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "CR/LF injection in Alt-Svc must be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h2=""alt.example:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "unsupported Alt-Svc protocol IDs should not be silently accepted");

      Status :=
        Http_Client.Alt_Svc.Parse_Header ("h3=""alt.example:0""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid Alt-Svc ports should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""alt..example:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "ambiguous Alt-Svc host labels should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""bad-.example:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "Alt-Svc host labels ending in hyphen should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""-bad.example:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "Alt-Svc host labels starting with hyphen should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example:443""",
           Now,
           Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "Alt-Svc host labels longer than 63 bytes should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""192.0.2.1:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Alt-Svc IPv4 literal authorities should parse");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""alt.example.:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Ok,
         "absolute Alt-Svc DNS authorities should parse");
      Assert
        (Ada.Strings.Unbounded.To_String (Parsed.Alternatives (1).Host)
         = "alt.example",
         "absolute Alt-Svc DNS authorities should be normalized");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""alt..:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "ambiguous absolute Alt-Svc DNS authorities should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""[2001:db8::1]:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Ok,
         "valid Alt-Svc IPv6 literal authorities should parse");
      Assert
        (Ada.Strings.Unbounded.To_String (Parsed.Alternatives (1).Host)
         = "2001:db8::1"
         and then Parsed.Alternatives (1).Port = 443,
         "Alt-Svc IPv6 literals should be stored without authority brackets");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""[2001:db8::1]443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "Alt-Svc IPv6 authorities without bracketed ports should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""[1234]:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "Alt-Svc bracketed authorities must contain valid IPv6 literals");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""999.0.2.1:443""", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid Alt-Svc IPv4-like authorities should be rejected");

      Status :=
        Http_Client.Alt_Svc.Parse_Header
          ("h3=""alt.example:443"",", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "trailing Alt-Svc alternatives should be rejected");

      Status := Http_Client.Alt_Svc.Parse_Header ("clear", Now, Parsed);
      Assert
        (Status = Http_Client.Errors.Ok and then Parsed.Clear,
         "clear directive should be modeled without mutating global state");
   end Test_Phase38_Alt_Svc_Parser_Conservative;

   procedure Test_Phase38_HTTPS_SVCB_Parser_And_Selection

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      R1     : Http_Client.DNS_SVCB.SVCB_Record;
      R2     : Http_Client.DNS_SVCB.SVCB_Record;
      R3     : Http_Client.DNS_SVCB.SVCB_Record;
      R4     : Http_Client.DNS_SVCB.SVCB_Record;
      R5     : Http_Client.DNS_SVCB.SVCB_Record;
      Set    : Http_Client.DNS_SVCB.Record_Set;
      Status : Http_Client.Errors.Result_Status;
      Index  : Natural;
   begin
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example alpn=h3-29 port=443 ipv4hint=192.0.2.1 ttl=60",
           R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "scripted HTTPS/SVCB h3-29 record should parse");
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          (Character'Val (9) &
           "priority=1 target=tab.example alpn=h3 port=443" &
           Character'Val (9),
           R5);
      Assert
        (Status = Http_Client.Errors.Ok,
         "SVCB parser should trim HTAB around text records");
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1" & Character'Val (9) &
           "target=tab.example" & Character'Val (9) &
           "alpn=h3" & Character'Val (9) & "port=443",
           R5);
      Assert
        (Status = Http_Client.Errors.Ok,
         "SVCB parser should accept HTAB between text record tokens");
      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=2 target=. alpn=h3,h2 port=8443 ech=ignored ipv6hint=2001:db8::1 ttl=30",
           R2);
      Assert
        (Status = Http_Client.Errors.Ok,
         "scripted HTTPS/SVCB h3 record should parse with unsupported ECH metadata");
      Assert
        (Http_Client.DNS_SVCB.Has_ALPN (R2, "h3"),
         "h3 ALPN should be recognized");
      R3 := R2;
      R3.ALPNs (1) := Ada.Strings.Unbounded.To_Unbounded_String (" H3 ");
      Assert
        (Http_Client.DNS_SVCB.Has_ALPN (R3, "h3"),
         "SVCB ALPN matching should normalize resolver-provided tokens");
      Assert
        (R2.Has_ECH,
         "ECH should be exposed as unsupported metadata, not implemented behavior");
      Status := Http_Client.DNS_SVCB.Append (Set, R1);
      Assert
        (Status = Http_Client.Errors.Ok, "first SVCB record should append");
      Status := Http_Client.DNS_SVCB.Append (Set, R2);
      Assert
        (Status = Http_Client.Errors.Ok, "second SVCB record should append");
      Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (Set);
      Assert
        (Index = 2,
         "SVCB selection should ignore draft h3-29 records");

      R3 := R2;
      R3.Priority := 1;
      R3.Target :=
        Ada.Strings.Unbounded.To_Unbounded_String ("bad target");
      Status := Http_Client.DNS_SVCB.Append (Set, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed malformed SVCB record should append");
      Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (Set);
      Assert
        (Index = 2,
         "SVCB selection should ignore malformed resolver records");

      R4 := R2;
      R4.Priority := 1;
      R4.Target :=
        Ada.Strings.Unbounded.To_Unbounded_String ("manual.example.");
      Status := Http_Client.DNS_SVCB.Append (Set, R4);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed absolute SVCB target should append");
      Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (Set);
      Assert
        (Index = 4
         and then To_String (Set.Items (Index).Target) = "manual.example",
         "SVCB append should normalize resolver-provided absolute targets");

      R4 := R2;
      R4.Priority := 1;
      R4.Target :=
        Ada.Strings.Unbounded.To_Unbounded_String
          ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example");
      Status := Http_Client.DNS_SVCB.Append (Set, R4);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed overlong SVCB target should append");
      Index := Http_Client.DNS_SVCB.Select_HTTP3_Record (Set);
      Assert
        (Index = 4,
         "SVCB selection should ignore overlong resolver targets");

      R5 := R2;
      R5.ALPNs (1) := Ada.Strings.Unbounded.To_Unbounded_String ("H3");
      Status := Http_Client.DNS_SVCB.Append (Set, R5);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed uppercase SVCB ALPN should append");
      Assert
        (To_String (Set.Items (Set.Count).ALPNs (1)) = "h3",
         "SVCB append should normalize resolver-provided ALPN tokens");

      R5 := R2;
      R5.ALPN_Count := 2;
      R5.ALPNs (1) := Ada.Strings.Unbounded.To_Unbounded_String ("H3");
      R5.ALPNs (2) := Ada.Strings.Unbounded.To_Unbounded_String ("h3");
      Status := Http_Client.DNS_SVCB.Append (Set, R5);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed duplicate SVCB ALPNs should append");
      Assert
        (Set.Items (Set.Count).ALPN_Count = 1
         and then To_String (Set.Items (Set.Count).ALPNs (1)) = "h3",
         "SVCB append should compact duplicate resolver-provided ALPN tokens");

      R5 := R2;
      R5.ALPN_Count := 2;
      R5.ALPNs (1) := Ada.Strings.Unbounded.Null_Unbounded_String;
      R5.ALPNs (2) := Ada.Strings.Unbounded.To_Unbounded_String ("h3");
      Status := Http_Client.DNS_SVCB.Append (Set, R5);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed empty SVCB ALPN should append");
      Assert
        (Set.Items (Set.Count).ALPN_Count = 1
         and then To_String (Set.Items (Set.Count).ALPNs (1)) = "h3",
         "SVCB append should drop empty resolver-provided ALPN tokens");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record ("priority=0 target=. alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "alias-form HTTPS/SVCB records are intentionally unsupported");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=. alpn=h3 port=70000", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid SVCB ports should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example alpn=h3, port=443", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "trailing SVCB ALPN separators should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example alpn=h3,h3 port=443", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "duplicate SVCB ALPN entries should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc..example alpn=h3 port=443", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "ambiguous SVCB target labels should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example alpn=h3 port=443",
           R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "overlong SVCB target labels should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=192.0.2.1 alpn=h3 port=443", R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "valid SVCB IPv4 literal targets should parse");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=999.0.2.1 alpn=h3 port=443", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "invalid SVCB IPv4-like targets should be rejected");

      Status :=
        Http_Client.DNS_SVCB.Parse_Record
          ("priority=1 target=svc.example. alpn=h3 port=443", R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "absolute SVCB target names should parse deterministically");
      Assert
        (To_String (R1.Target) = "svc.example",
         "absolute SVCB target names should be normalized for connection use");
   end Test_Phase38_HTTPS_SVCB_Parser_And_Selection;

   procedure Test_Phase38_HTTPS_Records_Text_Model

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      R1       : Http_Client.HTTPS_Records.HTTPS_Record;
      R2       : Http_Client.HTTPS_Records.HTTPS_Record;
      R3       : Http_Client.HTTPS_Records.HTTPS_Record;
      List     : Http_Client.HTTPS_Records.HTTPS_Record_List;
      Selected : Http_Client.HTTPS_Records.Selected_HTTPS_Service;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 svc.example alpn=h3-29 port=443 ipv4hint=192.0.2.1", R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "scripted HTTPS record with h3-29 should parse");
      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          (Character'Val (9) & "1 tab.example alpn=h3 port=443" &
           Character'Val (9),
           R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS record parser should trim HTAB around text records");
      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1" & Character'Val (9) & "tab.example" &
           Character'Val (9) & "alpn=h3" & Character'Val (9) &
           "port=443",
           R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS record parser should accept HTAB between text record tokens");
      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("2 . alpn=h3,h2 port=9443 ech=ignored ipv6hint=2001:db8::1", R2);
      Assert
        (Status = Http_Client.Errors.Ok,
         "scripted HTTPS record with h3 and ECH metadata should parse");
      Assert
        (R2.ALPN_Count = 2
         and then R2.ALPNs (1) = Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS record parser should preserve supported ALPN ordering");
      Assert
        (R2.Has_ECH and then R2.Has_IPv6_Hint,
         "ECH and address hints should remain structural metadata only");
      Status := Http_Client.HTTPS_Records.Append (List, R1);
      Assert
        (Status = Http_Client.Errors.Ok, "first HTTPS record should append");
      Status := Http_Client.HTTPS_Records.Append (List, R2);
      Assert
        (Status = Http_Client.Errors.Ok, "second HTTPS record should append");
      Selected := Http_Client.HTTPS_Records.Select_HTTP3 (List);
      Assert
        (Selected.Available
         and then Selected.Port = 9443
         and then Selected.ALPN = Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS selection should ignore draft h3-29 services");

      R3 := R2;
      R3.Priority := 1;
      R3.Target_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("bad target");
      Status := Http_Client.HTTPS_Records.Append (List, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed malformed HTTPS record should append");
      Selected := Http_Client.HTTPS_Records.Select_HTTP3 (List);
      Assert
        (Selected.Available
         and then Selected.Port = 9443
         and then Selected.ALPN = Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS selection should ignore malformed resolver records");

      R3 := R2;
      R3.Priority := 1;
      R3.Target_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("manual.example.");
      Status := Http_Client.HTTPS_Records.Append (List, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed absolute HTTPS target should append");
      Selected := Http_Client.HTTPS_Records.Select_HTTP3 (List);
      Assert
        (Selected.Available
         and then Selected.Port = 9443
         and then Selected.ALPN = Http_Client.HTTPS_Records.ALPN_H3
         and then To_String (List.Items (List.Count).Target_Name) =
           "manual.example",
         "HTTPS append should normalize resolver-provided absolute targets");

      R3 := R2;
      R3.Priority := 1;
      R3.Target_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String
          ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example");
      Status := Http_Client.HTTPS_Records.Append (List, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed overlong HTTPS target should append");
      Selected := Http_Client.HTTPS_Records.Select_HTTP3 (List);
      Assert
        (Selected.Available
         and then Selected.Port = 9443
         and then Selected.ALPN = Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS selection should ignore overlong resolver targets");

      R3 := R2;
      R3.ALPN_Count := 2;
      R3.ALPNs (1) := Http_Client.HTTPS_Records.ALPN_H3;
      R3.ALPNs (2) := Http_Client.HTTPS_Records.ALPN_H3;
      declare
         Direct_List : Http_Client.HTTPS_Records.HTTPS_Record_List;
      begin
         Direct_List.Count := 1;
         Direct_List.Items (1) := R3;
         Direct_List.Items (1).Target_Name :=
           Ada.Strings.Unbounded.To_Unbounded_String ("DIRECT.EXAMPLE.");
         Selected := Http_Client.HTTPS_Records.Select_HTTP3 (Direct_List);
         Assert
           (Selected.Available
            and then To_String (Selected.Target_Name) = "direct.example",
            "HTTPS selection should return normalized direct resolver targets");
      end;

      Status := Http_Client.HTTPS_Records.Append (List, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed duplicate HTTPS ALPNs should append");
      Assert
        (List.Items (List.Count).ALPN_Count = 1
         and then List.Items (List.Count).ALPNs (1) =
           Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS append should compact duplicate resolver-provided ALPN tokens");

      R3 := R2;
      R3.Priority := 0;
      Status := Http_Client.HTTPS_Records.Append (List, R3);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manually constructed HTTPS alias-form record should append");
      Selected := Http_Client.HTTPS_Records.Select_HTTP3 (List);
      Assert
        (Selected.Available
         and then Selected.Port = 9443
         and then Selected.ALPN = Http_Client.HTTPS_Records.ALPN_H3,
         "HTTPS selection should ignore alias-form resolver records");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record ("0 . alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Unsupported_Feature,
         "HTTPS record parser should reject alias-form records");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record ("1 . alpn=h3 port=0", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject invalid port values");
      Status := Http_Client.HTTPS_Records.Parse_Text_Record ("1 . alpn=", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject empty ALPN lists");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record ("1 . alpn=h3,", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject trailing ALPN separators");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 . alpn=h3,h3", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject duplicate ALPN entries");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 svc..example alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject ambiguous target labels");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example alpn=h3",
           R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject overlong target labels");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 192.0.2.1 alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS record parser should accept valid IPv4 literal targets");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 999.0.2.1 alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Invalid_Header,
         "HTTPS record parser should reject invalid IPv4-like targets");

      Status :=
        Http_Client.HTTPS_Records.Parse_Text_Record
          ("1 svc.example. alpn=h3", R1);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS record parser should accept absolute DNS presentation names");
   end Test_Phase38_HTTPS_Records_Text_Model;

   procedure Test_Phase38_Protocol_Discovery_Policy_And_Cache

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_Value     : Http_Client.URI.URI_Reference;
      Cache         : Http_Client.Protocol_Discovery.Discovery_Cache;
      Options       : Http_Client.Protocol_Discovery.Discovery_Options :=
        Http_Client.Protocol_Discovery.Default_Discovery_Options;
      H3            : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      Selected      : Http_Client.Protocol_Discovery.Discovery_Selection;
      Now           : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 14, 12.0);
      Status        : Http_Client.Errors.Result_Status;
      Client_Config : Http_Client.Clients.Client_Configuration :=
        Http_Client.Clients.Default_Client_Configuration;
      Client        : Http_Client.Clients.Client;
   begin
      Status := Http_Client.URI.Parse ("https://example.test/path", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok, "phase38 origin URI should parse");
      Http_Client.Protocol_Discovery.Initialize (Cache, Options);
      H3.Mode := Http_Client.HTTP3.HTTP3_Allowed;

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache, URI_Value, "h3="":443""; ma=60", Now, Options);
      Assert
        (Status = Http_Client.Errors.Ok,
         "disabled Alt-Svc discovery should be a deterministic no-op");
      Assert
        (Http_Client.Protocol_Discovery.Entry_Count (Cache) = 0,
         "disabled discovery must not learn hidden Alt-Svc state");

      Options.Enable_Alt_Svc := True;
      Options.Allow_HTTP3_Discovery := True;
      Options.Maximum_Alt_Svc_Entries := 2;
      Options.Maximum_Alternatives_Per_Origin := 1;
      Http_Client.Protocol_Discovery.Initialize (Cache, Options);

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "h3-29=""draft.example:443""; ma=60",
           Now,
           Options,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "draft-only Alt-Svc should parse without selecting final HTTP/3");
      Assert
        (Http_Client.Protocol_Discovery.Entry_Count (Cache) = 0,
         "draft-only Alt-Svc must not populate selectable discovery state");

      declare
         Invalid_Options : Http_Client.Protocol_Discovery.Discovery_Options :=
           Options;
      begin
         Invalid_Options.Maximum_Alt_Svc_Entries :=
           Http_Client.Protocol_Discovery.Max_Cache_Entries + 1;
         Status :=
           Http_Client.Protocol_Discovery.Selection
             (Cache,
              URI_Value,
              Invalid_Options,
              H3,
              Http_Client.Proxies.No_Proxy_Config,
              Now,
              Selected);
         Assert
           (Status = Http_Client.Errors.Invalid_Configuration,
            "discovery selection should validate resource limits before use");
      end;

      declare
         Invalid_H3 : Http_Client.HTTP3.HTTP3_Options := H3;
      begin
         Invalid_H3.Max_Header_List_Size := 0;
         Status :=
           Http_Client.Protocol_Discovery.Selection
             (Cache,
              URI_Value,
              Options,
              Invalid_H3,
              Http_Client.Proxies.No_Proxy_Config,
              Now,
              Selected);
         Assert
           (Status = Http_Client.Errors.Invalid_Configuration,
            "discovery selection should validate HTTP/3 options before use");
      end;

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "h3="":443""; ma=60",
           Now,
           Options,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "verified HTTPS Alt-Svc should be accepted when enabled");
      Assert
        (Http_Client.Protocol_Discovery.Entry_Count (Cache) = 1,
         "Alt-Svc cache should remain explicit and bounded");

      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok,
         "Alt-Svc selection should succeed without a proxy");
      Assert
        (Selected.Source = Http_Client.Protocol_Discovery.Discovery_Alt_Svc,
         "selection should come from Alt-Svc cache");
      Assert
        (Selected.Protocol = Http_Client.HTTP3.Protocol_HTTP_3,
         "discovery should select HTTP/3 only when explicitly allowed");
      Assert
        (Selected.Requires_Origin_TLS_Authority,
         "selection must preserve origin TLS authority validation");

      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.HTTP ("proxy.example", 8080),
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok
         and then
           Selected.Source = Http_Client.Protocol_Discovery.Discovery_None,
         "configured proxies must suppress discovery instead of being bypassed");

      declare
         Full_Cache : Http_Client.Protocol_Discovery.Discovery_Cache;
         Other_URI  : Http_Client.URI.URI_Reference;
      begin
         Http_Client.Protocol_Discovery.Initialize (Full_Cache, Options);
         Status := Http_Client.URI.Parse ("https://one.example/path", Other_URI);
         Assert
           (Status = Http_Client.Errors.Ok,
            "phase38 first cache-fill URI should parse");
         Status :=
           Http_Client.Protocol_Discovery.Accept_Alt_Svc
             (Full_Cache,
              Other_URI,
              "h3="":443""; ma=60",
              Now,
              Options,
              From_Verified_HTTPS_Response => True);
         Assert
           (Status = Http_Client.Errors.Ok,
            "first bounded Alt-Svc cache entry should be accepted");
         Status := Http_Client.URI.Parse ("https://two.example/path", Other_URI);
         Assert
           (Status = Http_Client.Errors.Ok,
            "phase38 second cache-fill URI should parse");
         Status :=
           Http_Client.Protocol_Discovery.Accept_Alt_Svc
             (Full_Cache,
              Other_URI,
              "h3="":443""; ma=60",
              Now,
              Options,
              From_Verified_HTTPS_Response => True);
         Assert
           (Status = Http_Client.Errors.Ok
            and then Http_Client.Protocol_Discovery.Entry_Count (Full_Cache) = 2,
            "second bounded Alt-Svc cache entry should fill the cache");
         Status := Http_Client.URI.Parse ("https://draft.example/path", Other_URI);
         Assert
           (Status = Http_Client.Errors.Ok,
            "phase38 draft-only full-cache URI should parse");
         Status :=
           Http_Client.Protocol_Discovery.Accept_Alt_Svc
             (Full_Cache,
              Other_URI,
              "h3-29=""draft.example:443""; ma=60",
              Now,
              Options,
              From_Verified_HTTPS_Response => True);
         Assert
           (Status = Http_Client.Errors.Ok
            and then Http_Client.Protocol_Discovery.Entry_Count (Full_Cache) = 2,
            "draft-only Alt-Svc should not fail when cache is full");
      end;

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "h3="":443""; ma=0, h3=""alt.example:8443""; ma=60",
           Now,
           Options,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "expired Alt-Svc alternatives should not consume bounded slots");
      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok
         and then Selected.Source = Http_Client.Protocol_Discovery.Discovery_Alt_Svc
         and then Ada.Strings.Unbounded.To_String (Selected.Alternative_Host) =
           "alt.example"
         and then Selected.Alternative_Port = 8443,
         "Alt-Svc selection should skip expired alternatives before applying " &
         "the per-origin cap");

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "h3="":443""; ma=60",
           Now,
           Options,
           From_Verified_HTTPS_Response => False);
      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "Alt-Svc from unverified or insecure contexts must be rejected");

      Status := Http_Client.URI.Parse ("http://example.test/path", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok,
         "phase38 plain HTTP origin URI should parse");
      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "h3="":443""; ma=60",
           Now,
           Options,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Invalid_Request,
         "Alt-Svc for plain HTTP origins must be rejected");
      Status := Http_Client.URI.Parse ("https://example.test/path", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok,
         "phase38 HTTPS origin URI should parse again");

      Status :=
        Http_Client.Protocol_Discovery.Accept_Alt_Svc
          (Cache,
           URI_Value,
           "clear",
           Now,
           Options,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Ok
         and then Http_Client.Protocol_Discovery.Entry_Count (Cache) = 0,
         "clear directive should clear only explicit discovery metadata");

      Status :=
        Http_Client.Clients.Accept_Alt_Svc_Header
          (Client,
           URI_Value,
           "h3="":443""; ma=60",
           Now,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Client_Not_Initialized,
         "client-owned Alt-Svc cache must reject uninitialized clients");
      Client_Config.Discovery := Options;
      Status := Http_Client.Clients.Initialize (Client, Client_Config);
      Assert
        (Status = Http_Client.Errors.Ok,
         "client with enabled discovery policy should initialize");
      Status :=
        Http_Client.Clients.Accept_Alt_Svc_Header
          (Client,
           URI_Value,
           "h3="":443""; ma=60",
           Now,
           From_Verified_HTTPS_Response => True);
      Assert
        (Status = Http_Client.Errors.Ok,
         "client-owned Alt-Svc cache should accept explicit verified HTTPS metadata");
      Http_Client.Clients.Clear_Discovery_Cache (Client);
   end Test_Phase38_Protocol_Discovery_Policy_And_Cache;

   procedure Test_Phase38_SVCB_Resolver_And_Fallback_Policy

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      URI_Value : Http_Client.URI.URI_Reference;
      Cache     : Http_Client.Protocol_Discovery.Discovery_Cache;
      Options   : Http_Client.Protocol_Discovery.Discovery_Options :=
        Http_Client.Protocol_Discovery.Default_Discovery_Options;
      H3        : Http_Client.HTTP3.HTTP3_Options :=
        Http_Client.HTTP3.Default_HTTP3_Options;
      Selected  : Http_Client.Protocol_Discovery.Discovery_Selection;
      Now       : constant Ada.Calendar.Time :=
        Ada.Calendar.Time_Of (2026, 5, 14, 12.0);
      Status    : Http_Client.Errors.Result_Status;
   begin
      Status :=
        Http_Client.URI.Parse ("https://example.test/resource", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok,
         "phase38 SVCB origin URI should parse");
      Options.Enable_HTTPS_SVCB := True;
      Options.Allow_HTTP3_Discovery := True;
      Options.Resolver := Phase38_Scripted_Resolver'Unrestricted_Access;
      H3.Mode := Http_Client.HTTP3.HTTP3_Allowed;
      Http_Client.Protocol_Discovery.Initialize (Cache, Options);

      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok,
         "scripted HTTPS/SVCB resolver should be usable without public DNS");
      Assert
        (Selected.Source = Http_Client.Protocol_Discovery.Discovery_HTTPS_SVCB,
         "SVCB selection should be reported distinctly");
      Assert
        (Selected.Alternative_Port = 9443,
         "SVCB port parameter should influence alternative endpoint selection");
      Assert
        (not Selected.Uses_Origin_Host,
         "non-dot target should select the advertised target name");
      Assert
        (Selected.Requires_Origin_TLS_Authority,
         "SVCB selection must still require original origin authority validation");

      Options.Resolver := Phase38_Manual_Absolute_Resolver'Unrestricted_Access;
      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok,
         "manual HTTPS/SVCB resolver should be selectable");
      Assert
        (Selected.Source = Http_Client.Protocol_Discovery.Discovery_HTTPS_SVCB
         and then To_String (Selected.Alternative_Host) = "svc.example"
         and then Selected.Alternative_Port = 9444,
         "SVCB selection should normalize resolver-provided target names");

      Options.Resolver := Phase38_Unsupported_Resolver'Unrestricted_Access;
      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok,
         "unsupported HTTPS/SVCB resolver should be a soft miss");
      Assert
        (Selected.Source = Http_Client.Protocol_Discovery.Discovery_None,
         "unsupported HTTPS/SVCB resolver should not select an alternative");

      Status :=
        Http_Client.URI.Parse ("http://example.test/resource", URI_Value);
      Assert
        (Status = Http_Client.Errors.Ok,
         "phase38 SVCB plain HTTP URI should parse");
      Options.Resolver := Phase38_Scripted_Resolver'Unrestricted_Access;
      Status :=
        Http_Client.Protocol_Discovery.Selection
          (Cache,
           URI_Value,
           Options,
           H3,
           Http_Client.Proxies.No_Proxy_Config,
           Now,
           Selected);
      Assert
        (Status = Http_Client.Errors.Ok,
         "HTTPS/SVCB discovery should ignore plain HTTP origins");
      Assert
        (Selected.Source = Http_Client.Protocol_Discovery.Discovery_None,
         "plain HTTP origins should not select HTTPS/SVCB alternatives");

      Assert
        (Http_Client.Protocol_Discovery.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "fallback should be disabled by default");
      Options.Fallback :=
        Http_Client.Protocol_Discovery.Discovery_Fallback_Before_Send;
      Assert
        (Http_Client.Protocol_Discovery.Fallback_Status
           (Options, Request_Bytes_Already_Sent => False)
         = Http_Client.Errors.Ok,
         "fallback before transmission may be enabled explicitly");
      Assert
        (Http_Client.Protocol_Discovery.Fallback_Status
           (Options, Request_Bytes_Already_Sent => True)
         = Http_Client.Errors.HTTP3_Fallback_Disallowed,
         "fallback after transmission must remain disallowed");
   end Test_Phase38_SVCB_Resolver_And_Fallback_Policy;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Discovery");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Phase38_Alt_Svc_Parser_Conservative'Access,
         "Test_Phase38_Alt_Svc_Parser_Conservative");
      Register_Routine
        (T,
         Test_Phase38_HTTPS_SVCB_Parser_And_Selection'Access,
         "Test_Phase38_HTTPS_SVCB_Parser_And_Selection");
      Register_Routine
        (T,
         Test_Phase38_HTTPS_Records_Text_Model'Access,
         "Test_Phase38_HTTPS_Records_Text_Model");
      Register_Routine
        (T,
         Test_Phase38_Protocol_Discovery_Policy_And_Cache'Access,
         "Test_Phase38_Protocol_Discovery_Policy_And_Cache");
      Register_Routine
        (T,
         Test_Phase38_SVCB_Resolver_And_Fallback_Policy'Access,
         "Test_Phase38_SVCB_Resolver_And_Fallback_Policy");
   end Register_Tests;

end Http_Client.Protocol_Discovery.Tests;
