with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.HTTP2.Frames is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Strict bounded HTTP/2 frame modeling, parsing, and serialization.
   --
   --  The frame layer understands the 9-octet HTTP/2 header and validates
   --  frame-specific invariants that do not require HPACK or connection state.
   --  It never allocates from an untrusted length until the configured maximum
   --  frame size has been checked.

   subtype Frame_Length is Natural range 0 .. 16#00FF_FFFF#;
   subtype Byte_Value is Natural range 0 .. 255;
   subtype Stream_ID is Natural range 0 .. 16#7FFF_FFFF#;

   type Frame_Type is
     (DATA,
      HEADERS,
      PRIORITY,
      RST_STREAM,
      SETTINGS,
      PUSH_PROMISE,
      PING,
      GOAWAY,
      WINDOW_UPDATE,
      CONTINUATION,
      UNKNOWN);

   type Frame_Header is record
      Length       : Frame_Length := 0;
      Kind         : Frame_Type := DATA;
      Raw_Type     : Byte_Value := 0;
      Flags        : Byte_Value := 0;
      Reserved_Bit : Boolean := False;
      Stream       : Stream_ID := 0;
   end record;
   --  Parsed HTTP/2 frame header.

   type Frame is record
      Header  : Frame_Header;
      Payload : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;
   --  Complete bounded frame value.

   function Type_Code (Kind : Frame_Type; Raw_Type : Byte_Value := 0)
      return Byte_Value;
   --  GNATdoc contract.
   --  @param Kind Subprogram parameter.
   --  @param Raw_Type Subprogram parameter.
   --  @return Subprogram result.
   --  Return the wire type code for Kind. UNKNOWN returns Raw_Type.

   function Kind_From_Code (Code : Byte_Value) return Frame_Type;
   --  GNATdoc contract.
   --  @param Code Subprogram parameter.
   --  @return Subprogram result.
   --  Map a wire frame-type code to the public frame kind.

   function Serialize_Header
     (Header : Frame_Header) return String;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @return Subprogram result.
   --  Serialize exactly the 9-octet HTTP/2 frame header in network byte order.

   function Parse_Header
     (Data   : String;
      Header : out Frame_Header) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Header Subprogram parameter.
   --  @return Subprogram result.
   --  Parse exactly the first 9 octets of Data as a frame header.

   function Validate_Header
     (Header         : Frame_Header;
      Max_Frame_Size : Natural := 16_384) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @param Max_Frame_Size Subprogram parameter.
   --  @return Subprogram result.
   --  Validate frame length and stream-id constraints for the frame type.
   --  WINDOW_UPDATE is valid both on stream zero for the connection window
   --  and on a nonzero stream for a stream window.

   function Validate_Payload
     (Header  : Frame_Header;
      Payload : String) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @return Subprogram result.
   --  Validate frame-specific payload lengths and simple fields.


   function RST_Stream_Error_Code (Payload : String) return Natural;
   --  GNATdoc contract.
   --  @param Payload Four-octet RST_STREAM payload.
   --  @return HTTP/2 error code in network byte order, or Natural'Last when
   --          Payload is not exactly four octets.
   --  Decode the RST_STREAM error code without interpreting it.

   function RST_Stream_Status (Payload : String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Payload Four-octet RST_STREAM payload.
   --  @return The most specific existing Result_Status for the peer reset
   --          error code. Unknown or non-specific codes remain
   --          HTTP2_Stream_Reset.
   --  Interpret a peer RST_STREAM payload without hiding the reset as a
   --  generic stream reset when the wire error code carries useful detail.


   type Continuation_State is record
      Expecting_Continuation : Boolean := False;
      Stream                 : Stream_ID := 0;
   end record;
   --  Minimal header-block continuation tracker for deterministic validation
   --  of HEADERS/PUSH_PROMISE followed by CONTINUATION frames. This does not
   --  decode HPACK; it only enforces frame sequencing and stream consistency.

   function Apply_Continuation_Rule
     (State  : in out Continuation_State;
      Header : Frame_Header) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param State Subprogram parameter.
   --  @param Header Subprogram parameter.
   --  @return Subprogram result.
   --  Apply HTTP/2 continuation sequencing rules. While a header block is
   --  incomplete, only CONTINUATION frames on the same stream are accepted.
   --  HEADERS/PUSH_PROMISE without END_HEADERS starts a required continuation
   --  sequence; CONTINUATION with END_HEADERS completes it.

   function Serialize_Frame
     (Header  : Frame_Header;
      Payload : String;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Header Subprogram parameter.
   --  @param Payload Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Serialize a complete frame after validating Header and Payload.

   function Parse_Frame
     (Data           : String;
      Max_Frame_Size : Natural;
      Item           : out Frame) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Data Subprogram parameter.
   --  @param Max_Frame_Size Subprogram parameter.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Parse one complete frame from Data. Data must contain exactly the frame
   --  header plus the declared payload. Short input returns Incomplete_Message;
   --  trailing bytes return HTTP2_Frame_Error.
end Http_Client.HTTP2.Frames;
