with Ada.Finalization;
private with GNAT.Sockets;

with Http_Client.Errors;
with Http_Client.URI;

package Http_Client.Transports.TCP is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Raw plain-TCP transport scaffolding.
   --
   --  This package owns a single TCP socket per Connection object. It opens a
   --  blocking plain TCP connection, writes caller-supplied bytes exactly,
   --  reads raw bytes, and closes deterministically. It does not parse HTTP,
   --  does not apply TLS, and does not alter request or response bytes.
   --
   --  Timeout values record the caller's intent. The initial implementation is
   --  deliberately conservative and may not enforce every timeout on every
   --  GNAT.Sockets/platform combination. Unit tests should therefore avoid
   --  relying on precise timeout expiry behavior.

   type Timeout_Milliseconds is range 0 .. 3_600_000;
   --  Timeout duration in milliseconds. Zero means use the socket layer's
   --  normal blocking behavior.

   type Timeout_Config is record
      Connect : Timeout_Milliseconds := 0;
      Read    : Timeout_Milliseconds := 0;
      Write   : Timeout_Milliseconds := 0;
   end record;
   --  Blocking-operation timeout intent for connect, read, and write calls.

   Default_Timeouts : constant Timeout_Config :=
     (Connect => 0,
      Read    => 0,
      Write   => 0);
   --  Default blocking behavior.

   type Connection is new Ada.Finalization.Limited_Controlled with private;
   --  Owned plain TCP connection.
   --
   --  A Connection closes its socket during finalization if still open. Calling
   --  Close on an already closed value is safe.

   overriding procedure Finalize (Item : in out Connection);
   --  GNATdoc contract.
   --  @param Item TCP connection being finalized.
   --  Close any still-open socket owned by Item.

   function Open
     (Item     : in out Connection;
      Host     : String;
      Port     : Http_Client.URI.TCP_Port;
      Timeouts : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status;
   --  Resolve Host, open a socket, and connect to Host:Port using plain TCP.
   --  Open first closes any socket already owned by Item. If opening or
   --  connecting fails, any intermediate socket is closed before this function
   --  returns, so failed opens never leave a stale connection attached to the
   --  same object.
   --
   --  @param Item Connection object that will own the opened socket.
   --  @param Host DNS name or numeric address to resolve through GNAT.Sockets.
   --  @param Port TCP port number.
   --  @param Timeouts Timeout intent for blocking socket operations.
   --  @return Ok on success, DNS_Failed for resolution failure,
   --          Connection_Failed for socket/connect failure, or Internal_Error
   --          for unexpected socket-layer failures.

   function Open_URI
     (Item     : in out Connection;
      URI      : Http_Client.URI.URI_Reference;
      Timeouts : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param URI Subprogram parameter.
   --  @param Timeouts Subprogram parameter.
   --  @return Subprogram result.
   --  Open a plain TCP connection for a parsed http URI.
   --
   --  https URIs return Unsupported_Feature because plain TCP must not fake
   --  HTTPS by connecting to port 443 without TLS. Invalid or unsupported URI
   --  inputs close any socket already owned by Item before returning.

   function Is_Open (Item : Connection) return Boolean;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Return True when Item currently owns an open socket.

   function Write_All
     (Item : in out Connection;
      Data : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @param Data Subprogram parameter.
   --  @return Subprogram result.
   --  Write every byte in Data to the open connection.
   --
   --  The data is transmitted exactly as supplied. Line endings, headers, and
   --  payload bytes are not interpreted or changed.

   function Read_Some
     (Item   : in out Connection;
      Buffer : out String;
      Count  : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  Read up to Buffer'Length raw bytes from the open connection.
   --
   --  @param Buffer Destination buffer. Bytes are written from Buffer'First.
   --  @param Count Number of bytes stored in Buffer. Count is zero on ordinary
   --         end of stream.
   --  @return Ok when bytes were read, End_Of_Stream when the peer closed
   --          cleanly before any byte was read, Not_Connected when no socket is
   --          open, or Read_Failed for socket read failures.

   function Close
     (Item : in out Connection) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Close the socket if open. Closing an already closed connection returns Ok.

   function Round_Trip_First_Bytes
     (Host       : String;
      Port       : Http_Client.URI.TCP_Port;
      Request    : String;
      Buffer     : out String;
      Count      : out Natural;
      Timeouts   : Timeout_Config := Default_Timeouts)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @param Request Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Count Subprogram parameter.
   --  @param Timeouts Subprogram parameter.
   --  @return Subprogram result.
   --  Test/integration helper: open plain TCP, write Request exactly, read one
   --  raw response chunk into Buffer, and close.
   --
   --  This is not a complete HTTP execution API. It does not parse responses,
   --  follow redirects, retry, pool, or manage connection reuse.

private
   type Connection is new Ada.Finalization.Limited_Controlled with record
      Socket  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Opened  : Boolean := False;
      Options : Timeout_Config := Default_Timeouts;
   end record;
end Http_Client.Transports.TCP;
