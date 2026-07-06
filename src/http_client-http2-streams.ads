with Http_Client.Errors;

package Http_Client.HTTP2.Streams
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Minimal HTTP/2 stream-state model for bounded HTTP/2 multiplexing.
   --
   --  The model is shared by the conservative single-stream path and the
   --  bounded multiplexed connection state. It validates per-stream lifecycle
   --  transitions; connection-wide scheduling, GOAWAY, HPACK, and flow control
   --  remain owned by the surrounding HTTP/2 connection layer.

   type Stream_State is
     (Idle,
      Open,
      Half_Closed_Local,
      Half_Closed_Remote,
      Closed,
      Reset);

   type Stream_Event is
     (Send_Headers,
      Send_Headers_End_Stream,
      Send_Data,
      Send_Data_End_Stream,
      Receive_Headers,
      Receive_Headers_End_Stream,
      Receive_Data,
      Receive_Data_End_Stream,
      Receive_RST_Stream,
      Send_RST_Stream);

   function Is_Client_Initiated_Stream_ID (Stream : Natural) return Boolean;
   --  GNATdoc contract.
   --  @param Stream Subprogram parameter.
   --  @return Subprogram result.
   --  Return True for nonzero odd stream identifiers.

   function Apply
     (State : in out Stream_State;
      Event : Stream_Event) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param State Subprogram parameter.
   --  @param Event Subprogram parameter.
   --  @return Subprogram result.
   --  Apply a client-side stream-state transition or return
   --  HTTP2_Protocol_Error. In Idle, only client-sent HEADERS may open the
   --  stream; receiving response frames before opening a request stream is
   --  rejected.
end Http_Client.HTTP2.Streams;
