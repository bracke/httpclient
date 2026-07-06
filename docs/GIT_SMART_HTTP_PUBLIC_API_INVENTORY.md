# Git smart HTTP public API inventory

Phase 1 freezes the compiled public surface that a downstream Git smart HTTP
consumer may rely on. The source of truth is the `.ads` files in `src/`; this
document intentionally records concrete signatures rather than approximate
pseudocode. `HttpClient` remains a generic HTTP client crate. It does not
contain `Version.Transport.Http` or any downstream VCS adapter.

## Status and byte model

```ada
type Result_Status is
  (Ok, Invalid_URI, Invalid_Header, Invalid_Request, Connection_Failed,
   DNS_Failed, Not_Connected, Write_Failed, Read_Failed, End_Of_Stream,
   Incomplete_Message, TLS_Failed, Certificate_Verification_Failed,
   Hostname_Verification_Failed, TLS_Handshake_Failed, CA_Store_Failed,
   TLS_Client_Certificate_Load_Failed, TLS_Client_Key_Load_Failed,
   TLS_Client_Key_Mismatch, TLS_Client_Key_Passphrase_Required,
   TLS_Client_Key_Passphrase_Invalid, TLS_Client_Certificate_Unsupported,
   TLS_Client_Certificate_Rejected, TLS_Client_Certificate_Scope_Mismatch,
   TLS_Client_Certificate_Configuration_Invalid, Timeout, Cancelled,
   Response_Too_Large, Header_Too_Large, Too_Many_Redirects,
   Invalid_Redirect, Invalid_Cookie, Cookie_Rejected, Cookie_Too_Large,
   Unsupported_Content_Encoding, Decompression_Failed,
   Decoded_Body_Too_Large, Invalid_Proxy, Proxy_Unsupported,
   Proxy_Connection_Failed, Proxy_Tunnel_Failed,
   Proxy_Authentication_Required, Invalid_SOCKS_Proxy,
   SOCKS_Unsupported_Version, SOCKS_Unsupported_Authentication_Method,
   SOCKS_Authentication_Failed, SOCKS_Connect_Failed,
   SOCKS_General_Server_Failure, SOCKS_Connection_Not_Allowed,
   SOCKS_TTL_Expired, SOCKS_Command_Unsupported, SOCKS_Malformed_Reply,
   SOCKS_Address_Type_Unsupported, SOCKS_Reply_Connection_Refused,
   SOCKS_Reply_Network_Unreachable, SOCKS_Reply_Host_Unreachable,
   Invalid_Credentials, Unsupported_Authentication_Scheme,
   Authentication_Required, Authentication_Failed,
   Authentication_Replay_Disallowed, Authentication_Challenge_Malformed,
   Authentication_Scope_Mismatch, Digest_Algorithm_Unsupported,
   Digest_QOP_Unsupported, Digest_Nonce_Stale,
   Authentication_Loop_Detected, Invalid_Configuration,
   Client_Not_Initialized, Retry_Disallowed, Retry_Body_Not_Replayable,
   Body_Not_Replayable, Body_Length_Mismatch, Body_Producer_Failed,
   Upload_Too_Large, Chunked_Upload_Unsupported,
   Invalid_Multipart_Boundary, Invalid_Form_Field, Invalid_File_Name,
   Multipart_Too_Large, Too_Many_Parts, Part_Length_Unknown,
   Part_Producer_Failed, Cache_Miss, Cache_Entry_Stale,
   Cache_Revalidation_Failed, Cache_Entry_Too_Large, Cache_Disabled,
   Invalid_Cache_Metadata, Cache_Open_Failed, Cache_Read_Failed,
   Cache_Write_Failed, Cache_Corrupt_Entry, Cache_Format_Unsupported,
   Cache_Limit_Exceeded, Cache_Storage_Unavailable,
   Cache_Encryption_Failed, Cache_Decryption_Failed,
   Cache_Authentication_Failed, Cache_Key_Invalid, Cache_KDF_Failed,
   Cache_Random_Failed, Cache_Encrypted_Format_Unsupported,
   Cache_Wrong_Key, HTTP2_Protocol_Error, HTTP2_Frame_Error,
   HTTP2_Compression_Error, HTTP2_Flow_Control_Error,
   HTTP2_Settings_Error, HTTP2_Header_Error, HTTP2_Stream_Reset, HTTP2_Stream_Refused,
   HTTP2_Stream_Limit_Reached, HTTP2_Stream_State_Error,
   HTTP2_Connection_Goaway, HTTP2_Header_Block_Interleaving_Error,
   HTTP2_Multiplexing_Unsupported, HTTP2_Unsupported_Feature,
   HTTP3_Unsupported, HTTP3_Frame_Error, HTTP3_Settings_Error,
   HTTP3_QPACK_Error, HTTP3_Stream_Error, HTTP3_Goaway,
   HTTP3_Protocol_Error, QUIC_Unsupported, QUIC_Connection_Failed,
   QUIC_Handshake_Failed, QUIC_Transport_Error, HTTP3_Proxy_Unsupported,
   HTTP3_Fallback_Disallowed, ALPN_Negotiation_Failed,
   HPACK_Decode_Failed, HPACK_Huffman_Error, Pool_Closed,
   Pool_Exhausted, Connection_Not_Reusable, Stale_Connection,
   Redirect_Downgrade_Blocked, Redirect_Body_Replay_Disallowed,
   Protocol_Error, Unsupported_Feature, Async_Queue_Full,
   Async_Cancelled, Async_Shutdown, Async_Not_Ready,
   Async_Result_Already_Taken, Async_Handle_Invalid,
   Async_Worker_Failed, Async_Unsupported_Mode, Internal_Error);

type Result_Category is
  (Success_Category, Validation_Category, Request_Category,
   Transport_Category, TLS_Category, Proxy_Category,
   Authentication_Category, Configuration_Category,
   Retry_Redirect_Category, Body_Category, Cache_Category,
   HTTP2_Category, HTTP3_Category, Pool_Category, Protocol_Category,
   Async_Category, Internal_Category);

function Category (Value : Result_Status) return Result_Category;
function Is_Success (Value : Result_Status) return Boolean;
```

Git packet-line and packfile data must use `Ada.Streams.Stream_Element_Array`
where possible. String body accessors remain byte-preserving 8-bit strings and
do not perform UTF-8 validation, charset conversion, line-ending normalization,
NUL stripping, or content interpretation.

## Request construction

