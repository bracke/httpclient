with Ada.Streams;

with GNAT.Sockets;

with Http_Client.Errors;
with Http_Client.URI;

package body Http_Client.Transports.TCP is
   use type GNAT.Sockets.Socket_Type;
   use type Http_Client.Errors.Result_Status;

   procedure Ensure_Socket_Support is
   begin
      GNAT.Sockets.Initialize;
   exception
      when others =>
         null;
   end Ensure_Socket_Support;

   procedure Force_Close (Item : in out Connection) is
   begin
      if Item.Socket /= GNAT.Sockets.No_Socket then
         begin
            GNAT.Sockets.Close_Socket (Item.Socket);
         exception
            when others =>
               null;
         end;
      end if;

      Item.Socket := GNAT.Sockets.No_Socket;
      Item.Opened := False;
   end Force_Close;

   overriding procedure Finalize (Item : in out Connection) is
   begin
      Force_Close (Item);
   end Finalize;

   function Is_Open (Item : Connection) return Boolean is
   begin
      return Item.Opened and then Item.Socket /= GNAT.Sockets.No_Socket;
   end Is_Open;

   function Open
     (Item     : in out Connection;
      Host     : String;
      Port     : Http_Client.URI.TCP_Port;
      Timeouts : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status
   is
      function Looks_Like_IPv6_Literal return Boolean is
      begin
         for C of Host loop
            if C = ':' then
               return True;
            end if;
         end loop;

         return False;
      end Looks_Like_IPv6_Literal;
   begin
      Force_Close (Item);

      if Host'Length = 0 then
         return Http_Client.Errors.DNS_Failed;
      end if;

      Ensure_Socket_Support;

      if Looks_Like_IPv6_Literal then
         declare
            Address : GNAT.Sockets.Sock_Addr_Type (GNAT.Sockets.Family_Inet6);
         begin
            Address.Addr := GNAT.Sockets.Inet_Addr (Host);
            Address.Port := GNAT.Sockets.Port_Type (Port);

            begin
               GNAT.Sockets.Create_Socket
                 (Socket => Item.Socket,
                  Family => GNAT.Sockets.Family_Inet6);
               Item.Options := Timeouts;
               GNAT.Sockets.Connect_Socket (Item.Socket, Address);
               Item.Opened := True;
               return Http_Client.Errors.Ok;
            exception
               when others =>
                  Force_Close (Item);
                  return Http_Client.Errors.Connection_Failed;
            end;
         exception
            when others =>
               Force_Close (Item);
               return Http_Client.Errors.DNS_Failed;
         end;
      end if;

      declare
         Host_Info : constant GNAT.Sockets.Host_Entry_Type :=
           GNAT.Sockets.Get_Host_By_Name (Host);

         Address : GNAT.Sockets.Sock_Addr_Type(GNAT.Sockets.Family_Inet);
      begin
         Address.Addr := GNAT.Sockets.Addresses (Host_Info, 1);
         Address.Port := GNAT.Sockets.Port_Type (Port);

         begin
            GNAT.Sockets.Create_Socket (Item.Socket);
            Item.Options := Timeouts;
            GNAT.Sockets.Connect_Socket (Item.Socket, Address);
            Item.Opened := True;
            return Http_Client.Errors.Ok;
         exception
            when others =>
               Force_Close (Item);
               return Http_Client.Errors.Connection_Failed;
         end;

      exception
         when others =>
            Force_Close (Item);
            return Http_Client.Errors.DNS_Failed;
      end;
   exception
      when others =>
         Force_Close (Item);
         return Http_Client.Errors.Internal_Error;
   end Open;

   function Open_URI
     (Item     : in out Connection;
      URI      : Http_Client.URI.URI_Reference;
      Timeouts : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status is
   begin
      if not Http_Client.URI.Is_Parsed (URI) then
         Force_Close (Item);
         return Http_Client.Errors.Invalid_URI;
      end if;

      if Http_Client.URI.Requires_TLS (URI) then
         Force_Close (Item);
         return Http_Client.Errors.Unsupported_Feature;
      end if;

      return Open
        (Item     => Item,
         Host     => Http_Client.URI.Host (URI),
         Port     => Http_Client.URI.Effective_Port (URI),
         Timeouts => Timeouts);
   end Open_URI;

   function Write_All
     (Item : in out Connection;
      Data : String) return Http_Client.Errors.Result_Status
   is
      use Ada.Streams;

      Max_Write_Chunk : constant Natural := 4096;
      First           : Natural := Data'First;
   begin
      if not Is_Open (Item) then
         return Http_Client.Errors.Not_Connected;
      end if;

      while First <= Data'Last loop
         declare
            Remaining : constant Natural := Data'Last - First + 1;
            Amount    : constant Natural := Natural'Min
              (Remaining,
               Max_Write_Chunk);
            Chunk     : Stream_Element_Array
              (1 .. Stream_Element_Offset (Amount));
            Last      : Stream_Element_Offset;
         begin
            for Offset in Chunk'Range loop
               Chunk (Offset) :=
                 Stream_Element
                   (Character'Pos
                      (Data (First + Natural (Offset - Chunk'First))));
            end loop;

            GNAT.Sockets.Send_Socket
              (Socket => Item.Socket,
               Item   => Chunk,
               Last   => Last);

            if Last < Chunk'First then
               return Http_Client.Errors.Write_Failed;
            end if;

            First := First + Natural (Last - Chunk'First + 1);
         end;
      end loop;

      return Http_Client.Errors.Ok;
   exception
      when others =>
         Force_Close (Item);
         return Http_Client.Errors.Write_Failed;
   end Write_All;

   function Read_Some
     (Item   : in out Connection;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status
   is
      use Ada.Streams;
   begin
      Count := 0;

      if not Is_Open (Item) then
         return Http_Client.Errors.Not_Connected;
      end if;

      if Buffer'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      declare
         Raw  : Stream_Element_Array (1 .. Stream_Element_Offset (Buffer'Length));
         Last : Stream_Element_Offset;
      begin
         GNAT.Sockets.Receive_Socket
           (Socket => Item.Socket,
            Item   => Raw,
            Last   => Last);

         if Last < Raw'First then
            return Http_Client.Errors.End_Of_Stream;
         end if;

         Count := Natural (Last - Raw'First + 1);

         for Offset in 0 .. Count - 1 loop
            Buffer (Buffer'First + Offset) :=
              Character'Val (Raw (Raw'First + Stream_Element_Offset (Offset)));
         end loop;

         return Http_Client.Errors.Ok;
      end;
   exception
      when others =>
         Force_Close (Item);
         Count := 0;
         return Http_Client.Errors.Read_Failed;
   end Read_Some;

   function Close
     (Item : in out Connection) return Http_Client.Errors.Result_Status is
   begin
      Force_Close (Item);
      return Http_Client.Errors.Ok;
   end Close;

   function Round_Trip_First_Bytes
     (Host       : String;
      Port       : Http_Client.URI.TCP_Port;
      Request    : String;
      Buffer     : out String;
      Count      : out Natural;
      Timeouts   : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status
   is
      Item   : Connection;
      Status : Http_Client.Errors.Result_Status;
   begin
      Count := 0;

      Status := Open
        (Item     => Item,
         Host     => Host,
         Port     => Port,
         Timeouts => Timeouts);

      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Write_All (Item, Request);

      if Status /= Http_Client.Errors.Ok then
         declare
            Ignored : constant Http_Client.Errors.Result_Status := Close (Item);
            pragma Unreferenced (Ignored);
         begin
            return Status;
         end;
      end if;

      Status := Read_Some (Item, Buffer, Count);

      declare
         Ignored : constant Http_Client.Errors.Result_Status := Close (Item);
         pragma Unreferenced (Ignored);
      begin
         return Status;
      end;
   end Round_Trip_First_Bytes;

end Http_Client.Transports.TCP;
