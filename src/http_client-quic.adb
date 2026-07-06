with Interfaces.C;
with Interfaces.C.Strings;
with System;

with Http_Client.Errors;

package body Http_Client.QUIC
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;
   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;
   use type System.Address;

   function Native_Backend_Available return Interfaces.C.int
     with Import, Convention => C,
     External_Name => "http_client_quic_backend_available";

   function Native_Open
     (Host                       : Interfaces.C.Strings.chars_ptr;
      Port                       : Interfaces.C.int;
      Idle_Timeout_Ms            : Interfaces.C.int;
      Connection_Timeout_Ms      : Interfaces.C.int;
      Max_Datagram_Size          : Interfaces.C.int;
      Max_Bidirectional_Streams  : Interfaces.C.int;
      Max_Unidirectional_Streams : Interfaces.C.int;
      Out_Handle                 : access System.Address)
      return Interfaces.C.int
     with Import, Convention => C,
     External_Name => "http_client_quic_backend_open";

   procedure Native_Close (Handle : System.Address)
     with Import, Convention => C,
     External_Name => "http_client_quic_backend_close";

   function Map_Native_Status
     (Status : Interfaces.C.int) return Http_Client.Errors.Result_Status is
   begin
      case Integer (Status) is
         when 0 =>
            return Http_Client.Errors.Ok;
         when 1 =>
            return Http_Client.Errors.QUIC_Unsupported;
         when 2 =>
            return Http_Client.Errors.Connection_Failed;
         when 3 =>
            return Http_Client.Errors.Timeout;
         when 4 =>
            return Http_Client.Errors.TLS_Handshake_Failed;
         when 5 =>
            return Http_Client.Errors.Certificate_Verification_Failed;
         when 6 =>
            return Http_Client.Errors.Invalid_Configuration;
         when 7 =>
            return Http_Client.Errors.Invalid_URI;
         when others =>
            return Http_Client.Errors.Internal_Error;
      end case;
   end Map_Native_Status;

   function Validate (Options : QUIC_Options)
      return Http_Client.Errors.Result_Status is
   begin
      if Options.Enable_Zero_RTT then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Idle_Timeout = 0 or else Options.Connection_Timeout = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Max_Datagram_Size < 1_200 then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Max_Bidirectional_Streams = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Max_Unidirectional_Streams < 3 then
         return Http_Client.Errors.Invalid_Configuration;
      else
         return Http_Client.Errors.Ok;
      end if;
   end Validate;

   function Host_Text_Is_Valid (Host : String) return Boolean is
   begin
      if Host'Length = 0 then
         return False;
      end if;

      for Ch of Host loop
         if Ch <= ' '
           or else Character'Pos (Ch) >= 127
           or else Ch = '/'
           or else Ch = Character'Val (16#5C#)
           or else Ch = '@'
         then
            return False;
         end if;
      end loop;

      return True;
   end Host_Text_Is_Valid;

   function Is_Open (Conn : Connection) return Boolean is
   begin
      return Conn.Opened;
   end Is_Open;

   procedure Close (Conn : in out Connection)
      with SPARK_Mode => Off
   is
   begin
      if Conn.Backend_Handle /= System.Null_Address then
         Native_Close (Conn.Backend_Handle);
      end if;

      Conn.Backend_Handle := System.Null_Address;
      Conn.Opened := False;
   end Close;

   function Open
     (Conn    : in out Connection;
      Host    : String;
      Port    : Natural;
      Options : QUIC_Options := Default_QUIC_Options)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is

      Status        : constant Http_Client.Errors.Result_Status := Validate (Options);
      Native_Status : Interfaces.C.int;
      Native_Host   : Interfaces.C.Strings.chars_ptr :=
        Interfaces.C.Strings.Null_Ptr;
      Handle        : aliased System.Address := System.Null_Address;
   begin
      Close (Conn);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      elsif not Host_Text_Is_Valid (Host) then
         return Http_Client.Errors.Invalid_URI;
      elsif Port = 0 or else Port > 65_535 then
         return Http_Client.Errors.Invalid_Configuration;
      elsif Options.Backend = Backend_Unavailable
        or else Native_Backend_Available = 0
      then
         return Http_Client.Errors.QUIC_Unsupported;
      end if;

      Native_Host := Interfaces.C.Strings.New_String (Host);
      Native_Status := Native_Open
        (Host                       => Native_Host,
         Port                       => Interfaces.C.int (Port),
         Idle_Timeout_Ms            => Interfaces.C.int (Options.Idle_Timeout),
         Connection_Timeout_Ms      => Interfaces.C.int (Options.Connection_Timeout),
         Max_Datagram_Size          => Interfaces.C.int (Options.Max_Datagram_Size),
         Max_Bidirectional_Streams  =>
           Interfaces.C.int (Options.Max_Bidirectional_Streams),
         Max_Unidirectional_Streams =>
           Interfaces.C.int (Options.Max_Unidirectional_Streams),
         Out_Handle                 => Handle'Access);
      Interfaces.C.Strings.Free (Native_Host);

      declare
         Mapped : constant Http_Client.Errors.Result_Status :=
           Map_Native_Status (Native_Status);
      begin
         if Mapped = Http_Client.Errors.Ok then
            if Handle = System.Null_Address then
               return Http_Client.Errors.Internal_Error;
            end if;

            Conn.Backend_Handle := Handle;
            Conn.Opened := True;
         end if;

         return Mapped;
      end;
   exception
      when others =>
         if Native_Host /= Interfaces.C.Strings.Null_Ptr then
            Interfaces.C.Strings.Free (Native_Host);
         end if;
         Conn.Backend_Handle := System.Null_Address;
         Conn.Opened := False;
         return Http_Client.Errors.Internal_Error;
   end Open;

end Http_Client.QUIC;
