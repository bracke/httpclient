with System;

with Http_Client.Errors;

package Http_Client.QUIC
  with SPARK_Mode => On
is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  QUIC transport boundary for future HTTP/3 execution.
   --
   --  The experimental boundary deliberately does not expose raw backend handles and does not
   --  fake HTTP/3 over the existing TCP/TLS transports. QUIC requires UDP and
   --  TLS 1.3 integrated into the QUIC handshake. Until a backend is provided,
   --  connection attempts return QUIC_Unsupported before request data is sent.

   type Backend_Availability is (Backend_Unavailable, Backend_Available);

   subtype Timeout_Milliseconds is Natural;

   type QUIC_Options is record
      Backend              : Backend_Availability := Backend_Unavailable;
      Idle_Timeout         : Timeout_Milliseconds := 30_000;
      Connection_Timeout   : Timeout_Milliseconds := 10_000;
      Max_Bidirectional_Streams : Natural := 1;
      Max_Unidirectional_Streams : Natural := 3;
      Max_Datagram_Size    : Natural := 1_200;
      Enable_Zero_RTT      : Boolean := False;
   end record;
   --  Public QUIC intent. 0-RTT is rejected until a production backend exists.

   Default_QUIC_Options : constant QUIC_Options :=
     (Backend => Backend_Unavailable,
      Idle_Timeout => 30_000,
      Connection_Timeout => 10_000,
      Max_Bidirectional_Streams => 1,
      Max_Unidirectional_Streams => 3,
      Max_Datagram_Size => 1_200,
      Enable_Zero_RTT => False);

   type Connection is tagged private;

   function Validate (Options : QUIC_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Validate bounded QUIC options without opening sockets.

   function Is_Open (Conn : Connection) return Boolean;
   --  GNATdoc contract.
   --  @param Conn Subprogram parameter.
   --  @return Subprogram result.
   --  Return True only for a real future QUIC backend connection.

   procedure Close (Conn : in out Connection)
     with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Conn Subprogram parameter.
   --  Release connection state. Safe for unopened backend connections.

   function Open
     (Conn    : in out Connection;
      Host    : String;
      Port    : Natural;
      Options : QUIC_Options := Default_QUIC_Options)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Conn Subprogram parameter.
   --  @param Host Subprogram parameter.
   --  @param Port Subprogram parameter.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Open a QUIC connection when a backend exists. This release returns
   --  QUIC_Unsupported for the default unavailable backend.

private
   type Connection is tagged record
      Opened : Boolean := False;
      Backend_Handle : System.Address := System.Null_Address;
   end record;
end Http_Client.QUIC;