```ada
type Request is private;

function Method_Image
  (Method : Http_Client.Types.Method_Name) return String;

function Create
  (Method    : Http_Client.Types.Method_Name;
   URI       : Http_Client.URI.URI_Reference;
   Item      : out Request;
   Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Payload   : String := "";
   Auto_Host : Boolean := True) return Http_Client.Errors.Result_Status;

function Default_Request return Request;
function Is_Valid (Item : Request) return Boolean;
function Method (Item : Request) return Http_Client.Types.Method_Name;
function URI (Item : Request) return Http_Client.URI.URI_Reference;
function Headers (Item : Request) return Http_Client.Headers.Header_List;
function Payload (Item : Request) return String;
function Request_Body (Item : Request) return Http_Client.Request_Bodies.Request_Body;
function Has_Payload (Item : Request) return Boolean;
function Request_Target (Item : Request) return String;
function Host_Header_Value (Item : Request) return String;

function Set_Payload
  (Item    : in out Request;
   Payload : String) return Http_Client.Errors.Result_Status;

function Set_Body
  (Item     : in out Request;
   New_Body : Http_Client.Request_Bodies.Request_Body)
   return Http_Client.Errors.Result_Status;

function Is_Body_Replayable (Item : Request) return Boolean;
function Reset_Body (Item : Request) return Http_Client.Errors.Result_Status;

procedure Set_Target
  (Item   : in out Request;
   Target : String);

function Target_Text (Item : Request) return String;
```

## Header collection

```ada
type Header_List is private;

function Empty return Header_List;
function Is_Valid_Name (Name : String) return Boolean;
function Is_Valid_Value (Value : String) return Boolean;

function Add
  (List  : in out Header_List;
   Name  : String;
   Value : String) return Http_Client.Errors.Result_Status;

function Add_HTTP2_Pseudo
  (List  : in out Header_List;
   Name  : String;
   Value : String) return Http_Client.Errors.Result_Status;

function Set
  (List  : in out Header_List;
   Name  : String;
   Value : String) return Http_Client.Errors.Result_Status;

procedure Append
  (List  : in out Header_List;
   Name  : String;
   Value : String)
with Pre => Is_Valid_Name (Name) and then Is_Valid_Value (Value);

function Contains (List : Header_List; Name : String) return Boolean;
function Get (List : Header_List; Name : String) return String;
function Count (List : Header_List; Name : String) return Natural;
function Remove (List : in out Header_List; Name : String) return Http_Client.Errors.Result_Status;
function Length (List : Header_List) return Natural;
procedure Clear (List : in out Header_List);
function Name_At (List : Header_List; Index : Positive) return String;
function Value_At (List : Header_List; Index : Positive) return String;
```

## Request bodies and upload producers

```ada
type Body_Kind is
  (Empty_Body, Buffered_Body, Fixed_Length_Stream, Unknown_Length_Stream);

type Body_Producer is limited interface;
type Body_Producer_Access is access all Body_Producer'Class;

function Read_Some
  (Item   : in out Body_Producer;
   Buffer : out String;
   Count  : out Natural) return Http_Client.Errors.Result_Status is abstract;

function Reset
  (Item : in out Body_Producer) return Http_Client.Errors.Result_Status is abstract;

type Request_Body is private;

function Empty return Request_Body;
function From_String (Payload : String) return Request_Body;

function From_Bytes
  (Payload : Ada.Streams.Stream_Element_Array) return Request_Body;

function From_Fixed_Length_Stream
  (Producer   : Body_Producer_Access;
   Length     : Natural;
   Replayable : Boolean := False) return Request_Body;

function From_Unknown_Length_Stream
  (Producer   : Body_Producer_Access;
   Replayable : Boolean := False) return Request_Body;

function From_Unknown_Length_Stream_With_Trailers
  (Producer   : Body_Producer_Access;
   Trailers   : Http_Client.Headers.Header_List;
   Replayable : Boolean := False) return Request_Body;

function With_Trailers
  (Item     : Request_Body;
   Trailers : Http_Client.Headers.Header_List) return Request_Body;

function Has_Trailers (Item : Request_Body) return Boolean;
function Trailers (Item : Request_Body) return Http_Client.Headers.Header_List;
function Kind (Item : Request_Body) return Body_Kind;
function Has_Body (Item : Request_Body) return Boolean;
function Is_Replayable (Item : Request_Body) return Boolean;
function Has_Producer (Item : Request_Body) return Boolean;
function Declared_Length (Item : Request_Body; Length : out Natural) return Boolean;
function Buffered_Payload (Item : Request_Body) return String;
function Buffered_Bytes (Item : Request_Body) return Ada.Streams.Stream_Element_Array;

function Read_Next
  (Item   : Request_Body;
   Buffer : out String;
   Count  : out Natural) return Http_Client.Errors.Result_Status;

function Read_Next
  (Item   : Request_Body;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
   return Http_Client.Errors.Result_Status;

function Reset_Body
  (Item : Request_Body) return Http_Client.Errors.Result_Status;
```

Buffered bodies are replayable and byte-preserving. Fixed-length stream bodies
carry an exact declared length. Unknown-length stream bodies are serialized as
HTTP/1.1 chunked uploads. Trailers are valid only with unknown-length chunked
uploads and are rejected for forbidden framing, routing, credential, and
connection-control names.

## Response model

```ada
type HTTP_Version is (HTTP_1_0, HTTP_1_1);

type Parse_Context is record
   Request_Was_HEAD : Boolean := False;
end record;

Default_Context : constant Parse_Context := (Request_Was_HEAD => False);

type Response is private;

function Default_Response return Response;
function Version_Image (Version : HTTP_Version) return String;
function Reason_Phrase (Item : Response) return String;
function Version (Item : Response) return HTTP_Version;
function Status_Code (Item : Response) return Http_Client.Types.Status_Code;
function Headers (Item : Response) return Http_Client.Headers.Header_List;
function Header (Item : Response; Name : String) return String;
function Has_Header (Item : Response; Name : String) return Boolean;
function Content_Type (Item : Response) return String;
function Has_Content_Type (Item : Response) return Boolean;
function Media_Type (Item : Response) return String;
function Charset (Item : Response) return String;
function Has_Charset (Item : Response) return Boolean;
function Trailers (Item : Response) return Http_Client.Headers.Header_List;
function Response_Body (Item : Response) return String;
function Response_Body_Bytes (Item : Response) return Ada.Streams.Stream_Element_Array;

function Copy_With_Headers
  (Item    : Response;
   Headers : Http_Client.Headers.Header_List) return Response;

function Parse_Header_Section
  (Input   : String;
   Result  : out Response;
   Context : Parse_Context := Default_Context)
   return Http_Client.Errors.Result_Status;

function Parse_Response
  (Input   : String;
   Result  : out Response;
   Context : Parse_Context := Default_Context)
   return Http_Client.Errors.Result_Status;
```

## Low-level execution options and buffered execution

