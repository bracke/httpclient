with Ada.Strings.Unbounded;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.HPACK;
with Http_Client.HTTP2.Uploads;
with Http_Client.Request_Bodies;

package body Http_Client.HTTP2.Trailers_Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;

   function Make_Connection
     return Http_Client.HTTP2.Connection.Connection_State
   is
      Options : Http_Client.HTTP2.HTTP2_Options :=
        Http_Client.HTTP2.Default_HTTP2_Options;
   begin
      Options.Mode := Http_Client.HTTP2.HTTP2_Allowed;
      Options.Enable_Multiplexing := True;
      Options.Local_Max_Concurrent_Streams := 4;
      Options.Enable_Upload_Streaming := True;
      Options.Enable_Public_Streaming := True;
      return Http_Client.HTTP2.Connection.Create (Options);
   end Make_Connection;

   function Encoded
     (Fields : Http_Client.Headers.Header_List) return String
   is
      Encoder : Http_Client.HTTP2.HPACK.Encoder :=
        Http_Client.HTTP2.HPACK.Create_Encoder;
      Output  : Ada.Strings.Unbounded.Unbounded_String;
      Status  : constant Http_Client.Errors.Result_Status :=
        Http_Client.HTTP2.HPACK.Encode_Header_Block (Encoder, Fields, Output);
   begin
      Assert (Status = Http_Client.Errors.Ok, "HPACK block should encode");
      return Ada.Strings.Unbounded.To_String (Output);
   end Encoded;

   function Headers_Frame
     (Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Flags   : Natural;
      Payload : String) return Http_Client.HTTP2.Frames.Frame
   is
      Result : Http_Client.HTTP2.Frames.Frame;
   begin
      Result.Header :=
        (Length       => Http_Client.HTTP2.Frames.Frame_Length (Payload'Length),
         Kind         => Http_Client.HTTP2.Frames.HEADERS,
         Raw_Type     => Http_Client.HTTP2.Frames.Type_Code
           (Http_Client.HTTP2.Frames.HEADERS),
         Flags        => Http_Client.HTTP2.Frames.Byte_Value (Flags),
         Reserved_Bit => False,
         Stream       => Stream);
      Result.Payload := Ada.Strings.Unbounded.To_Unbounded_String (Payload);
      return Result;
   end Headers_Frame;

   function Data_Frame
     (Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Flags   : Natural;
      Payload : String) return Http_Client.HTTP2.Frames.Frame
   is
      Result : Http_Client.HTTP2.Frames.Frame;
   begin
      Result.Header :=
        (Length       => Http_Client.HTTP2.Frames.Frame_Length (Payload'Length),
         Kind         => Http_Client.HTTP2.Frames.DATA,
         Raw_Type     => Http_Client.HTTP2.Frames.Type_Code
           (Http_Client.HTTP2.Frames.DATA),
         Flags        => Http_Client.HTTP2.Frames.Byte_Value (Flags),
         Reserved_Bit => False,
         Stream       => Stream);
      Result.Payload := Ada.Strings.Unbounded.To_Unbounded_String (Payload);
      return Result;
   end Data_Frame;

   procedure Add_Header
     (List  : in out Http_Client.Headers.Header_List;
      Name  : String;
      Value : String) is
   begin
      Assert
        (Http_Client.Headers.Add (List, Name, Value) = Http_Client.Errors.Ok,
         "header should be accepted in test setup");
   end Add_Header;

   procedure Add_Pseudo
     (List  : in out Http_Client.Headers.Header_List;
      Name  : String;
      Value : String) is
   begin
      Assert
        (Http_Client.Headers.Add_HTTP2_Pseudo (List, Name, Value) = Http_Client.Errors.Ok,
         "HTTP/2 pseudo-header should be accepted in test setup");
   end Add_Pseudo;

   procedure Open_Response_Stream
     (Conn   : in out Http_Client.HTTP2.Connection.Connection_State;
      Stream : out Http_Client.HTTP2.Frames.Stream_ID)
   is
      Initial : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, Stream) = Http_Client.Errors.Ok,
         "client stream should open");
      Add_Pseudo (Initial, ":status", "200");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream, 16#04#, Encoded (Initial))) = Http_Client.Errors.Ok,
         "initial HTTP/2 response HEADERS should be accepted");
   end Open_Response_Stream;

   procedure Test_Request_Trailers_Empty_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request_Body : Http_Client.Request_Bodies.Request_Body;
      Result  : Http_Client.HTTP2.Uploads.Upload_Result;
   begin
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, Stream) = Http_Client.Errors.Ok,
         "request stream should open");
      Add_Header (Trailer, "x-checksum", "abc");
      Request_Body := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.Empty, Trailer);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, Stream, Request_Body, Result) = Http_Client.Errors.Ok,
         "empty HTTP/2 body with request trailers should send trailing HEADERS");
      Assert
        (Result.Data_Frames = 0 and then Result.Trailer_Headers = 1
         and then Result.End_Stream_Sent,
         "empty body with trailers should send no DATA and one END_STREAM trailer block");
   end Test_Request_Trailers_Empty_Body;

   procedure Test_Request_Trailers_Buffered_Body

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Request_Body : Http_Client.Request_Bodies.Request_Body;
      Result  : Http_Client.HTTP2.Uploads.Upload_Result;
   begin
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, Stream) = Http_Client.Errors.Ok,
         "request stream should open");
      Add_Header (Trailer, "x-finish", "yes");
      Request_Body := Http_Client.Request_Bodies.With_Trailers
        (Http_Client.Request_Bodies.From_String ("abc"), Trailer);
      Assert
        (Http_Client.HTTP2.Uploads.Send_Body (Conn, Stream, Request_Body, Result) = Http_Client.Errors.Ok,
         "buffered HTTP/2 body with request trailers should send DATA then trailing HEADERS");
      Assert
        (Result.Bytes_Sent = 3 and then Result.Data_Frames = 1
         and then Result.Trailer_Headers = 1 and then Result.End_Stream_Sent,
         "buffered body should keep END_STREAM for the trailing HEADERS block");
   end Test_Request_Trailers_Buffered_Body;

   procedure Test_Request_Trailer_Forbidden_Names

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Assert
        (Http_Client.HTTP2.Connection.Open_Stream (Conn, Stream) = Http_Client.Errors.Ok,
         "request stream should open");
      Add_Header (Trailer, "content-length", "0");
      Assert
        (Http_Client.HTTP2.Connection.Send_Trailers (Conn, Stream, Trailer)
         = Http_Client.Errors.HTTP2_Header_Error,
         "HTTP/2 request trailers must reject framing/sensitive names");
   end Test_Request_Trailer_Forbidden_Names;

   procedure Test_Response_Trailers_After_Data

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Open_Response_Stream (Conn, Stream);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Data_Frame (Stream, 0, "abc")) = Http_Client.Errors.Ok,
         "response DATA before trailers should be body bytes");
      Add_Header (Trailer, "x-complete", "true");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream, 16#05#, Encoded (Trailer))) = Http_Client.Errors.Ok,
         "HTTP/2 response trailers should be accepted as trailing HEADERS with END_STREAM");
      Assert
        (Http_Client.HTTP2.Connection.Response_Trailers_Received (Conn, Stream),
         "stream should record that response trailers were received");
      Assert
        (Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, Stream) = 3,
         "trailers must not be exposed or counted as response body DATA bytes");
   end Test_Response_Trailers_After_Data;

   procedure Test_Response_Trailer_Pseudo_Rejected

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Open_Response_Stream (Conn, Stream);
      Add_Pseudo (Trailer, ":status", "200");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream, 16#05#, Encoded (Trailer)))
         = Http_Client.Errors.HTTP2_Header_Error,
         "HTTP/2 response trailers must reject pseudo-headers after HPACK decoding");
   end Test_Response_Trailer_Pseudo_Rejected;

   procedure Test_Response_Trailer_Content_Length_Rejected

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Open_Response_Stream (Conn, Stream);
      Add_Header (Trailer, "content-length", "3");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream, 16#05#, Encoded (Trailer)))
         = Http_Client.Errors.HTTP2_Header_Error,
         "HTTP/2 response trailers must reject Content-Length");
   end Test_Response_Trailer_Content_Length_Rejected;

   procedure Test_Data_After_Response_Trailers_Rejected

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn    : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream  : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Open_Response_Stream (Conn, Stream);
      Add_Header (Trailer, "x-complete", "true");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream, 16#05#, Encoded (Trailer))) = Http_Client.Errors.Ok,
         "response trailer block should close remote side");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Data_Frame (Stream, 0, "x")) = Http_Client.Errors.HTTP2_Stream_State_Error,
         "DATA after response trailers must be rejected");
   end Test_Data_After_Response_Trailers_Rejected;

   procedure Test_Response_Trailers_Interleaved_With_Other_Stream

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Conn     : Http_Client.HTTP2.Connection.Connection_State := Make_Connection;
      Stream_A : Http_Client.HTTP2.Frames.Stream_ID;
      Stream_B : Http_Client.HTTP2.Frames.Stream_ID;
      Trailer  : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   begin
      Open_Response_Stream (Conn, Stream_A);
      Open_Response_Stream (Conn, Stream_B);
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Data_Frame (Stream_B, 0, "bb")) = Http_Client.Errors.Ok,
         "stream B DATA should be accepted before stream A trailers");
      Add_Header (Trailer, "x-a-done", "1");
      Assert
        (Http_Client.HTTP2.Connection.Receive_Frame
           (Conn, Headers_Frame (Stream_A, 16#05#, Encoded (Trailer))) = Http_Client.Errors.Ok,
         "stream A trailers should not attach to stream B");
      Assert
        (Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, Stream_A) = 0
         and then Http_Client.HTTP2.Connection.Buffered_Response_Bytes (Conn, Stream_B) = 2,
         "trailer metadata must remain per-stream under multiplexing");
   end Test_Response_Trailers_Interleaved_With_Other_Stream;

   function Name (T : Section_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Http_Client.HTTP2.Trailers_Tests");
   end Name;

   procedure Register_Tests (T : in out Section_Test_Case) is
      use AUnit.Test_Cases;
   begin
      Registration.Register_Routine
        (T, Test_Request_Trailers_Empty_Body'Access,
         "HTTP/2 request trailers after empty body");
      Registration.Register_Routine
        (T, Test_Request_Trailers_Buffered_Body'Access,
         "HTTP/2 request trailers after buffered body");
      Registration.Register_Routine
        (T, Test_Request_Trailer_Forbidden_Names'Access,
         "HTTP/2 request trailer forbidden names");
      Registration.Register_Routine
        (T, Test_Response_Trailers_After_Data'Access,
         "HTTP/2 response trailers after DATA");
      Registration.Register_Routine
        (T, Test_Response_Trailer_Pseudo_Rejected'Access,
         "HTTP/2 response trailer pseudo-header rejection");
      Registration.Register_Routine
        (T, Test_Response_Trailer_Content_Length_Rejected'Access,
         "HTTP/2 response trailer Content-Length rejection");
      Registration.Register_Routine
        (T, Test_Data_After_Response_Trailers_Rejected'Access,
         "HTTP/2 DATA after response trailers rejection");
      Registration.Register_Routine
        (T, Test_Response_Trailers_Interleaved_With_Other_Stream'Access,
         "HTTP/2 multiplexed trailer stream isolation");
   end Register_Tests;
end Http_Client.HTTP2.Trailers_Tests;
