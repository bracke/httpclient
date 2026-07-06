with Http_Client.Errors;
with Http_Client.HTTP3.Frames;

package Http_Client.HTTP3.Streams
  with SPARK_Mode => On
is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  HTTP/3 stream classification and frame placement rules.

   type Stream_Kind is
     (Request_Bidirectional,
      Control_Unidirectional,
      QPACK_Encoder_Unidirectional,
      QPACK_Decoder_Unidirectional,
      Push_Unidirectional,
      Unknown_Unidirectional);

   function Validate_Frame_On_Stream
     (Kind       : Stream_Kind;
      Frame      : Http_Client.HTTP3.Frames.Frame_Type;
      Push_Enabled : Boolean := False) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @param Frame Subprogram parameter.
   --  @param Push_Enabled Subprogram parameter.
   --  @return Subprogram result.
   --  Reject frames illegal on the given HTTP/3 stream type. Push streams and
   --  push-related frames are unsupported unless explicitly enabled by a later
   --  release.
end Http_Client.HTTP3.Streams;
