with Ada.Strings.Unbounded;

with Http_Client.Errors;

private with Zlib;

package Http_Client.Zlib_Decompression is
   --  Ada-only decompression adapter used by Http_Client.Decompression and
   --  Http_Client.Response_Streams. This package is the only place where the
   --  external Ada Zlib library is referenced. No C zlib symbols are imported
   --  by Http_Client.

   type Wrapper_Format is (Gzip, Zlib_Wrapped_Deflate, Raw_Deflate);
   --  Supported HTTP content-coding wrappers. Raw_Deflate has no zlib
   --  or gzip wrapper and is selected only by explicit decompression policy.

   type Decoder is limited private;
   --  Incremental inflater state. A Decoder owns the underlying Zlib filter
   --  while initialized. Close is idempotent.

   function Looks_Like_Zlib_Header (Input : String) return Boolean;
   --  Return True when Input starts with a syntactically valid zlib CMF/FLG
   --  header. This keeps HTTP-facing deflate auto policy on the adapter
   --  boundary while delegating zlib syntax to the Zlib crate.
   --
   --  @param Input Encoded octets stored byte-for-byte in String form.
   --  @return True when the first two bytes satisfy zlib CMF/FLG checks.

   function Looks_Like_GZip_Header (Input : String) return Boolean;
   --  Return True when Input starts with a syntactically valid gzip header
   --  prefix for Deflate. This keeps HTTP-facing wrapper selection on the
   --  adapter boundary while delegating gzip syntax to the Zlib crate.
   --
   --  @param Input Encoded octets stored byte-for-byte in String form.
   --  @return True when gzip magic, method, and reserved flags are valid.

   function Decode_All
     (Input      : String;
      Format     : Wrapper_Format;
      Max_Output : Natural;
      Output     : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
   --  Decode one complete gzip, zlib-wrapped deflate, or raw-deflate byte string.
   --
   --  @param Input Encoded octets stored byte-for-byte in String form.
   --  @param Format Compression wrapper to expect.
   --  @param Max_Output Maximum decoded octets accepted.
   --  @param Output Decoded octets stored byte-for-byte in String form.
   --  @return Ok, Decompression_Failed, Decoded_Body_Too_Large, or
   --          Internal_Error.

   function Initialize
     (Item : in out Decoder; Format : Wrapper_Format)
      return Http_Client.Errors.Result_Status;
   --  Initialize an incremental decoder for the requested wrapper. Reinitializing an open Decoder first
   --  closes the previous filter.
   --
   --  @param Item Decoder to initialize.
   --  @param Format Compression wrapper to expect.
   --  @return Ok or Decompression_Failed.

   function Decode_Some
     (Item       : in out Decoder;
      Input      : String;
      Finish     : Boolean;
      Max_Output : Natural;
      Output     : out Ada.Strings.Unbounded.Unbounded_String;
      Stream_End : out Boolean) return Http_Client.Errors.Result_Status;
   --  Feed encoded octets into an incremental decoder and return decoded octets.
   --
   --  @param Item Open decoder state.
   --  @param Input Encoded octets for this step; may be empty only when Finish
   --         is True.
   --  @param Finish True when no more encoded input will be supplied.
   --  @param Max_Output Maximum additional decoded octets accepted for this
   --         call.
   --  @param Output Decoded octets produced by this call.
   --  @param Stream_End True when the wrapped compressed stream has ended.
   --  @return Ok, Decompression_Failed, Decoded_Body_Too_Large, or
   --          Internal_Error.

   procedure Close (Item : in out Decoder);
   --  GNATdoc contract.
   --  @param Item Decoder instance to finalize and invalidate.
   --  Close the underlying Zlib filter if open. Idempotent.

private
   type Decoder is limited record
      Filter : Zlib.Filter_Type;
      Opened : Boolean := False;
   end record;
end Http_Client.Zlib_Decompression;