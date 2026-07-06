with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

with AUnit.Assertions;

with Http_Client.Binary_Test_Data;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP1;
with Http_Client.Request_Bodies;
with Http_Client.Requests;
with Http_Client.Responses;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Binary_Safety_Tests is
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Errors.Result_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   procedure Assert_Bytes_Equal
     (Actual   : Ada.Streams.Stream_Element_Array;
      Expected : Ada.Streams.Stream_Element_Array;
      Message  : String)
   is
   begin
      Assert (Actual'Length = Expected'Length, Message & " length mismatch");
      if Expected'Length = 0 then
         return;
      end if;

      for Offset in 0 .. Natural (Expected'Length) - 1 loop
         Assert
           (Actual (Actual'First + Ada.Streams.Stream_Element_Offset (Offset)) =
            Expected (Expected'First + Ada.Streams.Stream_Element_Offset (Offset)),
            Message & " byte mismatch at offset" & Natural'Image (Offset));
      end loop;
   end Assert_Bytes_Equal;

   procedure Assert_Status
     (Actual   : Http_Client.Errors.Result_Status;
      Expected : Http_Client.Errors.Result_Status;
      Message  : String) is
   begin
      Assert
        (Actual = Expected,
         Message & " expected " & Http_Client.Errors.Result_Status'Image (Expected) &
         " got " & Http_Client.Errors.Result_Status'Image (Actual));
   end Assert_Status;

   procedure Assert_Header_Name_And_Value_Validation is
      List   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status : Http_Client.Errors.Result_Status;
   begin
      Assert (Http_Client.Headers.Is_Valid_Name ("Git-Protocol"),
              "valid token header name accepted");
      Assert (Http_Client.Headers.Is_Valid_Name ("X_Git.SHA256~Test"),
              "valid token punctuation accepted");

      Assert (not Http_Client.Headers.Is_Valid_Name (""),
              "empty header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad Name"),
              "space in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad" & Character'Val (9) & "Name"),
              "tab in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad:Name"),
              "colon in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad" & Character'Val (13) & "Name"),
              "CR in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad" & Character'Val (10) & "Name"),
              "LF in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad" & Character'Val (0) & "Name"),
              "NUL in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad" & Character'Val (127) & "Name"),
              "DEL in header name rejected");
      Assert (not Http_Client.Headers.Is_Valid_Name ("Bad(Name)"),
              "non-token separator in header name rejected");

      Assert (Http_Client.Headers.Is_Valid_Value ("visible ASCII value"),
              "ordinary visible ASCII header value accepted");
      Assert (Http_Client.Headers.Is_Valid_Value (""),
              "empty header value accepted");
      Assert (Http_Client.Headers.Is_Valid_Value ("  leading and trailing spaces  "),
              "leading/trailing spaces are stored by Header_List API");

      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (13) & "y"),
              "CR header value injection rejected");
      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (10) & "y"),
              "LF header value injection rejected");
      Assert (not Http_Client.Headers.Is_Valid_Value
                    ("x" & Character'Val (13) & Character'Val (10) & "Injected: y"),
              "CRLF header value injection rejected");
      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (0) & "y"),
              "NUL header value rejected");
      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (9) & "y"),
              "horizontal tab header value rejected by Phase 13 policy");
      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (127) & "y"),
              "DEL header value rejected");
      Assert (not Http_Client.Headers.Is_Valid_Value ("x" & Character'Val (133) & "y"),
              "C1 control header value rejected");

      Status := Http_Client.Headers.Add (List, "Git-Protocol", "version=2");
      Assert_Status (Status, Http_Client.Errors.Ok, "safe header add");
      Status := Http_Client.Headers.Add (List, "git-protocol", "version=1");
      Assert_Status (Status, Http_Client.Errors.Ok, "duplicate add preserves field");
      Assert (Http_Client.Headers.Count (List, "GIT-PROTOCOL") = 2,
              "case-insensitive duplicate count");
      Assert (Http_Client.Headers.Get (List, "gIt-PrOtOcOl") = "version=2",
              "case-insensitive lookup returns first inserted value");
      Assert (Http_Client.Headers.Name_At (List, 1) = "Git-Protocol",
              "iteration preserves first spelling");
      Assert (Http_Client.Headers.Name_At (List, 2) = "git-protocol",
              "iteration preserves duplicate spelling/order");

      Status := Http_Client.Headers.Set (List, "Git-Protocol", "version=3");
      Assert_Status (Status, Http_Client.Errors.Ok, "set replaces duplicates");
      Assert (Http_Client.Headers.Count (List, "git-protocol") = 1,
              "set collapses duplicate fields");
      Assert (Http_Client.Headers.Get (List, "git-protocol") = "version=3",
              "set replacement value visible");
   end Assert_Header_Name_And_Value_Validation;

   procedure Assert_Request_Response_Byte_Array_Preservation is
      All_Data       : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.All_Bytes;
      Empty_Data     : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.Empty;
      NUL_Data       : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.One_NUL;
      Boundary_Data  : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.CRLF_Heavy;
      Pkt_Line_Data  : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.Git_Pkt_Line_Like;
      Pack_Data      : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.Git_Packfile_Like;
      Compressedish  : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.Compressed_Looking;
      Long_Data      : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.Long_Buffer_Boundary;
      Request_Body   : Http_Client.Request_Bodies.Request_Body;
      Response       : Http_Client.Responses.Response;
      Status         : Http_Client.Errors.Result_Status;

      procedure Check_Response_Body
        (Label : String;
         Data  : Ada.Streams.Stream_Element_Array)
      is
      begin
         Status := Http_Client.Responses.Parse_Response
           ("HTTP/1.1 200 OK" & CRLF &
            "Content-Length: " & Decimal_Image (Natural (Data'Length)) &
            CRLF & CRLF & Http_Client.Binary_Test_Data.To_String (Data),
            Response);
         Assert_Status
           (Status, Http_Client.Errors.Ok,
            "response parser accepts " & Label & " entity body");
         Assert_Bytes_Equal
           (Http_Client.Responses.Response_Body_Bytes (Response), Data,
            Label & " Response_Body_Bytes byte-exact");
         Assert
           (Http_Client.Responses.Response_Body (Response) =
            Http_Client.Binary_Test_Data.To_String (Data),
            Label & " Response_Body string convenience path is octet-exact");
      end Check_Response_Body;
   begin
      Request_Body := Http_Client.Request_Bodies.From_Bytes (Empty_Data);
      Assert_Bytes_Equal
        (Http_Client.Request_Bodies.Buffered_Bytes (Request_Body), Empty_Data,
         "Request_Bodies.From_Bytes empty corpus byte-exact");

      Request_Body := Http_Client.Request_Bodies.From_Bytes (All_Data);
      Assert_Bytes_Equal
        (Http_Client.Request_Bodies.Buffered_Bytes (Request_Body), All_Data,
         "Request_Bodies.From_Bytes all-byte corpus byte-exact");

      Request_Body := Http_Client.Request_Bodies.From_String
        (Http_Client.Binary_Test_Data.To_String (All_Data));
      Assert_Bytes_Equal
        (Http_Client.Request_Bodies.Buffered_Bytes (Request_Body), All_Data,
         "Request_Bodies.From_String preserves Character octets including NUL/high bytes");

      Check_Response_Body ("empty", Empty_Data);
      Check_Response_Body ("one-NUL", NUL_Data);
      Check_Response_Body ("all-byte", All_Data);
      Check_Response_Body ("CRLFCRLF/header-looking", Boundary_Data);
      Check_Response_Body ("Git pkt-line-like", Pkt_Line_Data);
      Check_Response_Body ("Git packfile-like", Pack_Data);
      Check_Response_Body ("compressed-looking", Compressedish);
      Check_Response_Body ("long buffer-boundary", Long_Data);
   end Assert_Request_Response_Byte_Array_Preservation;

   procedure Assert_Header_Body_Boundary_And_Request_Serialization is
      URI      : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
      Output   : Ada.Strings.Unbounded.Unbounded_String;
      Status   : Http_Client.Errors.Result_Status;
      Payload  : constant Ada.Streams.Stream_Element_Array :=
        Http_Client.Binary_Test_Data.CRLF_Heavy;
      Text     : constant String := Http_Client.Binary_Test_Data.To_String (Payload);
      Boundary : Natural;
   begin
      Status := Http_Client.URI.Parse ("http://example.test/git-receive-pack", URI);
      Assert_Status (Status, Http_Client.Errors.Ok, "test URI parse");
      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.POST,
         URI    => URI,
         Item   => Request);
      Assert_Status (Status, Http_Client.Errors.Ok, "test request create");
      Status := Http_Client.Requests.Set_Body
        (Request, Http_Client.Request_Bodies.From_Bytes (Payload));
      Assert_Status (Status, Http_Client.Errors.Ok, "test request body attach");

      Status := Http_Client.HTTP1.Serialize_Request (Request, Output);
      Assert_Status (Status, Http_Client.Errors.Ok,
                     "HTTP/1.1 buffered binary request serialization");
      declare
         Wire : constant String := Ada.Strings.Unbounded.To_String (Output);
      begin
         Boundary := Ada.Strings.Fixed.Index (Wire, CRLF & CRLF);
         Assert (Boundary /= 0, "serialized request contains header/body boundary");
         Assert
           (Wire (Boundary + 4 .. Wire'Last) = Text,
            "request body bytes after first CRLFCRLF are preserved exactly");
         Assert
           (Ada.Strings.Fixed.Index
              (Wire (Wire'First .. Boundary + 3),
               "Transfer-Encoding: chunked") = 0,
            "buffered request body header section does not confuse body bytes with framing");
      end;
   end Assert_Header_Body_Boundary_And_Request_Serialization;

   procedure Assert_Framing_Header_Rejection is
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Content-Length: 0" & CRLF &
         "Content-Length: 0" & CRLF & CRLF,
         Response);
      Assert_Status (Status, Http_Client.Errors.Invalid_Header,
                     "duplicate identical Content-Length rejected deterministically");

      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Content-Length: 1" & CRLF &
         "Content-Length: 2" & CRLF & CRLF & "a",
         Response);
      Assert_Status (Status, Http_Client.Errors.Invalid_Header,
                     "duplicate conflicting Content-Length rejected deterministically");

      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Transfer-Encoding: chunked" & CRLF &
         "Content-Length: 0" & CRLF & CRLF,
         Response);
      Assert_Status (Status, Http_Client.Errors.Unsupported_Feature,
                     "Transfer-Encoding plus Content-Length rejected by buffered parser");

      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Transfer-Encoding: gzip" & CRLF & CRLF,
         Response);
      Assert_Status (Status, Http_Client.Errors.Unsupported_Feature,
                     "unsupported raw transfer coding rejected by buffered parser");

      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Content-Length: 4" & CRLF & CRLF & "abc",
         Response);
      Assert_Status (Status, Http_Client.Errors.Incomplete_Message,
                     "short Content-Length response body rejected");

      Status := Http_Client.Responses.Parse_Response
        ("HTTP/1.1 200 OK" & CRLF &
         "Content-Length: 3" & CRLF & CRLF & "abcd",
         Response);
      Assert_Status (Status, Http_Client.Errors.Protocol_Error,
                     "long Content-Length response body rejected and cannot bleed into reuse");
   end Assert_Framing_Header_Rejection;

   procedure Assert_HTTP2_Trailer_Header_Safety is
      Trailers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.Headers.Add (Trailers, "x-checksum", "abc123");
      Assert_Status (Status, Http_Client.Errors.Ok, "ordinary HTTP/2 trailer accepted in list");
      Assert_Status
        (Http_Client.Headers.Validate_HTTP2_Trailers (Trailers, Response => True),
         Http_Client.Errors.Ok,
         "ordinary HTTP/2 trailer validates");

      Trailers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Add (Trailers, "Transfer-Encoding", "chunked");
      Assert_Status (Status, Http_Client.Errors.Ok,
                     "forbidden HTTP/2 trailer can be represented before protocol validation");
      Assert_Status
        (Http_Client.Headers.Validate_HTTP2_Trailers (Trailers, Response => True),
         Http_Client.Errors.Invalid_Header,
         "HTTP/2 trailer Transfer-Encoding rejected");

      Trailers := Http_Client.Headers.Empty;
      Status := Http_Client.Headers.Add_HTTP2_Pseudo (Trailers, ":status", "200");
      Assert_Status (Status, Http_Client.Errors.Ok,
                     "pseudo-header can be represented by HTTP/2 mapping layer");
      Assert_Status
        (Http_Client.Headers.Validate_HTTP2_Trailers (Trailers, Response => True),
         Http_Client.Errors.Invalid_Header,
         "HTTP/2 trailer pseudo-header rejected");
   end Assert_HTTP2_Trailer_Header_Safety;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Phase 13 binary/header safety");
   end Name;

   procedure AUnit_Header_Validation
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Header_Name_And_Value_Validation;
   end AUnit_Header_Validation;

   procedure AUnit_Binary_Preservation
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Request_Response_Byte_Array_Preservation;
   end AUnit_Binary_Preservation;

   procedure AUnit_Boundary
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Header_Body_Boundary_And_Request_Serialization;
   end AUnit_Boundary;

   procedure AUnit_Framing_Rejection
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Framing_Header_Rejection;
   end AUnit_Framing_Rejection;

   procedure AUnit_HTTP2_Trailer_Header_Safety
     (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_HTTP2_Trailer_Header_Safety;
   end AUnit_HTTP2_Trailer_Header_Safety;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T, AUnit_Header_Validation'Access,
         "Test_Header_CRLF_Injection_Rejection");
      Register_Routine
        (T, AUnit_Binary_Preservation'Access,
         "Test_Request_Response_NUL_High_Byte_Preservation");
      Register_Routine
        (T, AUnit_Boundary'Access,
         "Test_CRLFCRLF_Body_Boundary_Preservation");
      Register_Routine
        (T, AUnit_Framing_Rejection'Access,
         "Test_Duplicate_Content_Length_And_TE_CL_Rejection");
      Register_Routine
        (T, AUnit_HTTP2_Trailer_Header_Safety'Access,
         "Test_HTTP2_Header_Validation_Rejects_Transfer_Framing");
   end Register_Tests;
end Http_Client.Binary_Safety_Tests;
