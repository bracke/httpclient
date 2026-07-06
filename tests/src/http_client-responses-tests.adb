with AUnit.Assertions;
with Http_Client.Errors;

package body Http_Client.Responses.Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   procedure Parse_Ok
     (Header_Block : String;
      Response     : out Http_Client.Responses.Response) is
      Status : constant Http_Client.Errors.Result_Status :=
        Http_Client.Responses.Parse_Response
          ("HTTP/1.1 200 OK" & CRLF & Header_Block & CRLF,
           Response);
   begin
      Assert
        (Status = Http_Client.Errors.Ok,
         "response metadata fixture should parse");
   end Parse_Ok;

   procedure Test_Content_Type_Returns_Header_Value
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: image/png" & CRLF, Response);
      Assert
        (Http_Client.Responses.Has_Content_Type (Response),
         "Content-Type should be present");
      Assert
        (Http_Client.Responses.Content_Type (Response) = "image/png",
         "Content_Type should return complete header value");
      Assert
        (Http_Client.Responses.Media_Type (Response) = "image/png",
         "Media_Type should return bare type when no parameters exist");
   end Test_Content_Type_Returns_Header_Value;

   procedure Test_Content_Type_Header_Name_Is_Case_Insensitive
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("content-type: application/pdf" & CRLF, Response);
      Assert
        (Http_Client.Responses.Has_Content_Type (Response),
         "lower-case content-type header should be found");
      Assert
        (Http_Client.Responses.Content_Type (Response) = "application/pdf",
         "case-insensitive response accessor should return value");
   end Test_Content_Type_Header_Name_Is_Case_Insensitive;

   procedure Test_Media_Type_Strips_Parameters
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: text/html; charset=utf-8" & CRLF, Response);
      Assert
        (Http_Client.Responses.Content_Type (Response) =
         "text/html; charset=utf-8",
         "Content_Type should preserve complete value");
      Assert
        (Http_Client.Responses.Media_Type (Response) = "text/html",
         "Media_Type should strip parameters");
   end Test_Media_Type_Strips_Parameters;

   procedure Test_Media_Type_Trims_Optional_Whitespace
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type:   Application/JSON   ; charset=utf-8"
                & CRLF, Response);
      Assert
        (Http_Client.Responses.Media_Type (Response) = "Application/JSON",
         "Media_Type should trim surrounding optional whitespace only");
   end Test_Media_Type_Trims_Optional_Whitespace;

   procedure Test_Charset_Parses_Unquoted_Value
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: text/plain; charset=utf-8" & CRLF, Response);
      Assert
        (Http_Client.Responses.Has_Charset (Response),
         "unquoted charset should be present");
      Assert
        (Http_Client.Responses.Charset (Response) = "utf-8",
         "unquoted charset value should be returned");
   end Test_Charset_Parses_Unquoted_Value;

   procedure Test_Charset_Parses_Quoted_Value
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: text/plain; charset=""utf-8""" & CRLF,
                Response);
      Assert
        (Http_Client.Responses.Has_Charset (Response),
         "quoted charset should be present");
      Assert
        (Http_Client.Responses.Charset (Response) = "utf-8",
         "quoted charset should be unquoted");
   end Test_Charset_Parses_Quoted_Value;

   procedure Test_Charset_Parameter_Name_Is_Case_Insensitive
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: text/plain; Charset=UTF-8" & CRLF,
                Response);
      Assert
        (Http_Client.Responses.Has_Charset (Response),
         "mixed-case charset parameter should be present");
      Assert
        (Http_Client.Responses.Charset (Response) = "UTF-8",
         "charset value casing should be preserved");
   end Test_Charset_Parameter_Name_Is_Case_Insensitive;

   procedure Test_Charset_Parses_After_Other_Parameters
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok
        ("Content-Type: text/plain; format=flowed; charset=iso-8859-1"
         & CRLF,
         Response);
      Assert
        (Http_Client.Responses.Has_Charset (Response),
         "charset should be found after unrelated parameters");
      Assert
        (Http_Client.Responses.Charset (Response) = "iso-8859-1",
         "charset after unrelated parameters should be returned");
   end Test_Charset_Parses_After_Other_Parameters;

   procedure Test_Missing_Content_Type_Is_Empty_And_Not_Present
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("X-Test: abc" & CRLF, Response);
      Assert
        (not Http_Client.Responses.Has_Content_Type (Response),
         "missing Content-Type should not be present");
      Assert
        (Http_Client.Responses.Content_Type (Response) = "",
         "missing Content_Type should return empty string");
      Assert
        (Http_Client.Responses.Media_Type (Response) = "",
         "missing Media_Type should return empty string");
      Assert
        (not Http_Client.Responses.Has_Charset (Response),
         "missing charset should not be present");
      Assert
        (Http_Client.Responses.Charset (Response) = "",
         "missing charset should return empty string");
   end Test_Missing_Content_Type_Is_Empty_And_Not_Present;

   procedure Test_Malformed_Charset_Is_Absent
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("Content-Type: text/plain; charset" & CRLF, Response);
      Assert
        (not Http_Client.Responses.Has_Charset (Response),
         "charset without equals should be absent");
      Assert
        (Http_Client.Responses.Charset (Response) = "",
         "charset without equals should return empty string");

      Parse_Ok ("Content-Type: text/plain; charset=" & CRLF, Response);
      Assert
        (not Http_Client.Responses.Has_Charset (Response),
         "empty charset should be absent");
      Assert
        (Http_Client.Responses.Charset (Response) = "",
         "empty charset should return empty string");

      Parse_Ok ("Content-Type: text/plain; charset=""""" & CRLF,
                Response);
      Assert
        (not Http_Client.Responses.Has_Charset (Response),
         "empty quoted charset should be absent");
      Assert
        (Http_Client.Responses.Charset (Response) = "",
         "empty quoted charset should return empty string");
   end Test_Malformed_Charset_Is_Absent;

   procedure Test_Generic_Response_Header_Wrapper_Returns_Value
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("X-Test: abc" & CRLF, Response);
      Assert
        (Http_Client.Responses.Has_Header (Response, "X-Test"),
         "generic response header wrapper should report present header");
      Assert
        (Http_Client.Responses.Header (Response, "X-Test") = "abc",
         "generic response header wrapper should return value");
   end Test_Generic_Response_Header_Wrapper_Returns_Value;

   procedure Test_Generic_Response_Header_Wrapper_Absent
     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (Case_Context);
      Response : Http_Client.Responses.Response;
   begin
      Parse_Ok ("X-Test: abc" & CRLF, Response);
      Assert
        (not Http_Client.Responses.Has_Header (Response, "X-Missing"),
         "generic response header wrapper should report absence");
      Assert
        (Http_Client.Responses.Header (Response, "X-Missing") = "",
         "missing generic response header should return empty string");
   end Test_Generic_Response_Header_Wrapper_Absent;

   overriding
   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Responses");
   end Name;

   overriding
   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine
        (T,
         Test_Content_Type_Returns_Header_Value'Access,
         "Test_Content_Type_Returns_Header_Value");
      Register_Routine
        (T,
         Test_Content_Type_Header_Name_Is_Case_Insensitive'Access,
         "Test_Content_Type_Header_Name_Is_Case_Insensitive");
      Register_Routine
        (T,
         Test_Media_Type_Strips_Parameters'Access,
         "Test_Media_Type_Strips_Parameters");
      Register_Routine
        (T,
         Test_Media_Type_Trims_Optional_Whitespace'Access,
         "Test_Media_Type_Trims_Optional_Whitespace");
      Register_Routine
        (T,
         Test_Charset_Parses_Unquoted_Value'Access,
         "Test_Charset_Parses_Unquoted_Value");
      Register_Routine
        (T,
         Test_Charset_Parses_Quoted_Value'Access,
         "Test_Charset_Parses_Quoted_Value");
      Register_Routine
        (T,
         Test_Charset_Parameter_Name_Is_Case_Insensitive'Access,
         "Test_Charset_Parameter_Name_Is_Case_Insensitive");
      Register_Routine
        (T,
         Test_Charset_Parses_After_Other_Parameters'Access,
         "Test_Charset_Parses_After_Other_Parameters");
      Register_Routine
        (T,
         Test_Missing_Content_Type_Is_Empty_And_Not_Present'Access,
         "Test_Missing_Content_Type_Is_Empty_And_Not_Present");
      Register_Routine
        (T,
         Test_Malformed_Charset_Is_Absent'Access,
         "Test_Malformed_Charset_Is_Absent");
      Register_Routine
        (T,
         Test_Generic_Response_Header_Wrapper_Returns_Value'Access,
         "Test_Generic_Response_Header_Wrapper_Returns_Value");
      Register_Routine
        (T,
         Test_Generic_Response_Header_Wrapper_Absent'Access,
         "Test_Generic_Response_Header_Wrapper_Absent");
   end Register_Tests;
end Http_Client.Responses.Tests;
