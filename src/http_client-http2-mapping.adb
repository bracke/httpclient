with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;

with Http_Client.URI;
with Http_Client.Request_Bodies;

package body Http_Client.HTTP2.Mapping is
   use type Http_Client.Errors.Result_Status;

   function Lower (S : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (S);
   end Lower;

   function Is_Forbidden_Connection_Header (Name : String) return Boolean is
      L : constant String := Lower (Name);
   begin
      return L = "connection"
        or else L = "keep-alive"
        or else L = "proxy-connection"
        or else L = "transfer-encoding"
        or else L = "te"
        or else L = "trailer"
        or else L = "upgrade";
   end Is_Forbidden_Connection_Header;

   function Is_Pseudo (Name : String) return Boolean is
   begin
      return Name'Length > 0 and then Name (Name'First) = ':';
   end Is_Pseudo;

   function Trim_OWS (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trim_OWS;

   function Is_HTTP2_Dropped_Compatibility_Header
     (Name  : String;
      Value : String) return Boolean
   is
      L : constant String := Lower (Name);
      V : constant String := Lower (Trim_OWS (Value));
   begin
      --  These fields may be synthesized by the HTTP/1.1 request preparation
      --  layer or supplied for HTTP/1.1 compatibility.  They are connection-
      --  specific and therefore must not appear on the HTTP/2 wire.  Dropping
      --  the harmless compatibility forms here prevents a valid h2 request
      --  from being reset by strict peers merely because the temporary wire
      --  request was prepared through the HTTP/1.1 serializer first.
      if L = "expect" and then V = "100-continue" then
         return True;
      elsif L = "connection" and then V = "close" then
         return True;
      elsif L = "keep-alive" or else L = "proxy-connection" then
         return True;
      else
         return False;
      end if;
   end Is_HTTP2_Dropped_Compatibility_Header;

   function Is_Allowed_TE_Header (Value : String) return Boolean is
   begin
      return Lower (Trim_OWS (Value)) = "trailers";
   end Is_Allowed_TE_Header;

   function Add_Checked
     (List  : in out Http_Client.Headers.Header_List;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status
   is
   begin
      if Is_Pseudo (Name) then
         return Http_Client.Headers.Add_HTTP2_Pseudo (List, Name, Value);
      else
         return Http_Client.Headers.Add (List, Name, Value);
      end if;
   end Add_Checked;

   function Build_Request_Headers
     (Request : Http_Client.Requests.Request;
      Output  : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status
   is
      URI     : constant Http_Client.URI.URI_Reference :=
        Http_Client.Requests.URI (Request);
      Source  : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Status  : Http_Client.Errors.Result_Status;
   begin
      Output := Http_Client.Headers.Empty;

      if not Http_Client.Requests.Is_Valid (Request)
        or else not Http_Client.URI.Is_Parsed (URI)
      then
         return Http_Client.Errors.Invalid_Request;
      elsif Http_Client.Request_Bodies.Has_Trailers
              (Http_Client.Requests.Request_Body (Request))
      then
         return Http_Client.Errors.Unsupported_Feature;
      end if;

      Status := Add_Checked
        (Output, ":method", Http_Client.Requests.Method_Image
           (Http_Client.Requests.Method (Request)));
      if Status /= Http_Client.Errors.Ok then return Status; end if;

      Status := Add_Checked (Output, ":scheme", Http_Client.URI.Scheme (URI));
      if Status /= Http_Client.Errors.Ok then return Status; end if;

      Status := Add_Checked
        (Output, ":path", Http_Client.URI.Request_Target (URI));
      if Status /= Http_Client.Errors.Ok then return Status; end if;

      Status := Add_Checked
        (Output, ":authority", Http_Client.URI.Host_Header_Value (URI));
      if Status /= Http_Client.Errors.Ok then return Status; end if;

      for I in 1 .. Http_Client.Headers.Length (Source) loop
         declare
            Original_Name : constant String := Http_Client.Headers.Name_At (Source, I);
            Lower_Name    : constant String := Lower (Original_Name);
            Value         : constant String := Http_Client.Headers.Value_At (Source, I);
         begin
            if Lower_Name = "host" then
               null;
            elsif Is_HTTP2_Dropped_Compatibility_Header (Lower_Name, Value) then
               null;
            elsif Lower_Name = "expect" then
               return Http_Client.Errors.Invalid_Header;
            elsif Lower_Name = "te" and then Is_Allowed_TE_Header (Value) then
               Status := Add_Checked (Output, Lower_Name, "trailers");
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            elsif Is_Forbidden_Connection_Header (Lower_Name) then
               return Http_Client.Errors.Invalid_Header;
            elsif Is_Pseudo (Original_Name) then
               return Http_Client.Errors.Invalid_Header;
            else
               Status := Add_Checked (Output, Lower_Name, Value);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;
         end;
      end loop;

      return Validate_Request_Headers (Output);
   end Build_Request_Headers;

   function Validate_Request_Headers
     (Headers : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status
   is
      Saw_Regular : Boolean := False;
      M, S, A, P  : Natural := 0;
   begin
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         declare
            Name : constant String := Http_Client.Headers.Name_At (Headers, I);
            L    : constant String := Lower (Name);
         begin
            if Name /= L then
               return Http_Client.Errors.Invalid_Header;
            end if;

            if Is_Pseudo (Name) then
               if Saw_Regular then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
               if Name = ":method" then M := M + 1;
               elsif Name = ":scheme" then S := S + 1;
               elsif Name = ":authority" then A := A + 1;
               elsif Name = ":path" then P := P + 1;
               else return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
            else
               Saw_Regular := True;
               if Name = "te" then
                  if not Is_Allowed_TE_Header
                    (Http_Client.Headers.Value_At (Headers, I))
                  then
                     return Http_Client.Errors.Invalid_Header;
                  end if;
               elsif Is_Forbidden_Connection_Header (Name) then
                  return Http_Client.Errors.Invalid_Header;
               end if;
            end if;
         end;
      end loop;

      if M /= 1 or else S /= 1 or else A /= 1 or else P /= 1 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      return Http_Client.Errors.Ok;
   end Validate_Request_Headers;

   function Parse_Status
     (Headers : Http_Client.Headers.Header_List;
      Status  : out Http_Client.Types.Status_Code)
      return Http_Client.Errors.Result_Status
   is
      Count : Natural := 0;
      Value : String (1 .. 3);
   begin
      Status := 500;
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         declare
            Name : constant String := Http_Client.Headers.Name_At (Headers, I);
            V    : constant String := Http_Client.Headers.Value_At (Headers, I);
         begin
            if Name = ":status" then
               Count := Count + 1;
               if V'Length /= 3 then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
               Value := V;
            elsif Is_Pseudo (Name) then
               return Http_Client.Errors.HTTP2_Protocol_Error;
            end if;
         end;
      end loop;

      if Count /= 1 then
         return Http_Client.Errors.HTTP2_Protocol_Error;
      end if;

      for C of Value loop
         if C not in '0' .. '9' then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
      end loop;

      declare
         N : constant Natural :=
           (Character'Pos (Value (1)) - Character'Pos ('0')) * 100 +
           (Character'Pos (Value (2)) - Character'Pos ('0')) * 10 +
           (Character'Pos (Value (3)) - Character'Pos ('0'));
      begin
         if N < 100 or else N > 599 then
            return Http_Client.Errors.HTTP2_Protocol_Error;
         end if;
         Status := Http_Client.Types.Status_Code (N);
      end;

      return Http_Client.Errors.Ok;
   end Parse_Status;

   function Validate_Response_Headers
     (Headers : Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status
   is
      Saw_Regular : Boolean := False;
      Code        : Http_Client.Types.Status_Code;
      Status      : Http_Client.Errors.Result_Status;
   begin
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         declare
            Name : constant String := Http_Client.Headers.Name_At (Headers, I);
            L    : constant String := Lower (Name);
         begin
            if Name /= L then
               return Http_Client.Errors.Invalid_Header;
            end if;

            if Is_Pseudo (Name) then
               if Saw_Regular or else Name /= ":status" then
                  return Http_Client.Errors.HTTP2_Protocol_Error;
               end if;
            else
               Saw_Regular := True;
               if Is_Forbidden_Connection_Header (Name) then
                  return Http_Client.Errors.Invalid_Header;
               end if;
            end if;
         end;
      end loop;

      Status := Parse_Status (Headers, Code);
      return Status;
   end Validate_Response_Headers;
end Http_Client.HTTP2.Mapping;
