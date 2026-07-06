with Ada.Directories; use Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Requests;

package body Http_Client.Multipart is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Boundary_Counter : Natural := 0;

   function Decimal_Padded (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
      Raw   : constant String := Image (Image'First + 1 .. Image'Last);
      Result : String (1 .. 8) := (others => '0');
   begin
      if Raw'Length >= Result'Length then
         return Raw (Raw'Last - Result'Length + 1 .. Raw'Last);
      else
         Result (Result'Last - Raw'Length + 1 .. Result'Last) := Raw;
         return Result;
      end if;
   end Decimal_Padded;

   function Generated_Boundary return String is
   begin
      Boundary_Counter := Boundary_Counter + 1;
      return "AdaHttpClientMultipartBoundary" & Decimal_Padded (Boundary_Counter);
   end Generated_Boundary;

   function Is_Visible_ASCII (C : Character) return Boolean is
   begin
      return Character'Pos (C) >= 33 and then Character'Pos (C) <= 126;
   end Is_Visible_ASCII;

   function Is_Safe_Parameter (Text : String; Limit : Natural) return Boolean is
   begin
      if Text'Length = 0 or else Text'Length > Limit then
         return False;
      end if;

      for C of Text loop
         if not Is_Visible_ASCII (C)
           or else C = '"'
           or else Character'Pos (C) = 92
           or else C = ';'
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Safe_Parameter;

   function Is_Valid_Content_Type (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return True;
      end if;

      if Text'Length > Max_Content_Type_Length then
         return False;
      end if;

      return Http_Client.Headers.Is_Valid_Value (Text);
   end Is_Valid_Content_Type;

   function Checked_Add (Left : Natural; Right : Natural; Result : out Natural) return Boolean is
   begin
      if Left > Natural'Last - Right then
         Result := 0;
         return False;
      end if;

      Result := Left + Right;
      return True;
   end Checked_Add;

   function Contains_Sequence (Haystack : String; Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Haystack'Length < Needle'Length then
         return False;
      end if;

      for Offset in 0 .. Haystack'Length - Needle'Length loop
         if Haystack
              (Haystack'First + Offset ..
               Haystack'First + Offset + Needle'Length - 1) = Needle
         then
            return True;
         end if;
      end loop;

      return False;
   end Contains_Sequence;

   function Contains_Boundary_Marker
     (Text : String; Boundary : String) return Boolean
   is
   begin
      return Contains_Sequence (Text, "--" & Boundary);
   end Contains_Boundary_Marker;

   procedure Reset_Cursor (Form : in out Multipart_Form) is
   begin
      Form.Read_Part := 1;
      Form.Stage := At_Part_Prefix;
      Form.Fragment := Null_Unbounded_String;
      Form.Fragment_Pos := 1;
      Form.Data_Pos := 1;
   end Reset_Cursor;

   function Part_Header (Form : Multipart_Form; Part : Multipart_Part) return String is
      pragma Unreferenced (Form);
      Result : Unbounded_String := Null_Unbounded_String;
   begin
      Append (Result, "Content-Disposition: form-data; name=""");
      Append (Result, To_String (Part.Name));
      Append (Result, """");

      if Part.Has_Filename then
         Append (Result, "; filename=""");
         Append (Result, To_String (Part.Filename));
         Append (Result, """");
      end if;

      Append (Result, CRLF);

      if Part.Has_Content_Type then
         Append (Result, "Content-Type: ");
         Append (Result, To_String (Part.Part_Type));
         Append (Result, CRLF);
      end if;

      Append (Result, CRLF);
      return To_String (Result);
   end Part_Header;

   function Part_Prefix (Form : Multipart_Form; Part : Multipart_Part) return String is
   begin
      return "--" & To_String (Form.Boundary_Text) & CRLF & Part_Header (Form, Part);
   end Part_Prefix;

   function Final_Boundary (Form : Multipart_Form) return String is
   begin
      return "--" & To_String (Form.Boundary_Text) & "--" & CRLF;
   end Final_Boundary;

   function Validate_Part_Common
     (Form         : Multipart_Form;
      Name         : String;
      Filename     : String;
      Content_Type : String) return Http_Client.Errors.Result_Status
   is
      Header_Length : Natural;
      Dummy_Part    : Multipart_Part;
   begin
      if Natural (Form.Parts.Length) >= Max_Part_Count then
         return Too_Many_Parts;
      end if;

      if not Is_Safe_Parameter (Name, Max_Field_Name_Length) then
         return Invalid_Form_Field;
      end if;

      if Filename'Length > 0
        and then not Is_Safe_Parameter (Filename, Max_File_Name_Length)
      then
         return Invalid_File_Name;
      end if;

      if not Is_Valid_Content_Type (Content_Type) then
         return Invalid_Header;
      end if;

      Dummy_Part.Name := To_Unbounded_String (Name);
      Dummy_Part.Has_Filename := Filename'Length > 0;
      Dummy_Part.Filename := To_Unbounded_String (Filename);
      Dummy_Part.Has_Content_Type := Content_Type'Length > 0;
      Dummy_Part.Part_Type := To_Unbounded_String (Content_Type);
      Header_Length := Part_Prefix (Form, Dummy_Part)'Length;

      if Header_Length > Max_Part_Header_Length then
         return Header_Too_Large;
      end if;

      return Ok;
   end Validate_Part_Common;

   function Create return Multipart_Form is
   begin
      return Form : Multipart_Form do
         Form.Boundary_Text := To_Unbounded_String (Generated_Boundary);
      end return;
   end Create;

   procedure Clear (Form : in out Multipart_Form) is
   begin
      Form.Parts.Clear;
      Reset_Cursor (Form);
   end Clear;

   function Is_Valid_Boundary (Boundary : String) return Boolean is
   begin
      if Boundary'Length = 0 or else Boundary'Length > Max_Boundary_Length then
         return False;
      end if;

      for C of Boundary loop
         if not ((C in 'A' .. 'Z') or else (C in 'a' .. 'z')
                 or else (C in '0' .. '9') or else C = '-'
                 or else C = '_' or else C = '.')
         then
            return False;
         end if;
      end loop;

      return True;
   end Is_Valid_Boundary;

   function Set_Boundary
     (Form     : in out Multipart_Form;
      Boundary : String) return Http_Client.Errors.Result_Status is
   begin
      if not Is_Valid_Boundary (Boundary) then
         return Invalid_Multipart_Boundary;
      end if;

      for Part of Form.Parts loop
         if Part.Kind = Memory_Part
           and then Contains_Boundary_Marker (To_String (Part.Data), Boundary)
         then
            return Invalid_Multipart_Boundary;
         end if;
      end loop;

      Form.Boundary_Text := To_Unbounded_String (Boundary);
      Reset_Cursor (Form);
      return Ok;
   end Set_Boundary;

   function Boundary (Form : Multipart_Form) return String is
   begin
      return To_String (Form.Boundary_Text);
   end Boundary;

   function Content_Type (Form : Multipart_Form) return String is
   begin
      return "multipart/form-data; boundary=" & To_String (Form.Boundary_Text);
   end Content_Type;

   function Add_Field
     (Form  : in out Multipart_Form;
      Name  : String;
      Value : String) return Http_Client.Errors.Result_Status
   is
      Status : constant Result_Status := Validate_Part_Common (Form, Name, "", "");
      Part   : Multipart_Part;
   begin
      if Status /= Ok then
         return Status;
      end if;

      if Contains_Boundary_Marker (Value, To_String (Form.Boundary_Text)) then
         return Invalid_Multipart_Boundary;
      end if;

      Part.Kind := Memory_Part;
      Part.Name := To_Unbounded_String (Name);
      Part.Data := To_Unbounded_String (Value);
      Part.Length := Value'Length;
      Form.Parts.Append (Part);
      Reset_Cursor (Form);
      return Ok;
   end Add_Field;

   function Add_Binary_Part
     (Form         : in out Multipart_Form;
      Name         : String;
      Data         : String;
      Filename     : String := "";
      Content_Type : String := "") return Http_Client.Errors.Result_Status
   is
      Status : constant Result_Status :=
        Validate_Part_Common (Form, Name, Filename, Content_Type);
      Part   : Multipart_Part;
   begin
      if Status /= Ok then
         return Status;
      end if;

      if Contains_Boundary_Marker (Data, To_String (Form.Boundary_Text)) then
         return Invalid_Multipart_Boundary;
      end if;

      Part.Kind := Memory_Part;
      Part.Name := To_Unbounded_String (Name);
      Part.Has_Filename := Filename'Length > 0;
      Part.Filename := To_Unbounded_String (Filename);
      Part.Has_Content_Type := Content_Type'Length > 0;
      Part.Part_Type := To_Unbounded_String (Content_Type);
      Part.Data := To_Unbounded_String (Data);
      Part.Length := Data'Length;
      Form.Parts.Append (Part);
      Reset_Cursor (Form);
      return Ok;
   end Add_Binary_Part;

   function Add_File
     (Form         : in out Multipart_Form;
      Name         : String;
      Path         : String;
      Filename     : String := "";
      Content_Type : String := "") return Http_Client.Errors.Result_Status
   is
      Status : constant Result_Status :=
        Validate_Part_Common (Form, Name, Filename, Content_Type);
      Size   : Ada.Directories.File_Size;
      Part   : Multipart_Part;
   begin
      if Status /= Ok then
         return Status;
      end if;

      if Path'Length = 0
        or else not Ada.Directories.Exists (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
      then
         return Invalid_Request;
      end if;

      Size := Ada.Directories.Size (Path);
      if Size > Ada.Directories.File_Size (Natural'Last) then
         return Upload_Too_Large;
      end if;

      Part.Kind := File_Part;
      Part.Name := To_Unbounded_String (Name);
      Part.Has_Filename := Filename'Length > 0;
      Part.Filename := To_Unbounded_String (Filename);
      Part.Has_Content_Type := Content_Type'Length > 0;
      Part.Part_Type := To_Unbounded_String (Content_Type);
      Part.Path := To_Unbounded_String (Path);
      Part.Length := Natural (Size);
      Form.Parts.Append (Part);
      Reset_Cursor (Form);
      return Ok;
   exception
      when others =>
         return Read_Failed;
   end Add_File;

   function Part_Count (Form : Multipart_Form) return Natural is
   begin
      return Natural (Form.Parts.Length);
   end Part_Count;

   function Set_Max_Encoded_Length
     (Form       : in out Multipart_Form;
      Max_Length : Natural) return Http_Client.Errors.Result_Status is
   begin
      Form.Max_Length := Max_Length;
      return Ok;
   end Set_Max_Encoded_Length;


   function Is_Replayable (Form : Multipart_Form) return Boolean is
   begin
      for Part of Form.Parts loop
         if Part.Kind = File_Part then
            if not Ada.Directories.Exists (To_String (Part.Path))
              or else Ada.Directories.Kind (To_String (Part.Path)) /=
                Ada.Directories.Ordinary_File
              or else Ada.Directories.Size (To_String (Part.Path)) /=
                Ada.Directories.File_Size (Part.Length)
            then
               return False;
            end if;
         end if;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Is_Replayable;

   function Content_Length
     (Form   : Multipart_Form;
      Length : out Natural) return Http_Client.Errors.Result_Status
   is
      Total : Natural := 0;
      Temp  : Natural := 0;
   begin
      Length := 0;

      for Part of Form.Parts loop
         if not Checked_Add (Total, Part_Prefix (Form, Part)'Length, Temp) then
            return Multipart_Too_Large;
         end if;
         Total := Temp;

         if not Checked_Add (Total, Part.Length, Temp) then
            return Multipart_Too_Large;
         end if;
         Total := Temp;

         if not Checked_Add (Total, CRLF'Length, Temp) then
            return Multipart_Too_Large;
         end if;
         Total := Temp;
      end loop;

      if not Checked_Add (Total, Final_Boundary (Form)'Length, Temp) then
         return Multipart_Too_Large;
      end if;

      if Temp > Form.Max_Length then
         return Multipart_Too_Large;
      end if;

      Length := Temp;
      return Ok;
   end Content_Length;

   procedure Append_File
     (Path   : String;
      Output : in out Unbounded_String;
      Status : out Result_Status)
   is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Status := Ok;
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         for I in Buffer'First .. Last loop
            Append (Output, Character'Val (Integer (Buffer (I))));
         end loop;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         Status := Read_Failed;
   end Append_File;

   function Render_Body
     (Form   : Multipart_Form;
      Output : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      Status : Result_Status := Ok;
   begin
      Output := Null_Unbounded_String;

      for Part of Form.Parts loop
         Append (Output, Part_Prefix (Form, Part));
         if Part.Kind = Memory_Part then
            Append (Output, To_String (Part.Data));
         else
            if not Ada.Directories.Exists (To_String (Part.Path))
              or else Ada.Directories.Size (To_String (Part.Path)) /=
                Ada.Directories.File_Size (Part.Length)
            then
               return Body_Length_Mismatch;
            end if;
            Append_File (To_String (Part.Path), Output, Status);
            if Status /= Ok then
               return Status;
            end if;
         end if;
         Append (Output, CRLF);
      end loop;

      Append (Output, Final_Boundary (Form));
      return Ok;
   exception
      when others =>
         Output := Null_Unbounded_String;
         return Read_Failed;
   end Render_Body;

   function To_Request_Body
     (Form : aliased in out Multipart_Form)
      return Http_Client.Request_Bodies.Request_Body
   is
      Body_Data   : Http_Client.Request_Bodies.Request_Body;
      Status : constant Result_Status := To_Request_Body (Form, Body_Data);
      pragma Unreferenced (Status);
   begin
      return Body_Data;
   end To_Request_Body;

   function To_Request_Body
     (Form : aliased in out Multipart_Form;
      Body_Data : out Http_Client.Request_Bodies.Request_Body)
      return Http_Client.Errors.Result_Status
   is
      Length : Natural := 0;
      Status : Result_Status := Content_Length (Form, Length);
   begin
      Body_Data := Http_Client.Request_Bodies.Empty;

      if Status /= Ok then
         return Status;
      end if;

      Body_Data := Http_Client.Request_Bodies.From_Fixed_Length_Stream
        (Producer   => Form'Unrestricted_Access,
         Length     => Length,
         Replayable => True);
      return Ok;
   end To_Request_Body;

   function Attach
     (Form                 : aliased in out Multipart_Form;
      Request              : Http_Client.Requests.Request;
      Result               : out Http_Client.Requests.Request;
      Replace_Content_Type : Boolean := False)
      return Http_Client.Errors.Result_Status
   is
      Headers : Http_Client.Headers.Header_List;
      Status  : Result_Status;
   begin
      Result := Http_Client.Requests.Default_Request;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Invalid_Request;
      end if;

      Headers := Http_Client.Requests.Headers (Request);
      if Http_Client.Headers.Contains (Headers, "Content-Type")
        and then not Replace_Content_Type
      then
         return Invalid_Header;
      end if;

      Status := Http_Client.Headers.Set (Headers, "Content-Type", Content_Type (Form));
      if Status /= Ok then
         return Status;
      end if;

      --  The encoded length belongs to the multipart body now. Drop any stale
      --  caller-supplied framing headers so the HTTP/1.1 serializer can add
      --  the exact Content-Length for the generated body.
      Status := Http_Client.Headers.Remove (Headers, "Content-Length");
      if Status /= Ok then
         return Status;
      end if;

      Status := Http_Client.Headers.Remove (Headers, "Transfer-Encoding");
      if Status /= Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Create
        (Method    => Http_Client.Requests.Method (Request),
         URI       => Http_Client.Requests.URI (Request),
         Item      => Result,
         Headers   => Headers,
         Payload   => "",
         Auto_Host => False);
      if Status /= Ok then
         return Status;
      end if;

      declare
         Body_Data : Http_Client.Request_Bodies.Request_Body;
      begin
         Status := To_Request_Body (Form, Body_Data);
         if Status /= Ok then
            Result := Http_Client.Requests.Default_Request;
            return Status;
         end if;

         return Http_Client.Requests.Set_Body (Result, Body_Data);
      end;
   end Attach;

   procedure Prepare_Fragment (Form : in out Multipart_Form; Text : String) is
   begin
      Form.Fragment := To_Unbounded_String (Text);
      Form.Fragment_Pos := 1;
   end Prepare_Fragment;

   procedure Copy_Fragment
     (Form   : in out Multipart_Form;
      Buffer : out String;
      Count  : in out Natural)
   is
      Text      : constant String := To_String (Form.Fragment);
      Available : Natural;
      Wanted    : Natural;
   begin
      if Form.Fragment_Pos > Text'Length then
         return;
      end if;

      Available := Text'Length - Form.Fragment_Pos + 1;
      Wanted := Natural'Min (Available, Buffer'Length - Count);
      Buffer (Buffer'First + Count .. Buffer'First + Count + Wanted - 1) :=
        Text (Form.Fragment_Pos .. Form.Fragment_Pos + Wanted - 1);
      Count := Count + Wanted;
      Form.Fragment_Pos := Form.Fragment_Pos + Wanted;
   end Copy_Fragment;

   function Copy_File_Data
     (Form   : in out Multipart_Form;
      Part   : Multipart_Part;
      Buffer : out String;
      Count  : in out Natural) return Result_Status
   is
      File      : Ada.Streams.Stream_IO.File_Type;
      Remaining : constant Natural := Part.Length - Form.Data_Pos + 1;
      Wanted    : constant Natural := Natural'Min (Remaining, Buffer'Length - Count);
   begin
      if Wanted = 0 then
         return Ok;
      end if;

      if not Ada.Directories.Exists (To_String (Part.Path))
        or else Ada.Directories.Size (To_String (Part.Path)) /=
          Ada.Directories.File_Size (Part.Length)
      then
         return Body_Length_Mismatch;
      end if;

      declare
         Elements  : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Wanted));
         Last      : Ada.Streams.Stream_Element_Offset;
      begin
         Ada.Streams.Stream_IO.Open
           (File, Ada.Streams.Stream_IO.In_File, To_String (Part.Path));
         Ada.Streams.Stream_IO.Set_Index
           (File, Ada.Streams.Stream_IO.Positive_Count (Form.Data_Pos));
         Ada.Streams.Stream_IO.Read (File, Elements, Last);
         Ada.Streams.Stream_IO.Close (File);

         if Natural (Last) /= Wanted then
            return Body_Length_Mismatch;
         end if;

         for I in Elements'First .. Last loop
            Buffer (Buffer'First + Count) := Character'Val (Integer (Elements (I)));
            Count := Count + 1;
            Form.Data_Pos := Form.Data_Pos + 1;
         end loop;
      end;

      return Ok;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         return Read_Failed;
   end Copy_File_Data;

   overriding function Read_Some
     (Form   : in out Multipart_Form;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status
   is
      Status : Result_Status;
   begin
      Count := 0;

      if Buffer'Length = 0 then
         return Ok;
      end if;

      while Count < Buffer'Length and then Form.Stage /= At_Done loop
         if Form.Stage = At_Part_Prefix then
            if Form.Read_Part > Natural (Form.Parts.Length) then
               Prepare_Fragment (Form, Final_Boundary (Form));
               Form.Stage := At_Final_Boundary;
            else
               if Length (Form.Fragment) = 0 then
                  Prepare_Fragment
                    (Form,
                     Part_Prefix (Form, Form.Parts (Positive (Form.Read_Part))));
               end if;

               Copy_Fragment (Form, Buffer, Count);
               if Form.Fragment_Pos > Length (Form.Fragment) then
                  Form.Fragment := Null_Unbounded_String;
                  Form.Fragment_Pos := 1;
                  Form.Stage := At_Part_Data;
               end if;
            end if;

         elsif Form.Stage = At_Part_Data then
            declare
               Part : constant Multipart_Part := Form.Parts (Positive (Form.Read_Part));
            begin
               if Part.Kind = Memory_Part then
                  declare
                     Data      : constant String := To_String (Part.Data);
                     Available : Natural := 0;
                     Wanted    : Natural := 0;
                  begin
                     if Form.Data_Pos <= Data'Length then
                        Available := Data'Length - Form.Data_Pos + 1;
                        Wanted := Natural'Min (Available, Buffer'Length - Count);
                        Buffer (Buffer'First + Count .. Buffer'First + Count + Wanted - 1) :=
                          Data (Form.Data_Pos .. Form.Data_Pos + Wanted - 1);
                        Count := Count + Wanted;
                        Form.Data_Pos := Form.Data_Pos + Wanted;
                     end if;
                  end;
               else
                  if Form.Data_Pos <= Part.Length then
                     Status := Copy_File_Data (Form, Part, Buffer, Count);
                     if Status /= Ok then
                        return Status;
                     end if;
                  end if;
               end if;

               if Form.Data_Pos > Part.Length then
                  Prepare_Fragment (Form, CRLF);
                  Form.Stage := At_Part_Trailing_CRLF;
               end if;
            end;

         elsif Form.Stage = At_Part_Trailing_CRLF then
            Copy_Fragment (Form, Buffer, Count);
            if Form.Fragment_Pos > Length (Form.Fragment) then
               Form.Read_Part := Form.Read_Part + 1;
               Form.Data_Pos := 1;
               Form.Fragment := Null_Unbounded_String;
               Form.Fragment_Pos := 1;
               Form.Stage := At_Part_Prefix;
            end if;

         elsif Form.Stage = At_Final_Boundary then
            Copy_Fragment (Form, Buffer, Count);
            if Form.Fragment_Pos > Length (Form.Fragment) then
               Form.Fragment := Null_Unbounded_String;
               Form.Fragment_Pos := 1;
               Form.Stage := At_Done;
            end if;
         end if;
      end loop;

      return Ok;
   exception
      when others =>
         Count := 0;
         return Part_Producer_Failed;
   end Read_Some;

   overriding function Reset
     (Form : in out Multipart_Form) return Http_Client.Errors.Result_Status is
   begin
      for Part of Form.Parts loop
         if Part.Kind = File_Part then
            if not Ada.Directories.Exists (To_String (Part.Path))
              or else Ada.Directories.Size (To_String (Part.Path)) /=
                Ada.Directories.File_Size (Part.Length)
            then
               return Body_Length_Mismatch;
            end if;
         end if;
      end loop;

      Reset_Cursor (Form);
      return Ok;
   exception
      when others =>
         return Read_Failed;
   end Reset;

end Http_Client.Multipart;
