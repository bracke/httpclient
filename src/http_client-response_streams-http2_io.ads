with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2_Execution_Common;
with Http_Client.Transports.TCP;

private package Http_Client.Response_Streams.HTTP2_IO is
   --  Private HTTP/2 frame I/O helpers for live streaming responses.

   function Read_Frame
     (Stream : in out Streaming_Response;
      Frame  : out Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status;

   function Try_Read_Frame
     (Stream     : in out Streaming_Response;
      Timeout_MS : Http_Client.Transports.TCP.Timeout_Milliseconds;
      Frame      : out Http_Client.HTTP2.Frames.Frame;
      Got_Frame  : out Boolean) return Http_Client.Errors.Result_Status;

   function Write_Settings_Ack
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status;

   function Write_Ping_Ack
     (Stream  : in out Streaming_Response;
      Payload : String) return Http_Client.Errors.Result_Status;

   function Write_Data_Window_Update
     (Stream    : in out Streaming_Response;
      Stream_ID : Natural;
      Increment : Natural) return Http_Client.Errors.Result_Status;

   function Handle_Settings_Frame
     (Stream                     : in out Streaming_Response;
      Frame                      : Http_Client.HTTP2.Frames.Frame;
      Peer                       : in out Http_Client.HTTP2_Execution_Common.Peer_Settings;
      Update_Read_Max_Frame_Size : Boolean := False)
      return Http_Client.Errors.Result_Status;

   function Handle_Ping_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status;

   function Window_Update_Increment
     (Frame     : Http_Client.HTTP2.Frames.Frame;
      Increment : out Natural) return Http_Client.Errors.Result_Status;

   function Validate_Data_Frame
     (Stream : Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status;

   function Consume_Data_Payload
     (Stream         : in out Streaming_Response;
      Payload_Length : Natural) return Http_Client.Errors.Result_Status;

   function Complete_Data_End_Stream
     (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status;

   function Validate_Trailer_Frame
     (Stream : in out Streaming_Response;
      Frame  : Http_Client.HTTP2.Frames.Frame)
      return Http_Client.Errors.Result_Status;

   function Terminal_Frame_Status
     (Stream           : Streaming_Response;
      Frame            : Http_Client.HTTP2.Frames.Frame;
      Data_Is_Protocol : Boolean := False) return Http_Client.Errors.Result_Status;

   function Handle_Response_Header_Block_Frame
     (Stream               : in out Streaming_Response;
      Frame                : Http_Client.HTTP2.Frames.Frame;
      Max_Header_List_Size : Natural;
      Header_Block         : in out Ada.Strings.Unbounded.Unbounded_String;
      End_Stream           : in out Boolean;
      Headers              : out Http_Client.Headers.Header_List;
      Complete             : out Boolean) return Http_Client.Errors.Result_Status;
end Http_Client.Response_Streams.HTTP2_IO;