```ada
type Protocol_Selection_Policy is
  (Protocol_From_Configuration, Force_HTTP_1_1, Prefer_HTTP_2,
   Force_HTTP_2, Prefer_HTTP_3, Force_HTTP_3);

type Execution_Options is record
   Max_Response_Size    : Natural := 16_777_216;
   Max_Header_Size      : Natural := 65_536;
   Max_Header_Line_Size : Natural := 8_192;
   Max_Body_Size        : Natural := 16_777_216;
   Read_Buffer_Size     : Positive := 4_096;
   Timeouts             : Http_Client.Transports.TCP.Timeout_Config :=
     Http_Client.Transports.TCP.Default_Timeouts;
   TLS                  : Http_Client.Transports.TLS.TLS_Options :=
     Http_Client.Transports.TLS.Default_TLS_Options;
   Add_Connection_Close : Boolean := True;
   Cookie_Jar           : Http_Client.Cookies.Cookie_Jar_Access := null;
   Strict_Cookies       : Boolean := False;
   Merge_Jar_Cookies    : Boolean := False;
   Advertise_Accept_Encoding : Boolean := False;
   Proxy                : Http_Client.Proxies.Proxy_Config :=
     Http_Client.Proxies.No_Proxy_Config;
   Diagnostics          : Http_Client.Diagnostics.Context_Access := null;
   Protocol_Policy      : Protocol_Selection_Policy := Protocol_From_Configuration;
end record;

function Create return Client;
function Supports_Network_IO (Item : Client) return Boolean;
function Is_Initialized (Item : Client) return Boolean;

function Execute
  (Item     : Client;
   Request  : Http_Client.Requests.Request;
   Response : out Http_Client.Responses.Response;
   Options  : Execution_Options := Default_Execution_Options)
   return Http_Client.Errors.Result_Status;

function Execute_Once
  (Request  : Http_Client.Requests.Request;
   Response : out Http_Client.Responses.Response;
   Options  : Execution_Options := Default_Execution_Options)
   return Http_Client.Errors.Result_Status;
```

`Execute` and `Execute_Once` are one-shot, non-retry, redirect-neutral buffered
APIs. They close owned transport handles after each exchange and do not mutate
the caller's request when adding temporary headers such as `Connection: close`.

## Redirect and retry execution

```ada
type Redirect_Method_Policy is
  (Rewrite_Post_To_Get_For_301_302, Preserve_Method_For_301_302);

type Redirect_Options is record
   Follow_Redirects               : Boolean := True;
   Max_Redirects                  : Natural := 10;
   Method_Policy_301_302          : Redirect_Method_Policy :=
     Rewrite_Post_To_Get_For_301_302;
   Allow_Body_Replay              : Boolean := False;
   Allow_HTTPS_To_HTTP_Redirects  : Boolean := False;
   Strip_Credentials_Cross_Origin : Boolean := True;
end record;

type Redirect_Result is record
   Final_Response : Http_Client.Responses.Response :=
     Http_Client.Responses.Default_Response;
   Final_URI      : Http_Client.URI.URI_Reference :=
     Http_Client.URI.Create_Unchecked ("");
   Redirect_Count : Natural := 0;
   Final_Request_Was_HEAD : Boolean := False;
end record;

subtype Retry_Result is Http_Client.Retry.Retry_Result;

function Execute_Following_Redirects
  (Item      : Client;
   Request   : Http_Client.Requests.Request;
   Result    : out Redirect_Result;
   Execution : Execution_Options := Default_Execution_Options;
   Redirects : Redirect_Options := Default_Redirect_Options)
   return Http_Client.Errors.Result_Status;

function Execute_With_Redirects
  (Item      : Client;
   Request   : Http_Client.Requests.Request;
   Result    : out Redirect_Result;
   Execution : Execution_Options := Default_Execution_Options;
   Redirects : Redirect_Options := Default_Redirect_Options)
   return Http_Client.Errors.Result_Status;

function Execute_With_Retry
  (Item      : Client;
   Request   : Http_Client.Requests.Request;
   Result    : out Retry_Result;
   Execution : Execution_Options := Default_Execution_Options;
   Retries   : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options)
   return Http_Client.Errors.Result_Status;

function Execute_Once_With_Retry
  (Request   : Http_Client.Requests.Request;
   Result    : out Retry_Result;
   Execution : Execution_Options := Default_Execution_Options;
   Retries   : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options)
   return Http_Client.Errors.Result_Status;

function Execute_With_Redirects_And_Retry
  (Item           : Client;
   Request        : Http_Client.Requests.Request;
   Result         : out Redirect_Result;
   Retry_Metadata : out Retry_Result;
   Execution      : Execution_Options := Default_Execution_Options;
   Redirects      : Redirect_Options := Default_Redirect_Options;
   Retries        : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options)
   return Http_Client.Errors.Result_Status;

function Execute_Once_With_Redirects_And_Retry
  (Request        : Http_Client.Requests.Request;
   Result         : out Redirect_Result;
   Retry_Metadata : out Retry_Result;
   Execution      : Execution_Options := Default_Execution_Options;
   Redirects      : Redirect_Options := Default_Redirect_Options;
   Retries        : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options)
   return Http_Client.Errors.Result_Status;
```

Retries are disabled by default. Default high-level redirects are enabled safely; strict configuration disables redirects. Non-replayable bodies must not be
retried or replayed across redirects.


## Download-to-file convenience API

`Http_Client.Clients` exposes file-download helpers for large non-Git assets and other callers that want a final response body on disk rather than in memory:

```ada
type Download_File_Mode is
  (Create_New,
   Overwrite,
   Replace_Atomically);

Default_Max_Download_Size : constant Natural := 1024 * 1024 * 1024;

type Download_Progress_Callback is access function
   (Bytes_Written : Natural;
    Total_Bytes   : Natural) return Http_Client.Errors.Result_Status;

type Download_Options is record
   Follow_Redirects      : Boolean := True;
   Max_Redirects         : Natural := 10;
   Max_Download_Size     : Natural := Default_Max_Download_Size;
   Require_Success_Status : Boolean := False;
   File_Mode             : Download_File_Mode := Replace_Atomically;
   Create_Parent_Dirs    : Boolean := False;
   Preserve_Partial_File : Boolean := False;
   Enable_Resume         : Boolean := False;
   Resume_If_Range       : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
   Expected_Size         : Natural := 0;
   Verify_SHA256         : Boolean := False;
   Expected_SHA256_Hex   : String (1 .. 64) := (others => '0');
   Progress_Callback     : Download_Progress_Callback := null;
   Progress_Interval_Bytes : Natural := 0;
   Cancellation         : Http_Client.Cancellation.Cancellation_Token_Access := null;
   Buffer_Size           : Positive := 64 * 1024;
end record;

type Download_Result is record
   Status              : Http_Client.Errors.Result_Status;
   Response            : Http_Client.Responses.Response;
   Final_URI           : Http_Client.URI.URI_Reference;
   HTTP_Status_Code    : Natural := 0;
   Expected_Final_Size : Natural := 0;
   Redirect_Count      : Natural := 0;
   Retry_Attempt_Count : Natural := 0;
   Resumed             : Boolean := False;
   Resume_Offset       : Natural := 0;
   Bytes_Written       : Natural := 0;
   Final_Size          : Natural := 0;
end record;

function Execute_To_File (...) return Http_Client.Errors.Result_Status;
function Download_To_File (...) return Http_Client.Errors.Result_Status;
```

