# Downloading responses to files

`Http_Client.Clients.Download_To_File` and `Http_Client.Clients.Execute_To_File` are convenience APIs for callers that want to fetch an HTTP response body into a local file without holding the complete body in memory.

The APIs use the existing streaming execution path internally. They open a `Http_Client.Response_Streams.Streaming_Response`, copy fixed-size chunks to disk, and return response metadata with an empty body. They do not call buffered `Get` or `Execute` and therefore are not capped by the buffered `Execution_Options.Max_Body_Size` setting.

The returned metadata is an ordinary `Http_Client.Responses.Response`, so callers can use response metadata convenience accessors such as `Has_Content_Type`, `Content_Type`, `Media_Type`, and `Charset` after the file transfer completes. These values remain server-declared header metadata only; the download API does not sniff file bytes or infer MIME types from the target path.

## API shape

```ada
type Download_File_Mode is
  (Create_New,
   Overwrite,
   Replace_Atomically);

type Download_Progress_Callback is access function
  (Bytes_Written : Natural;
   Total_Bytes   : Natural) return Http_Client.Errors.Result_Status;

type Download_Options is record
   Follow_Redirects      : Boolean := True;
   Max_Redirects         : Natural := 10;
   Max_Download_Size     : Natural := Default_Max_Download_Size;
   Require_Success_Status : Boolean := False;
   File_Mode             : Download_File_Mode := Replace_Atomically;
   Durability            : File_Durability_Mode := File_Durability_Default;
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
```

`Default_Max_Download_Size` is a separate high cap for file downloads, currently 1 GiB. `Max_Download_Size = 0` means the download API imposes no total byte cap. The limit is enforced against bytes written by the streaming API. If `Expected_Size` or `Content-Length` is available and exceeds the configured limit, the API fails before creating or installing the final file; otherwise it enforces the limit while streaming and never writes bytes beyond the configured limit. A malformed `Content-Length` is rejected as `Invalid_Header` rather than treated as an unknown size.

## Buffered, streaming, and file downloads

Use buffered `Get` or `Execute` when the complete response body should be available in memory and bounded by `Max_Body_Size` / `Max_Response_Size`.

Use `Execute_Stream` or `Http_Client.Response_Streams.Open` when the caller wants direct ownership of the response stream and its lifetime.

Use `Download_To_File` or `Execute_To_File` when the intended destination is a file. This avoids response-size-proportional memory allocation while retaining the same TLS, proxy, redirect, retry-before-headers, HTTP/1.1, and HTTP/2 transport behavior as the existing client execution path.

## File safety

`Create_New` refuses to overwrite an existing target. `Overwrite` writes directly to the requested target. `Replace_Atomically` writes to a sibling temporary file and installs the final target only after the response stream reaches end-of-body and the output file closes successfully.

`Durability` controls local filesystem sync behavior. The default closes files normally. `File_Durability_Flush_Temp_File` flushes text helper streams before close. `File_Durability_Sync_Data_And_Directory` fsyncs the completed temporary or direct target file before accepting it; with atomic replacement it also best-effort fsyncs the parent directory after rename where the platform supports directory sync. A file fsync failure returns `Write_Failed`; directory fsync failures are ignored because support is platform and filesystem dependent.

The target path is preflighted before network I/O for local errors that do not mutate the filesystem, such as an empty path or `Create_New` colliding with an existing file. Directory creation and temporary-file selection are delayed until after the response stream has opened and pre-write response checks have passed, so connection failures and rejected response metadata do not create parent directories or temporary files. On failure after writing starts, partial files or temporary files are removed by default. Set `Preserve_Partial_File` when the caller deliberately wants to inspect a partial download after a failure.


## Integrity checks

Set `Expected_Size` to require an exact final file size. Zero disables the size check. For resumed downloads, the expected size is the final size on disk, including bytes that existed before the ranged request. If `Expected_Size` is larger than a nonzero `Max_Download_Size`, the download fails before network I/O. If response metadata makes the final size known through `Content-Length` or resumed `Content-Range` and it disagrees with `Expected_Size`, the download fails before creating or writing the target file, or before appending to an existing partial file.

Set `Verify_SHA256` and `Expected_SHA256_Hex` to verify the completed file before it is accepted. SHA-256 verification reads the completed temporary or target file in bounded chunks through the OpenSSL-backed crypto bridge; it does not buffer the whole file in memory. Uppercase and lowercase hexadecimal digests are accepted. A malformed expected digest returns `Invalid_Configuration` before network I/O. A size or digest mismatch returns `Integrity_Check_Failed`. With `Replace_Atomically`, a failed integrity check prevents installation of the final target.

