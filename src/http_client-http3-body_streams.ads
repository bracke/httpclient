with Ada.Streams;
with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.HTTP3.Body_Streams is
   --  Release surface: experimental public API for 1.0.0.
   --  Binary-safe HTTP/3 response-body stream adapter.
   --
   --  This adapter exposes HTTP/3 DATA-frame payload bytes through the same
   --  pull contract used by the Git smart HTTP streaming path. It never exposes
   --  HTTP/3 frame metadata, QPACK bytes, control-stream bytes, or QUIC stream
   --  framing. The current implementation is an explicit backend boundary: a
   --  production QUIC backend feeds decoded DATA payload bytes into Append_Data
   --  and then calls Mark_End_Stream. Tests use the same boundary with scripted
   --  DATA payloads. The type is not task-safe.

   type Body_Stream is limited private;

   function Open
     (B              : out Body_Stream;
      Max_Body_Size  : Natural := 1_048_576)
      return Http_Client.Errors.Result_Status;
   --  Open an initially empty HTTP/3 body stream.
   --
   --  @param B Stream to initialize.
   --  @param Max_Body_Size Maximum DATA payload bytes accepted before
   --         Decoded_Body_Too_Large is returned.
   --  @return Ok or Invalid_Configuration.

   function Append_Data
     (B    : in out Body_Stream;
      Data : String) return Http_Client.Errors.Result_Status;
   --  Append decoded HTTP/3 DATA payload bytes supplied by the QUIC/backend
   --  layer. This subprogram is intentionally not frame parsing; frame and QPACK
   --  processing happen before this adapter.
   --
   --  @param B Stream to feed.
   --  @param Data DATA payload bytes.
   --  @return Ok, Not_Connected, or Decoded_Body_Too_Large.

   function Append_Data
     (B    : in out Body_Stream;
      Data : Ada.Streams.Stream_Element_Array)
      return Http_Client.Errors.Result_Status;
   --  Append decoded HTTP/3 DATA payload bytes from a binary Ada stream
   --  buffer. This overload exists so HTTP/3 backend and Git integrations do
   --  not need to round-trip packet-line or packfile bytes through text APIs.
   --
   --  @param B Stream to feed.
   --  @param Data DATA payload bytes.
   --  @return Ok, Not_Connected, or Decoded_Body_Too_Large.

   function Mark_End_Stream
     (B : in out Body_Stream) return Http_Client.Errors.Result_Status;
   --  Mark remote FIN/END_STREAM after all DATA payload bytes were appended.
   --
   --  @param B Stream to finish.
   --  @return Ok or Not_Connected.

   function Is_Open (B : Body_Stream) return Boolean;
   --  @param B Stream to query.
   --  @return True while the adapter is open and not explicitly closed.

   function Last_Status (B : Body_Stream) return Http_Client.Errors.Result_Status;
   --  @param B Stream to query.
   --  @return Most recent status.

   function Read_Some
     (B      : in out Body_Stream;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status;
   --  Pull the next HTTP/3 DATA payload bytes.
   --
   --  @param B Stream to read.
   --  @param Buffer Caller-provided byte buffer.
   --  @param Last Number of bytes written into Buffer.
   --  @return Ok with Last > 0, End_Of_Stream with Last = 0, Timeout when the
   --          backend has not queued more DATA and the stream has not ended, or
   --          a deterministic failure status.

   function Read_Some
     (B      : in out Body_Stream;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status;
   --  Binary-safe byte-array pull API for Git packet-line and packfile bytes.
   --
   --  @param B Stream to read.
   --  @param Buffer Caller-provided byte buffer.
   --  @param Last Last written array index, or Buffer'First - 1 for no data.
   --  @return Same status model as the String overload.

   function Close (B : in out Body_Stream) return Http_Client.Errors.Result_Status;
   --  Close the adapter and discard any unread queued DATA. Closing twice is Ok.
   --
   --  @param B Stream to close.
   --  @return Ok.

private
   type Body_Stream is record
      Opened      : Boolean := False;
      Finished    : Boolean := True;
      Failed      : Boolean := False;
      Buffer      : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Read_Offset : Natural := 1;
      Total       : Natural := 0;
      Max_Body    : Natural := 0;
      Last_Result : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   end record;
end Http_Client.HTTP3.Body_Streams;