The file-download helpers stream through `Execute_Stream` / `Response_Streams.Read_Some`; they do not call buffered `Get` or `Execute` and do not use buffered `Max_Body_Size` as their total-body cap. `Max_Download_Size` is the explicit cap for these APIs and defaults to `Default_Max_Download_Size` instead of the buffered response/body caps.

## Pull streaming API

```ada
type Streaming_Protocol_Policy is
  (Streaming_HTTP_1_1_Only, Streaming_Prefer_HTTP_2,
   Streaming_Force_HTTP_2, Streaming_Prefer_HTTP_3,
   Streaming_Force_HTTP_3);

type Streaming_Options is record
   Max_Header_Size       : Natural := 65_536;
   Max_Header_Line_Size  : Natural := 8_192;
   Max_Body_Size         : Natural := 16_777_216;
   Read_Buffer_Size      : Positive := 4_096;
   Timeouts              : Http_Client.Transports.TCP.Timeout_Config :=
     Http_Client.Transports.TCP.Default_Timeouts;
   TLS                   : Http_Client.Transports.TLS.TLS_Options :=
     Http_Client.Transports.TLS.Default_TLS_Options;
   Add_Connection_Close  : Boolean := True;
   Cookie_Jar            : Http_Client.Cookies.Cookie_Jar_Access := null;
   Strict_Cookies        : Boolean := False;
   Merge_Jar_Cookies     : Boolean := False;
   Enable_Decompression  : Boolean := False;
   Decompression         : Http_Client.Decompression.Decompression_Options :=
     Http_Client.Decompression.Default_Decompression_Options;
   HTTP3                 : Http_Client.HTTP3.HTTP3_Options :=
     Http_Client.HTTP3.Default_HTTP3_Options;
   Proxy                 : Http_Client.Proxies.Proxy_Config :=
     Http_Client.Proxies.No_Proxy_Config;
   Diagnostics           : Http_Client.Diagnostics.Context_Access := null;
   Protocol_Policy       : Streaming_Protocol_Policy := Streaming_HTTP_1_1_Only;
end record;

type Streaming_Response is new Ada.Finalization.Limited_Controlled with private;

function Open
  (Request   : Http_Client.Requests.Request;
   Stream    : in out Streaming_Response;
   Options   : Streaming_Options := Default_Streaming_Options;
   Final_URI : Http_Client.URI.URI_Reference :=
     Http_Client.URI.Create_Unchecked ("");
   Redirect_Count : Natural := 0;
   Retry_Attempt_Count : Natural := 1)
   return Http_Client.Errors.Result_Status;

function Metadata (Stream : Streaming_Response) return Http_Client.Responses.Response;
function Status_Code (Stream : Streaming_Response) return Http_Client.Types.Status_Code;
function Reason_Phrase (Stream : Streaming_Response) return String;
function Redirect_Count (Stream : Streaming_Response) return Natural;
function Retry_Attempt_Count (Stream : Streaming_Response) return Natural;
function Headers (Stream : Streaming_Response) return Http_Client.Headers.Header_List;
function Effective_URI (Stream : Streaming_Response) return Http_Client.URI.URI_Reference;
function Is_Open (Stream : Streaming_Response) return Boolean;
function End_Of_Body (Stream : Streaming_Response) return Boolean;
function Last_Status (Stream : Streaming_Response) return Http_Client.Errors.Result_Status;

function Read_Some
  (Stream : in out Streaming_Response;
   Buffer : out String;
   Last   : out Natural) return Http_Client.Errors.Result_Status;

function Read_Some
  (Stream : in out Streaming_Response;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
   return Http_Client.Errors.Result_Status;

function Close
  (Stream : in out Streaming_Response) return Http_Client.Errors.Result_Status;

function Execute_Stream
  (Request : Http_Client.Requests.Request;
   Stream  : in out Http_Client.Response_Streams.Streaming_Response;
   Options : Execution_Options := Default_Execution_Options)
   return Http_Client.Errors.Result_Status;

function Execute_Stream
  (Item    : Client;
   Request : Http_Client.Requests.Request;
   Stream  : in out Http_Client.Response_Streams.Streaming_Response)
   return Http_Client.Errors.Result_Status;
```

The Git-safe loop is:

```ada
while not Http_Client.Response_Streams.End_Of_Body (Stream) loop
   Status := Http_Client.Response_Streams.Read_Some (Stream, Buffer, Last);
   -- Feed Buffer (Buffer'First .. Last) to the pkt-line or pack parser.
end loop;
```

HTTP/1.1 chunked response framing is decoded incrementally before `Read_Some`
returns bytes. `Read_Some` never exposes chunk sizes, chunk extensions, chunk
CRLF delimiters, or trailers. Whole-body buffering is not required for the
streaming path.

## Configured client API

```ada
type Client_Configuration is record
   Execution            : Execution_Options := Default_Execution_Options;
   Redirects            : Redirect_Options := Default_Redirect_Options;
   Retries              : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options;
   Enable_Decompression : Boolean := True;
   Decompression        : Http_Client.Decompression.Decompression_Options :=
     Http_Client.Decompression.Default_Decompression_Options;
   Default_Headers      : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
   Pooling              : Http_Client.Connection_Pools.Pooling_Options :=
     Http_Client.Connection_Pools.Default_Pooling_Options;
   Cache                : Http_Client.Cache.Cache_Config := Http_Client.Cache.Default_Cache_Config;
   HTTP3                : Http_Client.HTTP3.HTTP3_Options :=
     Http_Client.HTTP3.Default_HTTP3_Options;
   Cache_Store          : Http_Client.Cache.Cache_Store_Access := null;
   Persistent_Cache_Store :
     Http_Client.Cache.Persistent.Persistent_Store_Access := null;
   Discovery            : Http_Client.Protocol_Discovery.Discovery_Options :=
     Http_Client.Protocol_Discovery.Default_Discovery_Options;
   Proxy_Discovery      : Http_Client.Proxy_Discovery.Discovery_Options :=
     Http_Client.Proxy_Discovery.Default_Discovery_Options;
   Proxy_PAC_Script     : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
end record;

type Client_Result is record
   Status              : Http_Client.Errors.Result_Status :=
     Http_Client.Errors.Internal_Error;
   Response            : Http_Client.Responses.Response :=
     Http_Client.Responses.Default_Response;
   Decoded_Response    : Http_Client.Decompression.Decoded_Response :=
     Http_Client.Decompression.Default_Decoded_Response;
   Final_URI           : Http_Client.URI.URI_Reference :=
     Http_Client.URI.Create_Unchecked ("");
   Redirect_Count      : Natural := 0;
   Retry_Attempt_Count : Natural := 0;
   Retry_Exhausted     : Boolean := False;
   Used_Decoded_View   : Boolean := False;
   Cache_Metadata      : Http_Client.Cache.Cache_Metadata :=
     (Source             => Http_Client.Cache.Cache_Bypassed,
      Stored_Time        => Ada.Calendar.Time_Of (1970, 1, 1),
      Fresh_Until        => Ada.Calendar.Time_Of (1970, 1, 1),
      Age_Seconds        => 0,
      Revalidation_Count => 0,
      Entry_Count        => 0,
      Stored_Body_Bytes  => 0);
end record;

function Validate
  (Configuration : Client_Configuration) return Http_Client.Errors.Result_Status;

function Initialize
  (Item          : in out Client;
   Configuration : Client_Configuration := Default_Client_Configuration)
   return Http_Client.Errors.Result_Status;

function Configure
  (Item          : in out Client;
   Configuration : Client_Configuration) return Http_Client.Errors.Result_Status;

function Configuration (Item : Client) return Client_Configuration;

function Execute
  (Item    : Client;
   Request : Http_Client.Requests.Request;
   Result  : out Client_Result) return Http_Client.Errors.Result_Status;
```