## Progress callbacks

Set `Progress_Callback` to observe bytes as they are written to disk. The callback receives `Bytes_Written`, including existing bytes for a resumed download, and `Total_Bytes` when the final size is known from `Content-Length`, resume state, or `Expected_Size`. `Total_Bytes = 0` means the final size is unknown or zero. Return `Ok` to continue; return any other status, such as `Cancelled`, to abort the transfer. Callback exceptions are converted to `Internal_Error` and partial-file cleanup follows `Preserve_Partial_File`. Set `Progress_Interval_Bytes` to reduce callback frequency for large downloads; zero reports after every write, while a positive value reports only after at least that many additional bytes and still emits a final callback if the last chunk did not meet the interval. Successful zero-byte downloads emit one final callback with `Bytes_Written = 0`.

## Cancellation

Set `Cancellation` to a `Http_Client.Cancellation.Cancellation_Token_Access` to cooperatively cancel a file download without routing control through the progress callback. A token already cancelled before the call returns `Cancelled` before creating the target file. Cancellation observed while streaming closes the response stream, discards the affected connection through the underlying streaming path, and applies the normal partial-file cleanup policy.

## Resume

Set `Require_Success_Status` to reject final non-2xx HTTP responses before any body bytes are written; the result still contains response metadata such as `HTTP_Status_Code` for logging. Set `Enable_Resume` with `File_Mode => Overwrite` to allow a bodyless GET download to continue an existing non-empty target file. The client sends `Range: bytes=<existing-size>-` and appends only when the server returns `206 Partial Content` with a valid `Content-Range` starting at the existing file size. Set `Resume_If_Range` to send an `If-Range` validator, usually a strong ETag or Last-Modified HTTP-date, so the server only returns a partial response when the remote entity still matches the caller's known validator. If the server ignores the range and returns `200 OK`, the client falls back to a normal full overwrite. A `416 Range Not Satisfiable` response is accepted only when `Content-Range: bytes */N` exactly matches the existing local file size; that represents an already-complete local file. Other status codes from a ranged attempt are reported as `Protocol_Error` without replacing the partial file.

When `Expected_Size` is set and the existing local file already has exactly that size, resume returns success after local integrity checks without opening the network. If the existing file is larger than `Expected_Size`, resume returns `Integrity_Check_Failed` before opening the network and leaves the file unchanged. `Max_Download_Size` remains a total final-file cap for resumed downloads: existing bytes plus appended bytes must fit inside the configured limit. If existing bytes already exceed a nonzero `Max_Download_Size`, resume returns `Response_Too_Large` before opening the network. Local resume files larger than the API's `Natural` size fields can represent also fail as `Response_Too_Large` instead of being ignored and overwritten. `Expected_Final_Size` is populated from `Content-Range` when a resumed `206 Partial Content` response declares the complete object size, even if `Content-Length` is absent. That declared size is also used for the early max-size check before appending. When both headers are present, the byte count implied by `Content-Range` must match `Content-Length`; inconsistent metadata returns `Protocol_Error` before appending. Pair `Enable_Resume` with `Preserve_Partial_File` when callers want interrupted transfers to leave retryable partial files behind.

## Redirects and retries

`Download_Options.Follow_Redirects` and `Max_Redirects` control redirect behavior for the download call. Redirects use the existing client redirect safety rules, including HTTPS downgrade blocking and cross-origin credential stripping. Intermediate redirect bodies are closed and are not written to the target file.

Streaming retries remain limited to failures before response headers are returned. Once a response stream has been returned and body bytes are being written to disk, mid-body failures are reported to the caller. A later call with `Enable_Resume` may continue a preserved partial target when the server supports byte ranges. Segmented downloads are outside this API.

## Example

See `examples/src/download_to_file.adb` for a compile-checked convenience example that sets `Max_Download_Size`, uses `Replace_Atomically`, and reports `Bytes_Written` from `Download_Result`. `HTTP_Status_Code` reports the final HTTP response status when a response was received, or zero when the call completed from local resume state without a response. `Redirect_Count` reports the number of followed redirects, `Retry_Attempt_Count` reports the number of stream-open attempts used for the final response, and `Expected_Final_Size` reports the final size implied by `Content-Length` plus any resume offset, by resumed `Content-Range`, or by `Expected_Size`, when known. For resumed downloads, `Resumed` and `Resume_Offset` report whether the server accepted the range request or the local resume state was accepted; `Bytes_Written` is the number of bytes appended by the current call, while `Final_Size` is the final file size on disk.
