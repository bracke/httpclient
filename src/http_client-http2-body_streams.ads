with Ada.Streams;

with Http_Client.Errors;
with Http_Client.HTTP2.Connection;
with Http_Client.HTTP2.Frames;
with Http_Client.HTTP2.Streams;

package Http_Client.HTTP2.Body_Streams is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  Public HTTP/2 response-body stream adapter.
   --
   --  This package adapts the bounded Http_Client.HTTP2.Connection DATA queue
   --  to the protocol-independent streaming-response shape. Reads
   --  return decoded response body bytes only, never HTTP/2 frame bytes. The
   --  caller-owned connection must remain alive while a Body_Stream is open.
   --  The type is not task-safe; callers sharing one connection or stream
   --  between Ada tasks must serialize access externally.
   --
   --  Early close marks only the addressed stream cancelled. A real transport
   --  should serialize RST_STREAM(CANCEL) when practical and may keep the
   --  connection reusable if protocol state remains clean. Trailers are not
   --  exposed as body bytes by this adapter; Phase 10 trailing HEADERS are
   --  tracked by the HTTP/2 connection layer and kept separate from DATA.

   type Connection_Access is access all Http_Client.HTTP2.Connection.Connection_State;

   type Body_Stream is limited private;
   --  Borrowed HTTP/2 response body stream. The stream does not own the
   --  connection object; it only owns a live stream-id view and local read
   --  offset. Close is explicit and idempotent.

   function Open
     (Connection : Connection_Access;
      Stream     : Http_Client.HTTP2.Frames.Stream_ID;
      B          : out Body_Stream) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Connection Subprogram parameter.
   --  @param Stream Subprogram parameter.
   --  @param B Subprogram parameter.
   --  @return Subprogram result.
   --  Attach B to an existing HTTP/2 stream after response HEADERS have been
   --  accepted. HTTP/2 public streaming must be explicitly enabled. Opening an
   --  unknown, reset, idle, or closed-before-consumption stream fails
   --  deterministically.

   function Is_Open (B : Body_Stream) return Boolean;
   --  GNATdoc contract.
   --  @param B Subprogram parameter.
   --  @return Subprogram result.
   --  Return True until END_STREAM is fully consumed, a stream failure is
   --  observed, or Close is called.

   function Last_Status (B : Body_Stream) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param B Subprogram parameter.
   --  @return Subprogram result.
   --  Return the most recent body-stream status.

   function Read_Some
     (B   : in out Body_Stream;
      Buffer : out String;
      Last   : out Natural) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param B Subprogram parameter.
   --  @param Buffer Subprogram parameter.
   --  @param Last Subprogram parameter.
   --  @return Subprogram result.
   --  Copy queued DATA bytes into Buffer. Ok with Last > 0 returns body bytes,
   --  credits receive flow-control through the connection model, and removes
   --  those bytes from the bounded unread queue. If the peer already ended
   --  the response side while the local request side remains open, EOF is
   --  reported without releasing the underlying half-closed-remote stream.
   --  Timeout
   --  with Last = 0 means no DATA is currently queued in the deterministic
   --  in-memory adapter but END_STREAM has not yet been observed. If the
   --  stream has cleanly reached END_STREAM and all queued bytes were consumed,
   --  End_Of_Stream with Last = 0 is returned and stream bookkeeping may be
   --  released. If a peer RST_STREAM is observed, the reset status is returned
   --  and reset stream bookkeeping is released after the caller observes it.
   --  GOAWAY, unsupported trailers, length mismatch, body-size limit,
   --  bodyless-DATA errors, and protocol failures are reported as deterministic
   --  statuses. DATA-frame semantic failures such as bodyless DATA, response
   --  size overflow, and content-length mismatch reset only the affected stream
   --  and credit any previously queued unread DATA immediately. After such a
   --  terminal status is observed by the caller, this adapter releases stream
   --  bookkeeping where safe; no automatic retry occurs after this public
   --  stream has been returned to the caller.



   function Read_Some
     (B      : in out Body_Stream;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param B Subprogram parameter.
   --  @param Buffer Caller-provided byte buffer.
   --  @param Last Last written array index, or Buffer'First - 1 for no data.
   --  @return Subprogram result.
   --  Copy queued HTTP/2 DATA payload bytes into Buffer. This overload is the
   --  binary-safe form for Git-style packet-line and packfile data. It never
   --  exposes HTTP/2 frame metadata and preserves NUL bytes and bytes above
   --  127 exactly.

   function Close (B : in out Body_Stream) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param B Subprogram parameter.
   --  @return Subprogram result.
   --  Close the stream. If called before END_STREAM is observed, cancel the
   --  HTTP/2 stream state with RST_STREAM semantics. If END_STREAM has already
   --  arrived but unread DATA remains queued, the unread tail is discarded,
   --  receive windows are credited, and the stream slot is released. If only
   --  the remote response side has ended, Close releases the public response
   --  slot but leaves the HTTP/2 stream state available to the upload path.
   --  If the stream was already reset, Close releases reset bookkeeping.
   --  Closing twice returns Ok.

private
   type Body_Stream is record
      Conn        : Connection_Access := null;
      Stream      : Http_Client.HTTP2.Frames.Stream_ID := 0;
      Offset      : Natural := 0;
      Opened      : Boolean := False;
      Finished    : Boolean := True;
      Last_Result : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
   end record;
end Http_Client.HTTP2.Body_Streams;