## Retry options

```ada
subtype Delay_Milliseconds is Natural;
type Backoff_Mode is (Fixed_Delay, Exponential_Delay);
type Delay_Hook_Access is access procedure (Pause : Delay_Milliseconds);

type Retry_Options is record
   Enable_Retries              : Boolean := False;
   Maximum_Attempts            : Positive := 1;
   Retry_Connect_Failures      : Boolean := True;
   Retry_Read_Failures         : Boolean := True;
   Retry_Write_Failures        : Boolean := True;
   Retry_Timeouts              : Boolean := True;
   Retry_5xx_Responses         : Boolean := False;
   Retry_429                   : Boolean := False;
   Retry_408                   : Boolean := False;
   Base_Delay                  : Delay_Milliseconds := 0;
   Maximum_Delay               : Delay_Milliseconds := 0;
   Backoff                     : Backoff_Mode := Fixed_Delay;
   Respect_Retry_After         : Boolean := False;
   Maximum_Retry_After         : Delay_Milliseconds := 60_000;
   Allow_Non_Idempotent_Retry  : Boolean := False;
   Retry_Transient_TLS_Failure : Boolean := False;
   Delay_Hook                  : Delay_Hook_Access := null;
end record;

type Retry_Result is record
   Final_Response    : Http_Client.Responses.Response := Http_Client.Responses.Default_Response;
   Final_Status      : Http_Client.Errors.Result_Status := Http_Client.Errors.Internal_Error;
   Attempts          : Positive := 1;
   Retries_Exhausted : Boolean := False;
   Last_Failure      : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
end record;
```

## TLS, TCP timeout, proxy, and decompression options

```ada
type Timeout_Milliseconds is range 0 .. 3_600_000;

type Timeout_Config is record
   Connect : Timeout_Milliseconds := 0;
   Read    : Timeout_Milliseconds := 0;
   Write   : Timeout_Milliseconds := 0;
end record;

type TLS_Options is record
   Timeouts : Http_Client.Transports.TCP.Timeout_Config :=
     Http_Client.Transports.TCP.Default_Timeouts;
   Disable_Certificate_Verification : Boolean := False;
   CA_File : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
   CA_Directory : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
   Send_SNI : Boolean := True;
   HTTP2 : Http_Client.HTTP2.HTTP2_Options := Http_Client.HTTP2.Default_HTTP2_Options;
   Client_Certificate : Http_Client.TLS.Client_Certificates.Client_Certificate :=
     Http_Client.TLS.Client_Certificates.No_Client_Certificate;
end record;

function Validate_Options
  (Options : TLS_Options) return Http_Client.Errors.Result_Status;

type Proxy_Kind is (No_Proxy, HTTP_Proxy, SOCKS5_Proxy);
type SOCKS5_Authentication_Method is (SOCKS5_No_Authentication, SOCKS5_Username_Password);
type SOCKS5_DNS_Mode is (SOCKS5_Remote_DNS, SOCKS5_Local_DNS);
type Proxy_Config is private;

function Parse (Text : String; Item : out Proxy_Config) return Http_Client.Errors.Result_Status;
function HTTP (Host : String; Port : Http_Client.URI.TCP_Port := 80) return Proxy_Config;
function SOCKS5
  (Host     : String;
   Port     : Http_Client.URI.TCP_Port := 1080;
   DNS_Mode : SOCKS5_DNS_Mode := SOCKS5_Remote_DNS) return Proxy_Config;

function With_Proxy_Authorization
  (Config : Proxy_Config; Value : String; Item : out Proxy_Config)
   return Http_Client.Errors.Result_Status;

function With_SOCKS5_Username_Password
  (Config   : Proxy_Config;
   Username : String;
   Password : String;
   Item     : out Proxy_Config) return Http_Client.Errors.Result_Status;

type Deflate_Decoding_Mode is
  (Zlib_Wrapped_Only, Raw_Only, Auto_Zlib_Then_Raw);

type Unsupported_Encoding_Policy is (Reject_Unsupported, Leave_Encoded);

type Decompression_Options is record
   Maximum_Decoded_Body_Size : Natural := 4_194_304;
   Unsupported_Policy        : Unsupported_Encoding_Policy := Reject_Unsupported;
   Deflate_Mode              : Deflate_Decoding_Mode := Zlib_Wrapped_Only;
end record;
```

High-level buffered decompression is enabled by default; low-level streaming remains raw by default, while configured high-level client streams and file downloads can opt in through Client_Configuration.Enable_Decompression.
`Accept-Encoding` is not automatically added unless the relevant explicit option
requests it. Git callers may send `Accept-Encoding: identity` for maximum
predictability.

## HTTP/2 and HTTP/3 protocol options

