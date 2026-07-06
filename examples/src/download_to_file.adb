with Ada.Text_IO;

with Http_Client.Clients;
with Http_Client.Errors;

procedure Download_To_File is
   use type Http_Client.Errors.Result_Status;

   Result  : Http_Client.Clients.Download_Result;
   Options : Http_Client.Clients.Download_Options :=
     Http_Client.Clients.Default_Download_Options;
   Status  : Http_Client.Errors.Result_Status;
begin
   Options.Max_Download_Size :=
     Http_Client.Clients.Default_Max_Download_Size;
   Options.File_Mode := Http_Client.Clients.Replace_Atomically;
   Options.Create_Parent_Dirs := True;

   Status :=
     Http_Client.Clients.Download_To_File
       (URL     => "https://example.com/file.bin",
        Path    => "downloads/file.bin",
        Result  => Result,
        Options => Options);

   if Status = Http_Client.Errors.Ok then
      Ada.Text_IO.Put_Line
        ("downloaded" & Natural'Image (Result.Bytes_Written) & " bytes");
   else
      Ada.Text_IO.Put_Line ("download failed: " & Status'Image);
   end if;
end Download_To_File;
