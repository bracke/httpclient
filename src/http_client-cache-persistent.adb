with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Directories; use Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO; use Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;

with Http_Client.Crypto;
with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Requests;
with Http_Client.Resources;
with Http_Client.Responses;
with Http_Client.URI;
with Http_Client.Types;

package body Http_Client.Cache.Persistent is
   use Ada.Strings.Unbounded;
   use Http_Client.Requests;
   use Http_Client.Types;
   use type Http_Client.Errors.Result_Status;
   use type Ada.Calendar.Time;
   use type Interfaces.Unsigned_64;

   function Trim (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trim;

   function Method_Image (M : Http_Client.Types.Method_Name) return String is
   begin
      return Http_Client.Requests.Method_Image (M);
   end Method_Image;

   function Parse_Method
     (S : String; M : out Http_Client.Types.Method_Name) return Boolean is
   begin
      for V in Http_Client.Types.Method_Name loop
         if S = Method_Image (V) then
            M := V;
            return True;
         end if;
      end loop;
      M := Http_Client.Types.GET;
      return False;
   end Parse_Method;

   function Hex_Digit (N : Natural) return Character is
      Hexes : constant String := "0123456789abcdef";
   begin
      return Hexes (N + 1);
   end Hex_Digit;

   function Hash64 (S : String) return Interfaces.Unsigned_64 is
      H : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      P : constant Interfaces.Unsigned_64 := 16#100000001B3#;
   begin
      for C of S loop
         H := H xor Interfaces.Unsigned_64 (Character'Pos (C));
         H := H * P;
      end loop;
      return H;
   end Hash64;

   function To_Hex (Value : Interfaces.Unsigned_64) return String is
      V : Interfaces.Unsigned_64 := Value;
      R : String (1 .. 16);
   begin
      for I in reverse R'Range loop
         R (I) := Hex_Digit (Natural (V and 16#F#));
         V := V / 16;
      end loop;
      return R;
   end To_Hex;

   Epoch : constant Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);

   function Epoch_Seconds (T : Ada.Calendar.Time) return String is
      Offset : Duration := T - Epoch;
   begin
      if Offset < 0.0 then
         Offset := 0.0;
      end if;
      return Long_Long_Integer'Image (Long_Long_Integer (Offset));
   exception
      when others =>
         return " 0";
   end Epoch_Seconds;

   function Time_From_Epoch_Seconds
     (Text : String; Default : Ada.Calendar.Time) return Ada.Calendar.Time
   is
      V : Long_Long_Integer;
   begin
      if Trim (Text)'Length = 0 then
         return Default;
      end if;
      V := Long_Long_Integer'Value (Trim (Text));
      if V < 0 then
         return Default;
      end if;
      return Epoch + Duration (V);
   exception
      when others =>
         return Default;
   end Time_From_Epoch_Seconds;

   function Config_Of (C : Persistent_Config) return Persistent_Config_Holder
   is
   begin
      return
        (Enabled                  => C.Enabled,
         Cache_Directory          => C.Cache_Directory,
         Create_If_Missing        => C.Create_If_Missing,
         Strict_Writes            => C.Strict_Writes,
         Max_Entries              => C.Max_Entries,
         Max_Total_Stored_Bytes   => C.Max_Total_Stored_Bytes,
         Max_Body_Bytes_Per_Entry => C.Max_Body_Bytes_Per_Entry,
         Max_Metadata_Bytes       => C.Max_Metadata_Bytes,
         Max_Directory_Scan_Count => C.Max_Directory_Scan_Count,
         Memory_Config            => C.Memory_Config,
         Encrypt_At_Rest          => C.Encrypt_At_Rest,
         Encryption_Algorithm     => C.Encryption_Algorithm,
         Raw_Encryption_Key       => C.Raw_Encryption_Key);
   end Config_Of;

   function Make_Config
     (Directory                : String;
      Enabled                  : Boolean := True;
      Create_If_Missing        : Boolean := False;
      Strict_Writes            : Boolean := False;
      Max_Entries              : Natural := 64;
      Max_Total_Stored_Bytes   : Natural := 8 * 1_024 * 1_024;
      Max_Body_Bytes_Per_Entry : Natural := 1 * 1_024 * 1_024;
      Max_Metadata_Bytes       : Natural := 64 * 1_024;
      Max_Directory_Scan_Count : Natural := 512;
      Memory_Config            : Http_Client.Cache.Cache_Config :=
        Http_Client.Cache.Default_Enabled_Cache_Config;
      Encrypt_At_Rest          : Boolean := False;
      Raw_Encryption_Key       : String := "") return Persistent_Config is
   begin
      return
        (Enabled                  => Enabled,
         Cache_Directory          => To_Unbounded_String (Directory),
         Create_If_Missing        => Create_If_Missing,
         Strict_Writes            => Strict_Writes,
         Max_Entries              => Max_Entries,
         Max_Total_Stored_Bytes   => Max_Total_Stored_Bytes,
         Max_Body_Bytes_Per_Entry => Max_Body_Bytes_Per_Entry,
         Max_Metadata_Bytes       => Max_Metadata_Bytes,
         Max_Directory_Scan_Count => Max_Directory_Scan_Count,
         Memory_Config            => Memory_Config,
         Encrypt_At_Rest          => Encrypt_At_Rest,
         Encryption_Algorithm     => AES_256_GCM,
         Raw_Encryption_Key       => To_Unbounded_String (Raw_Encryption_Key));
   end Make_Config;

   function Dir (Store : Persistent_Store) return String is
   begin
      return To_String (Store.Config.Cache_Directory);
   end Dir;

   function Compose (Store : Persistent_Store; Name : String) return String is
   begin
      return Ada.Directories.Compose (Dir (Store), Name);
   end Compose;

   function Escape (S : String) return String;

   function Metadata_Key_Text
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response) return String
   is
      Hs   : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      RH   : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Vary : constant String := Http_Client.Headers.Get (Hs, "Vary");
      Key  : Unbounded_String :=
        To_Unbounded_String (Http_Client.Cache.Origin_Key (Request));
      Pos  : Natural := Vary'First;
   begin
      if Http_Client.Headers.Contains (Hs, "Vary") then
         Append
           (Key, "|vary=" & Ada.Characters.Handling.To_Lower (Trim (Vary)));
      end if;

      while Vary'Length > 0 and then Pos <= Vary'Last loop
         declare
            Stop : Natural := Pos;
         begin
            while Stop <= Vary'Last and then Vary (Stop) /= ',' loop
               Stop := Stop + 1;
            end loop;

            declare
               Name : constant String := Trim (Vary (Pos .. Stop - 1));
            begin
               if Name'Length > 0 and then Name /= "*" then
                  Append
                    (Key, "|" & Ada.Characters.Handling.To_Lower (Name) & "=");
                  if Http_Client.Headers.Contains (RH, Name) then
                     Append (Key, Escape (Http_Client.Headers.Get (RH, Name)));
                  else
                     Append (Key, "<absent>");
                  end if;
               end if;
            end;

            Pos := Stop + 1;
         end;
      end loop;

      return To_String (Key);
   end Metadata_Key_Text;

   function Metadata_Name
     (Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response) return String is
   begin
      return To_Hex (Hash64 (Metadata_Key_Text (Request, Response))) & ".meta";
   end Metadata_Name;

   function New_Body_Name
     (Meta : String; Body_Text : String; Stored_At : Ada.Calendar.Time)
      return String is
   begin
      return
        To_Hex
          (Hash64 (Meta & "|" & Epoch_Seconds (Stored_At) & "|" & Body_Text))
        & ".body";
   end New_Body_Name;

   function Body_Name (Meta : String) return String is
   begin
      if Meta'Length > 5 then
         return Meta (Meta'First .. Meta'Last - 5) & ".body";
      else
         return Meta & ".body";
      end if;
   end Body_Name;

   function Is_Safe_Cache_File_Name (Name : String) return Boolean is
      function Has_Suffix (Suffix : String) return Boolean is
      begin
         return
           Name'Length > Suffix'Length
           and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix;
      end Has_Suffix;

      function Hex_Prefix_Length (Suffix : String) return Boolean is
         Prefix_Last : constant Natural := Name'Last - Suffix'Length;
      begin
         if Name'Length /= 16 + Suffix'Length then
            return False;
         end if;

         for I in Name'First .. Prefix_Last loop
            if Name (I) not in 'a' .. 'f' and then Name (I) not in '0' .. '9'
            then
               return False;
            end if;
         end loop;

         return True;
      end Hex_Prefix_Length;
   begin
      --  Cache names are never derived from raw URLs.  Accept only the exact
      --  filename shapes generated by this backend, so corrupt metadata cannot
      --  point at '.', arbitrary dot-only names, or sibling files inside the
      --  configured directory.
      return
        (Has_Suffix (".meta") and then Hex_Prefix_Length (".meta"))
        or else (Has_Suffix (".body") and then Hex_Prefix_Length (".body"))
        or else
          (Has_Suffix (".meta.tmp") and then Hex_Prefix_Length (".meta.tmp"))
        or else
          (Has_Suffix (".body.tmp") and then Hex_Prefix_Length (".body.tmp"))
        or else
          (Has_Suffix (".meta.2.tmp")
           and then Hex_Prefix_Length (".meta.2.tmp"));
   end Is_Safe_Cache_File_Name;

   function Read_Metadata_File
     (Store : Persistent_Store;
      Path  : String;
      Limit : Natural;
      Text  : out Unbounded_String) return Http_Client.Errors.Result_Status;

   procedure Cleanup_Temporary_And_Orphan_Files (Store : Persistent_Store) is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;

      function Metadata_References_Body (Body_File : String) return Boolean is
         Meta_Search : Ada.Directories.Search_Type;
         Meta_Ent    : Ada.Directories.Directory_Entry_Type;
         Meta_Seen   : Natural := 0;
         F           : Ada.Text_IO.File_Type;
         Line        : String (1 .. 4096);
         Last        : Natural;

         function Plain_Metadata_References_Body (Text : String) return Boolean
         is
            Start : Natural := Text'First;
            Stop  : Natural;
         begin
            while Text'Length > 0 and then Start <= Text'Last loop
               Stop := Start;
               while Stop <= Text'Last
                 and then Text (Stop) /= Character'Val (10)
               loop
                  Stop := Stop + 1;
               end loop;
               declare
                  L : constant String :=
                    (if Stop > Start then Text (Start .. Stop - 1) else "");
               begin
                  if L'Length = 5 + Body_File'Length
                    and then L (L'First .. L'First + 4) = "body="
                    and then L (L'First + 5 .. L'Last) = Body_File
                  then
                     return True;
                  end if;
               end;
               Start := Stop + 1;
            end loop;
            return False;
         exception
            when others =>
               return False;
         end Plain_Metadata_References_Body;
      begin
         if not Is_Safe_Cache_File_Name (Body_File) then
            return False;
         end if;

         Ada.Directories.Start_Search (Meta_Search, Dir (Store), "*.meta");
         while Ada.Directories.More_Entries (Meta_Search)
           and then Meta_Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Meta_Search, Meta_Ent);
            Meta_Seen := Meta_Seen + 1;
            if Ada.Directories.Kind (Ada.Directories.Full_Name (Meta_Ent))
              = Ada.Directories.Ordinary_File
            then
               begin
                  if Store.Config.Encrypt_At_Rest then
                     declare
                        Text   : Unbounded_String;
                        Status : constant Http_Client.Errors.Result_Status :=
                          Read_Metadata_File
                            (Store,
                             Ada.Directories.Full_Name (Meta_Ent),
                             Store.Config.Max_Metadata_Bytes,
                             Text);
                     begin
                        if Status = Http_Client.Errors.Ok
                          and then
                            Plain_Metadata_References_Body (To_String (Text))
                        then
                           Ada.Directories.End_Search (Meta_Search);
                           return True;
                        end if;
                     end;
                  else
                     Ada.Text_IO.Open
                       (F,
                        Ada.Text_IO.In_File,
                        Ada.Directories.Full_Name (Meta_Ent));
                     while not Ada.Text_IO.End_Of_File (F) loop
                        Ada.Text_IO.Get_Line (F, Line, Last);
                        if Last >= 5
                          and then Line (1 .. 5) = "body="
                          and then Last = 5 + Body_File'Length
                          and then Line (6 .. Last) = Body_File
                        then
                           Ada.Text_IO.Close (F);
                           Ada.Directories.End_Search (Meta_Search);
                           return True;
                        end if;
                     end loop;
                     Ada.Text_IO.Close (F);
                  end if;
               exception
                  when others =>
                     if Ada.Text_IO.Is_Open (F) then
                        Ada.Text_IO.Close (F);
                     end if;
               end;
            end if;
         end loop;
         Ada.Directories.End_Search (Meta_Search);
         return False;
      exception
         when others =>
            if Ada.Text_IO.Is_Open (F) then
               Ada.Text_IO.Close (F);
            end if;
            return False;
      end Metadata_References_Body;

      procedure Recover_Staged_Metadata is
         Stage_Search : Ada.Directories.Search_Type;
         Stage_Ent    : Ada.Directories.Directory_Entry_Type;
         Stage_Seen   : Natural := 0;
      begin
         Ada.Directories.Start_Search (Stage_Search, Dir (Store), "*");
         while Ada.Directories.More_Entries (Stage_Search)
           and then Stage_Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Stage_Search, Stage_Ent);
            Stage_Seen := Stage_Seen + 1;

            declare
               Name : constant String :=
                 Ada.Directories.Simple_Name (Stage_Ent);
            begin
               if Ada.Directories.Kind (Ada.Directories.Full_Name (Stage_Ent))
                 = Ada.Directories.Ordinary_File
                 and then Name'Length > 11
                 and then Name (Name'Last - 10 .. Name'Last) = ".meta.2.tmp"
                 and then Is_Safe_Cache_File_Name (Name)
               then
                  declare
                     Final_Name : constant String :=
                       Name (Name'First .. Name'Last - 6);
                  begin
                     if Is_Safe_Cache_File_Name (Final_Name)
                       and then
                         not Ada.Directories.Exists
                               (Compose (Store, Final_Name))
                     then
                        Ada.Directories.Rename
                          (Ada.Directories.Full_Name (Stage_Ent),
                           Compose (Store, Final_Name));
                     end if;
                  end;
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         Ada.Directories.End_Search (Stage_Search);
      exception
         when others =>
            null;
      end Recover_Staged_Metadata;
   begin
      if not Ada.Directories.Exists (Dir (Store)) then
         return;
      end if;

      --  Recover staged old metadata before orphan-body cleanup.  Otherwise a
      --  valid body referenced only by the staged metadata could be deleted as
      --  an orphan before the old metadata marker is restored.
      Recover_Staged_Metadata;

      Ada.Directories.Start_Search (Search, Dir (Store), "*");
      while Ada.Directories.More_Entries (Search)
        and then Seen < Store.Config.Max_Directory_Scan_Count
      loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         Seen := Seen + 1;

         declare
            Name : constant String := Ada.Directories.Simple_Name (Ent);
         begin
            if Ada.Directories.Kind (Ada.Directories.Full_Name (Ent))
              = Ada.Directories.Ordinary_File
            then
               if Name'Length > 11
                 and then Name (Name'Last - 10 .. Name'Last) = ".meta.2.tmp"
                 and then Is_Safe_Cache_File_Name (Name)
               then
                  --  Staged metadata recovery ran before orphan-body cleanup.
                  --  Any staged copy still visible here is stale because final
                  --  metadata already exists or restoration failed.
                  declare
                     Final_Name : constant String :=
                       Name (Name'First .. Name'Last - 6);
                  begin
                     if Is_Safe_Cache_File_Name (Final_Name)
                       and then
                         not Ada.Directories.Exists
                               (Compose (Store, Final_Name))
                     then
                        Ada.Directories.Rename
                          (Ada.Directories.Full_Name (Ent),
                           Compose (Store, Final_Name));
                     else
                        Ada.Directories.Delete_File
                          (Ada.Directories.Full_Name (Ent));
                     end if;
                  end;
               elsif Name'Length > 4
                 and then Name (Name'Last - 3 .. Name'Last) = ".tmp"
                 and then Is_Safe_Cache_File_Name (Name)
               then
                  Ada.Directories.Delete_File
                    (Ada.Directories.Full_Name (Ent));
               elsif (not Store.Config.Encrypt_At_Rest)
                 and then Name'Length > 5
                 and then Name (Name'Last - 4 .. Name'Last) = ".body"
                 and then Is_Safe_Cache_File_Name (Name)
                 and then not Metadata_References_Body (Name)
               then
                  Ada.Directories.Delete_File
                    (Ada.Directories.Full_Name (Ent));
               end if;
            end if;
         exception
            when others =>
               null;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         null;
   end Cleanup_Temporary_And_Orphan_Files;

   procedure Write_Text_File
     (Path   : String;
      Text   : String;
      Status : out Http_Client.Errors.Result_Status)
   is
      F : Ada.Text_IO.File_Type;
   begin
      Status := Http_Client.Errors.Ok;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Status := Http_Client.Errors.Cache_Write_Failed;
   end Write_Text_File;

   procedure Delete_File_If_Exists (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Delete_File_If_Exists;

   function Read_Text_File
     (Path : String; Limit : Natural; Text : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      F    : Ada.Text_IO.File_Type;
      Line : String (1 .. 4096);
      Last : Natural;
   begin
      Text := Null_Unbounded_String;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Text_IO.Get_Line (F, Line, Last);
         if Length (Text) + Last + 1 > Limit then
            Ada.Text_IO.Close (F);
            return Http_Client.Errors.Cache_Limit_Exceeded;
         end if;
         Append (Text, Line (1 .. Last));
         Append (Text, Character'Val (10));
      end loop;
      Ada.Text_IO.Close (F);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Text := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Read_Failed;
   end Read_Text_File;

   procedure Write_Binary_File
     (Path   : String;
      Text   : String;
      Status : out Http_Client.Errors.Result_Status)
   is
      F : Ada.Streams.Stream_IO.File_Type;
      use Ada.Streams;
   begin
      Status := Http_Client.Errors.Ok;
      Ada.Streams.Stream_IO.Create (F, Ada.Streams.Stream_IO.Out_File, Path);
      if Text'Length > 0 then
         declare
            Data :
              Stream_Element_Array (1 .. Stream_Element_Offset (Text'Length));
         begin
            for I in Text'Range loop
               Data (Stream_Element_Offset (I - Text'First + 1)) :=
                 Stream_Element (Character'Pos (Text (I)));
            end loop;
            Ada.Streams.Stream_IO.Write (F, Data);
         end;
      end if;
      Ada.Streams.Stream_IO.Close (F);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         Status := Http_Client.Errors.Cache_Write_Failed;
   end Write_Binary_File;

   function Read_Binary_File
     (Path : String; Limit : Natural; Text : out Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      F    : Ada.Streams.Stream_IO.File_Type;
      use Ada.Streams;
      Size : Ada.Streams.Stream_IO.Count;
   begin
      Text := Null_Unbounded_String;
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, Path);
      Size := Ada.Streams.Stream_IO.Size (F);
      if Size > Ada.Streams.Stream_IO.Count (Limit) then
         Ada.Streams.Stream_IO.Close (F);
         return Http_Client.Errors.Cache_Limit_Exceeded;
      end if;
      if Size > 0 then
         declare
            Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
            Last : Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Read (F, Data, Last);
            for I in Data'First .. Last loop
               Append (Text, Character'Val (Natural (Data (I))));
            end loop;
         end;
      end if;
      Ada.Streams.Stream_IO.Close (F);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         Text := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Read_Failed;
   end Read_Binary_File;

   function Is_Encrypted_Envelope (Text : String) return Boolean is
   begin
      return
        Text'Length >= 13
        and then Text (Text'First .. Text'First + 12) = "HCPCACHE-ENC ";
   end Is_Encrypted_Envelope;

   function Hex_Encode (S : String) return String is
      Hex : constant String := "0123456789abcdef";
      R   : String (1 .. S'Length * 2);
      P   : Natural := R'First;
   begin
      for C of S loop
         R (P) := Hex (Character'Pos (C) / 16 + 1);
         R (P + 1) := Hex (Character'Pos (C) mod 16 + 1);
         P := P + 2;
      end loop;
      return R;
   end Hex_Encode;

   function Hex_Value (C : Character) return Natural is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         return 10 + Character'Pos (C) - Character'Pos ('a');
      elsif C in 'A' .. 'F' then
         return 10 + Character'Pos (C) - Character'Pos ('A');
      else
         return 16;
      end if;
   end Hex_Value;

   function Hex_Decode
     (S : String; Out_Text : out Unbounded_String) return Boolean
   is
      R : Unbounded_String;
   begin
      Out_Text := Null_Unbounded_String;
      if S'Length mod 2 /= 0 then
         return False;
      end if;
      declare
         I : Natural := S'First;
      begin
         while I <= S'Last loop
            if Hex_Value (S (I)) >= 16 or else Hex_Value (S (I + 1)) >= 16 then
               return False;
            end if;
            Append
              (R,
               Character'Val (Hex_Value (S (I)) * 16 + Hex_Value (S (I + 1))));
            I := I + 2;
         end loop;
      end;
      Out_Text := R;
      return True;
   exception
      when others =>
         Out_Text := Null_Unbounded_String;
         return False;
   end Hex_Decode;

   function File_AAD (Path : String; Kind : String) return String is
      Name        : constant String := Ada.Directories.Simple_Name (Path);
      Stable_Name : constant String :=
        (if Name'Length > 4 and then Name (Name'Last - 3 .. Name'Last) = ".tmp"
         then Name (Name'First .. Name'Last - 4)
         else Name);
   begin
      --  Encrypted cache entries are first written to temporary files and then
      --  atomically renamed into place.  The AEAD associated data must bind the
      --  final cache-object name, not the transient .tmp publication name, so
      --  that the entry remains decryptable after the successful rename.
      return
        "HCPCACHE-ENC|v=1|alg=AES-256-GCM|kind="
        & Kind
        & "|name="
        & Stable_Name;
   exception
      when others =>
         return "HCPCACHE-ENC|v=1|alg=AES-256-GCM|kind=" & Kind;
   end File_AAD;

   procedure Write_Encrypted_File
     (Store  : Persistent_Store;
      Path   : String;
      Kind   : String;
      Plain  : String;
      Status : out Http_Client.Errors.Result_Status)
   is
      Nonce      : Unbounded_String;
      Ciphertext : Unbounded_String;
      Tag        : Unbounded_String;
      Envelope   : Unbounded_String;
   begin
      Status :=
        Http_Client.Crypto.Random_Bytes
          (Http_Client.Crypto.AES_256_GCM_Nonce_Length, Nonce);
      if Status /= Http_Client.Errors.Ok then
         return;
      end if;

      Status :=
        Http_Client.Crypto.AES_256_GCM_Encrypt
          (Key        => To_String (Store.Config.Raw_Encryption_Key),
           Nonce      => To_String (Nonce),
           Associated => File_AAD (Path, Kind),
           Plaintext  => Plain,
           Ciphertext => Ciphertext,
           Tag        => Tag);
      if Status /= Http_Client.Errors.Ok then
         return;
      end if;

      Append (Envelope, "HCPCACHE-ENC 1" & Character'Val (10));
      Append (Envelope, "alg=AES-256-GCM" & Character'Val (10));
      Append (Envelope, "kind=" & Kind & Character'Val (10));
      Append
        (Envelope,
         "nonce=" & Hex_Encode (To_String (Nonce)) & Character'Val (10));
      Append
        (Envelope, "tag=" & Hex_Encode (To_String (Tag)) & Character'Val (10));
      Append
        (Envelope,
         "plain-length=" & Natural'Image (Plain'Length) & Character'Val (10));
      Append
        (Envelope,
         "cipher-length="
         & Natural'Image (Length (Ciphertext))
         & Character'Val (10));
      Append (Envelope, Character'Val (10));
      Append (Envelope, To_String (Ciphertext));
      Write_Binary_File (Path, To_String (Envelope), Status);
   end Write_Encrypted_File;

   function Read_Encrypted_File
     (Store : Persistent_Store;
      Path  : String;
      Kind  : String;
      Limit : Natural;
      Plain : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Raw               : Unbounded_String;
      Status            : Http_Client.Errors.Result_Status;
      Header_End        : Natural := 0;
      Nonce_Hex         : Unbounded_String;
      Tag_Hex           : Unbounded_String;
      Alg_Text          : Unbounded_String;
      Kind_Text         : Unbounded_String;
      Plain_Length      : Natural := 0;
      Cipher_Length     : Natural := 0;
      Has_Length        : Boolean := False;
      Has_Cipher_Length : Boolean := False;
      Has_Version       : Boolean := False;
      Nonce             : Unbounded_String;
      Tag               : Unbounded_String;
      Cipher            : Unbounded_String;
   begin
      Plain := Null_Unbounded_String;
      Status := Read_Binary_File (Path, Limit + 1024, Raw);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      declare
         S : constant String := To_String (Raw);
      begin
         if not Is_Encrypted_Envelope (S) then
            return Http_Client.Errors.Cache_Encrypted_Format_Unsupported;
         end if;

         for I in S'First .. S'Last - 1 loop
            if S (I) = Character'Val (10)
              and then S (I + 1) = Character'Val (10)
            then
               Header_End := I;
               exit;
            end if;
         end loop;
         if Header_End = 0 then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;

         declare
            Start : Natural := S'First;
            Stop  : Natural;
         begin
            while Start <= Header_End loop
               Stop := Start;
               while Stop <= Header_End and then S (Stop) /= Character'Val (10)
               loop
                  Stop := Stop + 1;
               end loop;
               declare
                  Line : constant String :=
                    (if Stop > Start then S (Start .. Stop - 1) else "");
               begin
                  if Line = "HCPCACHE-ENC 1" then
                     Has_Version := True;
                  elsif Line'Length >= 4
                    and then Line (Line'First .. Line'First + 3) = "alg="
                  then
                     Alg_Text :=
                       To_Unbounded_String
                         (Line (Line'First + 4 .. Line'Last));
                  elsif Line'Length >= 5
                    and then Line (Line'First .. Line'First + 4) = "kind="
                  then
                     Kind_Text :=
                       To_Unbounded_String
                         (Line (Line'First + 5 .. Line'Last));
                  elsif Line'Length >= 6
                    and then Line (Line'First .. Line'First + 5) = "nonce="
                  then
                     Nonce_Hex :=
                       To_Unbounded_String
                         (Line (Line'First + 6 .. Line'Last));
                  elsif Line'Length >= 4
                    and then Line (Line'First .. Line'First + 3) = "tag="
                  then
                     Tag_Hex :=
                       To_Unbounded_String
                         (Line (Line'First + 4 .. Line'Last));
                  elsif Line'Length >= 13
                    and then
                      Line (Line'First .. Line'First + 12) = "plain-length="
                  then
                     Plain_Length :=
                       Natural'Value (Line (Line'First + 13 .. Line'Last));
                     Has_Length := True;
                  elsif Line'Length >= 14
                    and then
                      Line (Line'First .. Line'First + 13) = "cipher-length="
                  then
                     Cipher_Length :=
                       Natural'Value (Line (Line'First + 14 .. Line'Last));
                     Has_Cipher_Length := True;
                  end if;
               end;
               Start := Stop + 1;
            end loop;
         end;

         if not Has_Version
           or else To_String (Alg_Text) /= "AES-256-GCM"
           or else To_String (Kind_Text) /= Kind
           or else not Has_Length
           or else not Has_Cipher_Length
           or else Plain_Length > Limit
           or else Cipher_Length > Limit
           or else Header_End + 2 > S'Last + 1
         then
            return Http_Client.Errors.Cache_Encrypted_Format_Unsupported;
         end if;

         if Header_End + 2 <= S'Last then
            Cipher := To_Unbounded_String (S (Header_End + 2 .. S'Last));
         else
            Cipher := Null_Unbounded_String;
         end if;

         if Length (Cipher) /= Cipher_Length then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;
      end;

      if not Hex_Decode (To_String (Nonce_Hex), Nonce)
        or else not Hex_Decode (To_String (Tag_Hex), Tag)
      then
         return Http_Client.Errors.Cache_Corrupt_Entry;
      end if;
      if Length (Nonce) /= Http_Client.Crypto.AES_256_GCM_Nonce_Length
        or else Length (Tag) /= Http_Client.Crypto.AES_256_GCM_Tag_Length
      then
         return Http_Client.Errors.Cache_Corrupt_Entry;
      end if;

      Status :=
        Http_Client.Crypto.AES_256_GCM_Decrypt
          (Key        => To_String (Store.Config.Raw_Encryption_Key),
           Nonce      => To_String (Nonce),
           Associated => File_AAD (Path, Kind),
           Ciphertext => To_String (Cipher),
           Tag        => To_String (Tag),
           Plaintext  => Plain);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      if Length (Plain) /= Plain_Length then
         Plain := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Corrupt_Entry;
      end if;
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Plain := Null_Unbounded_String;
         return Http_Client.Errors.Cache_Corrupt_Entry;
   end Read_Encrypted_File;

   Store_Verifier_File_Name : constant String := "cache-store-verifier.enc";
   Store_Verifier_Plaintext : constant String :=
     "http_client persistent encrypted cache store verifier v1";

   function Store_Verifier_Path (Store : Persistent_Store) return String is
   begin
      return Compose (Store, Store_Verifier_File_Name);
   end Store_Verifier_Path;

   function Verify_Or_Create_Encrypted_Store
     (Store : Persistent_Store) return Http_Client.Errors.Result_Status
   is
      Path   : constant String := Store_Verifier_Path (Store);
      Plain  : Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
   begin
      if Ada.Directories.Exists (Path) then
         Status :=
           Read_Encrypted_File
             (Store => Store,
              Path  => Path,
              Kind  => "store",
              Limit => Store_Verifier_Plaintext'Length,
              Plain => Plain);
         if Status /= Http_Client.Errors.Ok then
            if Status = Http_Client.Errors.Cache_Authentication_Failed
              or else Status = Http_Client.Errors.Cache_Decryption_Failed
            then
               return Http_Client.Errors.Cache_Wrong_Key;
            else
               return Status;
            end if;
         end if;
         if To_String (Plain) /= Store_Verifier_Plaintext then
            return Http_Client.Errors.Cache_Wrong_Key;
         end if;
         return Http_Client.Errors.Ok;
      end if;

      declare
         Search         : Ada.Directories.Search_Type;
         Ent            : Ada.Directories.Directory_Entry_Type;
         Seen           : Natural := 0;
         Found_Metadata : Boolean := False;
      begin
         Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
         while Ada.Directories.More_Entries (Search)
           and then Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            Seen := Seen + 1;
            if Ada.Directories.Kind (Ada.Directories.Full_Name (Ent))
              = Ada.Directories.Ordinary_File
            then
               Found_Metadata := True;
               Status :=
                 Read_Encrypted_File
                   (Store => Store,
                    Path  => Ada.Directories.Full_Name (Ent),
                    Kind  => "meta",
                    Limit => Store.Config.Max_Metadata_Bytes,
                    Plain => Plain);
               Ada.Directories.End_Search (Search);
               if Status = Http_Client.Errors.Cache_Authentication_Failed
                 or else Status = Http_Client.Errors.Cache_Decryption_Failed
               then
                  return Http_Client.Errors.Cache_Wrong_Key;
               elsif Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               exit;
            end if;
         end loop;
         if not Found_Metadata then
            Ada.Directories.End_Search (Search);
         end if;
      exception
         when others =>
            return Http_Client.Errors.Cache_Open_Failed;
      end;

      Write_Encrypted_File
        (Store  => Store,
         Path   => Path,
         Kind   => "store",
         Plain  => Store_Verifier_Plaintext,
         Status => Status);
      return Status;
   exception
      when others =>
         return Http_Client.Errors.Cache_Open_Failed;
   end Verify_Or_Create_Encrypted_Store;

   function Plaintext_Open_Sees_Encrypted_Store
     (Store : Persistent_Store) return Boolean is
   begin
      return Ada.Directories.Exists (Store_Verifier_Path (Store));
   exception
      when others =>
         return False;
   end Plaintext_Open_Sees_Encrypted_Store;

   procedure Write_Metadata_File
     (Store  : Persistent_Store;
      Path   : String;
      Text   : String;
      Status : out Http_Client.Errors.Result_Status) is
   begin
      if Store.Config.Encrypt_At_Rest then
         Write_Encrypted_File (Store, Path, "meta", Text, Status);
      else
         Write_Text_File (Path, Text, Status);
      end if;
   end Write_Metadata_File;

   procedure Write_Body_File
     (Store  : Persistent_Store;
      Path   : String;
      Text   : String;
      Status : out Http_Client.Errors.Result_Status) is
   begin
      if Store.Config.Encrypt_At_Rest then
         Write_Encrypted_File (Store, Path, "body", Text, Status);
      else
         Write_Binary_File (Path, Text, Status);
      end if;
   end Write_Body_File;

   function Read_Metadata_File
     (Store : Persistent_Store;
      Path  : String;
      Limit : Natural;
      Text  : out Unbounded_String) return Http_Client.Errors.Result_Status is
   begin
      if Store.Config.Encrypt_At_Rest then
         return Read_Encrypted_File (Store, Path, "meta", Limit, Text);
      else
         return Read_Text_File (Path, Limit, Text);
      end if;
   end Read_Metadata_File;

   function Read_Body_File
     (Store : Persistent_Store;
      Path  : String;
      Limit : Natural;
      Text  : out Unbounded_String) return Http_Client.Errors.Result_Status is
   begin
      if Store.Config.Encrypt_At_Rest then
         return Read_Encrypted_File (Store, Path, "body", Limit, Text);
      else
         return Read_Binary_File (Path, Limit, Text);
      end if;
   end Read_Body_File;

   function Escape (S : String) return String is
      R   : Unbounded_String;
      Hex : constant String := "0123456789ABCDEF";
   begin
      for C of S loop
         if C in 'A' .. 'Z'
           or else C in 'a' .. 'z'
           or else C in '0' .. '9'
           or else C = ' '
           or else C = '-'
           or else C = '_'
           or else C = '.'
           or else C = '/'
           or else C = ':'
           or else C = ';'
           or else C = ','
           or else C = '='
           or else C = '?'
         then
            Append (R, C);
         else
            Append (R, '%');
            Append (R, Hex (Character'Pos (C) / 16 + 1));
            Append (R, Hex (Character'Pos (C) mod 16 + 1));
         end if;
      end loop;
      return To_String (R);
   end Escape;

   function Unescape (S : String) return String is
      R : Unbounded_String;
      I : Natural := S'First;
      function Val (C : Character) return Natural is
      begin
         if C in '0' .. '9' then
            return Character'Pos (C) - Character'Pos ('0');
         end if;
         if C in 'A' .. 'F' then
            return 10 + Character'Pos (C) - Character'Pos ('A');
         end if;
         if C in 'a' .. 'f' then
            return 10 + Character'Pos (C) - Character'Pos ('a');
         end if;
         return 16;
      end Val;
   begin
      while I <= S'Last loop
         if S (I) = '%'
           and then I + 2 <= S'Last
           and then Val (S (I + 1)) < 16
           and then Val (S (I + 2)) < 16
         then
            Append (R, Character'Val (Val (S (I + 1)) * 16 + Val (S (I + 2))));
            I := I + 3;
         else
            Append (R, S (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (R);
   end Unescape;

   procedure Append_Vary_Request_Headers
     (R        : in out Unbounded_String;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response)
   is
      RH   : constant Http_Client.Headers.Header_List :=
        Http_Client.Requests.Headers (Request);
      Vary : constant String :=
        Http_Client.Headers.Get
          (Http_Client.Responses.Headers (Response), "Vary");
      Pos  : Natural := Vary'First;
   begin
      if Vary'Length = 0 then
         return;
      end if;

      while Pos <= Vary'Last loop
         declare
            Stop : Natural := Pos;
         begin
            while Stop <= Vary'Last and then Vary (Stop) /= ',' loop
               Stop := Stop + 1;
            end loop;

            declare
               Name : constant String := Trim (Vary (Pos .. Stop - 1));
            begin
               if Name'Length > 0
                 and then Name /= "*"
                 and then Http_Client.Headers.Contains (RH, Name)
               then
                  Append
                    (R,
                     "req-header="
                     & Escape (Name)
                     & ":"
                     & Escape (Http_Client.Headers.Get (RH, Name))
                     & Character'Val (10));
               end if;
            end;

            Pos := Stop + 1;
         end;
      end loop;
   end Append_Vary_Request_Headers;

   function Metadata_Text
     (Request   : Http_Client.Requests.Request;
      Response  : Http_Client.Responses.Response;
      Body_File : String;
      Stored_At : Ada.Calendar.Time) return String
   is
      H : constant Http_Client.Headers.Header_List :=
        Http_Client.Responses.Headers (Response);
      R : Unbounded_String;
   begin
      Append (R, "HCPCACHE 1" & Character'Val (10));
      Append
        (R,
         "uri="
         & Escape (Http_Client.URI.Image (Http_Client.Requests.URI (Request)))
         & Character'Val (10));
      Append
        (R,
         "method="
         & Method_Image (Http_Client.Requests.Method (Request))
         & Character'Val (10));
      Append
        (R,
         "version="
         & Http_Client.Responses.Version_Image
             (Http_Client.Responses.Version (Response))
         & Character'Val (10));
      Append
        (R,
         "status="
         & Integer'Image (Http_Client.Responses.Status_Code (Response))
         & Character'Val (10));
      Append
        (R,
         "reason="
         & Escape (Http_Client.Responses.Reason_Phrase (Response))
         & Character'Val (10));
      Append (R, "body=" & Body_File & Character'Val (10));
      Append
        (R,
         "body-length="
         & Natural'Image
             (Http_Client.Responses.Response_Body (Response)'Length)
         & Character'Val (10));
      Append
        (R, "stored-at=" & Epoch_Seconds (Stored_At) & Character'Val (10));
      Append
        (R,
         "headers="
         & Natural'Image (Http_Client.Headers.Length (H))
         & Character'Val (10));
      for I in 1 .. Http_Client.Headers.Length (H) loop
         Append
           (R,
            "header="
            & Escape (Http_Client.Headers.Name_At (H, I))
            & ":"
            & Escape (Http_Client.Headers.Value_At (H, I))
            & Character'Val (10));
      end loop;
      Append_Vary_Request_Headers (R, Request, Response);
      return To_String (R);
   end Metadata_Text;

   function Value_After (Line : String; Prefix : String) return String is
   begin
      if Line'Length >= Prefix'Length
        and then Line (Line'First .. Line'First + Prefix'Length - 1) = Prefix
      then
         return Line (Line'First + Prefix'Length .. Line'Last);
      end if;
      return "";
   end Value_After;

   function Load_Entry
     (Store     : in out Persistent_Store;
      Meta_Path : String;
      Now       : Ada.Calendar.Time) return Http_Client.Errors.Result_Status
   is
      Text             : Unbounded_String;
      Status           : Http_Client.Errors.Result_Status;
      URI_Text         : Unbounded_String;
      Method_Text      : Unbounded_String;
      Version_Text     : Unbounded_String := To_Unbounded_String ("HTTP/1.1");
      Status_Text      : Unbounded_String;
      Reason_Text      : Unbounded_String;
      Body_File        : Unbounded_String;
      Body_Length_Text : Unbounded_String;
      Stored_At_Text   : Unbounded_String;
      Headers          : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Request_Headers  : Http_Client.Headers.Header_List :=
        Http_Client.Headers.Empty;
      Start            : Positive;
      Stop             : Natural;
   begin
      Status :=
        Read_Metadata_File
          (Store, Meta_Path, Store.Config.Max_Metadata_Bytes, Text);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      declare
         S : constant String := To_String (Text);
      begin
         if S'Length < 10 or else S (S'First .. S'First + 9) /= "HCPCACHE 1"
         then
            return Http_Client.Errors.Cache_Format_Unsupported;
         end if;
         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;
            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 4
                 and then Line (Line'First .. Line'First + 3) = "uri="
               then
                  URI_Text :=
                    To_Unbounded_String
                      (Unescape (Value_After (Line, "uri=")));
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "method="
               then
                  Method_Text :=
                    To_Unbounded_String (Value_After (Line, "method="));
               elsif Line'Length > 8
                 and then Line (Line'First .. Line'First + 7) = "version="
               then
                  Version_Text :=
                    To_Unbounded_String (Value_After (Line, "version="));
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "status="
               then
                  Status_Text :=
                    To_Unbounded_String (Trim (Value_After (Line, "status=")));
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "reason="
               then
                  Reason_Text :=
                    To_Unbounded_String
                      (Unescape (Value_After (Line, "reason=")));
               elsif Line'Length > 5
                 and then Line (Line'First .. Line'First + 4) = "body="
               then
                  Body_File :=
                    To_Unbounded_String (Value_After (Line, "body="));
               elsif Line'Length > 12
                 and then Line (Line'First .. Line'First + 11) = "body-length="
               then
                  Body_Length_Text :=
                    To_Unbounded_String
                      (Trim (Value_After (Line, "body-length=")));
               elsif Line'Length > 10
                 and then Line (Line'First .. Line'First + 9) = "stored-at="
               then
                  Stored_At_Text :=
                    To_Unbounded_String
                      (Trim (Value_After (Line, "stored-at=")));
               elsif Line'Length > 11
                 and then Line (Line'First .. Line'First + 10) = "req-header="
               then
                  declare
                     HV : constant String := Value_After (Line, "req-header=");
                     P  : Natural := HV'First;
                  begin
                     while P <= HV'Last and then HV (P) /= ':' loop
                        P := P + 1;
                     end loop;
                     if P <= HV'Last then
                        Status :=
                          Http_Client.Headers.Add
                            (Request_Headers,
                             Unescape (HV (HV'First .. P - 1)),
                             Unescape (HV (P + 1 .. HV'Last)));
                        if Status /= Http_Client.Errors.Ok then
                           return Http_Client.Errors.Cache_Corrupt_Entry;
                        end if;
                     end if;
                  end;
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "header="
               then
                  declare
                     HV : constant String := Value_After (Line, "header=");
                     P  : Natural := HV'First;
                  begin
                     while P <= HV'Last and then HV (P) /= ':' loop
                        P := P + 1;
                     end loop;
                     if P <= HV'Last then
                        Status :=
                          Http_Client.Headers.Add
                            (Headers,
                             Unescape (HV (HV'First .. P - 1)),
                             Unescape (HV (P + 1 .. HV'Last)));
                        if Status /= Http_Client.Errors.Ok then
                           return Http_Client.Errors.Cache_Corrupt_Entry;
                        end if;
                     end if;
                  end;
               end if;
            end;
            Start := Stop + 1;
         end loop;
      end;
      if Length (URI_Text) = 0
        or else Length (Method_Text) = 0
        or else Length (Status_Text) = 0
        or else Length (Body_File) = 0
        or else Length (Body_Length_Text) = 0
      then
         return Http_Client.Errors.Cache_Corrupt_Entry;
      end if;
      declare
         Body_Data          : Unbounded_String;
         URI_Ref            : Http_Client.URI.URI_Reference;
         Req                : Http_Client.Requests.Request;
         Resp               : Http_Client.Responses.Response;
         Meth               : Http_Client.Types.Method_Name;
         Raw                : Unbounded_String;
         Declared_Length    : Natural;
         Parsed_Status_Code : Natural;
      begin
         if not Is_Safe_Cache_File_Name (To_String (Body_File)) then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;

         Declared_Length := Natural'Value (To_String (Body_Length_Text));
         if Declared_Length > Store.Config.Max_Body_Bytes_Per_Entry then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;

         Parsed_Status_Code := Natural'Value (To_String (Status_Text));
         if Parsed_Status_Code < 100 or else Parsed_Status_Code > 599 then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;

         Status :=
           Read_Body_File
             (Store,
              Ada.Directories.Compose (Dir (Store), To_String (Body_File)),
              Store.Config.Max_Body_Bytes_Per_Entry,
              Body_Data);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         if Declared_Length /= Length (Body_Data) then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;
         if not Parse_Method (To_String (Method_Text), Meth) then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;
         if Http_Client.URI.Parse (To_String (URI_Text), URI_Ref)
           /= Http_Client.Errors.Ok
         then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;
         Status :=
           Http_Client.Requests.Create
             (Meth, URI_Ref, Req, Headers => Request_Headers);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
         Append
           (Raw,
            To_String (Version_Text)
            & " "
            & To_String (Status_Text)
            & " "
            & To_String (Reason_Text)
            & Character'Val (13)
            & Character'Val (10));
         for I in 1 .. Http_Client.Headers.Length (Headers) loop
            Append
              (Raw,
               Http_Client.Headers.Name_At (Headers, I)
               & ": "
               & Http_Client.Headers.Value_At (Headers, I)
               & Character'Val (13)
               & Character'Val (10));
         end loop;
         Append (Raw, Character'Val (13) & Character'Val (10));
         Append (Raw, To_String (Body_Data));
         Status :=
           Http_Client.Responses.Parse_Response (To_String (Raw), Resp);
         if Status /= Http_Client.Errors.Ok then
            return Http_Client.Errors.Cache_Corrupt_Entry;
         end if;
         declare
            Stored_At : constant Ada.Calendar.Time :=
              Time_From_Epoch_Seconds (To_String (Stored_At_Text), Now);
         begin
            Status :=
              Http_Client.Cache.Store (Store.Memory, Req, Resp, Stored_At);
         end;
         if Status = Http_Client.Errors.Ok then
            Store.Entry_Count_Value := Http_Client.Cache.Length (Store.Memory);
            Store.Stored_Bytes_Value :=
              Store.Stored_Bytes_Value + Length (Body_Data) + Length (Text);
         end if;
         return Status;
      end;
   exception
      when others =>
         return Http_Client.Errors.Cache_Corrupt_Entry;
   end Load_Entry;

   function Body_Name_For_Metadata_File
     (Store : Persistent_Store; Meta : String) return String
   is
      Text   : Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
      Start  : Positive;
      Stop   : Natural;
   begin
      if not Is_Safe_Cache_File_Name (Meta) then
         return "";
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return "";
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length = 0 then
            return "";
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 5
                 and then Line (Line'First .. Line'First + 4) = "body="
               then
                  declare
                     Name : constant String := Value_After (Line, "body=");
                  begin
                     if Is_Safe_Cache_File_Name (Name) then
                        return Name;
                     else
                        return "";
                     end if;
                  end;
               end if;
            end;
            Start := Stop + 1;
         end loop;
      end;

      return "";
   exception
      when others =>
         return "";
   end Body_Name_For_Metadata_File;

   function File_Size_Natural (Path : String) return Natural is
      use type Ada.Directories.File_Size;
      S : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
   begin
      if S > Ada.Directories.File_Size (Natural'Last) then
         return Natural'Last;
      else
         return Natural (S);
      end if;
   exception
      when others =>
         return 0;
   end File_Size_Natural;

   function Disk_Bytes_For_Meta
     (Store : Persistent_Store; Meta : String) return Natural
   is
      Total     : Natural := 0;
      Body_Data : constant String := Body_Name_For_Metadata_File (Store, Meta);
   begin
      if Is_Safe_Cache_File_Name (Meta)
        and then Ada.Directories.Exists (Compose (Store, Meta))
      then
         Total := File_Size_Natural (Compose (Store, Meta));
      end if;
      if Is_Safe_Cache_File_Name (Body_Data)
        and then Ada.Directories.Exists (Compose (Store, Body_Data))
      then
         if Natural'Last - Total
           < File_Size_Natural (Compose (Store, Body_Data))
         then
            return Natural'Last;
         end if;
         Total := Total + File_Size_Natural (Compose (Store, Body_Data));
      end if;
      return Total;
   end Disk_Bytes_For_Meta;

   procedure Disk_Stats
     (Store : Persistent_Store; Count : out Natural; Bytes : out Natural)
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
   begin
      Count := 0;
      Bytes := 0;
      if not Ada.Directories.Exists (Dir (Store)) then
         return;
      end if;
      Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
      while Ada.Directories.More_Entries (Search)
        and then Seen < Store.Config.Max_Directory_Scan_Count
      loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         Seen := Seen + 1;
         declare
            Meta : constant String := Ada.Directories.Simple_Name (Ent);
            Add  : constant Natural := Disk_Bytes_For_Meta (Store, Meta);
         begin
            if Is_Safe_Cache_File_Name (Meta) then
               Count := Count + 1;
               if Natural'Last - Bytes < Add then
                  Bytes := Natural'Last;
               else
                  Bytes := Bytes + Add;
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         Count := 0;
         Bytes := 0;
   end Disk_Stats;

   procedure Delete_Entry_Files (Store : Persistent_Store; Meta : String) is
      Body_Data : constant String := Body_Name_For_Metadata_File (Store, Meta);
   begin
      if Is_Safe_Cache_File_Name (Meta)
        and then Ada.Directories.Exists (Compose (Store, Meta))
      then
         Ada.Directories.Delete_File (Compose (Store, Meta));
      end if;
      if Is_Safe_Cache_File_Name (Body_Data)
        and then Ada.Directories.Exists (Compose (Store, Body_Data))
      then
         Ada.Directories.Delete_File (Compose (Store, Body_Data));
      end if;
   exception
      when others =>
         null;
   end Delete_Entry_Files;

   function Metadata_Origin_Key
     (Store : Persistent_Store; Meta : String; Key : out Unbounded_String)
      return Boolean
   is
      Text     : Unbounded_String;
      Status   : Http_Client.Errors.Result_Status;
      URI_Text : Unbounded_String;
      Start    : Positive;
      Stop     : Natural;
      URI_Ref  : Http_Client.URI.URI_Reference;
      Request  : Http_Client.Requests.Request;
   begin
      Key := Null_Unbounded_String;
      if not Is_Safe_Cache_File_Name (Meta) then
         return False;
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length < 10 or else S (S'First .. S'First + 9) /= "HCPCACHE 1"
         then
            return False;
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 4
                 and then Line (Line'First .. Line'First + 3) = "uri="
               then
                  URI_Text :=
                    To_Unbounded_String
                      (Unescape (Value_After (Line, "uri=")));
                  exit;
               end if;
            end;

            Start := Stop + 1;
         end loop;
      end;

      if Length (URI_Text) = 0 then
         return False;
      end if;

      if Http_Client.URI.Parse (To_String (URI_Text), URI_Ref)
        /= Http_Client.Errors.Ok
      then
         return False;
      end if;

      Status :=
        Http_Client.Requests.Create (Http_Client.Types.GET, URI_Ref, Request);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      Key := To_Unbounded_String (Http_Client.Cache.Origin_Key (Request));
      return Length (Key) > 0;
   exception
      when others =>
         Key := Null_Unbounded_String;
         return False;
   end Metadata_Origin_Key;

   function Metadata_Method_Matches_Request
     (Store   : Persistent_Store;
      Meta    : String;
      Request : Http_Client.Requests.Request) return Boolean
   is
      Text        : Unbounded_String;
      Status      : Http_Client.Errors.Result_Status;
      Method_Text : Unbounded_String;
      Start       : Positive;
      Stop        : Natural;
      Stored      : Http_Client.Types.Method_Name;
   begin
      if not Is_Safe_Cache_File_Name (Meta) then
         return False;
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length < 10 or else S (S'First .. S'First + 9) /= "HCPCACHE 1"
         then
            return False;
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "method="
               then
                  Method_Text :=
                    To_Unbounded_String (Value_After (Line, "method="));
                  exit;
               end if;
            end;

            Start := Stop + 1;
         end loop;
      end;

      if Length (Method_Text) = 0
        or else not Parse_Method (To_String (Method_Text), Stored)
      then
         return False;
      end if;

      return Stored = Http_Client.Requests.Method (Request);
   exception
      when others =>
         return False;
   end Metadata_Method_Matches_Request;

   function Metadata_Matches_Request
     (Store   : Persistent_Store;
      Meta    : String;
      Request : Http_Client.Requests.Request) return Boolean
   is
      Text       : Unbounded_String;
      Status     : Http_Client.Errors.Result_Status;
      Key        : Unbounded_String;
      Vary_Value : Unbounded_String;
      Start      : Positive;
      Stop       : Natural;

      function Stored_Request_Header
        (Name : String; Value : out Unbounded_String) return Boolean
      is
         Inner_Start : Positive;
         Inner_Stop  : Natural;
         Lower_Name  : constant String :=
           Ada.Characters.Handling.To_Lower (Name);
      begin
         Value := Null_Unbounded_String;
         declare
            S : constant String := To_String (Text);
         begin
            if S'Length = 0 then
               return False;
            end if;

            Inner_Start := S'First;
            while Inner_Start <= S'Last loop
               Inner_Stop := Inner_Start;
               while Inner_Stop <= S'Last
                 and then S (Inner_Stop) /= Character'Val (10)
               loop
                  Inner_Stop := Inner_Stop + 1;
               end loop;

               declare
                  Line : constant String :=
                    (if Inner_Stop > Inner_Start
                     then S (Inner_Start .. Inner_Stop - 1)
                     else "");
               begin
                  if Line'Length > 11
                    and then
                      Line (Line'First .. Line'First + 10) = "req-header="
                  then
                     declare
                        HV : constant String :=
                          Value_After (Line, "req-header=");
                        P  : Natural := HV'First;
                     begin
                        while P <= HV'Last and then HV (P) /= ':' loop
                           P := P + 1;
                        end loop;

                        if P <= HV'Last
                          and then
                            Ada.Characters.Handling.To_Lower
                              (Unescape (HV (HV'First .. P - 1)))
                            = Lower_Name
                        then
                           Value :=
                             To_Unbounded_String
                               (Unescape (HV (P + 1 .. HV'Last)));
                           return True;
                        end if;
                     end;
                  end if;
               end;

               Inner_Start := Inner_Stop + 1;
            end loop;
         end;

         return False;
      exception
         when others =>
            Value := Null_Unbounded_String;
            return False;
      end Stored_Request_Header;

      function Vary_Allows_Request return Boolean is
         Vary : constant String := To_String (Vary_Value);
         Pos  : Natural := Vary'First;
      begin
         if Vary'Length = 0 then
            return True;
         end if;

         while Pos <= Vary'Last loop
            declare
               Field_Stop : Natural := Pos;
            begin
               while Field_Stop <= Vary'Last and then Vary (Field_Stop) /= ','
               loop
                  Field_Stop := Field_Stop + 1;
               end loop;

               declare
                  Name         : constant String :=
                    Trim (Vary (Pos .. Field_Stop - 1));
                  Stored_Value : Unbounded_String;
                  Stored_Has   : Boolean;
                  Request_Has  : Boolean;
               begin
                  if Name'Length > 0 then
                     if Name = "*" then
                        return False;
                     end if;

                     Stored_Has := Stored_Request_Header (Name, Stored_Value);
                     Request_Has :=
                       Http_Client.Headers.Contains
                         (Http_Client.Requests.Headers (Request), Name);

                     if Stored_Has /= Request_Has then
                        return False;
                     end if;

                     if Stored_Has
                       and then
                         To_String (Stored_Value)
                         /= Http_Client.Headers.Get
                              (Http_Client.Requests.Headers (Request), Name)
                     then
                        return False;
                     end if;
                  end if;
               end;

               Pos := Field_Stop + 1;
            end;
         end loop;

         return True;
      end Vary_Allows_Request;
   begin
      if not Metadata_Origin_Key (Store, Meta, Key)
        or else To_String (Key) /= Http_Client.Cache.Origin_Key (Request)
        or else not Metadata_Method_Matches_Request (Store, Meta, Request)
      then
         return False;
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length < 10 or else S (S'First .. S'First + 9) /= "HCPCACHE 1"
         then
            return False;
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "header="
               then
                  declare
                     HV : constant String := Value_After (Line, "header=");
                     P  : Natural := HV'First;
                  begin
                     while P <= HV'Last and then HV (P) /= ':' loop
                        P := P + 1;
                     end loop;

                     if P <= HV'Last
                       and then
                         Ada.Characters.Handling.To_Lower
                           (Unescape (HV (HV'First .. P - 1)))
                         = "vary"
                     then
                        Vary_Value :=
                          To_Unbounded_String
                            (Unescape (HV (P + 1 .. HV'Last)));
                        exit;
                     end if;
                  end;
               end if;
            end;

            Start := Stop + 1;
         end loop;
      end;

      return Vary_Allows_Request;
   exception
      when others =>
         return False;
   end Metadata_Matches_Request;

   function Metadata_File_Is_Usable
     (Store : Persistent_Store; Meta : String) return Boolean
   is
      Text             : Unbounded_String;
      Status           : Http_Client.Errors.Result_Status;
      Body_File        : Unbounded_String;
      Body_Length_Text : Unbounded_String;
      Method_Text      : Unbounded_String;
      URI_Text         : Unbounded_String;
      Status_Text      : Unbounded_String;
      Saw_URI          : Boolean := False;
      Saw_Method       : Boolean := False;
      Saw_Status       : Boolean := False;
      Saw_Body_Length  : Boolean := False;
      Start            : Positive;
      Stop             : Natural;
      Declared_Length  : Natural := 0;
      Parsed_Status    : Natural := 0;
      Parsed_Method    : Http_Client.Types.Method_Name;
      Parsed_URI       : Http_Client.URI.URI_Reference;
   begin
      if not Is_Safe_Cache_File_Name (Meta) then
         return False;
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length < 10 or else S (S'First .. S'First + 9) /= "HCPCACHE 1"
         then
            return False;
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 4
                 and then Line (Line'First .. Line'First + 3) = "uri="
               then
                  URI_Text :=
                    To_Unbounded_String
                      (Unescape (Value_After (Line, "uri=")));
                  Saw_URI := True;
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "method="
               then
                  Method_Text :=
                    To_Unbounded_String (Value_After (Line, "method="));
                  Saw_Method := True;
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "status="
               then
                  Status_Text :=
                    To_Unbounded_String (Trim (Value_After (Line, "status=")));
                  Saw_Status := True;
               elsif Line'Length > 5
                 and then Line (Line'First .. Line'First + 4) = "body="
               then
                  Body_File :=
                    To_Unbounded_String (Value_After (Line, "body="));
               elsif Line'Length > 12
                 and then Line (Line'First .. Line'First + 11) = "body-length="
               then
                  Body_Length_Text :=
                    To_Unbounded_String
                      (Trim (Value_After (Line, "body-length=")));
                  Saw_Body_Length := True;
               end if;
            end;

            Start := Stop + 1;
         end loop;
      end;

      if not Saw_URI
        or else not Saw_Method
        or else not Saw_Status
        or else not Saw_Body_Length
        or else Length (Body_File) = 0
        or else Length (URI_Text) = 0
        or else Length (Method_Text) = 0
        or else Length (Status_Text) = 0
        or else not Is_Safe_Cache_File_Name (To_String (Body_File))
      then
         return False;
      end if;

      if not Parse_Method (To_String (Method_Text), Parsed_Method) then
         return False;
      end if;

      if Http_Client.URI.Parse (To_String (URI_Text), Parsed_URI)
        /= Http_Client.Errors.Ok
      then
         return False;
      end if;

      Parsed_Status := Natural'Value (To_String (Status_Text));
      if Parsed_Status < 100 or else Parsed_Status > 599 then
         return False;
      end if;

      Declared_Length := Natural'Value (To_String (Body_Length_Text));
      if Declared_Length > Store.Config.Max_Body_Bytes_Per_Entry then
         return False;
      end if;

      if not Ada.Directories.Exists (Compose (Store, To_String (Body_File)))
      then
         return False;
      end if;

      if Store.Config.Encrypt_At_Rest then
         declare
            Body_Check : Unbounded_String;
         begin
            Status :=
              Read_Body_File
                (Store,
                 Compose (Store, To_String (Body_File)),
                 Store.Config.Max_Body_Bytes_Per_Entry,
                 Body_Check);
            if Status /= Http_Client.Errors.Ok
              or else Length (Body_Check) /= Declared_Length
            then
               return False;
            end if;
         end;
      else
         declare
            Size : constant Natural :=
              File_Size_Natural (Compose (Store, To_String (Body_File)));
         begin
            if Size > Store.Config.Max_Body_Bytes_Per_Entry then
               return False;
            end if;

            if Length (Body_Length_Text) > 0 and then Size /= Declared_Length
            then
               return False;
            end if;
         end;
      end if;

      return True;
   exception
      when others =>
         return False;
   end Metadata_File_Is_Usable;

   procedure Cleanup_Invalid_Metadata_Files (Store : Persistent_Store) is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
   begin
      if not Ada.Directories.Exists (Dir (Store)) then
         return;
      end if;

      Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
      while Ada.Directories.More_Entries (Search)
        and then Seen < Store.Config.Max_Directory_Scan_Count
      loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         Seen := Seen + 1;
         declare
            Name : constant String := Ada.Directories.Simple_Name (Ent);
         begin
            if not Metadata_File_Is_Usable (Store, Name) then
               Delete_Entry_Files (Store, Name);
            end if;
         exception
            when others =>
               null;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         null;
   end Cleanup_Invalid_Metadata_Files;

   procedure Enforce_Disk_Limits
     (Store : in out Persistent_Store; Preserve_Meta : String := "")
   is
      Count : Natural;
      Bytes : Natural;
   begin
      loop
         Disk_Stats (Store, Count, Bytes);
         exit when
           Count <= Store.Config.Max_Entries
           and then Bytes <= Store.Config.Max_Total_Stored_Bytes;

         declare
            Search      : Ada.Directories.Search_Type;
            Ent         : Ada.Directories.Directory_Entry_Type;
            Seen        : Natural := 0;
            Found       : Boolean := False;
            Oldest_Name : Unbounded_String;
            Oldest_Time : Ada.Calendar.Time := Ada.Calendar.Clock;
         begin
            Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
            while Ada.Directories.More_Entries (Search)
              and then Seen < Store.Config.Max_Directory_Scan_Count
            loop
               Ada.Directories.Get_Next_Entry (Search, Ent);
               Seen := Seen + 1;
               declare
                  Name  : constant String := Ada.Directories.Simple_Name (Ent);
                  MTime : constant Ada.Calendar.Time :=
                    Ada.Directories.Modification_Time
                      (Ada.Directories.Full_Name (Ent));
               begin
                  if Is_Safe_Cache_File_Name (Name)
                    and then Name /= Preserve_Meta
                    and then ((not Found) or else MTime < Oldest_Time)
                  then
                     Found := True;
                     Oldest_Name := To_Unbounded_String (Name);
                     Oldest_Time := MTime;
                  end if;
               exception
                  when others =>
                     null;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
            exit when not Found;
            Delete_Entry_Files (Store, To_String (Oldest_Name));
         end;
      end loop;
      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
   exception
      when others =>
         null;
   end Enforce_Disk_Limits;

   procedure Reload_Memory_From_Disk
     (Store : in out Persistent_Store; Now : Ada.Calendar.Time)
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
      Status : Http_Client.Errors.Result_Status;
   begin
      Http_Client.Cache.Clear (Store.Memory);
      Store.Entry_Count_Value := 0;
      Store.Stored_Bytes_Value := 0;
      Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
      while Ada.Directories.More_Entries (Search)
        and then Seen < Store.Config.Max_Directory_Scan_Count
      loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         Seen := Seen + 1;
         Status := Load_Entry (Store, Ada.Directories.Full_Name (Ent), Now);
         if Status /= Http_Client.Errors.Ok then
            Delete_Entry_Files (Store, Ada.Directories.Simple_Name (Ent));
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
   exception
      when others =>
         Http_Client.Cache.Clear (Store.Memory);
         Store.Entry_Count_Value := 0;
         Store.Stored_Bytes_Value := 0;
   end Reload_Memory_From_Disk;

   function Directory_Encryption_Format_Status
     (Store : Persistent_Store) return Http_Client.Errors.Result_Status
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
      Raw    : Unbounded_String;
      Status : Http_Client.Errors.Result_Status;
   begin
      if not Ada.Directories.Exists (Dir (Store)) then
         return Http_Client.Errors.Ok;
      end if;

      if (not Store.Config.Encrypt_At_Rest)
        and then Plaintext_Open_Sees_Encrypted_Store (Store)
      then
         return Http_Client.Errors.Cache_Format_Unsupported;
      end if;

      Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
      while Ada.Directories.More_Entries (Search)
        and then Seen < Store.Config.Max_Directory_Scan_Count
      loop
         Ada.Directories.Get_Next_Entry (Search, Ent);
         Seen := Seen + 1;
         if Ada.Directories.Kind (Ada.Directories.Full_Name (Ent))
           = Ada.Directories.Ordinary_File
         then
            Status :=
              Read_Binary_File
                (Ada.Directories.Full_Name (Ent),
                 Store.Config.Max_Metadata_Bytes + 1024,
                 Raw);
            if Status /= Http_Client.Errors.Ok then
               Ada.Directories.End_Search (Search);
               return Status;
            end if;
            if Store.Config.Encrypt_At_Rest then
               if not Is_Encrypted_Envelope (To_String (Raw)) then
                  Ada.Directories.End_Search (Search);
                  return Http_Client.Errors.Cache_Encrypted_Format_Unsupported;
               end if;
            else
               if Is_Encrypted_Envelope (To_String (Raw)) then
                  Ada.Directories.End_Search (Search);
                  return Http_Client.Errors.Cache_Format_Unsupported;
               end if;
            end if;
         end if;
      end loop;
      Ada.Directories.End_Search (Search);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Cache_Read_Failed;
   end Directory_Encryption_Format_Status;

   function Open
     (Store : in out Persistent_Store; Config : Persistent_Config)
      return Http_Client.Errors.Result_Status
   is
      Memory_Config : Http_Client.Cache.Cache_Config := Config.Memory_Config;
   begin
      Close (Store);
      Store.Config := Config_Of (Config);
      if Config.Enabled
        and then
          (Config.Max_Entries = 0
           or else Config.Max_Total_Stored_Bytes = 0
           or else Config.Max_Body_Bytes_Per_Entry = 0
           or else Config.Max_Metadata_Bytes = 0
           or else Config.Max_Directory_Scan_Count = 0
           or else not Config.Memory_Config.Enabled)
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      if Config.Enabled and then Config.Encrypt_At_Rest then
         if Config.Encryption_Algorithm /= AES_256_GCM then
            return Http_Client.Errors.Cache_Encrypted_Format_Unsupported;
         end if;
         if Length (Config.Raw_Encryption_Key)
           /= Http_Client.Crypto.AES_256_GCM_Key_Length
         then
            return Http_Client.Errors.Cache_Key_Invalid;
         end if;
      end if;
      if Memory_Config.Max_Entries > Config.Max_Entries then
         Memory_Config.Max_Entries := Config.Max_Entries;
      end if;
      if Memory_Config.Max_Total_Body_Bytes > Config.Max_Total_Stored_Bytes
      then
         Memory_Config.Max_Total_Body_Bytes := Config.Max_Total_Stored_Bytes;
      end if;
      if Memory_Config.Max_Single_Response_Bytes
        > Config.Max_Body_Bytes_Per_Entry
      then
         Memory_Config.Max_Single_Response_Bytes :=
           Config.Max_Body_Bytes_Per_Entry;
      end if;
      Store.Config.Memory_Config := Memory_Config;
      Http_Client.Cache.Initialize (Store.Memory, Memory_Config);
      Store.Entry_Count_Value := 0;
      Store.Stored_Bytes_Value := 0;
      if not Config.Enabled then
         return Http_Client.Errors.Cache_Disabled;
      end if;
      if Length (Config.Cache_Directory) = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      end if;
      declare
         D : constant String := To_String (Config.Cache_Directory);
      begin
         if Ada.Directories.Exists (D) then
            if Ada.Directories.Kind (D) /= Ada.Directories.Directory then
               return Http_Client.Errors.Cache_Open_Failed;
            end if;
         elsif Config.Create_If_Missing then
            Ada.Directories.Create_Path (D);
         else
            return Http_Client.Errors.Cache_Open_Failed;
         end if;
      exception
         when others =>
            return Http_Client.Errors.Cache_Open_Failed;
      end;
      Store.Opened := True;
      declare
         Format_Status : constant Http_Client.Errors.Result_Status :=
           Directory_Encryption_Format_Status (Store);
      begin
         if Format_Status /= Http_Client.Errors.Ok then
            Store.Opened := False;
            return Format_Status;
         end if;
      end;
      if Store.Config.Encrypt_At_Rest then
         declare
            Verifier_Status : constant Http_Client.Errors.Result_Status :=
              Verify_Or_Create_Encrypted_Store (Store);
         begin
            if Verifier_Status /= Http_Client.Errors.Ok then
               Store.Opened := False;
               return Verifier_Status;
            end if;
         end;
      end if;
      Cleanup_Temporary_And_Orphan_Files (Store);
      Cleanup_Invalid_Metadata_Files (Store);
      Cleanup_Temporary_And_Orphan_Files (Store);
      --  Opening the persistent cache must remain bounded and must not
      --  eagerly read every cached body into memory.  Keep only disk-level
      --  metadata/statistics here; individual bodies are rehydrated lazily
      --  during Lookup or directly after Store/Update_From_304.
      Http_Client.Cache.Clear (Store.Memory);
      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
      Http_Client.Resources.Increment
        (Http_Client.Resources.Persistent_Cache_Stores_Open);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         Store.Opened := False;
         return Http_Client.Errors.Cache_Open_Failed;
   end Open;

   procedure Close (Store : in out Persistent_Store) is
   begin
      if Store.Opened then
         Http_Client.Resources.Decrement
           (Http_Client.Resources.Persistent_Cache_Stores_Open);
      end if;
      Store.Opened := False;
      Http_Client.Cache.Clear (Store.Memory);
      Store.Entry_Count_Value := 0;
      Store.Stored_Bytes_Value := 0;
   end Close;

   procedure Clear (Store : in out Persistent_Store) is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;

      function Ends_With (Name : String; Suffix : String) return Boolean is
      begin
         return
           Name'Length >= Suffix'Length
           and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix;
      end Ends_With;

      function Safe_Clear_File (Name : String) return Boolean is
      begin
         if Name = Store_Verifier_File_Name then
            return True;
         end if;
         return
           (Ends_With (Name, ".meta")
            or else Ends_With (Name, ".body")
            or else Ends_With (Name, ".tmp"))
           and then Is_Safe_Cache_File_Name (Name);
      end Safe_Clear_File;
   begin
      if Store.Opened and then Ada.Directories.Exists (Dir (Store)) then
         Ada.Directories.Start_Search (Search, Dir (Store), "*");
         while Ada.Directories.More_Entries (Search)
           and then Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            Seen := Seen + 1;
            declare
               Name : constant String := Ada.Directories.Simple_Name (Ent);
            begin
               if Ada.Directories.Kind (Ada.Directories.Full_Name (Ent))
                 = Ada.Directories.Ordinary_File
                 and then Safe_Clear_File (Name)
               then
                  Ada.Directories.Delete_File
                    (Ada.Directories.Full_Name (Ent));
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      end if;
      Http_Client.Cache.Clear (Store.Memory);
      Store.Entry_Count_Value := 0;
      Store.Stored_Bytes_Value := 0;
   exception
      when others =>
         Http_Client.Cache.Clear (Store.Memory);
         Store.Entry_Count_Value := 0;
         Store.Stored_Bytes_Value := 0;
   end Clear;

   procedure Invalidate
     (Store : in out Persistent_Store; Request : Http_Client.Requests.Request)
   is
      Wanted_Key : constant String := Http_Client.Cache.Origin_Key (Request);
      Search     : Ada.Directories.Search_Type;
      Ent        : Ada.Directories.Directory_Entry_Type;
      Seen       : Natural := 0;
   begin
      if not Store.Opened or else Wanted_Key = "" then
         return;
      end if;

      Http_Client.Cache.Invalidate (Store.Memory, Request);

      if Ada.Directories.Exists (Dir (Store)) then
         Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
         while Ada.Directories.More_Entries (Search)
           and then Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            Seen := Seen + 1;
            declare
               Meta_Name : constant String :=
                 Ada.Directories.Simple_Name (Ent);
               Key       : Unbounded_String;
            begin
               if Metadata_Origin_Key (Store, Meta_Name, Key)
                 and then To_String (Key) = Wanted_Key
               then
                  Delete_Entry_Files (Store, Meta_Name);
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      end if;

      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
   exception
      when others =>
         Http_Client.Cache.Invalidate (Store.Memory, Request);
         Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
   end Invalidate;

   function Is_Open (Store : Persistent_Store) return Boolean
   is (Store.Opened);
   function Encrypts_At_Rest (Store : Persistent_Store) return Boolean
   is (Store.Opened and then Store.Config.Encrypt_At_Rest);
   function Entry_Count (Store : Persistent_Store) return Natural
   is (Store.Entry_Count_Value);
   function Stored_Bytes (Store : Persistent_Store) return Natural
   is (Store.Stored_Bytes_Value);

   function Lookup
     (Store    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : out Http_Client.Responses.Response;
      Metadata : out Http_Client.Cache.Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
   begin
      if not Store.Opened or else not Store.Config.Enabled then
         return Http_Client.Errors.Cache_Disabled;
      end if;

      Status :=
        Http_Client.Cache.Lookup
          (Store.Memory, Request, Response, Metadata, Now);

      if Status = Http_Client.Errors.Ok
        or else Status = Http_Client.Errors.Cache_Entry_Stale
      then
         return Status;
      end if;

      --  Lazy persistent lookup: Open does not read cached bodies.  On a miss
      --  in the in-memory front, scan bounded metadata and rehydrate entries
      --  one at a time until the cache matcher finds a compatible
      --  origin/Vary entry.  Corrupt entries are removed deterministically.
      if Ada.Directories.Exists (Dir (Store)) then
         Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
         while Ada.Directories.More_Entries (Search)
           and then Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            Seen := Seen + 1;

            declare
               Meta_Name   : constant String :=
                 Ada.Directories.Simple_Name (Ent);
               Load_Status : Http_Client.Errors.Result_Status;
            begin
               if Metadata_Matches_Request (Store, Meta_Name, Request) then
                  Load_Status :=
                    Load_Entry (Store, Ada.Directories.Full_Name (Ent), Now);

                  if Load_Status /= Http_Client.Errors.Ok then
                     Delete_Entry_Files (Store, Meta_Name);
                  else
                     Status :=
                       Http_Client.Cache.Lookup
                         (Store.Memory, Request, Response, Metadata, Now);

                     if Status = Http_Client.Errors.Ok
                       or else Status = Http_Client.Errors.Cache_Entry_Stale
                     then
                        Ada.Directories.End_Search (Search);
                        Disk_Stats
                          (Store,
                           Store.Entry_Count_Value,
                           Store.Stored_Bytes_Value);
                        Metadata.Entry_Count := Store.Entry_Count_Value;
                        Metadata.Stored_Body_Bytes := Store.Stored_Bytes_Value;
                        return Status;
                     end if;
                  end if;
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      end if;

      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
      Metadata.Entry_Count := Store.Entry_Count_Value;
      Metadata.Stored_Body_Bytes := Store.Stored_Bytes_Value;
      return Http_Client.Errors.Cache_Miss;
   exception
      when others =>
         Response := Http_Client.Responses.Default_Response;
         Metadata :=
           (Source             => Http_Client.Cache.Cache_Bypassed,
            Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
            Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
            Age_Seconds        => 0,
            Revalidation_Count => 0,
            Entry_Count        => Store.Entry_Count_Value,
            Stored_Body_Bytes  => Store.Stored_Bytes_Value);
         return Http_Client.Errors.Cache_Read_Failed;
   end Lookup;

   function Store
     (Cache    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Status    : Http_Client.Errors.Result_Status;
      Meta      : constant String := Metadata_Name (Request, Response);
      Body_Data : constant String :=
        New_Body_Name
          (Meta, Http_Client.Responses.Response_Body (Response), Now);
      Tmp_Meta  : constant String := Meta & ".tmp";
      Tmp_Body  : constant String := Body_Data & ".tmp";
      Body_Text : constant String :=
        Http_Client.Responses.Response_Body (Response);
      Meta_Text : constant String :=
        Metadata_Text (Request, Response, Body_Data, Now);
   begin
      if not Cache.Opened or else not Cache.Config.Enabled then
         return Http_Client.Errors.Cache_Disabled;
      end if;
      if Body_Text'Length > Cache.Config.Max_Body_Bytes_Per_Entry then
         return Http_Client.Errors.Cache_Entry_Too_Large;
      end if;
      if Meta_Text'Length > Cache.Config.Max_Metadata_Bytes
        or else
          Body_Text'Length + Meta_Text'Length
          > Cache.Config.Max_Total_Stored_Bytes
      then
         return Http_Client.Errors.Cache_Limit_Exceeded;
      end if;
      if not Is_Safe_Cache_File_Name (Meta)
        or else not Is_Safe_Cache_File_Name (Body_Data)
      then
         return Http_Client.Errors.Cache_Write_Failed;
      end if;
      if not Http_Client.Cache.May_Store
               (Request, Response, Cache.Config.Memory_Config)
      then
         return Http_Client.Errors.Cache_Disabled;
      end if;
      Write_Body_File (Cache, Compose (Cache, Tmp_Body), Body_Text, Status);
      if Status /= Http_Client.Errors.Ok then
         Delete_File_If_Exists (Compose (Cache, Tmp_Body));
         Delete_File_If_Exists (Compose (Cache, Tmp_Meta));
         if Cache.Config.Strict_Writes then
            return Status;
         else
            return Http_Client.Errors.Ok;
         end if;
      end if;
      Write_Metadata_File
        (Cache, Compose (Cache, Tmp_Meta), Meta_Text, Status);
      if Status /= Http_Client.Errors.Ok then
         Delete_File_If_Exists (Compose (Cache, Tmp_Body));
         Delete_File_If_Exists (Compose (Cache, Tmp_Meta));
         if Cache.Config.Strict_Writes then
            return Status;
         else
            return Http_Client.Errors.Ok;
         end if;
      end if;
      declare
         Backup_Meta : constant String := Meta & ".2.tmp";
         Had_Old     : constant Boolean :=
           Ada.Directories.Exists (Compose (Cache, Meta));
      begin
         --  Do not delete an existing final body before the new metadata is
         --  active.  The final body name is content/time derived; when it
         --  already exists, keep it available for any old metadata and discard
         --  only the temporary duplicate.  This preserves the previous entry if
         --  metadata publication later fails.
         if Ada.Directories.Exists (Compose (Cache, Body_Data)) then
            Delete_File_If_Exists (Compose (Cache, Tmp_Body));
         else
            Ada.Directories.Rename
              (Compose (Cache, Tmp_Body), Compose (Cache, Body_Data));
         end if;

         --  Publish metadata last.  Keep the previous metadata staged aside
         --  until the new metadata name is active so a failed replacement can
         --  restore the old cache entry instead of intentionally removing it.
         if Had_Old then
            Delete_File_If_Exists (Compose (Cache, Backup_Meta));
            Ada.Directories.Rename
              (Compose (Cache, Meta), Compose (Cache, Backup_Meta));
         end if;

         begin
            Ada.Directories.Rename
              (Compose (Cache, Tmp_Meta), Compose (Cache, Meta));
            Delete_File_If_Exists (Compose (Cache, Backup_Meta));
         exception
            when others =>
               if Had_Old
                 and then Ada.Directories.Exists (Compose (Cache, Backup_Meta))
               then
                  begin
                     if Ada.Directories.Exists (Compose (Cache, Meta)) then
                        Ada.Directories.Delete_File (Compose (Cache, Meta));
                     end if;
                     Ada.Directories.Rename
                       (Compose (Cache, Backup_Meta), Compose (Cache, Meta));
                  exception
                     when others =>
                        null;
                  end;
               end if;
               raise;
         end;
      exception
         when others =>
            begin
               if Ada.Directories.Exists (Compose (Cache, Tmp_Meta)) then
                  Ada.Directories.Delete_File (Compose (Cache, Tmp_Meta));
               end if;
               if Ada.Directories.Exists (Compose (Cache, Tmp_Body)) then
                  Ada.Directories.Delete_File (Compose (Cache, Tmp_Body));
               end if;
               if Ada.Directories.Exists (Compose (Cache, Meta & ".2.tmp"))
                 and then not Ada.Directories.Exists (Compose (Cache, Meta))
               then
                  Ada.Directories.Rename
                    (Compose (Cache, Meta & ".2.tmp"), Compose (Cache, Meta));
               end if;
            exception
               when others =>
                  null;
            end;
            if Cache.Config.Strict_Writes then
               return Http_Client.Errors.Cache_Write_Failed;
            end if;
      end;
      Cleanup_Temporary_And_Orphan_Files (Cache);
      Enforce_Disk_Limits (Cache, Preserve_Meta => Meta);

      Http_Client.Cache.Clear (Cache.Memory);
      Status := Load_Entry (Cache, Compose (Cache, Meta), Now);
      Disk_Stats (Cache, Cache.Entry_Count_Value, Cache.Stored_Bytes_Value);

      declare
         Verify_Response : Http_Client.Responses.Response;
         Verify_Metadata : Http_Client.Cache.Cache_Metadata;
         Verify_Status   : constant Http_Client.Errors.Result_Status :=
           Http_Client.Cache.Lookup
             (Cache.Memory, Request, Verify_Response, Verify_Metadata, Now);
      begin
         if Status /= Http_Client.Errors.Ok
           or else
             (Verify_Status /= Http_Client.Errors.Ok
              and then Verify_Status /= Http_Client.Errors.Cache_Entry_Stale)
         then
            if Cache.Config.Strict_Writes then
               return Http_Client.Errors.Cache_Write_Failed;
            end if;
         end if;
      end;
      return Http_Client.Errors.Ok;
   end Store;

   function Update_From_304
     (Store    : in out Persistent_Store;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Metadata : out Http_Client.Cache.Cache_Metadata;
      Now      : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Status  : Http_Client.Errors.Result_Status;
      Cached  : Http_Client.Responses.Response;
      Ignored : Http_Client.Cache.Cache_Metadata;
   begin
      if not Store.Opened or else not Store.Config.Enabled then
         Metadata :=
           (Source             => Http_Client.Cache.Cache_Bypassed,
            Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
            Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
            Age_Seconds        => 0,
            Revalidation_Count => 0,
            Entry_Count        => Entry_Count (Store),
            Stored_Body_Bytes  => Stored_Bytes (Store));
         return Http_Client.Errors.Cache_Disabled;
      end if;

      Status :=
        Http_Client.Cache.Update_From_304
          (Store.Memory, Request, Response, Metadata, Now);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status :=
        Http_Client.Cache.Lookup (Store.Memory, Request, Cached, Ignored, Now);
      if Status = Http_Client.Errors.Ok
        or else Status = Http_Client.Errors.Cache_Entry_Stale
      then
         return
           Http_Client.Cache.Persistent.Store
             (Cache    => Store,
              Request  => Request,
              Response => Cached,
              Now      => Now);
      end if;

      return Http_Client.Errors.Ok;
   end Update_From_304;

   function Metadata_Max_Age_Expired
     (Store : Persistent_Store; Meta : String; Now : Ada.Calendar.Time)
      return Boolean
   is
      Text      : Unbounded_String;
      Status    : Http_Client.Errors.Result_Status;
      Stored_At : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Has_Time  : Boolean := False;
      Max_Age   : Natural := 0;
      Has_Age   : Boolean := False;
      Start     : Positive;
      Stop      : Natural;

      function Cache_Control_Max_Age
        (Value : String; Age : out Natural) return Boolean
      is
         Lower_Value : constant String :=
           Ada.Characters.Handling.To_Lower (Value);
         P           : Natural :=
           Ada.Strings.Fixed.Index (Lower_Value, "max-age=");
         First       : Natural;
         Last        : Natural;
      begin
         Age := 0;
         if P = 0 then
            return False;
         end if;
         First := P + 8;
         Last := First;
         while Last <= Lower_Value'Last
           and then Lower_Value (Last) in '0' .. '9'
         loop
            Last := Last + 1;
         end loop;
         if Last = First then
            return False;
         end if;
         Age := Natural'Value (Lower_Value (First .. Last - 1));
         return True;
      exception
         when others =>
            Age := 0;
            return False;
      end Cache_Control_Max_Age;
   begin
      if not Is_Safe_Cache_File_Name (Meta) then
         return False;
      end if;

      Status :=
        Read_Metadata_File
          (Store,
           Compose (Store, Meta),
           Store.Config.Max_Metadata_Bytes,
           Text);
      if Status /= Http_Client.Errors.Ok then
         return False;
      end if;

      declare
         S : constant String := To_String (Text);
      begin
         if S'Length = 0 then
            return False;
         end if;

         Start := S'First;
         while Start <= S'Last loop
            Stop := Start;
            while Stop <= S'Last and then S (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;

            declare
               Line : constant String :=
                 (if Stop > Start then S (Start .. Stop - 1) else "");
            begin
               if Line'Length > 10
                 and then Line (Line'First .. Line'First + 9) = "stored-at="
               then
                  Stored_At :=
                    Time_From_Epoch_Seconds
                      (Value_After (Line, "stored-at="), Stored_At);
                  Has_Time := True;
               elsif Line'Length > 7
                 and then Line (Line'First .. Line'First + 6) = "header="
               then
                  declare
                     HV : constant String := Value_After (Line, "header=");
                     P  : Natural := HV'First;
                     A  : Natural := 0;
                  begin
                     while P <= HV'Last and then HV (P) /= ':' loop
                        P := P + 1;
                     end loop;

                     if P <= HV'Last
                       and then
                         Ada.Characters.Handling.To_Lower
                           (Unescape (HV (HV'First .. P - 1)))
                         = "cache-control"
                       and then
                         Cache_Control_Max_Age
                           (Unescape (HV (P + 1 .. HV'Last)), A)
                     then
                        Max_Age := A;
                        Has_Age := True;
                     end if;
                  end;
               end if;
            end;
            Start := Stop + 1;
         end loop;
      end;

      return
        Has_Time
        and then Has_Age
        and then Now >= Stored_At + Duration (Max_Age);
   exception
      when others =>
         return False;
   end Metadata_Max_Age_Expired;

   function Remove_Expired
     (Store : in out Persistent_Store;
      Now   : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Http_Client.Errors.Result_Status
   is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Seen   : Natural := 0;
   begin
      if not Store.Opened then
         return Http_Client.Errors.Cache_Disabled;
      end if;

      if Ada.Directories.Exists (Dir (Store)) then
         Ada.Directories.Start_Search (Search, Dir (Store), "*.meta");
         while Ada.Directories.More_Entries (Search)
           and then Seen < Store.Config.Max_Directory_Scan_Count
         loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            Seen := Seen + 1;
            declare
               Meta : constant String := Ada.Directories.Simple_Name (Ent);
            begin
               if Metadata_Max_Age_Expired (Store, Meta, Now) then
                  Delete_Entry_Files (Store, Meta);
               end if;
            exception
               when others =>
                  null;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
      end if;

      Http_Client.Cache.Clear (Store.Memory);
      Disk_Stats (Store, Store.Entry_Count_Value, Store.Stored_Bytes_Value);
      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Cache_Read_Failed;
   end Remove_Expired;

end Http_Client.Cache.Persistent;