```ada
type HTTP2_Mode is (HTTP2_Disabled, HTTP2_Allowed, HTTP2_Required);
type Selected_Protocol is
  (Protocol_None, Protocol_HTTP_1_1, Protocol_HTTP_2, Protocol_Unsupported);

type HTTP2_Options is record
   Mode                    : HTTP2_Mode := HTTP2_Disabled;
   Max_Frame_Size          : Natural := 16_384;
   Max_Header_List_Size    : Natural := 65_536;
   Max_Body_Size           : Natural := 16_777_216;
   Enable_Server_Push      : Boolean := False;
   Enable_Multiplexing     : Boolean := False;
   Enable_Public_Streaming : Boolean := False;
   Enable_Upload_Streaming : Boolean := False;
   Max_Per_Stream_Buffered_Bytes : Natural := 16_777_216;
   Max_Total_Queued_Body_Bytes : Natural := 67_108_864;
   Max_Active_Streamed_Responses : Natural := 1;
   Max_Active_Upload_Streams : Natural := 1;
   Flow_Control_Update_Threshold : Natural := 16_384;
   Upload_Flow_Control_Timeout_MS : Natural := 30_000;
   Allow_Unknown_Length_HTTP2_Bodies : Boolean := False;
   Enable_Streaming_Decompression : Boolean := False;
   Local_Max_Concurrent_Streams : Natural := 1;
   Initial_Stream_Window_Size   : Natural := 1_048_576;
   Initial_Connection_Window_Size : Natural := 1_048_576;
end record;

function Validate (Options : HTTP2_Options) return Http_Client.Errors.Result_Status;
function ALPN_Advertisement (Options : HTTP2_Options) return String;
function Normalize_ALPN_Selected (Protocol : String) return Selected_Protocol;
function Selected_Status
  (Options : HTTP2_Options; Selected : Selected_Protocol)
   return Http_Client.Errors.Result_Status;
function Execution_Status_For_Selected
  (Options : HTTP2_Options; Selected : Selected_Protocol)
   return Http_Client.Errors.Result_Status;

type HTTP3_Mode is (HTTP3_Disabled, HTTP3_Allowed, HTTP3_Required);
type Protocol_Fallback_Policy is (Fallback_Disallowed, Fallback_Before_Send);
type Selected_Protocol is
  (Protocol_None, Protocol_HTTP_1_1, Protocol_HTTP_2,
   Protocol_HTTP_3, Protocol_Unknown);

type HTTP3_Options is record
   Mode            : HTTP3_Mode := HTTP3_Disabled;
   Fallback        : Protocol_Fallback_Policy := Fallback_Disallowed;
   QUIC            : Http_Client.QUIC.QUIC_Options := Http_Client.QUIC.Default_QUIC_Options;
   Max_Frame_Size  : Natural := 16_384;
   Max_Header_List_Size : Natural := 65_536;
   Enable_Server_Push : Boolean := False;
   Enable_Zero_RTT : Boolean := False;
end record;

function Validate (Options : HTTP3_Options) return Http_Client.Errors.Result_Status;
function ALPN_Token (Options : HTTP3_Options) return String;
function Normalize_ALPN_Selected (Token : String) return Selected_Protocol;
function Execution_Status
  (Options                      : HTTP3_Options;
   Proxy_Configured             : Boolean := False;
   SOCKS_Configured             : Boolean := False;
   Client_Certificate_Configured : Boolean := False)
   return Http_Client.Errors.Result_Status;
function Fallback_Status
  (Options                    : HTTP3_Options;
   Request_Bytes_Already_Sent : Boolean) return Http_Client.Errors.Result_Status;
```

HTTP/2 is optional and not the default safest Git streaming path. HTTP/3 is
experimental, backend-dependent, and must fail deterministically when unavailable.

## Phase 1 verification surface

The compile-only API stability project is:

```text
tests/api_stability/api_stability.gpr
tests/api_stability/src/api_stability_compile.adb
```

It exercises buffered GET construction, streaming GET construction, binary POST
bodies with `Ada.Streams.Stream_Element_Array`, fixed-length producers,
unknown-length chunked producers, trailers, explicit `Expect: 100-continue`,
`Execution_Options`, `Streaming_Options`, TLS custom CA fields, HTTP and SOCKS5
proxy options, retry/redirect/decompression options, HTTP/2 and HTTP/3 options,
response byte access, and byte-array `Read_Some` calls.

## Phase 1 completeness supplement

This supplement closes the inventory gaps found during the Phase 1 completeness
pass. The requested `src/http_client-redirects.ads` and
`src/http_client-configuration.ads` files are not present in the current tree;
redirect policy and reusable client configuration are exported by
`Http_Client.Clients`.

### Configured client surface

```ada
type Client_Configuration is record
   Execution            : Execution_Options := Default_Execution_Options;
   Redirects            : Redirect_Options := Default_Redirect_Options;
   Retries              : Http_Client.Retry.Retry_Options :=
     Http_Client.Retry.Default_Retry_Options;
   Enable_Decompression : Boolean := False;
   Decompression        : Http_Client.Decompression.Decompression_Options :=
     Http_Client.Decompression.Default_Decompression_Options;
   Default_Headers      : Http_Client.Headers.Header_List :=
     Http_Client.Headers.Empty;
   Pooling              : Http_Client.Connection_Pools.Pooling_Options :=
     Http_Client.Connection_Pools.Default_Pooling_Options;
   Cache                : Http_Client.Cache.Cache_Config :=
     Http_Client.Cache.Default_Cache_Config;
   HTTP3                : Http_Client.HTTP3.HTTP3_Options :=
     Http_Client.HTTP3.Default_HTTP3_Options;
   Cache_Store          : Http_Client.Cache.Cache_Store_Access := null;
   Persistent_Cache_Store :
     Http_Client.Cache.Persistent.Persistent_Store_Access := null;
   Discovery            : Http_Client.Protocol_Discovery.Discovery_Options :=
     Http_Client.Protocol_Discovery.Default_Discovery_Options;
   Proxy_Discovery      : Http_Client.Proxy_Discovery.Discovery_Options :=
     Http_Client.Proxy_Discovery.Default_Discovery_Options;
   Proxy_PAC_Script     : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;
end record;

Default_Client_Configuration : constant Client_Configuration;
Strict_Client_Configuration : constant Client_Configuration;

type Client_Result is record
   Status              : Http_Client.Errors.Result_Status :=
     Http_Client.Errors.Internal_Error;
   Response            : Http_Client.Responses.Response :=
     Http_Client.Responses.Default_Response;
   Decoded_Response    : Http_Client.Decompression.Decoded_Response :=
     Http_Client.Decompression.Default_Decoded_Response;
   Final_URI           : Http_Client.URI.URI_Reference :=
     Http_Client.URI.Create_Unchecked ("");
   Redirect_Count      : Natural := 0;
   Retry_Attempt_Count : Natural := 0;
   Retry_Exhausted     : Boolean := False;
   Used_Decoded_View   : Boolean := False;
   Cache_Metadata      : Http_Client.Cache.Cache_Metadata;
end record;

function Validate
  (Configuration : Client_Configuration)
   return Http_Client.Errors.Result_Status;

function Initialize
  (Item          : in out Client;
   Configuration : Client_Configuration := Default_Client_Configuration)
   return Http_Client.Errors.Result_Status;

function Configure
  (Item          : in out Client;
   Configuration : Client_Configuration)
   return Http_Client.Errors.Result_Status;

function Configuration (Item : Client) return Client_Configuration;

function Set_Default_Header
  (Configuration : in out Client_Configuration;
   Name          : String;
   Value         : String) return Http_Client.Errors.Result_Status;

function Remove_Default_Header
  (Configuration : in out Client_Configuration;
   Name          : String) return Http_Client.Errors.Result_Status;

function Execute
  (Item    : Client;
   Request : Http_Client.Requests.Request;
   Result  : out Client_Result) return Http_Client.Errors.Result_Status;

function Execute_Stream
  (Item    : Client;
   Request : Http_Client.Requests.Request;
   Stream  : in out Http_Client.Response_Streams.Streaming_Response)
   return Http_Client.Errors.Result_Status;

function Get
  (Item   : Client;
   URL    : String;
   Result : out Client_Result) return Http_Client.Errors.Result_Status;

function Delete
  (Item   : Client;
   URL    : String;
   Result : out Client_Result) return Http_Client.Errors.Result_Status;

function Put
  (Item         : Client;
   URL          : String;
   Payload      : String;
   Result       : out Client_Result;
   Content_Type : String := "") return Http_Client.Errors.Result_Status;

function Post
  (Item         : Client;
   URL          : String;
   Payload      : String;
   Result       : out Client_Result;
   Content_Type : String := "") return Http_Client.Errors.Result_Status;
```

