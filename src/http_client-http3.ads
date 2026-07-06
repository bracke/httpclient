with Http_Client.Errors;
with Http_Client.QUIC;

package Http_Client.HTTP3
  with SPARK_Mode => On
is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  HTTP/3 configuration and ALPN policy foundations.
   --
   --  HTTP/3 is explicit and disabled by default. The experimental surface models protocol
   --  boundaries, fallback policy, and unsupported execution. It does not
   --  silently prefer HTTP/3 for existing HTTPS requests and does not reuse
   --  TCP/TLS sockets for QUIC.

   type HTTP3_Mode is (HTTP3_Disabled, HTTP3_Allowed, HTTP3_Required);
   type Protocol_Fallback_Policy is (Fallback_Disallowed, Fallback_Before_Send);
   type Selected_Protocol is
     (Protocol_None,
      Protocol_HTTP_1_1,
      Protocol_HTTP_2,
      Protocol_HTTP_3,
      Protocol_Unknown);

   type HTTP3_Options is record
      Mode            : HTTP3_Mode := HTTP3_Disabled;
      Fallback        : Protocol_Fallback_Policy := Fallback_Disallowed;
      QUIC            : Http_Client.QUIC.QUIC_Options :=
        Http_Client.QUIC.Default_QUIC_Options;
      Max_Frame_Size  : Natural := 16_384;
      Max_Header_List_Size : Natural := 65_536;
      Enable_Server_Push : Boolean := False;
      Enable_Zero_RTT : Boolean := False;
   end record;
   --  @field Mode Opt-in HTTP/3 candidate policy.
   --  @field Fallback Allows downgrade to TCP protocols only before request
   --         bytes or body data are sent.
   --  @field QUIC QUIC transport intent. Default backend is unavailable.
   --  @field Max_Frame_Size Maximum HTTP/3 frame payload accepted in memory.
   --  @field Max_Header_List_Size Maximum decoded header-list size.
   --  @field Enable_Server_Push Must remain False until production HTTP/3 support is implemented.
   --  @field Enable_Zero_RTT Must remain False until production HTTP/3 support is implemented.

   Default_HTTP3_Options : constant HTTP3_Options :=
     (Mode => HTTP3_Disabled,
      Fallback => Fallback_Disallowed,
      QUIC => Http_Client.QUIC.Default_QUIC_Options,
      Max_Frame_Size => 16_384,
      Max_Header_List_Size => 65_536,
      Enable_Server_Push => False,
      Enable_Zero_RTT => False);

   function Validate (Options : HTTP3_Options)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.

   function ALPN_Token (Options : HTTP3_Options) return String;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @return Subprogram result.
   --  Return "h3" only when HTTP/3 is an enabled QUIC candidate.

   function Normalize_ALPN_Selected (Token : String) return Selected_Protocol;
   --  GNATdoc contract.
   --  @param Token Subprogram parameter.
   --  @return Subprogram result.

   function Execution_Status
     (Options                : HTTP3_Options;
      Proxy_Configured       : Boolean := False;
      SOCKS_Configured       : Boolean := False;
      Client_Certificate_Configured : Boolean := False)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @param Proxy_Configured Subprogram parameter.
   --  @param SOCKS_Configured Subprogram parameter.
   --  @param Client_Certificate_Configured Subprogram parameter.
   --  @return Subprogram result.
   --  Return deterministic HTTP/3 candidate status before request data is
   --  sent. Proxies, SOCKS UDP, client certificates over QUIC, and unavailable
   --  QUIC backends are rejected here. A selected backend returns Ok so the
   --  execution package can perform UDP/QUIC open, handshake, and stream-error
   --  mapping without involving the TCP/TLS stacks.

   function Fallback_Status
     (Options                  : HTTP3_Options;
      Request_Bytes_Already_Sent : Boolean)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Options Subprogram parameter.
   --  @param Request_Bytes_Already_Sent Subprogram parameter.
   --  @return Subprogram result.

end Http_Client.HTTP3;
