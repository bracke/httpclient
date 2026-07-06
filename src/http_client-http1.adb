with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Request_Bodies; use Http_Client.Request_Bodies;
with Http_Client.URI;

package body Http_Client.HTTP1 is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   function Parse_Content_Length
     (Text  : String;
      Value : out Natural) return Boolean
   is
      Accumulator : Natural := 0;
   begin
      Value := 0;

      if Text'Length = 0 then
         return False;
      end if;

      for C of Text loop
         if C not in '0' .. '9' then
            return False;
         end if;

         declare
            Digit : constant Natural :=
              Character'Pos (C) - Character'Pos ('0');
         begin
            if Accumulator > (Natural'Last - Digit) / 10 then
               return False;
            end if;

            Accumulator := Accumulator * 10 + Digit;
         end;
      end loop;

      Value := Accumulator;
      return True;
   end Parse_Content_Length;


   function Trimmed_Lower (Text : String) return String is
      First : Natural := Text'First;
      Last  : Natural := Text'Last;
   begin
      if Text'Length = 0 then
         return "";
      end if;

      while First <= Text'Last
        and then (Text (First) = ' ' or else Text (First) = Character'Val (9))
      loop
         First := First + 1;
      end loop;

      while Last >= First
        and then (Text (Last) = ' ' or else Text (Last) = Character'Val (9))
      loop
         Last := Last - 1;
      end loop;

      if First > Last then
         return "";
      end if;

      declare
         Result : String (1 .. Last - First + 1);
      begin
         for I in First .. Last loop
            Result (I - First + 1) :=
              Ada.Characters.Handling.To_Lower (Text (I));
         end loop;
         return Result;
      end;
   end Trimmed_Lower;

   function Is_Chunked_Transfer_Encoding (Text : String) return Boolean is
   begin
      return Trimmed_Lower (Text) = "chunked";
   end Is_Chunked_Transfer_Encoding;

   function Is_Expect_100_Continue (Text : String) return Boolean is
   begin
      return Trimmed_Lower (Text) = "100-continue";
   end Is_Expect_100_Continue;


   function Is_Forbidden_Trailer_Name (Name : String) return Boolean is
      Key : constant String := Trimmed_Lower (Name);
   begin
      return Key = "host"
        or else Key = "content-length"
        or else Key = "transfer-encoding"
        or else Key = "trailer"
        or else Key = "connection"
        or else Key = "keep-alive"
        or else Key = "te"
        or else Key = "upgrade"
        or else Key = "expect"
        or else Key = "authorization"
        or else Key = "proxy-authorization"
        or else Key = "cookie"
        or else Key = "cookie2";
   end Is_Forbidden_Trailer_Name;

   function Token_List_Contains
     (List_Text : String;
      Name      : String) return Boolean
   is
      Target : constant String := Trimmed_Lower (Name);
      First  : Natural := List_Text'First;
   begin
      if List_Text'Length = 0 then
         return False;
      end if;

      while First <= List_Text'Last loop
         declare
            Last : Natural := First;
         begin
            while Last <= List_Text'Last and then List_Text (Last) /= ',' loop
               Last := Last + 1;
            end loop;

            if Last > First
              and then Trimmed_Lower (List_Text (First .. Last - 1)) = Target
            then
               return True;
            end if;

            First := Last + 1;
         end;
      end loop;

      return False;
   end Token_List_Contains;

   function Trailer_Names_Image
     (Trailers : Http_Client.Headers.Header_List) return String
   is
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      for Index in 1 .. Http_Client.Headers.Length (Trailers) loop
         if Index > 1 then
            Append (Result, ", ");
         end if;
         Append (Result, Http_Client.Headers.Name_At (Trailers, Index));
      end loop;
      return To_String (Result);
   end Trailer_Names_Image;

   function Trailer_Fields_Are_Valid
     (Trailers : Http_Client.Headers.Header_List) return Boolean
   is
   begin
      for Index in 1 .. Http_Client.Headers.Length (Trailers) loop
         declare
            Name  : constant String := Http_Client.Headers.Name_At (Trailers, Index);
            Value : constant String := Http_Client.Headers.Value_At (Trailers, Index);
         begin
            if not Http_Client.Headers.Is_Valid_Name (Name)
              or else not Http_Client.Headers.Is_Valid_Value (Value)
              or else Is_Forbidden_Trailer_Name (Name)
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Trailer_Fields_Are_Valid;

   function Declared_Trailers_Cover_All
     (Declaration : String;
      Trailers    : Http_Client.Headers.Header_List) return Boolean
   is
   begin
      for Index in 1 .. Http_Client.Headers.Length (Trailers) loop
         if not Token_List_Contains
                  (Declaration, Http_Client.Headers.Name_At (Trailers, Index))
         then
            return False;
         end if;
      end loop;
      return True;
   end Declared_Trailers_Cover_All;

   function Headers_Are_Safe
     (Headers : Http_Client.Headers.Header_List) return Boolean
   is
   begin
      for Index in 1 .. Http_Client.Headers.Length (Headers) loop
         if not Http_Client.Headers.Is_Valid_Name
                  (Http_Client.Headers.Name_At (Headers, Index))
           or else not Http_Client.Headers.Is_Valid_Value
                  (Http_Client.Headers.Value_At (Headers, Index))
         then
            return False;
         end if;
      end loop;

      return True;
   end Headers_Are_Safe;

   function Serialize_Headers
     (Request : Http_Client.Requests.Request;
      Output  : out Ada.Strings.Unbounded.Unbounded_String;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return Http_Client.Errors.Result_Status
   is
      Headers          : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Req_Body         : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
      Body_Length      : Natural := 0;
      Has_Known_Length : Boolean := False;
      Has_Explicit_CL  : constant Boolean :=
        Http_Client.Headers.Contains (Headers, "Content-Length");
      Has_TE           : constant Boolean :=
        Http_Client.Headers.Contains (Headers, "Transfer-Encoding");
      Has_Trailer_Hdr  : constant Boolean :=
        Http_Client.Headers.Contains (Headers, "Trailer");
      Has_Body_Trailers : constant Boolean :=
        Http_Client.Request_Bodies.Has_Trailers (Req_Body);
      Body_Trailers    : constant Http_Client.Headers.Header_List :=
        Http_Client.Request_Bodies.Trailers (Req_Body);
      Content_Length   : Natural := 0;
      Host_Count       : constant Natural :=
        Http_Client.Headers.Count (Headers, "Host");
      Result           : Unbounded_String := Null_Unbounded_String;

      function Absolute_Request_Target return String is
         URI : constant Http_Client.URI.URI_Reference :=
           Http_Client.Requests.URI (Request);
         Prefix : constant String :=
           Http_Client.URI.Scheme (URI) & "://" & Http_Client.URI.Authority_Host (URI);
         Port_Image : constant String :=
           Natural'Image (Natural (Http_Client.URI.Effective_Port (URI)));
      begin
         if Http_Client.URI.Has_Explicit_Port (URI)
           and then not
             ((Http_Client.URI.Scheme (URI) = "http"
               and then Http_Client.URI.Effective_Port (URI) = 80)
              or else
              (Http_Client.URI.Scheme (URI) = "https"
               and then Http_Client.URI.Effective_Port (URI) = 443))
         then
            return Prefix & ":" &
              Port_Image (Port_Image'First + 1 .. Port_Image'Last) &
              Http_Client.Requests.Request_Target (Request);
         else
            return Prefix & Http_Client.Requests.Request_Target (Request);
         end if;
      end Absolute_Request_Target;
   begin
      Output := Null_Unbounded_String;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Invalid_Request;
      end if;

      if not Headers_Are_Safe (Headers) then
         return Invalid_Header;
      end if;

      if Host_Count > 1 then
         return Invalid_Header;
      end if;

      if Host_Count = 1
        and then Http_Client.Headers.Get (Headers, "Host")'Length = 0
      then
         return Invalid_Header;
      end if;

      if Http_Client.Headers.Count (Headers, "Content-Length") > 1
        or else Http_Client.Headers.Count (Headers, "Transfer-Encoding") > 1
        or else Http_Client.Headers.Count (Headers, "Trailer") > 1
        or else Http_Client.Headers.Count (Headers, "Expect") > 1
      then
         return Invalid_Header;
      end if;

      if Http_Client.Headers.Contains (Headers, "Expect")
        and then not Is_Expect_100_Continue
          (Http_Client.Headers.Get (Headers, "Expect"))
      then
         return Unsupported_Feature;
      end if;

      if Has_TE and then Has_Explicit_CL then
         return Protocol_Error;
      end if;

      if not Http_Client.Request_Bodies.Has_Producer (Req_Body) then
         return Invalid_Request;
      end if;

      Has_Known_Length :=
        Http_Client.Request_Bodies.Declared_Length (Req_Body, Body_Length);

      if Has_Body_Trailers then
         if Http_Client.Request_Bodies.Kind (Req_Body)
              /= Http_Client.Request_Bodies.Unknown_Length_Stream
         then
            return Protocol_Error;
         elsif not Trailer_Fields_Are_Valid (Body_Trailers) then
            return Invalid_Header;
         end if;
      end if;

      if Has_Trailer_Hdr then
         if Http_Client.Headers.Get (Headers, "Trailer")'Length = 0 then
            return Invalid_Header;
         elsif Has_Known_Length or else not Has_Body_Trailers then
            return Protocol_Error;
         elsif not Declared_Trailers_Cover_All
                    (Http_Client.Headers.Get (Headers, "Trailer"), Body_Trailers)
         then
            return Invalid_Header;
         end if;
      end if;

      if Has_TE then
         if not Is_Chunked_Transfer_Encoding
                  (Http_Client.Headers.Get (Headers, "Transfer-Encoding"))
         then
            return Unsupported_Feature;
         end if;

         if Has_Known_Length then
            return Protocol_Error;
         end if;
      end if;

      if Has_Explicit_CL then
         if not Has_Known_Length then
            return Protocol_Error;
         elsif not Parse_Content_Length
                  (Http_Client.Headers.Get (Headers, "Content-Length"),
                   Content_Length)
         then
            return Invalid_Header;
         end if;

         if Content_Length /= Body_Length then
            return Protocol_Error;
         end if;
      end if;

      Append
        (Result,
         Http_Client.Requests.Method_Image
           (Http_Client.Requests.Method (Request)));
      Append (Result, " ");
      if Target_Mode = Absolute_Form then
         Append (Result, Absolute_Request_Target);
      else
         Append (Result, Http_Client.Requests.Request_Target (Request));
      end if;
      Append (Result, " HTTP/1.1");
      Append (Result, CRLF);

      for Index in 1 .. Http_Client.Headers.Length (Headers) loop
         Append (Result, Http_Client.Headers.Name_At (Headers, Index));
         Append (Result, ": ");
         Append (Result, Http_Client.Headers.Value_At (Headers, Index));
         Append (Result, CRLF);
      end loop;

      if Host_Count = 0 then
         Append (Result, "Host: ");
         Append (Result, Http_Client.Requests.Host_Header_Value (Request));
         Append (Result, CRLF);
      end if;

      if Has_Known_Length and then Body_Length > 0
        and then not Has_Explicit_CL and then not Has_TE
      then
         Append (Result, "Content-Length: ");
         Append (Result, Decimal_Image (Body_Length));
         Append (Result, CRLF);
      elsif not Has_Known_Length and then not Has_TE then
         Append (Result, "Transfer-Encoding: chunked");
         Append (Result, CRLF);
      end if;

      if Has_Body_Trailers and then not Has_Trailer_Hdr then
         Append (Result, "Trailer: ");
         Append (Result, Trailer_Names_Image (Body_Trailers));
         Append (Result, CRLF);
      end if;

      Append (Result, CRLF);

      Output := Result;
      return Ok;
   end Serialize_Headers;

   function Serialize_Request
     (Request : Http_Client.Requests.Request;
      Output  : out Ada.Strings.Unbounded.Unbounded_String;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return Http_Client.Errors.Result_Status
   is
      Headers_Text : Unbounded_String := Null_Unbounded_String;
      Status       : Http_Client.Errors.Result_Status;
      Req_Body     : constant Http_Client.Request_Bodies.Request_Body :=
        Http_Client.Requests.Request_Body (Request);
   begin
      Output := Null_Unbounded_String;

      Status := Serialize_Headers (Request, Headers_Text, Target_Mode);
      if Status /= Ok then
         return Status;
      end if;

      case Http_Client.Request_Bodies.Kind (Req_Body) is
         when Http_Client.Request_Bodies.Empty_Body =>
            Output := Headers_Text;
         when Http_Client.Request_Bodies.Buffered_Body =>
            Output := Headers_Text;
            Append (Output, Http_Client.Request_Bodies.Buffered_Payload (Req_Body));
         when Http_Client.Request_Bodies.Fixed_Length_Stream |
              Http_Client.Request_Bodies.Unknown_Length_Stream =>
            return Invalid_Request;
      end case;

      return Ok;
   end Serialize_Request;

   function Serialize_Request
     (Request : Http_Client.Requests.Request;
      Target_Mode : Request_Target_Mode := Origin_Form)
      return String
   is
      Output : Unbounded_String;
      Status : constant Http_Client.Errors.Result_Status :=
        Serialize_Request (Request, Output, Target_Mode);
   begin
      if Status /= Ok then
         return "";
      end if;

      return To_String (Output);
   end Serialize_Request;

end Http_Client.HTTP1;