### Additional retry helpers

```ada
function Is_Retryable_Method
  (Method  : Http_Client.Types.Method_Name;
   Options : Retry_Options := Default_Retry_Options) return Boolean;

function Is_Request_Body_Replayable
  (Request : Http_Client.Requests.Request) return Boolean;

function Is_Retryable_Response
  (Response : Http_Client.Responses.Response;
   Options  : Retry_Options := Default_Retry_Options) return Boolean;

function Is_Retryable_Failure
  (Status  : Http_Client.Errors.Result_Status;
   Options : Retry_Options := Default_Retry_Options) return Boolean;

function Delay_For_Attempt
  (Attempt : Positive;
   Options : Retry_Options := Default_Retry_Options) return Delay_Milliseconds;

function Retry_After_Delay
  (Value   : String;
   Options : Retry_Options := Default_Retry_Options;
   Pause   : out Delay_Milliseconds) return Boolean;
```

### Additional decompression helpers

```ada
function Original_Response
  (Item : Decoded_Response) return Http_Client.Responses.Response;
function Encoded_Body (Item : Decoded_Response) return String;
function Original_Content_Encoding (Item : Decoded_Response) return String;
function Supported_Accept_Encoding return String;

function Decode_Body
  (Body             : String;
   Content_Encoding : String;
   Output           : out Ada.Strings.Unbounded.Unbounded_String;
   Options          : Decompression_Options := Default_Decompression_Options)
   return Http_Client.Errors.Result_Status;

function Decode_Response
  (Response : Http_Client.Responses.Response;
   Decoded  : out Decoded_Response;
   Options  : Decompression_Options := Default_Decompression_Options)
   return Http_Client.Errors.Result_Status;

function Decode_Response_With_Context
  (Response         : Http_Client.Responses.Response;
   Request_Was_HEAD : Boolean;
   Decoded          : out Decoded_Response;
   Options          : Decompression_Options := Default_Decompression_Options)
   return Http_Client.Errors.Result_Status;
```

### Additional URI and cookie accessors relevant to redirect/proxy callers

```ada
function Is_Empty (Item : URI_Reference) return Boolean;
function Is_Parsed (Item : URI_Reference) return Boolean;
function Has_Explicit_Port (Item : URI_Reference) return Boolean;
function Explicit_Port (Item : URI_Reference) return TCP_Port;
function Effective_Port (Item : URI_Reference) return TCP_Port;
function Path (Item : URI_Reference) return String;
function Effective_Path (Item : URI_Reference) return String;
function Has_Query (Item : URI_Reference) return Boolean;
function Query (Item : URI_Reference) return String;
function Has_Fragment (Item : URI_Reference) return Boolean;
function Fragment (Item : URI_Reference) return String;
function Requires_TLS (Item : URI_Reference) return Boolean;

type SameSite_Policy is (SameSite_Unspecified, SameSite_Lax, SameSite_Strict, SameSite_None);
type Cookie_Limits is record
   Max_Cookies              : Natural := 300;
   Max_Cookie_Size          : Natural := 4096;
   Max_Cookies_Per_Domain   : Natural := 50;
   Max_Cookie_Header_Length : Natural := 8192;
end record;

function Empty_Jar (Limits : Cookie_Limits := Default_Cookie_Limits) return Cookie_Jar;
function Store_From_Response
  (Jar             : in out Cookie_Jar;
   Request_URI     : Http_Client.URI.URI_Reference;
   Response_Headers : Http_Client.Headers.Header_List;
   Now             : Ada.Calendar.Time := Ada.Calendar.Clock)
   return Http_Client.Errors.Result_Status;
function Get_Cookie_Header
  (Jar         : Cookie_Jar;
   Request_URI : Http_Client.URI.URI_Reference;
   Now         : Ada.Calendar.Time := Ada.Calendar.Clock) return String;
```

### Additional proxy, TCP, TLS, HTTP/2, and HTTP/3 surface

```ada
function Is_Enabled (Item : Proxy_Config) return Boolean;
function Has_Proxy_Authorization (Item : Proxy_Config) return Boolean;
function SOCKS5_DNS_Resolution (Item : Proxy_Config) return SOCKS5_DNS_Mode;
function SOCKS5_Password (Item : Proxy_Config) return String;

function Open_URI
  (URI     : Http_Client.URI.URI_Reference;
   Conn    : out Connection;
   Options : Timeout_Config := Default_Timeouts)
   return Http_Client.Errors.Result_Status;
function Write_All
  (Conn : in out Connection;
   Data : String) return Http_Client.Errors.Result_Status;
function Round_Trip_First_Bytes
  (URI        : Http_Client.URI.URI_Reference;
   Request    : String;
   Max_Bytes  : Natural;
   Response   : out Ada.Strings.Unbounded.Unbounded_String;
   Options    : Timeout_Config := Default_Timeouts)
   return Http_Client.Errors.Result_Status;

function Open_Through_HTTP_Proxy
  (Proxy   : Http_Client.Proxies.Proxy_Config;
   Target  : Http_Client.URI.URI_Reference;
   Conn    : out Connection;
   Options : TLS_Options := Default_TLS_Options)
   return Http_Client.Errors.Result_Status;
function Open_Through_SOCKS_Proxy
  (Proxy   : Http_Client.Proxies.Proxy_Config;
   Target  : Http_Client.URI.URI_Reference;
   Conn    : out Connection;
   Options : TLS_Options := Default_TLS_Options)
   return Http_Client.Errors.Result_Status;
function Verification_Enabled_By_Default return Boolean;
function Selected_ALPN (Conn : Connection) return String;

type Connection_Access is access all Http_Client.HTTP2.Connection.Connection_State;
type Body_Stream is limited private;
function Open
  (Connection : Connection_Access;
   Stream     : Http_Client.HTTP2.Frames.Stream_ID;
   B          : out Body_Stream) return Http_Client.Errors.Result_Status;
function Read_Some
  (B      : in out Body_Stream;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
   return Http_Client.Errors.Result_Status;

type Body_Stream is limited private;
function Append_Data
  (B    : in out Body_Stream;
   Data : String) return Http_Client.Errors.Result_Status;
function Mark_End_Stream
  (B : in out Body_Stream) return Http_Client.Errors.Result_Status;
function Read_Some
  (B      : in out Body_Stream;
   Buffer : out Ada.Streams.Stream_Element_Array;
   Last   : out Ada.Streams.Stream_Element_Offset)
   return Http_Client.Errors.Result_Status;
```



