with Ada.Characters.Handling;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

with GNAT.Sockets;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;

pragma Style_Checks (Off);

package body Http_Client.Ada_Test_Fixtures is
   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;
   package S renames GNAT.Sockets;
   use type C.int;
   use type CS.chars_ptr;
   use type Ada.Streams.Stream_Element;
   use type System.Address;
   use type Ada.Streams.Stream_Element_Offset;
   use type Http_Client.Errors.Result_Status;

   Max_Capture : constant Natural := 131_072;
   Stop_Fixture : exception;

   procedure Safe_Close (Sock : S.Socket_Type);
   procedure Configure_Fixture_Socket_Timeouts (Sock : S.Socket_Type);
   procedure Configure_Tunnel_Socket_Timeouts (Sock : S.Socket_Type);

   TLS_Server_Socket  : S.Socket_Type;
   TLS_Client_Socket  : S.Socket_Type;
   TLS_Server_Open    : Boolean := False;
   TLS_Client_Open    : Boolean := False;

   Proxy_Server_Socket : S.Socket_Type;
   Proxy_Client_Socket : S.Socket_Type;
   Proxy_Origin_Socket : S.Socket_Type;
   Proxy_Server_Open   : Boolean := False;
   Proxy_Client_Open   : Boolean := False;
   Proxy_Origin_Open   : Boolean := False;

   SOCKS_Server_Socket : S.Socket_Type;
   SOCKS_Client_Socket : S.Socket_Type;
   SOCKS_Origin_Socket : S.Socket_Type;
   SOCKS_Server_Open   : Boolean := False;
   SOCKS_Client_Open   : Boolean := False;
   SOCKS_Origin_Open   : Boolean := False;

   procedure Safe_Close (Sock : S.Socket_Type) is
   begin
      --  Closing a socket from a different Ada task is not sufficient on all
      --  runtimes to wake a blocking OpenSSL SSL_accept/SSL_read/SSL_write or
      --  proxy tunnel receive.  Shut down both directions first, then close;
      --  both operations are best-effort because some tests deliberately race
      --  fixture teardown against client-side failure paths.
      begin
         S.Shutdown_Socket (Sock, S.Shut_Read_Write);
      exception
         when others =>
            null;
      end;

      begin
         S.Close_Socket (Sock);
      exception
         when others =>
            null;
      end;
   end Safe_Close;

   procedure Configure_Fixture_Socket_Timeouts (Sock : S.Socket_Type) is
   begin
      S.Set_Socket_Option
        (Sock,
         S.Socket_Level,
         (Name    => S.Receive_Timeout,
          Timeout => 1.0));
      S.Set_Socket_Option
        (Sock,
         S.Socket_Level,
         (Name    => S.Send_Timeout,
          Timeout => 1.0));
   exception
      when others =>
         null;
   end Configure_Fixture_Socket_Timeouts;

   procedure Configure_Tunnel_Socket_Timeouts (Sock : S.Socket_Type) is
   begin
      S.Set_Socket_Option
        (Sock,
         S.Socket_Level,
         (Name    => S.Receive_Timeout,
          Timeout => 0.02));
      S.Set_Socket_Option
        (Sock,
         S.Socket_Level,
         (Name    => S.Send_Timeout,
          Timeout => 0.02));
   exception
      when others =>
         null;
   end Configure_Tunnel_Socket_Timeouts;

   C_TLS_Fixed_Response   : constant C.int := 1;
   C_TLS_Chunked_Response : constant C.int := 2;
   C_TLS_Expect_Response  : constant C.int := 3;
   C_TLS_H2_Large_Response : constant C.int := 5;

   H2_Large_Response_Size  : constant Natural := 98_304;
   H2_Response_Chunk_Size  : constant Natural := 16_384;

   C_Proxy_CONNECT_Success       : constant C.int := 1;
   C_Proxy_Return_407            : constant C.int := 2;
   C_Proxy_Return_403            : constant C.int := 3;
   C_Proxy_Return_502            : constant C.int := 4;
   C_Proxy_Malformed_Response    : constant C.int := 5;
   C_Proxy_Close_Before_Response : constant C.int := 6;
   C_Proxy_Close_During_TLS      : constant C.int := 7;

   C_SOCKS_No_Auth_Success             : constant C.int := 1;
   C_SOCKS_Username_Password_Success   : constant C.int := 2;
   C_SOCKS_No_Acceptable_Methods       : constant C.int := 3;
   C_SOCKS_Username_Password_Failure   : constant C.int := 4;
   C_SOCKS_Malformed_Auth_Response     : constant C.int := 5;
   C_SOCKS_Connect_General_Failure     : constant C.int := 6;
   C_SOCKS_Connect_Host_Unreachable    : constant C.int := 7;
   C_SOCKS_Connect_Connection_Refused  : constant C.int := 8;
   C_SOCKS_Malformed_Connect_Reply     : constant C.int := 9;
   C_SOCKS_Close_Before_Reply          : constant C.int := 10;
   C_SOCKS_Close_During_TLS            : constant C.int := 11;
   C_SOCKS_Unsupported_Version_Reply   : constant C.int := 12;

   SSL_Filetype_PEM : constant C.int := 1;

   function TLS_Server_Method return System.Address
     with Import, Convention => C, External_Name => "TLS_server_method";
   function SSL_CTX_New (Method : System.Address) return System.Address
     with Import, Convention => C, External_Name => "SSL_CTX_new";
   procedure SSL_CTX_Free (Context : System.Address)
     with Import, Convention => C, External_Name => "SSL_CTX_free";
   function SSL_CTX_Use_Certificate_File
     (Context : System.Address; File : CS.chars_ptr; Kind : C.int) return C.int
     with Import, Convention => C, External_Name => "SSL_CTX_use_certificate_file";
   function SSL_CTX_Use_PrivateKey_File
     (Context : System.Address; File : CS.chars_ptr; Kind : C.int) return C.int
     with Import, Convention => C, External_Name => "SSL_CTX_use_PrivateKey_file";
   function SSL_New (Context : System.Address) return System.Address
     with Import, Convention => C, External_Name => "SSL_new";
   procedure SSL_Free (SSL : System.Address)
     with Import, Convention => C, External_Name => "SSL_free";
   function SSL_Set_FD (SSL : System.Address; FD : C.int) return C.int
     with Import, Convention => C, External_Name => "SSL_set_fd";
   function SSL_Accept (SSL : System.Address) return C.int
     with Import, Convention => C, External_Name => "SSL_accept";
   function SSL_Read
     (SSL : System.Address; Buffer : System.Address; Num : C.int) return C.int
     with Import, Convention => C, External_Name => "SSL_read";
   function SSL_Write
     (SSL : System.Address; Buffer : System.Address; Num : C.int) return C.int
     with Import, Convention => C, External_Name => "SSL_write";
   function SSL_Get_Servername (SSL : System.Address; Name_Type : C.int) return CS.chars_ptr
     with Import, Convention => C, External_Name => "SSL_get_servername";

   type ALPN_Select_Callback_Access is access function
     (SSL    : System.Address;
      Outp   : access System.Address;
      Outlen : access C.unsigned_char;
      Inp    : System.Address;
      Inlen  : C.unsigned;
      Arg    : System.Address) return C.int
     with Convention => C;

   procedure SSL_CTX_Set_ALPN_Select_CB
     (Context  : System.Address;
      Callback : ALPN_Select_Callback_Access;
      Arg      : System.Address)
     with Import, Convention => C, External_Name => "SSL_CTX_set_alpn_select_cb";

   type SNI_Callback_Access is access function
     (SSL : System.Address; Alert : access C.int; Arg : System.Address) return C.int
     with Convention => C;
   SSL_CTRL_SET_TLSEXT_SERVERNAME_CB : constant C.int := 53;

   function SSL_CTX_Callback_Ctrl
     (Context : System.Address; Command : C.int; Callback : SNI_Callback_Access) return C.long
     with Import, Convention => C, External_Name => "SSL_CTX_callback_ctrl";

   function SNI_Callback
     (SSL : System.Address; Alert : access C.int; Arg : System.Address) return C.int
     with Convention => C;

   function ALPN_Select_H2_Callback
     (SSL    : System.Address;
      Outp   : access System.Address;
      Outlen : access C.unsigned_char;
      Inp    : System.Address;
      Inlen  : C.unsigned;
      Arg    : System.Address) return C.int
     with Convention => C;

   protected TLS_State is
      procedure Reset (Mode : C.int; Cert : String; Key : String);
      procedure Set_Port (Port : Natural);
      procedure Set_Result (Value : C.int);
      procedure Append (Text : String);
      procedure Set_SNI;
      function Port return Natural;
      function Result return C.int;
      function Contains (Needle : String) return Boolean;
      function SNI_Seen return Boolean;
      function Cert_File return String;
      function Key_File return String;
      function Mode return C.int;
   private
      Current_Mode : C.int := C_TLS_Fixed_Response;
      Current_Cert : Ada.Strings.Unbounded.Unbounded_String;
      Current_Key  : Ada.Strings.Unbounded.Unbounded_String;
      Current_Port : Natural := 0;
      Current_Result : C.int := 0;
      Current_SNI : Boolean := False;
      Capture : String (1 .. Max_Capture);
      Capture_Last : Natural := 0;
   end TLS_State;

   protected Proxy_State is
      procedure Reset (Origin_Host : String; Origin_Port : Natural; Mode : C.int; Expected_Auth : String);
      procedure Set_Port (Port : Natural);
      procedure Append (Text : String);
      procedure Saw_CONNECT;
      procedure Add_C2O (Count : Natural);
      procedure Add_O2C (Count : Natural);
      function Port return Natural;
      function Origin_Host return String;
      function Origin_Port return Natural;
      function Mode return C.int;
      function Expected_Auth return String;
      function Contains (Needle : String) return Boolean;
      function CONNECT_Seen return Boolean;
      function C2O return Natural;
      function O2C return Natural;
   private
      P_Port : Natural := 0;
      P_Origin_Host : Ada.Strings.Unbounded.Unbounded_String;
      P_Origin_Port : Natural := 0;
      P_Mode : C.int := C_Proxy_CONNECT_Success;
      P_Expected_Auth : Ada.Strings.Unbounded.Unbounded_String;
      P_Saw_CONNECT : Boolean := False;
      P_C2O : Natural := 0;
      P_O2C : Natural := 0;
      Capture : String (1 .. Max_Capture);
      Capture_Last : Natural := 0;
   end Proxy_State;

   protected SOCKS_State is
      procedure Reset (Origin_Host : String; Origin_Port : Natural; Mode : C.int; User : String; Pass : String);
      procedure Set_Port (Port : Natural);
      procedure Append (Data : Ada.Streams.Stream_Element_Array);
      procedure Saw_CONNECT (Host : String; Port : Natural);
      procedure Add_C2O (Count : Natural);
      procedure Add_O2C (Count : Natural);
      procedure Auth_Seen;
      function Port return Natural;
      function Origin_Host return String;
      function Origin_Port return Natural;
      function Mode return C.int;
      function User return String;
      function Pass return String;
      function Contains (Needle : String) return Boolean;
      function CONNECT_Seen return Boolean;
      function Auth_Was_Seen return Boolean;
      function Origin_Equals (Host : String; Port : Natural) return Boolean;
      function C2O return Natural;
      function O2C return Natural;
   private
      S_Port : Natural := 0;
      S_Origin_Host : Ada.Strings.Unbounded.Unbounded_String;
      S_Origin_Port : Natural := 0;
      S_Mode : C.int := C_SOCKS_No_Auth_Success;
      S_User : Ada.Strings.Unbounded.Unbounded_String;
      S_Pass : Ada.Strings.Unbounded.Unbounded_String;
      S_Connect_Host : Ada.Strings.Unbounded.Unbounded_String;
      S_Connect_Port : Natural := 0;
      S_Saw_CONNECT : Boolean := False;
      S_Auth_Seen : Boolean := False;
      S_C2O : Natural := 0;
      S_O2C : Natural := 0;
      Capture : String (1 .. Max_Capture);
      Capture_Last : Natural := 0;
   end SOCKS_State;

   protected body TLS_State is
      procedure Reset (Mode : C.int; Cert : String; Key : String) is
      begin
         Current_Mode := Mode;
         Current_Cert := Ada.Strings.Unbounded.To_Unbounded_String (Cert);
         Current_Key := Ada.Strings.Unbounded.To_Unbounded_String (Key);
         Current_Port := 0;
         Current_Result := 0;
         Current_SNI := False;
         Capture_Last := 0;
      end Reset;
      procedure Set_Port (Port : Natural) is begin Current_Port := Port; end Set_Port;
      procedure Set_Result (Value : C.int) is begin if Current_Result = 0 then Current_Result := Value; end if;
        end Set_Result;
      procedure Append (Text : String) is
         Take : constant Natural := Natural'Min (Text'Length, Max_Capture - Capture_Last);
      begin
         if Take > 0 then
            Capture (Capture_Last + 1 .. Capture_Last + Take) := Text (Text'First .. Text'First + Take - 1);
            Capture_Last := Capture_Last + Take;
         end if;
      end Append;
      procedure Set_SNI is begin Current_SNI := True; end Set_SNI;
      function Port return Natural is begin return Current_Port; end Port;
      function Result return C.int is begin return Current_Result; end Result;
      function Contains (Needle : String) return Boolean is
      begin
         if Needle'Length = 0 then
            return True;
         elsif Capture_Last = 0 then
            return False;
         else
            return Ada.Strings.Fixed.Index (Capture (1 .. Capture_Last), Needle) /= 0;
         end if;
      end Contains;
      function SNI_Seen return Boolean is begin return Current_SNI; end SNI_Seen;
      function Cert_File return String is begin return Ada.Strings.Unbounded.To_String (Current_Cert); end Cert_File;
      function Key_File return String is begin return Ada.Strings.Unbounded.To_String (Current_Key); end Key_File;
      function Mode return C.int is begin return Current_Mode; end Mode;
   end TLS_State;

   protected body Proxy_State is
      procedure Reset (Origin_Host : String; Origin_Port : Natural; Mode : C.int; Expected_Auth : String) is
      begin
         P_Port := 0; P_Origin_Host := Ada.Strings.Unbounded.To_Unbounded_String (Origin_Host);
         P_Origin_Port := Origin_Port; P_Mode := Mode;
           P_Expected_Auth := Ada.Strings.Unbounded.To_Unbounded_String (Expected_Auth);
         P_Saw_CONNECT := False; P_C2O := 0; P_O2C := 0; Capture_Last := 0;
      end Reset;
      procedure Set_Port (Port : Natural) is begin P_Port := Port; end Set_Port;
      procedure Append (Text : String) is
         Take : constant Natural := Natural'Min (Text'Length, Max_Capture - Capture_Last);
      begin
         if Take > 0 then
            Capture (Capture_Last + 1 .. Capture_Last + Take) :=
              Text (Text'First .. Text'First + Take - 1);
            Capture_Last := Capture_Last + Take;
         end if;
      end Append;
      procedure Saw_CONNECT is begin P_Saw_CONNECT := True; end Saw_CONNECT;
      procedure Add_C2O (Count : Natural) is begin P_C2O := P_C2O + Count; end Add_C2O;
      procedure Add_O2C (Count : Natural) is begin P_O2C := P_O2C + Count; end Add_O2C;
      function Port return Natural is begin return P_Port; end Port;
      function Origin_Host return String is begin return Ada.Strings.Unbounded.To_String (P_Origin_Host);
        end Origin_Host;
      function Origin_Port return Natural is begin return P_Origin_Port; end Origin_Port;
      function Mode return C.int is begin return P_Mode; end Mode;
      function Expected_Auth return String is begin return Ada.Strings.Unbounded.To_String (P_Expected_Auth);
        end Expected_Auth;
      function Contains (Needle : String) return Boolean is
      begin
         return Needle'Length = 0 or else (Capture_Last > 0
           and then Ada.Strings.Fixed.Index (Capture (1 .. Capture_Last), Needle) /= 0);
      end Contains;
      function CONNECT_Seen return Boolean is begin return P_Saw_CONNECT; end CONNECT_Seen;
      function C2O return Natural is begin return P_C2O; end C2O;
      function O2C return Natural is begin return P_O2C; end O2C;
   end Proxy_State;

   protected body SOCKS_State is
      procedure Reset (Origin_Host : String; Origin_Port : Natural; Mode : C.int; User : String; Pass : String) is
      begin
         S_Port := 0; S_Origin_Host := Ada.Strings.Unbounded.To_Unbounded_String (Origin_Host);
           S_Origin_Port := Origin_Port;
         S_Mode := Mode; S_User := Ada.Strings.Unbounded.To_Unbounded_String (User);
           S_Pass := Ada.Strings.Unbounded.To_Unbounded_String (Pass);
         S_Connect_Host := Ada.Strings.Unbounded.Null_Unbounded_String; S_Connect_Port := 0;
           S_Saw_CONNECT := False; S_Auth_Seen := False;
         S_C2O := 0; S_O2C := 0; Capture_Last := 0;
      end Reset;
      procedure Set_Port (Port : Natural) is begin S_Port := Port; end Set_Port;
      procedure Append (Data : Ada.Streams.Stream_Element_Array) is
         Take : constant Natural := Natural'Min (Natural (Data'Length), Max_Capture - Capture_Last);
      begin
         for I in 0 .. Take - 1 loop
            Capture (Capture_Last + 1 + I) := Character'Val (Data (Data'First + Ada.Streams.Stream_Element_Offset (I)));
              
         end loop;
         Capture_Last := Capture_Last + Take;
      end Append;
      procedure Saw_CONNECT (Host : String; Port : Natural) is begin S_Saw_CONNECT := True;
        S_Connect_Host := Ada.Strings.Unbounded.To_Unbounded_String (Host); S_Connect_Port := Port; end Saw_CONNECT;
      procedure Add_C2O (Count : Natural) is begin S_C2O := S_C2O + Count; end Add_C2O;
      procedure Add_O2C (Count : Natural) is begin S_O2C := S_O2C + Count; end Add_O2C;
      procedure Auth_Seen is begin S_Auth_Seen := True; end Auth_Seen;
      function Port return Natural is begin return S_Port; end Port;
      function Origin_Host return String is begin return Ada.Strings.Unbounded.To_String (S_Origin_Host);
        end Origin_Host;
      function Origin_Port return Natural is begin return S_Origin_Port; end Origin_Port;
      function Mode return C.int is begin return S_Mode; end Mode;
      function User return String is begin return Ada.Strings.Unbounded.To_String (S_User); end User;
      function Pass return String is begin return Ada.Strings.Unbounded.To_String (S_Pass); end Pass;
      function Contains (Needle : String) return Boolean is
      begin
         return Needle'Length = 0 or else (Capture_Last > 0
           and then Ada.Strings.Fixed.Index (Capture (1 .. Capture_Last), Needle) /= 0);
      end Contains;
      function CONNECT_Seen return Boolean is begin return S_Saw_CONNECT; end CONNECT_Seen;
      function Auth_Was_Seen return Boolean is begin return S_Auth_Seen; end Auth_Was_Seen;
      function Origin_Equals (Host : String;
        Port : Natural) return Boolean is begin return Ada.Strings.Unbounded.To_String (S_Connect_Host) = Host
          and then S_Connect_Port = Port; end Origin_Equals;
      function C2O return Natural is begin return S_C2O; end C2O;
      function O2C return Natural is begin return S_O2C; end O2C;
   end SOCKS_State;

   function SNI_Callback
     (SSL : System.Address; Alert : access C.int; Arg : System.Address) return C.int
   is
      pragma Unreferenced (Alert, Arg);
      Name : constant CS.chars_ptr := SSL_Get_Servername (SSL, 0);
   begin
      if Name /= CS.Null_Ptr and then CS.Value (Name) = "localhost" then
         TLS_State.Set_SNI;
      end if;
      return 0;
   end SNI_Callback;

   function Decimal_Image (Value : Natural) return String;
   procedure SSL_Write_All (SSL : System.Address; Text : String);

   H2_ALPN : aliased constant String := "h2";

   function ALPN_Select_H2_Callback
     (SSL    : System.Address;
      Outp   : access System.Address;
      Outlen : access C.unsigned_char;
      Inp    : System.Address;
      Inlen  : C.unsigned;
      Arg    : System.Address) return C.int
   is
      pragma Unreferenced (SSL, Inp, Inlen, Arg);
   begin
      Outp.all := H2_ALPN (H2_ALPN'First)'Address;
      Outlen.all := 2;
      return 0;
   end ALPN_Select_H2_Callback;

   function Byte (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end Byte;

   function H2_Frame
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String
   is
      Length : constant Natural := Payload'Length;
   begin
      return
        Byte (Length / 65_536) &
        Byte ((Length / 256) mod 256) &
        Byte (Length mod 256) &
        Byte (Natural (Http_Client.HTTP2.Frames.Type_Code (Kind))) &
        Byte (Flags) &
        Byte ((Stream / 16#01_00_00_00#) mod 128) &
        Byte ((Stream / 65_536) mod 256) &
        Byte ((Stream / 256) mod 256) &
        Byte (Stream mod 256) &
        Payload;
   end H2_Frame;

   procedure SSL_Write_H2_Large_Response (SSL : System.Address) is
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Encoder : Http_Client.HTTP2.HPACK.Encoder :=
        Http_Client.HTTP2.HPACK.Create_Encoder;
      Block   : Ada.Strings.Unbounded.Unbounded_String;
      Status  : Http_Client.Errors.Result_Status;
      Payload : String (1 .. H2_Response_Chunk_Size);
      Sent    : Natural := 0;
   begin
      Status := Http_Client.Headers.Add_HTTP2_Pseudo (Headers, ":status", "200");
      if Status /= Http_Client.Errors.Ok then TLS_State.Set_Result (40); return; end if;
      Status := Http_Client.Headers.Add (Headers, "content-length", Decimal_Image (H2_Large_Response_Size));
      if Status /= Http_Client.Errors.Ok then TLS_State.Set_Result (41); return; end if;
      Status := Http_Client.Headers.Add (Headers, "x-tls-fixture", "h2-large");
      if Status /= Http_Client.Errors.Ok then TLS_State.Set_Result (42); return; end if;
      Status := Http_Client.HTTP2.HPACK.Encode_Header_Block (Encoder, Headers, Block);
      if Status /= Http_Client.Errors.Ok then TLS_State.Set_Result (43); return; end if;

      SSL_Write_All (SSL, H2_Frame (Http_Client.HTTP2.Frames.HEADERS, 16#04#, 1, Ada.Strings.Unbounded.To_String (Block)));

      for I in Payload'Range loop
         Payload (I) := Character'Val ((I - Payload'First) mod 251);
      end loop;

      while Sent < H2_Large_Response_Size loop
         declare
            Chunk : constant Natural := Natural'Min (Payload'Length, H2_Large_Response_Size - Sent);
            Last  : constant Boolean := Sent + Chunk = H2_Large_Response_Size;
         begin
            SSL_Write_All
              (SSL,
               H2_Frame
                 (Http_Client.HTTP2.Frames.DATA,
                  (if Last then 16#01# else 0),
                  1,
                  Payload (Payload'First .. Payload'First + Chunk - 1)));
            Sent := Sent + Chunk;
         end;
      end loop;
   end SSL_Write_H2_Large_Response;

   function Decimal_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal_Image;

   function Header_End (Text : String) return Natural is
   begin
      for I in Text'First .. Text'Last - 3 loop
         if Text (I .. I + 3) = ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF then return I + 3; end if;
      end loop;
      return 0;
   end Header_End;

   function Content_Length (Headers : String) return Natural is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Headers);
      Pos : constant Natural := Ada.Strings.Fixed.Index (Lower, "content-length:");
      J : Natural;
   begin
      if Pos = 0 then return 0; end if;
      J := Pos + 15;
      while J <= Headers'Last and then Headers (J) = ' ' loop J := J + 1; end loop;
      declare
         K : Natural := J;
      begin
         while K <= Headers'Last and then Headers (K) in '0' .. '9' loop K := K + 1; end loop;
         if K = J then return 0; end if;
         return Natural'Value (Headers (J .. K - 1));
      end;
   exception
      when others => return 0;
   end Content_Length;

   function Request_Complete (Text : String; Mode : C.int) return Boolean is
      H : constant Natural := Header_End (Text);
   begin
      if H = 0 then return False; end if;
      if Ada.Strings.Fixed.Index (Text (Text'First .. H), "Transfer-Encoding: chunked") /= 0 then
         return Ada.Strings.Fixed.Index (Text (H + 1 .. Text'Last), ASCII.CR & ASCII.LF & "0" & ASCII.CR &
           ASCII.LF & ASCII.CR & ASCII.LF) /= 0
           or else Ada.Strings.Fixed.Index (Text (H + 1 .. Text'Last), ASCII.CR & ASCII.LF & "0" & ASCII.CR &
             ASCII.LF & "X-Request-Trailer: done" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF) /= 0;
      end if;
      return Text'Length >= H + Content_Length (Text (Text'First .. H));
   end Request_Complete;

   procedure SSL_Write_All (SSL : System.Address; Text : String) is
      Sent : Natural := 0;
      N : C.int;
   begin
      while Sent < Text'Length loop
         N := SSL_Write (SSL, Text (Text'First + Sent)'Address, C.int (Text'Length - Sent));
         exit when N <= 0;
         Sent := Sent + Natural (N);
      end loop;
   end SSL_Write_All;

   procedure SSL_Write_All (SSL : System.Address; Data : Ada.Streams.Stream_Element_Array) is
      Sent : Natural := 0;
      N : C.int;
   begin
      while Sent < Natural (Data'Length) loop
         N := SSL_Write (SSL, Data (Data'First + Ada.Streams.Stream_Element_Offset (Sent))'Address,
           C.int (Natural (Data'Length) - Sent));
         exit when N <= 0;
         Sent := Sent + Natural (N);
      end loop;
   end SSL_Write_All;

   task type TLS_Server;
   TLS_Current : access TLS_Server;

   task body TLS_Server is
      Server : S.Socket_Type;
      Client : S.Socket_Type;
      Addr   : S.Sock_Addr_Type;
      Context : System.Address := System.Null_Address;
      SSL : System.Address := System.Null_Address;
      Cert : CS.chars_ptr := CS.Null_Ptr;
      Key : CS.chars_ptr := CS.Null_Ptr;
   begin
      S.Initialize;
      S.Create_Socket (Server);
      Configure_Fixture_Socket_Timeouts (Server);
      TLS_Server_Socket := Server;
      TLS_Server_Open := True;
      S.Set_Socket_Option (Server, S.Socket_Level, (S.Reuse_Address, True));
      S.Bind_Socket (Server, (S.Family_Inet, S.Inet_Addr ("127.0.0.1"), 0));
      S.Listen_Socket (Server);
      Addr := S.Get_Socket_Name (Server);

      Context := SSL_CTX_New (TLS_Server_Method);
      if Context = System.Null_Address then TLS_State.Set_Result (10); raise Stop_Fixture; end if;
      declare
         Ignored : C.long := SSL_CTX_Callback_Ctrl
           (Context, SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, SNI_Callback'Access);
      begin
         null;
      end;
      if TLS_State.Mode = C_TLS_H2_Large_Response then
         SSL_CTX_Set_ALPN_Select_CB
           (Context, ALPN_Select_H2_Callback'Access, System.Null_Address);
      end if;
      Cert := CS.New_String (TLS_State.Cert_File); Key := CS.New_String (TLS_State.Key_File);
      if SSL_CTX_Use_Certificate_File (Context, Cert, SSL_Filetype_PEM) /= 1 then TLS_State.Set_Result (11);
        raise Stop_Fixture; end if;
      if SSL_CTX_Use_PrivateKey_File (Context, Key, SSL_Filetype_PEM) /= 1 then TLS_State.Set_Result (12);
        raise Stop_Fixture; end if;
      CS.Free (Cert); CS.Free (Key); Cert := CS.Null_Ptr; Key := CS.Null_Ptr;
      TLS_State.Set_Port (Natural (Addr.Port));

      S.Accept_Socket (Server, Client, Addr);
      Configure_Fixture_Socket_Timeouts (Client);
      TLS_Client_Socket := Client;
      TLS_Client_Open := True;
      SSL := SSL_New (Context);
      if SSL = System.Null_Address then TLS_State.Set_Result (18); raise Stop_Fixture; end if;
      if SSL_Set_FD (SSL, C.int (S.To_C (Client))) /= 1 then TLS_State.Set_Result (18); raise Stop_Fixture; end if;
      if SSL_Accept (SSL) /= 1 then TLS_State.Set_Result (19); raise Stop_Fixture; end if;

      if TLS_State.Mode = C_TLS_H2_Large_Response then
         declare
            Buffer : String (1 .. 4096);
            Request : Ada.Strings.Unbounded.Unbounded_String;
            N : C.int;
         begin
            loop
               N := SSL_Read (SSL, Buffer (Buffer'First)'Address, C.int (Buffer'Length));
               exit when N <= 0;
               declare
                  Part : constant String := Buffer (1 .. Natural (N));
               begin
                  TLS_State.Append (Part);
                  Ada.Strings.Unbounded.Append (Request, Part);
               end;
               exit when Ada.Strings.Fixed.Index
                 (Ada.Strings.Unbounded.To_String (Request),
                  Http_Client.HTTP2.Client_Connection_Preface) /= 0;
            end loop;

            SSL_Write_All
              (SSL, H2_Frame (Http_Client.HTTP2.Frames.SETTINGS, 0, 0, ""));

            N := SSL_Read (SSL, Buffer (Buffer'First)'Address, C.int (Buffer'Length));
            if N > 0 then
               declare
                  Part : constant String := Buffer (1 .. Natural (N));
               begin
                  TLS_State.Append (Part);
               end;
            end if;
         end;

         SSL_Write_H2_Large_Response (SSL);
         declare
            Buffer : String (1 .. 4096);
            N      : C.int;
         begin
            loop
               N := SSL_Read (SSL, Buffer (Buffer'First)'Address, C.int (Buffer'Length));
               exit when N <= 0;
               TLS_State.Append (Buffer (1 .. Natural (N)));
            end loop;
         end;
         SSL_Free (SSL); SSL := System.Null_Address;
         SSL_CTX_Free (Context); Context := System.Null_Address;
         Safe_Close (Client);
         Safe_Close (Server);
         TLS_Client_Open := False;
         TLS_Server_Open := False;
         raise Stop_Fixture;
      end if;

      declare
         Buffer : String (1 .. 4096);
         Request : Ada.Strings.Unbounded.Unbounded_String;
         N : C.int;
         Sent_Continue : Boolean := False;
      begin
         loop
            N := SSL_Read (SSL, Buffer (Buffer'First)'Address, C.int (Buffer'Length));
            exit when N <= 0;
            declare
               Part : constant String := Buffer (1 .. Natural (N));
            begin
               TLS_State.Append (Part);
               Ada.Strings.Unbounded.Append (Request, Part);
            end;
            declare
               Text : constant String := Ada.Strings.Unbounded.To_String (Request);
            begin
               if not Sent_Continue and then TLS_State.Mode = C_TLS_Expect_Response
                 and then Header_End (Text) /= 0
                   and then Ada.Strings.Fixed.Index (Text, "Expect: 100-continue") /= 0 then
                  SSL_Write_All (SSL, "HTTP/1.1 100 Continue" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
                  Sent_Continue := True;
               end if;
               exit when Request_Complete (Text, TLS_State.Mode);
            end;
         end loop;
      end;

      if TLS_State.Mode = C_TLS_Chunked_Response then
         SSL_Write_All (SSL, "HTTP/1.1 200 OK" & ASCII.CR & ASCII.LF & "Transfer-Encoding: chunked" & ASCII.CR &
           ASCII.LF & "Connection: close" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF & "3" & ASCII.CR & ASCII.LF);
         SSL_Write_All (SSL, Ada.Streams.Stream_Element_Array'(1 => 16#00#, 2 => 16#0D#, 3 => 16#0A#));
         SSL_Write_All (SSL, ASCII.CR & ASCII.LF & "4" & ASCII.CR & ASCII.LF);
         SSL_Write_All (SSL, Ada.Streams.Stream_Element_Array'(1 => 16#80#, 2 => 16#FF#,
           3 => Character'Pos ('P'), 4 => Character'Pos ('K')));
         SSL_Write_All (SSL, ASCII.CR & ASCII.LF & "0" & ASCII.CR & ASCII.LF & "X-Trailer: ok" & ASCII.CR &
           ASCII.LF & ASCII.CR & ASCII.LF);
      else
         SSL_Write_All (SSL, "HTTP/1.1 200 OK" & ASCII.CR & ASCII.LF & "Content-Length: 7" & ASCII.CR & ASCII.LF &
           "X-TLS-Fixture: direct" & ASCII.CR & ASCII.LF & "Connection: close" & ASCII.CR & ASCII.LF & ASCII.CR &
             ASCII.LF);
         SSL_Write_All (SSL, Ada.Streams.Stream_Element_Array'(1 => 16#00#, 2 => 16#0D#, 3 => 16#0A#,
           4 => 16#80#, 5 => 16#FF#, 6 => Character'Pos ('P'), 7 => Character'Pos ('K')));
      end if;
      --  Do not call SSL_shutdown here.  The local fixture writes a complete
      --  response and then closes the socket; waiting for peer close_notify
      --  can deadlock tunnel/proxy tests whose client side keeps the TLS
      --  connection open until the HTTP response parser completes.
      SSL_Free (SSL); SSL := System.Null_Address;
      SSL_CTX_Free (Context); Context := System.Null_Address;
      Safe_Close (Client);
      Safe_Close (Server);
      TLS_Client_Open := False;
      TLS_Server_Open := False;
   exception
      when Stop_Fixture =>
         if Cert /= CS.Null_Ptr then
            CS.Free (Cert);
         end if;
         if Key /= CS.Null_Ptr then
            CS.Free (Key);
         end if;
         if SSL /= System.Null_Address then
            SSL_Free (SSL);
         end if;
         if Context /= System.Null_Address then
            SSL_CTX_Free (Context);
         end if;
         if TLS_Client_Open then
            Safe_Close (Client);
            TLS_Client_Open := False;
         end if;
         if TLS_Server_Open then
            Safe_Close (Server);
            TLS_Server_Open := False;
         end if;
      when others =>
         TLS_State.Set_Result (99);
         if Cert /= CS.Null_Ptr then
            CS.Free (Cert);
         end if;
         if Key /= CS.Null_Ptr then
            CS.Free (Key);
         end if;
         if SSL /= System.Null_Address then
            SSL_Free (SSL);
         end if;
         if Context /= System.Null_Address then
            SSL_CTX_Free (Context);
         end if;
         if TLS_Client_Open then
            Safe_Close (Client);
            TLS_Client_Open := False;
         end if;
         if TLS_Server_Open then
            Safe_Close (Server);
            TLS_Server_Open := False;
         end if;
   end TLS_Server;

   procedure Send_All (Sock : S.Socket_Type; Data : Ada.Streams.Stream_Element_Array) is
      First : Ada.Streams.Stream_Element_Offset := Data'First;
      Last  : Ada.Streams.Stream_Element_Offset;
   begin
      while First <= Data'Last loop
         S.Send_Socket (Sock, Data (First .. Data'Last), Last);
         exit when Last < First;
         First := Last + 1;
      end loop;
   end Send_All;

   procedure Send_All (Sock : S.Socket_Type; Text : String) is
      Data : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for I in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset (I - Text'First + 1)) :=
           Character'Pos (Text (I));
      end loop;
      Send_All (Sock, Data);
   end Send_All;

   function Receive_Some (Sock : S.Socket_Type; Buffer : out Ada.Streams.Stream_Element_Array) return Natural is
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      S.Receive_Socket (Sock, Buffer, Last);
      if Last < Buffer'First then return 0; end if;
      return Natural (Last - Buffer'First + 1);
   exception
      when others => return 0;
   end Receive_Some;

   function Receive_Exact
     (Sock   : S.Socket_Type;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Count  : Natural) return Boolean
   is
      First       : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Target_Last : Ada.Streams.Stream_Element_Offset;
      Last        : Ada.Streams.Stream_Element_Offset;
   begin
      if Count = 0 then
         return True;
      end if;

      if Count > Natural (Buffer'Length) then
         return False;
      end if;

      Target_Last :=
        Buffer'First + Ada.Streams.Stream_Element_Offset (Count - 1);

      while First <= Target_Last loop
         S.Receive_Socket (Sock, Buffer (First .. Target_Last), Last);
         if Last < First then
            return False;
         end if;
         First := Last + 1;
      end loop;

      return True;
   exception
      when others =>
         return False;
   end Receive_Exact;

   function To_String (Data : Ada.Streams.Stream_Element_Array; Count : Natural) return String is
      Result : String (1 .. Count);
   begin
      for I in 1 .. Count loop
         Result (I) := Character'Val
           (Data (Data'First + Ada.Streams.Stream_Element_Offset (I - 1)));
      end loop;
      return Result;
   end To_String;

   function Read_Headers (Sock : S.Socket_Type; Capture_Proxy : Boolean) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Text : Ada.Strings.Unbounded.Unbounded_String;
      Count : Natural;
   begin
      loop
         Count := Receive_Some (Sock, Buffer);
         exit when Count = 0;
         declare Part : constant String := To_String (Buffer, Count); begin
            if Capture_Proxy then Proxy_State.Append (Part); end if;
            Ada.Strings.Unbounded.Append (Text, Part);
         end;
         exit when Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (Text), ASCII.CR & ASCII.LF &
           ASCII.CR & ASCII.LF) /= 0;
      end loop;
      return Ada.Strings.Unbounded.To_String (Text);
   end Read_Headers;

   procedure Connect_To_Origin (Sock : out S.Socket_Type; Host : String; Port : Natural) is
   begin
      S.Create_Socket (Sock);
      Configure_Fixture_Socket_Timeouts (Sock);
      S.Connect_Socket (Sock, (S.Family_Inet, S.Inet_Addr (Host), S.Port_Type (Port)));
   end Connect_To_Origin;

   type Direction is (Client_To_Origin, Origin_To_Client);

   protected Pump_State is
      procedure Reset;
      procedure Mark_Done;
      function Done_Count return Natural;
   private
      Done : Natural := 0;
   end Pump_State;

   protected body Pump_State is
      procedure Reset is
      begin
         Done := 0;
      end Reset;

      procedure Mark_Done is
      begin
         Done := Done + 1;
      end Mark_Done;

      function Done_Count return Natural is
      begin
         return Done;
      end Done_Count;
   end Pump_State;

   task type Pump_Task
     (From     : access S.Socket_Type;
      To       : access S.Socket_Type;
      Dir      : Direction;
      Is_SOCKS : Boolean);

   task body Pump_Task is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Count  : Natural;
   begin
      loop
         Count := Receive_Some (From.all, Buffer);
         exit when Count = 0;

         Send_All
           (To.all,
            Buffer
              (Buffer'First
               .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count - 1)));

         if Dir = Client_To_Origin then
            if Is_SOCKS then
               SOCKS_State.Add_C2O (Count);
            else
               Proxy_State.Add_C2O (Count);
            end if;
         else
            if Is_SOCKS then
               SOCKS_State.Add_O2C (Count);
            else
               Proxy_State.Add_O2C (Count);
            end if;
         end if;
      end loop;

      begin
         S.Close_Socket (From.all);
      exception
         when others =>
            null;
      end;

      begin
         S.Close_Socket (To.all);
      exception
         when others =>
            null;
      end;

      Pump_State.Mark_Done;
   exception
      when others =>
         begin
            S.Close_Socket (From.all);
         exception
            when others =>
               null;
         end;

         begin
            S.Close_Socket (To.all);
         exception
            when others =>
               null;
         end;

         Pump_State.Mark_Done;
   end Pump_Task;

   procedure Pump_Tunnel
     (Client   : in out S.Socket_Type;
      Origin   : in out S.Socket_Type;
      Is_SOCKS : Boolean)
   is
      Buffer       : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Count        : Natural;
      Idle_Ticks   : Natural := 0;
      Total_C2O    : Natural := 0;
      Total_O2C    : Natural := 0;
      Progress     : Boolean;

      procedure Add_C2O (Amount : Natural) is
      begin
         Total_C2O := Total_C2O + Amount;
         if Is_SOCKS then
            SOCKS_State.Add_C2O (Amount);
         else
            Proxy_State.Add_C2O (Amount);
         end if;
      end Add_C2O;

      procedure Add_O2C (Amount : Natural) is
      begin
         Total_O2C := Total_O2C + Amount;
         if Is_SOCKS then
            SOCKS_State.Add_O2C (Amount);
         else
            Proxy_State.Add_O2C (Amount);
         end if;
      end Add_O2C;

      procedure Close_Both is
      begin
         Safe_Close (Client);
         Safe_Close (Origin);
      end Close_Both;
   begin
      --  Keep tunnel ownership inside the proxy fixture task.  Earlier
      --  versions spawned nested pump tasks; if either nested task remained
      --  blocked in socket I/O, finalization could keep the AUnit section from
      --  producing its report.  This bounded alternating pump is sufficient for
      --  the local TLS handshake/request/response tests and has no dependent
      --  tasks to strand.
      Configure_Tunnel_Socket_Timeouts (Client);
      Configure_Tunnel_Socket_Timeouts (Origin);

      for Tick in 1 .. 1000 loop
         pragma Unreferenced (Tick);
         Progress := False;

         Count := Receive_Some (Client, Buffer);
         if Count > 0 then
            Send_All
              (Origin,
               Buffer
                 (Buffer'First
                  .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count - 1)));
            Add_C2O (Count);
            Progress := True;
         end if;

         Count := Receive_Some (Origin, Buffer);
         if Count > 0 then
            Send_All
              (Client,
               Buffer
                 (Buffer'First
                  .. Buffer'First + Ada.Streams.Stream_Element_Offset (Count - 1)));
            Add_O2C (Count);
            Progress := True;
         end if;

         if Progress then
            Idle_Ticks := 0;
         else
            Idle_Ticks := Idle_Ticks + 1;
         end if;

         exit when Total_C2O > 0 and then Total_O2C > 0 and then Idle_Ticks >= 25;
      end loop;

      Close_Both;
   exception
      when others =>
         Close_Both;
   end Pump_Tunnel;

   task type Proxy_Server;
   Proxy_Current : access Proxy_Server;
   task body Proxy_Server is
      Server, Client, Origin : S.Socket_Type;
      Addr : S.Sock_Addr_Type;
      Request : Ada.Strings.Unbounded.Unbounded_String;
   begin
      S.Initialize;
      S.Create_Socket (Server);
      Configure_Fixture_Socket_Timeouts (Server);
      Proxy_Server_Socket := Server;
      Proxy_Server_Open := True;
      S.Set_Socket_Option (Server, S.Socket_Level, (S.Reuse_Address, True));
      S.Bind_Socket (Server, (S.Family_Inet, S.Inet_Addr ("127.0.0.1"), 0));
      S.Listen_Socket (Server); Addr := S.Get_Socket_Name (Server); Proxy_State.Set_Port (Natural (Addr.Port));
      S.Accept_Socket (Server, Client, Addr);
      Configure_Fixture_Socket_Timeouts (Client);
      Proxy_Client_Socket := Client;
      Proxy_Client_Open := True;
      if Proxy_State.Mode = C_Proxy_Close_Before_Response then S.Close_Socket (Client); S.Close_Socket (Server);
        raise Stop_Fixture; end if;
      Request := Ada.Strings.Unbounded.To_Unbounded_String (Read_Headers (Client, True));
      if Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (Request),
        "CONNECT ") = 1 then Proxy_State.Saw_CONNECT; end if;
      if Proxy_State.Mode = C_Proxy_Return_407
        or else (Proxy_State.Expected_Auth /= ""
          and then Ada.Strings.Fixed.Index (Ada.Strings.Unbounded.To_String (Request),
            Proxy_State.Expected_Auth) = 0) then
         Send_All (Client, "HTTP/1.1 407 Proxy Authentication Required" & ASCII.CR & ASCII.LF &
           "Content-Length: 0" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF); S.Close_Socket (Client);
             S.Close_Socket (Server); raise Stop_Fixture;
      elsif Proxy_State.Mode = C_Proxy_Return_403 then
         Send_All (Client, "HTTP/1.1 403 Forbidden" & ASCII.CR & ASCII.LF & "Content-Length: 0" & ASCII.CR &
           ASCII.LF & ASCII.CR & ASCII.LF); S.Close_Socket (Client); S.Close_Socket (Server); raise Stop_Fixture;
      elsif Proxy_State.Mode = C_Proxy_Return_502 then
         Send_All (Client, "HTTP/1.1 502 Bad Gateway" & ASCII.CR & ASCII.LF & "Content-Length: 0" & ASCII.CR &
           ASCII.LF & ASCII.CR & ASCII.LF); S.Close_Socket (Client); S.Close_Socket (Server); raise Stop_Fixture;
      elsif Proxy_State.Mode = C_Proxy_Malformed_Response then
         Send_All (Client, "NOT HTTP" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF); S.Close_Socket (Client);
           S.Close_Socket (Server); raise Stop_Fixture;
      end if;
      if Proxy_State.Mode = C_Proxy_Close_During_TLS then
         Send_All (Client, "HTTP/1.1 200 Connection Established" & ASCII.CR & ASCII.LF & "Proxy-Agent: local-test" &
           ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
         Safe_Close (Client);
         Safe_Close (Server);
         Proxy_Client_Open := False;
         Proxy_Server_Open := False;
         raise Stop_Fixture;
      end if;

      Connect_To_Origin (Origin, Proxy_State.Origin_Host, Proxy_State.Origin_Port);
      Proxy_Origin_Socket := Origin;
      Proxy_Origin_Open := True;
      Send_All (Client, "HTTP/1.1 200 Connection Established" & ASCII.CR & ASCII.LF & "Proxy-Agent: local-test" &
        ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF);
      Pump_Tunnel (Client, Origin, False);
      Safe_Close (Origin);
      Safe_Close (Client);
      Safe_Close (Server);
      Proxy_Origin_Open := False;
      Proxy_Client_Open := False;
      Proxy_Server_Open := False;
   exception
      when Stop_Fixture => null;
      when others => null;
   end Proxy_Server;

   task type SOCKS_Server;
   SOCKS_Current : access SOCKS_Server;
   task body SOCKS_Server is
      Server : S.Socket_Type;
      Client : S.Socket_Type;
      Origin : S.Socket_Type;
      Addr   : S.Sock_Addr_Type;
      B      : Ada.Streams.Stream_Element_Array (1 .. 512);
      Count  : Natural;
      Host   : String (1 .. 255);
      Host_Len : Natural := 0;
      Port   : Natural := 0;

      procedure Close_Client_Server is
      begin
         begin
            S.Close_Socket (Client);
            SOCKS_Client_Open := False;
         exception
            when others =>
               null;
         end;

         begin
            S.Close_Socket (Server);
            SOCKS_Server_Open := False;
         exception
            when others =>
               null;
         end;
      end Close_Client_Server;

      procedure Send_Reply (Code : Ada.Streams.Stream_Element) is
      begin
         Send_All
           (Client,
            Ada.Streams.Stream_Element_Array'
              (1  => 16#05#,
               2  => Code,
               3  => 0,
               4  => 1,
               5  => 0,
               6  => 0,
               7  => 0,
               8  => 0,
               9  => 0,
               10 => 0));
      end Send_Reply;
   begin
      S.Initialize;
      S.Create_Socket (Server);
      Configure_Fixture_Socket_Timeouts (Server);
      SOCKS_Server_Socket := Server;
      SOCKS_Server_Open := True;
      S.Set_Socket_Option
        (Server,
         S.Socket_Level,
         (S.Reuse_Address, True));
      S.Bind_Socket
        (Server,
         (S.Family_Inet, S.Inet_Addr ("127.0.0.1"), 0));
      S.Listen_Socket (Server);
      Addr := S.Get_Socket_Name (Server);
      SOCKS_State.Set_Port (Natural (Addr.Port));
      S.Accept_Socket (Server, Client, Addr);
      Configure_Fixture_Socket_Timeouts (Client);
      SOCKS_Client_Socket := Client;
      SOCKS_Client_Open := True;

      if not Receive_Exact (Client, B (1 .. 2), 2) then
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      declare
         Method_Count : constant Natural := Natural (B (2));
         Want_Userpass : constant Boolean :=
           SOCKS_State.Mode = C_SOCKS_Username_Password_Success
           or else SOCKS_State.Mode = C_SOCKS_Username_Password_Failure
           or else SOCKS_State.Mode = C_SOCKS_Malformed_Auth_Response;
         Have_No_Auth : Boolean := False;
         Have_Userpass : Boolean := False;
      begin
         if Method_Count = 0 or else Method_Count > 255 then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         if not Receive_Exact (Client, B (3 .. B'Last), Method_Count) then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         SOCKS_State.Append
           (B (1 .. Ada.Streams.Stream_Element_Offset (2 + Method_Count)));

         for I in 1 .. Method_Count loop
            declare
               Method : constant Ada.Streams.Stream_Element :=
                 B (Ada.Streams.Stream_Element_Offset (2 + I));
            begin
               if Method = 16#00# then
                  Have_No_Auth := True;
               elsif Method = 16#02# then
                  Have_Userpass := True;
               end if;
            end;
         end loop;

         if SOCKS_State.Mode = C_SOCKS_No_Acceptable_Methods
           or else (Want_Userpass and then not Have_Userpass)
           or else ((not Want_Userpass) and then not Have_No_Auth)
         then
            Send_All
              (Client,
               Ada.Streams.Stream_Element_Array'(1 => 16#05#, 2 => 16#FF#));
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         if Want_Userpass then
            Send_All
              (Client,
               Ada.Streams.Stream_Element_Array'(1 => 16#05#, 2 => 16#02#));
         else
            Send_All
              (Client,
               Ada.Streams.Stream_Element_Array'(1 => 16#05#, 2 => 16#00#));
         end if;
      end;

      if SOCKS_State.Mode = C_SOCKS_Username_Password_Success
        or else SOCKS_State.Mode = C_SOCKS_Username_Password_Failure
        or else SOCKS_State.Mode = C_SOCKS_Malformed_Auth_Response
      then

         if not Receive_Exact (Client, B (1 .. 2), 2) then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         declare
            User_Len : constant Natural := Natural (B (2));
            Pass_Len : Natural := 0;
            Total    : Natural;
         begin
            if not Receive_Exact (Client, B (3 .. B'Last), User_Len + 1) then
               Close_Client_Server;
               raise Stop_Fixture;
            end if;

            Pass_Len := Natural (B (3 + Ada.Streams.Stream_Element_Offset (User_Len)));
            if not Receive_Exact
              (Client,
               B (4 + Ada.Streams.Stream_Element_Offset (User_Len) .. B'Last),
               Pass_Len)
            then
               Close_Client_Server;
               raise Stop_Fixture;
            end if;

            Total := 3 + User_Len + Pass_Len;
            SOCKS_State.Append
              (B (1 .. Ada.Streams.Stream_Element_Offset (Total)));
            SOCKS_State.Auth_Seen;
         end;

         if SOCKS_State.Mode = C_SOCKS_Malformed_Auth_Response then
            Send_All
              (Client,
               Ada.Streams.Stream_Element_Array'(1 => 16#02#, 2 => 16#00#));
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         if SOCKS_State.Mode = C_SOCKS_Username_Password_Failure then
            Send_All
              (Client,
               Ada.Streams.Stream_Element_Array'(1 => 16#01#, 2 => 16#01#));
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         Send_All
           (Client,
            Ada.Streams.Stream_Element_Array'(1 => 16#01#, 2 => 16#00#));
      elsif SOCKS_State.Mode = C_SOCKS_Unsupported_Version_Reply then
         Send_All
           (Client,
            Ada.Streams.Stream_Element_Array'(1 => 16#04#, 2 => 16#00#));
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      if not Receive_Exact (Client, B (1 .. 4), 4) then
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      if B (4) = 16#01# then
         if not Receive_Exact (Client, B (5 .. 10), 6) then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         declare
            Host_Text : constant String :=
              Decimal_Image (Natural (B (5))) & "." &
              Decimal_Image (Natural (B (6))) & "." &
              Decimal_Image (Natural (B (7))) & "." &
              Decimal_Image (Natural (B (8)));
         begin
            Host_Len := Host_Text'Length;
            Host (1 .. Host_Len) := Host_Text;
         end;
         Port := Natural (B (9)) * 256 + Natural (B (10));
         Count := 10;
      elsif B (4) = 16#03# then
         if not Receive_Exact (Client, B (5 .. 5), 1) then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         Host_Len := Natural (B (5));
         if not Receive_Exact
           (Client,
            B (6 .. B'Last),
            Host_Len + 2)
         then
            Close_Client_Server;
            raise Stop_Fixture;
         end if;

         for I in 1 .. Host_Len loop
            Host (I) :=
              Character'Val
                (B (Ada.Streams.Stream_Element_Offset (5 + I)));
         end loop;
         Port :=
           Natural (B (Ada.Streams.Stream_Element_Offset (6 + Host_Len))) * 256
           + Natural (B (Ada.Streams.Stream_Element_Offset (7 + Host_Len)));
         Count := 7 + Host_Len;
      else
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      SOCKS_State.Append (B (1 .. Ada.Streams.Stream_Element_Offset (Count)));
      SOCKS_State.Saw_CONNECT (Host (1 .. Host_Len), Port);

      if SOCKS_State.Mode = C_SOCKS_Close_Before_Reply then
         Close_Client_Server;
         raise Stop_Fixture;
      elsif SOCKS_State.Mode = C_SOCKS_Malformed_Connect_Reply then
         Send_All
           (Client,
            Ada.Streams.Stream_Element_Array'
              (1 => 16#05#, 2 => 16#00#, 3 => 16#00#));
         Close_Client_Server;
         raise Stop_Fixture;
      elsif SOCKS_State.Mode = C_SOCKS_Connect_General_Failure then
         Send_Reply (16#01#);
         Close_Client_Server;
         raise Stop_Fixture;
      elsif SOCKS_State.Mode = C_SOCKS_Connect_Host_Unreachable then
         Send_Reply (16#04#);
         Close_Client_Server;
         raise Stop_Fixture;
      elsif SOCKS_State.Mode = C_SOCKS_Connect_Connection_Refused then
         Send_Reply (16#05#);
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      if SOCKS_State.Mode = C_SOCKS_Close_During_TLS then
         Send_Reply (16#00#);
         Close_Client_Server;
         raise Stop_Fixture;
      end if;

      Connect_To_Origin (Origin, SOCKS_State.Origin_Host, SOCKS_State.Origin_Port);
      SOCKS_Origin_Socket := Origin;
      SOCKS_Origin_Open := True;
      Send_Reply (16#00#);
      Pump_Tunnel (Client, Origin, True);

      begin
         S.Close_Socket (Origin);
         SOCKS_Origin_Open := False;
      exception
         when others =>
            null;
      end;
      Close_Client_Server;
   exception
      when Stop_Fixture =>
         null;
      when others =>
         null;
   end SOCKS_Server;

   function Start_TLS
     (Certificate_File : String;
      Private_Key_File : String;
      Mode             : Fixture_Mode) return Natural is
   begin
      TLS_Client_Open := False;
      TLS_Server_Open := False;
      TLS_State.Reset (C.int (Mode), Certificate_File, Private_Key_File);
      TLS_Current := new TLS_Server;
      for I in 1 .. 200 loop
         exit when TLS_State.Port /= 0 or else TLS_State.Result /= 0;
         delay 0.01;
      end loop;
      return TLS_State.Port;
   end Start_TLS;

   procedure Stop_TLS is
   begin
      if TLS_Client_Open then
         Safe_Close (TLS_Client_Socket);
         TLS_Client_Open := False;
      end if;

      if TLS_Server_Open then
         Safe_Close (TLS_Server_Socket);
         TLS_Server_Open := False;
      end if;

      for I in 1 .. 200 loop
         exit when TLS_Current = null or else TLS_Current.all'Terminated;
         delay 0.01;
      end loop;

      if TLS_Current /= null and then not TLS_Current.all'Terminated then
         abort TLS_Current.all;
         for I in 1 .. 200 loop
            exit when TLS_Current.all'Terminated;
            delay 0.01;
         end loop;
      end if;

      TLS_Current := null;
   end Stop_TLS;

   function TLS_Join_Result return Integer is
   begin
      return Integer (TLS_State.Result);
   end TLS_Join_Result;

   function TLS_Request_Contains (Needle : String) return Boolean is
   begin
      return TLS_State.Contains (Needle);
   end TLS_Request_Contains;

   function TLS_SNI_Seen return Boolean is
   begin
      return TLS_State.SNI_Seen;
   end TLS_SNI_Seen;

   function Start_CONNECT_Proxy
     (Origin_Host         : String;
      Origin_Port         : Natural;
      Mode                : Fixture_Mode;
      Expected_Proxy_Auth : String := "") return Natural is
   begin
      Proxy_Origin_Open := False;
      Proxy_Client_Open := False;
      Proxy_Server_Open := False;
      Proxy_State.Reset (Origin_Host, Origin_Port, C.int (Mode), Expected_Proxy_Auth);
      Proxy_Current := new Proxy_Server;
      for I in 1 .. 200 loop
         exit when Proxy_State.Port /= 0 or else Proxy_Current.all'Terminated;
         delay 0.01;
      end loop;
      return Proxy_State.Port;
   end Start_CONNECT_Proxy;

   procedure Stop_CONNECT_Proxy is
   begin
      if Proxy_Origin_Open then
         Safe_Close (Proxy_Origin_Socket);
         Proxy_Origin_Open := False;
      end if;

      if Proxy_Client_Open then
         Safe_Close (Proxy_Client_Socket);
         Proxy_Client_Open := False;
      end if;

      if Proxy_Server_Open then
         Safe_Close (Proxy_Server_Socket);
         Proxy_Server_Open := False;
      end if;

      for I in 1 .. 200 loop
         exit when Proxy_Current = null or else Proxy_Current.all'Terminated;
         delay 0.01;
      end loop;

      if Proxy_Current /= null and then not Proxy_Current.all'Terminated then
         abort Proxy_Current.all;
         for I in 1 .. 200 loop
            exit when Proxy_Current.all'Terminated;
            delay 0.01;
         end loop;
      end if;

      Proxy_Current := null;
   end Stop_CONNECT_Proxy;

   function CONNECT_Capture_Contains (Needle : String) return Boolean is
   begin
      return Proxy_State.Contains (Needle);
   end CONNECT_Capture_Contains;

   function CONNECT_Saw_CONNECT return Boolean is
   begin
      return Proxy_State.CONNECT_Seen;
   end CONNECT_Saw_CONNECT;

   function CONNECT_Tunnel_Client_To_Origin_Bytes return Natural is
   begin
      return Proxy_State.C2O;
   end CONNECT_Tunnel_Client_To_Origin_Bytes;

   function CONNECT_Tunnel_Origin_To_Client_Bytes return Natural is
   begin
      return Proxy_State.O2C;
   end CONNECT_Tunnel_Origin_To_Client_Bytes;

   function Start_SOCKS5_Proxy
     (Origin_Host   : String;
      Origin_Port   : Natural;
      Mode          : Fixture_Mode;
      Expected_User : String := "";
      Expected_Pass : String := "") return Natural is
   begin
      SOCKS_Origin_Open := False;
      SOCKS_Client_Open := False;
      SOCKS_Server_Open := False;
      SOCKS_State.Reset (Origin_Host, Origin_Port, C.int (Mode), Expected_User, Expected_Pass);
      SOCKS_Current := new SOCKS_Server;
      for I in 1 .. 200 loop
         exit when SOCKS_State.Port /= 0 or else SOCKS_Current.all'Terminated;
         delay 0.01;
      end loop;
      return SOCKS_State.Port;
   end Start_SOCKS5_Proxy;

   procedure Stop_SOCKS5_Proxy is
   begin
      if SOCKS_Origin_Open then
         Safe_Close (SOCKS_Origin_Socket);
         SOCKS_Origin_Open := False;
      end if;

      if SOCKS_Client_Open then
         Safe_Close (SOCKS_Client_Socket);
         SOCKS_Client_Open := False;
      end if;

      if SOCKS_Server_Open then
         Safe_Close (SOCKS_Server_Socket);
         SOCKS_Server_Open := False;
      end if;

      for I in 1 .. 200 loop
         exit when SOCKS_Current = null or else SOCKS_Current.all'Terminated;
         delay 0.01;
      end loop;

      if SOCKS_Current /= null and then not SOCKS_Current.all'Terminated then
         abort SOCKS_Current.all;
         for I in 1 .. 200 loop
            exit when SOCKS_Current.all'Terminated;
            delay 0.01;
         end loop;
      end if;

      SOCKS_Current := null;
   end Stop_SOCKS5_Proxy;

   function SOCKS5_Capture_Contains (Needle : String) return Boolean is
   begin
      return SOCKS_State.Contains (Needle);
   end SOCKS5_Capture_Contains;

   function SOCKS5_Saw_CONNECT return Boolean is
   begin
      return SOCKS_State.CONNECT_Seen;
   end SOCKS5_Saw_CONNECT;

   function SOCKS5_Tunnel_Client_To_Origin_Bytes return Natural is
   begin
      return SOCKS_State.C2O;
   end SOCKS5_Tunnel_Client_To_Origin_Bytes;

   function SOCKS5_Tunnel_Origin_To_Client_Bytes return Natural is
   begin
      return SOCKS_State.O2C;
   end SOCKS5_Tunnel_Origin_To_Client_Bytes;

   function SOCKS5_Auth_Seen return Boolean is
   begin
      return SOCKS_State.Auth_Was_Seen;
   end SOCKS5_Auth_Seen;

   function SOCKS5_Origin_Equals (Host : String; Port : Natural) return Boolean is
   begin
      return SOCKS_State.Origin_Equals (Host, Port);
   end SOCKS5_Origin_Equals;

end Http_Client.Ada_Test_Fixtures;