## Phase 8 timeout and cancellation

See `docs/GIT_SMART_HTTP_PHASE8_TIMEOUT_CANCELLATION_PASS.md` for the cancellation token API, `Cancelled` status, timeout semantics, and connection-discard rules. Timeout values of `0` remain disabled/no timeout. Cancellation is cooperative and checked at documented execution and streaming checkpoints; affected connections are discarded and cancellation is not retried.


## Phase 10 HTTP/2 trailers

HTTP/2 trailers are supported as trailing HEADERS. They are not HTTP/1.1 chunk trailers, they do not use `Transfer-Encoding: chunked`, and HTTP/2 request trailers do not require the HTTP/1.1 `Trailer` declaration field. Pseudo-headers and conservative framing/sensitive trailer names are rejected. Response body streaming returns only DATA bytes; trailer metadata is tracked separately by the HTTP/2 connection model and is never emitted by `Read_Some`. Trailer handling is per-stream under multiplexing. Timeout, cancellation, pooling, and decompression policies continue to treat trailers as metadata rather than body bytes. HTTP/1.1 trailer behavior remains unchanged, and HTTP/3 trailers remain outside this phase.

## Phase 11 HTTP/3 boundary inventory addendum

The HTTP/3 public surface is experimental/backend-dependent. `Http_Client.HTTP3.HTTP3_Options`, `Http_Client.QUIC.QUIC_Options`, `Http_Client.HTTP3.Execution.Execute_Buffered`, `Http_Client.HTTP3.Execution.Buffered_Backend_Callback`, `Http_Client.HTTP3.Body_Streams.Append_Data`, and `Http_Client.HTTP3.Body_Streams.Read_Some` are compile-visible boundary APIs. In the current tree no built-in production QUIC backend is linked; callers may supply a buffered backend callback. Without one, `Force_HTTP_3` and `Streaming_Force_HTTP_3` fail deterministically and do not fall back. `Prefer_HTTP_3` and `Streaming_Prefer_HTTP_3` may fall back only before request bytes are sent and must preserve configured proxy/TLS/security options. `HTTP3_Proxy_Unsupported`, `HTTP3_Fallback_Disallowed`, and `QUIC_Unsupported` are public deterministic statuses for this boundary.


## Phase 14 example-backed API shapes

The public API inventory is backed by compile-targeted examples in `examples/src`: streaming GET
through `Http_Client.Response_Streams.Open` and byte-array `Read_Some`, buffered byte-array request
bodies through `Http_Client.Request_Bodies.From_Bytes`, fixed and unknown-length producer bodies
through `From_Fixed_Length_Stream` and `From_Unknown_Length_Stream`, request trailers through
`From_Unknown_Length_Stream_With_Trailers`, TLS custom CA through `Streaming_Options.TLS.CA_File`,
HTTP and SOCKS proxies through `Streaming_Options.Proxy`, explicit decompression through
`Streaming_Options.Enable_Decompression`, HTTP/2 and HTTP/3 policy through streaming protocol
options, and redirect/retry policy through `Http_Client.Clients` and `Http_Client.Retry`.


## Non-Git-facing public units classified for completeness

The Git smart HTTP integration surface is intentionally narrower than the full crate. The following compile-visible public units exist in `src/` but are not required for a minimal Git transport adapter. They are still release-surface units and are classified here so the public inventory is not silent about them:

- `Http_Client.Alt_Svc`, `Http_Client.DNS_SVCB`, `Http_Client.HTTPS_Records`, `Http_Client.Protocol_Discovery`, and `Http_Client.Proxy_Discovery` — explicit discovery and proxy-helper surfaces. Git consumers should keep discovery disabled unless they deliberately validate it with their proxy policy.
- `Http_Client.Async` — bounded task integration for buffered requests; streaming Git transports may remain synchronous.
- `Http_Client.Auth`, `Http_Client.Auth.Bearer`, `Http_Client.Auth.Digest`, and `Http_Client.Auth.Scopes` — generic authentication helpers; callers remain responsible for origin/proxy credential scope.
- `Http_Client.Cancellation` — cooperative cancellation token surface used by long-running buffered or streaming operations.
- `Http_Client.Crypto` and `Http_Client.TLS` — implementation-boundary packages for crypto/TLS support; applications should configure TLS through stable client and certificate options.
- `Http_Client.HTTP1.Reader` and `Http_Client.HTTP1` — low-level HTTP/1.1 framing helpers below the high-level client.
- `Http_Client.HTTP2.Body_Streams`, `Http_Client.HTTP2.HPACK`, `Http_Client.HTTP2.Mapping`, `Http_Client.HTTP2.Settings`, `Http_Client.HTTP2.Single_Stream`, `Http_Client.HTTP2.Streams`, and `Http_Client.HTTP2.Uploads` — low-level HTTP/2 helper units; Git consumers normally select HTTP/2 through client execution or streaming options.
- `Http_Client.HTTP3.Frames`, `Http_Client.HTTP3.Mapping`, `Http_Client.HTTP3.QPACK`, `Http_Client.HTTP3.Settings`, `Http_Client.HTTP3.Streams`, and `Http_Client.HTTP3.Body_Streams` — experimental HTTP/3 helper units; no production HTTP/3 execution is implied without a configured backend.
- `Http_Client.Multipart` — multipart body construction; not part of Git smart HTTP packet/packfile transport.
- `Http_Client.Proxies.SOCKS` and `Http_Client.Transports.SOCKS` — SOCKS helper/transport units below the high-level proxy configuration.
- `Http_Client.Resources` — observational counters for diagnostics/tests/benchmarks; not protocol-control state.
- `Http_Client.Zlib_Decompression` — adapter boundary around the external Ada `zlib` dependency. Git callers should configure decompression through `Http_Client.Decompression` or client options; adapter internals are not the Git-facing API.

For package-by-package compatibility class, see `PUBLIC_PACKAGES.md` and `RELEASE_SURFACE_MANIFEST.md`.


Additional high-level convenience API before 1.0:

```ada
function Response_Text (Result : Client_Result) return String;
function Final_URL (Result : Client_Result) return String;
function Get
  (URL           : String;
   Result        : out Client_Result;
   Configuration : Client_Configuration := Default_Client_Configuration)
   return Http_Client.Errors.Result_Status;
```
